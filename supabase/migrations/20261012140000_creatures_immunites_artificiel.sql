-- Type « créature artificielle » : immunités d'office, appliquées aux créatures déjà enregistrées (ajout seulement).
-- Dégâts : poison, psychique, non létaux. États : Mort immédiate, Rappel à la vie, Maladie, Effets et sorts mentaux,
-- Épuisé, Diminution de caractéristiques, Saignement, Inconscient, Pétrifié, Putréfié, Endormi, Métamorphose, Étourdi,
-- et Empoisonné (immunité au poison).

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{"poison","psychique","non létaux"}'::text[]) x where x <> all(immunites_degats)),
    immunites_etats = immunites_etats
      || array(select x from unnest('{"Mort immédiate","Rappel à la vie","Maladie","Effets et sorts mentaux","Épuisé","Diminution de caractéristiques","Saignement","Inconscient","Pétrifié","Putréfié","Endormi","Métamorphose","Étourdi","Empoisonné"}'::text[]) x
               where x <> all(immunites_etats))
where lower(type) like 'créature artificielle%';
