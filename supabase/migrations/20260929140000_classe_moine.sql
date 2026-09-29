-- Nouvelle classe de mercenaire « Moine » (demande de Bruno, 2026-09-29), sélectionnable dans
-- l'administration ; aucun mercenaire n'est modifié.
insert into classe (nom)
select 'Moine' where not exists (select 1 from classe where nom = 'Moine');
