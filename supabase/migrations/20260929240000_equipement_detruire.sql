-- Détruire une arme, un bouclier ou une armure équipé (règle de Bruno, 2026-09-29), depuis la fiche du mercenaire :
-- l'objet est détruit immédiatement, retiré du mercenaire, et la moitié des composants de sa recette
-- (arrondie à l'inférieur, comme pour partie_detruire) rejoint l'arsenal. Les gemmes serties sont perdues.
-- Réservé au recruteur du mercenaire (ou au MJ).
create or replace function equipement_detruire(p_mercenaire uuid, p_emplacement text, p_position integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_objet uuid;
  o objet_catalogue%rowtype;
  v_merc text;
  rec recette%rowtype;
  i record;
  v_rendu integer;
  v_rendus jsonb := '[]'::jsonb;
  v_message text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_emplacement not in ('arme', 'bouclier', 'armure') then
    raise exception 'Seules une arme, un bouclier ou une armure équipés peuvent être détruits ici.';
  end if;
  select nom into v_merc from mercenaire where id = p_mercenaire;
  select e.objet_id into v_objet from mercenaire_equipement e
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire
      and e.emplacement = p_emplacement and e.position = p_position
    for update;
  if v_objet is null then
    raise exception 'Rien n''est équipé à cet emplacement.';
  end if;
  select * into o from objet_catalogue where id = v_objet;
  delete from mercenaire_equipement
    where session_id = ctx_session() and mercenaire_id = p_mercenaire
      and emplacement = p_emplacement and position = p_position;
  select * into rec from recette
    where resultat_objet_id = v_objet and coalesce(actif, true)
    order by code_unique limit 1;
  if found then
    for i in
      select x.objet_id, x.quantite_requise, c.nom
      from ingredient_recette x join objet_catalogue c on c.id = x.objet_id
      where x.recette_id = rec.id
      order by c.nom
    loop
      v_rendu := floor(floor(i.quantite_requise::numeric / greatest(coalesce(rec.quantite_produite, 1), 1)) / 2)::integer;
      if v_rendu > 0 then
        perform _arsenal_ajouter(i.objet_id, v_rendu);
        v_rendus := v_rendus || jsonb_build_object('objet_id', i.objet_id, 'nom', i.nom, 'quantite', v_rendu);
      end if;
    end loop;
  end if;
  v_message := o.nom || ' de ' || coalesce(v_merc, 'un mercenaire') || ' est détruit.';
  if jsonb_array_length(v_rendus) > 0 then
    v_message := v_message || ' Composants récupérés : ' || (
      select string_agg(e ->> 'nom' || ' ×' || (e ->> 'quantite'), ', ')
      from jsonb_array_elements(v_rendus) e) || '.';
  end if;
  perform _journal('destruction', v_message, 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', v_objet, 'composants', v_rendus));
  return jsonb_build_object('composants', v_rendus, 'message', v_message);
end;
$$;

grant create on schema public to fortress_fn;
alter function equipement_detruire(uuid, text, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function equipement_detruire(uuid, text, integer) from public;
grant execute on function equipement_detruire(uuid, text, integer) to authenticated;
