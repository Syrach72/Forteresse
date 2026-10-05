-- Récompense « Boost de production » (code boost) : le MJ précise à quel matériau elle s'applique quand il
-- la place dans un emplacement de récompense d'une quête (Bruno, 2026-10-05). Colonne facultative, remplie
-- seulement pour cet objet. L'effet en jeu (production x2 pendant 3 instances) n'est pas encore automatisé.
alter table quete_recompense
  add column materiau text check (materiau is null or materiau in ('bois', 'fer', 'cuir'));
