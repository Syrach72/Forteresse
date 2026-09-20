-- Parade des boucliers : texte court de 5 caracteres maximum (comme la
-- protection des armures, 20260920100000_objet_catalogue_armures_stats.sql),
-- nullable, vide par defaut. Format libre (ex. "2", "+1", "3/2") tant que
-- Bruno n'a pas fixe la forme definitive de cette valeur.

alter table objet_catalogue
  add column parade text
    check (char_length(parade) <= 5);
