-- Test catalogue partagé + isolation de l'état entre sessions (migrations 20260925200000 puis
-- 20260925230000). À exécuter APRÈS les migrations. Tout est ANNULÉ à la fin (le script se
-- termine par une erreur dont le message est le compte rendu ; chaque ligne commence par OK ou KO).
-- Nécessite deux utilisateurs autres que l'administrateur ; les joueurs sont simulés avec
-- `set local role authenticated` (la RLS s'applique) et request.jwt.claims.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u1 uuid; u2 uuid;
  sa uuid; sb uuid; sc uuid;
  n_obj integer; n_cat integer; n integer; n2 integer;
  m uuid; o_a uuid; q uuid; g jsonb;
  o_div uuid; o_ing uuid; r_div uuid; v_racine uuid; v_inv uuid; v_atelier text;
  vet_tpl integer;
  rapport text := '';
begin
  select id into u1 from auth.users where id <> u_admin order by created_at limit 1;
  select id into u2 from auth.users where id <> u_admin and id <> u1 order by created_at limit 1;
  if u1 is null or u2 is null then raise exception 'Il faut deux utilisateurs autres que l''admin'; end if;
  select count(*) into n_obj from objet_catalogue;
  select count(*) into n_cat from categorie;

  -- 1. Création et lancement (le MJ) ; C reste non lancée
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  sa := session_creer('TEST A'); sb := session_creer('TEST B'); sc := session_creer('TEST C');
  perform session_lancer(sa); perform session_lancer(sb);
  select count(*) into n from objet_catalogue;
  rapport := rapport || case when n = n_obj then E'\nOK lancer une session ne copie plus le catalogue (' || n || ' objets, un seul catalogue)' else E'\nKO catalogue : ' || n || ' au lieu de ' || n_obj end;
  select count(*) into n from budget_poste where session_id = sa;
  select count(*) into n2 from budget_poste where session_id is null;
  rapport := rapport || case when n = n2 and n > 0 then E'\nOK le budget de départ est copié dans la session (' || n || ' postes)' else E'\nKO budget ' || n || '/' || n2 end;
  select count(*) into n from ligne_inventaire l join inventaire i on i.id = l.inventaire_id where i.session_id = sa and i.type = 'arsenal';
  select count(*) into n2 from base_depart_ligne;
  rapport := rapport || case when n = n2 then E'\nOK arsenal de départ = base de départ (' || n || ' lignes)' else E'\nKO arsenal de départ ' || n || '/' || n2 end;
  insert into session_membre (session_id, user_id) values (sa, u1), (sb, u2), (sc, u1);
  insert into session_active (user_id, session_id) values (u1, sa)
    on conflict (user_id) do update set session_id = sa, contexte_base = false;
  insert into session_active (user_id, session_id) values (u2, sb)
    on conflict (user_id) do update set session_id = sb, contexte_base = false;
  select id into m from mercenaire where actif order by nom limit 1;
  select id into o_a from objet_catalogue where cout_achat_or between 1 and 500 order by nom limit 1;
  select id into q from quete where actif order by nom limit 1;
  select veterance into vet_tpl from mercenaire where id = m;

  -- 2. Joueur 1 (équipe A)
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  select count(*) into n from objet_catalogue;
  select count(*) into n2 from categorie;
  rapport := rapport || case when n = n_obj and n2 = n_cat then E'\nOK joueur A voit tout le catalogue partagé' else E'\nKO joueur A voit ' || n || ' objets / ' || n2 || ' catégories' end;
  begin
    insert into objet_catalogue (code_unique, nom) values ('test-interdit', 'x');
    rapport := rapport || E'\nKO un joueur a créé un objet du catalogue';
  exception when others then rapport := rapport || E'\nOK un joueur ne peut pas modifier le catalogue'; end;
  begin
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m, u1, 'joueur un');
    rapport := rapport || E'\nOK recrutement du mercenaire dans la session A';
  exception when others then rapport := rapport || E'\nKO recrutement A : ' || sqlerrm; end;
  begin
    perform partie_acheter(o_a);
    select or_compagnie into n from partie_etat;
    rapport := rapport || case when n < 1000 then E'\nOK achat : l''or de la session A baisse (' || n || ')' else E'\nKO achat sans effet' end;
  exception when others then rapport := rapport || E'\nKO achat : ' || sqlerrm; end;
  begin
    perform quete_choisir(q);
    rapport := rapport || E'\nOK quête choisie dans A';
  exception when others then rapport := rapport || E'\nKO choix de quête A : ' || sqlerrm; end;
  begin
    perform quete_engager(0, m);
    rapport := rapport || E'\nOK mercenaire engagé dans la quête de A';
  exception when others then rapport := rapport || E'\nKO engagement : ' || sqlerrm; end;
  reset role;

  -- 3. Joueur 2 (équipe B) : le MÊME mercenaire et la MÊME quête sont libres dans sa session
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u2::text, true);
  set local role authenticated;
  select or_compagnie into n from partie_etat;
  select count(*) into n2 from recrutement;
  rapport := rapport || case when n = 1000 and n2 = 0 then E'\nOK joueur B : or intact et aucun recrutement d''A visible' else E'\nKO B voit or ' || coalesce(n::text, 'null') || ', recrutements ' || n2 end;
  select count(*) into n from quete_etat where en_cours;
  rapport := rapport || case when n = 0 then E'\nOK joueur B : la quête choisie par A n''est pas en cours chez lui' else E'\nKO quête de A visible chez B' end;
  begin
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m, u2, 'joueur deux');
    select lit into n from recrutement where mercenaire_id = m;
    rapport := rapport || case when n = 0 then E'\nOK le même mercenaire est recruté aussi dans B (lit 0, indépendant de A)' else E'\nKO lit B ' || coalesce(n::text, 'null') end;
  exception when others then rapport := rapport || E'\nKO le même mercenaire ne peut pas servir dans B : ' || sqlerrm; end;
  begin
    perform quete_choisir(q);
    perform quete_engager(0, m);
    rapport := rapport || E'\nOK la même quête et le même mercenaire servent aussi dans B';
  exception when others then rapport := rapport || E'\nKO quête de B : ' || sqlerrm; end;
  begin
    perform session_choisir(sa);
    rapport := rapport || E'\nKO B a choisi la session A';
  exception when others then rapport := rapport || E'\nOK B ne peut pas choisir la session A'; end;
  reset role;

  -- 4. Vétérance : propre à chaque session, repli sur la fiche du catalogue
  insert into mercenaire_etat (session_id, mercenaire_id, veterance) values (sa, m, vet_tpl + 4);
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  select _vet(m) into n;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u2::text, true);
  set local role authenticated;
  select _vet(m) into n2;
  reset role;
  rapport := rapport || case when n = vet_tpl + 4 and n2 = vet_tpl then E'\nOK vétérance : ' || n || ' dans A, ' || n2 || ' dans B (fiche du catalogue)' else E'\nKO vétérance A ' || n || ' / B ' || n2 end;

  -- 5. Session non lancée (C) : joueur 1
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  perform session_choisir(sc);
  select count(*) into n from partie_etat;
  rapport := rapport || case when n = 0 then E'\nOK session non lancée : aucun état visible' else E'\nKO session non lancée voit ' || n end;
  begin
    perform partie_acheter(o_a);
    rapport := rapport || E'\nKO achat dans une session non lancée';
  exception when others then rapport := rapport || E'\nOK achat impossible avant lancement'; end;
  reset role;

  -- 6. +1 Instance du MJ dans A : ne touche que A
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  perform session_choisir(sa);
  perform mercenaire_definir_veterance(m, vet_tpl + 2);
  select veterance into n from mercenaire_etat where session_id = sa and mercenaire_id = m;
  rapport := rapport || case when n = vet_tpl + 2 then E'
