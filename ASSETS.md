# Assets et remplacements

## Originaux fournis et intégrés
| Usage | Fichier local | Source fournie |
|---|---|---|
| Connexion / inscription | public/assets/coastal-castle.jpg | https://b59c4c796d3efc62d8d9ba1798852ff8.cdn.bubble.io/f1788870492822x997808219868680800/coastal-medieval-castle-on-sea.jpg |
| Château accueil | public/assets/castle-original.jpg | https://b59c4c796d3efc62d8d9ba1798852ff8.cdn.bubble.io/cdn-cgi/image/w=1536,h=1071,f=auto,dpr=0.75,fit=cover/f1788942295603x773537471465239700/Background%20Image%20-%20Castle%20%2820%29.jpg |
| Pièce d’or | public/assets/gold-coin.png | https://b59c4c796d3efc62d8d9ba1798852ff8.cdn.bubble.io/cdn-cgi/image/w=96,h=96,f=auto,dpr=0.75,fit=contain/f1788941066451x108355134780333090/pi%C3%A8ce.png |
| Cadre solde | public/assets/gold-frame.png | https://b59c4c796d3efc62d8d9ba1798852ff8.cdn.bubble.io/cdn-cgi/image/w=256,h=102,f=auto,dpr=0.75,fit=contain/f1788940658954x442579790422325600/Image1.png |

Les versions générées provisoirement ne sont pas utilisées dans le prototype final.

## Références temporaires
- Les icônes de lieux et objets sont des fenêtres CSS sur les captures originales copiées dans `public/assets/references/`. Leur définition se trouve dans LOCATIONS.icon et ITEMS.crop. Des petits fonds/cadres restent donc intégrés à ces références ; remplacer Sprite et ItemArt par un simple img lorsque les originaux sont fournis.
- Les intérieurs Armurerie, Forge, Infirmerie, Alchimie et Trésorerie utilisent une région de leurs captures comme décor provisoire. Mettre les vrais fonds dans public/assets et remplacer les URLs ASSETS de src/data.js. Supprimer alors les règles CSS de recadrage des références.
- Le panneau Quêtes utilise la capture dédiée ; fournir l’asset transparent pour supprimer son fond résiduel.
- Aniron Bold est maintenant embarquée dans public/assets/aniron-bold.ttf. Source : https://b59c4c796d3efc62d8d9ba1798852ff8.cdn.bubble.io/f1788873151650x228167851210015580/anirb___.ttf ; conserver les conditions de licence du fichier fourni avant diffusion publique. Cormorant Garamond reste la police de texte courant.

Les captures demeurent intactes. Aucun asset de Bruno n’est écrasé. Le téléchargement local des originaux permet à la démo de fonctionner indépendamment du CDN, hors polices.

Les captures supplémentaires Guerrier, fiche, Fougue, dortoir, infirmerie, entraînement, trésorerie, quêtes et marché sont copiées dans public/assets/references/. Les zones de portraits et icônes sont référencées par ReferenceCrop, sans altérer les fichiers originaux.

## Icônes originales fournies le 9 septembre
Douze PNG conservés dans `public/assets/icons/`, avec URLs sources dans `sources.json`. Les lieux et menus utilisent les originaux ; le cadenas remplace le libellé sur la carte. Objets magiques est aussi utilisé au marché. Le champignon est disponible pour les futures recettes, sans quantité inventée.

Le laboratoire réutilise la capture fournie le 10 septembre à 19:32 dans `references/alchemy-workbench.png` : le pentagramme et les composants sont cadrés à l’affichage, sans altérer le fichier original. Le champignon utilise son PNG transparent.

Le fond des Dortoirs (`public/assets/references/dormitory.png`) a été remplacé le 11 septembre 2026 par un visuel fourni localement par Bruno (`dortoir1 (2).png`), sans overlay d’interface cette fois. Il sert de décor plein cadre via `.dortoirs .interior-backdrop` (background-size: cover). Vérifier la licence avant toute diffusion publique.

Le fond de l’Infirmerie (`public/assets/references/infirmary.png`) a été remplacé le 11 septembre 2026 par un visuel fourni localement par Bruno (`infirmerie fond.jpg`, dossier `D:\Photos\Fortress Bubble`), sans overlay d’interface. Décor plein cadre via `.infirmerie .interior-backdrop` (background-size: cover, position center bottom). Vérifier la licence avant toute diffusion publique.

