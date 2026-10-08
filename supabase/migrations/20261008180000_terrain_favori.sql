-- Compétence passive « Explorateur-né » du Rôdeur (Bruno, 2026-10-08) : le joueur choisit un type de terrain favori au
-- recrutement du mercenaire, un deuxième à la vétérance 4 et un troisième à la vétérance 8 (même mécanique que
-- l'Ennemi Juré : pas de doublon, choix conservés après un renvoi tant que la vétérance requise est atteinte).
-- Terrains : arctique, désert, forêt, littoral, marais, montagne, plaine, Outreterre.
-- Information de fiche : aucun calcul du site n'en dépend.

create table mercenaire_terrain_favori (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  rang smallint not null check (rang between 1 and 3),
  type text not null check (type in ('arctique', 'désert', 'forêt', 'littoral', 'marais', 'montagne', 'plaine', 'outreterre')),
  created_at timestamptz not null default now(),
  unique (session_id, mercenaire_id, rang),
  unique (session_id, mercenaire_id, type)
);
alter table mercenaire_terrain_favori enable row level security;
create policy "mercenaire_terrain_favori: lecture" on mercenaire_terrain_favori for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_terrain_favori: ecriture admin" on mercenaire_terrain_favori for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_terrain_favori: fonctions serveur" on mercenaire_terrain_favori for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_terrain_favori to authenticated, fortress_fn;
revoke all on mercenaire_terrain_favori from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_terrain_favori;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

create or replace function terrain_favori_choisir(p_mercenaire uuid, p_type text)
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
  if p_type is null or p_type not in ('arctique', 'désert', 'forêt', 'littoral', 'marais', 'montagne', 'plaine', 'outreterre') then
    raise exception 'Choisissez un type de terrain dans la liste.';
  end if;
  if not _possede_competence(p_mercenaire, array['explorateur-né']) then
    raise exception 'Ce mercenaire ne possède pas la compétence Explorateur-né.';
  end if;
  v_vet := _vet(p_mercenaire);
  select count(*) into v_n from mercenaire_terrain_favori
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  v_rang := v_n + 1;
  if v_rang > 3 then
    raise exception 'Les trois terrains favoris de ce mercenaire sont déjà choisis.';
  end if;
  v_requis := case v_rang when 1 then 1 when 2 then 4 else 8 end;
  if v_vet < v_requis then
    raise exception 'Le prochain terrain favori se choisit à la vétérance %.', v_requis;
  end if;
  if exists (select 1 from mercenaire_terrain_favori
             where mercenaire_id = p_mercenaire and session_id = ctx_session() and type = p_type) then
    raise exception 'Ce terrain favori est déjà choisi pour ce mercenaire : choisissez un autre terrain.';
  end if;
  insert into mercenaire_terrain_favori (mercenaire_id, rang, type) values (p_mercenaire, v_rang, p_type);
  select nom into v_nom from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_nom || ' : terrain favori n°' || v_rang || ' = ' || p_type || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'terrain_favori', p_type, 'rang', v_rang));
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
    'mission_attribution', 'mission_compteur', 'mercenaire_effet', 'mercenaire_ennemi_jure', 'mercenaire_terrain_favori',
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
alter function terrain_favori_choisir(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function terrain_favori_choisir(uuid, text) from public;
grant execute on function terrain_favori_choisir(uuid, text) to authenticated;
