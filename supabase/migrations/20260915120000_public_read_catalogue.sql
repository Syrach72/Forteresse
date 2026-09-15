-- La Forge (cote joueur, pas l'admin) doit pouvoir lire le catalogue
-- d'armes, les categories et les recettes pour afficher les vraies
-- infos d'un objet selectionne (cf. demande Bruno : image/nom/ressources/
-- vetérance/temps de fabrication/portee/description a la Forge). Le jeu
-- cote joueur n'a pas de session Supabase authentifiee (seule l'admin se
-- connecte reellement) ; les policies "lecture par tout utilisateur
-- connecte" (auth.role() = 'authenticated') bloquaient donc cette lecture
-- pour un visiteur anonyme. Ce sont des donnees de reference publiques du
-- jeu (pas de compagnie/utilisateur associe), pas des donnees privees :
-- ouvrir la lecture au role anon est sans risque.

drop policy "objet_catalogue: lecture par tout utilisateur connecte" on objet_catalogue;
create policy "objet_catalogue: lecture publique"
  on objet_catalogue for select
  using (true);

drop policy "recette: lecture par tout utilisateur connecte" on recette;
create policy "recette: lecture publique"
  on recette for select
  using (true);

drop policy "ingredient_recette: lecture par tout utilisateur connecte" on ingredient_recette;
create policy "ingredient_recette: lecture publique"
  on ingredient_recette for select
  using (true);

drop policy "categorie: lecture par tout utilisateur connecte" on categorie;
create policy "categorie: lecture publique"
  on categorie for select
  using (true);
