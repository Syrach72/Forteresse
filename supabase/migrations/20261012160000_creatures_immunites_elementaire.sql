-- Type « élémentaire » : immunités d'office, appliquées aux créatures déjà enregistrées (ajout seulement).
-- Dégâts : poison, acide. États : Paralysé, Empoisonné, Putréfié, Pétrifié, Saignement, Endormi, Étourdi, Inconscient,
-- Critiques, Maladresses, Tenailles, Attaques Sournoises, Épuisé.

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{"poison","acide"}'::text[]) x where x <> all(immunites_degats)),
    immunites_etats = immunites_etats
      || array(select x from unnest('{"Paralysé","Empoisonné","Putréfié","Pétrifié","Saignement","Endormi","Étourdi","Inconscient","Critiques","Maladresses","Tenailles","Attaques Sournoises","Épuisé"}'::text[]) x
               where x <> all(immunites_etats))
where lower(type) like 'élémentaire%';
