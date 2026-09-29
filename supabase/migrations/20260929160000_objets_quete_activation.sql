-- Objets de quête : activation (règle de Bruno, 2026-09-29). Quand une quête est terminée, ses objets
-- (rubrique « Objets de Quête » : Calèche, Forge, Armurerie…) rejoignent l'arsenal. Depuis la fiche de
-- l'objet, le bouton « Activer » lui fait produire DÉFINITIVEMENT son effet pour la session, puis
-- l'objet disparaît de l'inventaire. Les effets (lieux déverrouillés, sac à dos +3 pour la Calèche)
-- se lisent désormais sur cette table d'activation, plus sur la simple possession.
create table objet_quete_active (
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  objet_id uuid not null references objet_catalogue (id) on delete cascade,
  active_le timestamptz not null default now(),
  primary key (session_id, objet_id)
);
alter table objet_quete_active enable row level security;
create policy "objet_quete_active: lecture" on objet_quete_active for select to authenticated
  using (session_id = ctx_session());
create policy "objet_quete_active: ecriture admin" on objet_quete_active for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "objet_quete_active: fonctions serveur" on objet_quete_active for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on objet_quete_active to authenticated;
revoke all on objet_quete_active from anon;

do $$
begin
  alter publication supabase_realtime add table objet_quete_active;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- Activation : retire un exemplaire de l'arsenal et enregistre l'effet, en une seule opération.
create or replace function objet_quete_activer(p_objet uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_nom text;
  v_racine text;
begin
  perform _verrou_partie();
  select nom, _racine_categorie(categorie_id) into v_nom, v_racine
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  if v_racine is distinct from 'Objets de Quête' then
    raise exception 'Seuls les objets de quête peuvent être activés.';
  end if;
  if exists (select 1 from objet_quete_active where objet_id = p_objet and session_id = ctx_session()) then
    raise exception '% est déjà activé.', v_nom;
  end if;
  if _arsenal_quantite(p_objet) < 1 then
    raise exception '% n''est pas dans l''arsenal.', v_nom;
  end if;
  perform _arsenal_retirer(p_objet, 1);
  insert into objet_quete_active (objet_id) values (p_objet);
  perform _journal('equipement', v_nom || ' activé : son effet est permanent pour la session.', 0,
    jsonb_build_object('objet_id', p_objet));
end;
$$;

-- Sac à dos : +3 emplacements pour tous les mercenaires dès que la Calèche est ACTIVÉE.
create or replace function _sac_capacite()
returns integer
language sql
stable
security definer set search_path = public
as $$
  select 9 + case when exists (
    select 1 from objet_quete_active a
      join objet_catalogue o on o.id = a.objet_id
    where a.session_id = ctx_session()
      and lower(o.nom) in ('calèche', 'caleche')
  ) then 3 else 0 end;
$$;

-- La remise à zéro d'une partie efface aussi les activations.
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
    'objet_quete_active', 'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
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

grant create on schema public to fortress_fn;
alter function objet_quete_activer(uuid) owner to fortress_fn;
alter function _sac_capacite() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function objet_quete_activer(uuid) from public;
grant execute on function objet_quete_activer(uuid) to authenticated;
