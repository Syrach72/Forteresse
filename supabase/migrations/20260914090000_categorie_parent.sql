-- Bruno veut des sous-catégories (ex. Armure légère/intermédiaire/lourde,
-- Bouclier sous Armures) : categorie devient auto-référencée via
-- parent_id, plutôt qu'une seconde table. Une catégorie racine a
-- parent_id nul. La limite à deux niveaux (pas de sous-sous-catégorie)
-- est appliquée côté interface (Admin.jsx), pas en contrainte SQL : une
-- contrainte CHECK ne peut pas interroger d'autres lignes de la même
-- table en PostgreSQL.

alter table categorie add column parent_id uuid references categorie (id);

insert into categorie (nom, parent_id)
select n.nom, c.id
from categorie c
cross join (values ('Armure légère'), ('Armure intermédiaire'), ('Armure lourde'), ('Bouclier')) as n(nom)
where c.nom = 'Armures'
on conflict (nom) do nothing;
