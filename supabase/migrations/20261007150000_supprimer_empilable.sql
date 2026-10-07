-- La colonne empilable du catalogue n'est plus lue nulle part (regle d'empilement par categorie, Bruno,
-- 2026-10-07) : verifie en production qu'aucune fonction, vue ou dependance ne la reference. Le code ne la
-- demande ni ne l'envoie plus avant cette suppression.
alter table objet_catalogue drop column empilable;
