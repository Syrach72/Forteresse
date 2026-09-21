-- Test des regles du dortoir partage (migration 20260921140000). Faux
-- mercenaires ; tout est ANNULE a la fin (le script se termine volontairement
-- par une erreur dont le message est le compte rendu ; OK / KO par ligne).
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  c1 uuid;
  m uuid[] := '{}';
  v_id uuid;
  libres integer;
  v integer;
  n integer;
  lit_a integer;
  rapport text := '';
begin
  select id into c1 from classe order by nom limit 1;
  update dortoir_reglage set places = 6 where id;
  update partie_etat set or_compagnie = 1000 where id;
  select 6 - count(*) into libres from recrutement;
  -- Remplit tous les lits libres avec de faux mercenaires.
  for i in 1..libres loop
    insert into mercenaire (nom, classe_id, veterance) values ('TEST d' || i, c1, 0) returning id into v_id;
    m := m || v_id;
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (v_id, u_admin, 'test');
  end loop;
  select count(*), count(distinct lit) into n, v from recrutement;
  rapport := rapport || case when n = v and n = 6 and (select min(lit) from recrutement) = 0 and (select max(lit) from recrutement) = 5 then E'\nOK 6 recrutes : lits 0 a 5, tous differents' else E'\nKO lits : ' || n || ' recrutes, ' || v || ' lits distincts' end;

  -- Plus de lit libre : refus.
  insert into mercenaire (nom, classe_id, veterance) values ('TEST extra', c1, 0) returning id into v_id;
  begin
    insert into recrutement (mercenaire_id, user_id, nom_joueur) values (v_id, u_admin, 'test');
    rapport := rapport || E'\nKO recrutement accepte sans lit libre';
  exception when others then
    rapport := rapport || E'\nOK aucun lit libre : ' || sqlerrm;
  end;

  -- Un renvoi libere un lit, que le suivant reprend.
  select lit into lit_a from recrutement where mercenaire_id = m[1];
  delete from recrutement where mercenaire_id = m[1];
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (v_id, u_admin, 'test');
  select lit into n from recrutement where mercenaire_id = v_id;
  rapport := rapport || case when n = lit_a then E'\nOK le lit libere est repris par le suivant (lit ' || lit_a || ')' else E'\nKO lit ' || n || ' au lieu de ' || lit_a end;

  -- 7e lit : debloque pour 100 Po sur la tresorerie partagee.
  update partie_etat set or_compagnie = 50 where id;
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  begin perform dortoir_debloquer_place(); rapport := rapport || E'\nKO deblocage sans solde accepte';
  exception when others then rapport := rapport || E'\nOK deblocage sans solde refuse : ' || sqlerrm; end;
  update partie_etat set or_compagnie = 1000 where id;
  v := dortoir_debloquer_place();
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when v = 7 and n = 900 then E'\nOK 7e lit debloque : -100 Po' else E'\nKO deblocage : places ' || v || ' or ' || n end;
  begin perform dortoir_debloquer_place(); rapport := rapport || E'\nKO 8e lit debloque';
  exception when others then rapport := rapport || E'\nOK pas de 8e lit : ' || sqlerrm; end;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST septieme', c1, 0) returning id into v_id;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (v_id, u_admin, 'test');
  select lit into n from recrutement where mercenaire_id = v_id;
  rapport := rapport || case when n = 6 then E'\nOK le 7e recrute prend le lit 6' else E'\nKO 7e recrute : lit ' || n end;

  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
exception when others then
  raise exception E'%  || RAPPORT :%', sqlerrm, rapport;
end;
$$;
