-- Soins et Ressourcement : mêmes bénéficiaires (Bruno, 2026-10-13).
--
--  * Soins : le lanceur peut se soigner lui-même.
--  * Ressourcement : bénéficiaire = le Druide, un mercenaire allié de la même quête, ou le compagnon / familier
--    d'un mercenaire de cette quête. Refusé sur les morts-vivants et les artificiels.
--  * PV temporaires d'un compagnon / familier : colonne `mercenaire_compagnon.pv_temp`, remise à zéro quand son
--    maître quitte la quête (comme les PV temporaires des mercenaires, qui disparaissent à la fin de la quête).

alter table mercenaire_compagnon add column pv_temp integer not null default 0 check (pv_temp >= 0);

create function _compagnon_pv_temp_fin()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update mercenaire_compagnon set pv_temp = 0
    where session_id = old.session_id and mercenaire_id = old.mercenaire_id and pv_temp > 0;
  return old;
end;
$$;
create trigger quete_mercenaire_compagnon_pv_temp
  after delete on quete_mercenaire
  for each row execute function _compagnon_pv_temp_fin();

-- Compagnon / familier : le patch d'état accepte `pv_temp` (en baisse seulement, sauf pour le MJ).
create or replace function compagnon_etat_maj(p_mercenaire uuid, p_patch jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_pv_actuel integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_patch ? 'reaction_utilisee' then
    if not exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
      raise exception 'Ce mercenaire n''est pas engagé dans une quête.';
    end if;
    if not coalesce((p_patch ->> 'reaction_utilisee')::boolean, true) and not is_admin() then
      raise exception 'La réaction redevient disponible quand le MJ clique sur Rd.';
    end if;
  end if;
  if p_patch ? 'pv_temp' then
    select pv_temp into v_pv_actuel from mercenaire_compagnon
      where mercenaire_id = p_mercenaire and session_id = ctx_session();
    if (p_patch ->> 'pv_temp')::integer < 0 then
      raise exception 'PV temporaires invalides.';
    end if;
    if coalesce(v_pv_actuel, 0) < (p_patch ->> 'pv_temp')::integer and not is_admin() then
      raise exception 'Les PV temporaires ne se gagnent que par le Ressourcement.';
    end if;
  end if;
  update mercenaire_compagnon set
    sante_actuelle = case when p_patch ? 'sante_actuelle' then (p_patch ->> 'sante_actuelle')::integer else sante_actuelle end,
    energie_actuelle = case when p_patch ? 'energie_actuelle' then (p_patch ->> 'energie_actuelle')::integer else energie_actuelle end,
    etat = case when p_patch ? 'etat' then nullif(p_patch ->> 'etat', '') else etat end,
    etat_niveau = case when p_patch ? 'etat_niveau' then (p_patch ->> 'etat_niveau')::smallint else etat_niveau end,
    etat_rounds = case when p_patch ? 'etat_rounds' then (p_patch ->> 'etat_rounds')::smallint else etat_rounds end,
    commentaires = case when p_patch ? 'commentaires' then coalesce(p_patch ->> 'commentaires', '') else commentaires end,
    reaction_utilisee = case when p_patch ? 'reaction_utilisee' then coalesce((p_patch ->> 'reaction_utilisee')::boolean, false) else reaction_utilisee end,
    reaction_rd = case when p_patch ? 'reaction_utilisee' then false else reaction_rd end,
    pv_temp = case when p_patch ? 'pv_temp' then (p_patch ->> 'pv_temp')::integer else pv_temp end
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  if not found then
    raise exception 'Ce mercenaire n''a pas de compagnon.';
  end if;
end;
$$;

-- Soins : le lanceur peut se soigner lui-même (seule la ligne de refus disparaît).
create or replace function soins_lancer(p_mercenaire uuid, p_competence uuid, p_montant integer, p_cible_type text, p_cible uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_nom text;
  v_merc text;
  v_vet integer;
  v_mult integer;
  v_gain integer;
  v_quete uuid;
  v_nom_cible text;
  v_max integer;
  v_act integer;
  v_nouvelle integer;
  v_reste integer;
  v_creature_id uuid;
  v_type text;
  v_role text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_montant is null or p_montant < 1 or p_montant > 10 then
    raise exception 'Le montant à dépenser est un entier de 1 à 10.';
  end if;
  if p_cible_type not in ('mercenaire', 'compagnon') or p_cible is null then
    raise exception 'Choisissez qui vous soignez.';
  end if;
  v_vet := _vet(p_mercenaire);
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= v_vet
      and lower(btrim(o.nom)) = 'soins'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas le sort Soins actif de ce mercenaire.';
  end if;

  select quete_id into v_quete from quete_mercenaire
    where mercenaire_id = p_mercenaire and session_id = ctx_session() limit 1;
  if v_quete is null then
    raise exception 'Le lanceur doit être engagé dans une quête pour soigner.';
  end if;
  if not exists (select 1 from quete_mercenaire
                 where mercenaire_id = p_cible and quete_id = v_quete and session_id = ctx_session()) then
    raise exception 'Ce mercenaire n''est pas engagé dans la même quête.';
  end if;

  v_mult := case when v_vet >= 10 then 4 when v_vet >= 6 then 3 when v_vet >= 3 then 2 else 1 end;
  v_gain := p_montant * v_mult;
  select nom into v_merc from mercenaire where id = p_mercenaire;

  if p_cible_type = 'compagnon' then
    select c.id, c.type, c.sante_max, mc.role
      into v_creature_id, v_type, v_max, v_role
      from mercenaire_compagnon mc join creature c on c.id = mc.creature_id
      where mc.mercenaire_id = p_cible and mc.session_id = ctx_session() for update of mc;
    if v_creature_id is null then
      raise exception 'Ce mercenaire n''a ni compagnon ni familier.';
    end if;
    if lower(coalesce(v_type, '')) in ('mort-vivant', 'créature artificielle', 'artificiel') then
      raise exception 'Soins n''a aucun effet sur les morts-vivants et les artificiels.';
    end if;
    select coalesce(sante_actuelle, v_max) into v_act from mercenaire_compagnon
      where mercenaire_id = p_cible and session_id = ctx_session();
    perform mercenaire_depenser_energie(p_mercenaire, p_montant);
    v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
    update mercenaire_compagnon
      set sante_actuelle = case when v_nouvelle >= v_max then null else v_nouvelle end
      where mercenaire_id = p_cible and session_id = ctx_session();
    select 'le ' || v_role || ' de ' || nom into v_nom_cible from mercenaire where id = p_cible;
  else
    select nom into v_nom_cible from mercenaire where id = p_cible;
    perform mercenaire_depenser_energie(p_mercenaire, p_montant);
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), p_cible, _vet(p_cible))
      on conflict (session_id, mercenaire_id) do nothing;
    v_max := _sante_max(p_cible);
    select coalesce(e.sante_actuelle, v_max) into v_act from mercenaire_etat e
      where e.session_id = ctx_session() and e.mercenaire_id = p_cible for update;
    v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
    update mercenaire_etat set sante_actuelle = case when v_nouvelle >= v_max then null else v_nouvelle end
      where session_id = ctx_session() and mercenaire_id = p_cible;
    if exists (select 1 from infirmerie_place where mercenaire_id = p_cible) then
      v_reste := _soins_instances(p_cible, case when v_nouvelle >= v_max then null else v_nouvelle end);
      if v_reste = 0 then
        delete from infirmerie_place where mercenaire_id = p_cible;
      else
        update infirmerie_place set restant = v_reste where mercenaire_id = p_cible;
      end if;
    end if;
  end if;

  perform _journal('equipement', v_merc || ' lance Soins sur ' || v_nom_cible || ' : ' || p_montant
    || ' énergie(s), +' || (v_nouvelle - v_act) || ' PV.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'cible_id', p_cible, 'cible_type', p_cible_type,
      'competence_id', p_competence, 'soin', v_nouvelle - v_act));
  return jsonb_build_object('soin', v_nouvelle - v_act, 'energie', p_montant, 'cible', v_nom_cible, 'multiplicateur', v_mult);
