-- Compétences actives à usage limité (Bruno, 2026-10-13) : Fougue, Second Souffle, Attaque Sournoise.
--
--  * Fougue : coût 3 énergies, une fois par Instance.
--  * Second Souffle : une fois par Instance ; 0 à 10 énergies au choix ; rend 3 PV + 1 PV par tranche de 2 énergies
--    dépensées (crédités par le serveur, plafonnés à la santé max, comme une potion de vie).
--  * Attaque Sournoise : coût 1 énergie, une fois par Round.
--
-- Un usage = une ligne `mercenaire_competence_limitee` portant la période ('instance' ou 'round') et son numéro :
--   - instance : annuler un +1 Instance rattache les usages de l'instance annulée à la précédente ;
--   - round : le numéro du Rd en cours sert de clé, donc « Annuler » le Rd retrouve l'état d'avant ; la remise à
--     zéro du round efface les usages par round.

create table mercenaire_competence_limitee (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  competence_id uuid not null,
  periode text not null check (periode in ('instance', 'round')),
  numero integer not null,
  created_at timestamptz not null default now()
);
create index mercenaire_competence_limitee_merc on mercenaire_competence_limitee (session_id, mercenaire_id);
alter table mercenaire_competence_limitee enable row level security;
create policy "mercenaire_competence_limitee: lecture" on mercenaire_competence_limitee for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_competence_limitee: ecriture admin" on mercenaire_competence_limitee for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_competence_limitee: fonctions serveur" on mercenaire_competence_limitee for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_competence_limitee to authenticated, fortress_fn;
revoke all on mercenaire_competence_limitee from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_competence_limitee;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

create function competence_limitee_utiliser(p_mercenaire uuid, p_competence uuid, p_montant integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_nom text;
  v_cle text;
  v_periode text;
  v_cout integer;
  v_soin integer := 0;
  v_numero integer;
  v_merc text;
  v_max integer;
  v_act integer;
  v_nouvelle integer;
  v_reste integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence active n''est pas utilisable par ce mercenaire.';
  end if;
  v_cle := case
    when lower(btrim(v_nom)) = 'fougue' then 'fougue'
    when lower(btrim(v_nom)) = 'second souffle' then 'second souffle'
    when lower(btrim(v_nom)) = 'attaque sournoise' then 'attaque sournoise'
  end;
  if v_cle is null then
    raise exception 'Cette compétence n''a pas de limite d''usage gérée par le site.';
  end if;
  v_periode := case when v_cle = 'attaque sournoise' then 'round' else 'instance' end;
  if v_periode = 'instance' then
    select instance_courante into v_numero from partie_etat where session_id = ctx_session();
  else
    select round_courant into v_numero from partie_etat where session_id = ctx_session();
  end if;
  v_numero := coalesce(v_numero, 0);
  if exists (select 1 from mercenaire_competence_limitee
             where session_id = ctx_session() and mercenaire_id = p_mercenaire and competence_id = p_competence
               and periode = v_periode and numero = v_numero) then
    raise exception '% : déjà utilisée pour ce% en cours.', v_nom,
      case when v_periode = 'instance' then 'tte instance' else ' round' end;
  end if;
  v_cout := case v_cle
    when 'fougue' then 3
    when 'attaque sournoise' then 1
    else coalesce(p_montant, 0)
  end;
  if v_cout < 0 or v_cout > 10 then
    raise exception 'Le montant à dépenser est un entier de 0 à 10.';
  end if;
  if v_cout > 0 then
    perform mercenaire_depenser_energie(p_mercenaire, v_cout);
  end if;
  if v_cle = 'second souffle' then
    v_soin := 3 + v_cout / 2;
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
      on conflict (session_id, mercenaire_id) do nothing;
    v_max := _sante_max(p_mercenaire);
    select coalesce(e.sante_actuelle, v_max) into v_act from mercenaire_etat e
      where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire for update;
    v_nouvelle := least(v_act + v_soin, greatest(v_max, v_act));
    update mercenaire_etat set sante_actuelle = case when v_nouvelle >= v_max then null else v_nouvelle end
      where session_id = ctx_session() and mercenaire_id = p_mercenaire;
    v_soin := v_nouvelle - v_act;
    if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
      v_reste := _soins_instances(p_mercenaire, case when v_nouvelle >= v_max then null else v_nouvelle end);
      if v_reste = 0 then
        delete from infirmerie_place where mercenaire_id = p_mercenaire;
      else
        update infirmerie_place set restant = v_reste where mercenaire_id = p_mercenaire;
      end if;
    end if;
  end if;
  insert into mercenaire_competence_limitee (mercenaire_id, competence_id, periode, numero)
    values (p_mercenaire, p_competence, v_periode, v_numero);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' (' || v_cout || ' énergie(s)'
    || case when v_cle = 'second souffle' then ', +' || v_soin || ' PV' else '' end || ').', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'competence_id', p_competence, 'usage_limite', v_cle));
  return jsonb_build_object('competence', v_cle, 'energie', v_cout, 'soin', v_soin);
end;
$$;

-- Remise à zéro du round (Rd -> 0) : les usages « par round » sont effacés.
create function _competence_limitee_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = 0 and old.round_courant > 0 then
    delete from mercenaire_competence_limitee where session_id = new.session_id and periode = 'round';
  end if;
  return new;
end;
$$;
create trigger partie_etat_round_competence_limitee
  after update of round_courant on partie_etat
  for each row execute function _competence_limitee_round();

-- +1 Instance annulé : les usages de l'instance annulée rejoignent la précédente (comme le Conduit Divin).
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
  update mercenaire_competence_limitee set numero = v_instance
    where session_id = ctx_session() and periode = 'instance' and numero > v_instance;
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
    'mission_attribution', 'mission_compteur', 'mercenaire_effet', 'mercenaire_ennemi_jure', 'mercenaire_terrain_favori', 'mercenaire_style_combat', 'mercenaire_conduit_divin', 'mercenaire_compagnon',
    'mercenaire_forme_sauvage', 'mercenaire_ressourcement', 'mercenaire_competence_limitee',
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
alter function competence_limitee_utiliser(uuid, uuid, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function competence_limitee_utiliser(uuid, uuid, integer) from public;
grant execute on function competence_limitee_utiliser(uuid, uuid, integer) to authenticated;
-- _competence_limitee_round reste propriété de postgres (déclencheur, comme _reactions_round).
revoke all on function _competence_limitee_round() from public;
