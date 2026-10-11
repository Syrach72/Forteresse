-- Missions : événements prêts à l'emploi (Bruno, 2026-10-11). Plus besoin de « brancher » : le menu de
-- l'administration propose uniquement des événements qui se déclenchent tout seuls.
--
-- * quete_reussie / quete_reussie_sans_blessure : désormais aussi pour les missions INDIVIDUELLES, au profit de
--   chaque joueur qui avait au moins un mercenaire engagé dans la quête (avant, seules les missions collectives
--   se déclenchaient).
-- * quete_echouee : quête échouée (collectif, et chaque joueur qui avait un mercenaire engagé).
-- * niveau_gagne : un mercenaire gagne un niveau de vétérance (au profit de son recruteur ; quelle que soit
--   l'origine : quête, entraînement ou correction du MJ). Un niveau perdu (annulation) retire le compte.
-- * entrainement_termine : un élève rejoint le niveau de son instructeur (au profit de son recruteur).
-- * La valeur « a_brancher » reste acceptée pour les anciennes missions : elles ne se déclenchent pas.

alter table mission drop constraint if exists mission_evenement_check;
alter table mission add constraint mission_evenement_check
  check (evenement in ('recrutement_paye', 'quete_reussie', 'quete_reussie_sans_blessure', 'quete_echouee',
    'niveau_gagne', 'entrainement_termine', 'a_brancher'));

-- Événement qui ne concerne qu'UN joueur : compteur personnel +1 et missions individuelles (pas de compteur
-- collectif : il est déjà incrémenté par l'appel sans joueur).
create or replace function _mission_evenement_joueur(p_evenement text, p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_perso integer;
  m record;
begin
  if p_user is null then
    return;
  end if;
  insert into mission_compteur (evenement, user_id, valeur) values (p_evenement, p_user, 1)
    on conflict (session_id, evenement, user_id) do update set valeur = mission_compteur.valeur + 1
    returning valeur into v_perso;
  for m in select id, seuil from mission
           where actif and evenement = p_evenement and rubrique = 'individuelle' order by ordre
  loop
    if v_perso >= m.seuil then
      perform _mission_attribuer(m.id, p_user);
    end if;
  end loop;
end;
$$;

-- Défait des occurrences d'un événement (annulation d'un +1 Instance) : compteurs personnel et collectif.
-- Les missions déjà attribuées restent acquises.
create or replace function _mission_compteur_retirer(p_evenement text, p_user uuid, p_n integer,
  p_collectif boolean default true)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_zero constant uuid := '00000000-0000-0000-0000-000000000000';
begin
  update mission_compteur set valeur = greatest(valeur - greatest(p_n, 0), 0)
    where session_id = ctx_session() and evenement = p_evenement
      and ((p_collectif and user_id = v_zero) or user_id = p_user);
end;
$$;

-- Niveau de vétérance gagné (ou retiré) : compte pour le recruteur du mercenaire.
create or replace function _mission_declencheur_niveau()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_avant integer;
  v_user uuid;
  i integer;
begin
  if tg_op = 'INSERT' then
    select m.veterance into v_avant from mercenaire m where m.id = new.mercenaire_id;
  else
    v_avant := old.veterance;
  end if;
  if v_avant is null or new.veterance is null or new.veterance = v_avant then
    return null;
  end if;
  select r.user_id into v_user from recrutement r
    where r.mercenaire_id = new.mercenaire_id and r.session_id = new.session_id;
  if new.veterance > v_avant then
    for i in 1..least(new.veterance - v_avant, 10) loop
      perform _mission_evenement('niveau_gagne', v_user);
    end loop;
  else
    perform _mission_compteur_retirer('niveau_gagne', v_user, v_avant - new.veterance);
  end if;
  return null;
exception when others then
  -- une erreur de mission ne doit jamais empêcher une montée de niveau
  raise warning 'missions : %', sqlerrm;
  return null;
end;
$$;
create trigger mission_niveau after insert or update of veterance on mercenaire_etat
  for each row execute function _mission_declencheur_niveau();

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
  v_joueur uuid;
  v_gain integer;
  v_res jsonb;
  v_energie integer;
  v_gagnants integer := 0;
  v_sans_blessure boolean;
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
    -- Expérience (Bruno, 2026-10-11) : le gain dépend de l'écart entre le FP de la quête et la vétérance
    -- du mercenaire (+2 ou plus : 15 XP, +1 : 12, 0 : 10, -1 : 6, -2 : 3, au-delà : 0). L'XP en trop est reportée.
    v_gain := _xp_gain_quete(q.facteur_puissance, v_vet_avant);
    v_res := _xp_ajouter(r.mercenaire_id, v_gain);
    v_vet_apres := (v_res ->> 'veterance_apres')::integer;
    if v_gain > 0 then
      v_gagnants := v_gagnants + 1;
    end if;
    -- Énergie : retour au maximum (vide = maximum).
    update mercenaire_etat set energie_actuelle = null
      where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    v_mercs := v_mercs || jsonb_build_object('mercenaire_id', r.mercenaire_id, 'position', r.position,
      'veterance_avant', v_vet_avant, 'veterance_apres', v_vet_apres, 'energie_avant', v_energie,
      'xp_gain', v_gain, 'xp_avant', v_res -> 'xp_avant', 'xp_apres', v_res -> 'xp_apres',
      'effets', _effets_snapshot(r.mercenaire_id),
      'sante_avant', (select st2.sante_actuelle from mercenaire_etat st2
        where st2.mercenaire_id = r.mercenaire_id and st2.session_id = ctx_session()));
  end loop;
  -- Mission « quête réussie sans blessure » : aucun mercenaire engagé n'a de santé actuelle sous son maximum.
  v_sans_blessure := not exists (
    select 1 from quete_mercenaire qm
      join mercenaire_etat me on me.mercenaire_id = qm.mercenaire_id and me.session_id = ctx_session()
      where qm.quete_id = q.id and qm.session_id = ctx_session()
        and me.sante_actuelle is not null and me.sante_actuelle < _sante_max(qm.mercenaire_id));
  if v_sans_blessure then
    perform _mission_evenement('quete_reussie_sans_blessure', null);
  end if;
  -- Missions individuelles : chaque joueur qui avait au moins un mercenaire engagé dans la quête.
  for v_joueur in
    select distinct rc.user_id
      from quete_mercenaire qm join recrutement rc on rc.mercenaire_id = qm.mercenaire_id
      where qm.quete_id = q.id and qm.session_id = ctx_session() and rc.user_id is not null
  loop
    perform _mission_evenement_joueur('quete_reussie', v_joueur);
    if v_sans_blessure then
      perform _mission_evenement_joueur('quete_reussie_sans_blessure', v_joueur);
    end if;
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
      || v_gagnants || ' mercenaire(s) gagnent de l''expérience ; l''énergie des mercenaires engagés revient au maximum.'
      || case when jsonb_array_length(v_boosts) > 0 then ' Boost de production activé.' else '' end,
    0, jsonb_build_object('quete_terminee', q.id, 'mercenaires', v_mercs, 'boosts', v_boosts_gain));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs, 'mystere_nom', v_myst_nom,
    'boosts', v_boosts, 'boosts_gain', v_boosts_gain,
    'sans_blessure', v_sans_blessure,
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
  v_user uuid;
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
    -- L'expérience (et la vétérance qu'elle a fait gagner) est reprise, seulement si elle n'a pas bougé depuis.
    if (i ->> 'xp_apres') is not null then
      update mercenaire_etat
        set veterance = (i ->> 'veterance_avant')::integer, xp = (i ->> 'xp_avant')::integer
        where mercenaire_id = v_merc and session_id = ctx_session()
          and veterance = (i ->> 'veterance_apres')::integer
          and xp = (i ->> 'xp_apres')::integer;
    elsif coalesce((i ->> 'veterance_apres')::integer, 0) > coalesce((i ->> 'veterance_avant')::integer, 0) then
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
  if coalesce((p_gains ->> 'sans_blessure')::boolean, false) then
    perform _missions_annuler_evenement('quete_reussie_sans_blessure');
  end if;
  -- Comptes personnels des missions individuelles (les missions déjà données restent acquises).
  for v_user in
    select distinct rc.user_id from recrutement rc
      where rc.mercenaire_id in (
        select (x ->> 'mercenaire_id')::uuid from jsonb_array_elements(coalesce(p_gains -> 'mercenaires', '[]'::jsonb)) x)
        and rc.user_id is not null
  loop
    perform _mission_compteur_retirer('quete_reussie', v_user, 1, false);
    if coalesce((p_gains ->> 'sans_blessure')::boolean, false) then
      perform _mission_compteur_retirer('quete_reussie_sans_blessure', v_user, 1, false);
    end if;
  end loop;
  perform _journal('annulation', 'Quête accomplie annulée (+1 Instance annulé).',
    case when v_attente is null then -coalesce((p_gains ->> 'or')::integer, 0) else 0 end, jsonb_build_object('annule_quete', p_gains ->> 'quete_id'));
