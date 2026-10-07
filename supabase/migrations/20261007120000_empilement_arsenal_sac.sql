-- Règle de Bruno (2026-10-07) sur l'empilement :
--  * ARSENAL : tous les objets absolument identiques s'empilent, armes et armures comprises (même objet,
--    sans gemmes). Seuls les exemplaires sertis restent un par ligne (règle du 2026-09-22 : l'affichage
--    des gemmes se fait sans nombre) ;
--  * SAC À DOS : 3 objets identiques par emplacement, sauf armes, armures et boucliers (rubriques
--    « Armes » et « Armures », boucliers compris) : un seul par emplacement.
-- Remplace la règle du 2026-09-28 (armes/armures jamais empilées, nulle part). La colonne `empilable`
-- du catalogue n'est plus lue : on la remet à vrai pour que la fiche admin reste cohérente.

update objet_catalogue set empilable = true
  where _racine_categorie(categorie_id) in ('Armes', 'Armures');

-- Regrouper les lignes d'arsenal déjà éclatées (armes/armures nues identiques) en une seule ligne.
with doublons as (
  select l.inventaire_id, l.objet_id, sum(l.quantite)::integer as total,
         (array_agg(l.id order by l.created_at, l.id))[1] as garde
  from ligne_inventaire l
  join inventaire i on i.id = l.inventaire_id and i.type = 'arsenal'
  where l.gemmes is null and l.quantite > 0
  group by l.inventaire_id, l.objet_id
  having count(*) > 1
),
maj as (
  update ligne_inventaire l set quantite = d.total, updated_at = now()
  from doublons d where l.id = d.garde
  returning l.id
)
delete from ligne_inventaire l
using doublons d
where l.inventaire_id = d.inventaire_id and l.objet_id = d.objet_id
  and l.gemmes is null and l.id <> d.garde
  and l.inventaire_id in (select id from inventaire where type = 'arsenal');

