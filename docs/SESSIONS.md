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

## Étapes
0. Sauvegarde complète (fait : `../sauvegardes/2026-09-25_avant_sessions/`).
1. Migration SQL + tests d'isolation (rollback puis application).
2. Client : sélecteur de session, nom en haut, écran d'attente, invitations par session,
   « Rejoindre une session », lancement au premier +1 Instance.
3. Administration : contexte Base / session, création de session, « Envoyer à la session »,
   arsenal/or de départ de la base, remise à zéro.
4. Bascule : appliquer la migration puis publier le client, vérifier sur le site.
