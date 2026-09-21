-- Test de l'entretien de la compagnie (migration 20260921170000). S'ANNULE TOUT
-- SEUL (finit par une erreur dont le message est le compte rendu ; OK / KO par
-- ligne). Un joueur inexistant (u_autre) simule un joueur ordinaire.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u_autre constant uuid := '00000000-0000-4000-8000-000000000001';
  c1 uuid;
  m1 uuid;
  m2 uuid;
  base integer;
  attendu integer;
  r jsonb;
  n integer;
  rapport text := '';
begin
  select id into c1 from classe order by nom limit 1;
  update dortoir_reglage set places = 18 where id;
  select entretien_montant() into base;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST entretien 1', c1, 7) returning id into m1;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST entretien 2', c1, 3) returning id into m2;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m1, u_admin, 'test'), (m2, u_admin, 'test');
  select entretien_montant() into attendu;
  rapport := rapport || case when attendu = base + 100 then E'\nOK entretien = 10 x somme des veterances (' || base || ' + 100 = ' || attendu || ')' else E'\nKO entretien ' || attendu || ' au lieu de ' || (base + 100) end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_autre)::text, true);
  perform set_config('request.jwt.claim.sub', u_autre::text, true);
  begin perform entretien_prelever(); rapport := rapport || E'\nKO joueur : entretien preleve';
  exception when others then rapport := rapport || E'\nOK prelevement reserve a l''admin : ' || sqlerrm; end;
  begin perform entretien_annuler(10); rapport := rapport || E'\nKO joueur : entretien rembourse';
  exception when others then rapport := rapport || E'\nOK remboursement reserve a l''admin : ' || sqlerrm; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  update partie_etat set or_compagnie = 10 where id;
  r := entretien_prelever();
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = 10 - attendu and (r ->> 'montant')::integer = attendu and n < 0 then E'\nOK solde passe negatif sans blocage : ' || n || ' Po' else E'\nKO solde ' || n || ', reponse ' || r::text end;
  select count(*) into n from partie_journal where type = 'depense' and message like 'Entretien de la compagnie%' and montant = -attendu and created_at > now() - interval '1 minute';
  rapport := rapport || case when n = 1 then E'\nOK une ligne de journal' else E'\nKO lignes de journal : ' || n end;
  begin perform partie_depenser(1, 'test'); rapport := rapport || E'\nKO depense acceptee avec un solde negatif';
  exception when others then rapport := rapport || E'\nOK depense refusee avec un solde negatif : ' || sqlerrm; end;
  perform entretien_annuler(attendu);
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = 10 then E'\nOK annulation : solde rendu (10 Po)' else E'\nKO solde apres annulation : ' || n end;
  update partie_etat set or_compagnie = 1000000 where id;
  delete from recrutement where mercenaire_id in (m1, m2);
  select entretien_montant() into n;
  rapport := rapport || case when n = base then E'\nOK renvoyer des mercenaires baisse l''entretien (retour a ' || base || ')' else E'\nKO entretien apres renvoi : ' || n end;

  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
exception when others then
  raise exception E'%  || RAPPORT :%', sqlerrm, rapport;
end;
$$;
