-- Immunités par type de créature appliquées aux créatures déjà enregistrées (ajout seulement, rien n'est retiré).
-- Mort-vivant : dégâts poison, psychique ; états Mort immédiate, Maladie, Empoisonné, Effets et sorts mentaux,
-- Paralysé, Épuisé, Diminution de caractéristiques, Inconscient, Putréfié, Endormi, Étourdi, Saignement.
-- Plante : dégâts poison, psychique ; états Empoisonné, Endormi, Étourdi, Aveuglé, Assourdi, Effets et sorts mentaux.
-- Règle : immunité aux dégâts de poison => immunité à l'état Empoisonné.

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{poison,psychique}'::text[]) x where x <> all(immunites_degats)),
    immunites_etats = immunites_etats
      || array(select x from unnest('{"Mort immédiate","Maladie","Empoisonné","Effets et sorts mentaux","Paralysé","Épuisé","Diminution de caractéristiques","Inconscient","Putréfié","Endormi","Étourdi","Saignement"}'::text[]) x
               where x <> all(immunites_etats))
where lower(type) like 'mort-vivant%';

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{poison,psychique}'::text[]) x where x <> all(immunites_degats)),
    immunites_etats = immunites_etats
      || array(select x from unnest('{"Empoisonné","Endormi","Étourdi","Aveuglé","Assourdi","Effets et sorts mentaux"}'::text[]) x
               where x <> all(immunites_etats))
where lower(type) like 'plante%';

update public.creature
set immunites_etats = immunites_etats || array['Empoisonné']
where 'poison' = any(immunites_degats) and 'Empoisonné' <> all(immunites_etats);
