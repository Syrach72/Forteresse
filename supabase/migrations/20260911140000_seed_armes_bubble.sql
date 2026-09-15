-- Armes fournies par Bruno (export de la table "items" de Bubble),
-- ajoutees telles quelles au catalogue. "Epee Longue" est deja presente
-- (code 'epee', ajoutee depuis src/data.js) : non dupliquee ici.
-- Descriptions non fournies dans l'export -> laissees a NULL, a completer
-- par Bruno plutot qu'inventees.

insert into objet_catalogue (code_unique, nom, categorie, empilable, utilisable, actif) values
  ('arc-court', 'Arc Court', 'Arme', true, false, true),
  ('arbalete-legere', 'Arbalète légère', 'Arme', true, false, true),
  ('arc-long', 'Arc Long', 'Arme', true, false, true),
  ('chaine-cloutee', 'Chaîne Cloutée', 'Arme', true, false, true),
  ('baton', 'Bâton', 'Arme', true, false, true),
  ('cimeterre', 'Cimeterre', 'Arme', true, false, true),
  ('couteau-de-lancer', 'Couteau de Lancer', 'Arme', true, false, true),
  ('coutille', 'Coutille', 'Arme', true, false, true),
  ('dague', 'Dague', 'Arme', true, false, true),
  ('epee-batarde', 'Epée Batarde', 'Arme', true, false, true),
  ('epee-courte', 'Epée Courte', 'Arme', true, false, true),
  ('flechette', 'Fléchette', 'Arme', true, false, true),
  ('fleau-a-une-main', 'Fléau à une Main', 'Arme', true, false, true),
  ('javeline', 'Javeline', 'Arme', true, false, true),
  ('hache-de-lancer', 'Hache de Lancer', 'Arme', true, false, true),
  ('glaive', 'Glaive', 'Arme', true, false, true),
  ('massue', 'Massue', 'Arme', true, false, true),
  ('morgenstern', 'Morgenstern', 'Arme', true, false, true),
  ('rapiere', 'Rapière', 'Arme', true, false, true),
  ('sabre', 'Sabre', 'Arme', true, false, true);
