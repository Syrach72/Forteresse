-- Test des prix de deblocage des lits du dortoir (migration 20260921150000) :
-- 12 deblocages successifs (100 x3, 150 x3, 200 x3, 300 x3), refus au 19e lit et
-- faute d'or. S'ANNULE TOUT SEUL (il se termine par une erreur dont le message est
-- le compte rendu ; OK / KO par ligne).
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  avant integer;
  apres integer;
  places integer;
  prix integer[] := '{}';
  attendu integer[] := '{100,100,100,150,150,150,200,200,200,300,300,300}';
  rapport text := '';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  update dortoir_reglage set places = 6 where id;
  update partie_etat set or_compagnie = 10000 where id;
  for i in 1..12 loop
    select or_compagnie into avant from partie_etat;
    places := dortoir_debloquer_place();
    select or_compagnie into apres from partie_etat;
    prix := prix || (avant - apres);
    if places <> 6 + i then rapport := rapport || E'\nKO deblocage ' || i || ' : places ' || places; end if;
  end loop;
  rapport := rapport || case when prix = attendu then E'\nOK 12 deblocages dans l''ordre : ' || array_to_string(prix, ' / ') || ' Po' else E'\nKO prix : ' || array_to_string(prix, ' / ') end;
  select or_compagnie into apres from partie_etat;
  rapport := rapport || case when apres = 10000 - 2250 then E'\nOK total preleve : 2250 Po' else E'\nKO total : ' || (10000 - apres) end;
  begin perform dortoir_debloquer_place(); rapport := rapport || E'\nKO 19e lit debloque';
  exception when others then rapport := rapport || E'\nOK pas de 19e lit : ' || sqlerrm; end;
  update dortoir_reglage set places = 9 where id;
  update partie_etat set or_compagnie = 149 where id;
  begin perform dortoir_debloquer_place(); rapport := rapport || E'\nKO 10e lit debloque avec 149 Po';
  exception when others then rapport := rapport || E'\nOK 149 Po ne suffisent pas pour le 10e lit (150) : ' || sqlerrm; end;
  update partie_etat set or_compagnie = 150 where id;
  places := dortoir_debloquer_place();
  select or_compagnie into apres from partie_etat;
  rapport := rapport || case when places = 10 and apres = 0 then E'\nOK 150 Po suffisent : 10e lit, solde 0' else E'\nKO 10e lit : places ' || places || ' or ' || apres end;
  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
exception when others then
  raise exception E'%  || RAPPORT :%', sqlerrm, rapport;
end;
$$;
