-- Départ de session (Bruno, 2026-09-29) :
--  1. une nouvelle session démarre avec 300 Po (au lieu de 1000) avant le premier « +1 Instance » :
--     valeur de départ de la base (réglable dans l'administration), copiée à chaque lancement de session ;
--  2. le PREMIER mercenaire recruté dans une session par un même joueur (même nom de joueur, sans
--     tenir compte des majuscules) est gratuit. Son entretien reste dû (il est calculé sur les
--     recrutements en cours). La gratuité est consommée une seule fois par nom de joueur et par
--     session, même si le mercenaire est renvoyé ensuite.
update base_depart set or_compagnie = 300;
alter table base_depart alter column or_compagnie set default 300;

create table recrutement_gratuit (
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  nom_cle text not null,
  mercenaire_id uuid references mercenaire (id) on delete set null,
  cree_le timestamptz not null default now(),
  primary key (session_id, nom_cle)
);
alter table recrutement_gratuit enable row level security;
create policy "recrutement_gratuit: lecture" on recrutement_gratuit for select to authenticated
  using (session_id = ctx_session());
create policy "recrutement_gratuit: ecriture admin" on recrutement_gratuit for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "recrutement_gratuit: fonctions serveur" on recrutement_gratuit for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on recrutement_gratuit to authenticated;
revoke all on recrutement_gratuit from anon;

do $$
begin
  alter publication supabase_realtime add table recrutement_gratuit;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

create or replace function mercenaire_recruter(p_mercenaire uuid, p_nom_joueur text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  v_nom text;
  v_vet integer;
  v_cout integer;
  v_joueur text := left(btrim(coalesce(p_nom_joueur, '')), 24);
  v_cle text;
  v_gratuit boolean;
begin
  v_or := _verrou_partie();
  if v_joueur = '' then
    raise exception 'Inscrivez votre nom de joueur avant de recruter.';
  end if;
  v_cle := lower(v_joueur);
  select nom into v_nom from mercenaire where id = p_mercenaire;
  if v_nom is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  v_vet := _vet(p_mercenaire);
  v_gratuit := not exists (
    select 1 from recrutement_gratuit where session_id = ctx_session() and nom_cle = v_cle);
  v_cout := case when v_gratuit then 0 else 100 * v_vet end;
  if v_or < v_cout then
    raise exception 'Trésorerie insuffisante : recruter % coûte % Po (100 Po × vétérance %).', v_nom, v_cout, v_vet;
  end if;
  -- L'insertion attribue le lit (ou refuse s'il n'y en a plus, ou si le mercenaire est déjà
  -- recruté) : rien n'est payé ni consommé dans ces cas, l'opération entière est annulée.
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (p_mercenaire, auth.uid(), v_joueur);
  if v_gratuit then
    insert into recrutement_gratuit (nom_cle, mercenaire_id) values (v_cle, p_mercenaire);
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : premier mercenaire de '
      || v_joueur || ', gratuit.', 0,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', 0, 'gratuit', true));
  else
    update partie_etat set or_compagnie = or_compagnie - v_cout where id;
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : −' || v_cout || ' Po.', -v_cout,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', v_cout));
  end if;
  return jsonb_build_object('cout', v_cout, 'or', v_or - v_cout, 'gratuit', v_gratuit);
end;
$$;

-- La remise à zéro d'une partie efface aussi les gratuités consommées.
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
    'recrutement_gratuit', 'objet_quete_active', 'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
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
alter function mercenaire_recruter(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