end;
$$;

create or replace function quetes_echec()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  v_id uuid;
  r record;
  v_gain integer;
  v_joueur uuid;
  v_res jsonb;
  v_mercs jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  perform _verrou_partie();
  select quete_id into v_id from quete_etat where en_cours for update;
  if v_id is null then
    return null;
  end if;
  select * into q from quete where id = v_id;
  for r in select mercenaire_id from quete_mercenaire where quete_id = v_id order by position
  loop
    v_gain := _xp_gain_quete(q.facteur_puissance, _vet(r.mercenaire_id)) / 4;
    v_res := _xp_ajouter(r.mercenaire_id, v_gain);
    v_mercs := v_mercs || jsonb_build_object('mercenaire_id', r.mercenaire_id, 'xp_gain', v_gain,
      'veterance_avant', v_res -> 'veterance_avant', 'veterance_apres', v_res -> 'veterance_apres');
  end loop;
  -- Missions « quête échouée » : la compagnie, puis chaque joueur qui avait un mercenaire engagé.
  perform _mission_evenement('quete_echouee', null);
  for v_joueur in
    select distinct rc.user_id
      from quete_mercenaire qm join recrutement rc on rc.mercenaire_id = qm.mercenaire_id
      where qm.quete_id = v_id and qm.session_id = ctx_session() and rc.user_id is not null
  loop
    perform _mission_evenement_joueur('quete_echouee', v_joueur);
  end loop;
  perform _effets_fin_quete(v_id);
  delete from quete_mercenaire where quete_id = v_id;
  update quete_etat
    set en_cours = false, instances_restantes = null,
        echec_attente = jsonb_build_object('id', gen_random_uuid(), 'quete_id', q.id, 'nom', q.nom, 'le', now())
    where quete_id = v_id;
  perform _journal('or', q.nom || ' : echec de la quete. Aucune recompense (le quart de l''experience est tout de meme acquis) ; la quete redevient disponible.',
    0, jsonb_build_object('quete_echec', q.id));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom, 'echec', true, 'mercenaires', v_mercs);
