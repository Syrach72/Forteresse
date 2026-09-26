-- Equipement et competences d'un mercenaire (regles de Bruno, 2026-09-26).
--
-- 1. Catalogue de competences (icone, nom, description), commun a toutes les
--    sessions comme le reste du catalogue ; ecriture reservee au MJ.
-- 2. Tableau de competences PAR MERCENAIRE (commun aux sessions, comme la fiche) :
--    10 lignes (une par veterance 1 a 10) ; chaque ligne a 3 cellules passives
--    (position 0 a 2) et 5 cellules actives (position 0 a 4). Le MJ place une
--    competence du catalogue dans une cellule depuis la fiche admin du mercenaire.
-- 3. Equipement PAR SESSION : 3 armes, 1 armure, 3 objets par mercenaire. On
--    equipe depuis le sac a dos (l'objet quitte le sac et prend un emplacement),
--    on deséquipe vers le sac (refuse si le sac est plein).
--
-- Les fonctions appartiennent a fortress_fn (isolation par session, cf.
-- docs/SESSIONS.md) et verifient que le mercenaire est bien a l'appelant (ou
-- que l'appelant est le MJ).

-- ---------------------------------------------------------------------------
-- 1. Catalogue de competences
-- ---------------------------------------------------------------------------
create table competence (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  description text,
  icone text,
  created_at timestamptz not null default now(),
  constraint competence_nom_key unique (nom)
);

-- ---------------------------------------------------------------------------
-- 2. Cellules de competences d'un mercenaire
-- ---------------------------------------------------------------------------
create table mercenaire_competence (
  id uuid primary key default gen_random_uuid(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  veterance smallint not null check (veterance between 1 and 10),
  type text not null check (type in ('passive', 'active')),
  position smallint not null check (position between 0 and 4),
  competence_id uuid not null references competence (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint mercenaire_competence_cellule_key unique (mercenaire_id, veterance, type, position),
  constraint mercenaire_competence_passive_position_check check (type = 'active' or position <= 2)
);

alter table competence enable row level security;
alter table mercenaire_competence enable row level security;
create policy "competence: lecture" on competence for select to authenticated using (true);
create policy "competence: ecriture admin" on competence for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "mercenaire_competence: lecture" on mercenaire_competence for select to authenticated using (true);
create policy "mercenaire_competence: ecriture admin" on mercenaire_competence for all to authenticated
  using (is_admin()) with check (is_admin());
grant select, insert, update, delete on competence, mercenaire_competence to authenticated;
revoke all on competence, mercenaire_competence from anon;

-- ---------------------------------------------------------------------------
-- 3. Equipement d'un mercenaire (etat de session)
-- ---------------------------------------------------------------------------
create table mercenaire_equipement (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  emplacement text not null check (emplacement in ('arme', 'armure', 'objet')),
  position smallint not null check (position between 0 and 2),
  objet_id uuid not null references objet_catalogue (id),
  gemmes uuid[],
  created_at timestamptz not null default now(),
  constraint mercenaire_equipement_emplacement_key unique (session_id, mercenaire_id, emplacement, position),
  constraint mercenaire_equipement_armure_check check (emplacement <> 'armure' or position = 0)
);

alter table mercenaire_equipement enable row level security;
create policy "mercenaire_equipement: lecture" on mercenaire_equipement for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_equipement: ecriture admin" on mercenaire_equipement for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_equipement: fonctions serveur" on mercenaire_equipement for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_equipement to authenticated, fortress_fn;
revoke all on mercenaire_equipement from anon;

do $$
begin
  alter publication supabase_realtime add table mercenaire_equipement;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
-- Le mercenaire est-il a l'appelant (recrute par lui dans la session), ou
-- l'appelant est-il le MJ ?
create function _droit_mercenaire(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if is_admin() then
    return;
  end if;
  if not exists (
    select 1 from recrutement where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas à votre nom.';
  end if;
end;
$$;

-- Ajoute des exemplaires au sac a dos : complete l'emplacement existant (3 au
-- plus) ou en prend un nouveau (9 au plus). Un objet serti (gemmes) a toujours
-- son propre emplacement. Refuse avec un message demandant de faire de la place.
create function _sac_dos_ajouter(p_sac uuid, p_objet uuid, p_quantite integer, p_gemmes uuid[], p_action text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_ligne uuid;
  v_actuel integer;
  v_compte integer;
begin
  if v_gemmes is null then
    select id, quantite into v_ligne, v_actuel from ligne_inventaire
      where inventaire_id = p_sac and objet_id = p_objet and gemmes is null and quantite > 0
      order by created_at, id limit 1
      for update;
  end if;
  if v_ligne is not null then
    if v_actuel + p_quantite > 3 then
      raise exception 'Cet emplacement du sac à dos est complet (3 au plus) : libérez d''abord de la place avant de %.', p_action;
    end if;
    update ligne_inventaire set quantite = quantite + p_quantite, updated_at = now() where id = v_ligne;
  else
    select count(*) into v_compte from ligne_inventaire where inventaire_id = p_sac and quantite > 0;
    if v_compte >= 9 then
      raise exception 'Le sac à dos est plein : libérez d''abord un emplacement avant de %.', p_action;
    end if;
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (p_sac, p_objet, p_quantite, v_gemmes);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Equiper : sac a dos -> emplacement du mercenaire
-- ---------------------------------------------------------------------------
create function sac_dos_equiper(p_mercenaire uuid, p_objet uuid, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_merc text;
  v_nom text;
  v_racine text;
  v_emp text;
  v_max integer;
  v_pos integer;
  v_sac uuid;
  v_ligne uuid;
  v_qte integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  if v_merc is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id) into v_nom, v_racine
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  v_emp := case v_racine when 'Armes' then 'arme' when 'Armures' then 'armure' when 'Objet divers' then 'objet' end;
  if v_emp is null then
    raise exception 'Seuls les armes, les armures et les objets divers peuvent être équipés.';
  end if;
  v_max := case when v_emp = 'armure' then 0 else 2 end;
  select g.p into v_pos from generate_series(0, v_max) as g(p)
    where not exists (
      select 1 from mercenaire_equipement e
      where e.mercenaire_id = p_mercenaire and e.emplacement = v_emp and e.position = g.p)
    order by g.p limit 1;
  if v_pos is null then
    raise exception '%', case v_emp
      when 'arme' then v_merc || ' porte déjà 3 armes : déséquipez-en une d''abord.'
      when 'armure' then v_merc || ' porte déjà une armure : déséquipez-la d''abord.'
      else v_merc || ' porte déjà 3 objets : déséquipez-en un d''abord.' end;
  end if;
  v_sac := _sac_dos_id(p_mercenaire);
  select id, quantite into v_ligne, v_qte from ligne_inventaire
    where inventaire_id = v_sac and objet_id = p_objet and gemmes is not distinct from v_gemmes and quantite > 0
    order by created_at, id limit 1
    for update;
  if v_ligne is null then
    raise exception 'Cet objet n''est pas dans le sac à dos.';
  end if;
  if v_qte = 1 then
    delete from ligne_inventaire where id = v_ligne;
  else
    update ligne_inventaire set quantite = quantite - 1, updated_at = now() where id = v_ligne;
  end if;
  insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id, gemmes)
    values (p_mercenaire, v_emp, v_pos, p_objet, v_gemmes);
  perform _journal('equipement', v_nom || ' équipé par ' || v_merc || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'emplacement', v_emp, 'position', v_pos));
end;
$$;

-- ---------------------------------------------------------------------------
-- Deséquiper : emplacement -> sac a dos (refuse si le sac est plein)
-- ---------------------------------------------------------------------------
create function equipement_retirer(p_mercenaire uuid, p_emplacement text, p_position integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  e mercenaire_equipement%rowtype;
  v_merc text;
  v_nom text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select * into e from mercenaire_equipement
    where mercenaire_id = p_mercenaire and emplacement = p_emplacement and position = p_position
    for update;
  if not found then
    raise exception 'Cet emplacement est vide.';
  end if;
  select nom into v_merc from mercenaire where id = p_mercenaire;
  select nom into v_nom from objet_catalogue where id = e.objet_id;
  perform _sac_dos_ajouter(_sac_dos_id(p_mercenaire), e.objet_id, 1, e.gemmes, 'pouvoir déséquiper l''objet');
  delete from mercenaire_equipement where id = e.id;
  perform _journal('equipement', coalesce(v_nom, 'Objet') || ' déséquipé par ' || coalesce(v_merc, 'le mercenaire') || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', e.objet_id, 'emplacement', p_emplacement, 'position', p_position));
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits, proprietaire fortress_fn
-- ---------------------------------------------------------------------------
grant create on schema public to fortress_fn;
alter function _droit_mercenaire(uuid) owner to fortress_fn;
alter function _sac_dos_ajouter(uuid, uuid, integer, uuid[], text) owner to fortress_fn;
alter function sac_dos_equiper(uuid, uuid, uuid[]) owner to fortress_fn;
alter function equipement_retirer(uuid, text, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _droit_mercenaire(uuid) from public;
revoke all on function _sac_dos_ajouter(uuid, uuid, integer, uuid[], text) from public;
revoke all on function sac_dos_equiper(uuid, uuid, uuid[]) from public;
revoke all on function equipement_retirer(uuid, text, integer) from public;
grant execute on function sac_dos_equiper(uuid, uuid, uuid[]) to authenticated;
grant execute on function equipement_retirer(uuid, text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Remise a zero d'une session : l'equipement est sauvegarde puis efface avec le reste.
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
    'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
    'mercenaire_equipement', 'ligne_inventaire', 'inventaire', 'atelier_fabrication',
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
