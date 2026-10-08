-- Conduit Divin (Bruno, 2026-10-08) : une compétence ACTIVE dont le titre porte « CD » s'utilise sans dépense d'énergie,
-- après validation du joueur. Les utilisations sont limitées PAR INSTANCE et partagées entre toutes les compétences CD du
-- mercenaire : 1, puis 2 à partir de la vétérance 4, puis 3 à partir de la vétérance 8. Une même compétence CD ne se
-- reprend pas dans la même instance ; quand toutes les utilisations sont dépensées, toutes les compétences CD sont
-- grisées. Le compteur repart à zéro au +1 Instance (les utilisations sont rattachées au numéro de l'instance) ; annuler
-- un +1 Instance rend les utilisations de l'instance précédente telles qu'elles étaient.

create table mercenaire_conduit_divin (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  competence_id uuid not null references objet_catalogue (id) on delete cascade,
  instance_no integer not null,
  created_at timestamptz not null default now(),
  unique (session_id, mercenaire_id, competence_id, instance_no)
);
alter table mercenaire_conduit_divin enable row level security;
create policy "mercenaire_conduit_divin: lecture" on mercenaire_conduit_divin for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_conduit_divin: ecriture admin" on mercenaire_conduit_divin for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_conduit_divin: fonctions serveur" on mercenaire_conduit_divin for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_conduit_divin to authenticated, fortress_fn;
revoke all on mercenaire_conduit_divin from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_conduit_divin;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

create or replace function conduit_divin_utiliser(p_mercenaire uuid, p_competence uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_inst integer;
  v_total integer;
  v_n integer;
  v_nom text;
  v_merc text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select instance_courante into v_inst from partie_etat where session_id = ctx_session();
  v_inst := coalesce(v_inst, 0);
  -- Utilisations d'une instance annulée depuis : elles ne comptent plus.
  delete from mercenaire_conduit_divin
    where session_id = ctx_session() and mercenaire_id = p_mercenaire and instance_no > v_inst;
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
      and o.nom ~ '(^|[^A-Za-z])CD([^A-Za-z]|$)'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas une compétence Conduit Divin (CD) active de ce mercenaire.';
  end if;
  v_vet := _vet(p_mercenaire);
  v_total := 1 + (v_vet >= 4)::integer + (v_vet >= 8)::integer;
  if exists (select 1 from mercenaire_conduit_divin
             where session_id = ctx_session() and mercenaire_id = p_mercenaire
               and competence_id = p_competence and instance_no = v_inst) then
    raise exception 'Cette compétence a déjà été utilisée pendant cette instance.';
  end if;
  select count(*) into v_n from mercenaire_conduit_divin
    where session_id = ctx_session() and mercenaire_id = p_mercenaire and instance_no = v_inst;
  if v_n >= v_total then
    raise exception 'Conduit Divin : les % utilisation(s) de cette instance sont déjà dépensées.', v_total;
  end if;
  insert into mercenaire_conduit_divin (mercenaire_id, competence_id, instance_no)
    values (p_mercenaire, p_competence, v_inst);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' (Conduit Divin : ' || (v_n + 1) || ' / ' || v_total || ').', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'competence_id', p_competence, 'conduit_divin', v_n + 1));
  return jsonb_build_object('utilisees', v_n + 1, 'total', v_total);
end;
$$;

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
    'mission_attribution', 'mission_compteur', 'mercenaire_effet', 'mercenaire_ennemi_jure', 'mercenaire_terrain_favori', 'mercenaire_style_combat', 'mercenaire_conduit_divin',
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




grant create on schema public to fortress_fn;
alter function conduit_divin_utiliser(uuid, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function conduit_divin_utiliser(uuid, uuid) from public;
grant execute on function conduit_divin_utiliser(uuid, uuid) to authenticated;
