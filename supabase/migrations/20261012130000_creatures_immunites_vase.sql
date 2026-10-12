-- Type « vase » : immunités d'office, appliquées aux créatures déjà enregistrées (ajout seulement).
-- Dégâts : poison, psychique. États : Critiques, Maladresses, Tenailles, Attaques Sournoises, Effets et sorts mentaux,
-- Ciblage corporel, Paralysé, Agrippé, Entravé, Pétrifié, Métamorphose, Étourdi, Assourdi, Aveuglé, Endormi,
-- Inconscient, et Empoisonné (immunité au poison).

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{"poison","psychique"}'::text[]) x where x <> all(immunites_degats)),
    immunites_etats = immunites_etats
      || array(select x from unnest('{"Critiques","Maladresses","Tenailles","Attaques Sournoises","Effets et sorts mentaux","Ciblage corporel","Paralysé","Agrippé","Entravé","Pétrifié","Métamorphose","Étourdi","Assourdi","Aveuglé","Endormi","Inconscient","Empoisonné"}'::text[]) x
               where x <> all(immunites_etats))
where lower(type) like 'vase%';
