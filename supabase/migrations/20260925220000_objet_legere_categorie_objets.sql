-- Objets : cellule « Légère » (oui/non, non par défaut) sur les armes, et sous-catégorie
-- « Objets » sous Armures (comme « Armes > Objets ») pour le « Catalogue des objets » des pages
-- Forge et Armurerie.
--
-- Les fonctions de copie entre base et sessions (_cloner_contenu, _env_objet, cf.
-- 20260925200000 et 20260925210000) doivent copier aussi la nouvelle colonne : on les
-- corrige à partir de leur définition actuelle en base (le remplacement est vérifié).

alter table objet_catalogue add column legere boolean not null default false;

do $$
declare
  d text;
begin
  select pg_get_functiondef('_cloner_contenu(uuid, uuid)'::regprocedure) into d;
  if position('emploi_outil_id, emploi_entretien, deux_mains, session_id)' in d) = 0
     or position('mo.new, o.emploi_entretien, o.deux_mains, p_dst' in d) = 0 then
    raise exception '_cloner_contenu : définition inattendue';
  end if;
  d := replace(d, 'emploi_outil_id, emploi_entretien, deux_mains, session_id)',
                  'emploi_outil_id, emploi_entretien, deux_mains, legere, session_id)');
  d := replace(d, 'mo.new, o.emploi_entretien, o.deux_mains, p_dst',
                  'mo.new, o.emploi_entretien, o.deux_mains, o.legere, p_dst');
  execute d;

  select pg_get_functiondef('_env_objet(uuid, uuid)'::regprocedure) into d;
  if position('emploi_entretien, deux_mains, session_id)' in d) = 0
     or position('o.emploi_entretien, o.deux_mains, p_session)' in d) = 0 then
    raise exception '_env_objet : définition inattendue';
  end if;
  d := replace(d, 'emploi_entretien, deux_mains, session_id)', 'emploi_entretien, deux_mains, legere, session_id)');
  d := replace(d, 'o.emploi_entretien, o.deux_mains, p_session)', 'o.emploi_entretien, o.deux_mains, o.legere, p_session)');
  execute d;
end;
$$;

-- « Objets » sous Armes et sous Armures : base de départ ET sessions déjà créées (les sessions
-- qui se lanceront plus tard copient la base). Sans doublon si elle existe déjà.
insert into categorie (nom, parent_id, session_id)
  select 'Objets', r.id, r.session_id
  from categorie r
  where r.parent_id is null and lower(btrim(r.nom)) in ('armes', 'armures')
    and not exists (
      select 1 from categorie c
      where c.parent_id = r.id and lower(btrim(c.nom)) = 'objets'
        and c.session_id is not distinct from r.session_id);
