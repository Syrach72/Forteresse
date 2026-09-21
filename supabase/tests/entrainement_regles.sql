-- Test des regles du terrain d'entrainement (migration 20260921100000).
-- A coller dans l'editeur SQL de Supabase. Il cree de faux mercenaires, teste
-- chaque regle, puis S'ANNULE TOUT SEUL (il se termine volontairement par une
-- erreur : aucune donnee reelle n'est touchee ni conservee). Le compte de test
-- est l'administrateur ; un joueur inexistant simule un « autre joueur ».
-- Lire le compte rendu dans le message d'erreur final : chaque ligne commence
-- par OK ou KO.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u_autre constant uuid := '00000000-0000-4000-8000-000000000001';
  c1 uuid;
  c2 uuid;
  m_maitre uuid;
  m_novice uuid;
  m_presque uuid;
  m_voleur uuid;
  gains jsonb;
  g1 jsonb;
  g2 jsonb;
  g3 jsonb;
  g4 jsonb;
  v integer;
  n integer;
  rapport text := '';
begin
  select id into c1 from classe order by nom limit 1;
  select id into c2 from classe order by nom offset 1 limit 1;
  delete from entrainement_place;
  update entrainement_reglage set places_eleves = 1;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST maitre', c1, 6) returning id into m_maitre;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST novice', c1, 2) returning id into m_novice;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST presque', c1, 4) returning id into m_presque;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST voleur', c2, 1) returning id into m_voleur;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values
    (m_maitre, u_admin, 'test'), (m_novice, u_admin, 'test'),
    (m_presque, u_admin, 'test'), (m_voleur, u_admin, 'test');

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  begin
    perform entrainement_choisir_eleve(0, m_novice);
    rapport := rapport || E'\nKO eleve accepte sans instructeur';
  exception when others then
    rapport := rapport || E'\nOK pas d''eleve sans instructeur : ' || sqlerrm;
  end;
  begin
    perform entrainement_choisir_instructeur(m_maitre);
    rapport := rapport || E'\nOK instructeur place';
  exception when others then
    rapport := rapport || E'\nKO instructeur refuse : ' || sqlerrm;
  end;
  begin
    perform entrainement_choisir_instructeur(m_novice);
    rapport := rapport || E'\nKO deuxieme instructeur accepte';
  exception when others then
    rapport := rapport || E'\nOK un seul instructeur : ' || sqlerrm;
  end;
  begin
    perform entrainement_choisir_eleve(0, m_presque);
    rapport := rapport || E'\nKO ecart de 2 accepte';
  exception when others then
    rapport := rapport || E'\nOK ecart insuffisant refuse : ' || sqlerrm;
  end;
  begin
    perform entrainement_choisir_eleve(0, m_voleur);
    rapport := rapport || E'\nKO autre classe acceptee';
  exception when others then
    rapport := rapport || E'\nOK autre classe refusee : ' || sqlerrm;
  end;
  begin
    perform entrainement_choisir_eleve(1, m_novice);
    rapport := rapport || E'\nKO place non debloquee acceptee';
  exception when others then
    rapport := rapport || E'\nOK place non debloquee refusee : ' || sqlerrm;
  end;
  begin
    perform entrainement_choisir_eleve(0, m_novice);
    rapport := rapport || E'\nOK eleve place (classe identique, ecart 4)';
  exception when others then
    rapport := rapport || E'\nKO eleve valide refuse : ' || sqlerrm;
  end;

  -- Un autre joueur ne peut ni placer, ni renvoyer, ni faire avancer.
  perform set_config('request.jwt.claims', json_build_object('sub', u_autre)::text, true);
  perform set_config('request.jwt.claim.sub', u_autre::text, true);
  begin
    perform entrainement_renvoyer(m_novice);
    rapport := rapport || E'\nKO un autre joueur a renvoye mon eleve';
  exception when others then
    rapport := rapport || E'\nOK renvoi refuse a un autre joueur : ' || sqlerrm;
  end;
  begin
    perform entrainement_choisir_eleve(0, m_presque);
    rapport := rapport || E'\nKO un autre joueur a place mon mercenaire';
  exception when others then
    rapport := rapport || E'\nOK placement refuse a un autre joueur : ' || sqlerrm;
  end;
  begin
    perform entrainement_instance();
    rapport := rapport || E'\nKO un joueur a fait avancer l''entrainement';
  exception when others then
    rapport := rapport || E'\nOK +1 Instance reserve a l''admin : ' || sqlerrm;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  -- +1 Instance : 2 -> 3 -> 4 -> 5 -> 6 (rejoint l'instructeur, renvoye).
  g1 := entrainement_instance();
  select veterance into v from mercenaire where id = m_novice;
  rapport := rapport || case when v = 3 then E'\nOK instance 1 : vet 3' else E'\nKO instance 1 : vet ' || v end;
  g2 := entrainement_instance();
  g3 := entrainement_instance();
  select veterance into v from mercenaire where id = m_novice;
  select count(*) into n from entrainement_place where mercenaire_id = m_novice;
  rapport := rapport || case when v = 5 and n = 1 then E'\nOK instance 3 : vet 5, toujours a l''entrainement' else E'\nKO instance 3 : vet ' || v || ' place ' || n end;
  g4 := entrainement_instance();
  select veterance into v from mercenaire where id = m_novice;
  select count(*) into n from entrainement_place where mercenaire_id = m_novice;
  rapport := rapport || case when v = 6 and n = 0 and (g4 -> 0 ->> 'gradue') = 'true' then E'\nOK instance 4 : vet 6 = instructeur, eleve renvoye au dortoir' else E'\nKO instance 4 : vet ' || v || ' place ' || n end;
  select count(*) into n from entrainement_place where mercenaire_id = m_maitre and role = 'instructeur';
  rapport := rapport || case when n = 1 then E'\nOK l''instructeur reste en place' else E'\nKO instructeur parti' end;

  -- Annuler le dernier +1 Instance : vet 5 et eleve replace.
  perform entrainement_annuler_instance(g4);
  select veterance into v from mercenaire where id = m_novice;
  select count(*) into n from entrainement_place where mercenaire_id = m_novice and role = 'eleve' and position = 0;
  rapport := rapport || case when v = 5 and n = 1 then E'\nOK annulation : vet 5, eleve replace' else E'\nKO annulation : vet ' || v || ' place ' || n end;

  -- Renvoi anticipe de l'eleve : il garde son niveau.
  perform entrainement_renvoyer(m_novice);
  select veterance into v from mercenaire where id = m_novice;
  select count(*) into n from entrainement_place where mercenaire_id = m_novice;
  rapport := rapport || case when v = 5 and n = 0 then E'\nOK renvoi anticipe : vet 5 conservee' else E'\nKO renvoi anticipe : vet ' || v || ' place ' || n end;

  -- Renvoyer l'instructeur ramene les eleves.
  perform entrainement_choisir_eleve(0, m_novice);
  perform entrainement_renvoyer(m_maitre);
  select count(*) into n from entrainement_place;
  rapport := rapport || case when n = 0 then E'\nOK instructeur renvoye : ses eleves aussi' else E'\nKO il reste ' || n || ' place(s)' end;

  -- Renvoi de la compagnie (suppression du recrutement) : quitte l'entrainement.
  perform entrainement_choisir_instructeur(m_maitre);
  perform entrainement_choisir_eleve(0, m_novice);
  delete from recrutement where mercenaire_id = m_novice;
  select count(*) into n from entrainement_place;
  rapport := rapport || case when n = 1 then E'\nOK eleve renvoye de la compagnie : quitte l''entrainement' else E'\nKO places restantes : ' || n end;
  delete from recrutement where mercenaire_id = m_maitre;
  select count(*) into n from entrainement_place;
  rapport := rapport || case when n = 0 then E'\nOK instructeur renvoye de la compagnie : entrainement vide' else E'\nKO places restantes : ' || n end;

  -- Deblocage des places eleves.
  v := entrainement_debloquer_place();
  rapport := rapport || case when v = 2 then E'\nOK place eleve debloquee (2)' else E'\nKO places : ' || v end;

  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
end;
$$;
