-- Test de l'experience et de la progression par l'entrainement (migration 20261011100000).
-- A coller dans l'editeur SQL de Supabase. Il cree de faux mercenaires, teste chaque regle, puis S'ANNULE TOUT
-- SEUL (il se termine volontairement par une erreur dont le message est le compte rendu ; chaque ligne commence
-- par OK ou KO). Le compte de test est l'administrateur. A completer par un essai reel : une quete reussie puis
-- echouee sur le site (gain d'XP selon l'ecart FP - veterance, quart du gain en cas d'echec, bouton Annuler).
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  c1 uuid;
  m_maitre uuid;
  m_a uuid;
  m_b uuid;
  m_egal uuid;
  r jsonb;
  g jsonb;
  v integer;
  x integer;
  n integer;
  rapport text := '';
begin
  -- Le contexte de session (ctx_session) vient de l'utilisateur connecte : a poser avant toute insertion.
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  select id into c1 from classe order by nom limit 1;
  delete from entrainement_place;
  update entrainement_reglage set places_eleves = 1;
  -- Assez de lits pour les 4 faux recrutements (annule avec le reste).
  update dortoir_reglage set places = 18 where id;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST maitre', c1, 7) returning id into m_maitre;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST a', c1, 2) returning id into m_a;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST b', c1, 2) returning id into m_b;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST egal', c1, 7) returning id into m_egal;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values
    (m_maitre, u_admin, 'test'), (m_a, u_admin, 'test'), (m_b, u_admin, 'test'), (m_egal, u_admin, 'test');

  -- Paliers
  rapport := rapport || case when _xp_palier(1) = 20 and _xp_palier(4) = 30 and _xp_palier(6) = 40
      and _xp_palier(8) = 60 and _xp_palier(9) = 70 and _xp_palier(10) is null
    then E'\nOK paliers 20/20/30/30/40/40/50/60/70, rien au niveau 10' else E'\nKO paliers' end;

  -- Gain de quete selon l'ecart FP - veterance
  rapport := rapport || case when _xp_gain_quete(5, 3) = 15 and _xp_gain_quete(4, 3) = 12 and _xp_gain_quete(3, 3) = 10
      and _xp_gain_quete(2, 3) = 6 and _xp_gain_quete(1, 3) = 3 and _xp_gain_quete(0, 3) = 0
    then E'\nOK gain de quete : 15 / 12 / 10 / 6 / 3 / 0' else E'\nKO gain de quete' end;

  -- Ajout d'XP : simple, report d'excedent, plusieurs niveaux, plafond au niveau 10
  r := _xp_ajouter(m_a, 10);
  rapport := rapport || case when (r ->> 'veterance_apres')::int = 2 and (r ->> 'xp_apres')::int = 10
    then E'\nOK +10 XP : niveau 2, 10 XP' else E'\nKO +10 XP : ' || r::text end;
  r := _xp_ajouter(m_a, 15);
  rapport := rapport || case when (r ->> 'veterance_apres')::int = 3 and (r ->> 'xp_apres')::int = 5
    then E'\nOK +15 XP : niveau 3, 5 XP reportes' else E'\nKO +15 XP : ' || r::text end;
  r := _xp_ajouter(m_a, 100);
  rapport := rapport || case when (r ->> 'veterance_apres')::int = 6 and (r ->> 'xp_apres')::int = 5
    then E'\nOK +100 XP : trois niveaux d''un coup (niveau 6, 5 XP)' else E'\nKO +100 XP : ' || r::text end;
  r := _xp_ajouter(m_a, 1000);
  rapport := rapport || case when (r ->> 'veterance_apres')::int = 10 and (r ->> 'xp_apres')::int = 0
    then E'\nOK plafond : niveau 10, plus d''XP' else E'\nKO plafond : ' || r::text end;
  select points_carac into v from mercenaire_etat where mercenaire_id = m_a and session_id = ctx_session();
  rapport := rapport || case when v = 8 then E'\nOK points de caracteristique : 8 niveaux gagnes = 8 points'
    else E'\nKO points de caracteristique : ' || coalesce(v::text, 'null') end;

  -- Correction manuelle de la veterance : l'experience repart a 0
  perform _xp_ajouter(m_b, 12);
  perform mercenaire_definir_veterance(m_b, 4);
  select xp into x from mercenaire_etat where mercenaire_id = m_b and session_id = ctx_session();
  rapport := rapport || case when x = 0 and _vet(m_b) = 4 then E'\nOK correction manuelle : XP remis a 0'
    else E'\nKO correction manuelle : xp ' || coalesce(x::text, 'null') end;
  perform mercenaire_definir_veterance(m_b, 2);

  -- Entrainement : ecart minimal de 1 niveau
  perform entrainement_choisir_instructeur(m_maitre);
  begin
    perform entrainement_choisir_eleve(0, m_egal);
    rapport := rapport || E'\nKO eleve de meme niveau accepte';
  exception when others then
    rapport := rapport || E'\nOK meme niveau que l''instructeur refuse : ' || sqlerrm;
  end;

  -- Eleve niveau 2 sous un instructeur niveau 7 (xp remis a zero) : 1+1+1+2+3 = 8 instances.
  update mercenaire_etat set xp = 0 where mercenaire_id = m_b and session_id = ctx_session();
  perform entrainement_choisir_eleve(0, m_b);
  n := 0;
  loop
    g := entrainement_instance();
    n := n + 1;
    exit when n >= 12 or not exists (select 1 from entrainement_place where mercenaire_id = m_b);
    if n = 1 then
      select xp into x from mercenaire_etat where mercenaire_id = m_b and session_id = ctx_session();
      rapport := rapport || case when _vet(m_b) = 3 and x = 0 then E'\nOK 1re instance (ecart 5) : niveau 3'
        else E'\nKO 1re instance : niveau ' || _vet(m_b) || ', xp ' || coalesce(x::text, 'null') end;
    end if;
  end loop;
  rapport := rapport || case when n = 8 and _vet(m_b) = 7 then E'\nOK niveau 2 -> 7 sous un instructeur 7 : 8 instances, retourne a la caserne'
    else E'\nKO formation : ' || n || ' instances, niveau ' || _vet(m_b) end;

  -- Annulation de la derniere instance : niveau et XP repris.
  update mercenaire_etat set veterance = 6, xp = 0 where mercenaire_id = m_b and session_id = ctx_session();
  perform entrainement_choisir_eleve(0, m_b);
  g := entrainement_instance();
  select xp into x from mercenaire_etat where mercenaire_id = m_b and session_id = ctx_session();
  rapport := rapport || case when _vet(m_b) = 6 and x = 14 then E'\nOK ecart 1 : 14 XP sur 40 (un tiers arrondi)'
    else E'\nKO ecart 1 : niveau ' || _vet(m_b) || ', xp ' || coalesce(x::text, 'null') end;
  perform entrainement_annuler_instance(g);
  select xp into x from mercenaire_etat where mercenaire_id = m_b and session_id = ctx_session();
  rapport := rapport || case when _vet(m_b) = 6 and x = 0 then E'\nOK annulation : XP repris'
    else E'\nKO annulation : niveau ' || _vet(m_b) || ', xp ' || coalesce(x::text, 'null') end;

  raise exception E'RAPPORT (tout est annule)%', rapport;
end;
$$;
