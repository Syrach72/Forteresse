-- Missions (demande de Bruno, 2026-10-08) : récompenses automatiques quand un événement se produit.
--  * Deux rubriques : « individuelle » (cadeau pour UN joueur : objet à donner à l'un de SES mercenaires, fenêtre
--    visible de lui seul) et « collective » (cadeau pour la compagnie : or et objets versés tout de suite,
--    annoncés à tous).
--  * Les missions sont des données (table mission, commune à toutes les sessions comme le catalogue) : or +
--    objet du catalogue. Les effets éphémères (bonus pendant une quête) ne sont pas encore pris en charge.
--  * Le serveur décide : chaque événement incrémente des compteurs (mission_compteur) puis attribue les missions
--    dont le seuil est atteint (mission_attribution, une seule fois par mission et par joueur / par session).
--  * Événements branchés : recrutement_paye (mercenaire embauché contre de l'or ; le premier est gratuit et ne
--    compte pas) et quete_reussie. Pour en ajouter : un déclencheur qui appelle _mission_evenement(code, joueur).
--  * mission_reclamer() : le joueur envoie l'objet d'une mission individuelle dans le sac à dos de l'un de ses
--    mercenaires.
--  * recompense_cachee : sur la page des missions la récompense s'affiche « ? » tant que la mission n'est pas accomplie.

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table mission (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  rubrique text not null check (rubrique in ('individuelle', 'collective')),
  nom text not null check (length(btrim(nom)) > 0),
  description text not null default '',
  evenement text not null check (evenement in ('recrutement_paye', 'quete_reussie')),
  seuil smallint not null default 1 check (seuil >= 1),
  recompense_or integer not null default 0 check (recompense_or >= 0),
  recompense_objet_id uuid references objet_catalogue (id) on delete set null,
  recompense_quantite smallint not null default 1 check (recompense_quantite >= 1),
  recompense_cachee boolean not null default false,
  ordre integer not null default 0,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

create table mission_attribution (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mission_id uuid not null references mission (id) on delete cascade,
  user_id uuid references auth.users (id) on delete cascade,
  accomplie_le timestamptz not null default now(),
  or_verse integer not null default 0,
  objet_id uuid references objet_catalogue (id) on delete set null,
  quantite smallint not null default 1,
  reclamee_le timestamptz,
  mercenaire_id uuid references mercenaire (id) on delete set null
);
create unique index mission_attribution_unique
  on mission_attribution (session_id, mission_id, coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Compteurs d'événements : user_id = 0000… pour le compteur collectif de la session.
create table mission_compteur (
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  evenement text not null,
  user_id uuid not null,
  valeur integer not null default 0,
  primary key (session_id, evenement, user_id)
);

alter table mission enable row level security;
alter table mission_attribution enable row level security;
alter table mission_compteur enable row level security;

create policy "mission: lecture" on mission for select to authenticated using (true);
create policy "mission: ecriture admin" on mission for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "mission: fonctions serveur" on mission for all to fortress_fn using (true) with check (true);

create policy "mission_attribution: lecture" on mission_attribution for select to authenticated
  using (session_id = ctx_session() and (user_id is null or user_id = auth.uid() or is_admin()));
create policy "mission_attribution: ecriture admin" on mission_attribution for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mission_attribution: fonctions serveur" on mission_attribution for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());

create policy "mission_compteur: lecture" on mission_compteur for select to authenticated
  using (session_id = ctx_session()
    and (user_id = auth.uid() or user_id = '00000000-0000-0000-0000-000000000000'::uuid));
create policy "mission_compteur: ecriture admin" on mission_compteur for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mission_compteur: fonctions serveur" on mission_compteur for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());

grant select, insert, update, delete on mission, mission_attribution, mission_compteur
  to authenticated, fortress_fn;
revoke all on mission, mission_attribution, mission_compteur from anon;

do $$
begin
  alter publication supabase_realtime add table mission_attribution;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Attribution d'une mission accomplie
-- ---------------------------------------------------------------------------
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
  insert into mission_attribution (mission_id, user_id, or_verse, objet_id, quantite, reclamee_le)
    values (m.id, p_user, m.recompense_or, m.recompense_objet_id, m.recompense_quantite,
      -- objet d'une mission individuelle : à réclamer (le joueur choisit le mercenaire) ; sinon rien à réclamer
      case when m.rubrique = 'individuelle' and m.recompense_objet_id is not null then null else now() end)
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
  v_texte := case when m.recompense_or > 0 then '+' || m.recompense_or || ' Po' else '' end
    || case when m.recompense_or > 0 and m.recompense_objet_id is not null then ' et ' else '' end
    || case when m.recompense_objet_id is not null
         then (select nom from objet_catalogue where id = m.recompense_objet_id) || ' ×' || m.recompense_quantite
         else '' end;
  perform _journal('or', 'Mission accomplie : « ' || m.nom || ' »'
    || case when v_texte <> '' then ' (' || v_texte || ').' else '.' end, m.recompense_or,
    jsonb_build_object('mission', m.id, 'rubrique', m.rubrique));
end;
$$;

-- Un événement s'est produit : compteurs +1, puis attribution des missions dont le seuil est atteint.
create or replace function _mission_evenement(p_evenement text, p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_zero constant uuid := '00000000-0000-0000-0000-000000000000';
  v_coll integer;
  v_perso integer := 0;
  m record;
begin
  insert into mission_compteur (evenement, user_id, valeur) values (p_evenement, v_zero, 1)
    on conflict (session_id, evenement, user_id) do update set valeur = mission_compteur.valeur + 1
    returning valeur into v_coll;
  if p_user is not null then
    insert into mission_compteur (evenement, user_id, valeur) values (p_evenement, p_user, 1)
      on conflict (session_id, evenement, user_id) do update set valeur = mission_compteur.valeur + 1
      returning valeur into v_perso;
  end if;
  for m in select id, rubrique, seuil from mission where actif and evenement = p_evenement order by ordre
  loop
    if m.rubrique = 'collective' and v_coll >= m.seuil then
      perform _mission_attribuer(m.id, null);
    elsif m.rubrique = 'individuelle' and p_user is not null and v_perso >= m.seuil then
      perform _mission_attribuer(m.id, p_user);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Déclencheurs : recrutement payant (via le journal) et quête réussie
-- ---------------------------------------------------------------------------
create or replace function _mission_declencheur_journal()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.type = 'depense' and new.details ? 'mercenaire_id'
     and coalesce((new.details ->> 'cout')::integer, 0) > 0 then
    perform _mission_evenement('recrutement_paye', new.auteur_id);
  end if;
  return null;
exception when others then
  -- une erreur de mission ne doit jamais empêcher l'embauche
  raise warning 'missions : %', sqlerrm;
  return null;
end;
$$;
create trigger mission_journal after insert on partie_journal
  for each row execute function _mission_declencheur_journal();

create or replace function _mission_declencheur_quete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if old.terminee_le is null and new.terminee_le is not null then
    perform _mission_evenement('quete_reussie', null);
  end if;
  return null;
exception when others then
  -- une erreur de mission ne doit jamais empêcher la fin d'une quête
  raise warning 'missions : %', sqlerrm;
  return null;
end;
$$;
create trigger mission_quete after update on quete_etat
  for each row execute function _mission_declencheur_quete();

-- ---------------------------------------------------------------------------
-- 4. Réclamer l'objet d'une mission individuelle : il part dans le sac à dos d'un mercenaire du joueur
-- ---------------------------------------------------------------------------
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
begin
  perform _verrou_partie();
  select * into a from mission_attribution where id = p_attribution for update;
  if not found then
    raise exception 'Récompense introuvable.';
  end if;
  if a.user_id is distinct from auth.uid() then
    raise exception 'Cette récompense est destinée à un autre joueur.';
  end if;
  if a.reclamee_le is not null or a.objet_id is null then
    raise exception 'Cette récompense a déjà été reçue.';
  end if;
  if not exists (select 1 from recrutement where mercenaire_id = p_mercenaire and user_id = auth.uid()) then
    raise exception 'Choisissez l''un de vos mercenaires.';
  end if;
  select * into m from mission where id = a.mission_id;
  select nom into v_nom_objet from objet_catalogue where id = a.objet_id;
  select nom into v_nom_merc from mercenaire where id = p_mercenaire;
  perform _sac_dos_ajouter(_sac_dos_id(p_mercenaire), a.objet_id, a.quantite, null, 'recevoir cette récompense');
  update mission_attribution set reclamee_le = now(), mercenaire_id = p_mercenaire where id = a.id;
  perform _journal('sac_envoi', 'Mission « ' || m.nom || ' » : ' || v_nom_objet || ' ×' || a.quantite
    || ' rejoint le sac à dos de ' || v_nom_merc || '.', 0,
    jsonb_build_object('mission', m.id, 'mercenaire_id', p_mercenaire, 'objet_id', a.objet_id));
  return jsonb_build_object('message', v_nom_objet || ' ×' || a.quantite || ' rejoint le sac à dos de ' || v_nom_merc || '.');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Remise à zéro d'une session : missions et compteurs repartent de zéro
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
    'mission_attribution', 'mission_compteur',
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
-- 6. Propriétaire fortress_fn (isolation par session) et droits
-- ---------------------------------------------------------------------------
grant create on schema public to fortress_fn;
alter function _mission_attribuer(uuid, uuid) owner to fortress_fn;
alter function _mission_evenement(text, uuid) owner to fortress_fn;
alter function _mission_declencheur_journal() owner to fortress_fn;
alter function _mission_declencheur_quete() owner to fortress_fn;
alter function mission_reclamer(uuid, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _mission_attribuer(uuid, uuid) from public;
revoke all on function _mission_evenement(text, uuid) from public;
revoke all on function _mission_declencheur_journal() from public;
revoke all on function _mission_declencheur_quete() from public;
revoke all on function mission_reclamer(uuid, uuid) from public;
grant execute on function mission_reclamer(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Deux missions d'exemple (à modifier selon les envies de Bruno)
-- ---------------------------------------------------------------------------
insert into mission (code, rubrique, nom, description, evenement, seuil, recompense_or,
  recompense_objet_id, recompense_quantite, ordre)
values
  ('premiere-recrue-payee', 'individuelle', 'Première recrue',
   'Embauchez un mercenaire contre de l’or (le premier, gratuit, ne compte pas).',
   'recrutement_paye', 1, 0,
   (select id from objet_catalogue where lower(btrim(nom)) = 'potion de vie mineure' limit 1), 1, 10),
  ('premiere-victoire', 'collective', 'Première victoire',
   'La compagnie réussit sa première quête.',
   'quete_reussie', 1, 100, null, 1, 20);
