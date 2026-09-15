-- Seed de demonstration : catalogue et recettes correspondant exactement
-- au contenu actuel de src/data.js (ITEMS) et src/alchemy.js
-- (INGREDIENTS, ALCHEMY_RECIPES). Aucune donnee inventee : memes
-- identifiants, noms, descriptions et quantites que le prototype local.
--
-- Ne seed PAS Compagnie/Inventaire/LigneInventaire ici : ces lignes
-- appartiennent a une Compagnie liee a un vrai compte (auth.users), qui
-- n'existe pas encore tant qu'aucun compte n'a ete cree via le lien
-- magique. A faire dans une migration separee une fois un premier
-- compte reel disponible.

insert into objet_catalogue (code_unique, nom, description, categorie, empilable, utilisable) values
  ('epee', 'Épée longue', 'Une lame équilibrée, forgée pour durer.', 'Arme', true, false),
  ('maille', 'Cotte de mailles', 'Une maille robuste pour les longues expéditions.', 'Armure', true, false),
  ('potion', 'Potion de soin', 'Restaure un point de vie à votre personnage.', 'Potion', true, true),
  ('potion-energy', 'Potion d''énergie', 'Préparation vivifiante. Effets à définir avec Bruno et à appliquer manuellement.', 'Potion', true, true),
  ('potion-clarity', 'Potion de clairvoyance', 'Préparation des sens. Effets à définir avec Bruno et à appliquer manuellement.', 'Potion', true, true),
  ('metal', 'Métal', null, 'Matériau', true, false),
  ('cuir', 'Cuir', null, 'Matériau', true, false),
  ('bois', 'Bois', null, 'Matériau', true, false),
  ('mushroom', 'Champignon', null, 'Ingrédient', true, false),
  ('worm', 'Ver mystique', null, 'Ingrédient', true, false),
  ('scorpion', 'Scorpion', null, 'Ingrédient', true, false),
  ('spider', 'Araignée', null, 'Ingrédient', true, false),
  ('eye', 'Œil', null, 'Ingrédient', true, false),
  ('slime', 'Gelée verte', null, 'Ingrédient', true, false),
  ('wing', 'Aile de chauve-souris', null, 'Ingrédient', true, false),
  ('root', 'Mandragore', null, 'Ingrédient', true, false),
  ('sun', 'Essence solaire', null, 'Ingrédient', true, false),
  ('claw', 'Griffe', null, 'Ingrédient', true, false),
  ('blood', 'Sang', null, 'Ingrédient', true, false),
  ('tentacle', 'Tentacules', null, 'Ingrédient', true, false),
  ('sulfur', 'Soufre', null, 'Ingrédient', true, false),
  ('salt', 'Sel blanc', null, 'Ingrédient', true, false),
  ('silver', 'Poudre d''argent', null, 'Ingrédient', true, false),
  ('coal', 'Charbon', null, 'Ingrédient', true, false);

-- Recettes forge/armurerie : couts en materiaux tires des champs
-- metal/leather/wood de src/data.js ITEMS.
insert into recette (code_unique, nom, atelier, resultat_objet_id, quantite_produite) values
  ('recette-epee', 'Épée longue', 'forge', (select id from objet_catalogue where code_unique = 'epee'), 1),
  ('recette-maille', 'Cotte de mailles', 'armurerie', (select id from objet_catalogue where code_unique = 'maille'), 1);

insert into ingredient_recette (recette_id, objet_id, quantite_requise) values
  ((select id from recette where code_unique = 'recette-epee'), (select id from objet_catalogue where code_unique = 'metal'), 10),
  ((select id from recette where code_unique = 'recette-epee'), (select id from objet_catalogue where code_unique = 'cuir'), 5),
  ((select id from recette where code_unique = 'recette-epee'), (select id from objet_catalogue where code_unique = 'bois'), 2),
  ((select id from recette where code_unique = 'recette-maille'), (select id from objet_catalogue where code_unique = 'metal'), 30),
  ((select id from recette where code_unique = 'recette-maille'), (select id from objet_catalogue where code_unique = 'cuir'), 8),
  ((select id from recette where code_unique = 'recette-maille'), (select id from objet_catalogue where code_unique = 'bois'), 30);

-- Recettes du laboratoire, cf. ALCHEMY_RECIPES dans src/alchemy.js.
insert into recette (code_unique, nom, atelier, resultat_objet_id, quantite_produite) values
  ('recette-healing', 'Potion de soin', 'alchimie', (select id from objet_catalogue where code_unique = 'potion'), 1),
  ('recette-energy', 'Potion d''énergie', 'alchimie', (select id from objet_catalogue where code_unique = 'potion-energy'), 1),
  ('recette-clarity', 'Potion de clairvoyance', 'alchimie', (select id from objet_catalogue where code_unique = 'potion-clarity'), 1);

insert into ingredient_recette (recette_id, objet_id, quantite_requise) values
  ((select id from recette where code_unique = 'recette-healing'), (select id from objet_catalogue where code_unique = 'mushroom'), 1),
  ((select id from recette where code_unique = 'recette-healing'), (select id from objet_catalogue where code_unique = 'slime'), 1),
  ((select id from recette where code_unique = 'recette-healing'), (select id from objet_catalogue where code_unique = 'salt'), 1),
  ((select id from recette where code_unique = 'recette-energy'), (select id from objet_catalogue where code_unique = 'mushroom'), 1),
  ((select id from recette where code_unique = 'recette-energy'), (select id from objet_catalogue where code_unique = 'root'), 1),
  ((select id from recette where code_unique = 'recette-energy'), (select id from objet_catalogue where code_unique = 'sun'), 1),
  ((select id from recette where code_unique = 'recette-energy'), (select id from objet_catalogue where code_unique = 'sulfur'), 1),
  ((select id from recette where code_unique = 'recette-clarity'), (select id from objet_catalogue where code_unique = 'eye'), 1),
  ((select id from recette where code_unique = 'recette-clarity'), (select id from objet_catalogue where code_unique = 'worm'), 1),
  ((select id from recette where code_unique = 'recette-clarity'), (select id from objet_catalogue where code_unique = 'silver'), 1),
  ((select id from recette where code_unique = 'recette-clarity'), (select id from objet_catalogue where code_unique = 'salt'), 1),
  ((select id from recette where code_unique = 'recette-clarity'), (select id from objet_catalogue where code_unique = 'coal'), 1);
