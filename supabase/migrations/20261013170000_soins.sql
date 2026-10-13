-- Soins (Bruno, 2026-10-13) : coût 1+ énergie ; un mercenaire allié, un compagnon ou un familier de la Compagnie
-- touché récupère autant de PV que d'énergie dépensée, ×2 à la vétérance 3, ×3 à la 6, ×4 à la 10. Sans effet sur
-- les morts-vivants et les artificiels ; jamais au-delà des PV max.
--
-- Même principe que le Ressourcement : l'énergie dépensée et les PV rendus sont gérés par le serveur, le joueur
-- choisit le bénéficiaire parmi les mercenaires de la même quête que le lanceur (lanceur exclu : le sort se lance
-- sur un allié « que vous touchez ») et les compagnons / familiers de ces mercenaires.
--
--  p_cible_type : 'mercenaire' (p_cible = le mercenaire soigné) ou 'compagnon' (p_cible = le mercenaire dont le
--  compagnon ou familier est soigné).

create function soins_lancer(p_mercenaire uuid, p_competence uuid, p_montant integer, p_cible_type text, p_cible uuid)
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
  if p_cible_type = 'mercenaire' and p_cible = p_mercenaire then
    raise exception 'Soins se lance sur un allié que vous touchez, pas sur vous-même.';
  end if;

  -- Le bénéficiaire (ou le maître du compagnon) doit être engagé dans la même quête que le lanceur.
  select quete_id into v_quete from quete_mercenaire
    where mercenaire_id = p_mercenaire and session_id = ctx_session() limit 1;
  if v_quete is null then
    raise exception 'Le lanceur doit être engagé dans une quête pour soigner un allié.';
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

grant create on schema public to fortress_fn;
alter function soins_lancer(uuid, uuid, integer, text, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function soins_lancer(uuid, uuid, integer, text, uuid) from public;
grant execute on function soins_lancer(uuid, uuid, integer, text, uuid) to authenticated;
