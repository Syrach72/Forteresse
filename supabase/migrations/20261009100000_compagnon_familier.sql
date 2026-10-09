-- Compagnon animal (Rôdeur Maître des Bêtes) et familier (Incantateur) — demande de Bruno, 2026-10-09.
--
-- À partir de la vétérance 3, le joueur choisit un compagnon animal (faucon, chien ou panthère) pour son Rôdeur
-- Maître des Bêtes, ou un familier pour son Incantateur. Les fiches viennent du catalogue des créatures (créées
-- dans l'administration) : une fiche est repérée par la colonne `creature.compagnon`. Une fois validé, le choix
-- devient un onglet « Compagnon » / « Familier » sur la fiche du mercenaire.
--
--  * `creature.compagnon` : 'faucon' | 'chien' | 'panthere' | 'familier' (null = créature ordinaire, MJ seul).
--    Seules les créatures repérées (et leurs capacités, icônes, armes) deviennent lisibles par les joueurs.
--  * `mercenaire_compagnon` : un compagnon (ou familier) par mercenaire et par session ; l'état de jeu seulement
--    (santé, énergie, état, commentaires), la fiche restant lue dans le catalogue.
--  * `compagnon_choisir` : vérifie la classe, la vétérance 3 et l'absence de choix déjà fait ; le choix est définitif
--    (seul le MJ peut le retirer). `compagnon_etat_maj` : le joueur du mercenaire (ou le MJ) tient l'état à jour.
-- Toute suppression/mise à jour a une clause WHERE explicite (pg_safeupdate).

alter table creature add column compagnon text
  check (compagnon in ('faucon', 'chien', 'panthere', 'familier'));

-- ---------------------------------------------------------------------------
-- 1. Lecture par les joueurs des seules fiches de compagnons
-- ---------------------------------------------------------------------------
create policy "creature: lecture compagnons" on creature for select to authenticated
  using (compagnon is not null and actif);
create policy "creature: lecture fonctions serveur" on creature for select to fortress_fn
  using (compagnon is not null);

create function _creature_est_compagnon(p_creature uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (select 1 from creature where id = p_creature and compagnon is not null and actif);
$$;
revoke all on function _creature_est_compagnon(uuid) from public;
grant execute on function _creature_est_compagnon(uuid) to authenticated;

create function _capacite_creature_visible(p_capacite uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (select 1 from creature_capacite cc where cc.capacite_id = p_capacite and _creature_est_compagnon(cc.creature_id));
$$;
revoke all on function _capacite_creature_visible(uuid) from public;
grant execute on function _capacite_creature_visible(uuid) to authenticated;

create policy "creature_capacite: lecture compagnons" on creature_capacite for select to authenticated
  using (_creature_est_compagnon(creature_id));
create policy "creature_arme: lecture compagnons" on creature_arme for select to authenticated
  using (_creature_est_compagnon(creature_id));
create policy "capacite_creature: lecture compagnons" on capacite_creature for select to authenticated
  using (_capacite_creature_visible(id));

-- ---------------------------------------------------------------------------
-- 2. Le compagnon d'un mercenaire (état par session)
-- ---------------------------------------------------------------------------
create table mercenaire_compagnon (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  role text not null check (role in ('compagnon', 'familier')),
  creature_id uuid not null references creature (id) on delete cascade,
  sante_actuelle integer check (sante_actuelle is null or sante_actuelle >= 0),
  energie_actuelle integer check (energie_actuelle is null or energie_actuelle >= 0),
  etat text check (etat is null or length(etat) <= 30),
  etat_niveau smallint not null default 1 check (etat_niveau between 1 and 3),
  etat_rounds smallint not null default 0 check (etat_rounds between 0 and 9),
  commentaires text not null default '' check (length(commentaires) <= 4000),
  created_at timestamptz not null default now(),
  unique (session_id, mercenaire_id)
);
alter table mercenaire_compagnon enable row level security;
create policy "mercenaire_compagnon: lecture" on mercenaire_compagnon for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_compagnon: ecriture admin" on mercenaire_compagnon for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_compagnon: fonctions serveur" on mercenaire_compagnon for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_compagnon to authenticated, fortress_fn;
revoke all on mercenaire_compagnon from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_compagnon;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Choisir (définitif) et tenir à jour
-- ---------------------------------------------------------------------------
create function compagnon_choisir(p_mercenaire uuid, p_creature uuid)
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
  if v_tag is null then
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

-- Mise à jour de l'état du compagnon : seules les clés présentes dans p_patch changent
-- (sante_actuelle, energie_actuelle, etat, etat_niveau, etat_rounds, commentaires).
create function compagnon_etat_maj(p_mercenaire uuid, p_patch jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  update mercenaire_compagnon set
    sante_actuelle = case when p_patch ? 'sante_actuelle' then (p_patch ->> 'sante_actuelle')::integer else sante_actuelle end,
    energie_actuelle = case when p_patch ? 'energie_actuelle' then (p_patch ->> 'energie_actuelle')::integer else energie_actuelle end,
    etat = case when p_patch ? 'etat' then nullif(p_patch ->> 'etat', '') else etat end,
    etat_niveau = case when p_patch ? 'etat_niveau' then (p_patch ->> 'etat_niveau')::smallint else etat_niveau end,
    etat_rounds = case when p_patch ? 'etat_rounds' then (p_patch ->> 'etat_rounds')::smallint else etat_rounds end,
    commentaires = case when p_patch ? 'commentaires' then coalesce(p_patch ->> 'commentaires', '') else commentaires end
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  if not found then
    raise exception 'Ce mercenaire n''a pas de compagnon.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Remise à zéro d'une session : le compagnon est sauvegardé puis effacé avec le reste
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
-- 5. Propriétaire fortress_fn (isolation par session) et droits d'exécution
-- ---------------------------------------------------------------------------
grant create on schema public to fortress_fn;
alter function compagnon_choisir(uuid, uuid) owner to fortress_fn;
alter function compagnon_etat_maj(uuid, jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function compagnon_choisir(uuid, uuid) from public;
revoke all on function compagnon_etat_maj(uuid, jsonb) from public;
grant execute on function compagnon_choisir(uuid, uuid) to authenticated;
grant execute on function compagnon_etat_maj(uuid, jsonb) to authenticated;