end;
$$;

create or replace function entrainement_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_instr uuid;
  v_vinstr integer;
  v_g integer;
  r record;
  v_avant integer;
  v_apres integer;
  v_gradue boolean;
  v_pal integer;
  v_n integer;
  v_gain integer;
  v_res jsonb;
  v_termine boolean;
  v_xp_avant integer;
  v_xp_apres integer;
  v_gains jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for v_g in 1..2 loop
    select p.mercenaire_id into v_instr
      from entrainement_place p where p.role = 'instructeur' and p.groupe = v_g;
    if not found then
      continue;
    end if;
    v_vinstr := _vet(v_instr);
    for r in
      select p.position, p.mercenaire_id as mid, _vet(p.mercenaire_id) as vet
      from entrainement_place p
      where p.role = 'eleve' and p.groupe = v_g
      order by p.position
      for update of p
    loop
      v_avant := r.vet;
      select e.xp into v_xp_avant from mercenaire_etat e
        where e.session_id = ctx_session() and e.mercenaire_id = r.mid;
      v_xp_avant := coalesce(v_xp_avant, 0);
      v_pal := _xp_palier(v_avant);
      v_n := 0;
      v_termine := false;
      v_gain := 0;
      if v_avant >= v_vinstr or v_pal is null then
        -- Déjà au niveau de l'instructeur (ou au niveau maximum) : il retourne à la caserne.
        v_apres := v_avant;
        v_xp_apres := v_xp_avant;
        v_gradue := true;
      else
        -- Une part du palier par instance : 1 instance par niveau à 3 niveaux d'écart ou plus, 2 à 2 niveaux,
        -- 3 à 1 niveau (arrondi au supérieur pour ne jamais ajouter d'instance).
        v_n := _xp_formation_instances(v_vinstr - v_avant);
        v_gain := ceil(v_pal::numeric / v_n)::integer;
        v_res := _xp_ajouter(r.mid, v_gain);
        v_apres := (v_res ->> 'veterance_apres')::integer;
        v_xp_apres := (v_res ->> 'xp_apres')::integer;
        v_gradue := v_apres >= v_vinstr;
        v_termine := v_gradue;
      end if;
      if v_termine then
        -- Mission « entraînement terminé » : au profit du recruteur de l'élève.
        perform _mission_evenement('entrainement_termine',
          (select rc.user_id from recrutement rc where rc.mercenaire_id = r.mid));
      end if;
      if v_gradue then
        delete from entrainement_place where mercenaire_id = r.mid;
      end if;
      v_gains := v_gains || jsonb_build_object(
        'mercenaire_id', r.mid, 'groupe', v_g, 'position', r.position,
        'de', v_avant, 'a', v_apres, 'gradue', v_gradue,
        'xp_gain', v_gain, 'xp_avant', v_xp_avant, 'xp_apres', v_xp_apres, 'instances', v_n,
        'termine', v_termine);
    end loop;
  end loop;
  return v_gains;
end;
$$;

create or replace function entrainement_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
  v_id uuid;
  v_g integer;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    v_id := (g ->> 'mercenaire_id')::uuid;
    v_g := coalesce((g ->> 'groupe')::integer, 1);
    if (g ->> 'xp_apres') is not null then
      if (g ->> 'xp_avant') is distinct from (g ->> 'xp_apres') or (g ->> 'de') <> (g ->> 'a') then
        update mercenaire_etat
          set veterance = (g ->> 'de')::integer, xp = (g ->> 'xp_avant')::integer
          where mercenaire_id = v_id and session_id = ctx_session()
            and veterance = (g ->> 'a')::integer and xp = (g ->> 'xp_apres')::integer;
      end if;
    elsif (g ->> 'de')::integer <> (g ->> 'a')::integer then
      update mercenaire_etat
        set veterance = (g ->> 'de')::integer
        where mercenaire_id = v_id and session_id = ctx_session() and veterance = (g ->> 'a')::integer;
    end if;
    if coalesce((g ->> 'termine')::boolean, false) then
      perform _mission_compteur_retirer('entrainement_termine',
        (select rc.user_id from recrutement rc where rc.mercenaire_id = v_id), 1);
    end if;
    if (g ->> 'gradue')::boolean
       and exists (select 1 from entrainement_place where role = 'instructeur' and groupe = v_g)
       and not exists (select 1 from entrainement_place where mercenaire_id = v_id)
       and not exists (
         select 1 from entrainement_place
         where role = 'eleve' and groupe = v_g and position = (g ->> 'position')::integer)
    then
      insert into entrainement_place (groupe, role, position, mercenaire_id)
        values (v_g, 'eleve', (g ->> 'position')::integer, v_id);
    end if;
  end loop;
end;
$$;

grant create on schema public to fortress_fn;
alter function _mission_evenement_joueur(text, uuid) owner to fortress_fn;
alter function _mission_compteur_retirer(text, uuid, integer, boolean) owner to fortress_fn;
alter function _mission_declencheur_niveau() owner to fortress_fn;
alter function quetes_instance() owner to fortress_fn;
alter function quetes_annuler_instance(jsonb) owner to fortress_fn;
alter function quetes_echec() owner to fortress_fn;
alter function entrainement_instance() owner to fortress_fn;
alter function entrainement_annuler_instance(jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _mission_evenement_joueur(text, uuid) from public;
revoke all on function _mission_compteur_retirer(text, uuid, integer, boolean) from public;
revoke all on function _mission_declencheur_niveau() from public;
