-- Gain de vétérance à la fin d'une quête (Bruno, 2026-09-26) : quand une quête se termine (le +1 Instance
-- du MJ amène son compteur à 0), chaque mercenaire engagé gagne +1 de vétérance, SAUF si sa vétérance est
-- strictement supérieure au facteur de puissance (FP) de la quête : dans ce cas il n'en gagne pas
-- (vétérance égale au FP : il gagne). Le gain s'écrit sur la vétérance de la session et il est annulé si le
-- MJ annule le +1 Instance qui a terminé la quête.

create or replace function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  e quete_etat%rowtype;
  r record;
  v_avant integer;
  v_apres integer;
  v_vet_avant integer;
  v_vet_apres integer;
  v_gagnants integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_mercs jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select * into e from quete_etat where en_cours for update;
  if not found then
    return null;
  end if;
  select * into q from quete where id = e.quete_id;
  v_avant := coalesce(e.instances_restantes, q.instances_requises);
  v_apres := greatest(v_avant - 1, 0);
  if v_apres > 0 then
    update quete_etat set instances_restantes = v_apres where quete_id = q.id;
    return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
      'avant', v_avant, 'apres', v_apres, 'termine', false);
  end if;
  if q.recompense_or > 0 then
    update partie_etat set or_compagnie = or_compagnie + q.recompense_or where id;
  end if;
  for r in select objet_id, quantite from quete_recompense where quete_id = q.id order by position
  loop
    perform _arsenal_ajouter(r.objet_id, r.quantite);
    v_items := v_items || jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite);
  end loop;
  for r in select position, mercenaire_id from quete_mercenaire where quete_id = q.id order by position
  loop
    v_vet_avant := _vet(r.mercenaire_id);
    if v_vet_avant > q.facteur_puissance then
      v_vet_apres := v_vet_avant;
    else
      v_vet_apres := v_vet_avant + 1;
      insert into mercenaire_etat (session_id, mercenaire_id, veterance)
        values (ctx_session(), r.mercenaire_id, v_vet_apres)
        on conflict (session_id, mercenaire_id) do update set veterance = excluded.veterance;
      v_gagnants := v_gagnants + 1;
    end if;
    v_mercs := v_mercs || jsonb_build_object('mercenaire_id', r.mercenaire_id, 'position', r.position,
      'veterance_avant', v_vet_avant, 'veterance_apres', v_vet_apres);
  end loop;
  delete from quete_mercenaire where quete_id = q.id;
  update quete_etat
    set en_cours = false, terminee_le = now(), instances_restantes = 0
    where quete_id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : +' || q.recompense_or || ' Po, ' || jsonb_array_length(v_items) || ' objet(s) rejoignent l''arsenal, '
      || v_gagnants || ' mercenaire(s) gagnent +1 de vétérance.',
    q.recompense_or, jsonb_build_object('quete_id', q.id, 'items', v_items, 'mercenaires', v_mercs));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs);
end;
$$;

create or replace function quetes_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  i jsonb;
  v_quete uuid;
  v_merc uuid;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_gains is null then
    return;
  end if;
  perform _verrou_partie();
  v_quete := (p_gains ->> 'quete_id')::uuid;
  if not coalesce((p_gains ->> 'termine')::boolean, true) then
    update quete_etat
      set instances_restantes = (p_gains ->> 'avant')::integer
      where quete_id = v_quete and en_cours
        and instances_restantes = (p_gains ->> 'apres')::integer;
    return;
  end if;
  if exists (select 1 from quete_etat where en_cours and quete_id <> v_quete) then
    raise exception 'Une autre quête est en cours : impossible de rouvrir celle-ci.';
  end if;
  if coalesce((p_gains ->> 'or')::integer, 0) > 0 then
    update partie_etat set or_compagnie = or_compagnie - (p_gains ->> 'or')::integer where id;
  end if;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'items', '[]'::jsonb))
  loop
    perform _arsenal_retirer((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
  end loop;
  update quete_etat
    set en_cours = true, terminee_le = null,
        instances_restantes = greatest(coalesce((p_gains ->> 'avant')::integer, 1), 1)
    where quete_id = v_quete;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'mercenaires', '[]'::jsonb))
  loop
    v_merc := (i ->> 'mercenaire_id')::uuid;
    -- La vétérance gagnée à la fin de la quête est reprise (seulement si elle n'a pas bougé depuis).
    if coalesce((i ->> 'veterance_apres')::integer, 0) > coalesce((i ->> 'veterance_avant')::integer, 0) then
      update mercenaire_etat
        set veterance = (i ->> 'veterance_avant')::integer
        where mercenaire_id = v_merc and session_id = ctx_session()
          and veterance = (i ->> 'veterance_apres')::integer;
    end if;
    if exists (select 1 from recrutement where mercenaire_id = v_merc)
       and not exists (select 1 from quete_mercenaire where mercenaire_id = v_merc)
       and not exists (select 1 from entrainement_place where mercenaire_id = v_merc)
       and not exists (select 1 from infirmerie_place where mercenaire_id = v_merc)
       and not exists (
         select 1 from quete_mercenaire
         where quete_id = v_quete and position = (i ->> 'position')::integer)
    then
      insert into quete_mercenaire (quete_id, position, mercenaire_id)
        values (v_quete, (i ->> 'position')::integer, v_merc);
    end if;
  end loop;
  perform _journal('annulation', 'Quête accomplie annulée (+1 Instance annulé).',
    -coalesce((p_gains ->> 'or')::integer, 0), jsonb_build_object('annule_quete', p_gains ->> 'quete_id'));
end;
$$;
