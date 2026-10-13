-- Restauration Partielle (Bruno, 2026-10-13) : coût 2 énergies ; le lanceur touche une créature (lui-même, un
-- mercenaire allié de la quête, ou un compagnon / familier) et met fin à l'un de ses états : Aveuglé, Assourdi,
-- Paralysé ou Empoisonné. (La Maladie n'a pas de représentation dans le site : elle se retire à la main.)
--
-- Mêmes bénéficiaires que Soins. L'état retiré est choisi par le joueur parmi ceux que porte la cible ; le
-- premier état (colonnes historiques) est remplacé par le suivant pour qu'il n'y ait jamais de « trou ».

create function restauration_partielle_lancer(p_mercenaire uuid, p_competence uuid, p_cible_type text, p_cible uuid, p_etat text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_nom text;
  v_merc text;
  v_quete uuid;
  v_nom_cible text;
  v_principal text;
  v_a_principal boolean := false;
  v_sup record;
  v_position smallint;
  v_creature_id uuid;
  v_role text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_cible_type not in ('mercenaire', 'compagnon') or p_cible is null then
    raise exception 'Choisissez qui vous touchez.';
  end if;
  if p_etat is null or p_etat not in ('aveugle', 'assourdi', 'paralyse', 'empoisonne') then
    raise exception 'Restauration Partielle ne retire que Aveuglé, Assourdi, Paralysé ou Empoisonné.';
  end if;
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
      and lower(btrim(o.nom)) = 'restauration partielle'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas Restauration Partielle (active) pour ce mercenaire.';
  end if;

  select quete_id into v_quete from quete_mercenaire
    where mercenaire_id = p_mercenaire and session_id = ctx_session() limit 1;
  if v_quete is null then
    raise exception 'Le lanceur doit être engagé dans une quête.';
  end if;
  if not exists (select 1 from quete_mercenaire
                 where mercenaire_id = p_cible and quete_id = v_quete and session_id = ctx_session()) then
    raise exception 'Ce mercenaire n''est pas engagé dans la même quête.';
  end if;

  -- Où se trouve l'état à retirer : premier état ou état supplémentaire.
  if p_cible_type = 'compagnon' then
    select mc.role, mc.etat, 'le ' || mc.role || ' de ' || m.nom
      into v_role, v_principal, v_nom_cible
      from mercenaire_compagnon mc join mercenaire m on m.id = mc.mercenaire_id
      where mc.mercenaire_id = p_cible and mc.session_id = ctx_session() for update of mc;
    if v_role is null then
      raise exception 'Ce mercenaire n''a ni compagnon ni familier.';
    end if;
  else
    select nom into v_nom_cible from mercenaire where id = p_cible;
    select etat into v_principal from mercenaire_etat
      where mercenaire_id = p_cible and session_id = ctx_session() for update;
  end if;
  v_a_principal := v_principal is not distinct from p_etat;
  select position into v_position from etat_supplementaire
    where session_id = ctx_session() and cible = p_cible_type and cible_id = p_cible and etat = p_etat;
  if not v_a_principal and v_position is null then
    raise exception '% n''a pas l''état demandé.', v_nom_cible;
  end if;

  perform mercenaire_depenser_energie(p_mercenaire, 2);

  if v_a_principal then
    -- Le premier supplémentaire (s'il existe) devient le premier état ; le second monte d'un rang.
    select * into v_sup from etat_supplementaire
      where session_id = ctx_session() and cible = p_cible_type and cible_id = p_cible and position = 1;
    if p_cible_type = 'compagnon' then
      update mercenaire_compagnon
        set etat = v_sup.etat, etat_niveau = coalesce(v_sup.niveau, 1), etat_rounds = coalesce(v_sup.rounds, 0)
        where mercenaire_id = p_cible and session_id = ctx_session();
    else
      update mercenaire_etat
        set etat = v_sup.etat, etat_niveau = coalesce(v_sup.niveau, 1), etat_rounds = coalesce(v_sup.rounds, 0),
            etat_efface = null, etat_decremente = false
        where mercenaire_id = p_cible and session_id = ctx_session();
    end if;
    if v_sup.id is not null then
      delete from etat_supplementaire where id = v_sup.id;
      update etat_supplementaire set position = 1
        where session_id = ctx_session() and cible = p_cible_type and cible_id = p_cible and position = 2;
    end if;
  else
    delete from etat_supplementaire
      where session_id = ctx_session() and cible = p_cible_type and cible_id = p_cible and etat = p_etat;
    if v_position = 1 then
      update etat_supplementaire set position = 1
        where session_id = ctx_session() and cible = p_cible_type and cible_id = p_cible and position = 2;
    end if;
  end if;

  select nom into v_merc from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_merc || ' lance Restauration Partielle sur ' || v_nom_cible || ' : l''état '
    || p_etat || ' prend fin.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'cible_id', p_cible, 'cible_type', p_cible_type,
      'competence_id', p_competence, 'etat_retire', p_etat));
  return jsonb_build_object('cible', v_nom_cible, 'etat', p_etat);
end;
$$;

grant create on schema public to fortress_fn;
alter function restauration_partielle_lancer(uuid, uuid, text, uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function restauration_partielle_lancer(uuid, uuid, text, uuid, text) from public;
grant execute on function restauration_partielle_lancer(uuid, uuid, text, uuid, text) to authenticated;
