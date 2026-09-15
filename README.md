# Forteresse — prototype responsive

**Passation à Bruno et Claude : lire [CLAUDE.md](CLAUDE.md)** pour comprendre le code local, les règles actuelles, les limites et la proposition de future base de données.

Prototype React + Vite basé sur les captures et le brief oral de Bruno. Interface française, police Aniron fournie par Tim. Aucune publication ni authentification réelle.

## Lancer

```sh
npm install
npm run dev -- --host 127.0.0.1 --port 4173
```

Ouvrir http://127.0.0.1:4173. `npm run build` prépare la distribution. Les modifications se conservent pendant la session de page et se réinitialisent au rechargement.

## Parcours disponibles

- Château : onze lieux ancrés en pourcentage, vue desktop compacte ; décor + liste tactile sur mobile.
- Connexion / inscription : validation et entrée dans la démo, aucun mot de passe stocké.
- Guerrier : quatre cartes, fiche individuelle, modifications manuelles, progression et popup Fougue. Les autres classes ont un écran vide prêt à compléter.
- Dortoirs / Infirmerie : placement au clic ou glisser-déposer, compteurs 0–5, sortie manuelle, déblocage contrôlé par le solde.
- Entraînement : instructeur et élèves distincts, choix du mercenaire, compteur, retrait et place élève supplémentaire.
- Bouton global « +10 minutes » : +1 sur tous les compteurs, maximum 5. Aucun timer réel.
- Trésorerie : modification des frais/recettes, recalcul immédiat dans le header, historique des mouvements.
- Marché : quatre catégories et catalogue filtré ; achat, quantité disponible, débit d’or et inventaire.
- Laboratoire : inventaire de 16 composants, cinq branches, glisser-déposer et sélection au clic, trois recettes illustratives, fabrication reliée à l’Arsenal.
- Forge / Armurerie : recettes de démonstration, contrôle des ressources, fabrication et durée d’instance.
- Arsenal : objets communs, équipement/rangement, consommation de potion sans modification automatique des fiches.
- Quêtes : quatre fiches statiques avec niveau requis, stock commun et inventaires de campagne séparés par mercenaire. Transferts aller/retour d’une unité.

## Limites

Prototype local à une page : pas de multi-utilisateur, serveur, permissions MJ, sauvegarde persistante, paiement, vente ou règles définitives d’alchimie/magie. Les fonds métier et plusieurs icônes utilisent les captures comme références temporaires, comme autorisé par Tim. Les prix/recettes et certaines contraintes demeurent illustratifs. Les règles confirmées et celles à valider sont dans `BRIEF-CONFIRME.md`.

## Architecture réutilisable

- `src/App.jsx` : shell, navigation et orchestration partagée des états.
- `src/Characters.jsx`, `Dormitory.jsx`, `Training.jsx`, `Treasury.jsx`, `Market.jsx`, `Quests.jsx` : écrans/composants métier.
- `src/characters.js`, `dormitory.js`, `training-data.js`, `treasury-data.js`, `data.js` : données et transitions.
- `src/game.js` : opérations inventaire, achat et fabrication.
- `Modal`, `Catalog`, `ReferenceCrop`, `Sprite`, `ItemArt` : primitives réutilisées ; les deux zones de repos utilisent le même composant avec une variante.
- `src/styles.css` : tokens, Aniron, repères et responsive.

## Vérifications

```sh
npm run test:domain
npm run build
npm run test:sites
```

Les scripts de navigateur sous work/ sont des preuves locales de vérification (ils référencent le runtime de cette machine). `design-qa.md` décrit la comparaison visuelle et les limites.

## Documents

`CLAUDE.md` : guide de reprise du code, fonctionnement local, architecture de données proposée et plan de développement.
`BRIEF-CONFIRME.md` : transcription structurée des règles reçues.
`ASSETS.md` : sources et emplacements de remplacement.
`DESIGN.md` / `UX-CONTRACT.md` : conventions réutilisables.
