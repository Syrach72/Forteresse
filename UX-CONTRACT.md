# Contrat du prototype

## Source métier
Demande de Tim et captures jointes du 8–9 septembre 2026. Brief oral partiellement reçu : BRIEF-CONFIRME.md fait autorité. Pas d’API, d’argent réel, de persistance ou de droits de production. État partagé en mémoire dans cette page, remis à zéro au rechargement. Les classes ouvrent une liste de mercenaires ; Guerrier dispose de fiches séparées et d’un formulaire manuel.

## Canonical UI Map
| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | Auth | UX-CONTRACT.md | connexion, inscription simulées | navigateur : erreurs puis succès |
| Scrollbar | src/styles.css | DESIGN.md | document, dialog | inspection responsive |
| Toast | App/notify | UX-CONTRACT.md | succès | achat, fabrication |
| CRUD | game.js/transact | src/data.js | acheter, fabriquer, équiper, utiliser | tests métier et navigateur |
| Select/Listbox | HTML select | UX-CONTRACT.md | native | navigateur, choix mercenaire et durée |

## Comportement
- Navigation par liens hash, historique navigateur ; fermeture du dialogue au changement de route.
- Achat : contrôle stock/solde, débit et ajout inventaire dans une unique transition locale, message et journal.
- Fabrication : contrôle et consommation des trois ressources, ajout objet, journal ; solde inchangé.
- Utilisation : consommation d’une potion, suppression de la pile vide ; effets à reporter manuellement sur la fiche.
- Erreur : pas de mutation partielle, message conservé dans le contexte de l’action.
- Popup : dialog natif modal, Escape, focus restauré. Aucun confirm/alert natif.
- Auth : champs étiquetés, erreurs associées et focus au premier invalide ; mots de passe masqués et non stockés ; la validation lance seulement la démo.
- Pas de suppression définitive ni d’effets externes. Les modifications se réinitialisent au rechargement.
- Tour verrouillée en attente des règles. Entraînement, Armurerie et Forge accessibles pour démonstration.

## Règles confirmées et propriétaires
- Les mercenaires appartiennent à la compagnie ; repos, soins et entraînement sont partagés. Ne pas utiliser Current User comme propriétaire permanent du personnage.
- Compteurs 0–5, bouton +10 minutes = +1 partout, aucune minuterie réelle ni sortie automatique.
- Coûts manuels/recettes et solde du header cohérents, mouvements d’achat préservés après édition.
- Quêtes statiques, inventaires de campagne séparés par mercenaire, transferts sans duplication.
- Select/Listbox : sélecteurs natifs de mercenaire et de durée ; popup système accepté. Form : Auth, éditeurs Characters, Dormitory, Training et Treasury.

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|

Les règles non confirmées figurent explicitement dans BRIEF-CONFIRME.md. Il n’y a ni rôle serveur réel ni appel IA.

## Alchimie
Propriétaire des interactions : Alchemy.jsx ; commandes et état : alchemy.js/changeAlchemy dans l’état partagé de App. Drag natif HTML sur ordinateur, boutons natifs pour sélectionner/déposer et retirer au clavier/toucher. Escape annule la sélection. Dépôt externe invalide ignoré, coordonnées/ingrédients validés par la commande. Remplacer ou déplacer ne consomme rien. Fabrication synchrone : vérification de la recette et des stocks, consommation, ajout à l’Arsenal et journal dans une transition. La préparation est vidée pour empêcher une seconde fabrication au double clic. Tests dédiés dans tests/alchemy.test.mjs.
