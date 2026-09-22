-- Gestion des employes (regle de Bruno, 2026-09-22) : depuis le Marche, le
-- bouton "Materiaux" devient "Materiaux et Embauche" et ouvre les deux cote a
-- cote. Un employe (Mineur, Bucheron, Tanneur pour l'instant) est un objet du
-- catalogue comme les autres (categorie racine "Embauche"), mais l'achat ne
-- rejoint pas l'arsenal : il va dans une nouvelle table `employe` (visible sur
-- une nouvelle page "Gestion des Employes"). Chaque metier produit une
-- quantite d'un materiau par instance (proportionnelle au nombre embauche,
-- avec un bonus si equipe d'un outil specialise pris dans l'arsenal), et
-- coute un entretien en Po par instance -- les deux au meme rythme que les
-- ateliers (+1 Instance).
--
-- Tout est reglable depuis l'admin (comme veterance_requise, cout_achat_or,
-- etc.) : aucune valeur de production/entretien n'est fixee ici, Bruno les
-- saisit lui-meme sur la fiche du metier.

insert into categorie (nom) values ('Embauche') on conflict (nom) do nothing;

alter table objet_catalogue
  add column if not exists emploi_materiau_id uuid references objet_catalogue (id),
  add column if not exists emploi_production integer,
  add column if not exists emploi_production_outil integer,
  add column if not exists emploi_outil_id uuid references objet_catalogue (id),
  add column if not exists emploi_entretien integer;

