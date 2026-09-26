-- Facteur de puissance (FP) d'une quête (Bruno, 2026-09-26) : un nombre saisi par le MJ dans
-- l'administration, affiché sur la tuile en haut à droite de la fiche de quête (à la place de
-- la vétérance moyenne requise). Il sert à une jauge de difficulté purement informative :
-- ratio = (somme des vétérances des mercenaires engagés ÷ 4) ÷ FP ; le ratio optimal est 1.
-- Au départ, le FP reprend la vétérance requise déjà saisie (minimum 1). La colonne
-- `veterance_requise` reste en base, inchangée.
alter table quete add column facteur_puissance integer not null default 1 check (facteur_puissance >= 1);
update quete set facteur_puissance = greatest(1, veterance_requise);
