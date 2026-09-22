-- Correctif : un tableau de gemmes vide ('{}') envoyé par le client pour une
-- arme nue ne correspondait pas aux lignes existantes, dont la colonne
-- gemmes vaut NULL (jamais renseignee avant le sertissage). "IS NOT DISTINCT
-- FROM" distingue NULL de '{}', d'ou l'echec "Cette arme n'est plus
-- disponible dans l'arsenal." des le premier essai. On normalise '{}' en
-- NULL des l'entree des trois fonctions partagees.
create or replace function _arsenal_quantite(p_objet uuid, p_gemmes uuid[] default null)
returns integer
language sql
security definer set search_path = public
as $$
  select coalesce(sum(quantite), 0)::integer
  from ligne_inventaire
  where inventaire_id = _arsenal_id() and objet_id = p_objet
    and gemmes is not distinct from nullif(p_gemmes, '{}'::uuid[]);
$$;

create or replace function _arsenal_ajouter(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
begin
  update ligne_inventaire
    set quantite = quantite + p_quantite, updated_at = now()
    where id = (
      select id from ligne_inventaire
      where inventaire_id = _arsenal_id() and objet_id = p_objet and gemmes is not distinct from v_gemmes
      order by created_at, id limit 1);
  if not found then
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (_arsenal_id(), p_objet, p_quantite, v_gemmes);
  end if;
end;
$$;

create or replace function _arsenal_retirer(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  l record;
  v_reste integer := p_quantite;
  v_pris integer;
begin
  if _arsenal_quantite(p_objet, v_gemmes) < p_quantite then
    raise exception 'Quantité insuffisante dans l''arsenal.';
  end if;
  for l in
    select id, quantite from ligne_inventaire
    where inventaire_id = _arsenal_id() and objet_id = p_objet and gemmes is not distinct from v_gemmes and quantite > 0
    order by created_at, id
    for update
  loop
    exit when v_reste <= 0;
    v_pris := least(l.quantite, v_reste);
    if v_pris = l.quantite then
      delete from ligne_inventaire where id = l.id;
    else
      update ligne_inventaire
        set quantite = quantite - v_pris, updated_at = now()
        where id = l.id;
    end if;
    v_reste := v_reste - v_pris;
  end loop;
end;
$$;
