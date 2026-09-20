-- Armes : deux cellules courtes en plus de la portee (existante, texte libre).
--   allonge      : 8 caracteres maximum
--   type_degats  : type de degats, 8 caracteres maximum
-- Nullables et vides par defaut : seules les armes les renseignent. Format
-- libre tant que Bruno n'a pas fixe la forme definitive de ces valeurs.

alter table objet_catalogue
  add column allonge text
    check (char_length(allonge) <= 8),
  add column type_degats text
    check (char_length(type_degats) <= 8);
