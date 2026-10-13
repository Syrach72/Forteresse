-- Ressourcement : le Druide choisit le bénéficiaire des PV temporaires (Bruno, 2026-10-13) : lui-même ou n'importe
-- quel autre mercenaire engagé dans la même quête. Les PV temporaires sont créditées sur le bénéficiaire
-- (`mercenaire_effet`, stat 'pv_temp') ; l'énergie dépensée et l'utilisation comptée restent celles du Druide.

drop function ressourcement_utiliser(uuid, uuid, integer);

create function ressourcement_utiliser(p_mercenaire uuid, p_competence uuid, p_montant integer, p_cible uuid default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_inst integer;
  v_total integer;
  v_n integer;
  v_nom text;
  v_merc text;
  v_classe text;
  v_sous text;
  v_cible uuid := coalesce(p_cible, p_mercenaire);
  v_nom_cible text;
  v_quete uuid;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_montant is null or p_montant < 1 or p_montant > 10 then
    raise exception 'Le montant à dépenser est un entier de 1 à 10.';
  end if;
  select m.nom, translate(lower(coalesce(c.nom, '')), 'êîéèô', 'eieeo'),
         translate(lower(btrim(coalesce(m.sous_classe, ''))), 'êîéèô', 'eieeo')
    into v_merc, v_classe, v_sous
    from mercenaire m left join classe c on c.id = m.classe_id
    where m.id = p_mercenaire;
  if v_classe <> 'druide' or v_sous <> 'cercle de la terre' then
    raise exception 'Seul un Druide du Cercle de la Terre peut utiliser le Ressourcement.';
  end if;
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
      and o.nom ~* 'ressourcement'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas le Ressourcement actif de ce mercenaire.';
  end if;

  -- Bénéficiaire : le Druide, ou un mercenaire engagé dans la même quête que lui.
  if v_cible <> p_mercenaire then
    select quete_id into v_quete from quete_mercenaire
      where mercenaire_id = p_mercenaire and session_id = ctx_session() limit 1;
    if v_quete is null then
      raise exception 'Le Druide doit être engagé dans une quête pour soutenir un autre mercenaire.';
    end if;
    if not exists (select 1 from quete_mercenaire
                   where mercenaire_id = v_cible and quete_id = v_quete and session_id = ctx_session()) then
      raise exception 'Ce mercenaire n''est pas engagé dans la même quête.';
    end if;
  end if;
  select nom into v_nom_cible from mercenaire where id = v_cible;

  select instance_courante into v_inst from partie_etat where session_id = ctx_session();
  v_inst := coalesce(v_inst, 0);
  select count(*) into v_total from mercenaire_terrain_favori
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  select count(*) into v_n from mercenaire_ressourcement
    where mercenaire_id = p_mercenaire and session_id = ctx_session() and instance_no = v_inst;
  if v_n >= v_total then
    raise exception 'Ressourcement : les % utilisation(s) de cette instance sont déjà dépensées.', v_total;
  end if;

  perform mercenaire_depenser_energie(p_mercenaire, p_montant);
  insert into mercenaire_effet (mercenaire_id, stat, valeur, quetes_restantes)
    values (v_cible, 'pv_temp', p_montant, 1);
  insert into mercenaire_ressourcement (mercenaire_id, competence_id, instance_no)
    values (p_mercenaire, p_competence, v_inst);
  perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' : ' || p_montant || ' PV temporaires pour '
    || v_nom_cible || ' (' || (v_n + 1) || ' / ' || v_total || ' cette instance).', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'cible_id', v_cible, 'competence_id', p_competence,
      'ressourcement', v_n + 1, 'pv_temp', p_montant));
  return jsonb_build_object('utilisees', v_n + 1, 'total', v_total, 'pv_temp', p_montant, 'cible', v_nom_cible);
end;
$$;

grant create on schema public to fortress_fn;
alter function ressourcement_utiliser(uuid, uuid, integer, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function ressourcement_utiliser(uuid, uuid, integer, uuid) from public;
grant execute on function ressourcement_utiliser(uuid, uuid, integer, uuid) to authenticated;
