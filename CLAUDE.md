# Forteresse — guide de reprise pour Bruno et Claude

Passation du 11 septembre 2026. Ce document décrit le code livré et le prototype accessible sur localhost. La base de données présentée plus loin est une proposition d’évolution : elle n’est pas implémentée.

## 1. Mission et ordre de lecture

Tu reprends **Forteresse**, un compagnon de jeu de rôle en français : une compagnie de mercenaires, un château interactif, des ateliers, du repos, des soins, de l’entraînement, une trésorerie et des inventaires.

Bruno fournit l’univers, les contenus et les règles de jeu. Tim a réalisé le prototype local à partir de ses références et de ses demandes. Préserve ce travail : ne reconstruis pas tout de zéro et ne change pas de stack sans besoin explicite.

Commence par :

1. Ce fichier `CLAUDE.md`.
2. `AGENTS.md` : consignes propres au prototype et préférences visuelles.
3. `BRIEF-CONFIRME.md` : règles reçues, hypothèses et points à préciser.
4. `DESIGN.md` et `UX-CONTRACT.md` : apparence et comportement des interfaces.
5. `ASSETS.md` : provenance des visuels et références temporaires.
6. Les fichiers de code correspondant à la demande de Bruno.

Distingue toujours **fonctionnement vérifié dans le code**, **règle confirmée par le brief**, **valeur de démonstration** et **proposition future**. Une constante dans un fichier ne suffit pas à prouver qu’une règle de jeu est définitive.

## 2. Installation et lancement

Depuis le dossier contenant `package.json` :

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4173 --strictPort
```

Ouvrir :

- Accueil : `http://127.0.0.1:4173/`
- Laboratoire : `http://127.0.0.1:4173/#alchimie`
- Arsenal : `http://127.0.0.1:4173/#stock`

Utiliser une version Node compatible avec les dépendances verrouillées ; Node 22 LTS récent est un point de départ recommandé. Réinstaller `node_modules` sur la machine de Bruno au lieu de copier celui du Mac de Tim. Aucun fichier `.env` ou secret n’est requis pour la démo.

### Vérifications

```sh
npm run test:domain
npm run build
npm run test:sites
```

Ces commandes ont été exécutées avec succès pendant cette passation : **12 tests métier, build de production et 4 tests worker/packaging**. Aucun nouvel audit visuel exhaustif n’a été effectué pendant la rédaction. Ces tests ne prouvent pas le fonctionnement d’un futur backend.

Pour prévisualiser le build :

```sh
npm run preview -- --host 127.0.0.1 --port 4173 --strictPort
```

Arrêter le serveur de développement sur ce port avant de lancer la preview, ou choisir un autre port.

## 3. État réel du projet

**Il s’agit d’une application frontend de démonstration, pas encore d’une application multi-utilisateur persistante.**

| Élément | État actuel |
|---|---|
| Interface française | Implémentée |
| Navigation entre les lieux | Implémentée, via le fragment d’URL |
| Achats, fabrication, inventaires | Transitions locales en mémoire |
| Laboratoire et glisser-déposer | Implémentés, avec contrôle des stocks |
| Fiches de guerriers | Présentes, édition manuelle |
| Autres classes | Écrans à compléter |
| Dortoirs, soins et entraînement | Placements et compteurs locaux |
| Trésorerie et transferts de campagne | Implémentés localement |
| Connexion et inscription | Simulées ; aucun véritable compte créé |
| Base de données | Absente |
| Sauvegarde après rechargement | Absente |
| Droits joueur/MJ | Absents côté serveur |
| API métier, paiements, IA intégrée | Absents |

Les états survivent à la navigation entre écrans dans la même page. **Recharger la page réinitialise la démo.** Il n’y a pas de persistance localStorage ni de synchronisation entre ordinateurs.

## 4. Stack et structure du code

Versions déclarées dans le manifeste : React 19.2.0, React DOM 19.2.0, Vite 6.4.2, plugin React 5.0.4. JavaScript/JSX, CSS et tests natifs Node. Pas de TypeScript ni de bibliothèque de routage ajoutée.

