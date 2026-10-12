-- Créature artificielle : les « dégâts mystiques » englobent nécrotique, radiant et psychique (ajout seulement).

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{"nécrotique","radiant","psychique"}'::text[]) x where x <> all(immunites_degats))
where lower(type) like 'créature artificielle%';