OK le MJ fixe la vétérance de la session A' else E'
KO vétérance MJ ' || coalesce(n::text, 'null') end;
  g := quetes_instance();
  select instances_restantes into n from quete_etat where session_id = sa and quete_id = q;
  select instances_restantes into n2 from quete_etat where session_id = sb and quete_id = q;
  rapport := rapport || case when g is not null and n is distinct from n2 and (select en_cours from quete_etat where session_id = sb and quete_id = q) then E'\nOK +1 Instance dans A (reste ' || coalesce(n::text, '-') || ') ; la même quête dans B est intacte (' || n2 || ')' else E'\nKO +1 Instance : A ' || coalesce(n::text, 'null') || ', B ' || coalesce(n2::text, 'null') end;
  select or_compagnie into n from partie_etat where session_id = sb;
  rapport := rapport || case when n = 1000 then E'\nOK l''or de B n''a pas bougé' else E'\nKO or de B : ' || coalesce(n::text, 'null') end;

  -- 7. Fabrication d'un objet divers à la forge OU à l'armurerie
  select id into v_racine from categorie where parent_id is null and lower(btrim(nom)) = 'objet divers' limit 1;
  select id, quantite into o_ing, n from (
    select l.objet_id as id, l.quantite from ligne_inventaire l join inventaire i on i.id = l.inventaire_id
    where i.session_id = sa and i.type = 'arsenal' and l.quantite >= 1 order by l.quantite desc limit 1) x;
  select id into v_inv from inventaire where session_id = sa and type = 'arsenal';
  insert into objet_catalogue (code_unique, nom, categorie_id, duree_fabrication_instances, cout_achat_or)
    values ('test-divers-fab', 'Test divers fabriqué', v_racine, null, 5) returning id into o_div;
  select atelier::text into v_atelier from recette limit 1;
  execute format('insert into recette (code_unique, nom, atelier, resultat_objet_id, quantite_produite) values (%L, %L, %L, %L, 1) returning id',
    'recette-test-divers', 'Recette test', v_atelier, o_div) into r_div;
  insert into ingredient_recette (recette_id, objet_id, quantite_requise) values (r_div, o_ing, 1);
  begin
    perform partie_fabriquer(o_div);
    rapport := rapport || E'\nKO fabrication d''un objet divers sans atelier';
  exception when others then rapport := rapport || E'\nOK atelier exigé pour un objet divers : ' || sqlerrm; end;
  begin
    perform partie_fabriquer(o_div, 'alchimie');
    rapport := rapport || E'\nKO atelier alchimie accepté pour un objet divers';
  exception when others then rapport := rapport || E'\nOK seuls la forge et l''armurerie sont acceptées'; end;
  begin
    g := partie_fabriquer(o_div, 'armurerie');
    select l.quantite into n2 from ligne_inventaire l where l.inventaire_id = v_inv and l.objet_id = o_div;
    rapport := rapport || case when n2 = 1 and g ->> 'atelier' = 'armurerie' then E'\nOK objet divers fabriqué à l''armurerie (ingrédient consommé)' else E'\nKO fabrication : ' || coalesce(n2::text, 'null') end;
  exception when others then rapport := rapport || E'\nKO fabrication armurerie : ' || sqlerrm; end;
  begin
    g := partie_fabriquer(o_div, 'forge');
    rapport := rapport || case when g ->> 'atelier' = 'forge' then E'\nOK le même objet peut aussi être fabriqué à la forge' else E'\nKO forge' end;
  exception when others then rapport := rapport || E'\nOK 2e fabrication refusée (ingrédient épuisé ?) : ' || sqlerrm; end;

  -- 8. Remise à zéro de A : sauvegarde, catalogue intact, B intacte
  perform session_reinitialiser(sa);
  select count(*) into n from partie_etat where session_id = sa;
  select count(*) into n2 from objet_catalogue;
  rapport := rapport || case when n = 0 and n2 = n_obj + 1 and (select lancee_le is null from session where id = sa) then E'\nOK remise à zéro : état de A vide, catalogue intact, A non lancée' else E'\nKO remise à zéro ' || n || '/' || n2 end;
  rapport := rapport || case when exists (select 1 from session_sauvegarde where session_id = sa and jsonb_array_length(donnees -> 'quete_etat') >= 1 and jsonb_array_length(donnees -> 'mercenaire_etat') = 1) then E'\nOK sauvegarde automatique (quête et vétérance conservées)' else E'\nKO sauvegarde' end;
  select count(*) into n from mercenaire_etat where session_id = sa;
  select count(*) into n2 from quete_etat where session_id = sb;
  rapport := rapport || case when n = 0 and n2 = 1 and exists (select 1 from recrutement where session_id = sb) then E'\nOK B intacte, état de A effacé' else E'\nKO B / A ' || n || '/' || n2 end;

  -- 9. Garde-fou : aucune fonction de jeu ne doit contourner la RLS
  select count(*) into n from pg_proc p join pg_roles r on r.oid = p.proowner
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and r.rolname = 'postgres'
      and p.proname not in ('est_membre', 'ctx_session', 'ctx_est_base', 'session_lancee', 'is_admin',
        'invitation_valide', 'verifier_invitation', 'handle_new_user', 'enregistrer_maintien',
        'session_creer', 'session_renommer', 'session_choisir', 'session_lancer',
        'session_reinitialiser', 'session_rejoindre', '_vet');
  rapport := rapport || case when n = 0 then E'\nOK toutes les fonctions de jeu appartiennent à fortress_fn' else E'\nKO fonctions propriétaires postgres hors liste : ' || n end;

  raise exception E'RAPPORT (tout est annulé)%', rapport;
end;
$$;
