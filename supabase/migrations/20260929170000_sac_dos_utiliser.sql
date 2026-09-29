-- Utiliser un produit alchimique depuis le sac à dos d'un mercenaire (Bruno, 2026-09-29) : « Utiliser »
-- puis « Confirmer » consomme 1 exemplaire ; s'il n'en reste qu'un, la ligne du sac disparaît. Les
-- effets se reportent à la main sur la fiche (aucun automatisme de santé/énergie).
create or replace function sac_dos_utiliser(p_mercenaire uuid, p_objet uuid, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_merc text;
  v_nom text;
  v_racine text;
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
  select nom, _racine_categorie(categorie_id) into v_nom, v_racine
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  if v_racine is distinct from 'Produits Alchimiques' then
    raise exception 'Seuls les produits alchimiques peuvent être utilisés.';
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
  perform _journal('equipement', v_nom || ' utilisé par ' || v_merc || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'quantite', 1));
end;
$$;

grant create on schema public to fortress_fn;
alter function sac_dos_utiliser(uuid, uuid, uuid[]) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function sac_dos_utiliser(uuid, uuid, uuid[]) from public;
grant execute on function sac_dos_utiliser(uuid, uuid, uuid[]) to authenticated;
