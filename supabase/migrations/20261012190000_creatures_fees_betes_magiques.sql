-- Fées et bêtes magiques : immunisées aux effets et sorts mentaux (et aux six états mentaux qui en découlent :
-- Charmé, Confus, Désorienté, Effrayé, Fasciné, Possédé). Ajout seulement.

update public.creature
set immunites_etats = immunites_etats
      || array(select x from unnest('{"Effets et sorts mentaux","Charmé","Confus","Désorienté","Effrayé","Fasciné","Possédé"}'::text[]) x
               where x <> all(immunites_etats))
where lower(type) like 'fée%' or lower(type) like 'bête magique%';
