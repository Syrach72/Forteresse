# Sessions (parties indépendantes) — conception

Décidé avec Bruno le 2026-09-25. L'ÉTAT de jeu n'est jamais partagé entre deux sessions.
**Le catalogue (objets, catégories, classes, recettes, mercenaires, quêtes) est UN SEUL,
commun à toutes les sessions** (migration `20260925230000_catalogue_partage.sql`, même
jour) : ce que Bruno crée ou modifie est visible partout. Seuls le budget, l'or et l'arsenal
de départ (base de départ) sont copiés dans une session à son lancement.

## Règles de Bruno
- Bruno est l'unique MJ (= administrateur global) de toutes les sessions.
- Une session a un nom choisi par Bruno. Un joueur peut appartenir à plusieurs sessions,
  choisit celle où il joue, et son nom s'affiche en haut de l'écran.
- Une session est **non lancée** tant que Bruno n'a pas cliqué une première fois sur
  « +1 Instance » ; les joueurs voient « en attente du MJ » et ne peuvent rien faire.
  Le premier clic **lance** la session (copie du contenu + état de départ), n'avance aucun
  compteur, ne s'annule pas. Le budget de l'instance ne joue qu'à partir du clic suivant.
- Ensuite l'état de la session est indépendant (or, arsenal, recrutements, vétérance, quêtes…).
  Un même mercenaire ou objet peut servir dans plusieurs sessions.
- Tout est permanent. Seul le MJ peut « remettre à zéro » : la session redevient non lancée
  (sauvegarde automatique avant, confirmation forte).
- Code d'invitation lié à une session, à usage unique, généré et envoyé par Bruno ;
  « Rejoindre une session » pour un compte existant.
- Les données de test actuelles sont la **« Session test »** (déjà lancée). Son contenu a été
  fusionné dans le catalogue partagé (union ; en cas de conflit la Session test l'emporte).

## Architecture (base de données)
- `session`, `session_membre`, `session_active` (session choisie par chaque utilisateur,
  + `contexte_base` pour Bruno éditant la base).
- **Catalogue partagé** (lecture pour tous, écriture MJ) : categorie, classe, objet_catalogue,
  recette, ingredient_recette, mercenaire, quete, quete_recompense. Plus de `session_id`.
- **État par session** : `mercenaire_etat` (vétérance ; repli sur la valeur de la fiche, fonction
  `_vet()`, modifiée par `mercenaire_definir_veterance`), `quete_etat` (en_cours, instances
  restantes, terminée), plus partie_etat, partie_journal, atelier_fabrication, forge_sertissage,
  employe, inventaire, ligne_inventaire, recrutement, entrainement_*, infirmerie_*,
  dortoir_reglage, quete_mercenaire. Unicités « par session » (ex. recrutement (session, mercenaire)).
- `budget_poste` : lignes de départ (session_id NULL) copiées dans la session au lancement ;
  `base_depart`, `base_depart_ligne` : or et arsenal de départ.
- Isolation par RLS : `ctx_session()` = session active de l'utilisateur (membre, ou admin),
  `ctx_est_base()` = Bruno en contexte base. Fonctionne aussi pour Realtime (qui n'a pas
  d'en-têtes HTTP, d'où le choix de stocker la session active en base plutôt que dans un
  en-tête).
- Les fonctions serveur (~45) sont **propriétaires `fortress_fn`** (rôle sans BYPASSRLS,
  membre de `authenticated`) : leurs requêtes sont donc automatiquement limitées à la
  session active, sans réécrire leur code. **Toute nouvelle fonction qui touche des
  tables de session doit appartenir à `fortress_fn`** (sinon, propriétaire `postgres` =
  contourne la RLS et voit toutes les sessions). Un test SQL vérifie ce point.
- `_cloner_contenu` et `session_envoyer` ont été supprimés (plus de copie de contenu).
- « Objet divers » : les objets qui ont une recette se fabriquent à la forge OU à l'armurerie
  (`partie_fabriquer(p_objet, p_atelier)`, atelier exigé pour cette rubrique) ; bouton « Catalogue
  des objets » sur les deux pages.
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

## Catalogue partagé (2026-09-25)
Migration appliquée en production, 40 vérifications OK à blanc (`tests/sessions_isolation.sql`
réécrit) et 28 après application. Sauvegarde avant : `2026-09-25_avant_catalogue_partage` (hors
dépôt). Les anciens tests SQL (quetes_instances, entrainement_regles…) supposent l'ancien modèle : à
revalider avant réutilisation.
