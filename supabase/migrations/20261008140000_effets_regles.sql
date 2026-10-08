-- Effets temporaires : règles complémentaires (Bruno, 2026-10-08).
--  * Un mercenaire qui a encore un effet temporaire non dépensé (en réserve, actif ou PV temporaires restants)
--    ne peut pas en recevoir un nouveau : la remise est refusée (sinon le premier serait perdu).
--  * Annuler un +1 Instance qui a terminé une quête remet TOUT comme avant : les effets consommés (ou les PV
--    temporaires disparus) reviennent, la santé actuelle ramenée au maximum est rétablie, et les missions
--    collectives déclenchées par la réussite de la quête sont retirées (or et objets repris).
--    (Un effet déjà donné à un mercenaire reste définitif : le joueur le confirme avant de le donner.)

create or replace function _effets_snapshot(p_mercenaire uuid)
returns jsonb
language sql
stable
security definer set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at), '[]'::jsonb)
  from mercenaire_effet e
  where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session();
$$;

-- Missions déclenchées par un événement : défait une occurrence (compteur collectif -1, missions collectives
-- dont le seuil n'est plus atteint retirées, or et objets repris).
create or replace function _missions_annuler_evenement(p_evenement text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_zero constant uuid := '00000000-0000-0000-0000-000000000000';
  v_val integer;
  a mission_attribution%rowtype;
  v_nom text;
begin
  update mission_compteur set valeur = greatest(valeur - 1, 0)
    where evenement = p_evenement and user_id = v_zero and session_id = ctx_session()
    returning valeur into v_val;
  if v_val is null then
    return;
  end if;
  for a in
    select ma.* from mission_attribution ma join mission m on m.id = ma.mission_id
    where m.evenement = p_evenement and m.rubrique = 'collective' and m.seuil > v_val
      and ma.session_id = ctx_session()
  loop
    select nom into v_nom from mission where id = a.mission_id;
    if a.or_verse > 0 then
      update partie_etat set or_compagnie = or_compagnie - a.or_verse where id;
    end if;
    if a.objet_id is not null then
      if _arsenal_quantite(a.objet_id) < a.quantite then
        raise exception 'Annulation impossible : la récompense de la mission « % » n''est plus dans l''arsenal.', v_nom;
      end if;
      perform _arsenal_retirer(a.objet_id, a.quantite);
    end if;
    delete from mission_attribution where id = a.id;
    perform _journal('annulation', 'Mission « ' || v_nom || ' » annulée (+1 Instance annulé).', -a.or_verse,
      jsonb_build_object('mission', a.mission_id));
  end loop;
end;
$$;

create or replace function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  e quete_etat%rowtype;
  r record;
  b jsonb;
  v_avant integer;
  v_apres integer;
  v_vet_avant integer;
  v_vet_apres integer;
  v_energie integer;
  v_gagnants integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_mercs jsonb := '[]'::jsonb;
  v_boosts jsonb := '[]'::jsonb;
  v_boosts_gain jsonb := '[]'::jsonb;
  v_mat text;
  v_prev integer;
  v_myst_id uuid;
  v_myst_nom text;
  n integer;
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
  -- Les récompenses (or + objets + objet mystère) ne rejoignent l'arsenal qu'à la fermeture de la
  -- fenêtre de récompenses (quete_recompenses_recuperer) : ici elles sont seulement mises en attente.
  -- Un emplacement de récompense peut contenir l'objet « Récompense mystère » (code recompense-mystere) :
  -- il n'entre jamais dans l'arsenal, mais est remplacé, quantité fois, par un objet tiré au hasard
  -- (Armes, Boucliers, Objets divers, Produits alchimiques). L'objet « Boost de production » (code boost)
  -- n'entre pas non plus à l'arsenal : il active un boost de production (voir plus bas).
  for r in
    select qr.objet_id, qr.quantite, qr.materiau,
           (o.code_unique = 'recompense-mystere') as myst,
           (o.code_unique = 'boost') as boost,
           (select ch.objet_id from quete_recompense_choix ch where ch.quete_id = qr.quete_id and ch.position = qr.position) as choix
      from quete_recompense qr join objet_catalogue o on o.id = qr.objet_id
      where qr.quete_id = q.id order by qr.position
  loop
    if r.boost then
      if r.materiau is not null then
        v_boosts := v_boosts || jsonb_build_object('objet_id', r.objet_id, 'materiau', r.materiau, 'instances', 3);
      end if;
    elsif r.myst and r.choix is not null then
      -- Récompense choisie par le MJ mais cachée aux joueurs (« ? ») : donnée telle quelle, sans tirage.
      select o2.nom into v_myst_nom from objet_catalogue o2 where o2.id = r.choix;
      v_items := v_items || jsonb_build_object('objet_id', r.choix, 'quantite', r.quantite, 'mystere', true, 'nom', v_myst_nom);
    elsif r.myst then
      for n in 1..r.quantite loop
        select t.id, t.nom into v_myst_id, v_myst_nom from _objet_mystere_tirer() t;
        if v_myst_id is not null then
          v_items := v_items || jsonb_build_object('objet_id', v_myst_id, 'quantite', 1, 'mystere', true, 'nom', v_myst_nom);
        end if;
      end loop;
    else
      v_items := v_items || jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite);
    end if;
  end loop;
  -- Boosts de production : actifs tout de suite (3 instances, celle-ci comprise), renouvelés à 3 s'il en restait.
  for b in select * from jsonb_array_elements(v_boosts)
  loop
    v_mat := b ->> 'materiau';
    select case v_mat when 'bois' then boost_bois when 'fer' then boost_fer else boost_cuir end
      into v_prev from partie_etat where id;
    update partie_etat
      set boost_bois = case when v_mat = 'bois' then 3 else boost_bois end,
          boost_fer = case when v_mat = 'fer' then 3 else boost_fer end,
          boost_cuir = case when v_mat = 'cuir' then 3 else boost_cuir end
      where id;
    v_boosts_gain := v_boosts_gain || jsonb_build_object('materiau', v_mat, 'avant', coalesce(v_prev, 0), 'apres', 3);
  end loop;
  for r in select position, mercenaire_id from quete_mercenaire where quete_id = q.id order by position
  loop
    v_vet_avant := _vet(r.mercenaire_id);
    select st.energie_actuelle into v_energie
      from mercenaire_etat st
      where st.mercenaire_id = r.mercenaire_id and st.session_id = ctx_session();
    if v_vet_avant > q.facteur_puissance then
      v_vet_apres := v_vet_avant;
    else
      v_vet_apres := v_vet_avant + 1;
      insert into mercenaire_etat (session_id, mercenaire_id, veterance)
        values (ctx_session(), r.mercenaire_id, v_vet_apres)
        on conflict (session_id, mercenaire_id) do update set veterance = excluded.veterance;
      v_gagnants := v_gagnants + 1;
    end if;
    -- Énergie : retour au maximum (vide = maximum).
    update mercenaire_etat set energie_actuelle = null
      where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    v_mercs := v_mercs || jsonb_build_object('mercenaire_id', r.mercenaire_id, 'position', r.position,
      'veterance_avant', v_vet_avant, 'veterance_apres', v_vet_apres, 'energie_avant', v_energie,
      'effets', _effets_snapshot(r.mercenaire_id),
      'sante_avant', (select st2.sante_actuelle from mercenaire_etat st2
        where st2.mercenaire_id = r.mercenaire_id and st2.session_id = ctx_session()));
  end loop;
  perform _effets_fin_quete(q.id);
  delete from quete_mercenaire where quete_id = q.id;
  update quete_etat
    set en_cours = false, terminee_le = now(), instances_restantes = 0,
        recompenses_attente = jsonb_build_object('quete_id', q.id, 'nom', q.nom,
          'or', q.recompense_or, 'items', v_items, 'boosts', v_boosts)
    where quete_id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : récompenses à récupérer, '
      || v_gagnants || ' mercenaire(s) gagnent +1 de vétérance ; l''énergie des mercenaires engagés revient au maximum.'
      || case when jsonb_array_length(v_boosts) > 0 then ' Boost de production activé.' else '' end,
    0, jsonb_build_object('quete_terminee', q.id, 'mercenaires', v_mercs, 'boosts', v_boosts_gain));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs, 'mystere_nom', v_myst_nom,
    'boosts', v_boosts, 'boosts_gain', v_boosts_gain,
    'attente', true);
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
  v_attente jsonb;
  v_mat text;
  e jsonb;
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
  select recompenses_attente into v_attente from quete_etat where quete_id = v_quete;
  if v_attente is not null then
    -- Récompenses pas encore récupérées : rien n'est entré dans l'arsenal, on les abandonne.
    update quete_etat set recompenses_attente = null where quete_id = v_quete;
  else
    if coalesce((p_gains ->> 'or')::integer, 0) > 0 then
      update partie_etat set or_compagnie = or_compagnie - (p_gains ->> 'or')::integer where id;
    end if;
    for i in select * from jsonb_array_elements(coalesce(p_gains -> 'items', '[]'::jsonb))
    loop
      perform _arsenal_retirer((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
    end loop;
  end if;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'boosts_gain', '[]'::jsonb))
  loop
    v_mat := i ->> 'materiau';
    update partie_etat
      set boost_bois = case when v_mat = 'bois' and boost_bois = (i ->> 'apres')::integer then (i ->> 'avant')::integer else boost_bois end,
          boost_fer = case when v_mat = 'fer' and boost_fer = (i ->> 'apres')::integer then (i ->> 'avant')::integer else boost_fer end,
          boost_cuir = case when v_mat = 'cuir' and boost_cuir = (i ->> 'apres')::integer then (i ->> 'avant')::integer else boost_cuir end
      where id;
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
    -- L'énergie d'avant la fin de la quête est reprise (seulement si elle n'a pas été modifiée depuis).
    if (i ->> 'energie_avant') is not null then
      update mercenaire_etat
        set energie_actuelle = (i ->> 'energie_avant')::integer
        where mercenaire_id = v_merc and session_id = ctx_session() and energie_actuelle is null;
    end if;
    -- Effets temporaires consommés à la fin de la quête (ou PV temporaires disparus) : ils reviennent tels quels.
    if exists (select 1 from recrutement where mercenaire_id = v_merc) then
      for e in select * from jsonb_array_elements(coalesce(i -> 'effets', '[]'::jsonb))
      loop
        insert into mercenaire_effet
          select * from jsonb_populate_record(null::mercenaire_effet, e)
          on conflict (id) do update
            set valeur = excluded.valeur, quetes_restantes = excluded.quetes_restantes;
      end loop;
    end if;
    -- Santé actuelle ramenée au maximum à la fin de la quête : rétablie (seulement si elle n'a pas bougé depuis).
    if (i ->> 'sante_avant') is not null then
      update mercenaire_etat
        set sante_actuelle = (i ->> 'sante_avant')::integer
        where mercenaire_id = v_merc and session_id = ctx_session()
          and sante_actuelle = least((i ->> 'sante_avant')::integer, _sante_max(v_merc));
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
  perform _missions_annuler_evenement('quete_reussie');
  perform _journal('annulation', 'Quête accomplie annulée (+1 Instance annulé).',
    case when v_attente is null then -coalesce((p_gains ->> 'or')::integer, 0) else 0 end, jsonb_build_object('annule_quete', p_gains ->> 'quete_id'));
end;
$$;

create or replace function mission_reclamer(p_attribution uuid, p_mercenaire uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  a mission_attribution%rowtype;
  m mission%rowtype;
  v_nom_objet text;
  v_nom_merc text;
  v_message text;
begin
  perform _verrou_partie();
  select * into a from mission_attribution where id = p_attribution for update;
  if not found then
    raise exception 'Récompense introuvable.';
  end if;
  if a.user_id is distinct from auth.uid() then
    raise exception 'Cette récompense est destinée à un autre joueur.';
  end if;
  if a.reclamee_le is not null or (a.objet_id is null and a.effet_stat is null) then
    raise exception 'Cette récompense a déjà été reçue.';
  end if;
  if not exists (select 1 from recrutement where mercenaire_id = p_mercenaire and user_id = auth.uid()) then
    raise exception 'Choisissez l''un de vos mercenaires.';
  end if;
  select * into m from mission where id = a.mission_id;
  select nom into v_nom_merc from mercenaire where id = p_mercenaire;
  if a.effet_stat is not null and exists (
    select 1 from mercenaire_effet where mercenaire_id = p_mercenaire and session_id = ctx_session()) then
    raise exception '% a déjà un effet temporaire non dépensé : choisissez un autre mercenaire.', v_nom_merc;
  end if;
  v_message := '';
  if a.objet_id is not null then
    select nom into v_nom_objet from objet_catalogue where id = a.objet_id;
    perform _sac_dos_ajouter(_sac_dos_id(p_mercenaire), a.objet_id, a.quantite, null, 'recevoir cette récompense');
    v_message := v_nom_objet || ' ×' || a.quantite || ' rejoint le sac à dos de ' || v_nom_merc || '.';
  end if;
  if a.effet_stat is not null then
    insert into mercenaire_effet (mercenaire_id, stat, valeur, quetes_restantes, mission_id)
      values (p_mercenaire, a.effet_stat, a.effet_valeur,
        case when a.effet_stat = 'pv_temp' then 1 else coalesce(a.effet_quetes, 1) end, a.mission_id);
    v_message := trim(v_message || ' ' || v_nom_merc || ' reçoit '
      || _effet_libelle(a.effet_stat, a.effet_valeur, coalesce(a.effet_quetes, 1))
      || ' (appliqué quand il part en quête).');
  end if;
  update mission_attribution set reclamee_le = now(), mercenaire_id = p_mercenaire where id = a.id;
  perform _journal(case when a.objet_id is not null then 'sac_envoi' else 'equipement' end,
    'Mission « ' || m.nom || ' » : ' || v_message, 0,
    jsonb_build_object('mission', m.id, 'mercenaire_id', p_mercenaire, 'objet_id', a.objet_id, 'effet', a.effet_stat));
  return jsonb_build_object('message', v_message);
end;
$$;

grant create on schema public to fortress_fn;
alter function _effets_snapshot(uuid) owner to fortress_fn;
alter function _missions_annuler_evenement(text) owner to fortress_fn;
alter function quetes_instance() owner to fortress_fn;
alter function quetes_annuler_instance(jsonb) owner to fortress_fn;
alter function mission_reclamer(uuid, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _effets_snapshot(uuid) from public;
revoke all on function _missions_annuler_evenement(text) from public;