| Chemin | Responsabilité |
|---|---|
| `src/main.jsx` | Monte l’application React |
| `src/App.jsx` | Shell, navigation, états partagés, orchestration et dialogues |
| `src/data.js` | Lieux, assets, petit catalogue d’objets et valeurs initiales |
| `src/game.js` | Création de l’état de jeu et commandes achat/fabrication/équipement/utilisation |
| `src/Alchemy.jsx` | Interface du laboratoire, pentagramme, inventaire et résultat |
| `src/alchemy.js` | Composants, recettes, réservation et fabrication alchimique |
| `src/Characters.jsx` | Listes et fiches de personnages, formulaires |
| `src/characters.js` | Classes, quatre guerriers, descriptions et progression |
| `src/Dormitory.jsx` | Composant partagé pour dortoirs et infirmerie |
| `src/dormitory.js` | Placements et compteurs des lits |
| `src/Training.jsx`, `src/training-data.js` | Instructeur, élèves et emplacements |
| `src/Treasury.jsx`, `src/treasury-data.js` | Budget et modification des postes |
| `src/Market.jsx` | Entrées des catégories du marché |
| `src/Quests.jsx` | Quêtes et inventaires de campagne |
| `src/styles.css` | Styles partagés, responsive et animations |
| `src/alchemy.css` | Styles du laboratoire |
| `public/assets/` | Images, icônes, police et captures de référence |
| `tests/game.test.mjs` | Achats, stocks, repos, durées, trésorerie et autres transitions |
| `tests/alchemy.test.mjs` | Réservation, déplacement, fabrication et échecs |
| `tests/sites-worker.test.mjs` | Service des assets et packaging |

### Navigation

`App.jsx` lit `location.hash` et écoute `hashchange`. Les principaux lieux sont :

`forteresse`, `alchimie`, `stock`, `forge`, `armurerie`, `dortoirs`, `infirmerie`, `entrainement`, `tresorerie`, `marche`, `quetes`.

Le nom visible **Arsenal** correspond encore à la route technique `stock`. Les routes de classes se trouvent dans `characters.js`. `connexion` et `inscription` sont des écrans de démonstration.

### États et commandes

`App` possède les états via `useState`, accompagnés de références `useRef` pour certaines commandes. Les fonctions métier clonent les données, valident une action et renvoient soit un nouvel état, soit une erreur.

- `initialGame()` : instancie le jeu et son alchimie.
- `transact(state, action)` : acheter, fabriquer à la forge/armurerie, équiper/ranger, utiliser une potion.
- `changeAlchemy(game, action)` : préparer ou fabriquer une potion.
- `updateDormitory()` : placer, modifier une durée, libérer un lit.
- `changeTreasury()` : modifier un montant et calculer sa variation.
- `transferCampaign()` dans `App.jsx` : transfert d’une unité entre arsenal commun et inventaire d’un mercenaire.
- `advanceTime()` : avance manuelle du temps et des compteurs.

Structures actuellement séparées : `game.inventory` pour l’arsenal, `game.alchemy.stock` pour les ingrédients, `game.resources` pour les matériaux des ateliers, `game.stock` pour le marché, et `campaign` pour les possessions de campagne. Ne pas créer une future base avec plusieurs sources contradictoires pour la quantité d’un même objet dans un même inventaire.

## 5. Parcours et règles actuelles

### Château et direction visuelle

- Château d’accueil sur toute la largeur, blocs d’accès plafonnés à une taille compacte.
- Arsenal en haut à gauche ; Dortoirs à l’ancienne place du Stock, en bas à gauche.
- Quêtes ancré sous le solde et le bouton +10 minutes.
- Footer décoratif supprimé.
- Pages métier compactes ; recadrer les décors vers le bas pour montrer les actions sans défilement excessif.
- Identité bois/parchemin/or ; Aniron fournie et embarquée pour la personnalité médiévale, Cormorant Garamond pour le texte courant.
- Transitions brèves, focus visible, clavier/toucher et `prefers-reduced-motion`. Ne pas remplacer l’interface par un tableau de bord SaaS générique.
- Conserver le défilement du document lorsque nécessaire, sans cacher les actions dans un panneau trop court.

