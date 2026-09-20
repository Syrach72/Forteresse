-- Malus d'une armure (boucliers exclus) : deux valeurs chiffrees negatives, vides
-- par defaut.
--   malus_discretion : malus de Discretion (ex. -1)
--   malus_vitesse    : malus de Vitesse (ex. -2)
-- Entiers de -99 a 0 (0 = aucun malus), nullables : seules les armures les
-- renseignent. Plus tard, quand un mercenaire equipera une armure, ces malus
-- viendront modifier les valeurs de sa fiche (pas encore implemente : ils ne
-- servent pour l'instant qu'a la fiche de l'objet).

alter table objet_catalogue
  add column malus_discretion integer
    check (malus_discretion between -99 and 0),
  add column malus_vitesse integer
    check (malus_vitesse between -99 and 0);
