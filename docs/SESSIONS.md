# Sessions (parties indépendantes) — conception

Décidé avec Bruno le 2026-09-25. Rien n'est partagé entre deux sessions ; le contenu
d'une session (catalogue, recettes, mercenaires, quêtes, budget, valeurs de départ)
est une COPIE de la « base de départ » faite au lancement de la session.

## Règles de Bruno
- Bruno est l'unique MJ (= administrateur global) de toutes les sessions.
- Une session a un nom choisi par Bruno. Un joueur peut appartenir à plusieurs sessions,
  choisit celle où il joue, et son nom s'affiche en haut de l'écran.
- Une session est **non lancée** tant que Bruno n'a pas cliqué une première fois sur
  « +1 Instance » ; les joueurs voient « en attente du MJ » et ne peuvent rien faire.
  Le premier clic **lance** la session (copie du contenu + état de départ), n'avance aucun
  compteur, ne s'annule pas. Le budget de l'instance ne joue qu'à partir du clic suivant.
- Ensuite la session est indépendante : Bruno peut modifier son contenu sans toucher les
  autres ; « Envoyer à la session » ajoute à la main un élément de la base à une session.
- Tout est permanent. Seul le MJ peut « remettre à zéro » : la session redevient non lancée
  (sauvegarde automatique avant, confirmation forte).
- Code d'invitation lié à une session, à usage unique, généré et envoyé par Bruno ;
  « Rejoindre une session » pour un compte existant.
- Les données de test actuelles deviennent la **« Session test »** (déjà lancée) ; la base
  de départ est une copie de ce contenu. Rien n'est effacé.

## Architecture (base de données)
- `session`, `session_membre`, `session_active` (session choisie par chaque utilisateur,
  + `contexte_base` pour Bruno éditant la base).
- Tables de **contenu** : `session_id` NULL = base de départ ; sinon copie de la session.
  categorie, classe, objet_catalogue, recette, ingredient_recette, mercenaire, quete,
  quete_recompense, budget_poste (+ `base_depart`, `base_depart_ligne` : or et arsenal de
  départ, base uniquement).
- Tables d'**état** : `session_id` NOT NULL. partie_etat, partie_journal, atelier_fabrication,
  forge_sertissage, employe, inventaire, ligne_inventaire (via inventaire), recrutement,
  entrainement_*, infirmerie_*, dortoir_reglage, quete_mercenaire.
- Isolation par RLS : `ctx_session()` = session active de l'utilisateur (membre, ou admin),
  `ctx_est_base()` = Bruno en contexte base. Fonctionne aussi pour Realtime (qui n'a pas
  d'en-têtes HTTP, d'où le choix de stocker la session active en base plutôt que dans un
  en-tête).
- Les fonctions serveur (~45) sont **propriétaires `fortress_fn`** (rôle sans BYPASSRLS,
  membre de `authenticated`) : leurs requêtes sont donc automatiquement limitées à la
  session active, sans réécrire leur code. **Toute nouvelle fonction qui touche des
  tables de session doit appartenir à `fortress_fn`** (sinon, propriétaire `postgres` =
  contourne la RLS et voit toutes les sessions). Un test SQL vérifie ce point.
- `_cloner_contenu(source, cible)` copie le contenu (avec remappage des identifiants) :
  utilisé par `session_lancer` et par la migration initiale.
- Compatible avec l'ancien client : la migration met tout le monde sur « Session test ».

## Étapes (toutes faites le 2026-09-25)
0. Sauvegarde complète (`../sauvegardes/2026-09-25_avant_sessions/`, hors dépôt).
1. Migration `20260925200000_sessions.sql` + test `tests/sessions_isolation.sql` (36 vérifications),
   appliquée en production.
2. Client (`src/Sessions.jsx`) : bandeau « Session … » avec sélecteur, écrans « en attente du
   MJ » / « choix » / « aucune session », « Rejoindre une session » (code), lancement au premier
   « +1 Instance » du MJ (sans compteur, sans « Annuler »), attente des joueurs par relecture
   toutes les 8 s puis rechargement.
3. Administration (`src/Admin.jsx`) : menu « Vous modifiez » (Base de départ ou une session),
   onglet Sessions (créer, ouvrir, jouer/diriger, renommer, inviter, remettre à zéro avec nom à
   retaper), « Envoyer à la session » (`20260925210000_session_envoyer.sql`, test
   `tests/session_envoyer.sql`), or et arsenal de départ de la base (onglet Arsenal en contexte
   Base), invitations liées à une session.
4. Vérifié sur le site : création d'une session, écran d'attente MJ, lancement (1000 Po, arsenal de
   départ, 18 lits vides, 6 quêtes, 10 postes de budget), retour à la Session test intacte, contexte
   Base, invitation, remise à zéro ; la session de test a ensuite été supprimée.

## Non vérifié à l'écran (couvert seulement par les tests SQL)
Le point de vue d'un joueur non-admin (écran d'attente, « Rejoindre une session ») et l'inscription
avec un code dans l'interface ; l'isolation Realtime entre deux navigateurs.

## À savoir
- L'arsenal de départ de la base ne reprend pas les armes serties (gemmes) de l'arsenal d'origine.
- Nouvelle fonction SQL touchant des tables de session : `alter function ... owner to fortress_fn`
  (voir le garde-fou dans les tests), sinon elle contourne l'isolation.
- Les tests SQL s'exécutent dans l'éditeur Supabase en une transaction annulée (voir la mémoire
  `reference_supabase_sql_procedure`).
