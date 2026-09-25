-- Test d'isolation entre sessions (migration 20260925200000). À exécuter APRÈS la migration.
-- Tout est ANNULÉ à la fin (le script se termine par une erreur dont le message est le
-- compte rendu ; chaque ligne commence par OK ou KO). Nécessite un utilisateur autre que
-- l'administrateur ; les joueurs sont simulés avec `set local role authenticated` (la RLS
-- s'applique) et request.jwt.claims.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u1 uuid; u2 uuid;
  s_test uuid; sa uuid; sb uuid; sc uuid;
  n_base_obj integer; n_base_merc integer; n integer; n2 integer;
  m_a uuid; m_b uuid; o_a uuid; q_a uuid; q_b uuid; g jsonb;
  or_test_avant integer; rec_test_avant integer; obj_test_avant integer;
  or_a integer; or_b integer;
  rapport text := '';
begin
  select id into s_test from session where nom = 'Session test';
  select id into u1 from auth.users where id <> u_admin order by created_at limit 1;
  select id into u2 from auth.users where id <> u_admin and id <> u1 order by created_at limit 1;
  if u1 is null or u2 is null then raise exception 'Il faut deux utilisateurs autres que l''admin'; end if;

  -- 0. Migration : Session test et base de départ
  select count(*) into n_base_obj from objet_catalogue where session_id is null;
  select count(*) into obj_test_avant from objet_catalogue where session_id = s_test;
  select count(*) into n_base_merc from mercenaire where session_id is null;
  select count(*) into rec_test_avant from recrutement where session_id = s_test;
  select or_compagnie into or_test_avant from partie_etat where session_id = s_test;
  rapport := rapport || case when n_base_obj = obj_test_avant and obj_test_avant > 0 then E'\nOK base de départ = copie du contenu de la Session test (' || n_base_obj || ' objets)' else E'\nKO base ' || n_base_obj || ' / test ' || obj_test_avant end;
  select count(*) into n from objet_catalogue where session_id is null and id in (select id from objet_catalogue where session_id = s_test);
  rapport := rapport || case when n = 0 then E'\nOK la copie a de nouveaux identifiants' else E'\nKO identifiants partagés : ' || n end;
  select count(*) into n from objet_catalogue o where o.session_id = s_test and o.categorie_id not in (select id from categorie where session_id = s_test);
  rapport := rapport || case when n = 0 then E'\nOK liens des objets de la Session test intacts' else E'\nKO liens cassés : ' || n end;
  select count(*) into n from objet_catalogue o where o.session_id is null and o.categorie_id not in (select id from categorie where session_id is null);
  rapport := rapport || case when n = 0 then E'\nOK liens des objets de la base intacts' else E'\nKO liens cassés dans la base : ' || n end;
  select count(*) into n from ingredient_recette i where i.session_id is null and (i.recette_id not in (select id from recette where session_id is null) or i.objet_id not in (select id from objet_catalogue where session_id is null));
  rapport := rapport || case when n = 0 then E'\nOK recettes de la base cohérentes' else E'\nKO recettes de la base : ' || n end;

  -- 1. Création et lancement de deux sessions (l'administrateur), une non lancée
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  sa := session_creer('TEST A'); sb := session_creer('TEST B'); sc := session_creer('TEST C');
  begin
    perform session_creer('test a');
    rapport := rapport || E'\nKO deux sessions de même nom';
  exception when others then rapport := rapport || E'\nOK nom de session unique : ' || sqlerrm; end;
  g := session_lancer(sa); perform session_lancer(sb);
  select count(*) into n from objet_catalogue where session_id = sa;
  select count(*) into n2 from objet_catalogue where session_id = sb;
  rapport := rapport || case when n = n_base_obj and n2 = n_base_obj then E'\nOK lancement : chaque session a sa copie du contenu' else E'\nKO copies ' || n || ' / ' || n2 end;
  select or_compagnie into or_a from partie_etat where session_id = sa;
  rapport := rapport || case when or_a = 1000 then E'\nOK état de départ : or 1000' else E'\nKO or de départ ' || coalesce(or_a::text, 'null') end;
  begin
    perform session_lancer(sa);
    rapport := rapport || E'\nKO relancer une session lancée';
  exception when others then rapport := rapport || E'\nOK relancement refusé : ' || sqlerrm; end;
  insert into session_membre (session_id, user_id) values (sa, u1), (sb, u2), (sc, u1);
  insert into session_active (user_id, session_id) values (u1, sa)
    on conflict (user_id) do update set session_id = sa, contexte_base = false;
  insert into session_active (user_id, session_id) values (u2, sb)
    on conflict (user_id) do update set session_id = sb, contexte_base = false;
  select id into m_a from mercenaire where session_id = sa order by nom limit 1;
  select id into m_b from mercenaire where session_id = sb order by nom limit 1;
  select id into o_a from objet_catalogue where session_id = sa and cout_achat_or between 1 and 500 order by nom limit 1;
  select id into q_a from quete where session_id = sa order by nom limit 1;
  select id into q_b from quete where session_id = sb order by nom limit 1;

  -- 2. Joueur 1 (équipe A)
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  begin
    perform session_choisir(sb);
    rapport := rapport || E'\nKO un joueur a choisi la session d''une autre équipe';
  exception when others then rapport := rapport || E'\nOK session d''une autre équipe refusée : ' || sqlerrm; end;
  select count(*) into n from objet_catalogue;
  select count(*) into n2 from objet_catalogue where session_id <> sa;
  rapport := rapport || case when n = n_base_obj and n2 = 0 then E'\nOK joueur A : ne voit que le catalogue de sa session' else E'\nKO joueur A voit ' || n || ' objets dont ' || n2 || ' d''ailleurs' end;
  select count(*) into n from partie_etat;
  rapport := rapport || case when n = 1 then E'\nOK joueur A : une seule trésorerie visible' else E'\nKO trésoreries visibles : ' || n end;
  begin
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m_b, u1, 'intrus');
    rapport := rapport || E'\nKO recrutement d''un mercenaire d''une autre session';
  exception when others then rapport := rapport || E'\nOK mercenaire d''une autre session refusé : ' || sqlerrm; end;
  begin
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m_a, u1, 'joueur un');
    select lit into n from recrutement where mercenaire_id = m_a;
    rapport := rapport || case when n = 0 then E'\nOK recrutement dans sa session, premier lit' else E'\nKO lit ' || coalesce(n::text, 'null') end;
  exception when others then rapport := rapport || E'\nKO recrutement refusé : ' || sqlerrm; end;
  begin
    perform partie_acheter(o_a);
    select or_compagnie into n from partie_etat;
    rapport := rapport || case when n < 1000 then E'\nOK achat : l''or de la session A baisse (' || n || ')' else E'\nKO achat sans effet' end;
  exception when others then rapport := rapport || E'\nKO achat : ' || sqlerrm; end;
  begin
    perform quete_choisir(q_a);
    rapport := rapport || E'\nOK quête choisie dans A';
  exception when others then rapport := rapport || E'\nKO choix de quête : ' || sqlerrm; end;
  reset role;

  -- 3. Joueur 2 (équipe B) : rien de ce qu'a fait A n'est visible ni actif
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u2::text, true);
  set local role authenticated;
  select or_compagnie into n from partie_etat;
  select count(*) into n2 from recrutement;
  rapport := rapport || case when n = 1000 and n2 = 0 then E'\nOK joueur B : or intact (1000) et aucun recrutement d''A visible' else E'\nKO B voit or ' || coalesce(n::text, 'null') || ', recrutements ' || n2 end;
  begin
    perform quete_choisir(q_b);
    rapport := rapport || E'\nOK B choisit sa quête pendant que A a la sienne (une par session)';
  exception when others then rapport := rapport || E'\nKO quête de B : ' || sqlerrm; end;
  begin
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m_b, u2, 'joueur deux');
    select lit into n from recrutement where mercenaire_id = m_b;
    rapport := rapport || case when n = 0 then E'\nOK B : son premier lit est le lit 0 (indépendant de A)' else E'\nKO lit B ' || coalesce(n::text, 'null') end;
  exception when others then rapport := rapport || E'\nKO recrutement B : ' || sqlerrm; end;
  begin
    perform session_choisir(sa);
    rapport := rapport || E'\nKO B a choisi la session A';
  exception when others then rapport := rapport || E'\nOK B ne peut pas choisir la session A'; end;
  reset role;

  -- 4. Session non lancée (C) : joueur 1
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  perform session_choisir(sc);
  select count(*) into n from objet_catalogue;
  select count(*) into n2 from partie_etat;
  rapport := rapport || case when n = 0 and n2 = 0 then E'\nOK session non lancée : aucun contenu ni état visible' else E'\nKO session non lancée voit ' || n || '/' || n2 end;
  begin
    perform partie_acheter(o_a);
    rapport := rapport || E'\nKO achat dans une session non lancée';
  exception when others then rapport := rapport || E'\nOK achat impossible avant lancement : ' || sqlerrm; end;
  begin
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m_a, u1, 'x');
    rapport := rapport || E'\nKO recrutement avant lancement';
  exception when others then rapport := rapport || E'\nOK recrutement impossible avant lancement'; end;
  reset role;

  -- 5. +1 Instance du MJ dans A : ne touche que A
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  perform session_choisir(sa);
  g := quetes_instance();
  select count(*) into n from quete where session_id = sa and en_cours;
  select count(*) into n2 from quete where session_id = sb and en_cours;
  rapport := rapport || case when g is not null and n = 0 and n2 = 1 then E'\nOK +1 Instance dans A : quête de A résolue, quête de B intacte' else E'\nKO +1 Instance : A en cours ' || n || ', B en cours ' || n2 end;
  select or_compagnie into or_b from partie_etat where session_id = sb;
  rapport := rapport || case when or_b = 1000 then E'\nOK l''or de B n''a pas bougé' else E'\nKO or de B : ' || coalesce(or_b::text, 'null') end;

  -- 6. Invitation liée à une session + « rejoindre »
  perform session_choisir(sb);
  insert into invitation (code, note) values ('TESTCODE', 'test');
  rapport := rapport || case when (select session_id from invitation where code = 'TESTCODE') = sb then E'\nOK le code d''invitation est lié à la session active du MJ' else E'\nKO session du code' end;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  perform session_rejoindre('test-code');
  rapport := rapport || case when exists (select 1 from session_membre where session_id = sb and user_id = u1) then E'\nOK rejoindre une session avec un code' else E'\nKO rejoindre' end;
  begin
    perform session_rejoindre('TESTCODE');
    rapport := rapport || E'\nKO code réutilisé';
  exception when others then rapport := rapport || E'\nOK code à usage unique : ' || sqlerrm; end;

  -- 7. Base de départ : le MJ y écrit sans toucher les sessions
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  perform session_choisir(null);
  set local role authenticated;
  insert into categorie (nom) values ('TEST base seulement');
  select count(*) into n from categorie where session_id is null and nom = 'TEST base seulement';
  reset role;
  select count(*) into n2 from categorie where session_id is not null and nom = 'TEST base seulement';
  rapport := rapport || case when n = 1 and n2 = 0 then E'\nOK ajout dans la base : absent des sessions déjà lancées' else E'\nKO ajout base ' || n || '/' || n2 end;

  -- 8. Remise à zéro de A : sauvegarde, session non lancée, B et Session test intactes
  perform session_reinitialiser(sa);
  select count(*) into n from partie_etat where session_id = sa;
  select count(*) into n2 from objet_catalogue where session_id = sa;
  rapport := rapport || case when n = 0 and n2 = 0 and (select lancee_le is null from session where id = sa) then E'\nOK remise à zéro : A vide et non lancée' else E'\nKO remise à zéro ' || n || '/' || n2 end;
  rapport := rapport || case when exists (select 1 from session_sauvegarde where session_id = sa and jsonb_array_length(donnees -> 'recrutement') = 1) then E'\nOK sauvegarde automatique avant remise à zéro (1 recrutement conservé)' else E'\nKO sauvegarde' end;
  select count(*) into n from partie_etat where session_id = sb;
  select count(*) into n2 from recrutement where session_id = sb;
  rapport := rapport || case when n = 1 and n2 = 1 then E'\nOK session B intacte après la remise à zéro de A' else E'\nKO B touchée ' || n || '/' || n2 end;
  g := session_lancer(sa);
  rapport := rapport || case when exists (select 1 from categorie where session_id = sa and nom = 'TEST base seulement') then E'\nOK après relancement, A reprend la base actuelle (y compris le nouvel ajout)' else E'\nKO relancement' end;
  select count(*) into n from objet_catalogue where session_id = s_test;
  select count(*) into n2 from recrutement where session_id = s_test;
  select or_compagnie into or_a from partie_etat where session_id = s_test;
  rapport := rapport || case when n = obj_test_avant and n2 = rec_test_avant and or_a = or_test_avant then E'\nOK Session test inchangée (' || n || ' objets, ' || n2 || ' recrutements, or ' || or_a || ')' else E'\nKO Session test modifiée' end;

  -- 9. Compatibilité ancien client : un compte existant voit la Session test
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  perform session_choisir(s_test);
  set local role authenticated;
  select count(*) into n from objet_catalogue;
  select count(*) into n2 from recrutement;
  reset role;
  rapport := rapport || case when n = obj_test_avant and n2 = rec_test_avant then E'\nOK compatibilité : le MJ retrouve son état actuel dans la Session test' else E'\nKO compatibilité ' || n || '/' || n2 end;

  -- 10. Garde-fou : aucune fonction de jeu ne doit contourner la RLS
  select count(*) into n from pg_proc p join pg_roles r on r.oid = p.proowner
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and r.rolname = 'postgres'
      and p.proname not in ('est_membre', 'ctx_session', 'ctx_est_base', 'session_lancee', 'is_admin',
        'invitation_valide', 'verifier_invitation', 'handle_new_user', 'enregistrer_maintien',
        '_cloner_contenu', 'session_creer', 'session_renommer', 'session_choisir', 'session_lancer',
        'session_reinitialiser', 'session_rejoindre');
  rapport := rapport || case when n = 0 then E'\nOK toutes les fonctions de jeu appartiennent à fortress_fn' else E'\nKO fonctions propriétaires postgres hors liste : ' || n end;

  raise exception E'RAPPORT (tout est annulé)%', rapport;
end;
$$;
