---
version: alpha
name: Forteresse
description: Interface de jeu de rôle reprenant les captures de Bruno.
colors:
  primary: '#4a2b16'
  background: '#e7dac0'
  surface: '#f1e7d2'
  text: '#241b12'
  accent: '#e1bc55'
  border: '#8f7a56'
  muted: '#675c4a'
  danger: '#9a271c'
  focus: '#255d85'
typography:
  display:
    fontFamily: 'Aniron, Georgia, serif'
  body:
    fontFamily: 'Cormorant Garamond, Georgia, serif'
rounded:
  DEFAULT: '2px'
  dialog: '0px'
  auth: '12px'
spacing:
  page: '32px'
  mobile: '16px'
components:
  Location: {height: '76px'}
  Modal: {width: '660px'}
  Button: {height: '42px'}
---
# Forteresse

## Overview
Prototype français de compagnon de JDR en présentiel. Source autoritaire : captures de Bruno et demande de Tim. La signature est le château interactif : les lieux restent attachés aux salles. Aucun style SaaS générique. Les règles métier détaillées sont des hypothèses de démonstration, en attente de l’explication orale.

## Colors
Les variables de `src/styles.css` constituent la source runtime : primary → --wood, background → --paper, surface → --paper-light, text → --ink, accent → --gold, border → --edge, muted → --muted, danger → --danger, focus → --focus. Cette documentation les reflète ; modifier les deux ensemble. Fond parchemin et panneaux de bois ; texte brun très sombre. Les couleurs d’état sont accompagnées de texte.

## Typography
Aniron pour navigation et lieux, Cormorant Garamond pour titres et textes ; Georgia pour les petits libellés. Aniron Bold est l’original fourni par Tim, embarqué en local ; Cormorant Garamond sert au texte courant. Français et nombres fr-FR.

## Layout
Carte ratio 756/581, identique à la zone sous la navigation de la capture complète. Coordonnées en pourcentages centralisées dans LOCATIONS. Sous 681px, décor et liste de onze lieux ; les boutons miniatures sont masqués. Inventaire : 8 colonnes, puis 6, puis 4. Sur mobile très étroit, les lieux passent à une colonne. Scroll du document ; scroll du dialogue lorsque nécessaire.

## Elevation & Depth
Panneaux parchemin translucides bordés, ombres courtes, bois en relief pour actions. Formulaire avec flou du décor marin.

## Shapes
Panneaux rectangulaires de la référence. Arrondi réservé au formulaire et à l’illustration d’objet.

## Components
Sprite et ItemArt référencent temporairement des régions des captures originales par masquage CSS. Assets officiels déjà fournis : les deux châteaux, pièce et cadre du solde. Modal est un dialog natif avec Escape, focus initial et restauration. Catalog partagé entre marché et atelier. Actions via transact ; un verrou local empêche le double clic pendant l’action. Toast partagé, aria-live. Les actions répétées, erreurs, valeurs vides et filtres sans résultats sont visibles. Reduced motion respecté, scrollbar global, focus visible.

## Do's and Don'ts
- Garder la géométrie du décor et des lieux dans le même repère.
- Remplacer les références par les images originales dans src/data.js et les composants d’assets.
- Ne pas considérer les coûts, recettes, droits et quêtes de démo comme validés.
- Ne pas stocker de mot de passe ni prétendre à une authentification réelle.

## Compléments approuvés pendant la construction
Accueil sur toute la largeur de la fenêtre, pages métier plafonnées à 1120 px. Carte à ratio constant et blocs compacts. Mercenaires communs, fiches manuelles, instances 0–5 et incrément global : voir BRIEF-CONFIRME.md.

## Ajustements validés en direct
Château sur toute la largeur de la fenêtre, blocs plafonnés à leur taille compacte. Footer supprimé ; action globale +10 minutes près du solde. Icônes PNG originales. Transitions de page 220 ms, popups 180 ms, survol discret ; aucune attente imposée et respect de prefers-reduced-motion.

Correction explicite de Tim : l’accueil occupe 100 % de la fenêtre, sans max-width. Le plafond de taille des blocs reste actif ; le ratio du château est conservé. Les pages métier restent compactes.

Arsenal remplace Stock et échange sa position avec Dortoirs. Quêtes est ancré au groupe du solde dans le header.

Pages métier compactes : infirmerie en trois colonnes/deux rangées, panneau de disponibilité raccourci, décor recadré vers le bas. À 1440×800, infirmerie/dortoirs/entraînement/forge/armurerie tiennent dans la hauteur avec les données initiales. Sur des écrans plus courts ou avec plus de contenu, conserver le défilement du document plutôt que masquer les actions.

## Atelier d’alchimie
Pentagramme illustré en bas à gauche, cinq cibles circulaires visibles, inventaire de seize composants à droite avec grimoire. Réutiliser les images de Tim. Réservation des quantités visible, résultat avant consommation, bouton explicite de fabrication. Une combinaison inconnue ne détruit rien. Même commande métier pour glisser-déposer et clic/clavier/toucher. État de préparation partagé et conservé en naviguant, remis à zéro au rechargement comme le reste du prototype. Animations brèves uniquement sur réussite et zones survolées ; mouvement réduit respecté.
