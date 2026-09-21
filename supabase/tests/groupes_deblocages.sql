-- Test des deblocages reserves a l'administrateur et du second groupe
-- d'instruction (migration 20260921160000). A coller dans l'editeur SQL de
-- Supabase. S'ANNULE TOUT SEUL (il se termine par une erreur dont le message est
-- le compte rendu ; chaque ligne commence par OK ou KO). Un joueur inexistant
-- (u_autre) simule un joueur ordinaire : il n'est pas administrateur.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u_autre constant uuid := '00000000-0000-4000-8000-000000000001';
  c1 uuid;
  m_maitre1 uuid;
  m_maitre2 uuid;
  m_eleve1 uuid;
  m_eleve2 uuid;
  v integer;
  n integer;
  avant integer;
  apres integer;
  rapport text := '';
begin
  select id into c1 from classe order by nom limit 1;
  delete from entrainement_place;
  update entrainement_reglage set places_eleves = 1, places_eleves_2 = 1, groupe2_debloque = false;
  update dortoir_reglage set places = 18 where id;
  update infirmerie_reglage set places = 2 where id;
  update partie_etat set or_compagnie = 10000 where id;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST maitre 1', c1, 8) returning id into m_maitre1;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST maitre 2', c1, 9) returning id into m_maitre2;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST eleve 1', c1, 1) returning id into m_eleve1;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST eleve 2', c1, 2) returning id into m_eleve2;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values
    (m_maitre1, u_admin, 'test'), (m_maitre2, u_admin, 'test'),
    (m_eleve1, u_admin, 'test'), (m_eleve2, u_admin, 'test');

  -- 1. Un joueur ordinaire ne debloque rien.
  perform set_config('request.jwt.claims', json_build_object('sub', u_autre)::text, true);
  perform set_config('request.jwt.claim.sub', u_autre::text, true);
  begin perform dortoir_debloquer_place(); rapport := rapport || E'\nKO joueur : lit de dortoir debloque';
  exception when others then rapport := rapport || E'\nOK dortoir reserve a l''admin : ' || sqlerrm; end;
  begin perform infirmerie_debloquer_place(); rapport := rapport || E'\nKO joueur : lit d''infirmerie debloque';
  exception when others then rapport := rapport || E'\nOK infirmerie reservee a l''admin : ' || sqlerrm; end;
  begin perform entrainement_debloquer_place(1); rapport := rapport || E'\nKO joueur : place eleve (groupe 1) debloquee';
  exception when others then rapport := rapport || E'\nOK place eleve groupe 1 reservee a l''admin : ' || sqlerrm; end;
  begin perform entrainement_debloquer_place(2); rapport := rapport || E'\nKO joueur : place eleve (groupe 2) debloquee';
  exception when others then rapport := rapport || E'\nOK place eleve groupe 2 reservee a l''admin : ' || sqlerrm; end;
  begin perform entrainement_debloquer_groupe2(); rapport := rapport || E'\nKO joueur : second instructeur debloque';
  exception when others then rapport := rapport || E'\nOK second instructeur reserve a l''admin : ' || sqlerrm; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  -- 2. Infirmerie : 300, 500, 800 puis 1200 Po, dans l'ordre, pas de 7e lit.
  select or_compagnie into avant from partie_etat;
  perform infirmerie_debloquer_place();
  perform infirmerie_debloquer_place();
  perform infirmerie_debloquer_place();
  v := infirmerie_debloquer_place();
  select or_compagnie into apres from partie_etat;
  rapport := rapport || case when v = 6 and avant - apres = 2800 then E'\nOK infirmerie : 6 lits, 300 + 500 + 800 + 1200 = 2800 Po' else E'\nKO infirmerie : lits ' || v || ', preleve ' || (avant - apres) end;
  begin perform infirmerie_debloquer_place(); rapport := rapport || E'\nKO 7e lit d''infirmerie debloque';
  exception when others then rapport := rapport || E'\nOK pas de 7e lit d''infirmerie : ' || sqlerrm; end;

  -- 3. Terrain, groupe 1 : 100 Po par place, 3 places au maximum.
  select or_compagnie into avant from partie_etat;
  perform entrainement_debloquer_place(1);
  v := entrainement_debloquer_place(1);
  select or_compagnie into apres from partie_etat;
  rapport := rapport || case when v = 3 and avant - apres = 200 then E'\nOK groupe 1 : places 2 et 3, 100 Po chacune' else E'\nKO groupe 1 : places ' || v || ', preleve ' || (avant - apres) end;
  begin perform entrainement_debloquer_place(1); rapport := rapport || E'\nKO 4e place du groupe 1';
  exception when others then rapport := rapport || E'\nOK pas de 4e place (groupe 1) : ' || sqlerrm; end;

  -- 4. Groupe 2 : bloque tant que l'instructeur n'est pas debloque (1000 Po).
  begin perform entrainement_choisir_instructeur(m_maitre2, 2); rapport := rapport || E'\nKO instructeur place dans le groupe 2 bloque';
  exception when others then rapport := rapport || E'\nOK groupe 2 bloque : ' || sqlerrm; end;
  select or_compagnie into avant from partie_etat;
  perform entrainement_debloquer_groupe2();
  select or_compagnie into apres from partie_etat;
  rapport := rapport || case when avant - apres = 1000 then E'\nOK second instructeur debloque : 1000 Po' else E'\nKO second instructeur : preleve ' || (avant - apres) end;
  begin perform entrainement_debloquer_groupe2(); rapport := rapport || E'\nKO second instructeur debloque deux fois';
  exception when others then rapport := rapport || E'\nOK deja debloque : ' || sqlerrm; end;
  select or_compagnie into avant from partie_etat;
  perform entrainement_debloquer_place(2);
  v := entrainement_debloquer_place(2);
  select or_compagnie into apres from partie_etat;
  rapport := rapport || case when v = 3 and avant - apres = 600 then E'\nOK groupe 2 : places 2 et 3, 300 Po chacune' else E'\nKO groupe 2 : places ' || v || ', preleve ' || (avant - apres) end;
  begin perform entrainement_debloquer_place(2); rapport := rapport || E'\nKO 4e place du groupe 2';
  exception when others then rapport := rapport || E'\nOK pas de 4e place (groupe 2) : ' || sqlerrm; end;

  -- 5. Deux groupes en meme temps, chacun avec son instructeur et ses eleves.
  perform entrainement_choisir_instructeur(m_maitre1, 1);
  perform entrainement_choisir_instructeur(m_maitre2, 2);
  perform entrainement_choisir_eleve(0, m_eleve1, 1);
  perform entrainement_choisir_eleve(0, m_eleve2, 2);
  select count(*) into n from entrainement_place where groupe = 1 and role = 'eleve' and mercenaire_id = m_eleve1;
  select count(*) into v from entrainement_place where groupe = 2 and role = 'eleve' and mercenaire_id = m_eleve2;
  rapport := rapport || case when n = 1 and v = 1 then E'\nOK un eleve dans chaque groupe' else E'\nKO eleves : ' || n || ' / ' || v end;
  perform entrainement_instance();
  select veterance into n from mercenaire where id = m_eleve1;
  select veterance into v from mercenaire where id = m_eleve2;
  rapport := rapport || case when n = 2 and v = 3 then E'\nOK +1 Instance : les deux groupes avancent (2 et 3)' else E'\nKO instance : vet ' || n || ' / ' || v end;

  -- 6. Renvoyer l'instructeur du groupe 1 ne touche pas le groupe 2.
  perform entrainement_renvoyer(m_maitre1);
  select count(*) into n from entrainement_place where groupe = 1;
  select count(*) into v from entrainement_place where groupe = 2;
  rapport := rapport || case when n = 0 and v = 2 then E'\nOK renvoi de l''instructeur 1 : groupe 1 vide, groupe 2 intact' else E'\nKO renvoi : groupe 1 ' || n || ', groupe 2 ' || v end;

  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
exception when others then
  raise exception E'%  || RAPPORT :%', sqlerrm, rapport;
end;
$$;
