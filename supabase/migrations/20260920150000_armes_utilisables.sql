-- Armes : "Utilisable" coche. Depuis le 2026-09-20 la case est cochee par defaut
-- a la creation d'un objet, mais les armes creees avant (103 sur 104) sont
-- restees a "Non". On les passe a "Oui" (toute la rubrique Armes et ses
-- sous-categories). Donnee seule, aucune structure modifiee ; le champ n'est
-- lu que par l'administration.

update objet_catalogue
set utilisable = true
where utilisable = false
  and categorie_id in (
    with recursive arbre as (
      select id from categorie
      where lower(btrim(nom)) = 'armes' and parent_id is null
      union all
      select c.id from categorie c join arbre a on c.parent_id = a.id
    )
    select id from arbre
  );