### Mercenaires, repos et soins

Le brief rattache les mercenaires à la compagnie. Les joueurs peuvent les utiliser successivement ; ce ne sont pas automatiquement des personnages possédés à vie par un compte.

Le prototype possède quatre guerriers : Gnaeus Gnaru, Hetamon Haaee, Tavoul Abramos et Orik Vanaeskerkin. Plusieurs caractéristiques des fiches sont encore incomplètes. Ne pas combler ces manques en inventant des statistiques.

Les caractéristiques et les effets sont renseignés manuellement. L’application n’appelle pas d’IA pour modifier les fiches. L’aptitude Fougue est expliquée dans le brief ; les autres aptitudes ne sont pas toutes documentées.

Dortoirs et infirmerie partagent leur composant : placer un personnage, régler une durée, libérer manuellement la place et débloquer des emplacements. Entraînement distingue instructeur et élèves.

**+10 minutes signifie +1 sur les compteurs, bornés de 0 à 5.** Aucun timer réel ni achèvement automatique. Le champ historique `remaining` ne signifie pas qu’il faut décrémenter. L’interdiction d’occuper plusieurs activités simultanées est une hypothèse de cohérence du prototype à confirmer avec Bruno.

### Trésorerie, marché et arsenal

Budget manuel avec recettes et frais. Les achats restent comptabilisés quand un poste budgétaire est modifié. Le prototype démarre notamment avec 905 Po, 45 métal, 18 cuir, 40 bois et quatre potions : **ce sont les valeurs de la démo, pas une dotation utilisateur décidée**.

Marché : vérifier prix, stock disponible et solde avant achat ; débiter et ajouter l’objet dans une transition locale. Catalogue de démonstration très réduit : épée, cotte de mailles et potions. Les ressources des recettes forge/armurerie sont dans `data.js`.

Arsenal : les objets sont actuellement agrégés par identifiant, avec quantité et booléen `equipped`. Ce modèle ne représente pas encore plusieurs exemplaires d’une arme avec des durabilités ou porteurs distincts. Si Bruno demande cette granularité, la faire évoluer explicitement.

Utiliser une potion retire une unité ; ses effets doivent être reportés manuellement sur la fiche. Ne pas transformer une description provisoire en automatisme de santé.

### Quêtes et campagnes

Quatre fiches : Le Marteau de Feu (vétérance 3), La Faille (8), Le Dignitaire (4), Camp Gobelin (3). Plusieurs descriptions restent à renseigner. Le brief ne prévoit ni acceptation ni récompense automatique.

Les inventaires de campagne sont séparés par mercenaire ; les transferts aller/retour déplacent une unité. La gestion persistante d’une campagne, de ses membres et de ses droits reste à construire.

## 6. Laboratoire : comportement à connaître précisément

L’inventaire reste visible à côté des cinq branches du pentagramme. Glisser-déposer natif sur ordinateur ; sélection puis clic/toucher et boutons utilisables au clavier. Escape annule la sélection. Un retour vers l’inventaire ou la croix retire un ingrédient.

`INGREDIENTS` contient 16 composants, initialisés à six unités : champignon, ver mystique, scorpion, araignée, œil, gelée verte, aile de chauve-souris, mandragore, essence solaire, griffe, sang, tentacules, soufre, sel blanc, poudre d’argent et charbon.

| Recette de démonstration | Composition | Objet produit |
|---|---|---|
| Potion de soin | Champignon + Gelée verte + Sel blanc | `potion` |
| Potion d’énergie | Champignon + Mandragore + Essence solaire + Soufre | `potion-energy` |
| Potion de clairvoyance | Œil + Ver mystique + Poudre d’argent + Sel blanc + Charbon | `potion-clarity` |

