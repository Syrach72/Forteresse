-- Test du budget partage et de l'entretien (migrations 20260921170000 et
-- 20260921180000). S'ANNULE TOUT SEUL (finit par une erreur dont le message est le
-- compte rendu ; OK / KO par ligne). u_autre = joueur ordinaire simule.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u_autre constant uuid := '00000000-0000-4000-8000-000000000001';
  c1 uuid;
  m1 uuid;
  m2 uuid;
  base integer;
  entretien integer;
  autres integer;
  recettes integer;
  attendu integer;
  r jsonb;
  n integer;
  v_journal integer;
  rapport text := '';
begin
  select id into c1 from classe order by nom limit 1;
  update dortoir_reglage set places = 18 where id;
  select entretien_montant() into base;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST budget 1', c1, 7) returning id into m1;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST budget 2', c1, 3) returning id into m2;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (m1, u_admin, 'test'), (m2, u_admin, 'test');
  select entretien_montant() into entretien;
  rapport := rapport || case when entretien = base + 100 then E'\nOK entretien = 10 x somme des veterances (' || base || ' + 100 = ' || entretien || ')' else E'\nKO entretien ' || entretien || ' au lieu de ' || (base + 100) end;
  select coalesce(sum(montant) filter (where nature = 'recette'), 0), coalesce(sum(montant) filter (where nature = 'depense' and not auto), 0)
    into recettes, autres from budget_poste;
  attendu := recettes - autres - entretien;

  perform set_config('request.jwt.claims', json_build_object('sub', u_autre)::text, true);
  perform set_config('request.jwt.claim.sub', u_autre::text, true);
  begin perform budget_modifier('recettes', 1); rapport := rapport || E'\nKO joueur : budget modifie';
  exception when others then rapport := rapport || E'\nOK budget reserve a l''admin : ' || sqlerrm; end;
  begin perform budget_appliquer_instance(); rapport := rapport || E'\nKO joueur : budget d''instance applique';
  exception when others then rapport := rapport || E'\nOK application reservee a l''admin : ' || sqlerrm; end;
  begin perform budget_annuler_instance(10); rapport := rapport || E'\nKO joueur : annulation du budget';
  exception when others then rapport := rapport || E'\nOK annulation reservee a l''admin : ' || sqlerrm; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  begin perform budget_modifier('entretien', 5); rapport := rapport || E'\nKO entretien modifie a la main';
  exception when others then rapport := rapport || E'\nOK entretien calcule, pas saisi : ' || sqlerrm; end;
  begin perform budget_modifier('inconnu', 5); rapport := rapport || E'\nKO poste inconnu accepte';
  exception when others then rapport := rapport || E'\nOK poste inconnu refuse : ' || sqlerrm; end;
  begin perform budget_modifier('medecin', -1); rapport := rapport || E'\nKO montant negatif accepte';
  exception when others then rapport := rapport || E'\nOK montant negatif refuse : ' || sqlerrm; end;

  update partie_etat set or_compagnie = 10 where id;
  r := budget_appliquer_instance();
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = 10 + attendu and (r ->> 'net')::integer = attendu then E'\nOK +1 Instance : solde 10 + (' || recettes || ' - ' || (autres + entretien) || ') = ' || n || ' Po' else E'\nKO solde ' || n || ', reponse ' || r::text end;
  select count(*) into v_journal from partie_journal where message like 'Nouvelle instance : recettes%' and montant = attendu and created_at > now() - interval '1 minute';
  rapport := rapport || case when v_journal = 1 then E'\nOK une ligne de journal' else E'\nKO lignes de journal : ' || v_journal end;
  perform budget_annuler_instance(attendu);
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = 10 then E'\nOK annulation : solde rendu (10 Po)' else E'\nKO solde apres annulation : ' || n end;

  -- Solde negatif : depenses > recettes, aucun blocage, achats refuses.
  perform budget_modifier('recettes', 0);
  update partie_etat set or_compagnie = 10 where id;
  r := budget_appliquer_instance();
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = 10 - autres - entretien and n < 0 then E'\nOK solde negatif sans blocage : ' || n || ' Po' else E'\nKO solde ' || n end;
  begin perform partie_depenser(1, 'test'); rapport := rapport || E'\nKO depense acceptee avec un solde negatif';
  exception when others then rapport := rapport || E'\nOK depense refusee avec un solde negatif : ' || sqlerrm; end;

  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
exception when others then
  raise exception E'%  || RAPPORT :%', sqlerrm, rapport;
end;
$$;
