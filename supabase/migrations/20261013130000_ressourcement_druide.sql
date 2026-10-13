-- Ressourcement du Druide « Cercle de la Terre » (Bruno, 2026-10-13) : une utilisation par instance ET par terrain
-- favori différent possédé (1 à 5). Le décompte est fait par instance, comme le Conduit Divin ; aucune énergie n'est
-- dépensée (le coût éventuel reste à régler à la table).
--
--  * `mercenaire_ressourcement` : une ligne par utilisation (mercenaire, instance).
--  * `ressourcement_utiliser` : vérifie la classe/sous-classe, la compétence active atteinte et le solde.
--  * Annuler un +1 Instance rattache les utilisations de l'instance annulée à la précédente (comme le Conduit Divin).

create table mercenaire_ressourcement (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  competence_id uuid not null,
  instance_no integer not null,
  created_at timestamptz not null default now()
);
alter table mercenaire_ressourcement enable row level security;
create policy "mercenaire_ressourcement: lecture" on mercenaire_ressourcement for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_ressourcement: ecriture admin" on mercenaire_ressourcement for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_ressourcement: fonctions serveur" on mercenaire_ressourcement for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_ressourcement to authenticated, fortress_fn;
revoke all on mercenaire_ressourcement from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_ressourcement;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

create function ressourcement_utiliser(p_mercenaire uuid, p_competence uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_inst integer;
  v_total integer;
  v_n integer;
  v_nom text;
  v_merc text;
  v_classe text;
  v_sous text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select m.nom, translate(lower(coalesce(c.nom, '')), 'êîéèô', 'eieeo'),
         translate(lower(btrim(coalesce(m.sous_classe, ''))), 'êîéèô', 'eieeo')
    into v_merc, v_classe, v_sous
    from mercenaire m left join classe c on c.id = m.classe_id
    where m.id = p_mercenaire;
  if v_classe <> 'druide' or v_sous <> 'cercle de la terre' then
    raise exception 'Seul un Druide du Cercle de la Terre peut utiliser le Ressourcement.';
  end if;
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
      and o.nom ~* 'ressourcement'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas le Ressourcement actif de ce mercenaire.';
  end if;
  select instance_courante into v_inst from partie_etat where session_id = ctx_session();
  v_inst := coalesce(v_inst, 0);
  select count(*) into v_total from mercenaire_terrain_favori
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  select count(*) into v_n from mercenaire_ressourcement
    where mercenaire_id = p_mercenaire and session_id = ctx_session() and instance_no = v_inst;
  if v_n >= v_total then
    raise exception 'Ressourcement : les % utilisation(s) de cette instance sont déjà dépensées.', v_total;
  end if;
  insert into mercenaire_ressourcement (mercenaire_id, competence_id, instance_no)
    values (p_mercenaire, p_competence, v_inst);
  perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' (' || (v_n + 1) || ' / ' || v_total || ' cette instance).', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'competence_id', p_competence, 'ressourcement', v_n + 1));
  return jsonb_build_object('utilisees', v_n + 1, 'total', v_total);
end;
$$;

-- +1 Instance annulé : les utilisations de l'instance annulée rejoignent la précédente (comme le Conduit Divin).
create or replace function journal_instance_annuler()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_instance integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  update partie_etat set instance_courante = greatest(instance_courante - 1, 0)
    where id and session_id = ctx_session()
    returning instance_courante into v_instance;
  update partie_journal set instance_no = v_instance
    where session_id = ctx_session() and instance_no > v_instance;
  update mercenaire_conduit_divin set instance_no = v_instance
    where session_id = ctx_session() and instance_no > v_instance;
  update mercenaire_ressourcement set instance_no = v_instance
    where session_id = ctx_session() and instance_no > v_instance;
end;
$$;

-- Remise à zéro d'une session : le Ressourcement est sauvegardé puis effacé avec le reste.
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
    'mercenaire_forme_sauvage', 'mercenaire_ressourcement',
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

grant create on schema public to fortress_fn;
alter function ressourcement_utiliser(uuid, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function ressourcement_utiliser(uuid, uuid) from public;
grant execute on function ressourcement_utiliser(uuid, uuid) to authenticated;
