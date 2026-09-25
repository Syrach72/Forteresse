-- Test de « Envoyer à la session » (migration 20260925210000). Tout est ANNULÉ à la fin.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u1 uuid;
  s uuid; sc uuid;
  cat_r uuid; cat_f uuid; cl uuid; o1 uuid; o2 uuid; o_exist uuid; rec uuid; q uuid; m uuid;
  g jsonb; n integer; n2 integer;
  rapport text := '';
begin
  select id into u1 from auth.users where id <> u_admin order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  s := session_creer('TEST ENVOI'); perform session_lancer(s);
  sc := session_creer('TEST ENVOI VIDE');

  -- contenu uniquement présent dans la base
  insert into categorie (nom, session_id) values ('TEST CAT ENVOI', null) returning id into cat_r;
  insert into categorie (nom, parent_id, session_id) values ('TEST SOUS ENVOI', cat_r, null) returning id into cat_f;
  insert into objet_catalogue (code_unique, nom, categorie_id, cout_achat_or, session_id)
    values ('TESTENVOI', 'Objet test envoi', cat_f, 10, null) returning id into o1;
  insert into objet_catalogue (code_unique, nom, categorie_id, session_id)
    values ('TESTENVOI_ING', 'Ingrédient test envoi', cat_f, null) returning id into o2;
  select id into o_exist from objet_catalogue where session_id is null and code_unique <> 'TESTENVOI' and code_unique <> 'TESTENVOI_ING' limit 1;
  insert into recette (code_unique, nom, atelier, resultat_objet_id, session_id)
    values ('TESTENVOI_R', 'Recette test envoi', 'forge', o1, null) returning id into rec;
  insert into ingredient_recette (recette_id, objet_id, quantite_requise, session_id)
    values (rec, o2, 2, null), (rec, o_exist, 1, null);

  begin
    perform session_envoyer(sc, 'objet', o1);
    rapport := rapport || E'\nKO envoi vers une session non lancée';
  exception when others then rapport := rapport || E'\nOK session non lancée refusée : ' || sqlerrm; end;

  g := session_envoyer(s, 'objet', o1);
  select count(*) into n from objet_catalogue where session_id = s and code_unique in ('TESTENVOI', 'TESTENVOI_ING');
  rapport := rapport || case when n = 2 and (g ->> 'objets_ajoutes')::int = 2 then E'\nOK envoi d''un objet : l''objet et son ingrédient inédit sont ajoutés' else E'\nKO objets ajoutés ' || n || ' / ' || coalesce(g::text, 'null') end;
  select count(*) into n from recette r join ingredient_recette i on i.recette_id = r.id
    join objet_catalogue oi on oi.id = i.objet_id
    where r.session_id = s and r.code_unique = 'TESTENVOI_R' and i.session_id = s and oi.session_id = s;
  rapport := rapport || case when n = 2 then E'\nOK la recette est copiée avec ses 2 ingrédients, tous rattachés à la session' else E'\nKO recette : ' || n || ' ingrédients' end;
  select count(*) into n from categorie c join categorie p on p.id = c.parent_id
    where c.session_id = s and c.nom = 'TEST SOUS ENVOI' and p.session_id = s and p.nom = 'TEST CAT ENVOI';
  rapport := rapport || case when n = 1 then E'\nOK la chaîne de catégories est recréée dans la session' else E'\nKO catégories ' || n end;
  select count(*) into n from objet_catalogue where session_id is null and code_unique = 'TESTENVOI';
  rapport := rapport || case when n = 1 then E'\nOK la base n''est pas modifiée' else E'\nKO base modifiée' end;
  begin
    perform session_envoyer(s, 'objet', o1);
    rapport := rapport || E'\nKO renvoi d''un objet déjà présent';
  exception when others then rapport := rapport || E'\nOK objet déjà présent refusé : ' || sqlerrm; end;

  insert into classe (nom, session_id) values ('TEST CLASSE ENVOI', null) returning id into cl;
  insert into mercenaire (nom, classe_id, veterance, session_id) values ('TEST MERC ENVOI', cl, 3, null) returning id into m;
  perform session_envoyer(s, 'mercenaire', m);
  select count(*) into n from mercenaire x join classe c on c.id = x.classe_id
    where x.session_id = s and x.nom = 'TEST MERC ENVOI' and c.session_id = s and c.nom = 'TEST CLASSE ENVOI' and x.veterance = 3;
  rapport := rapport || case when n = 1 then E'\nOK envoi d''un mercenaire avec sa classe' else E'\nKO mercenaire ' || n end;
  begin
    perform session_envoyer(s, 'mercenaire', m);
    rapport := rapport || E'\nKO mercenaire déjà présent accepté';
  exception when others then rapport := rapport || E'\nOK mercenaire déjà présent refusé'; end;

  insert into objet_catalogue (code_unique, nom, categorie_id, session_id)
    values ('TESTENVOI_REC', 'Récompense test envoi', cat_f, null) returning id into o2;
  insert into quete (nom, recompense_or, session_id) values ('TEST QUETE ENVOI', 25, null) returning id into q;
  insert into quete_recompense (quete_id, position, objet_id, quantite, session_id) values (q, 1, o2, 2, null), (q, 2, o1, 1, null);
  perform session_envoyer(s, 'quete', q);
  select count(*) into n from quete qs join quete_recompense r on r.quete_id = qs.id join objet_catalogue oo on oo.id = r.objet_id
    where qs.session_id = s and qs.nom = 'TEST QUETE ENVOI' and oo.session_id = s and not qs.en_cours and qs.terminee_le is null;
  rapport := rapport || case when n = 2 then E'\nOK envoi d''une quête : récompenses rattachées aux objets de la session, quête disponible' else E'\nKO quête ' || n end;

  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  begin
    perform session_envoyer(s, 'objet', o1);
    rapport := rapport || E'\nKO un joueur a envoyé un objet';
  exception when others then rapport := rapport || E'\nOK réservé au MJ : ' || sqlerrm; end;

  select count(*) into n from pg_proc p join pg_roles r on r.oid = p.proowner
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and r.rolname = 'postgres'
      and p.proname not in ('est_membre', 'ctx_session', 'ctx_est_base', 'session_lancee', 'is_admin',
        'invitation_valide', 'verifier_invitation', 'handle_new_user', 'enregistrer_maintien',
        '_cloner_contenu', 'session_creer', 'session_renommer', 'session_choisir', 'session_lancer',
        'session_reinitialiser', 'session_rejoindre', 'session_envoyer', '_env_categorie', '_env_objet');
  rapport := rapport || case when n = 0 then E'\nOK garde-fou : aucune autre fonction de jeu ne contourne la RLS' else E'\nKO fonctions hors liste : ' || n end;

  raise exception E'RAPPORT (tout est annulé)%', rapport;
end;
$$;
