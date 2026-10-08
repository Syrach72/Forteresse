-- Missions individuelles : au plus 6 récompenses en attente par joueur (Bruno, 2026-10-08).
-- Un joueur qui a déjà 6 récompenses (objet ou effet) non données à un mercenaire ne reçoit pas de nouvelle
-- mission individuelle : elle reste à accomplir (son compteur continue) et se débloque dès qu'il en donne une.
-- _mission_rattraper() attribue alors les missions dont le seuil est déjà atteint.

create or replace function _mission_attribuer(p_mission uuid, p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  m mission%rowtype;
  v_id uuid;
  v_texte text;
begin
  select * into m from mission where id = p_mission;
  -- Plafond de 6 récompenses individuelles (objet ou effet) en attente : la mission attend qu'une place se libère.
  if m.rubrique = 'individuelle' and p_user is not null
     and (m.recompense_objet_id is not null or m.recompense_effet_stat is not null)
     and (select count(*) from mission_attribution
          where user_id = p_user and session_id = ctx_session() and reclamee_le is null) >= 6 then
    return;
  end if;
  insert into mission_attribution (mission_id, user_id, or_verse, objet_id, quantite,
      effet_stat, effet_valeur, effet_quetes, reclamee_le)
    values (m.id, p_user, m.recompense_or, m.recompense_objet_id, m.recompense_quantite,
      m.recompense_effet_stat, m.recompense_effet_valeur, m.recompense_effet_quetes,
      -- objet ou effet d'une mission individuelle : à réclamer (le joueur choisit le mercenaire)
      case when m.rubrique = 'individuelle'
             and (m.recompense_objet_id is not null or m.recompense_effet_stat is not null)
           then null else now() end)
    on conflict do nothing
    returning id into v_id;
  if v_id is null then
    return;
  end if;
  if m.recompense_or > 0 then
    update partie_etat set or_compagnie = or_compagnie + m.recompense_or where id;
  end if;
  if m.rubrique = 'collective' and m.recompense_objet_id is not null then
    perform _arsenal_ajouter(m.recompense_objet_id, m.recompense_quantite);
  end if;
  v_texte := concat_ws(' et ',
    case when m.recompense_or > 0 then '+' || m.recompense_or || ' Po' end,
    case when m.recompense_objet_id is not null
      then (select nom from objet_catalogue where id = m.recompense_objet_id) || ' ×' || m.recompense_quantite end,
    case when m.recompense_effet_stat is not null
      then _effet_libelle(m.recompense_effet_stat, m.recompense_effet_valeur, m.recompense_effet_quetes) end);
  perform _journal('or', 'Mission accomplie : « ' || m.nom || ' »'
    || case when v_texte <> '' then ' (' || v_texte || ').' else '.' end, m.recompense_or,
    jsonb_build_object('mission', m.id, 'rubrique', m.rubrique));
end;
$$;

create or replace function _mission_rattraper(p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  m record;
  v_val integer;
begin
  if p_user is null then
    return;
  end if;
  for m in select id, evenement, seuil from mission
    where actif and rubrique = 'individuelle' and evenement <> 'a_brancher' order by ordre
  loop
    select valeur into v_val from mission_compteur
      where session_id = ctx_session() and evenement = m.evenement and user_id = p_user;
    if coalesce(v_val, 0) >= m.seuil and not exists (
      select 1 from mission_attribution
      where session_id = ctx_session() and mission_id = m.id and user_id = p_user) then
      perform _mission_attribuer(m.id, p_user);
    end if;
  end loop;
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
  -- Une place vient de se libérer : les missions mises en attente par le plafond de 6 se débloquent.
  perform _mission_rattraper(auth.uid());
  return jsonb_build_object('message', v_message);
end;
$$;

grant create on schema public to fortress_fn;
alter function _mission_attribuer(uuid, uuid) owner to fortress_fn;
alter function _mission_rattraper(uuid) owner to fortress_fn;
alter function mission_reclamer(uuid, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _mission_rattraper(uuid) from public;
