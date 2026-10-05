-- Les 12 emplacements d'icônes cliquables d'une créature (table creature_icone) ont été remplacés, le 2026-10-05, par
-- un emplacement d'icône sur chaque capacité / action / réaction (capacite_creature.icone). La table n'est plus lue
-- ni écrite par le site : suppression (Bruno : « table inutile, tu peux nettoyer »).
drop table if exists creature_icone;
