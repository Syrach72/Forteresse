-- Forme Sauvage (Druide, Bruno 2026-10-13) : coût 2 Énergies. Le Druide prend la forme d'une Bête deux fois par
-- instance, pendant 2 × son Mental en rounds. Ses statistiques sont remplacées par celles de la bête (sauf le Mental)
-- et il endosse ses PV : si ils tombent à 0, il retrouve sa forme et ses PV. L'onglet « Forme sauvage » n'existe
-- que pendant la transformation ; il disparaît à la fin du décompte (Rd), sur « Retour forme originale » ou à 0 PV.
--
--  * La bête vient du catalogue des créatures : `creature.compagnon` accepte trois étiquettes de plus,
--    'forme_sauvage_2' / '_5' / '_8' = vétérance minimale pour la choisir (Niv. 2, 5, 8 : cumulatif). Elles
--    rendent la fiche lisible par les joueurs avec les politiques déjà posées pour les compagnons.
--  * `mercenaire_forme_sauvage` : une ligne par mercenaire. `actif` = transformé. Les PV de la bête sont tenus ici
--    (ceux du mercenaire ne bougent pas). Les utilisations sont comptées par instance (colonnes instance_no/usages).
--  * Rd : -1 round ; à 0 la forme s'achève. « Annuler » le Rd rend le round (et la forme si elle venait de finir).
-- Toute mise à jour a une clause WHERE explicite (pg_safeupdate).

-- ---------------------------------------------------------------------------
-- 1. Étiquettes de créature
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in select conname from pg_constraint
    where conrelid = 'creature'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%compagnon%'
  loop
    execute format('alter table creature drop constraint %I', c.conname);
  end loop;
end;
$$;
alter table creature add constraint creature_compagnon_check
  check (compagnon in ('faucon', 'chien', 'panthere', 'familier', 'forme_sauvage_2', 'forme_sauvage_5', 'forme_sauvage_8'));

-- Une fiche « forme sauvage » ne peut pas être choisie comme compagnon animal ou familier.
create or replace function compagnon_choisir(p_mercenaire uuid, p_creature uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_tag text;
  v_role text;
  v_classe text;
  v_sous text;
  v_nom text;
  v_nom_creature text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select compagnon, nom into v_tag, v_nom_creature from creature where id = p_creature and actif;
  if v_tag is null or v_tag like 'forme_sauvage%' then
    raise exception 'Cette fiche n''est pas disponible comme compagnon.';
  end if;
  v_role := case when v_tag = 'familier' then 'familier' else 'compagnon' end;
  select m.nom,
         translate(lower(coalesce(c.nom, '')), 'êîéèô', 'eieeo'),
         translate(lower(coalesce(m.sous_classe, '')), 'êîéèô', 'eieeo')
    into v_nom, v_classe, v_sous
    from mercenaire m left join classe c on c.id = m.classe_id
    where m.id = p_mercenaire;
  if v_role = 'compagnon' and not (v_classe = 'rodeur' and v_sous = 'maitre des betes') then
    raise exception 'Seul un Rôdeur Maître des Bêtes peut avoir un compagnon animal.';
  end if;
  if v_role = 'familier' and v_classe <> 'incantateur' then
    raise exception 'Seul un Incantateur peut avoir un familier.';
  end if;
  if _vet(p_mercenaire) < 3 then
    raise exception 'Le choix se fait à partir de la vétérance 3.';
  end if;
  if exists (select 1 from mercenaire_compagnon where mercenaire_id = p_mercenaire and session_id = ctx_session()) then
    raise exception 'Ce mercenaire a déjà fait son choix.';
  end if;
  insert into mercenaire_compagnon (mercenaire_id, role, creature_id) values (p_mercenaire, v_role, p_creature);
  perform _journal('equipement', v_nom || ' : ' || v_role || ' = ' || v_nom_creature || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, v_role, v_nom_creature));
  return jsonb_build_object('role', v_role);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. La forme sauvage d'un mercenaire (état par session)
