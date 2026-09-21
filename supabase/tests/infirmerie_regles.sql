-- Test des regles de l'infirmerie (migration 20260921120000). Meme principe que
-- entrainement_regles.sql : faux mercenaires, tout est ANNULE a la fin (le
-- script se termine volontairement par une erreur dont le message est le
-- compte rendu ; chaque ligne commence par OK ou KO).
-- ATTENTION : l'editeur SQL s'execute en administrateur ; les DELETE/UPDATE
-- ont ici une clause WHERE car l'application, elle, les refuse sans (voir
-- 20260921110000). Verifier aussi par un appel REST reel.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u_autre constant uuid := '00000000-0000-4000-8000-000000000001';
  c1 uuid;
  m_a uuid;
  m_b uuid;
  m_c uuid;
  g4 jsonb;
  g5 jsonb;
  v integer;
  n integer;
  rapport text := '';
begin
  select id into c1 from classe order by nom limit 1;
  delete from infirmerie_place where position >= 0;
  delete from entrainement_place where position >= 0;
  update infirmerie_reglage set places = 2 where places >= 2;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST a', c1, 6) returning id into m_a;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST b', c1, 2) returning id into m_b;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST c', c1, 1) returning id into m_c;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values
    (m_a, u_admin, 'test'), (m_b, u_admin, 'test'), (m_c, u_admin, 'test');

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  begin
    perform infirmerie_soigner(m_a);
    select restant into v from infirmerie_place where mercenaire_id = m_a and position = 0;
    rapport := rapport || case when v = 5 then E'\nOK soigner : premier lit, delai de 5' else E'\nKO soigner : restant ' || coalesce(v::text, 'aucun') end;
  exception when others then
    rapport := rapport || E'\nKO soigner refuse : ' || sqlerrm;
  end;
  begin
    perform infirmerie_soigner(m_a);
    rapport := rapport || E'\nKO deja a l''infirmerie accepte';
  exception when others then
    rapport := rapport || E'\nOK deja a l''infirmerie refuse : ' || sqlerrm;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_autre)::text, true);
  perform set_config('request.jwt.claim.sub', u_autre::text, true);
  begin
    perform infirmerie_soigner(m_b);
    rapport := rapport || E'\nKO un autre joueur a envoye mon mercenaire';
  exception when others then
    rapport := rapport || E'\nOK envoi refuse a un autre joueur : ' || sqlerrm;
  end;
  begin
    perform infirmerie_renvoyer(m_a);
    rapport := rapport || E'\nKO un autre joueur a rappele mon mercenaire';
  exception when others then
    rapport := rapport || E'\nOK rappel refuse a un autre joueur : ' || sqlerrm;
  end;
  begin
    perform infirmerie_instance();
    rapport := rapport || E'\nKO un joueur a fait avancer l''infirmerie';
  exception when others then
    rapport := rapport || E'\nOK +1 Instance reserve a l''admin : ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  -- Lits : 2 debloques, un troisieme a debloquer.
  perform infirmerie_soigner(m_b);
  begin
    perform infirmerie_soigner(m_c);
    rapport := rapport || E'\nKO troisieme mercenaire accepte sans lit';
  exception when others then
    rapport := rapport || E'\nOK aucun lit libre : ' || sqlerrm;
  end;
  v := infirmerie_debloquer_place();
  perform infirmerie_soigner(m_c);
  select position into n from infirmerie_place where mercenaire_id = m_c;
  rapport := rapport || case when v = 3 and n = 2 then E'\nOK troisieme lit debloque et utilise' else E'\nKO lits ' || v || ' position ' || coalesce(n::text, 'aucune') end;
  begin
    perform infirmerie_debloquer_place();
    rapport := rapport || E'\nKO quatrieme lit debloque';
  exception when others then
    rapport := rapport || E'\nOK pas de quatrieme lit : ' || sqlerrm;
  end;

  -- Exclusivite avec l'entrainement.
  delete from infirmerie_place where position >= 0;
  begin
    perform entrainement_choisir_instructeur(m_a);
    perform infirmerie_soigner(m_a);
    rapport := rapport || E'\nKO un instructeur a ete envoye a l''infirmerie';
  exception when others then
    rapport := rapport || E'\nOK a l''entrainement : pas a l''infirmerie : ' || sqlerrm;
  end;
  delete from entrainement_place where position >= 0;
  perform infirmerie_soigner(m_b);
  begin
    perform entrainement_choisir_instructeur(m_b);
    rapport := rapport || E'\nKO un mercenaire soigne est devenu instructeur';
  exception when others then
    rapport := rapport || E'\nOK a l''infirmerie : pas a l''entrainement : ' || sqlerrm;
  end;
  delete from infirmerie_place where position >= 0;

  -- +1 Instance : 5 -> 4 -> 3 -> 2 -> 1 -> 0 (sort).
  perform infirmerie_soigner(m_a);
  perform infirmerie_instance();
  perform infirmerie_instance();
  perform infirmerie_instance();
  g4 := infirmerie_instance();
  select restant into v from infirmerie_place where mercenaire_id = m_a;
  rapport := rapport || case when v = 1 then E'\nOK apres 4 instances : reste 1' else E'\nKO apres 4 instances : ' || coalesce(v::text, 'sorti') end;
  g5 := infirmerie_instance();
  select count(*) into n from infirmerie_place where mercenaire_id = m_a;
  rapport := rapport || case when n = 0 and (g5 -> 0 ->> 'sorti') = 'true' then E'\nOK 5e instance : sorti, retrouve sa place au dortoir' else E'\nKO 5e instance : encore ' || n end;

  -- Annuler : la derniere instance, puis la precedente.
  perform infirmerie_annuler_instance(g5);
  select restant into v from infirmerie_place where mercenaire_id = m_a;
  rapport := rapport || case when v = 1 then E'\nOK annulation : replace avec 1' else E'\nKO annulation : ' || coalesce(v::text, 'absent') end;
  perform infirmerie_annuler_instance(g4);
  select restant into v from infirmerie_place where mercenaire_id = m_a;
  rapport := rapport || case when v = 2 then E'\nOK annulation precedente : compteur 2' else E'\nKO annulation precedente : ' || coalesce(v::text, 'absent') end;

  -- Rappel avant la fin (recruteur).
  perform infirmerie_renvoyer(m_a);
  select count(*) into n from infirmerie_place where mercenaire_id = m_a;
  rapport := rapport || case when n = 0 then E'\nOK rappel au dortoir avant la fin' else E'\nKO rappel : encore la' end;

  -- Renvoye de la compagnie : quitte l'infirmerie.
  perform infirmerie_soigner(m_a);
  delete from recrutement where mercenaire_id = m_a;
  select count(*) into n from infirmerie_place where mercenaire_id = m_a;
  rapport := rapport || case when n = 0 then E'\nOK renvoye de la compagnie : quitte l''infirmerie' else E'\nKO reste a l''infirmerie' end;

  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
exception when others then
  raise exception E'%  || RAPPORT :%', sqlerrm, rapport;
end;
$$;
