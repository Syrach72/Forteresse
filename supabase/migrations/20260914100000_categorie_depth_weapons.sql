-- Bruno demande un troisième niveau de sous-catégories (Armes courantes
-- / Armes de guerre / Armes de moine / Objets sous Armes, puis un niveau
-- encore en dessous pour Armes courantes et Armes de guerre). La limite
-- "parent doit être une racine" appliquée côté interface (Admin.jsx,
-- migration categorie_parent) n'a plus lieu d'être : parent_id supporte
-- déjà une profondeur arbitraire au niveau SQL, seule l'interface
-- limitait à deux niveaux. Elle est levée dans le même commit qui
-- accompagne cette migration.
--
-- Second changement nécessaire : « Arme à distance » doit exister deux
-- fois (sous Armes courantes ET sous Armes de guerre), avec le même
-- nom. L'unicité du nom était globale (categorie_nom_key) ; elle devient
-- unique par parent seulement.

alter table categorie drop constraint categorie_nom_key;
alter table categorie add constraint categorie_nom_parent_key unique (parent_id, nom);

-- Niveau 2, sous Armes.
insert into categorie (nom, parent_id)
select n.nom, c.id
from categorie c
cross join (values ('Armes courantes'), ('Armes de guerre'), ('Armes de moine'), ('Objets')) as n(nom)
where c.nom = 'Armes' and c.parent_id is null
on conflict (parent_id, nom) do nothing;

-- Niveau 3, sous Armes courantes.
insert into categorie (nom, parent_id)
select n.nom, c.id
from categorie c
cross join (values ('Arme à une main'), ('Arme à deux mains'), ('Arme à distance')) as n(nom)
where c.nom = 'Armes courantes'
on conflict (parent_id, nom) do nothing;

-- Niveau 3, sous Armes de guerre.
insert into categorie (nom, parent_id)
select n.nom, c.id
from categorie c
cross join (
  values ('Arme légère'), ('Arme lourde à une main'), ('Arme lourde à deux mains'), ('Arme à distance')
) as n(nom)
where c.nom = 'Armes de guerre'
on conflict (parent_id, nom) do nothing;
