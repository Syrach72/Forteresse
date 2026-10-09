-- Initiative (demande de Bruno, 2026-10-09) : quand une quête est choisie, chaque mercenaire engagé lance un d20
-- (le serveur tire le nombre) ; les créatures de la quête lancent toutes seules dès que le premier lancer est
-- demandé. Total = d20 + Vélocité (vélocité effective : bonus et effets temporaires compris, fonction _velocite).
-- Quand tout le monde a lancé, le serveur classe : rang 1 = total le plus élevé. À égalité de total, les ex æquo
-- relancent un d20 (autant de fois que nécessaire) uniquement pour se départager : le total ne change pas.
--
--  * `initiative_etat` : une ligne par session = « le lancer d'initiative est ouvert » (visible de tous).
--  * `initiative` : une ligne par mercenaire ou créature (d20, vélocité, total, relances de départage, rang).
--    Les lignes des créatures ne sont lisibles que par le MJ ; celles des mercenaires par toute la session.
--  * Remise à zéro automatique quand une quête est choisie ou que son choix est annulé / qu'elle est accomplie.
-- Toute suppression/mise à jour a une clause WHERE explicite (pg_safeupdate).

create table initiative_etat (
  session_id uuid primary key references session (id) on delete cascade default ctx_session(),
  quete_id uuid not null references quete (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table initiative (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  quete_id uuid not null references quete (id) on delete cascade,
  kind text not null check (kind in ('mercenaire', 'creature')),
  mercenaire_id uuid references mercenaire (id) on delete cascade,
  creature_quete_id uuid references creature_quete (id) on delete cascade,
  de smallint not null check (de between 1 and 20),
  velocite integer not null,
  total integer not null,
  departage smallint[] not null default '{}',
  rang smallint,
  created_at timestamptz not null default now(),
  check ((kind = 'mercenaire' and mercenaire_id is not null and creature_quete_id is null)
      or (kind = 'creature' and creature_quete_id is not null and mercenaire_id is null)),
  unique (session_id, mercenaire_id),
  unique (session_id, creature_quete_id)
);

alter table initiative_etat enable row level security;
alter table initiative enable row level security;
create policy "initiative_etat: lecture" on initiative_etat for select to authenticated
  using (session_id = ctx_session());
create policy "initiative_etat: ecriture admin" on initiative_etat for all to authenticated
  using (is_admin() and session_id = ctx_session()) with check (is_admin() and session_id = ctx_session());
create policy "initiative_etat: fonctions serveur" on initiative_etat for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
create policy "initiative: lecture" on initiative for select to authenticated
  using (session_id = ctx_session() and (kind = 'mercenaire' or is_admin()));
create policy "initiative: ecriture admin" on initiative for all to authenticated
  using (is_admin() and session_id = ctx_session()) with check (is_admin() and session_id = ctx_session());
create policy "initiative: fonctions serveur" on initiative for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on initiative_etat, initiative to authenticated, fortress_fn;
revoke all on initiative_etat, initiative from anon;
do $$
begin
  alter publication supabase_realtime add table initiative_etat;
  alter publication supabase_realtime add table initiative;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- Les fonctions du serveur lisent la vélocité des créatures (catalogue réservé au MJ pour les joueurs).
drop policy "creature: lecture fonctions serveur" on creature;
create policy "creature: lecture fonctions serveur" on creature for select to fortress_fn using (true);

-- ---------------------------------------------------------------------------
-- Classement : quand tout le monde a lancé, relances de départage puis rang
-- ---------------------------------------------------------------------------
create function _initiative_resoudre()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_quete uuid;
  v_attendus integer;
  v_faits integer;
  v_tours integer := 0;
begin
  select quete_id into v_quete from initiative_etat where session_id = ctx_session();
  if v_quete is null then
    return;
  end if;
  select (select count(*) from quete_mercenaire where quete_id = v_quete and session_id = ctx_session())
       + (select count(*) from creature_quete where quete_id = v_quete and session_id = ctx_session())
    into v_attendus;
  select count(*) into v_faits from initiative where session_id = ctx_session() and quete_id = v_quete;
  if v_attendus = 0 or v_faits < v_attendus
     or exists (select 1 from initiative where session_id = ctx_session() and rang is not null) then
    return;
  end if;
  -- Ex æquo (même total et même suite de relances) : tous relancent, jusqu'à ce que plus personne ne soit à égalité.
  loop
    update initiative i
      set departage = i.departage || (1 + floor(random() * 20))::smallint
      where i.session_id = ctx_session()
        and exists (select 1 from initiative j
                    where j.session_id = i.session_id and j.id <> i.id
                      and j.total = i.total and j.departage = i.departage);
    exit when not found;
    v_tours := v_tours + 1;
    exit when v_tours >= 100;
  end loop;
  update initiative i set rang = r.rang
    from (select id, (row_number() over (order by total desc, departage desc))::smallint as rang
            from initiative where session_id = ctx_session()) r
    where i.id = r.id and i.session_id = ctx_session();
end;
$$;

-- Ouvre le lancer d'initiative : les créatures de la quête lancent toutes en même temps (sans visuel).
create function initiative_demarrer()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_quete uuid;
begin
  perform _verrou_partie();
  select quete_id into v_quete from quete_etat where session_id = ctx_session() and en_cours;
  if v_quete is null then
    raise exception 'Aucune quête n''est choisie.';
  end if;
  if exists (select 1 from initiative_etat where session_id = ctx_session()) then
    return;
  end if;
  insert into initiative_etat (quete_id) values (v_quete);
  insert into initiative (quete_id, kind, creature_quete_id, de, velocite, total)
    select v_quete, 'creature', c.id, d.de, k.velocite, d.de + k.velocite
    from creature_quete c
    join creature k on k.id = c.creature_id
    cross join lateral (select (1 + floor(random() * 20))::integer as de) d
    where c.session_id = ctx_session() and c.quete_id = v_quete;
  perform _initiative_resoudre();
end;
$$;

-- Lancer d'un mercenaire engagé dans la quête : le serveur tire le d20 (non modifiable ensuite).
create function initiative_lancer(p_mercenaire uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_quete uuid;
  v_de integer;
  v_vel integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select quete_id into v_quete from quete_etat where session_id = ctx_session() and en_cours;
  if v_quete is null then
    raise exception 'Aucune quête n''est choisie.';
  end if;
  if not exists (select 1 from quete_mercenaire
                 where mercenaire_id = p_mercenaire and quete_id = v_quete and session_id = ctx_session()) then
    raise exception 'Ce mercenaire n''est pas engagé dans la quête en cours.';
  end if;
  perform initiative_demarrer();
  if exists (select 1 from initiative where mercenaire_id = p_mercenaire and session_id = ctx_session()) then
    raise exception 'Ce mercenaire a déjà lancé son dé d''initiative.';
  end if;
  v_de := 1 + floor(random() * 20)::integer;
  v_vel := _velocite(p_mercenaire);
  insert into initiative (quete_id, kind, mercenaire_id, de, velocite, total)
    values (v_quete, 'mercenaire', p_mercenaire, v_de, v_vel, v_de + v_vel);
  perform _initiative_resoudre();
  return jsonb_build_object('de', v_de, 'velocite', v_vel, 'total', v_de + v_vel);
end;
$$;

-- ---------------------------------------------------------------------------
-- Remise à zéro quand la quête en cours change (choisie, annulée ou accomplie)
-- ---------------------------------------------------------------------------
-- Propriétaire postgres (comme _creatures_quete_cycle) : agit sur la session de la ligne modifiée, pas sur celle de
-- l'appelant ; session_id explicite partout.
create function _initiative_cycle()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.en_cours is distinct from old.en_cours then
    delete from initiative where session_id = new.session_id;
    delete from initiative_etat where session_id = new.session_id;
  end if;
  return new;
end;
$$;
create trigger quete_etat_initiative
  after insert or update of en_cours on quete_etat
  for each row execute function _initiative_cycle();

-- ---------------------------------------------------------------------------
-- Remise à zéro d'une session : l'initiative est sauvegardée puis effacée avec le reste
-- ---------------------------------------------------------------------------
create or replace function session_reinitialiser(p_session uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  t text;
  v_donnees jsonb := '{}'::jsonb;
  v_table jsonb;
  v_ordre text[] := array[
    'mission_attribution', 'mission_compteur', 'mercenaire_effet', 'mercenaire_ennemi_jure', 'mercenaire_terrain_favori', 'mercenaire_style_combat', 'mercenaire_conduit_divin', 'mercenaire_compagnon',
    'initiative', 'initiative_etat',
    'cimetiere', 'recrutement_gratuit', 'objet_quete_active', 'creature_quete', 'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
    'mercenaire_equipement', 'ligne_inventaire', 'inventaire', 'atelier_file', 'atelier_fabrication',
    'forge_sertissage', 'employe',
    'partie_journal', 'partie_etat', 'dortoir_reglage', 'entrainement_reglage',
    'infirmerie_reglage', 'mercenaire_etat', 'quete_etat', 'budget_poste'];
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  perform 1 from session where id = p_session for update;
  if not found then
    raise exception 'Session introuvable.';
  end if;
  foreach t in array v_ordre loop
    execute format(
      'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from %I x where x.session_id = $1', t)
      into v_table using p_session;
    v_donnees := v_donnees || jsonb_build_object(t, v_table);
  end loop;
  insert into session_sauvegarde (session_id, motif, donnees)
    values (p_session, 'Remise à zéro par le MJ', v_donnees);
  foreach t in array v_ordre loop
    execute format('delete from %I where session_id = $1', t) using p_session;
  end loop;
  update session set lancee_le = null where id = p_session;
end;
$$;

-- ---------------------------------------------------------------------------
-- Propriétaire fortress_fn (isolation par session) et droits d'exécution
-- ---------------------------------------------------------------------------
grant create on schema public to fortress_fn;
alter function _initiative_resoudre() owner to fortress_fn;
alter function initiative_demarrer() owner to fortress_fn;
alter function initiative_lancer(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _initiative_resoudre() from public;
revoke all on function initiative_demarrer() from public;
revoke all on function initiative_lancer(uuid) from public;
revoke all on function _initiative_cycle() from public;
grant execute on function initiative_demarrer() to authenticated;
grant execute on function initiative_lancer(uuid) to authenticated;
