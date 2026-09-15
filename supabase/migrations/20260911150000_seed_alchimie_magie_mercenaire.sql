-- Contenu fourni par Bruno depuis son app Bubble (captures d'ecran du
-- 11/09/2026) : produits finis d'alchimie, composants de magie, et
-- correction du nom du materiau "metal" -> "Fer" (nom canonique cote
-- Bubble). "Souffre" (liste Composants Mages) non ajoute : doublon
-- probable de "Soufre" deja present. Les 4 objets qui apparaissent a la
-- fois comme produit d'alchimie et comme composant de magie (Acide
-- Nitrique, Eau Royale, Gel Sideral, Sang de Dragon) ne sont inseres
-- qu'une fois ici : le meme objet peut etre resultat d'une recette ET
-- ingredient d'une autre, cf. principe de separation catalogue/recette.

update objet_catalogue set nom = 'Fer' where code_unique = 'metal';

-- Composants de magie (nouveaux, hors doublons avec le catalogue existant)
insert into objet_catalogue (code_unique, nom, categorie, empilable, utilisable, actif) values
  ('poussiere-de-fee', 'Poussière de Fée', 'Ingrédient', true, false, true),
  ('ichor-fielon', 'Ichor Fiélon', 'Ingrédient', true, false, true),
  ('argent-alchimique', 'Argent Alchimique', 'Ingrédient', true, false, true),
  ('mercure', 'Mercure', 'Ingrédient', true, false, true),
  ('obsidienne', 'Obsidienne', 'Ingrédient', true, false, true),
  ('diamant', 'Diamant', 'Ingrédient', true, false, true),
  ('nacre', 'Nacre', 'Ingrédient', true, false, true),
  ('quartz-enfume', 'Quartz Enfumé', 'Ingrédient', true, false, true),
  ('chrysocolle', 'Chrysocolle', 'Ingrédient', true, false, true),
  ('fluorite', 'Fluorite', 'Ingrédient', true, false, true),
  ('rubis', 'Rubis', 'Ingrédient', true, false, true),
  ('saphir', 'Saphir', 'Ingrédient', true, false, true);

-- Produits finis d'alchimie. Categorie 'Potion' par defaut pour tous
-- (hypothese a confirmer : certains, comme les grenades/bombes/kit, sont
-- peut-etre plutot des 'Objet divers' -- voir question posee a Bruno).
insert into objet_catalogue (code_unique, nom, categorie, empilable, utilisable, actif) values
  ('acide-nitrique', 'Acide Nitrique', 'Potion', true, true, true),
  ('eau-royale', 'Eau Royale', 'Potion', true, true, true),
  ('gel-sideral', 'Gel Sidéral', 'Potion', true, true, true),
  ('sang-de-dragon', 'Sang de Dragon', 'Potion', true, true, true),
  ('trousse-de-soins', 'Trousse de Soins', 'Potion', true, true, true),
  ('heroisme', 'Héroïsme', 'Potion', true, true, true),
  ('restauration-supreme', 'Restauration Suprême', 'Potion', true, true, true),
  ('restauration', 'Restauration', 'Potion', true, true, true),
  ('regeneration', 'Régénération', 'Potion', true, true, true),
  ('immobilisante', 'Immobilisante', 'Potion', true, true, true),
  ('souffle-enflamme', 'Souffle Enflammé', 'Potion', true, true, true),
  ('vol', 'Vol', 'Potion', true, true, true),
  ('vitesse', 'Vitesse', 'Potion', true, true, true),
  ('forme-gazeuse', 'Forme Gazeuse', 'Potion', true, true, true),
  ('invisibilite-superieure', 'Invisibilité Supérieure', 'Potion', true, true, true),
  ('invisibilite', 'Invisibilité', 'Potion', true, true, true),
  ('force-de-geant', 'Force de Géant', 'Potion', true, true, true),
  ('agrandissement', 'Agrandissement', 'Potion', true, true, true),
  ('rapetissement', 'Rapetissement', 'Potion', true, true, true),
  ('onguent-de-sommeil', 'Onguent de Sommeil', 'Potion', true, true, true),
  ('kit-d-alchimiste', 'Kit d''Alchimiste', 'Potion', true, true, true),
  ('grenade-a-plomb', 'Grenade à Plomb', 'Potion', true, true, true),
  ('grenade-energetique', 'Grenade Energétique', 'Potion', true, true, true),
  ('feu-gregeois', 'Feu Grégeois', 'Potion', true, true, true),
  ('bombe-lacrymogene', 'Bombe Lacrymogène', 'Potion', true, true, true),
  ('bombe-fumigene', 'Bombe Fumigène', 'Potion', true, true, true),
  ('antidote-universel', 'Antidote Universel', 'Potion', true, true, true),
  ('acide-generique', 'Acide Générique', 'Potion', true, true, true),
  ('poison', 'Poison', 'Potion', true, true, true),
  ('potion-energie-majeure', 'Potion d''Energie Majeure', 'Potion', true, true, true),
  ('potion-energie-mediane', 'Potion d''Energie Médiane', 'Potion', true, true, true),
  ('potion-energie-mineure', 'Potion d''Energie Mineure', 'Potion', true, true, true),
  ('potion-vie-majeure', 'Potion de Vie Majeure', 'Potion', true, true, true),
  ('potion-vie-mediane', 'Potion de Vie Médiane', 'Potion', true, true, true),
  ('potion-vie-mineure', 'Potion de Vie Mineure', 'Potion', true, true, true);

-- Structure prete pour les mercenaires (cf. section 8 CLAUDE.md).
-- Pas de lignes inserees : compagnie_id exige une Compagnie reelle,
-- qui exige elle-meme un compte reel (aucun cree pour l'instant).
create table mercenaire (
  id uuid primary key default gen_random_uuid(),
  compagnie_id uuid not null references compagnie (id) on delete cascade,
  nom text not null,
  portrait text,
  classe text,
  role text,
  veterance integer,
  attaque integer,
  defense integer,
  esprit integer,
  mouvement integer,
  mana integer,
  sante integer,
  notes text,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

alter table mercenaire enable row level security;

create policy "mercenaire: acces reserve aux membres de la compagnie"
  on mercenaire for select
  using (est_membre_compagnie(compagnie_id));
