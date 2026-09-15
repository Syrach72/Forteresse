-- Portee des armes : texte libre (ex. "30/90c" pour l'arc long dans
-- src/characters.js, courte/longue portee exprimee en cases), pas une
-- paire de bornes numeriques fixes -> pas de contrainte check ici, la
-- meme colonne couvre un arc a une valeur comme une arme de corps a
-- corps qui la laisse vide (sans portee a distance).

alter table objet_catalogue
  add column portee text;
