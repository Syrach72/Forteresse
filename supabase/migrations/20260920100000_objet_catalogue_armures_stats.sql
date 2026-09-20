-- Fiche admin des Armures (boucliers exclus) : a la place de la portee, deux
-- cellules courtes, vides par defaut.
--   protection : texte libre de 5 caracteres maximum (ex. "4/3/2")
--   type_armure : une seule lettre majuscule (ex. "M")
-- Colonnes nullables : elles ne concernent que les armures, les autres
-- objets les laissent vides. Meme principe que la portee des armes
-- (20260915110000_objet_catalogue_portee.sql).

alter table objet_catalogue
  add column protection text
    check (char_length(protection) <= 5),
  add column type_armure text
    check (type_armure ~ '^[A-Z]$');
