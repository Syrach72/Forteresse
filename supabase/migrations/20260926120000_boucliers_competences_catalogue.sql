-- Deux corrections sur l'equipement et les competences (Bruno, 2026-09-26).
--
-- 1. Les competences vivent deja dans le catalogue : objets des rubriques racines
--    « Competences Actives » et « Competences Passives ». Les cellules du tableau d'un
--    mercenaire pointent donc vers ces objets ; la table `competence` creee la veille
--    (jamais remplie) est supprimee.
-- 2. Le bouclier a son propre emplacement, distinct de l'armure. Il reste range sous la
--    rubrique « Armures » du catalogue (categorie « Bouclier ») : c'est la categorie de
--    l'objet ou l'un de ses ancetres nommee « Bouclier… » qui le distingue.

-- ---------------------------------------------------------------------------
-- 1. Competences = objets du catalogue
-- ---------------------------------------------------------------------------
alter table mercenaire_competence drop constraint mercenaire_competence_competence_id_fkey;
alter table mercenaire_competence
  add constraint mercenaire_competence_competence_id_fkey
  foreign key (competence_id) references objet_catalogue (id) on delete cascade;
drop table competence;

-- ---------------------------------------------------------------------------
-- 2. Emplacement « bouclier »
-- ---------------------------------------------------------------------------
create function _est_bouclier(p_categorie uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  with recursive chaine as (
    select id, nom, parent_id from categorie where id = p_categorie
    union all
    select c.id, c.nom, c.parent_id from categorie c join chaine ch on c.id = ch.parent_id
  )
  select exists (select 1 from chaine where lower(btrim(nom)) like 'bouclier%');
$$;

alter table mercenaire_equipement drop constraint mercenaire_equipement_emplacement_check;
alter table mercenaire_equipement
  add constraint mercenaire_equipement_emplacement_check
  check (emplacement in ('arme', 'armure', 'bouclier', 'objet'));
alter table mercenaire_equipement drop constraint mercenaire_equipement_armure_check;
alter table mercenaire_equipement
  add constraint mercenaire_equipement_armure_check
  check (emplacement not in ('armure', 'bouclier') or position = 0);

create or replace function sac_dos_equiper(p_mercenaire uuid, p_objet uuid, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_merc text;
  v_nom text;
  v_racine text;
  v_bouclier boolean;
  v_emp text;
  v_max integer;
  v_pos integer;
  v_sac uuid;
  v_ligne uuid;
  v_qte integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  if v_merc is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id), _est_bouclier(categorie_id)
    into v_nom, v_racine, v_bouclier
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  v_emp := case v_racine
    when 'Armes' then 'arme'
    when 'Armures' then case when v_bouclier then 'bouclier' else 'armure' end
    when 'Objet divers' then 'objet' end;
  if v_emp is null then
    raise exception 'Seuls les armes, les armures, les boucliers et les objets divers peuvent être équipés.';
  end if;
  v_max := case when v_emp in ('armure', 'bouclier') then 0 else 2 end;
  select g.p into v_pos from generate_series(0, v_max) as g(p)
    where not exists (
      select 1 from mercenaire_equipement e
      where e.mercenaire_id = p_mercenaire and e.emplacement = v_emp and e.position = g.p)
    order by g.p limit 1;
  if v_pos is null then
    raise exception '%', case v_emp
      when 'arme' then v_merc || ' porte déjà 3 armes : déséquipez-en une d''abord.'
      when 'armure' then v_merc || ' porte déjà une armure : déséquipez-la d''abord.'
      when 'bouclier' then v_merc || ' porte déjà un bouclier : déséquipez-le d''abord.'
      else v_merc || ' porte déjà 3 objets : déséquipez-en un d''abord.' end;
  end if;
  v_sac := _sac_dos_id(p_mercenaire);
  select id, quantite into v_ligne, v_qte from ligne_inventaire
    where inventaire_id = v_sac and objet_id = p_objet and gemmes is not distinct from v_gemmes and quantite > 0
    order by created_at, id limit 1
    for update;
  if v_ligne is null then
    raise exception 'Cet objet n''est pas dans le sac à dos.';
  end if;
  if v_qte = 1 then
    delete from ligne_inventaire where id = v_ligne;
  else
    update ligne_inventaire set quantite = quantite - 1, updated_at = now() where id = v_ligne;
  end if;
  insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id, gemmes)
    values (p_mercenaire, v_emp, v_pos, p_objet, v_gemmes);
  perform _journal('equipement', v_nom || ' équipé par ' || v_merc || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'emplacement', v_emp, 'position', v_pos));
end;
$$;

grant create on schema public to fortress_fn;
alter function _est_bouclier(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _est_bouclier(uuid) from public;
