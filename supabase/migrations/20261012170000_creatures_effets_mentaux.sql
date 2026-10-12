-- Règle : l'immunité aux effets et sorts mentaux entraîne l'immunité à Charmé, Confus, Désorienté, Effrayé, Fasciné,
-- Possédé. Appliquée aux créatures déjà enregistrées (ajout seulement).

update public.creature
set immunites_etats = immunites_etats
      || array(select x from unnest('{"Charmé","Confus","Désorienté","Effrayé","Fasciné","Possédé"}'::text[]) x
               where x <> all(immunites_etats))
where 'Effets et sorts mentaux' = any(immunites_etats);
