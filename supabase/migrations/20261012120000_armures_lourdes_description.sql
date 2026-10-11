-- Armures lourdes (Bruno, 2026-10-12) : la mention de réservation, lue à l'ouverture de la fiche du catalogue,
-- reprend la règle appliquée par le serveur (20261012110000) : Guerrier / Paladin / Prêtres des domaines de la
-- Guerre et de la Forge. Seules les armures de la catégorie « Armure lourde » sont touchées ; le reste du
-- descriptif (« Puissance mini : 8 », « Uniquement sur mesure »…) est conservé.
with recursive lourdes as (
  select id from categorie where lower(btrim(nom)) = 'armure lourde'
  union all
  select c.id from categorie c join lourdes l on c.parent_id = l.id
)
update objet_catalogue
  set description = regexp_replace(
        description, 'Réservée Guerrier / Paladin\.?',
        'Réservée Guerrier / Paladin / Prêtres des domaines de la Guerre et de la Forge.')
  where categorie_id in (select id from lourdes)
    and description like '%Réservée Guerrier / Paladin%'
    and description not like '%Prêtres des domaines%';

-- « Interdite Mage & Druide. » ne décrivait plus la règle des armures lourdes : remplacé par la mention commune.
with recursive lourdes as (
  select id from categorie where lower(btrim(nom)) = 'armure lourde'
  union all
  select c.id from categorie c join lourdes l on c.parent_id = l.id
)
update objet_catalogue
  set description = regexp_replace(
        description, 'Interdite Mage & Druide\.?',
        'Réservée Guerrier / Paladin / Prêtres des domaines de la Guerre et de la Forge.')
  where categorie_id in (select id from lourdes)
    and description like '%Interdite Mage & Druide%';
