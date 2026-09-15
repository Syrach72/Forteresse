-- Decisions de Bruno du 11/09 :
-- 1. Categorie "Potion" renommee en "Produits Alchimiques" (les objets
--    type Kit/grenades/bombes/Poison restent dedans, pas de reclassement).
-- 2. Atelier de magie ajoute a l'enum atelier_recette ; ses formules
--    seront affichees sous le nom "Formule" cote interface (pas de
--    changement de schema necessaire, seulement un libelle d'affichage
--    dans Admin.jsx).
-- 3. Cinq mercenaires supplementaires (liste Bubble) inseres pour la
--    compagnie de Bruno si elle existe deja ; sans effet si aucune
--    compagnie n'existe encore (migration a rejouer sinon).

update objet_catalogue set categorie = 'Produits Alchimiques' where categorie = 'Potion';

alter type atelier_recette add value if not exists 'magie';

insert into mercenaire (compagnie_id, nom)
select c.id, n.nom
from compagnie c
cross join (values ('Xoxl'), ('Tanti'), ('Sosiel Vaenic'), ('Rysak Dartmoor'), ('Panivar Lotheed')) as n(nom)
where c.id = (select id from compagnie order by created_at asc limit 1)
  and not exists (
    select 1 from mercenaire m where m.compagnie_id = c.id and m.nom = n.nom
  );
