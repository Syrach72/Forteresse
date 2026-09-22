-- Un exemplaire serti (gemmes non vide) ne doit jamais s'empiler avec un
-- autre, meme identique (memes gemmes) : chaque sertissage cree sa propre
-- ligne d'arsenal, toujours quantite 1 (regle de Bruno, pour laisser
-- l'affichage des gemmes sans nombre a cote). Seuls les objets nus (gemmes
-- null) continuent de s'additionner dans la meme ligne, comme avant.
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
