-- Test de la Reaction (migration 20261011120000) : depensee, rendue par le Rd, reprise par « Annuler » le Rd.
-- A coller dans l'editeur SQL de Supabase ; tout est ANNULE a la fin (le script se termine volontairement par une
-- erreur dont le message est le compte rendu : OK / KO par ligne). Le bouton cote joueur, lui, se verifie sur le
-- site : mercenaire engage dans une quete, clic sur « Reaction », puis Rd du MJ.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  c1 uuid;
  m_a uuid;
  v boolean;
  w boolean;
  rapport text := '';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  select id into c1 from classe order by nom limit 1;
  update dortoir_reglage set places = 18 where id;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST reaction', c1, 2) returning id into m_a;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m_a, u_admin, 'test');
  insert into mercenaire_etat (session_id, mercenaire_id, veterance) values (ctx_session(), m_a, 2);
  update partie_etat set round_courant = 5 where session_id = ctx_session();

  update mercenaire_etat set reaction_utilisee = true where session_id = ctx_session() and mercenaire_id = m_a;
  update partie_etat set round_courant = 6 where session_id = ctx_session();
  select reaction_utilisee, reaction_rd into v, w from mercenaire_etat where session_id = ctx_session() and mercenaire_id = m_a;
  rapport := rapport || case when v = false and w = true then E'\nOK Rd : la reaction redevient disponible' else E'\nKO apres Rd : ' || v::text || '/' || w::text end;

  update partie_etat set round_courant = 5 where session_id = ctx_session();
  select reaction_utilisee, reaction_rd into v, w from mercenaire_etat where session_id = ctx_session() and mercenaire_id = m_a;
  rapport := rapport || case when v = true and w = false then E'\nOK Annuler le Rd : la reaction est de nouveau depensee' else E'\nKO apres annulation : ' || v::text || '/' || w::text end;

  update partie_etat set round_courant = 6 where session_id = ctx_session();
  update partie_etat set round_courant = 7 where session_id = ctx_session();
  select reaction_utilisee, reaction_rd into v, w from mercenaire_etat where session_id = ctx_session() and mercenaire_id = m_a;
  rapport := rapport || case when v = false and w = false then E'\nOK deuxieme Rd : disponible, rien a reprendre' else E'\nKO deuxieme Rd : ' || v::text || '/' || w::text end;

  raise exception E'RAPPORT (tout est annule)%', rapport;
end;
$$;
