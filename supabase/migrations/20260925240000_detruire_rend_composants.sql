-- Détruire une arme, une armure ou un objet (rubriques Armes, Armures, Objet divers — aucun autre
-- item) rend automatiquement à l'arsenal la moitié des composants de sa recette, arrondie à
-- l'inférieur. Règle de Bruno, 2026-09-25.
--
-- Calcul : pour chaque exemplaire détruit, floor(quantité requise par exemplaire / 2) de chaque
-- composant (quantité requise par exemplaire = quantité de la recette / quantité produite). Exemple :
-- 3 composants -> 1 rendu ; 1 composant -> 0 rendu. Sans recette, rien n'est rendu. Les gemmes
-- serties dans une arme ne sont pas des composants : elles restent perdues, comme avant.
-- Les destructions ne s'annulent pas (partie_annuler ne les gère pas) : rien d'autre à défaire.

drop function partie_detruire(uuid, integer, uuid[]);
create function partie_detruire(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
  rec recette%rowtype;
  i record;
  v_racine text;
  v_rendu integer;
  v_rendus jsonb := '[]'::jsonb;
  v_message text;
begin
  perform _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  if not found or coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if _arsenal_quantite(p_objet, p_gemmes) < p_quantite then
    raise exception 'Quantité invalide : cet objet n''est pas disponible en telle quantité dans l''arsenal.';
  end if;
  perform _arsenal_retirer(p_objet, p_quantite, p_gemmes);
  v_racine := lower(coalesce(_racine_categorie(o.categorie_id), ''));
  if v_racine in ('armes', 'armures', 'objet divers') then
    select * into rec from recette
      where resultat_objet_id = p_objet and coalesce(actif, true)
      order by code_unique limit 1;
    if found then
      for i in
        select x.objet_id, x.quantite_requise, c.nom
        from ingredient_recette x join objet_catalogue c on c.id = x.objet_id
        where x.recette_id = rec.id
        order by c.nom
      loop
        v_rendu := floor(floor(i.quantite_requise::numeric / greatest(coalesce(rec.quantite_produite, 1), 1)) / 2)::integer * p_quantite;
        if v_rendu > 0 then
          perform _arsenal_ajouter(i.objet_id, v_rendu);
          v_rendus := v_rendus || jsonb_build_object('objet_id', i.objet_id, 'nom', i.nom, 'quantite', v_rendu);
        end if;
      end loop;
    end if;
  end if;
  v_message := 'Destruction de ' || o.nom || ' ×' || p_quantite || '.';
  if jsonb_array_length(v_rendus) > 0 then
    v_message := v_message || ' Composants récupérés : ' || (
      select string_agg(e ->> 'nom' || ' ×' || (e ->> 'quantite'), ', ')
      from jsonb_array_elements(v_rendus) e) || '.';
  end if;
  perform _journal('destruction', v_message, 0,
    jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite, 'gemmes', p_gemmes, 'composants', v_rendus));
  return jsonb_build_object('composants', v_rendus, 'message', v_message);
end;
$$;
revoke all on function partie_detruire(uuid, integer, uuid[]) from public;
grant execute on function partie_detruire(uuid, integer, uuid[]) to authenticated;
-- les fonctions de jeu appartiennent à fortress_fn (RLS par session) ; il faut le droit de création
-- dans le schéma le temps du changement de propriétaire
grant create on schema public to fortress_fn;
alter function partie_detruire(uuid, integer, uuid[]) owner to fortress_fn;
revoke create on schema public from fortress_fn;