L’ordre des branches ne compte pas. Une branche contient une unité. Les recettes finales et les effets doivent être validés par Bruno.

### Préparation

`availableIngredient()` calcule stock moins occurrences déjà placées. Le dépôt réserve la disponibilité affichée, sans consommer le stock réel. Le remplacement et l’échange entre branches, le retrait ou le vidage rendent les composants disponibles. Une tentative de réserver plus que le stock est refusée.

### Reconnaissance et fabrication

`findAlchemyRecipe()` trie les identifiants des slots non vides et compare leur représentation aux ingrédients triés de chaque recette. Les répétitions sont conservées : ce n’est pas une simple comparaison d’ensembles uniques.

Le bouton **Fabriquer la potion** est désactivé sans correspondance. La commande `brew` :

1. Retrouve la recette exacte.
2. Compte les quantités nécessaires par ingrédient et recontrôle le stock.
3. Retire les quantités nécessaires.
4. Ajoute ou augmente la potion dans `game.inventory`.
5. Vide les cinq slots et ajoute un mouvement au journal local.
6. Retourne le résultat pour l’affichage de réussite dans le laboratoire.

Une erreur ne doit pas appliquer un état partiellement modifié. La consommation des ingrédients **est implémentée et testée dans ce code local**. Le résultat est présenté dans le panneau du laboratoire ; ne pas inventer une popup distincte déjà présente.

## 7. Assets, limites techniques et packaging

Des visuels utilisent encore des régions de captures, découpées à l’affichage par `ReferenceCrop`, `Sprite`, `ItemArt` ou `IngredientArt`. Les fichiers originaux ne sont pas découpés sur disque. Consulter `ASSETS.md` avant de remplacer un visuel ; conserver les sources et vérifier les licences avant diffusion publique.

`App.jsx` contient des branches héritées, parfois rendues inaccessibles par une branche précédente du même écran. Identifier le chemin réellement rendu avant nettoyage. La commande héritée `quest` dans `game.js` n’autorise pas à ajouter un parcours de quête contraire au brief.

Certaines actions de `App.act` ont un délai visuel de 280 ms. C’est un détail d’interface, pas un temps de fabrication. Les animations et verrous locaux ne constituent pas un contrôle de concurrence serveur.

Le build Vite écrit dans `dist/client`. `scripts/prepare-sites-build.mjs` complète :

- `dist/server/index.js`
- `dist/.openai/hosting.json`

`worker/index.js` sert les assets et le fallback HTML. **Ce n’est pas une API de jeu.** `.openai/hosting.json` ne configure actuellement ni D1 ni R2. Préserver ces fichiers pour la compatibilité de packaging ; leur présence ne prouve pas un hébergement de production actif.

## 8. Future base de données — proposition adaptée au prototype

Cette section est un plan de conception, non une instruction de créer toutes les tables immédiatement. Aucun fournisseur de base ou d’authentification n’est imposé. Choisir la stack avec Bruno, puis écrire des migrations versionnées et des tests.

### Principes

- Le catalogue décrit les objets ; les lignes d’inventaire décrivent ce que l’on possède.
- Les personnages, les comptes de connexion et les objets sont des entités différentes.
- La compagnie constitue le contexte des données partagées du prototype.
- Chaque recette possède des exigences quantitatives et un résultat.
- Le stock du marché est distinct de celui de la compagnie.
- Des identifiants stables et des clés étrangères lient les tables ; un nom ou une icône ne constitue pas une identité.

### Vue des relations

```text
Utilisateur ── Adhésion ── Compagnie ── Inventaire
                              │             │
                              │        LigneInventaire ── ObjetCatalogue
                              │                                  ↑
                          Mercenaire                             │
                              │                          IngredientRecette
                        Participation                            │
                              │                               Recette
                           Campagne                         resultat_objet
                                                                 ↓
                                                          ObjetCatalogue
```

### Tables du premier socle

