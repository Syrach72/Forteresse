-- Relie les icones deja uploadees dans le bucket catalogue-icones (depuis
-- D:\Photos\Fortress Bubble, fournies par Bruno) aux objets du catalogue
-- correspondants, par nom. 75 objets sur 89 trouvent une image avec une
-- correspondance de nom fiable ; les 14 restants (voir message a Bruno)
-- n'ont pas de fichier suffisamment univoque et restent sans icone.

update objet_catalogue set icone = 'https://khfqxloykeaqbeedvvft.supabase.co/storage/v1/object/public/catalogue-icones/' || v.file
from (values
  ('epee', 'epee.png'), ('arc-court', 'arc-court.png'), ('arbalete-legere', 'arbalete-legere.png'),
  ('arc-long', 'arc-long.png'), ('chaine-cloutee', 'chaine-cloutee.png'), ('baton', 'baton.png'),
  ('cimeterre', 'cimeterre.png'), ('couteau-de-lancer', 'couteau-de-lancer.png'), ('coutille', 'coutille.png'),
  ('dague', 'dague.png'), ('epee-batarde', 'epee-batarde.png'), ('epee-courte', 'epee-courte.png'),
  ('flechette', 'flechette.png'), ('fleau-a-une-main', 'fleau-a-une-main.png'), ('javeline', 'javeline.png'),
  ('hache-de-lancer', 'hache-de-lancer.png'), ('glaive', 'glaive.png'), ('massue', 'massue.png'),
  ('morgenstern', 'morgenstern.png'), ('rapiere', 'rapiere.png'), ('maille', 'maille.png'),
  ('bombe-fumigene', 'bombe-fumigene.png'),
  ('metal', 'metal.png'), ('cuir', 'cuir.png'), ('bois', 'bois.png'),
  ('mushroom', 'mushroom.png'), ('worm', 'worm.png'), ('scorpion', 'scorpion.png'),
  ('spider', 'spider.png'), ('eye', 'eye.png'), ('wing', 'wing.png'),
  ('root', 'root.png'), ('tentacle', 'tentacle.png'), ('sulfur', 'sulfur.png'),
  ('poussiere-de-fee', 'poussiere-de-fee.png'), ('ichor-fielon', 'ichor-fielon.png'),
  ('argent-alchimique', 'argent-alchimique.png'), ('mercure', 'mercure.png'), ('obsidienne', 'obsidienne.png'),
  ('diamant', 'diamant.png'), ('nacre', 'nacre.png'), ('quartz-enfume', 'quartz-enfume.png'),
  ('chrysocolle', 'chrysocolle.png'), ('fluorite', 'fluorite.png'), ('rubis', 'rubis.png'),
  ('saphir', 'saphir.png'),
  ('acide-nitrique', 'acide-nitrique.png'), ('eau-royale', 'eau-royale.png'), ('gel-sideral', 'gel-sideral.png'),
  ('sang-de-dragon', 'sang-de-dragon.png'),
  ('trousse-de-soins', 'trousse-de-soins.png'), ('heroisme', 'heroisme.png'),
  ('restauration-supreme', 'restauration-supreme.png'), ('restauration', 'restauration.png'),
  ('regeneration', 'regeneration.png'), ('immobilisante', 'immobilisante.png'),
  ('souffle-enflamme', 'souffle-enflamme.png'), ('vol', 'vol.png'), ('vitesse', 'vitesse.png'),
  ('forme-gazeuse', 'forme-gazeuse.png'), ('invisibilite-superieure', 'invisibilite-superieure.png'),
  ('invisibilite', 'invisibilite.png'), ('force-de-geant', 'force-de-geant.png'),
  ('agrandissement', 'agrandissement.png'), ('rapetissement', 'rapetissement.png'),
  ('onguent-de-sommeil', 'onguent-de-sommeil.png'), ('kit-d-alchimiste', 'kit-d-alchimiste.png'),
  ('grenade-a-plomb', 'grenade-a-plomb.png'), ('grenade-energetique', 'grenade-energetique.png'),
  ('feu-gregeois', 'feu-gregeois.png'), ('bombe-lacrymogene', 'bombe-lacrymogene.png'),
  ('antidote-universel', 'antidote-universel.png'), ('acide-generique', 'acide-generique.png'),
  ('poison', 'poison.png'), ('potion-energy', 'potion-energy.png')
) as v(code, file)
where objet_catalogue.code_unique = v.code;
