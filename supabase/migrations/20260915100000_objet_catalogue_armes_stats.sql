-- Bruno veut, pour les objets de la rubrique Armes (et ses sous-categories),
-- trois informations supplementaires sur la fiche "Modifier l'objet" de
-- l'admin : la veterance requise (1 a 20), le temps de fabrication exprime
-- en nombre d'instances (1 a 5, meme echelle que "Duree d'instance" dans
-- l'atelier du prototype), et un cout en pieces d'or pour acheter l'objet
-- directement au lieu de le fabriquer (illimite : pas de plafond).
--
-- Colonnes nullables : ces trois champs ne concernent que les armes,
-- les autres categories (Ingredient, Materiau, ...) n'ont pas a les
-- renseigner. Le cout est un champ libre pour l'instant ; Bruno a
-- prevenu qu'il sera indexe plus tard sur une offre de marche (cf.
-- OffreMarche, section 8 CLAUDE.md) plutot que remplace par elle.

alter table objet_catalogue
  add column veterance_requise integer
    check (veterance_requise between 1 and 20),
  add column duree_fabrication_instances integer
    check (duree_fabrication_instances between 1 and 5),
  add column cout_achat_or integer
    check (cout_achat_or >= 0);