| Table | Champs proposés | Explication |
|---|---|---|
| Utilisateur | id, identifiant_auth, nom_affiche, actif, dates | Compte humain ; authentification déléguée au système choisi, aucun mot de passe en clair |
| Compagnie | id, nom, actif, cree_par, dates | Groupe de jeu et propriétaire du stock commun |
| AdhesionCompagnie | id, utilisateur_id, compagnie_id, role, actif | Accès joueur/MJ ; un même utilisateur peut appartenir à plusieurs compagnies |
| ObjetCatalogue | id, code_unique, nom, description, icone, categorie, empilable, utilisable, actif | Modèles : champignon, épée, potion ; aucune quantité possédée dans cette table |
| Inventaire | id, compagnie_id, type, nom, campagne_id facultatif, mercenaire_id facultatif | Arsenal commun ou sac de campagne ; définir précisément les propriétaires autorisés |
| LigneInventaire | id, inventaire_id, objet_id, quantite, equipe_par facultatif, durabilite facultative, nom_personnalise facultatif | Possession réelle ; les attributs d’exemplaire sont une extension proposée |
| Recette | id, code_unique, nom, atelier, resultat_objet_id, quantite_produite, actif | Atelier alchimie/forge/armurerie ; formule commune si les règles le permettent |
| IngredientRecette | id, recette_id, objet_id, quantite_requise | Une ligne par objet requis dans une recette |

Exemple : une seule fiche ObjetCatalogue « Champignon », une ligne d’inventaire à six unités dans l’arsenal, et une exigence de recette qui demande un champignon. Modifier le stock ne doit jamais modifier les exigences de recette.

Une recette utilise **une ligne par objet**, avec quantité 2 si elle exige deux unités. Ne pas maintenir une seconde liste d’ingrédients sur Recette qui pourrait diverger de ces lignes.

Les catégories pourront couvrir Arme, Armure, Potion, Ingrédient, Matériau, Objet magique, Objet divers et Munition selon les contenus réellement fournis. Les catégories/pluriels du catalogue actuel devront être normalisés explicitement.

### Mercenaires, campagnes et progression

| Table | Champs proposés | Explication |
|---|---|---|
| Mercenaire | id, compagnie_id, nom, portrait, classe, role, veterance, attaque, defense, esprit, mouvement, mana, sante, notes, actif | Personnage persistant ; confirmer les statistiques et bornes avec Bruno |
| Campagne | id, compagnie_id, nom, statut, quete_id facultatif | Contexte d’une aventure |
| ParticipationCampagne | id, campagne_id, mercenaire_id, utilisateur_id facultatif, statut | Affectation temporaire d’un personnage à une aventure/joueur |
| Quete | id, nom, description, veterance_requise, actif | Fiches statiques actuellement dans `Quests.jsx` |
| Aptitude | id, code, nom, description, cout, unite_cout | Extension lorsque Bruno fournit les aptitudes complètes |
| ProgressionMercenaire | id, mercenaire_id, aptitude_id, niveau, date | Extension pour progression validée manuellement |

Ne pas attribuer définitivement tous les mercenaires au premier joueur connecté. L’équipement détaillé peut être représenté par `LigneInventaire.equipe_par`, au lieu d’une seconde liste d’armes stockée sur le personnage.

### Lieux, compteurs et économie

| Table | Champs proposés | Explication |
|---|---|---|
| Emplacement | id, compagnie_id, lieu, index, debloque, cout_deblocage, groupe_entrainement_id facultatif, role_emplacement | Lits et places d’entraînement |
| Affectation | id, emplacement_id, mercenaire_id, compteur, actif, debut, fin facultative | Occupation ; compteur entier 0–5, pas une heure de fin automatique |
| GroupeEntrainement | id, compagnie_id, nom, actif | Association instructeur/élèves |
| EtatTemps | compagnie_id, minutes_avancees | Avance globale manuelle |
| PosteBudget | id, compagnie_id, libelle, nature, montant, actif | Recettes/frais modifiables |
| MouvementTresorerie | id, compagnie_id, montant_signe, motif, operation_id, auteur_id, date | Historique des achats et autres mouvements |
| OffreMarche | id, objet_id, prix, quantite_disponible, actif, compagnie_id facultatif | Catalogue commercial et disponibilité |

