-- Barre d'initiative, suite (Bruno, 2026-10-21) :
--  * Les créatures du MJ sont des « ? » pour les joueurs jusqu'à ce que le MJ ait cliqué une première fois sur « Fin de
--    tour » pour cette créature (`revele`). Le nom (`label`) n'est même pas stocké tant qu'elle n'est pas révélée : un joueur
--    ne peut pas le lire par l'API. Le MJ lit les noms dans creature_quete.
--  * « Passer le tour » (MJ, créatures) : comme « Fin de tour » mais sans révéler le nom.
--  * « Retarder son action » : quand arrive son tour (premier de ceux qui n'ont pas joué), un mercenaire (son joueur ou le MJ)
--    ou une créature (MJ) se repositionne N crans plus loin parmi ceux qui n'ont pas encore joué, une seule fois par Rd.
--    L'ordre est porté par `ordre` (= le rang au départ, remis au rang à chaque Rd) ; le Rd annulé restitue l'état d'avant.

alter table initiative_tour
  add column ordre double precision,
  add column ordre_prec double precision,
  add column retarde boolean not null default false,
  add column retarde_prec boolean,
  add column revele boolean not null default false;

-- Reprise de l'existant : ordre = rang ; les créatures déjà passées sont révélées, les autres perdent leur nom.
update initiative_tour set ordre = rang where session_id is not null;
update initiative_tour set revele = true, label = coalesce(label, (select c.nom_onglet from creature_quete c where c.id = creature_quete_id))
  where kind = 'creature' and joue_ordre is not null;
update initiative_tour set label = null where kind = 'creature' and not revele;

create or replace function _initiative_tour_ajouter()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.rang is not null and old.rang is null then
    insert into initiative_tour (session_id, initiative_id, kind, mercenaire_id, creature_quete_id, label, rang, ordre)
      values (new.session_id, new.id, new.kind, new.mercenaire_id, new.creature_quete_id, null, new.rang, new.rang)
      on conflict (initiative_id) do update set rang = excluded.rang, ordre = excluded.rang;
  end if;
  return new;
end;
$$;

create or replace function _initiative_tour_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = old.round_courant + 1 then
    update initiative_tour
      set joue_prec = joue_ordre, joue_ordre = null,
          ordre_prec = ordre, ordre = rang,
          retarde_prec = retarde, retarde = false
      where session_id = new.session_id;
  elsif new.round_courant = old.round_courant - 1 then
    update initiative_tour
      set joue_ordre = joue_prec, joue_prec = null,
          ordre = coalesce(ordre_prec, rang), ordre_prec = null,
          retarde = coalesce(retarde_prec, false), retarde_prec = null
      where session_id = new.session_id;
  end if;
  return new;
end;
$$;

create or replace function initiative_fin_tour(p_kind text, p_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_joue integer;
begin
  perform _verrou_partie();
  if p_kind = 'mercenaire' then
    perform _droit_mercenaire(p_id);
    select id, joue_ordre into v_id, v_joue from initiative_tour
      where session_id = ctx_session() and mercenaire_id = p_id for update;
  elsif p_kind = 'creature' then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    select id, joue_ordre into v_id, v_joue from initiative_tour
      where session_id = ctx_session() and creature_quete_id = p_id for update;
  else
    raise exception 'Participant inconnu.';
  end if;
  if v_id is null then
    raise exception 'Ce participant n''est pas dans l''ordre d''initiative.';
  end if;
  if v_joue is not null then
    raise exception 'Tour déjà terminé : attendez le prochain Rd.';
  end if;
  update initiative_tour
    set joue_ordre = coalesce((select max(t.joue_ordre) from initiative_tour t where t.session_id = ctx_session()), 0) + 1,
        -- Un premier « Fin de tour » révèle le nom d'une créature aux joueurs.
        revele = revele or kind = 'creature',
        label = case when kind = 'creature'
                     then coalesce(label, (select c.nom_onglet from creature_quete c where c.id = creature_quete_id))
                     else label end
    where id = v_id;
end;
$$;

-- « Passer le tour » d'une créature (MJ) : même effet que « Fin de tour », sans révéler son nom.
create function initiative_passer_tour(p_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_joue integer;
begin
  perform _verrou_partie();
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  select id, joue_ordre into v_id, v_joue from initiative_tour
    where session_id = ctx_session() and creature_quete_id = p_id for update;
  if v_id is null then
    raise exception 'Cette créature n''est pas dans l''ordre d''initiative.';
  end if;
  if v_joue is not null then
    raise exception 'Tour déjà terminé : attendez le prochain Rd.';
  end if;
  update initiative_tour
    set joue_ordre = coalesce((select max(t.joue_ordre) from initiative_tour t where t.session_id = ctx_session()), 0) + 1
    where id = v_id;
end;
$$;

-- « Retarder son action » : à son tour, repasse N crans plus loin parmi ceux qui n'ont pas encore joué (une fois par Rd).
create function initiative_retarder(p_kind text, p_id uuid, p_crans integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_joue integer;
  v_retarde boolean;
  v_premier uuid;
  v_t double precision;
  v_t2 double precision;
begin
  perform _verrou_partie();
  if p_kind = 'mercenaire' then
    perform _droit_mercenaire(p_id);
    select id, joue_ordre, retarde into v_id, v_joue, v_retarde from initiative_tour
      where session_id = ctx_session() and mercenaire_id = p_id for update;
  elsif p_kind = 'creature' then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    select id, joue_ordre, retarde into v_id, v_joue, v_retarde from initiative_tour
      where session_id = ctx_session() and creature_quete_id = p_id for update;
  else
    raise exception 'Participant inconnu.';
  end if;
  if v_id is null then
    raise exception 'Ce participant n''est pas dans l''ordre d''initiative.';
  end if;
  if v_joue is not null then
    raise exception 'Tour déjà terminé : attendez le prochain Rd.';
  end if;
  if v_retarde then
    raise exception 'L''action a déjà été retardée ce Rd.';
  end if;
  select id into v_premier from initiative_tour
    where session_id = ctx_session() and joue_ordre is null
    order by ordre, rang limit 1;
  if v_premier is distinct from v_id then
    raise exception 'Ce n''est pas encore son tour : l''action ne se retarde qu''à son propre tour.';
  end if;
  if p_crans is null or p_crans < 1 then
    raise exception 'Choisissez un nombre de crans d''au moins 1.';
  end if;
  select x.ordre into v_t from (
    select ordre, row_number() over (order by ordre, rang) as rn
      from initiative_tour where session_id = ctx_session() and joue_ordre is null and id <> v_id) x
    where x.rn = p_crans;
  if v_t is null then
    raise exception 'Pas assez de participants derrière pour reculer d''autant de crans.';
  end if;
  select x.ordre into v_t2 from (
    select ordre, row_number() over (order by ordre, rang) as rn
      from initiative_tour where session_id = ctx_session() and joue_ordre is null and id <> v_id) x
    where x.rn = p_crans + 1;
  update initiative_tour
    set ordre = case when v_t2 is null then v_t + 1 else (v_t + v_t2) / 2 end, retarde = true
    where id = v_id;
end;
$$;

grant create on schema public to fortress_fn;
alter function initiative_fin_tour(text, uuid) owner to fortress_fn;
alter function initiative_passer_tour(uuid) owner to fortress_fn;
alter function initiative_retarder(text, uuid, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function initiative_passer_tour(uuid) from public, anon;
revoke all on function initiative_retarder(text, uuid, integer) from public, anon;
grant execute on function initiative_passer_tour(uuid) to authenticated;
grant execute on function initiative_retarder(text, uuid, integer) to authenticated;