-- ---------------------------------------------------------------------------
-- Effectif embauche : une ligne par (metier, avec/sans outil), quantite
-- toujours >= 0. Partage entre tous les joueurs, comme l'arsenal.
-- ---------------------------------------------------------------------------
create table employe (
  id uuid primary key default gen_random_uuid(),
  objet_id uuid not null references objet_catalogue (id),
  outil boolean not null default false,
  quantite integer not null default 0 check (quantite >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (objet_id, outil)
);

alter table employe enable row level security;
create policy "employe: lecture par les joueurs connectes"
  on employe for select to authenticated using (true);
create policy "employe: ecriture admin"
  on employe for all to authenticated using (is_admin()) with check (is_admin());

-- ---------------------------------------------------------------------------
-- Embauche : debite le cout (par unite) de la tresorerie, ajoute a
-- l'effectif "sans outil". Reserve a la categorie racine "Embauche".
-- ---------------------------------------------------------------------------
create function employe_embaucher(p_objet uuid, p_quantite integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  o objet_catalogue%rowtype;
  v_cout integer;
  v_jid uuid;
begin
  v_or := _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  select * into o from objet_catalogue where id = p_objet and actif is not false;
  if not found then
    raise exception 'Objet inconnu.';
  end if;
  if _racine_categorie(o.categorie_id) is distinct from 'Embauche' then
    raise exception 'Cet objet ne peut pas être embauché.';
  end if;
  if o.cout_achat_or is null or o.cout_achat_or < 0 then
    raise exception 'Le coût d''embauche de ce métier n''est pas encore défini.';
  end if;
  v_cout := o.cout_achat_or * p_quantite;
  if v_or < v_cout then
    raise exception 'Vous n''avez pas assez de pièces d''or.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - v_cout where id;
  insert into employe (objet_id, outil, quantite) values (p_objet, false, p_quantite)
    on conflict (objet_id, outil) do update set quantite = employe.quantite + excluded.quantite, updated_at = now();
  v_jid := _journal('embauche', p_quantite || ' ' || o.nom || '(s) embauché(s) : −' || v_cout || ' Po.',
    -v_cout, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
  return jsonb_build_object('journal_id', v_jid, 'or', v_or - v_cout);
end;
$$;

-- Congediement : definitif, sans remboursement (renvoi, pas revente).
create function employe_congedier(p_objet uuid, p_outil boolean, p_quantite integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
  v_actuel integer;
  v_outil boolean := coalesce(p_outil, false);
begin
  perform _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  select quantite into v_actuel from employe where objet_id = p_objet and outil = v_outil for update;
  if v_actuel is null or v_actuel < p_quantite then
    raise exception 'Cet employé n''est pas disponible en telle quantité.';
  end if;
  select * into o from objet_catalogue where id = p_objet;
  if v_actuel = p_quantite then
    delete from employe where objet_id = p_objet and outil = v_outil;
  else
    update employe set quantite = quantite - p_quantite, updated_at = now()
      where objet_id = p_objet and outil = v_outil;
  end if;
  perform _journal('congediement', p_quantite || ' ' || coalesce(o.nom, 'employé') || '(s) congédié(s).', 0,
    jsonb_build_object('objet_id', p_objet, 'outil', v_outil, 'quantite', p_quantite));
end;
$$;

-- Equiper l'outil specialise du metier : consomme l'outil dans l'arsenal,
-- deplace des employes de la pile "sans outil" vers "avec outil".
create function employe_equiper_outil(p_objet uuid, p_quantite integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
  v_sans integer;
  v_jid uuid;
begin
  perform _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  select * into o from objet_catalogue where id = p_objet;
  if not found then
    raise exception 'Objet inconnu.';
  end if;
  if o.emploi_outil_id is null then
    raise exception 'Aucun outil spécialisé n''est défini pour ce métier.';
  end if;
  select quantite into v_sans from employe where objet_id = p_objet and outil = false for update;
  if v_sans is null or v_sans < p_quantite then
    raise exception 'Pas assez d''employés sans outil disponibles.';
  end if;
  if _arsenal_quantite(o.emploi_outil_id) < p_quantite then
    raise exception 'Pas assez d''outils dans l''arsenal.';
  end if;
  perform _arsenal_retirer(o.emploi_outil_id, p_quantite);
  update employe set quantite = quantite - p_quantite, updated_at = now()
    where objet_id = p_objet and outil = false;
  insert into employe (objet_id, outil, quantite) values (p_objet, true, p_quantite)
    on conflict (objet_id, outil) do update set quantite = employe.quantite + excluded.quantite, updated_at = now();
  v_jid := _journal('equipement', p_quantite || ' ' || o.nom || '(s) équipé(s) de leur outil spécialisé.', 0,
    jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
  return jsonb_build_object('journal_id', v_jid);
end;
$$;

-- ---------------------------------------------------------------------------
-- Production et entretien, au meme rythme que les ateliers (+1 Instance,
-- administrateur). Pas de file d'attente ici : chaque employe produit et
-- coute a chaque instance, tant qu'il est dans l'effectif.
-- ---------------------------------------------------------------------------
create function employes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  o objet_catalogue%rowtype;
  v_gains jsonb := '[]'::jsonb;
  v_production integer;
  v_entretien integer;
  v_total_entretien integer := 0;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for r in select * from employe where quantite > 0 order by objet_id, outil for update
  loop
    select * into o from objet_catalogue where id = r.objet_id;
    v_production := r.quantite * (coalesce(o.emploi_production, 0)
      + case when r.outil then coalesce(o.emploi_production_outil, 0) else 0 end);
    v_entretien := r.quantite * coalesce(o.emploi_entretien, 0);
    if v_production > 0 and o.emploi_materiau_id is not null then
      perform _arsenal_ajouter(o.emploi_materiau_id, v_production);
    end if;
    v_total_entretien := v_total_entretien + v_entretien;
    v_gains := v_gains || jsonb_build_object(
      'objet_id', r.objet_id, 'outil', r.outil,
      'materiau_id', o.emploi_materiau_id, 'produit', v_production, 'entretien', v_entretien);
  end loop;
  if v_total_entretien > 0 then
    update partie_etat set or_compagnie = or_compagnie - v_total_entretien where id;
  end if;
  if jsonb_array_length(v_gains) > 0 then
    perform _journal('production', 'Production des employés : entretien −' || v_total_entretien || ' Po.',
      -v_total_entretien, jsonb_build_object('gains', v_gains));
  end if;
  return v_gains;
end;
$$;

create function employes_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
  v_total_entretien integer := 0;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    if coalesce((g ->> 'produit')::integer, 0) > 0 and (g ->> 'materiau_id') is not null then
      perform _arsenal_retirer((g ->> 'materiau_id')::uuid, (g ->> 'produit')::integer);
    end if;
    v_total_entretien := v_total_entretien + coalesce((g ->> 'entretien')::integer, 0);
  end loop;
  if v_total_entretien > 0 then
    update partie_etat set or_compagnie = or_compagnie + v_total_entretien where id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Nouveaux types de journal.
-- ---------------------------------------------------------------------------
do $$
declare
  v_conname text;
begin
  select con.conname into v_conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    where rel.relname = 'partie_journal' and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%type%';
  if v_conname is not null then
    execute format('alter table partie_journal drop constraint %I', v_conname);
  end if;
end;
$$;
alter table partie_journal add constraint partie_journal_type_check
  check (type in ('achat', 'vente', 'destruction', 'fabrication', 'recuperation', 'depense', 'or',
    'annulation', 'sac_envoi', 'sac_retour', 'sertissage', 'embauche', 'congediement', 'equipement', 'production'));

-- ---------------------------------------------------------------------------
-- Droits.
-- ---------------------------------------------------------------------------
revoke all on function employe_embaucher(uuid, integer) from public;
revoke all on function employe_congedier(uuid, boolean, integer) from public;
revoke all on function employe_equiper_outil(uuid, integer) from public;
revoke all on function employes_instance() from public;
revoke all on function employes_annuler_instance(jsonb) from public;
grant execute on function employe_embaucher(uuid, integer) to authenticated;
grant execute on function employe_congedier(uuid, boolean, integer) to authenticated;
grant execute on function employe_equiper_outil(uuid, integer) to authenticated;
grant execute on function employes_instance() to authenticated;
grant execute on function employes_annuler_instance(jsonb) to authenticated;

do $$
begin
  alter publication supabase_realtime add table employe;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