Décider si le marché est global ou propre à une compagnie. Pour la trésorerie, choisir une règle unique de calcul du solde : ne pas additionner deux fois un achat en le stockant dans les frais et les mouvements sans convention.

### Historique et dotation de départ

| Table | Champs proposés | Explication |
|---|---|---|
| OperationInventaire | id, cle_idempotence, acteur_id, type, statut, recette_id facultatif, date, erreur | Une tentative d’achat/fabrication/transfert et son résultat |
| MouvementInventaire | id, operation_id, inventaire_id, objet_id, ligne_id facultatif, delta, date | Entrées/sorties traçables |
| DotationDepart | id, version, objet_id, quantite, actif | Pack de départ explicitement validé ; indépendant des constantes de démonstration |
| AttributionDotation | id, compagnie_id ou destinataire explicite, version, date | Marque une distribution déjà faite |

Le jeu local n’impose pas un inventaire personnel à chaque compte. Si Bruno en demande un, ajouter ce type et son propriétaire explicitement, sans remplacer silencieusement l’arsenal commun.

### Contraintes d’intégrité

- Quantités entières, non négatives ; exigences et résultats de recettes strictement positifs.
- Unicité recette/objet pour IngredientRecette ; unicité compagnie/utilisateur pour les adhésions.
- Une seule pile canonique par inventaire/objet empilable.
- Si des exemplaires d’armes individuels sont retenus : une ligne par exemplaire, quantité 1 ; autoriser plusieurs lignes du même modèle. Ne pas imposer une unicité inventaire/objet à toutes les lignes.
- Références obligatoires et clés étrangères pour propriétaires, modèles et recettes.
- Un seul occupant actif par emplacement ; règles de multi-affectation des mercenaires à confirmer.
- Définir archivage et suppression ; ne pas effacer un modèle encore référencé par des possessions ou un historique.

## 9. Passer du prototype à une application persistante

### Fabrication serveur

La transition React actuelle est cohérente dans sa mémoire locale. Pour plusieurs joueurs, déplacer la décision finale côté serveur :

1. Authentifier l’acteur et vérifier ses droits sur la compagnie et l’inventaire.
2. Recevoir une clé unique de tentative et la sélection ; recharger la recette active et son résultat.
3. Comparer les quantités de chaque objet, sans perdre les doublons ni tenir compte de l’ordre.
4. Vérifier le stock actuel ; consommer et produire dans une transaction avec une stratégie de concurrence adaptée.
5. Journaliser et retourner le résultat. Une même clé de tentative doit retourner le même résultat sans seconde consommation.
6. Mettre à jour le frontend et vider les slots seulement après succès. En erreur, conserver la préparation et expliquer le problème.

Tant que l’interface a cinq branches à une unité, refuser les recettes exigeant plus de cinq unités. Ne pas remplacer la comparaison des quantités par un simple test « contient tous les ingrédients ».

### Autres opérations

- Achat : disponibilité, solde, débit et attribution dans une même opération serveur.
- Transfert : débit source et crédit destination atomiques, ou déplacement de l’identité de l’exemplaire individuel.
- Utilisation : vérifier le stock, décrémenter et journaliser ; effets manuels tant qu’aucune règle automatique n’est validée.
- Équipement : contrôler accès au personnage et à l’objet ; ne pas modifier le catalogue.
- Temps : commande autorisée +10 minutes, +1 aux compteurs concernés, borne 5 ; aucune minuterie ajoutée.
- Connexion : remplacer le formulaire simulé par une authentification réelle et une résolution explicite de la compagnie active.

Les filtres d’interface, boutons masqués et états `busy` ne sont pas des permissions. Appliquer des contrôles serveur à chaque mutation et des règles de lecture par compagnie/rôle. Une clé administrateur ne doit jamais être envoyée au navigateur.

### Méthode d’intégration

