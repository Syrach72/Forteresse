-- Test des regles des quetes (migration 20260925100000). Meme principe que
-- infirmerie_regles.sql : fausses donnees, tout est ANNULE a la fin (le script
-- se termine volontairement par une erreur dont le message est le compte rendu ;
-- chaque ligne commence par OK ou KO). L'editeur SQL s'execute en
-- administrateur : verifier aussi par un appel REST reel.
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u_autre constant uuid := '00000000-0000-4000-8000-000000000001';
  c1 uuid;
  m_a uuid;
  m_b uuid;
  m_c uuid;
  q uuid;
  g1 jsonb;
  g2 jsonb;
  g3 jsonb;
  v integer;
  v_or_avant integer;
  v_or_apres integer;
  rapport text := '';
begin
  select id into c1 from classe order by nom limit 1;
  update quete set en_cours = false, instances_restantes = null where en_cours;
  delete from entrainement_place where position >= 0;
  delete from infirmerie_place where position >= 0;
  insert into quete (nom, instances_requises, recompense_or) values ('TEST quete', 3, 50) returning id into q;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST a', c1, 1) returning id into m_a;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST b', c1, 1) returning id into m_b;
  insert into mercenaire (nom, classe_id, veterance) values ('TEST c', c1, 1) returning id into m_c;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values
    (m_a, u_admin, 'test'), (m_b, u_admin, 'test'), (m_c, u_autre, 'autre');

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  -- Engager avant d'avoir choisi la quete : refuse.
  begin
    perform quete_engager(0, m_a);
    rapport := rapport || E'\nKO engagement accepte sans quete en cours';
  exception when others then
    rapport := rapport || E'\nOK engagement refuse sans quete en cours : ' || sqlerrm;
  end;

  perform quete_choisir(q);
  select instances_restantes into v from quete where id = q;
  rapport := rapport || case when v = 3 then E'\nOK choisir : compteur initialise a 3' else E'\nKO compteur ' || coalesce(v::text, 'null') end;

  perform quete_engager(0, m_a);
  perform quete_engager(1, m_b);
  select count(*) into v from quete_mercenaire where quete_id = q;
  rapport := rapport || case when v = 2 then E'\nOK deux mercenaires engages' else E'\nKO engages : ' || v end;

  begin
    perform quete_engager(2, m_a);
    rapport := rapport || E'\nKO meme mercenaire engage deux fois';
  exception when others then
    rapport := rapport || E'\nOK double engagement refuse : ' || sqlerrm;
  end;
  begin
    perform quete_engager(0, m_c);
    rapport := rapport || E'\nKO emplacement deja pris accepte';
  exception when others then
    rapport := rapport || E'\nOK emplacement pris refuse : ' || sqlerrm;
  end;
  begin
    perform quete_engager(6, m_c);
    rapport := rapport || E'\nKO 7e emplacement accepte';
  exception when others then
    rapport := rapport || E'\nOK 7e emplacement refuse : ' || sqlerrm;
  end;
  -- Un mercenaire engage ne peut aller ni a l'infirmerie ni a l'entrainement.
  begin
    perform infirmerie_soigner(m_a);
    rapport := rapport || E'\nKO mercenaire en quete envoye a l''infirmerie';
  exception when others then
    rapport := rapport || E'\nOK infirmerie refusee pour un mercenaire en quete : ' || sqlerrm;
  end;

  -- Autre joueur : ne peut ni engager ni retirer les mercenaires d'autrui.
  perform set_config('request.jwt.claims', json_build_object('sub', u_autre)::text, true);
  perform set_config('request.jwt.claim.sub', u_autre::text, true);
  begin
    perform quete_engager(2, m_b);
    rapport := rapport || E'\nKO engagement du mercenaire d''un autre joueur';
  exception when others then
    rapport := rapport || E'\nOK engagement refuse a un autre joueur : ' || sqlerrm;
  end;
  begin
    perform quete_retirer(m_a);
    rapport := rapport || E'\nKO retrait du mercenaire d''un autre joueur';
  exception when others then
    rapport := rapport || E'\nOK retrait refuse a un autre joueur : ' || sqlerrm;
  end;
  perform quete_engager(2, m_c);
  begin
    perform quetes_instance();
    rapport := rapport || E'\nKO un joueur a fait avancer la quete';
  exception when others then
    rapport := rapport || E'\nOK +1 Instance reserve a l''admin : ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  -- Decompte : 3 -> 2 -> 1 -> accomplie.
  g1 := quetes_instance();
  select instances_restantes into v from quete where id = q;
  rapport := rapport || case when v = 2 and (g1 ->> 'termine') = 'false' then E'\nOK +1 Instance : reste 2, pas encore accomplie' else E'\nKO apres 1 : ' || coalesce(v::text, 'null') end;
  g2 := quetes_instance();
  select instances_restantes into v from quete where id = q;
  rapport := rapport || case when v = 1 and (g2 ->> 'termine') = 'false' then E'\nOK +1 Instance : reste 1' else E'\nKO apres 2 : ' || coalesce(v::text, 'null') end;
  select count(*) into v from quete_mercenaire where quete_id = q;
  rapport := rapport || case when v = 3 then E'\nOK mercenaires toujours engages pendant le decompte' else E'\nKO engages : ' || v end;

  select or_compagnie into v_or_avant from partie_etat;
  g3 := quetes_instance();
  select or_compagnie into v_or_apres from partie_etat;
  rapport := rapport || case when (g3 ->> 'termine') = 'true' and v_or_apres = v_or_avant + 50 then E'\nOK 3e +1 Instance : quete accomplie, +50 Po' else E'\nKO accomplissement : or ' || v_or_avant || ' -> ' || v_or_apres end;
  select count(*) into v from quete_mercenaire where quete_id = q;
  rapport := rapport || case when v = 0 then E'\nOK mercenaires liberes' else E'\nKO mercenaires restants : ' || v end;
  rapport := rapport || case when (select terminee_le is not null and not en_cours from quete where id = q) then E'\nOK quete indisponible (terminee)' else E'\nKO quete toujours disponible' end;
  begin
    perform quete_choisir(q);
    rapport := rapport || E'\nKO quete terminee re-choisie';
  exception when others then
    rapport := rapport || E'\nOK quete terminee non choisissable : ' || sqlerrm;
  end;

  -- Annulation du dernier +1 Instance : la quete rouvre, or repris, mercenaires replaces.
  perform quetes_annuler_instance(g3);
  select or_compagnie into v_or_apres from partie_etat;
  select count(*) into v from quete_mercenaire where quete_id = q;
  rapport := rapport || case when v_or_apres = v_or_avant and v = 3 and (select en_cours and instances_restantes = 1 from quete where id = q) then E'\nOK annulation : or repris, 3 mercenaires replaces, reste 1' else E'\nKO annulation : or ' || v_or_apres || ', mercenaires ' || v end;
  perform quetes_annuler_instance(g2);
  select instances_restantes into v from quete where id = q;
  rapport := rapport || case when v = 2 then E'\nOK annulation d''un decompte : reste 2' else E'\nKO annulation decompte : ' || coalesce(v::text, 'null') end;

  -- Annuler le choix : mercenaires liberes, compteur efface.
  perform quete_annuler_choix();
  select count(*) into v from quete_mercenaire where quete_id = q;
  rapport := rapport || case when v = 0 and (select not en_cours and instances_restantes is null from quete where id = q) then E'\nOK annuler le choix : mercenaires liberes, compteur efface' else E'\nKO annuler le choix : ' || v end;

  -- Un mercenaire renvoye de la compagnie quitte la quete.
  perform quete_choisir(q);
  perform quete_engager(0, m_a);
  delete from recrutement where mercenaire_id = m_a;
  select count(*) into v from quete_mercenaire where mercenaire_id = m_a;
  rapport := rapport || case when v = 0 then E'\nOK renvoi de la compagnie : quitte la quete' else E'\nKO renvoye mais toujours en quete' end;

  raise exception E'RAPPORT (tout est annule)%', rapport;
end;
$$;
