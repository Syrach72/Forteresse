-- Sous-type « intangible » : immunités ajoutées aux créatures déjà enregistrées (ajout seulement).
-- Dégâts : acide, poison, armes non magiques. États : À Terre, Épuisé, Inconscient, Putréfié, Agrippé, Immobilisé,
-- Pétrifié, Paralysé, Entravé, Saignement, Maladie, Tenailles, Attaques Sournoises, Empoisonné (via poison).

update public.creature
set immunites_degats = immunites_degats
      || array(select x from unnest('{"acide","poison","contondant, perforant et tranchant des armes non magiques"}'::text[]) x
               where x <> all(immunites_degats)),
    immunites_etats = immunites_etats
      || array(select x from unnest('{"À Terre","Épuisé","Inconscient","Putréfié","Agrippé","Immobilisé","Pétrifié","Paralysé","Entravé","Saignement","Maladie","Tenailles","Attaques Sournoises","Empoisonné"}'::text[]) x
               where x <> all(immunites_etats))
where lower(sous_type) like '%intangible%';