-- ---------------------------------------------------------------------------
create table mercenaire_forme_sauvage (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  creature_id uuid not null references creature (id) on delete cascade,
  actif boolean not null default true,
  rounds_restants integer not null check (rounds_restants >= 0),
  rounds_total integer not null check (rounds_total >= 0),
  dernier_rd boolean not null default false,
  instance_no integer not null default 0,
  usages integer not null default 0 check (usages >= 0),
  sante_actuelle integer check (sante_actuelle is null or sante_actuelle >= 0),
  energie_actuelle integer check (energie_actuelle is null or energie_actuelle >= 0),
  etat text check (etat is null or length(etat) <= 30),
  etat_niveau smallint not null default 1 check (etat_niveau between 1 and 3),
  etat_rounds smallint not null default 0 check (etat_rounds between 0 and 9),
  commentaires text not null default '' check (length(commentaires) <= 4000),
  created_at timestamptz not null default now(),
  unique (session_id, mercenaire_id)
);
alter table mercenaire_forme_sauvage enable row level security;
create policy "mercenaire_forme_sauvage: lecture" on mercenaire_forme_sauvage for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_forme_sauvage: ecriture admin" on mercenaire_forme_sauvage for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_forme_sauvage: fonctions serveur" on mercenaire_forme_sauvage for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_forme_sauvage to authenticated, fortress_fn;
revoke all on mercenaire_forme_sauvage from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_forme_sauvage;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Prendre la forme (2 Énergies, 2 fois par instance), la quitter, tenir l'état à jour
-- ---------------------------------------------------------------------------
create function forme_sauvage_activer(p_mercenaire uuid, p_competence uuid, p_creature uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_inst integer;
  v_classe text;
  v_tag text;
  v_palier integer;
  v_pv integer;
  v_nom_creature text;
  v_merc text;
  v_rounds integer;
  v_ligne mercenaire_forme_sauvage%rowtype;
  v_usages integer := 0;
  v_existe boolean;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  v_vet := _vet(p_mercenaire);
  select m.nom, translate(lower(coalesce(c.nom, '')), 'êîéèô', 'eieeo')
    into v_merc, v_classe
    from mercenaire m left join classe c on c.id = m.classe_id
    where m.id = p_mercenaire;
  if v_classe <> 'druide' then
    raise exception 'Seul un Druide peut prendre la forme sauvage.';
  end if;
  if not exists (
    select 1 from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
      where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
        and mc.veterance <= v_vet and o.nom ~* '(forme|force) sauvage'
  ) then
    raise exception 'Cette compétence n''est pas la Forme Sauvage active de ce mercenaire.';
  end if;
  select compagnon, nom, sante_max into v_tag, v_nom_creature, v_pv from creature where id = p_creature and actif;
  if v_tag is null or v_tag not like 'forme_sauvage\_%' then
    raise exception 'Cette bête n''est pas disponible pour la forme sauvage.';
  end if;
  v_palier := substring(v_tag from '([0-9]+)$')::integer;
  if v_palier > v_vet then
    raise exception 'Cette bête demande la vétérance %.', v_palier;
  end if;

  select * into v_ligne from mercenaire_forme_sauvage
    where mercenaire_id = p_mercenaire and session_id = ctx_session() for update;
  v_existe := found;
  if v_existe and v_ligne.actif then
    raise exception 'Ce mercenaire est déjà sous forme sauvage.';
  end if;
  select instance_courante into v_inst from partie_etat where session_id = ctx_session();
  v_inst := coalesce(v_inst, 0);
  if v_existe and v_ligne.instance_no = v_inst then
    v_usages := v_ligne.usages;
  end if;
  if v_usages >= 2 then
    raise exception 'Forme Sauvage : les 2 utilisations de cette instance sont déjà dépensées.';
  end if;
  v_rounds := greatest(2 * _mental(p_mercenaire), 1);

  -- Dépense d'énergie (refusée si elle est insuffisante : rien n'est alors créé).
  perform mercenaire_depenser_energie(p_mercenaire, 2);

  insert into mercenaire_forme_sauvage
    (mercenaire_id, creature_id, actif, rounds_restants, rounds_total, dernier_rd, instance_no, usages, sante_actuelle)
    values (p_mercenaire, p_creature, true, v_rounds, v_rounds, false, v_inst, v_usages + 1, v_pv)
    on conflict (session_id, mercenaire_id) do update set
      creature_id = excluded.creature_id, actif = true, rounds_restants = excluded.rounds_restants,
      rounds_total = excluded.rounds_total, dernier_rd = false, instance_no = excluded.instance_no,
      usages = excluded.usages, sante_actuelle = excluded.sante_actuelle, energie_actuelle = null,
      etat = null, etat_niveau = 1, etat_rounds = 0, commentaires = '';
  perform _journal('equipement', v_merc || ' prend la forme sauvage : ' || v_nom_creature || ' (' || v_rounds || ' rounds, '
    || (v_usages + 1) || ' / 2 cette instance).', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'forme_sauvage', v_nom_creature));
  return jsonb_build_object('rounds', v_rounds, 'utilisees', v_usages + 1);
