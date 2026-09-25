-- Test : détruire une arme / armure / objet divers rend la moitié (arrondie à l'inférieur) des
-- composants de sa recette ; aucun autre item ne rend rien. À exécuter APRÈS la migration
-- 20260925240000 ; tout est annulé à la fin (le message d'erreur est le compte rendu).
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  s_test uuid;
  rapport text := '';
  r record; i record;
  avant jsonb; apres integer; attendu integer; n integer; g jsonb;
begin
  select id into s_test from session where nom = 'Session test';
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  perform session_choisir(s_test);
  -- une recette par rubrique : Armes, Armures, Objet divers (éligibles) ; Produits Alchimiques, Gemmes (non éligibles)
  for r in
    select distinct on (lower(_racine_categorie(o.categorie_id))) lower(_racine_categorie(o.categorie_id)) racine, o.id objet, o.nom, rec.id recette,
           coalesce(rec.quantite_produite, 1) prod
    from recette rec join objet_catalogue o on o.id = rec.resultat_objet_id
    where coalesce(rec.actif, true) and exists (select 1 from ingredient_recette x where x.recette_id = rec.id)
      and lower(_racine_categorie(o.categorie_id)) in ('armes', 'armures', 'objet divers', 'produits alchimiques', 'gemmes')
    order by lower(_racine_categorie(o.categorie_id)), (select sum(x.quantite_requise) from ingredient_recette x where x.recette_id = rec.id) desc
  loop
    perform _arsenal_ajouter(r.objet, 3);
    avant := '{}'::jsonb;
    for i in select x.objet_id, x.quantite_requise from ingredient_recette x where x.recette_id = r.recette loop
      avant := avant || jsonb_build_object(i.objet_id::text, _arsenal_quantite(i.objet_id));
    end loop;
    g := partie_detruire(r.objet, 2);
    n := 0;
    for i in select x.objet_id, x.quantite_requise from ingredient_recette x where x.recette_id = r.recette loop
      apres := _arsenal_quantite(i.objet_id);
      attendu := (avant ->> i.objet_id::text)::integer
        + case when r.racine in ('armes', 'armures', 'objet divers')
               then floor(floor(i.quantite_requise::numeric / r.prod) / 2)::integer * 2 else 0 end;
      if apres <> attendu then n := n + 1; end if;
    end loop;
    rapport := rapport || case when n = 0 then E'\nOK ' || r.racine || ' (' || r.nom || ') : ' ||
        case when r.racine in ('armes', 'armures', 'objet divers') then 'moitié des composants rendue, arrondie à l''inférieur' else 'rien rendu (item non éligible)' end
        || ' — ' || (g ->> 'message')
      else E'\nKO ' || r.racine || ' (' || r.nom || ') : ' || n || ' composant(s) faux' end;
  end loop;
  -- exemple d'arrondi : 1 composant -> 0 rendu, 3 -> 1
  rapport := rapport || case when floor(1 / 2.0) = 0 and floor(3 / 2.0) = 1 then E'\nOK arrondi à l''inférieur (1 -> 0, 3 -> 1)' else E'\nKO arrondi' end;
  raise exception E'RAPPORT (tout est annulé)%', rapport;
end;
$$;
