-- Armes et armures ne s'empilent jamais (règle de Bruno, 2026-09-28), que ce soit à l'Arsenal ou
-- dans un sac à dos : chaque exemplaire garde sa propre ligne d'inventaire, comme c'était déjà le
-- cas pour les objets sertis (gemmes). La colonne `empilable` du catalogue existait déjà mais
-- n'était lue nulle part : _arsenal_ajouter et _sac_dos_ajouter ne faisaient que la recopier sans
-- jamais la consulter. On étend la même condition qui gérait déjà les objets sertis.

update objet_catalogue set empilable = false
  where _racine_categorie(categorie_id) in ('Armes', 'Armures');

create or replace function _arsenal_ajouter(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_empilable boolean;
begin
  select empilable into v_empilable from objet_catalogue where id = p_objet;
  if v_gemmes is not null or coalesce(v_empilable, true) = false then
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

create or replace function _sac_dos_ajouter(p_sac uuid, p_objet uuid, p_quantite integer, p_gemmes uuid[], p_action text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_empilable boolean;
  v_ligne uuid;
  v_actuel integer;
  v_compte integer;
begin
  select empilable into v_empilable from objet_catalogue where id = p_objet;
  if v_gemmes is null and coalesce(v_empilable, true) then
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
    if v_compte >= 9 then
      raise exception 'Le sac à dos est plein : libérez d''abord un emplacement avant de %.', p_action;
    end if;
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (p_sac, p_objet, p_quantite, v_gemmes);
  end if;
end;
$$;
