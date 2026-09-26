-- Icônes d'une arme (Bruno, 2026-09-26) : jusqu'à 2 icônes côte à côte, choisies dans le catalogue
-- (rubrique Armes) et affichées sur l'arme portée par un mercenaire. Elles sont liées à l'arme et
-- ne se modifient pas sur la fiche du mercenaire. La première, si elle n'est pas renseignée,
-- retombe sur l'icône de Puissance (côté interface) ; la seconde est facultative.
alter table objet_catalogue
  add column arme_icone_1 text,
  add column arme_icone_2 text;
