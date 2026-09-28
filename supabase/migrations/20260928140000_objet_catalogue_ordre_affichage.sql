-- Ordre d'affichage manuel du catalogue (demande de Bruno, 2026-09-28) : au
-- Marché, les listes suivent l'ordre naturel de la table, qui ne correspond à
-- rien de voulu. On ajoute une colonne `ordre` (même principe que
-- `budget_poste.ordre`) : 0 par défaut pour tout le catalogue existant (donc
-- aucun changement ailleurs), et des valeurs explicites seulement pour les
-- métiers de Collecte et les Matériaux, dans l'ordre demandé.
-- Le tri (ordre puis nom) est fait côté client dans App.jsx.

alter table objet_catalogue add column if not exists ordre smallint not null default 0;

update objet_catalogue set ordre = 1 where id = '79dbcc99-6575-4b81-864f-0e7d75ba7fd0'; -- Bucheron
update objet_catalogue set ordre = 2 where id = '7f83a81a-95d8-4bff-88c0-3067c3bde1a4'; -- Scierie
update objet_catalogue set ordre = 3 where id = '01ee1d40-839b-4d9f-854c-37792d23d52d'; -- Mineur
update objet_catalogue set ordre = 4 where id = 'ee5d0c5b-c035-4e63-9cae-9e59c7ff0b59'; -- Camp de Mineur
update objet_catalogue set ordre = 5 where id = '7c5b5fb4-ba81-414c-9deb-3cea1d365156'; -- Tanneur
update objet_catalogue set ordre = 6 where id = '2c1e6724-8279-4978-ad88-ee1f726cf0dd'; -- Tannerie

update objet_catalogue set ordre = 1 where id = 'cc90d826-039d-4dd5-bbc3-d5160de3cf05'; -- Bois
update objet_catalogue set ordre = 2 where id = 'c30566e1-64a9-4eab-bd7a-88a0e9fe0fa3'; -- Fer
update objet_catalogue set ordre = 3 where id = '7639252a-4a2d-43ec-933b-44b1056c4a5b'; -- Cuir