Le fond du Laboratoire Alchimiste (`public/assets/references/alchemy.png`) a été remplacé le 11 septembre 2026 par un visuel fourni localement par Bruno (`alchimiste fond.jpg`, dossier `D:\Photos\Fortress Bubble`), sans overlay d’interface. La règle CSS héritée pour ce lieu recadrait une région zoomée (auto 122%/160%, adaptée à l’ancienne capture) ; une règle dédiée `.alchimie .interior-backdrop { background-size: cover; background-position: center; }` a été ajoutée dans `src/styles.css` pour afficher ce nouveau visuel en plein cadre, sur le même principe que `.infirmerie`. Vérifier la licence avant toute diffusion publique.

Le fond de l’Armurerie (`public/assets/references/armory.png`) a été remplacé le 11 septembre 2026 par un visuel fourni localement par Bruno (`armurerie fond.jpg`, dossier `D:\Photos\Fortress Bubble`), sans overlay d’interface. Même correctif que l’Alchimie : règle dédiée `.armurerie .interior-backdrop { background-size: cover; background-position: center; }` ajoutée dans `src/styles.css` pour remplacer le recadrage zoomé hérité. Vérifier la licence avant toute diffusion publique.

Le fond de la Forge (`public/assets/references/forge.png`) a été remplacé le 11 septembre 2026 par un visuel fourni localement par Bruno (`forge fond.jpg`, dossier `D:\Photos\Fortress Bubble`), sans overlay d’interface. Même correctif : règle dédiée `.forge .interior-backdrop { background-size: cover; background-position: center; }` ajoutée dans `src/styles.css`. Vérifier la licence avant toute diffusion publique.

Le fond du Terrain d’Entraînement (`public/assets/references/training.png`) a été remplacé le 11 septembre 2026 par un visuel fourni localement par Bruno (`terrain d'entraînement.png`, dossier `D:\Photos\Fortress Bubble`), sans overlay d’interface. `.entrainement .interior-backdrop` était déjà en background-size: cover ; aucun correctif CSS nécessaire. Vérifier la licence avant toute diffusion publique.

Le fond de la Trésorerie (`public/assets/references/treasury.png`) a été remplacé le 11 septembre 2026 par un visuel fourni localement par Bruno (`trésorerie fond.jpg`, dossier `D:\Photos\Fortress Bubble`), sans overlay d’interface. La règle héritée appliquait `filter: blur(9px) brightness(0.45)` pour masquer le texte de l’ancienne capture ; elle a été retirée dans `src/styles.css` (`.tresorerie .interior-backdrop`) au profit d’un simple `background-size: cover; background-position: center;`, sur le même principe que les autres lieux. Vérifier la licence avant toute diffusion publique.

## Fond du Marché (11 septembre 2026)
Le fond du Marché utilise maintenant un nouveau fichier plein cadre, `public/assets/references/market-square.png` (clé `ASSETS.market`), à partir d’un visuel fourni localement par Bruno (`marché fond.jpg`, dossier `D:\Photos\Fortress Bubble`), affiché via `.marche .interior-backdrop` (`background-size: cover; background-position: center;`), exactement comme les autres lieux.

Une première tentative avait simplement ajouté ce fond plein cadre par-dessus le fond existant de `.market-hub` (qui affichait déjà `market.png` en `107% 100%` dans sa propre boîte à ratio fixe 560/362) : résultat, deux scènes de marché différentes superposées/décalées. Correction : le `background` propre à `.market-hub` a été retiré dans `src/styles.css` — `.market-hub` ne sert plus qu’à positionner les 4 boutons de catégorie (`CATEGORIES` dans `Market.jsx`, coordonnées x/y/w/h inchangées), rendu transparent au-dessus du fond plein cadre unique.

`public/assets/references/market.png` (l’ancien fichier) reste inchangé et toujours utilisé comme feuille de sprites pour les icônes « Objets divers » et « Armes » (`ReferenceCrop source="market"`) — voir plus haut. Vérifier la licence du nouveau visuel avant toute diffusion publique.

## Cadre du solde d'or (11 septembre 2026)
`public/assets/gold-frame.png` a été remplacé par un visuel fourni localement par Bruno (`slot2.png`, dossier `D:\Photos\Fortress Bubble`), une plaque bois/cuir bien plus large que haute (893×360, contre 100×102 pour l'original). Pour éviter toute déformation, `.gold-counter` (`src/styles.css`) est passé de `background-size: 100% 100%` (étirement libre, déjà très déformant avec l'ancien visuel quasi carré) à `background-size: cover` : l'image garde ses proportions natives et est seulement rognée en haut/bas pour remplir le cadre, jamais écrasée horizontalement.