end;
$$;

-- Retour à la forme originale (bouton du joueur ou du MJ).
create function forme_sauvage_terminer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_merc text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  update mercenaire_forme_sauvage set actif = false, dernier_rd = false
    where mercenaire_id = p_mercenaire and session_id = ctx_session() and actif;
  if not found then
    raise exception 'Ce mercenaire n''est pas sous forme sauvage.';
  end if;
  select nom into v_merc from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_merc || ' retrouve sa forme originale.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'forme_sauvage', 'fin'));
end;
$$;

-- Mise à jour de l'état de la bête : seules les clés présentes dans p_patch changent. À 0 PV, la forme s'achève.
create function forme_sauvage_etat_maj(p_mercenaire uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_pv integer;
  v_actif boolean;
  v_merc text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  update mercenaire_forme_sauvage set
    sante_actuelle = case when p_patch ? 'sante_actuelle' then (p_patch ->> 'sante_actuelle')::integer else sante_actuelle end,
    energie_actuelle = case when p_patch ? 'energie_actuelle' then (p_patch ->> 'energie_actuelle')::integer else energie_actuelle end,
    etat = case when p_patch ? 'etat' then nullif(p_patch ->> 'etat', '') else etat end,
    etat_niveau = case when p_patch ? 'etat_niveau' then (p_patch ->> 'etat_niveau')::smallint else etat_niveau end,
    etat_rounds = case when p_patch ? 'etat_rounds' then (p_patch ->> 'etat_rounds')::smallint else etat_rounds end,
    commentaires = case when p_patch ? 'commentaires' then coalesce(p_patch ->> 'commentaires', '') else commentaires end
    where mercenaire_id = p_mercenaire and session_id = ctx_session() and actif
    returning sante_actuelle into v_pv;
  if not found then
    raise exception 'Ce mercenaire n''est pas sous forme sauvage.';
  end if;
  v_actif := true;
  if v_pv is not null and v_pv <= 0 then
    update mercenaire_forme_sauvage set actif = false, dernier_rd = false
      where mercenaire_id = p_mercenaire and session_id = ctx_session();
    select nom into v_merc from mercenaire where id = p_mercenaire;
    perform _journal('equipement', v_merc || ' retrouve sa forme originale (la bête tombe à 0 PV).', 0,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'forme_sauvage', 'pv0'));
    v_actif := false;
  end if;
  return jsonb_build_object('actif', v_actif);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Rd : décompte des rounds (propriétaire postgres, comme _reactions_round)
-- ---------------------------------------------------------------------------
create function _forme_sauvage_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = old.round_courant + 1 then
    update mercenaire_forme_sauvage set dernier_rd = false
      where session_id = new.session_id and dernier_rd;
    update mercenaire_forme_sauvage
      set rounds_restants = rounds_restants - 1, dernier_rd = true, actif = (rounds_restants - 1 > 0)
      where session_id = new.session_id and actif;
  elsif new.round_courant = old.round_courant - 1 then
    update mercenaire_forme_sauvage
      set rounds_restants = rounds_restants + 1, actif = true, dernier_rd = false
      where session_id = new.session_id and dernier_rd;
  end if;
  return new;
end;
$$;
create trigger partie_etat_round_forme_sauvage
  after update of round_courant on partie_etat
  for each row execute function _forme_sauvage_round();

-- ---------------------------------------------------------------------------
-- 5. Remise à zéro d'une session : la forme sauvage est sauvegardée puis effacée avec le reste
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
    'mercenaire_forme_sauvage',
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
-- 6. Propriétaire fortress_fn (isolation par session) et droits d'exécution
-- ---------------------------------------------------------------------------
grant create on schema public to fortress_fn;
alter function forme_sauvage_activer(uuid, uuid, uuid) owner to fortress_fn;
alter function forme_sauvage_terminer(uuid) owner to fortress_fn;
alter function forme_sauvage_etat_maj(uuid, jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function forme_sauvage_activer(uuid, uuid, uuid) from public;
revoke all on function forme_sauvage_terminer(uuid) from public;
revoke all on function forme_sauvage_etat_maj(uuid, jsonb) from public;
grant execute on function forme_sauvage_activer(uuid, uuid, uuid) to authenticated;
grant execute on function forme_sauvage_terminer(uuid) to authenticated;
grant execute on function forme_sauvage_etat_maj(uuid, jsonb) to authenticated;
-- _forme_sauvage_round reste propriété de postgres (déclencheur, comme _reactions_round).
revoke all on function _forme_sauvage_round() from public;
