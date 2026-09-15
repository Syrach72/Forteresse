# Vérification visuelle et fonctionnelle — 9 septembre 2026

Source : captures de Bruno et assets originaux fournis par Tim. La comparaison initiale côte à côte est dans `work/comparison-map.png` (repère 756 × 581). Les positions relatives des lieux sont conservées. À la demande de Tim, le rendu final remplit toute la largeur de la fenêtre, plafonne les blocs, supprime le footer et place +10 minutes près du solde. Aniron et les nouvelles icônes originales sont intégrés.

Rendus inspectés : `work/home-aniron.png` et `work/home-mobile-aniron.png`. Le montant est centré dans l’espace à droite de la pièce. Les libellés restent dans leurs blocs sur desktop. Sur mobile, la carte devient un aperçu accompagné d’une liste de lieux. Le débordement des boutons masqués a été corrigé en les retirant de la mise en page mobile.

Vérifications : marché (achat, catégorie vide), quêtes statiques, transfert aller-retour d’inventaire ; absence de débordement à 320, 390, 768 et 1280 px sur les cinq routes couvertes par `work/market-check.cjs`, aucune erreur JavaScript. Build réussi, huit tests métier réussis. Audit strict : aucune anomalie.

Animations : apparition des pages 220 ms, dialogues 180 ms, relief discret au survol. Aucun délai métier ajouté ; préférence de mouvement réduit respectée. L’interface garde ses actions et sa navigation durant les transitions.

Écarts assumés : les pages métier gardent des captures provisoires avec éléments graphiques intégrés, conformément à l’accord de Tim. Des fiches et recettes restent à renseigner. Connexion simulée, état en mémoire, aucun backend multiutilisateur. Le champignon est importé pour les recettes futures sans créer de règle ou quantité.

final result: passed

Vérification complémentaire : `work/fullwidth-check.cjs` valide la largeur complète à 1594, 1920 et 390 px, la taille compacte des blocs, Arsenal au-dessus de Dortoirs et Quêtes aligné sous le groupe du solde. Rendu : `work/home-fullwidth.png`.

Compactage des pages métier : `work/compact-review.cjs` mesure 800 px pour les cinq pages sur un écran 1440×800, contre 1208 px auparavant pour l’infirmerie. Contrôle complémentaire à 320, 390 et 768 px : absence de débordement horizontal et ouverture/fermeture de la fiche de soins. Rendu inspecté : `work/infirmary-compact.png`.

## Laboratoire — 10 septembre
Nouvel atelier avec inventaire permanent, cinq branches, recette et fabrication. Validation de compilation et douze tests métier réussis, dont quatre scénarios d’alchimie couvrant reservation, remplacement/échange/retrait, stocks insuffisants, ingrédients inconnus, trois résultats utilisables et double fabrication refusée. Aucun contrôle navigateur supplémentaire effectué pour cette évolution ; les preuves visuelles antérieures ne couvrent pas cet atelier.
