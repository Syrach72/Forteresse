-- Parade des armes et des boucliers (Bruno, 2026-09-26) : niveau en chiffres romains, de I à III.
-- Les boucliers l'utilisaient déjà (colonne `parade`, texte libre de 5 caractères au plus) ; les
-- armes la reçoivent aussi. La base n'accepte plus que I, II ou III (ou vide). Sur la fiche d'un
-- mercenaire, les parades de ses armes et de son bouclier ne se cumulent pas : seule la plus
-- élevée s'affiche.
alter table objet_catalogue add constraint objet_catalogue_parade_niveau_check
  check (parade is null or parade in ('I', 'II', 'III'));
