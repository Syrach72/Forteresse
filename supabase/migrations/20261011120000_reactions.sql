-- Réaction (Bruno, 2026-10-11) : chaque mercenaire engagé dans une quête, chaque créature de la quête, chaque
-- compagnon animal et familier dispose d'une Réaction par round. Le joueur (ou le MJ) la dépense en cliquant sur le
-- bouton « Réaction » ; elle redevient disponible quand le MJ clique sur Rd.
--
-- * reaction_utilisee : la réaction est dépensée. reaction_rd : elle l'était avant le dernier Rd (pour que
--   « Annuler » le Rd la rende telle quelle).
-- * Rd (+1 au compteur) : tout redevient disponible ; Annuler (-1) : celles qui avaient été rendues par ce Rd
--   redeviennent dépensées ; remise à zéro du round : tout redevient disponible.
-- * Un mercenaire qui quitte la quête retrouve sa réaction (et son compagnon aussi).
-- * Un joueur peut seulement dépenser la réaction ; seul le MJ peut la rendre (en plus du Rd).

alter table mercenaire_etat
  add column reaction_utilisee boolean not null default false,
  add column reaction_rd boolean not null default false;
alter table creature_quete
  add column reaction_utilisee boolean not null default false,
  add column reaction_rd boolean not null default false;
alter table mercenaire_compagnon
  add column reaction_utilisee boolean not null default false,
  add column reaction_rd boolean not null default false;

-- Rd : propriétaire postgres (comme _creatures_round), il s'exécute pour la session de la ligne modifiée.
create function _reactions_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = old.round_courant + 1 then
    update mercenaire_etat set reaction_rd = reaction_utilisee, reaction_utilisee = false
      where session_id = new.session_id and (reaction_utilisee or reaction_rd);
    update creature_quete set reaction_rd = reaction_utilisee, reaction_utilisee = false
      where session_id = new.session_id and (reaction_utilisee or reaction_rd);
    update mercenaire_compagnon set reaction_rd = reaction_utilisee, reaction_utilisee = false
      where session_id = new.session_id and (reaction_utilisee or reaction_rd);
  elsif new.round_courant = old.round_courant - 1 then
    update mercenaire_etat set reaction_utilisee = true, reaction_rd = false
      where session_id = new.session_id and reaction_rd;
    update creature_quete set reaction_utilisee = true, reaction_rd = false
      where session_id = new.session_id and reaction_rd;
    update mercenaire_compagnon set reaction_utilisee = true, reaction_rd = false
      where session_id = new.session_id and reaction_rd;
  elsif new.round_courant = 0 and old.round_courant > 0 then
    update mercenaire_etat set reaction_utilisee = false, reaction_rd = false
      where session_id = new.session_id and (reaction_utilisee or reaction_rd);
    update creature_quete set reaction_utilisee = false, reaction_rd = false
      where session_id = new.session_id and (reaction_utilisee or reaction_rd);
    update mercenaire_compagnon set reaction_utilisee = false, reaction_rd = false
      where session_id = new.session_id and (reaction_utilisee or reaction_rd);
  end if;
  return new;
end;
$$;
create trigger partie_etat_round_reactions
  after update of round_courant on partie_etat
  for each row execute function _reactions_round();

-- Un mercenaire qui quitte la quête retrouve sa réaction, et son compagnon aussi.
create function _reactions_apres_quete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update mercenaire_etat set reaction_utilisee = false, reaction_rd = false
    where session_id = old.session_id and mercenaire_id = old.mercenaire_id
      and (reaction_utilisee or reaction_rd);
  update mercenaire_compagnon set reaction_utilisee = false, reaction_rd = false
    where session_id = old.session_id and mercenaire_id = old.mercenaire_id
      and (reaction_utilisee or reaction_rd);
  return old;
end;
$$;
create trigger quete_mercenaire_reaction
  after delete on quete_mercenaire
  for each row execute function _reactions_apres_quete();

-- Dépenser (ou, pour le MJ, rendre) la réaction d'un mercenaire engagé dans une quête.
create function reaction_definir(p_mercenaire uuid, p_utilisee boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire n''est pas engagé dans une quête.';
  end if;
  if not coalesce(p_utilisee, true) and not is_admin() then
    raise exception 'La réaction redevient disponible quand le MJ clique sur Rd.';
  end if;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
    on conflict (session_id, mercenaire_id) do nothing;
  update mercenaire_etat
    set reaction_utilisee = coalesce(p_utilisee, true), reaction_rd = false
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
end;
$$;

-- Compagnon animal / familier : même règle, par le patch d'état déjà utilisé par la fiche.
create or replace function compagnon_etat_maj(p_mercenaire uuid, p_patch jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
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
  update mercenaire_compagnon set
    sante_actuelle = case when p_patch ? 'sante_actuelle' then (p_patch ->> 'sante_actuelle')::integer else sante_actuelle end,
    energie_actuelle = case when p_patch ? 'energie_actuelle' then (p_patch ->> 'energie_actuelle')::integer else energie_actuelle end,
    etat = case when p_patch ? 'etat' then nullif(p_patch ->> 'etat', '') else etat end,
    etat_niveau = case when p_patch ? 'etat_niveau' then (p_patch ->> 'etat_niveau')::smallint else etat_niveau end,
    etat_rounds = case when p_patch ? 'etat_rounds' then (p_patch ->> 'etat_rounds')::smallint else etat_rounds end,
    commentaires = case when p_patch ? 'commentaires' then coalesce(p_patch ->> 'commentaires', '') else commentaires end,
    reaction_utilisee = case when p_patch ? 'reaction_utilisee' then coalesce((p_patch ->> 'reaction_utilisee')::boolean, false) else reaction_utilisee end,
    reaction_rd = case when p_patch ? 'reaction_utilisee' then false else reaction_rd end
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  if not found then
    raise exception 'Ce mercenaire n''a pas de compagnon.';
  end if;
end;
$$;

grant create on schema public to fortress_fn;
alter function reaction_definir(uuid, boolean) owner to fortress_fn;
alter function compagnon_etat_maj(uuid, jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function reaction_definir(uuid, boolean) from public;
grant execute on function reaction_definir(uuid, boolean) to authenticated;
-- _reactions_round et _reactions_apres_quete restent propriété de postgres (déclencheurs, comme _creatures_round).
revoke all on function _reactions_round() from public;
revoke all on function _reactions_apres_quete() from public;
