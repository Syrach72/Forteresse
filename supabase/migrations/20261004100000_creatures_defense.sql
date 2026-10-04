-- Créatures : Esquive, Parade et Armure (comme le pavé de défense d'un mercenaire), demandés par Bruno
-- (2026-10-04). Texte court libre : l'Esquive est un nombre (« 1 »), la Parade un niveau en chiffres romains
-- (« II »), l'Armure au format Perforant/Tranchant/Contondant (« 2/3/3 »). Null = non renseigné.
alter table creature add column esquive text check (esquive is null or length(esquive) <= 12);
alter table creature add column parade text check (parade is null or length(parade) <= 12);
alter table creature add column armure text check (armure is null or length(armure) <= 12);
