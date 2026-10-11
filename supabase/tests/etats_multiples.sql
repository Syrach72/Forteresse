-- Test des etats supplementaires (migration 20261012100000) : Rd, annulation du Rd, disparition a 0 round.
-- A coller dans l'editeur SQL de Supabase ; tout est ANNULE a la fin (le script se termine volontairement par une
-- erreur dont le message est le compte rendu : OK / KO par ligne). Les droits (joueur / MJ) et l'interface se
-- verifient sur le site : mercenaire en quete, cliquer deux etats puis regler leurs rounds.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  v_cible constant uuid := '11111111-1111-4111-8111-111111111111';
  r1 record;
  r2 record;
  n integer;
  rapport text := '';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  update partie_etat set round_courant = 5 where session_id = ctx_session();
  insert into etat_supplementaire (cible, cible_id, position, etat, niveau, rounds) values
    ('mercenaire', v_cible, 1, 'fascine', 1, 2),
    ('mercenaire', v_cible, 2, 'muet', 1, 1);

  update partie_etat set round_courant = 6 where session_id = ctx_session();
  select * into r1 from etat_supplementaire where cible_id = v_cible and position = 1;
  select * into r2 from etat_supplementaire where cible_id = v_cible and position = 2;
  rapport := rapport || case when r1.etat = 'fascine' and r1.rounds = 1 and r2.etat is null and r2.efface = 'muet'
    then E'\nOK Rd : Fascine 2 -> 1 round, Muet (1 round) disparait' else E'\nKO Rd : ' || coalesce(r1.etat, 'null') || '/' || r1.rounds || ' ; ' || coalesce(r2.etat, 'null') || '/' || coalesce(r2.efface, 'null') end;

  update partie_etat set round_courant = 5 where session_id = ctx_session();
  select * into r1 from etat_supplementaire where cible_id = v_cible and position = 1;
  select * into r2 from etat_supplementaire where cible_id = v_cible and position = 2;
  rapport := rapport || case when r1.etat = 'fascine' and r1.rounds = 2 and r2.etat = 'muet' and r2.rounds = 1
    then E'\nOK Annuler le Rd : les deux etats reviennent avec leurs rounds' else E'\nKO annulation : ' || coalesce(r1.etat, 'null') || '/' || r1.rounds || ' ; ' || coalesce(r2.etat, 'null') || '/' || r2.rounds end;

  update partie_etat set round_courant = 6 where session_id = ctx_session();
  update partie_etat set round_courant = 7 where session_id = ctx_session();
  select count(*) into n from etat_supplementaire where cible_id = v_cible;
  select * into r1 from etat_supplementaire where cible_id = v_cible and position = 1;
  rapport := rapport || case when n = 1 and r1.etat is null and r1.efface = 'fascine'
    then E'\nOK deuxieme Rd : Muet efface pour de bon, Fascine arrive a 0 et disparait' else E'\nKO deuxieme Rd : ' || n || ' ligne(s)' end;

  raise exception E'RAPPORT (tout est annule)%', rapport;
end;
$$;
