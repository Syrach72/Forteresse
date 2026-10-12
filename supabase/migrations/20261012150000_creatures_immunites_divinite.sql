-- Type « divinité » : immunités d'office, appliquées aux créatures déjà enregistrées (ajout seulement).
-- États : Critiques, Maladresses, Charmé, Empoisonné, Étourdi, Incapable d'agir, Inconscient, Paralysé, Pétrifié, Banni.

update public.creature
set immunites_etats = immunites_etats
      || array(select x from unnest('{"Critiques","Maladresses","Charmé","Empoisonné","Étourdi","Incapable d''agir","Inconscient","Paralysé","Pétrifié","Banni"}'::text[]) x
               where x <> all(immunites_etats))
where lower(type) like 'divinité%';
