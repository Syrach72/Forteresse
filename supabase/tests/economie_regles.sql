-- Test des regles de l'economie partagee (migration 20260921130000). Faux
-- objets et fausse recette ; tout est ANNULE a la fin (le script se termine
-- volontairement par une erreur dont le message est le compte rendu ; chaque
-- ligne commence par OK ou KO). L'editeur SQL est administrateur : verifier
-- aussi par des appels REST reels (cf. pg_safeupdate).
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  u_autre constant uuid := '00000000-0000-4000-8000-000000000001';
  cat uuid;
  o_a uuid; o_m1 uuid; o_m2 uuid; o_p uuid; o_q uuid;
  r_p uuid; r_q uuid;
  res jsonb; j1 jsonb; j2 jsonb; j3 jsonb; gains jsonb;
  v integer; n integer; w integer;
  rapport text := '';
begin
  select id into cat from categorie limit 1;
  insert into objet_catalogue (code_unique, nom, categorie_id, cout_achat_or) values ('t-a', 'TEST A', cat, 100) returning id into o_a;
  insert into objet_catalogue (code_unique, nom, categorie_id) values ('t-m1', 'TEST M1', cat) returning id into o_m1;
  insert into objet_catalogue (code_unique, nom, categorie_id) values ('t-m2', 'TEST M2', cat) returning id into o_m2;
  insert into objet_catalogue (code_unique, nom, categorie_id, cout_achat_or, duree_fabrication_instances) values ('t-p', 'TEST P', cat, 300, 2) returning id into o_p;
  insert into objet_catalogue (code_unique, nom, categorie_id, cout_achat_or) values ('t-q', 'TEST Q', cat, 40) returning id into o_q;
  insert into recette (code_unique, nom, atelier, resultat_objet_id) values ('t-rp', 'TEST P', 'forge', o_p) returning id into r_p;
  insert into ingredient_recette (recette_id, objet_id, quantite_requise) values (r_p, o_m1, 2), (r_p, o_m2, 1);
  insert into recette (code_unique, nom, atelier, resultat_objet_id) values ('t-rq', 'TEST Q', 'forge', o_q) returning id into r_q;
  insert into ingredient_recette (recette_id, objet_id, quantite_requise) values (r_q, o_m1, 1);
  delete from atelier_fabrication where atelier in ('forge', 'armurerie', 'alchimie', 'mage');
  update partie_etat set or_compagnie = 1000 where id;
  update entrainement_reglage set places_eleves = 1 where id;
  update infirmerie_reglage set places = 2 where id;
  perform _arsenal_ajouter(o_m1, 10);
  perform _arsenal_ajouter(o_m2, 5);

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  -- Achat
  res := partie_acheter(o_a);
  select or_compagnie into v from partie_etat;
  rapport := rapport || case when v = 900 and _arsenal_quantite(o_a) = 1 then E'\nOK achat : -100 Po, objet dans l''arsenal' else E'\nKO achat : or ' || v end;
  j1 := res;
  update partie_etat set or_compagnie = 50 where id;
  begin perform partie_acheter(o_a); rapport := rapport || E'\nKO achat sans solde accepte';
  exception when others then rapport := rapport || E'\nOK achat sans solde refuse : ' || sqlerrm; end;
  update partie_etat set or_compagnie = 900 where id;
  begin perform partie_acheter(o_m1); rapport := rapport || E'\nKO achat sans cout accepte';
  exception when others then rapport := rapport || E'\nOK achat sans cout refuse : ' || sqlerrm; end;

  -- Vente (moitie de la valeur) et destruction
  res := partie_vendre(o_a, 1);
  select or_compagnie into v from partie_etat;
  rapport := rapport || case when v = 950 and _arsenal_quantite(o_a) = 0 then E'\nOK vente : +50 Po (moitie)' else E'\nKO vente : or ' || v end;
  begin perform partie_vendre(o_a, 1); rapport := rapport || E'\nKO vente sans stock acceptee';
  exception when others then rapport := rapport || E'\nOK vente sans stock refusee : ' || sqlerrm; end;
  begin perform partie_vendre(o_m1, 1); rapport := rapport || E'\nKO vente sans valeur acceptee';
  exception when others then rapport := rapport || E'\nOK vente sans valeur refusee : ' || sqlerrm; end;
  perform partie_detruire(o_m1, 1);
  begin perform partie_detruire(o_m1, 100); rapport := rapport || E'\nKO destruction trop grande acceptee';
  exception when others then rapport := rapport || E'\nOK destruction trop grande refusee : ' || sqlerrm; end;
  rapport := rapport || case when _arsenal_quantite(o_m1) = 9 then E'\nOK destruction : M1 9' else E'\nKO destruction : M1 ' || _arsenal_quantite(o_m1) end;

  -- Fabrication en file
  res := partie_fabriquer(o_p);
  j2 := res;
  select restant into v from atelier_fabrication where atelier = 'forge';
  rapport := rapport || case when v = 2 and _arsenal_quantite(o_m1) = 7 and _arsenal_quantite(o_m2) = 4 then E'\nOK fabrication en file : ingredients consommes, duree 2' else E'\nKO fabrication : restant ' || coalesce(v::text, 'aucun') end;
  begin perform partie_fabriquer(o_p); rapport := rapport || E'\nKO deuxieme fabrication dans l''atelier acceptee';
  exception when others then rapport := rapport || E'\nOK atelier occupe : ' || sqlerrm; end;

  -- Un autre joueur : peut acheter (economie commune) mais ni annuler mon operation ni avancer l'instance
  perform set_config('request.jwt.claims', json_build_object('sub', u_autre)::text, true);
  perform set_config('request.jwt.claim.sub', u_autre::text, true);
  begin perform partie_annuler((j2 ->> 'journal_id')::uuid); rapport := rapport || E'\nKO un autre joueur a annule mon operation';
  exception when others then rapport := rapport || E'\nOK annulation refusee a un autre joueur : ' || sqlerrm; end;
  begin perform ateliers_instance(); rapport := rapport || E'\nKO un joueur a fait avancer les ateliers';
  exception when others then rapport := rapport || E'\nOK +1 Instance ateliers reserve a l''admin : ' || sqlerrm; end;
  begin perform partie_or_definir(5); rapport := rapport || E'\nKO un joueur a fixe l''or';
  exception when others then rapport := rapport || E'\nOK or reserve a l''admin : ' || sqlerrm; end;
  perform partie_acheter(o_q);
  rapport := rapport || case when _arsenal_quantite(o_q) = 1 then E'\nOK un autre joueur achete dans l''arsenal commun' else E'\nKO achat autre joueur' end;
  perform partie_vendre(o_q, 1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);

  -- Recuperation et instances
  begin perform partie_recuperer('forge'); rapport := rapport || E'\nKO recuperation avant la fin acceptee';
  exception when others then rapport := rapport || E'\nOK recuperation avant la fin refusee : ' || sqlerrm; end;
  perform ateliers_instance();
  gains := ateliers_instance();
  select restant into v from atelier_fabrication where atelier = 'forge';
  rapport := rapport || case when v = 0 then E'\nOK 2 instances : duree 0' else E'\nKO duree ' || v end;
  perform ateliers_annuler_instance(gains);
  select restant into v from atelier_fabrication where atelier = 'forge';
  rapport := rapport || case when v = 1 then E'\nOK annulation de la derniere instance : duree 1' else E'\nKO annulation instance : ' || v end;
  perform ateliers_instance();
  perform partie_recuperer('forge');
  select count(*) into n from atelier_fabrication where atelier = 'forge';
  rapport := rapport || case when n = 0 and _arsenal_quantite(o_p) = 1 then E'\nOK recuperation : objet dans l''arsenal, atelier libre' else E'\nKO recuperation' end;
  begin perform partie_annuler((j2 ->> 'journal_id')::uuid); rapport := rapport || E'\nKO annulation apres recuperation acceptee';
  exception when others then rapport := rapport || E'\nOK annulation apres recuperation refusee : ' || sqlerrm; end;

  -- Annulation d'une fabrication en file
  select _arsenal_quantite(o_m1) into w;
  j3 := partie_fabriquer(o_p);
  perform partie_annuler((j3 ->> 'journal_id')::uuid);
  select count(*) into n from atelier_fabrication where atelier = 'forge';
  rapport := rapport || case when n = 0 and _arsenal_quantite(o_m1) = w then E'\nOK annulation fabrication en file : ingredients restitues, atelier libere' else E'\nKO annulation en file' end;
  begin perform partie_annuler((j3 ->> 'journal_id')::uuid); rapport := rapport || E'\nKO double annulation acceptee';
  exception when others then rapport := rapport || E'\nOK double annulation refusee : ' || sqlerrm; end;

  -- Fabrication immediate puis annulation
  j3 := partie_fabriquer(o_q);
  rapport := rapport || case when _arsenal_quantite(o_q) = 1 and _arsenal_quantite(o_m1) = w - 1 and not (j3 ->> 'file')::boolean then E'\nOK fabrication immediate (sans duree)' else E'\nKO fabrication immediate' end;
  perform partie_annuler((j3 ->> 'journal_id')::uuid);
  rapport := rapport || case when _arsenal_quantite(o_q) = 0 and _arsenal_quantite(o_m1) = w then E'\nOK annulation fabrication immediate' else E'\nKO annulation immediate' end;

  -- Annulation d'un achat, refusee si l'objet n'est plus la
  select or_compagnie into v from partie_etat;
  res := partie_acheter(o_a);
  perform partie_annuler((res ->> 'journal_id')::uuid);
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = v and _arsenal_quantite(o_a) = 0 then E'\nOK annulation d''achat : or rembourse' else E'\nKO annulation achat : or ' || n end;
  res := partie_acheter(o_a);
  perform partie_vendre(o_a, 1);
  begin perform partie_annuler((res ->> 'journal_id')::uuid); rapport := rapport || E'\nKO annulation d''un achat deja revendu acceptee';
  exception when others then rapport := rapport || E'\nOK annulation refusee (objet revendu) : ' || sqlerrm; end;

  -- Depense, or, deblocages de places
  select or_compagnie into v from partie_etat;
  perform partie_depenser(200, 'Test');
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = v - 200 then E'\nOK depense libre' else E'\nKO depense' end;
  begin perform partie_depenser(999999, 'Test'); rapport := rapport || E'\nKO depense sans solde acceptee';
  exception when others then rapport := rapport || E'\nOK depense sans solde refusee : ' || sqlerrm; end;
  perform partie_or_definir(1234);
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = 1234 then E'\nOK or fixe par l''admin' else E'\nKO or ' || n end;
  perform entrainement_debloquer_place();
  select or_compagnie into n from partie_etat;
  rapport := rapport || case when n = 1134 then E'\nOK place eleve : -100 Po sur la tresorerie partagee' else E'\nKO place eleve : or ' || n end;
  begin perform infirmerie_debloquer_place(); rapport := rapport || case when (select or_compagnie from partie_etat) = 834 then E'\nOK lit d''infirmerie : -300 Po' else E'\nKO lit infirmerie' end;
  exception when others then rapport := rapport || E'\nKO lit infirmerie refuse : ' || sqlerrm; end;
  perform partie_or_definir(499);
  begin perform infirmerie_debloquer_place(); rapport := rapport || E'\nKO lit infirmerie sans solde accepte';
  exception when others then rapport := rapport || E'\nOK lit infirmerie sans solde refuse : ' || sqlerrm; end;

  raise exception E'TEST TERMINE, TOUT EST ANNULE :%', rapport;
exception when others then
  raise exception E'%  || RAPPORT :%', sqlerrm, rapport;
end;
$$;