Créer une couche d’accès aux données/commandes entre les composants et le backend, plutôt que disperser les appels réseau dans chaque bouton. Conserver les fonctions pures pour les tests de règles, mais faire revalider les opérations par le serveur. Charger les données au démarrage, prévoir chargement/erreur/session expirée, puis réconcilier l’état local avec les réponses serveur.

Les seeds de démonstration doivent être explicites et séparés de la production. Les identifiants actuels comme `mushroom` ou `potion-energy` peuvent devenir des codes stables, avec une table de correspondance si les clés de base sont des UUID.

## 10. Plan de travail et critères de validation

### Ordre conseillé

1. Lancer le prototype et ses tests, parcourir les lieux clés.
2. Confirmer avec Bruno les règles encore provisoires, la propriété des stocks, le rôle des joueurs/MJ et le backend choisi.
3. Implémenter comptes/compagnies/catalogue/inventaires/recettes avec migrations et permissions.
4. Brancher fabrication, achat et transfert serveur avec journal et idempotence.
5. Brancher personnages, repos, soins, entraînement et temps.
6. Finaliser trésorerie, marché, progression et vrais assets selon priorité.
7. Vérifier parcours multi-utilisateur et responsive avant déploiement.

### Tests futurs essentiels

- Rechargement : les données persistent après intégration du backend.
- Deux joueurs : accès autorisé au stock partagé, refus d’accès à une autre compagnie.
- Recette complète dans un autre ordre ; ingrédients manquants, supplémentaires, répétés et stock insuffisant.
- Deux clics, deux onglets ou demandes concurrentes : pas de potion gratuite, quantité négative ou double fabrication involontaire.
- Échec pendant une opération : ni perte partielle ni création partielle ; reprise sans duplication.
- Transfert : conservation du total et identité/durabilité de l’exemplaire si cette fonctionnalité est adoptée.
- Budget : modifier un poste n’efface pas les achats antérieurs.
- Compteurs : bornes 0–5, aucun achèvement automatique.
- Glisser-déposer et alternative clic/clavier sur desktop/mobile ; erreurs compréhensibles et résultat conservé après reset de la préparation.

## 11. Instructions pratiques pour Claude

- Répondre en français et donner à Bruno des explications concrètes.
- Lire les fichiers avant de les modifier. Distinguer une preuve de test métier d’une validation visuelle.
- Préserver la direction artistique et les règles confirmées ; ne pas inventer les prix, effets ou caractéristiques manquants.
- Ne pas confondre catalogue, stock possédé, exigences de recette et personnages.
- Ne pas supprimer de données ou médias au motif qu’ils semblent anciens. Vérifier références, sauvegarde et plan de remplacement.
- Éviter les refontes générales quand une correction ciblée suffit. Refactoriser progressivement `App.jsx` en conservant le comportement testé.
- Respecter les fichiers de packaging et les assets originaux.
- Signaler précisément le périmètre terminé et ce qui reste simulé. Un build réussi n’est pas un déploiement ni une base de données créée.

## 12. Contenu à transmettre

Fournir le dossier avec `src/`, `public/`, `tests/`, `scripts/`, `worker/`, `.openai/`, `.npmrc`, `package.json`, `package-lock.json`, `vite.config.mjs`, `index.html`, ce fichier et les documents de projet référencés.

Ne pas inclure `node_modules/`, `dist/` ou `work/` : ce sont des dépendances, résultats de build ou essais locaux. Vérifier l’absence de secrets et de données privées dans tout paquet transmis. Le guide ci-présent suffit pour la reprise du code ; aucun document externe n’est nécessaire.

Message initial à donner à Claude :

> Lis CLAUDE.md et les documents référencés, puis lance le prototype et les tests. Explique-moi ce qui fonctionne actuellement et ce qui reste simulé. Préserve l’interface et les règles confirmées. Pour la prochaine étape, aide-moi à choisir et brancher une base de données adaptée à la compagnie, aux mercenaires, aux inventaires et aux recettes, avec des modifications progressives et testées.