La pièce d'or (`.coin`) a une nouvelle règle `.gold-counter .coin { margin-left: -18px; }` pour mordre sur la bordure gauche du cadre : ce décalage a été calculé en échantillonnant l'image de fond réellement affichée (via canvas) pour repérer la ligne de couture sombre de la bordure, puis centrer la pièce dessus (mesuré : centre de la pièce à 8px du bord gauche de la boîte, exactement sur cette ligne). Vérifier la licence avant toute diffusion publique.

## Effet verre flouté des boutons de la barre de menu (11 septembre 2026)
Les boutons `.class-nav button` / `.class-nav a` (Légende, Guerrier, Roublard, Rôdeur, Prêtre, Druide, Incantateur, Paladin, Forteresse) ont un effet « verre dépoli » dans `src/styles.css` : fond semi-transparent (`rgba(255,255,255,0.22)`) + `backdrop-filter: blur(7px)` (et `-webkit-` pour Safari), qui floute la texture de carte derrière chaque bouton sans flouter le texte (le `backdrop-filter` n’affecte que ce qui est visible à travers la transparence, jamais le contenu propre de l’élément). Le texte reste en `var(--ink)` (#241b12, quasi noir), non flouté. L’état survol/actif garde le même principe avec une teinte dorée semi-transparente (`rgba(221,199,126,0.55)`) plutôt que la couleur pleine d’origine.

## Fond de la barre de menu (11 septembre 2026)
Le même visuel (`public/assets/references/parchment-map.png`) est aussi utilisé comme fond de `.game-header` (la barre de navigation des classes + solde + temps, présente sur toutes les pages), via `background: url("/assets/references/parchment-map.png") center/cover;` dans `src/styles.css`. Seul le fond derrière les boutons change ; les boutons (`.class-nav a`, `.gold-counter`, etc.) gardent leur propre fond, défini séparément.

## Fond des pages de classe (11 septembre 2026)
Un fond texture (`public/assets/references/parchment-map.png`, clé `ASSETS.parchment`) a été ajouté à partir d’un visuel fourni localement par Bruno (`fond texture carte.png`, dossier `D:\Photos\Fortress Bubble`) pour les pages de classe **Guerrier, Roublard, Rôdeur, Prêtre, Druide, Incantateur et Paladin** (liste et fiche de détail). Appliqué via un style inline sur `<main className="characters-page">` dans `Characters.jsx` (liste `PARCHMENT_CLASSES`), en `background-size: cover; background-position: center;`. **Légende n’a volontairement pas ce fond** (non demandé par Bruno) et garde le fond uni `var(--paper)` d’origine. Vérifier la licence avant toute diffusion publique.

## Pentagramme du Laboratoire Alchimiste (18 septembre 2026)
Le visuel du pentagramme (`.sigil-art`, `Alchemy.jsx`) utilisait une région recadrée de `alchemy-workbench.png` (feuille de référence). Remplacé par un visuel autonome fourni localement par Bruno (`pentagrame.png`, dossier `D:\Photos\Fortress Bubble`), copié dans `public/assets/references/pentagram-star.png`. `alchemy.css` (`.sigil-art img`) est passé du recadrage/zoom hérité (`width:327%`, décalage `top`) à un simple `object-fit: contain` : l'image est fournie entière, pas une région d'une feuille de sprites. `alchemy-workbench.png` reste utilisé par ailleurs pour les icônes d'ingrédients (`IngredientArt`, `.ingredient-crop`). Vérifier la licence avant toute diffusion publique.

## Régression connue — icônes de la page Quêtes (11 septembre 2026)
Le fond de la page Quêtes (`public/assets/references/quests-page.png`) a été remplacé par un visuel fourni localement par Bruno (`quêtes fond.jpg`, dossier `D:\Photos\Fortress Bubble`) et la règle `.quetes .interior-backdrop` simplifiée en `background-size: cover; background-position: center;` (suppression du `blur(4px) brightness(0.7)` hérité). Le fond plein cadre fonctionne.

**Mais** ce fichier servait aussi de feuille de sprites : `Quests.jsx` découpe dedans, via `ReferenceCrop`/coordonnées fixes, les icônes des 4 cartes de quête (coffre, parchemin, couronne, tête de gobelin) et des boutons « Arsenal » / « Inventaires de campagne ». En écrasant le fichier, ces 6 icônes affichent désormais un carré de couleur unie au lieu du bon visuel. Aucune sauvegarde de l’original n’existait (pas de dépôt Git dans ce dossier) : la restauration devra passer par l’historique des versions OneDrive du fichier, ou par de nouveaux visuels dédiés fournis par Bruno pour ces 6 icônes. Décision de Bruno le 11 septembre : conserver le nouveau fond tel quel et traiter la réparation des icônes plus tard, séparément.
