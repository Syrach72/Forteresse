-- Compétence passive « Style de Combat » (Bruno, 2026-10-08) : à la vétérance 2, le joueur choisit UN style parmi
-- Archerie, Combat à deux armes, Défense, Duel. Le choix est définitif et conservé après un renvoi (tant que le
-- mercenaire a la vétérance 2). Un style ne se choisit qu'une fois : si un nouveau choix est un jour accordé, le
-- même style ne pourra pas être repris (contrainte d'unicité du type).
-- Automatismes d'affichage (client) : Archerie (arme à portée) et Duel (arme à une main, sans bouclier) donnent +1🎲.

create table mercenaire_style_combat (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  rang smallint not null check (rang = 1),
  type text not null check (type in ('archerie', 'combat à deux armes', 'défense', 'duel')),
  created_at timestamptz not null default now(),
  unique (session_id, mercenaire_id, rang),
  unique (session_id, mercenaire_id, type)
);
alter table mercenaire_style_combat enable row level security;
create policy "mercenaire_style_combat: lecture" on mercenaire_style_combat for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_style_combat: ecriture admin" on mercenaire_style_combat for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_style_combat: fonctions serveur" on mercenaire_style_combat for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_style_combat to authenticated, fortress_fn;
revoke all on mercenaire_style_combat from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_style_combat;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

create or replace function style_combat_choisir(p_mercenaire uuid, p_type text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_n integer;
  v_rang integer;
  v_nom text;
  v_requis integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_type is null or p_type not in ('archerie', 'combat à deux armes', 'défense', 'duel') then
    raise exception 'Choisissez un style de combat dans la liste.';
  end if;
  if not _possede_competence(p_mercenaire, array['style de combat']) then
    raise exception 'Ce mercenaire ne possède pas la compétence Style de Combat.';
  end if;
  v_vet := _vet(p_mercenaire);
  select count(*) into v_n from mercenaire_style_combat
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  v_rang := v_n + 1;
  if v_rang > 1 then
    raise exception 'Le style de combat de ce mercenaire est déjà choisi.';
  end if;
  v_requis := 2;
  if v_vet < v_requis then
    raise exception 'Le style de combat se choisit à la vétérance %.', v_requis;
  end if;
  if exists (select 1 from mercenaire_style_combat
             where mercenaire_id = p_mercenaire and session_id = ctx_session() and type = p_type) then
    raise exception 'Ce style de combat est déjà choisi pour ce mercenaire.';
  end if;
  insert into mercenaire_style_combat (mercenaire_id, rang, type) values (p_mercenaire, v_rang, p_type);
  select nom into v_nom from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_nom || ' : style de combat n°' || v_rang || ' = ' || p_type || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'style_combat', p_type, 'rang', v_rang));
  return jsonb_build_object('rang', v_rang, 'type', p_type);
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
    'mission_attribution', 'mission_compteur', 'mercenaire_effet', 'mercenaire_ennemi_jure', 'mercenaire_terrain_favori', 'mercenaire_style_combat',
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
alter function style_combat_choisir(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function style_combat_choisir(uuid, text) from public;
grant execute on function style_combat_choisir(uuid, text) to authenticated;
