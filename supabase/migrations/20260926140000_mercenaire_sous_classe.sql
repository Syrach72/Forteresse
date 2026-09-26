-- Sous-classe d'un mercenaire (Bruno, 2026-09-26) : texte libre de 20 caractères au plus,
-- saisi par le MJ dans l'administration ; affiché après la classe sur la fiche
-- (ex. « Guerrier (Protecteur) »). Champ du catalogue, donc commun à toutes les sessions.
alter table mercenaire add column sous_classe text;
alter table mercenaire add constraint mercenaire_sous_classe_longueur_check
  check (sous_classe is null or char_length(sous_classe) <= 20);
