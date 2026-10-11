-- Test des nouveaux evenements de missions (migration 20261011110000) : niveau gagne (individuel) et
-- entrainement termine (collectif). A coller dans l'editeur SQL de Supabase ; tout est ANNULE a la fin (le script
-- se termine volontairement par une erreur dont le message est le compte rendu : OK / KO par ligne).
-- Les evenements « quete reussie / echouee » pour les joueurs se verifient par un essai reel sur le site.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  c1 uuid;
  m_maitre uuid;
  m_a uuid;
  m_b uuid;
  mi_niveau uuid;
  mi_coll uuid;
  n integer;
  rapport text := '';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  select id into c1 from classe order by nom limit 1;
  delete from entrainement_place;
  update entrainement_reglage set places_eleves = 1;
  update dortoir_reglage set places = 18 where id;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST maitre', c1, 7) returning id into m_maitre;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST a', c1, 2) returning id into m_a;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST b', c1, 6) returning id into m_b;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values
    (m_maitre, u_admin, 'test'), (m_a, u_admin, 'test'), (m_b, u_admin, 'test');
  insert into mission (code, rubrique, nom, evenement, seuil, recompense_or)
    values ('test-niveau', 'individuelle', 'TEST niveau', 'niveau_gagne', 2, 10) returning id into mi_niveau;
  insert into mission (code, rubrique, nom, evenement, seuil, recompense_or)
    values ('test-coll', 'collective', 'TEST fin entrainement', 'entrainement_termine', 1, 5) returning id into mi_coll;

  -- Deux niveaux gagnes par le meme joueur : la mission individuelle (seuil 2) se declenche au second.
  perform _xp_ajouter(m_a, 20);
  select count(*) into n from mission_attribution where mission_id = mi_niveau;
  rapport := rapport || case when n = 0 then E'\nOK 1 niveau sur 2 : mission pas encore accomplie' else E'\nKO attribuee trop tot : ' || n end;
  perform _xp_ajouter(m_a, 30);
  select count(*) into n from mission_attribution where mission_id = mi_niveau and user_id = u_admin;
  rapport := rapport || case when n = 1 then E'\nOK 2e niveau : mission individuelle accomplie pour le joueur' else E'\nKO attribution : ' || n end;

  -- Fin d'entrainement : 3 instances (ecart de 1 niveau), puis la mission collective se declenche.
  perform entrainement_choisir_instructeur(m_maitre);
  perform entrainement_choisir_eleve(0, m_b);
  perform entrainement_instance();
  perform entrainement_instance();
  select count(*) into n from mission_attribution where mission_id = mi_coll;
  rapport := rapport || case when n = 0 then E'\nOK avant la fin : mission collective pas accomplie' else E'\nKO collective trop tot : ' || n end;
  perform entrainement_instance();
  select count(*) into n from mission_attribution where mission_id = mi_coll and user_id is null;
  rapport := rapport || case when n = 1 then E'\nOK fin de l''entrainement : mission collective accomplie' else E'\nKO collective : ' || n end;

  raise exception E'RAPPORT (tout est annule)%', rapport;
end;
$$;
