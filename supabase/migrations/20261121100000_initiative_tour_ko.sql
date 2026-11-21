-- Barre d'initiative et PV (Bruno, 2026-11-21) : un mercenaire ou une créature tombé à 0 PV sort de la barre d'initiative et
-- n'a plus accès à « Fin de tour » (ni « Passer le tour » / « Retarder ») tant qu'il n'a pas récupéré au moins 1 PV.
--  * `ko` : tenu à jour par deux déclencheurs (santé d'un mercenaire = mercenaire_etat, d'une créature = creature_quete).
--    Une santé « null » signifie « au maximum » : pas à terre.
--  * Les joueurs ne lisent pas creature_quete : c'est pourquoi l'état est recopié ici, dans une table lisible par la session.

alter table initiative_tour add column ko boolean not null default false;

-- Reprise de l'existant.
update initiative_tour t set ko = true
  from mercenaire_etat e
  where t.kind = 'mercenaire' and e.session_id = t.session_id and e.mercenaire_id = t.mercenaire_id
    and e.sante_actuelle is not null and e.sante_actuelle <= 0;
update initiative_tour t set ko = true
  from creature_quete c
  where t.kind = 'creature' and c.id = t.creature_quete_id
    and c.sante_actuelle is not null and c.sante_actuelle <= 0;

create function _initiative_tour_ko_merc()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update initiative_tour
    set ko = (new.sante_actuelle is not null and new.sante_actuelle <= 0)
    where session_id = new.session_id and mercenaire_id = new.mercenaire_id
      and ko is distinct from (new.sante_actuelle is not null and new.sante_actuelle <= 0);
  return new;
end;
$$;
create trigger mercenaire_etat_initiative_ko
  after insert or update of sante_actuelle on mercenaire_etat
  for each row execute function _initiative_tour_ko_merc();

create function _initiative_tour_ko_creature()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update initiative_tour
    set ko = (new.sante_actuelle is not null and new.sante_actuelle <= 0)
    where creature_quete_id = new.id
      and ko is distinct from (new.sante_actuelle is not null and new.sante_actuelle <= 0);
  return new;
end;
$$;
create trigger creature_quete_initiative_ko
  after insert or update of sante_actuelle on creature_quete
  for each row execute function _initiative_tour_ko_creature();

revoke all on function _initiative_tour_ko_merc() from public, anon, authenticated;
revoke all on function _initiative_tour_ko_creature() from public, anon, authenticated;

-- Un participant qui entre dans la barre déjà à 0 PV est marqué tout de suite.
create or replace function _initiative_tour_ajouter()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_ko boolean;
begin
  if new.rang is not null and old.rang is null then
    if new.kind = 'mercenaire' then
      select coalesce(e.sante_actuelle <= 0, false) into v_ko from mercenaire_etat e
        where e.session_id = new.session_id and e.mercenaire_id = new.mercenaire_id;
    else
      select coalesce(c.sante_actuelle <= 0, false) into v_ko from creature_quete c where c.id = new.creature_quete_id;
    end if;
    insert into initiative_tour (session_id, initiative_id, kind, mercenaire_id, creature_quete_id, label, rang, ordre, ko)
      values (new.session_id, new.id, new.kind, new.mercenaire_id, new.creature_quete_id, null, new.rang, new.rang, coalesce(v_ko, false))
      on conflict (initiative_id) do update set rang = excluded.rang, ordre = excluded.rang;
  end if;
  return new;
end;
$$;

