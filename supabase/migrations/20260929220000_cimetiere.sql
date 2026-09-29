-- Cimetière (règle de Bruno, 2026-09-29) : à la fin d'une instance (+1 Instance, après les soins de
-- l'infirmerie), tout mercenaire recruté encore à 0 PV actuels ne réintègre pas la caserne : son
-- équipement (porté ET sac à dos) est d'abord rendu à l'arsenal (sans limite d'emplacements), puis il
-- rejoint le cimetière. Il n'est plus disponible ni recrutable, mais n'est pas renvoyé : il garde sa
-- vétérance (mercenaire_etat) et sa fiche reste consultable. Une règle de retour à la vie viendra plus tard.
create table cimetiere (
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  user_id uuid,
  nom_joueur text,
  mort_le timestamptz not null default now(),
  primary key (session_id, mercenaire_id)
);
alter table cimetiere enable row level security;
create policy "cimetiere: lecture" on cimetiere for select to authenticated
  using (session_id = ctx_session());
create policy "cimetiere: ecriture admin" on cimetiere for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "cimetiere: fonctions serveur" on cimetiere for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on cimetiere to authenticated;
revoke all on cimetiere from anon;

do $$
begin
  alter publication supabase_realtime add table cimetiere;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- Fin d'instance : envoie au cimetière les mercenaires recrutés encore à 0 PV. Renvoie, pour chaque mort,
-- de quoi annuler l'opération (recruteur, nom du joueur, équipement et contenu du sac).
create function cimetiere_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  l record;
  v_nom text;
  v_sac uuid;
  v_eq jsonb;
  v_contenu jsonb;
  v_gains jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  for r in
    select rec.mercenaire_id, rec.user_id, rec.nom_joueur
    from recrutement rec
      join mercenaire_etat e on e.mercenaire_id = rec.mercenaire_id and e.session_id = ctx_session()
    where rec.session_id = ctx_session() and e.sante_actuelle = 0
    order by rec.lit
  loop
    select nom into v_nom from mercenaire where id = r.mercenaire_id;
    select coalesce(jsonb_agg(jsonb_build_object(
        'emplacement', emplacement, 'position', position, 'objet_id', objet_id, 'gemmes', gemmes)), '[]'::jsonb)
      into v_eq from mercenaire_equipement where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    v_sac := _sac_dos_id(r.mercenaire_id);
    select coalesce(jsonb_agg(jsonb_build_object(
        'objet_id', objet_id, 'quantite', quantite, 'gemmes', gemmes)), '[]'::jsonb)
      into v_contenu from ligne_inventaire where inventaire_id = v_sac and quantite > 0;
    -- Tout l'équipement retourne à l'arsenal.
    for l in select objet_id, gemmes from mercenaire_equipement
             where mercenaire_id = r.mercenaire_id and session_id = ctx_session() loop
      perform _arsenal_ajouter(l.objet_id, 1, l.gemmes);
    end loop;
    delete from mercenaire_equipement where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    for l in select objet_id, quantite, gemmes from ligne_inventaire
             where inventaire_id = v_sac and quantite > 0 loop
      perform _arsenal_ajouter(l.objet_id, l.quantite, l.gemmes);
    end loop;
    delete from ligne_inventaire where inventaire_id = v_sac;
    insert into cimetiere (mercenaire_id, user_id, nom_joueur) values (r.mercenaire_id, r.user_id, r.nom_joueur);
    -- Le lit est libéré ; entraînement, infirmerie et quête sont quittés (déclencheurs du recrutement).
    delete from recrutement where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    perform _journal('equipement', coalesce(v_nom, 'Un mercenaire') || ' est tombé à 0 PV : il repose au cimetière, son équipement est rendu à l''arsenal.', 0,
      jsonb_build_object('mercenaire_id', r.mercenaire_id, 'cimetiere', true));
    v_gains := v_gains || jsonb_build_object(
      'mercenaire_id', r.mercenaire_id, 'user_id', r.user_id, 'nom_joueur', r.nom_joueur,
      'equipement', v_eq, 'sac', v_contenu);
  end loop;
  return v_gains;
end;
$$;

-- Annulation du dernier +1 Instance : les morts de cette instance sont rappelés (recrutement rétabli, équipement
-- repris dans l'arsenal s'il y est encore). Un mercenaire dont le lit n'est plus libre reste au cimetière.
create function cimetiere_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
  x jsonb;
  v_id uuid;
  v_sac uuid;
  v_gemmes uuid[];
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb)) loop
    v_id := (g ->> 'mercenaire_id')::uuid;
    if not exists (select 1 from cimetiere where mercenaire_id = v_id and session_id = ctx_session()) then
      continue;
    end if;
    begin
      insert into recrutement (mercenaire_id, user_id, nom_joueur)
        values (v_id, (g ->> 'user_id')::uuid, g ->> 'nom_joueur');
    exception when others then
      continue;
    end;
    delete from cimetiere where mercenaire_id = v_id and session_id = ctx_session();
    for x in select * from jsonb_array_elements(coalesce(g -> 'equipement', '[]'::jsonb)) loop
      v_gemmes := case when jsonb_typeof(x -> 'gemmes') = 'array'
        then array(select jsonb_array_elements_text(x -> 'gemmes')::uuid) else null end;
      if _arsenal_quantite((x ->> 'objet_id')::uuid, v_gemmes) >= 1 then
        perform _arsenal_retirer((x ->> 'objet_id')::uuid, 1, v_gemmes);
        insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id, gemmes)
          values (v_id, x ->> 'emplacement', (x ->> 'position')::smallint, (x ->> 'objet_id')::uuid, v_gemmes)
          on conflict do nothing;
      end if;
    end loop;
    v_sac := _sac_dos_id(v_id);
    for x in select * from jsonb_array_elements(coalesce(g -> 'sac', '[]'::jsonb)) loop
      v_gemmes := case when jsonb_typeof(x -> 'gemmes') = 'array'
        then array(select jsonb_array_elements_text(x -> 'gemmes')::uuid) else null end;
      if _arsenal_quantite((x ->> 'objet_id')::uuid, v_gemmes) >= (x ->> 'quantite')::integer then
        perform _arsenal_retirer((x ->> 'objet_id')::uuid, (x ->> 'quantite')::integer, v_gemmes);
        insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
          values (v_sac, (x ->> 'objet_id')::uuid, (x ->> 'quantite')::integer, v_gemmes);
      end if;
    end loop;
  end loop;
