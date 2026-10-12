-- Type « nuée » : immunités et vulnérabilité d'office, appliquées aux créatures déjà enregistrées (ajout seulement).
-- Dégâts : psychique, armes non magiques. Vulnérabilité : dégâts de zone.
-- États : Effets et sorts mentaux, À Terre, Aveuglé, Assourdi, Étourdi, Paralysé, Inconscient, Pétrifié, Agrippé,
-- Entravé, Critiques, Tenailles, Attaques Sournoises, Saignement, Maladresses, Endormi.

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{"psychique","contondant, perforant et tranchant des armes non magiques"}'::text[]) x
               where x <> all(immunites_degats)),
    immunites_etats = immunites_etats
      || array(select x from unnest('{"Effets et sorts mentaux","À Terre","Aveuglé","Assourdi","Étourdi","Paralysé","Inconscient","Pétrifié","Agrippé","Entravé","Critiques","Tenailles","Attaques Sournoises","Saignement","Maladresses","Endormi"}'::text[]) x
               where x <> all(immunites_etats)),
    vulnerabilites = vulnerabilites
      || array(select x from unnest('{"dégâts de zone"}'::text[]) x where x <> all(vulnerabilites))
where lower(type) like 'nuée%';