create or replace function _arsenal_ajouter(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
begin
  if v_gemmes is not null then
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (_arsenal_id(), p_objet, p_quantite, v_gemmes);
    return;
  end if;
  update ligne_inventaire
    set quantite = quantite + p_quantite, updated_at = now()
    where id = (
      select id from ligne_inventaire
      where inventaire_id = _arsenal_id() and objet_id = p_objet and gemmes is null
      order by created_at, id limit 1);
  if not found then
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (_arsenal_id(), p_objet, p_quantite, null);
  end if;
end;
$$;

-- Sac à dos : armes, armures et boucliers un par emplacement ; le reste jusqu'à 3.
create or replace function _sac_dos_ajouter(p_sac uuid, p_objet uuid, p_quantite integer, p_gemmes uuid[], p_action text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_seul boolean;
  v_ligne uuid;
  v_actuel integer;
  v_compte integer;
begin
  select coalesce(_racine_categorie(categorie_id) in ('Armes', 'Armures'), false) into v_seul
    from objet_catalogue where id = p_objet;
  if v_gemmes is null and not coalesce(v_seul, false) then
    select id, quantite into v_ligne, v_actuel from ligne_inventaire
      where inventaire_id = p_sac and objet_id = p_objet and gemmes is null and quantite > 0
      order by created_at, id limit 1
      for update;
  end if;
  if v_ligne is not null then
    if v_actuel + p_quantite > 3 then
      raise exception 'Cet emplacement du sac à dos est complet (3 au plus) : libérez d''abord de la place avant de %.', p_action;
    end if;
    update ligne_inventaire set quantite = quantite + p_quantite, updated_at = now() where id = v_ligne;
  else
    select count(*) into v_compte from ligne_inventaire where inventaire_id = p_sac and quantite > 0;
    if v_compte >= _sac_capacite() then
      raise exception 'Le sac à dos est plein : libérez d''abord un emplacement avant de %.', p_action;
    end if;
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (p_sac, p_objet, p_quantite, v_gemmes);
  end if;
end;
$$;

create or replace function sac_dos_envoyer(p_mercenaire uuid, p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_sac uuid;
  v_racine text;
  v_actuel integer;
  v_compte integer;
  v_nom text;
  v_merc text;
  v_mental integer;
  v_portees integer;
  v_seul boolean;
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
begin
  perform _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id) into v_nom, v_racine
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  if v_racine is null or v_racine not in ('Composants', 'Objet divers', 'Armes', 'Armures', 'Produits Alchimiques') then
    raise exception 'Seuls les composants alchimiques, les produits alchimiques, les armes, les armures et les objets divers peuvent rejoindre un sac à dos.';
  end if;
  v_seul := v_racine in ('Armes', 'Armures');
  if v_gemmes is not null and p_quantite <> 1 then
    raise exception 'Une arme sertie s''envoie une par une.';
  end if;
  if _arsenal_quantite(p_objet, v_gemmes) < p_quantite then
    raise exception 'Quantité insuffisante dans l''arsenal.';
  end if;
  -- Gemmes serties : un mercenaire n'en porte pas plus que son niveau de Mental (une arme à 2 gemmes en compte 2).
  if v_gemmes is not null then
    v_mental := _mental(p_mercenaire);
    v_portees := _gemmes_portees(p_mercenaire);
    if v_portees + cardinality(v_gemmes) > v_mental then
      select nom into v_merc from mercenaire where id = p_mercenaire;
      raise exception '% ne peut pas porter plus de gemmes serties que son niveau de Mental : Mental %, % gemme(s) déjà portée(s), % de plus avec cette arme.',
        v_merc, v_mental, v_portees, cardinality(v_gemmes);
    end if;
  end if;
  v_sac := _sac_dos_id(p_mercenaire);
  select count(*) into v_compte from ligne_inventaire where inventaire_id = v_sac and quantite > 0;
  if v_seul or v_gemmes is not null then
    -- Armes, armures, boucliers (et objets sertis) : un exemplaire par emplacement.
    if v_compte + p_quantite > _sac_capacite() then
      raise exception 'Le sac à dos n''a pas assez d''emplacements libres (% requis, % libre(s)) : libérez d''abord de la place avant de transférer l''objet.',
        p_quantite, greatest(_sac_capacite() - v_compte, 0);
    end if;
    for i in 1..p_quantite loop
      insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
        values (v_sac, p_objet, 1, v_gemmes);
    end loop;
  else
    select quantite into v_actuel from ligne_inventaire
      where inventaire_id = v_sac and objet_id = p_objet and gemmes is null and quantite > 0
      order by created_at, id limit 1;
    if v_actuel is not null then
      if v_actuel + p_quantite > 3 then
        raise exception 'Cet emplacement du sac à dos ne peut pas dépasser 3 (encore % disponible(s)) : libérez d''abord de la place avant de transférer l''objet.', 3 - v_actuel;
      end if;
      update ligne_inventaire set quantite = quantite + p_quantite, updated_at = now()
        where id = (
          select id from ligne_inventaire
          where inventaire_id = v_sac and objet_id = p_objet and gemmes is null and quantite > 0
          order by created_at, id limit 1);
    else
      if p_quantite > 3 then
        raise exception 'Un emplacement du sac à dos ne peut pas dépasser 3.';
      end if;
      if v_compte >= _sac_capacite() then
        raise exception 'Le sac à dos est plein : libérez d''abord un emplacement avant de pouvoir transférer l''objet.';
      end if;
      insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
        values (v_sac, p_objet, p_quantite, null);
    end if;
  end if;
  perform _arsenal_retirer(p_objet, p_quantite, v_gemmes);
  perform _journal('sac_envoi', v_nom || ' ×' || p_quantite || ' envoyé au sac à dos.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'quantite', p_quantite, 'gemmes', v_gemmes));
end;
$$;
