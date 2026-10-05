-- Sous-classe : 40 caractères au plus (20 auparavant, texte coupé).
alter table mercenaire drop constraint mercenaire_sous_classe_longueur_check;
alter table mercenaire add constraint mercenaire_sous_classe_longueur_check
  check (sous_classe is null or char_length(sous_classe) <= 40);