end;
$$;

-- Ressourcement : même liste de bénéficiaires que Soins ; PV temporaires du compagnon dans `pv_temp`.
drop function ressourcement_utiliser(uuid, uuid, integer, uuid);

create function ressourcement_utiliser(p_mercenaire uuid, p_competence uuid, p_montant integer,
                                       p_cible_type text default 'mercenaire', p_cible uuid default null)
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
  v_creature_id uuid;
  v_type text;
  v_role text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_montant is null or p_montant < 1 or p_montant > 10 then
    raise exception 'Le montant à dépenser est un entier de 1 à 10.';
  end if;
  if p_cible_type not in ('mercenaire', 'compagnon') then
    raise exception 'Bénéficiaire invalide.';
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

  -- Bénéficiaire : le Druide (ou son propre compagnon), ou quelqu'un de la même quête que lui.
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
  if p_cible_type = 'compagnon' then
    select c.id, c.type, mc.role into v_creature_id, v_type, v_role
      from mercenaire_compagnon mc join creature c on c.id = mc.creature_id
      where mc.mercenaire_id = v_cible and mc.session_id = ctx_session() for update of mc;
    if v_creature_id is null then
      raise exception 'Ce mercenaire n''a ni compagnon ni familier.';
    end if;
    if lower(coalesce(v_type, '')) in ('mort-vivant', 'créature artificielle', 'artificiel') then
      raise exception 'Le Ressourcement n''a aucun effet sur les morts-vivants et les artificiels.';
    end if;
    select 'le ' || v_role || ' de ' || nom into v_nom_cible from mercenaire where id = v_cible;
  else
    select nom into v_nom_cible from mercenaire where id = v_cible;
  end if;

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
  if p_cible_type = 'compagnon' then
    update mercenaire_compagnon set pv_temp = pv_temp + p_montant
      where mercenaire_id = v_cible and session_id = ctx_session();
  else
    insert into mercenaire_effet (mercenaire_id, stat, valeur, quetes_restantes)
      values (v_cible, 'pv_temp', p_montant, 1);
  end if;
  insert into mercenaire_ressourcement (mercenaire_id, competence_id, instance_no)
    values (p_mercenaire, p_competence, v_inst);
  perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' : ' || p_montant || ' PV temporaires pour '
    || v_nom_cible || ' (' || (v_n + 1) || ' / ' || v_total || ' cette instance).', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'cible_id', v_cible, 'cible_type', p_cible_type,
      'competence_id', p_competence, 'ressourcement', v_n + 1, 'pv_temp', p_montant));
  return jsonb_build_object('utilisees', v_n + 1, 'total', v_total, 'pv_temp', p_montant, 'cible', v_nom_cible);
end;
$$;

grant create on schema public to fortress_fn;
alter function compagnon_etat_maj(uuid, jsonb) owner to fortress_fn;
alter function soins_lancer(uuid, uuid, integer, text, uuid) owner to fortress_fn;
alter function ressourcement_utiliser(uuid, uuid, integer, text, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function ressourcement_utiliser(uuid, uuid, integer, text, uuid) from public;
grant execute on function ressourcement_utiliser(uuid, uuid, integer, text, uuid) to authenticated;
-- _compagnon_pv_temp_fin reste propriété de postgres (déclencheur, comme _reactions_apres_quete).
revoke all on function _compagnon_pv_temp_fin() from public;