-- « Fin de tour » : refusé à 0 PV.
create or replace function initiative_fin_tour(p_kind text, p_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_joue integer;
  v_ko boolean;
begin
  perform _verrou_partie();
  if p_kind = 'mercenaire' then
    perform _droit_mercenaire(p_id);
    select id, joue_ordre, ko into v_id, v_joue, v_ko from initiative_tour
      where session_id = ctx_session() and mercenaire_id = p_id for update;
  elsif p_kind = 'creature' then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    select id, joue_ordre, ko into v_id, v_joue, v_ko from initiative_tour
      where session_id = ctx_session() and creature_quete_id = p_id for update;
  else
    raise exception 'Participant inconnu.';
  end if;
  if v_id is null then
    raise exception 'Ce participant n''est pas dans l''ordre d''initiative.';
  end if;
  if v_ko then
    raise exception 'À 0 PV : pas de tour tant qu''il n''a pas récupéré au moins 1 PV.';
  end if;
  if v_joue is not null then
    raise exception 'Tour déjà terminé : attendez le prochain Rd.';
  end if;
  update initiative_tour
    set joue_ordre = coalesce((select max(t.joue_ordre) from initiative_tour t where t.session_id = ctx_session()), 0) + 1,
        revele = revele or kind = 'creature',
        label = case when kind = 'creature'
                     then coalesce(label, (select c.nom_onglet from creature_quete c where c.id = creature_quete_id))
                     else label end
    where id = v_id;
end;
$$;

create or replace function initiative_passer_tour(p_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_joue integer;
  v_ko boolean;
begin
  perform _verrou_partie();
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  select id, joue_ordre, ko into v_id, v_joue, v_ko from initiative_tour
    where session_id = ctx_session() and creature_quete_id = p_id for update;
  if v_id is null then
    raise exception 'Cette créature n''est pas dans l''ordre d''initiative.';
  end if;
  if v_ko then
    raise exception 'À 0 PV : pas de tour tant qu''elle n''a pas récupéré au moins 1 PV.';
  end if;
  if v_joue is not null then
    raise exception 'Tour déjà terminé : attendez le prochain Rd.';
  end if;
  update initiative_tour
    set joue_ordre = coalesce((select max(t.joue_ordre) from initiative_tour t where t.session_id = ctx_session()), 0) + 1
    where id = v_id;
end;
$$;

-- « Retarder » : les participants à 0 PV ne comptent ni comme « premier » ni comme « derrière ».
create or replace function initiative_retarder(p_kind text, p_id uuid, p_crans integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_joue integer;
  v_retarde boolean;
  v_ko boolean;
  v_premier uuid;
  v_t double precision;
  v_t2 double precision;
begin
  perform _verrou_partie();
  if p_kind = 'mercenaire' then
    perform _droit_mercenaire(p_id);
    select id, joue_ordre, retarde, ko into v_id, v_joue, v_retarde, v_ko from initiative_tour
      where session_id = ctx_session() and mercenaire_id = p_id for update;
  elsif p_kind = 'creature' then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    select id, joue_ordre, retarde, ko into v_id, v_joue, v_retarde, v_ko from initiative_tour
      where session_id = ctx_session() and creature_quete_id = p_id for update;
  else
    raise exception 'Participant inconnu.';
  end if;
  if v_id is null then
    raise exception 'Ce participant n''est pas dans l''ordre d''initiative.';
  end if;
  if v_ko then
    raise exception 'À 0 PV : pas de tour tant qu''il n''a pas récupéré au moins 1 PV.';
  end if;
  if v_joue is not null then
    raise exception 'Tour déjà terminé : attendez le prochain Rd.';
  end if;
  if v_retarde then
    raise exception 'L''action a déjà été retardée ce Rd.';
  end if;
  select id into v_premier from initiative_tour
    where session_id = ctx_session() and joue_ordre is null and not ko
    order by ordre, rang limit 1;
  if v_premier is distinct from v_id then
    raise exception 'Ce n''est pas encore son tour : l''action ne se retarde qu''à son propre tour.';
  end if;
  if p_crans is null or p_crans < 1 then
    raise exception 'Choisissez un nombre de crans d''au moins 1.';
  end if;
  select x.ordre into v_t from (
    select ordre, row_number() over (order by ordre, rang) as rn
      from initiative_tour where session_id = ctx_session() and joue_ordre is null and not ko and id <> v_id) x
    where x.rn = p_crans;
  if v_t is null then
    raise exception 'Pas assez de participants derrière pour reculer d''autant de crans.';
  end if;
  select x.ordre into v_t2 from (
    select ordre, row_number() over (order by ordre, rang) as rn
      from initiative_tour where session_id = ctx_session() and joue_ordre is null and not ko and id <> v_id) x
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