end;
$$;

-- Un mercenaire du cimetière ne peut plus être recruté.
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
  v_donne boolean;
  v_equipe boolean := false;
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
  if exists (select 1 from cimetiere where session_id = ctx_session() and mercenaire_id = p_mercenaire) then
    raise exception '% repose au cimetière et ne peut plus être recruté.', v_nom;
  end if;
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
  end if;

  -- Équipement de base (défini dans l'administration) : donné une seule fois par session, seulement
  -- si le mercenaire n'a encore rien d'équipé (aucun écrasement d'un équipement acquis).
  select coalesce(e.equipement_base_donne, false) into v_donne from mercenaire_etat e
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire;
  if not coalesce(v_donne, false) then
    if not exists (select 1 from mercenaire_equipement q
                   where q.session_id = ctx_session() and q.mercenaire_id = p_mercenaire) then
      insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id)
        select b.mercenaire_id, b.emplacement, b.position, b.objet_id
        from mercenaire_equipement_base b where b.mercenaire_id = p_mercenaire
        on conflict do nothing;
      v_equipe := found;
    end if;
    insert into mercenaire_etat (session_id, mercenaire_id, veterance, equipement_base_donne)
      values (ctx_session(), p_mercenaire, v_vet, true)
      on conflict (session_id, mercenaire_id) do update set equipement_base_donne = true;
  end if;

  if v_gratuit then
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : premier mercenaire de '
      || v_joueur || ', gratuit.' || case when v_equipe then ' Il arrive avec son équipement de base.' else '' end, 0,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', 0, 'gratuit', true));
  else
    update partie_etat set or_compagnie = or_compagnie - v_cout where id;
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : −' || v_cout || ' Po.'
      || case when v_equipe then ' Il arrive avec son équipement de base.' else '' end, -v_cout,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', v_cout));
  end if;
  return jsonb_build_object('cout', v_cout, 'or', v_or - v_cout, 'gratuit', v_gratuit);
end;
$$;

-- La remise à zéro d'une partie vide aussi le cimetière.
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
    'cimetiere', 'recrutement_gratuit', 'objet_quete_active', 'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
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
alter function cimetiere_instance() owner to fortress_fn;
alter function cimetiere_annuler_instance(jsonb) owner to fortress_fn;
alter function mercenaire_recruter(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function cimetiere_instance() from public;
revoke all on function cimetiere_annuler_instance(jsonb) from public;
grant execute on function cimetiere_instance() to authenticated;
grant execute on function cimetiere_annuler_instance(jsonb) to authenticated;
