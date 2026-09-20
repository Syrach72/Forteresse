-- Malus d'Esquive des boucliers : entier de -99 a 0 (0 = aucun malus), nullable,
-- vide par defaut. Meme principe que malus_discretion / malus_vitesse
-- (20260920120000_objet_catalogue_armures_malus.sql), qui s'appliquent aussi aux
-- boucliers ; seule l'esquive est propre aux boucliers. Comme les autres malus,
-- il ne sert pour l'instant qu'a la fiche de l'objet (application aux fiches de
-- mercenaires prevue avec la fiche perso).

alter table objet_catalogue
  add column malus_esquive integer
    check (malus_esquive between -99 and 0);
