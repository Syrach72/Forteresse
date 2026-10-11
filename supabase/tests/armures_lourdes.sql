-- Test de la regle des armures lourdes (migration 20261012110000) : Guerrier, Paladin et Pretres des domaines de
-- la Guerre et de la Forge seulement. A coller dans l'editeur SQL de Supabase ; tout est ANNULE a la fin (erreur
-- finale dont le message est le compte rendu : OK / KO par ligne).
do $$
declare
  u_admin constant uuid := 'da7170e6-6adb-4975-89a1-e8002e09f65b';
  c_pretre uuid;
  c_guerrier uuid;
  v_obj uuid;
  m_forge uuid;
  m_guerre uuid;
  m_vie uuid;
  m_guerrier uuid;
  rapport text := '';
  m uuid;
  lib text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin)::text, true);
  perform set_config('request.jwt.claim.sub', u_admin::text, true);
  select id into c_pretre from classe where lower(nom) in ('prêtre', 'pretre') limit 1;
  select id into c_guerrier from classe where lower(nom) = 'guerrier' limit 1;
  select o.id into v_obj from objet_catalogue o join categorie c on c.id = o.categorie_id
    where lower(btrim(c.nom)) = 'armure lourde' order by o.nom limit 1;
  if v_obj is null then
    raise exception E'RAPPORT\nKO aucune armure lourde dans le catalogue pour tester';
  end if;
  update objet_catalogue set veterance_requise = null where id = v_obj;
  insert into mercenaire (nom, classe_id, sous_classe, veterance) values ('TEST forge', c_pretre, 'Domaine de la Forge', 1) returning id into m_forge;
  insert into mercenaire (nom, classe_id, sous_classe, veterance) values ('TEST guerre', c_pretre, 'Domaine de la Guerre', 1) returning id into m_guerre;
  insert into mercenaire (nom, classe_id, sous_classe, veterance) values ('TEST vie', c_pretre, 'Domaine de la Vie', 1) returning id into m_vie;
  insert into mercenaire (nom, classe_id, sous_classe, veterance) values ('TEST guerrier', c_guerrier, 'Defenseur', 1) returning id into m_guerrier;
  foreach m in array array[m_forge, m_guerre, m_vie, m_guerrier] loop
    select nom into lib from mercenaire where id = m;
    perform _sac_dos_ajouter(_sac_dos_id(m), v_obj, 1, null, 'test');
    begin
      perform sac_dos_equiper(m, v_obj);
      rapport := rapport || case when m = m_vie then E'\nKO ' || lib || ' (Domaine de la Vie) a equipe une armure lourde'
        else E'\nOK ' || lib || ' equipe l''armure lourde' end;
    exception when others then
      rapport := rapport || case when m = m_vie and sqlerrm like '%réservées%' then E'\nOK ' || lib || ' (Domaine de la Vie) refuse : ' || sqlerrm
        else E'\nKO ' || lib || ' : ' || sqlerrm end;
    end;
  end loop;
  raise exception E'RAPPORT (tout est annule)%', rapport;
end;
$$;
