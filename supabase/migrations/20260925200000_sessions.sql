-- Sessions : parties indépendantes (voir docs/SESSIONS.md).
--
-- Contenu (catalogue, recettes, mercenaires, quêtes, budget) : session_id NULL = base de
-- départ, sinon copie propre à la session (faite au lancement). État de jeu : session_id
-- NOT NULL. Isolation par RLS via ctx_session() (session active de l'utilisateur).
-- Les fonctions serveur appartiennent au rôle fortress_fn (sans BYPASSRLS, membre de
-- authenticated) : elles héritent de l'isolation sans réécriture. TOUTE NOUVELLE FONCTION
-- touchant des tables de session doit être `alter function ... owner to fortress_fn`.
--
-- Compatible avec l'ancien client : tous les comptes existants sont rattachés à la
-- « Session test » (déjà lancée) qui reprend l'état actuel ; la base de départ est une
-- copie du contenu actuel. Aucune donnée n'est supprimée.

-- ---------------------------------------------------------------------------
-- 1. Tables de session
-- ---------------------------------------------------------------------------
create table session (
  id uuid primary key default gen_random_uuid(),
  nom text not null check (length(btrim(nom)) > 0),
  lancee_le timestamptz,
  created_at timestamptz not null default now(),
  cree_par uuid references auth.users (id) on delete set null
);
create unique index session_nom_unique on session (lower(btrim(nom)));

create table session_membre (
  session_id uuid not null references session (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

-- Session (ou contexte « base » pour l'administrateur) choisie par chaque utilisateur.
create table session_active (
  user_id uuid primary key references auth.users (id) on delete cascade,
  session_id uuid references session (id) on delete set null,
  contexte_base boolean not null default false
);

-- Sauvegarde automatique avant une remise à zéro par le MJ.
create table session_sauvegarde (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade,
  cree_le timestamptz not null default now(),
  motif text not null,
  donnees jsonb not null
);

-- Valeurs de départ de la base : or et arsenal donnés à une session au lancement.
create table base_depart (
  id boolean primary key default true check (id),
  or_compagnie integer not null default 1000 check (or_compagnie >= 0)
);
insert into base_depart default values;

create table base_depart_ligne (
  objet_id uuid primary key references objet_catalogue (id) on delete cascade,
  quantite integer not null check (quantite > 0)
);

-- ---------------------------------------------------------------------------
-- 2. Contexte de l'utilisateur (propriétaire postgres : lit les tables de session)
-- ---------------------------------------------------------------------------
create function est_membre(p_session uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select is_admin() or exists (
    select 1 from session_membre where session_id = p_session and user_id = auth.uid());
$$;

-- Session active de l'utilisateur, seulement s'il en fait partie (ou s'il est admin).
create function ctx_session()
returns uuid
language sql
stable
security definer set search_path = public
as $$
  select sa.session_id
  from session_active sa
  where sa.user_id = auth.uid()
    and not sa.contexte_base
    and sa.session_id is not null
    and (is_admin() or exists (
      select 1 from session_membre m
      where m.session_id = sa.session_id and m.user_id = sa.user_id));
$$;

-- L'administrateur édite la base de départ (contenu avec session_id NULL).
create function ctx_est_base()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select is_admin() and exists (
    select 1 from session_active where user_id = auth.uid() and contexte_base);
$$;

create function session_lancee(p_session uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select coalesce((select lancee_le is not null from session where id = p_session), false);
$$;

-- ---------------------------------------------------------------------------
-- 3. Colonne session_id sur les tables de contenu et d'état
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'categorie', 'classe', 'objet_catalogue', 'recette', 'ingredient_recette', 'mercenaire',
    'quete', 'quete_recompense', 'budget_poste',
    'partie_etat', 'partie_journal', 'atelier_fabrication', 'forge_sertissage', 'employe',
    'inventaire', 'ligne_inventaire', 'recrutement', 'entrainement_place',
    'entrainement_reglage', 'infirmerie_place', 'infirmerie_reglage', 'dortoir_reglage',
    'quete_mercenaire', 'invitation']
  loop
    execute format(
      'alter table %I add column session_id uuid references session (id) on delete cascade default ctx_session()', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Session test : reprend tout l'existant (contenu + état)
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  v_test uuid;
begin
  insert into session (nom, lancee_le) values ('Session test', now()) returning id into v_test;
  foreach t in array array[
    'categorie', 'classe', 'objet_catalogue', 'recette', 'ingredient_recette', 'mercenaire',
    'quete', 'quete_recompense', 'budget_poste',
    'partie_etat', 'partie_journal', 'atelier_fabrication', 'forge_sertissage', 'employe',
    'inventaire', 'ligne_inventaire', 'recrutement', 'entrainement_place',
    'entrainement_reglage', 'infirmerie_place', 'infirmerie_reglage', 'dortoir_reglage',
    'quete_mercenaire', 'invitation']
  loop
    execute format('update %I set session_id = $1 where session_id is null', t) using v_test;
  end loop;
  -- tous les comptes existants jouent dans la Session test
  insert into session_membre (session_id, user_id) select v_test, id from profil;
  insert into session_active (user_id, session_id) select id, v_test from profil;
end;
$$;

-- Les tables d'état exigent une session ; l'invitation aussi (défaut : session active).
alter table partie_etat alter column session_id set not null;
alter table partie_journal alter column session_id set not null;
alter table atelier_fabrication alter column session_id set not null;
alter table forge_sertissage alter column session_id set not null;
alter table employe alter column session_id set not null;
alter table inventaire alter column session_id set not null;
alter table ligne_inventaire alter column session_id set not null;
alter table recrutement alter column session_id set not null;
alter table entrainement_place alter column session_id set not null;
alter table entrainement_reglage alter column session_id set not null;
alter table infirmerie_place alter column session_id set not null;
alter table infirmerie_reglage alter column session_id set not null;
alter table dortoir_reglage alter column session_id set not null;
alter table quete_mercenaire alter column session_id set not null;
alter table invitation alter column session_id set not null;

-- ---------------------------------------------------------------------------
-- 5. Clés et unicités : désormais par session
-- ---------------------------------------------------------------------------
alter table partie_etat drop constraint partie_etat_pkey, add primary key (session_id);
alter table dortoir_reglage drop constraint dortoir_reglage_pkey, add primary key (session_id);
alter table entrainement_reglage drop constraint entrainement_reglage_pkey, add primary key (session_id);
alter table infirmerie_reglage drop constraint infirmerie_reglage_pkey, add primary key (session_id);
alter table forge_sertissage drop constraint forge_sertissage_pkey, add primary key (session_id);
alter table atelier_fabrication drop constraint atelier_fabrication_pkey, add primary key (session_id, atelier);
alter table entrainement_place drop constraint entrainement_place_pkey,
  add primary key (session_id, groupe, role, position);
alter table infirmerie_place drop constraint infirmerie_place_pkey, add primary key (session_id, position);
alter table recrutement drop constraint recrutement_lit_key, add unique (session_id, lit);

-- budget_poste : clé primaire technique (Realtime en exige une) + unicité par session.
alter table budget_poste drop constraint budget_poste_pkey;
alter table budget_poste add column id uuid not null default gen_random_uuid();
alter table budget_poste add primary key (id);
create unique index budget_poste_session_code
  on budget_poste (coalesce(session_id, '00000000-0000-0000-0000-000000000000'::uuid), code);

alter table categorie drop constraint categorie_nom_parent_key;
create unique index categorie_session_parent_nom
  on categorie (coalesce(session_id, '00000000-0000-0000-0000-000000000000'::uuid), parent_id, nom);
alter table classe drop constraint classe_nom_key;
create unique index classe_session_nom
  on classe (coalesce(session_id, '00000000-0000-0000-0000-000000000000'::uuid), nom);
alter table objet_catalogue drop constraint objet_catalogue_code_unique_key;
create unique index objet_catalogue_session_code
  on objet_catalogue (coalesce(session_id, '00000000-0000-0000-0000-000000000000'::uuid), code_unique);
alter table recette drop constraint recette_code_unique_key;
create unique index recette_session_code
  on recette (coalesce(session_id, '00000000-0000-0000-0000-000000000000'::uuid), code_unique);

drop index quete_une_seule_en_cours;
create unique index quete_une_seule_en_cours
  on quete (coalesce(session_id, '00000000-0000-0000-0000-000000000000'::uuid)) where en_cours;

-- ---------------------------------------------------------------------------
-- 6. Copie du contenu (identifiants renouvelés, liens recalculés)
--    p_src / p_dst : session, ou NULL pour la base de départ. Propriétaire postgres.
-- ---------------------------------------------------------------------------
create function _cloner_contenu(p_src uuid, p_dst uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  drop table if exists m_categorie, m_classe, m_objet, m_recette, m_mercenaire, m_quete;
  create temp table m_categorie on commit drop as
    select id as old, gen_random_uuid() as new from categorie where session_id is not distinct from p_src;
  create temp table m_classe on commit drop as
    select id as old, gen_random_uuid() as new from classe where session_id is not distinct from p_src;
  create temp table m_objet on commit drop as
    select id as old, gen_random_uuid() as new from objet_catalogue where session_id is not distinct from p_src;
  create temp table m_recette on commit drop as
    select id as old, gen_random_uuid() as new from recette where session_id is not distinct from p_src;
  create temp table m_mercenaire on commit drop as
    select id as old, gen_random_uuid() as new from mercenaire where session_id is not distinct from p_src;
  create temp table m_quete on commit drop as
    select id as old, gen_random_uuid() as new from quete where session_id is not distinct from p_src;

  insert into categorie (id, nom, actif, parent_id, session_id)
    select m.new, c.nom, c.actif, mp.new, p_dst
    from categorie c
    join m_categorie m on m.old = c.id
    left join m_categorie mp on mp.old = c.parent_id
    where c.session_id is not distinct from p_src;

  insert into classe (id, nom, actif, session_id)
    select m.new, c.nom, c.actif, p_dst
    from classe c join m_classe m on m.old = c.id
    where c.session_id is not distinct from p_src;

  insert into objet_catalogue (
    id, code_unique, nom, description, icone, empilable, utilisable, actif, categorie_id,
    veterance_requise, duree_fabrication_instances, cout_achat_or, portee, protection,
    type_armure, malus_discretion, malus_vitesse, malus_esquive, parade, allonge,
    type_degats, emploi_materiau_id, emploi_production, emploi_production_outil,
    emploi_outil_id, emploi_entretien, deux_mains, session_id)
    select m.new, o.code_unique, o.nom, o.description, o.icone, o.empilable, o.utilisable, o.actif,
      mc.new, o.veterance_requise, o.duree_fabrication_instances, o.cout_achat_or, o.portee,
      o.protection, o.type_armure, o.malus_discretion, o.malus_vitesse, o.malus_esquive,
      o.parade, o.allonge, o.type_degats, mm.new, o.emploi_production, o.emploi_production_outil,
      mo.new, o.emploi_entretien, o.deux_mains, p_dst
    from objet_catalogue o
    join m_objet m on m.old = o.id
    left join m_categorie mc on mc.old = o.categorie_id
    left join m_objet mm on mm.old = o.emploi_materiau_id
    left join m_objet mo on mo.old = o.emploi_outil_id
    where o.session_id is not distinct from p_src;

  insert into recette (id, code_unique, nom, atelier, resultat_objet_id, quantite_produite, actif, session_id)
    select m.new, r.code_unique, r.nom, r.atelier, mo.new, r.quantite_produite, r.actif, p_dst
    from recette r
    join m_recette m on m.old = r.id
    join m_objet mo on mo.old = r.resultat_objet_id
    where r.session_id is not distinct from p_src;

  insert into ingredient_recette (recette_id, objet_id, quantite_requise, session_id)
    select mr.new, mo.new, i.quantite_requise, p_dst
    from ingredient_recette i
    join m_recette mr on mr.old = i.recette_id
    join m_objet mo on mo.old = i.objet_id
    where i.session_id is not distinct from p_src;

  insert into mercenaire (
    id, nom, portrait, role, veterance, attaque, defense, esprit, mouvement, mana, sante,
    notes, actif, classe_id, session_id)
    select m.new, x.nom, x.portrait, x.role, x.veterance, x.attaque, x.defense, x.esprit,
      x.mouvement, x.mana, x.sante, x.notes, x.actif, mc.new, p_dst
    from mercenaire x
    join m_mercenaire m on m.old = x.id
    left join m_classe mc on mc.old = x.classe_id
    where x.session_id is not distinct from p_src;

  -- Les quêtes repartent « disponibles » : l'avancement fait partie de l'état de la session.
  insert into quete (
    id, nom, description, veterance_requise, icone, recompense_or, actif,
    instances_requises, session_id)
    select m.new, q.nom, q.description, q.veterance_requise, q.icone, q.recompense_or, q.actif,
      q.instances_requises, p_dst
    from quete q join m_quete m on m.old = q.id
    where q.session_id is not distinct from p_src;

  insert into quete_recompense (quete_id, position, objet_id, quantite, session_id)
    select mq.new, r.position, mo.new, r.quantite, p_dst
    from quete_recompense r
    join m_quete mq on mq.old = r.quete_id
    join m_objet mo on mo.old = r.objet_id
    where r.session_id is not distinct from p_src;

  insert into budget_poste (code, libelle, nature, montant, auto, ordre, session_id)
    select b.code, b.libelle, b.nature, b.montant, b.auto, b.ordre, p_dst
    from budget_poste b where b.session_id is not distinct from p_src;
end;
$$;

-- Base de départ = copie du contenu de la Session test ; arsenal de départ = son arsenal.
do $$
declare
  v_test uuid;
begin
  select id into v_test from session where nom = 'Session test';
  perform _cloner_contenu(v_test, null);
  insert into base_depart_ligne (objet_id, quantite)
    select ob.id, sum(l.quantite)
    from ligne_inventaire l
    join inventaire i on i.id = l.inventaire_id and i.type = 'arsenal' and i.session_id = v_test
    join objet_catalogue ot on ot.id = l.objet_id
    join objet_catalogue ob on ob.session_id is null and ob.code_unique = ot.code_unique
    where l.quantite > 0 and coalesce(array_length(l.gemmes, 1), 0) = 0
    group by ob.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Rôle propriétaire des fonctions de jeu : sans BYPASSRLS, membre de authenticated
-- ---------------------------------------------------------------------------
create role fortress_fn nologin;
grant authenticated to fortress_fn;
grant fortress_fn to postgres;
grant create on schema public to fortress_fn;

-- ---------------------------------------------------------------------------
-- 8. Sécurité (RLS) : tout est limité à la session active
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  p record;
  contenu text[] := array[
    'categorie', 'classe', 'objet_catalogue', 'recette', 'ingredient_recette', 'mercenaire',
    'quete', 'quete_recompense', 'budget_poste'];
  etat text[] := array[
    'partie_etat', 'partie_journal', 'atelier_fabrication', 'forge_sertissage', 'employe',
    'inventaire', 'ligne_inventaire', 'recrutement', 'entrainement_place',
    'entrainement_reglage', 'infirmerie_place', 'infirmerie_reglage', 'dortoir_reglage',
    'quete_mercenaire'];
begin
  foreach t in array contenu || etat loop
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on %I', p.policyname, t);
    end loop;
    execute format('alter table %I enable row level security', t);
  end loop;

  foreach t in array contenu loop
    execute format($f$create policy "%1$s: lecture" on %1$I for select to authenticated
      using ((session_id is not null and session_id = ctx_session()) or (session_id is null and ctx_est_base()))$f$, t);
    execute format($f$create policy "%1$s: ecriture admin" on %1$I for all to authenticated
      using (is_admin() and ((session_id is not null and session_id = ctx_session()) or (session_id is null and ctx_est_base())))
      with check (is_admin() and ((session_id is not null and session_id = ctx_session()) or (session_id is null and ctx_est_base())))$f$, t);
    execute format($f$create policy "%1$s: fonctions serveur" on %1$I for all to fortress_fn
      using (session_id is not null and session_id = ctx_session())
      with check (session_id is not null and session_id = ctx_session())$f$, t);
  end loop;

  foreach t in array etat loop
    execute format($f$create policy "%1$s: lecture" on %1$I for select to authenticated
      using (session_id = ctx_session())$f$, t);
    execute format($f$create policy "%1$s: ecriture admin" on %1$I for all to authenticated
      using (is_admin() and session_id = ctx_session())
      with check (is_admin() and session_id = ctx_session())$f$, t);
    execute format($f$create policy "%1$s: fonctions serveur" on %1$I for all to fortress_fn
      using (session_id = ctx_session()) with check (session_id = ctx_session())$f$, t);
  end loop;
end;
$$;

-- Recrutement : un joueur recrute pour lui-même dans sa session lancée, parmi les
-- mercenaires de cette session ; il libère les siens (l'admin tous).
create policy "recrutement: un joueur recrute pour lui-meme" on recrutement
  for insert to authenticated
  with check (
    auth.uid() = user_id and session_id = ctx_session() and session_lancee(session_id)
    and exists (select 1 from mercenaire m where m.id = mercenaire_id));
create policy "recrutement: liberation par le recruteur" on recrutement
  for delete to authenticated
  using (session_id = ctx_session() and auth.uid() = user_id);

-- Nouvelles tables
alter table session enable row level security;
alter table session_membre enable row level security;
alter table session_active enable row level security;
alter table session_sauvegarde enable row level security;
alter table base_depart enable row level security;
alter table base_depart_ligne enable row level security;

create policy "session: lecture par ses membres" on session for select to authenticated
  using (est_membre(id));
create policy "session: gestion par admin" on session for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "session_membre: lecture des siens" on session_membre for select to authenticated
  using (user_id = auth.uid() or is_admin());
create policy "session_membre: gestion par admin" on session_membre for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "session_active: lecture de la sienne" on session_active for select to authenticated
  using (user_id = auth.uid());
create policy "session_sauvegarde: admin" on session_sauvegarde for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "base_depart: admin" on base_depart for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "base_depart_ligne: admin" on base_depart_ligne for all to authenticated
  using (is_admin()) with check (is_admin());

revoke all on session, session_membre, session_active, session_sauvegarde, base_depart,
  base_depart_ligne from anon;
grant select, insert, update, delete on session, session_membre, session_active,
  session_sauvegarde, base_depart, base_depart_ligne to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Fonctions de jeu : propriétaire fortress_fn (+ garde-fou du verrou de partie)
-- ---------------------------------------------------------------------------
create or replace function _verrou_partie()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if ctx_session() is null then
    raise exception 'Aucune session active : choisissez une session.';
  end if;
  select or_compagnie into v_or from partie_etat where id for update;
  if v_or is null then
    raise exception 'Cette session n''est pas encore lancée : en attente du MJ.';
  end if;
  return v_or;
end;
$$;

do $$
declare
  f text;
  r record;
begin
  foreach f in array array[
    '_arsenal_ajouter', '_arsenal_id', '_arsenal_quantite', '_arsenal_retirer', '_journal',
    '_racine_categorie', '_refuser_si_en_quete', '_sac_dos_id', '_verrou_partie',
    'ateliers_annuler_instance', 'ateliers_instance', 'budget_annuler_instance',
    'budget_appliquer_instance', 'budget_modifier', 'dortoir_debloquer_place',
    'employe_congedier', 'employe_embaucher', 'employe_equiper_outil',
    'employes_annuler_instance', 'employes_instance', 'entrainement_annuler_instance',
    'entrainement_apres_renvoi', 'entrainement_choisir_eleve',
    'entrainement_choisir_instructeur', 'entrainement_debloquer_groupe2',
    'entrainement_debloquer_place', 'entrainement_instance', 'entrainement_renvoyer',
    'entretien_montant', 'infirmerie_annuler_instance', 'infirmerie_apres_renvoi',
    'infirmerie_debloquer_place', 'infirmerie_instance', 'infirmerie_renvoyer',
    'infirmerie_soigner', 'mercenaires_recrutes', 'partie_acheter', 'partie_annuler',
    'partie_depenser', 'partie_detruire', 'partie_fabriquer', 'partie_or_definir',
    'partie_recuperer', 'partie_vendre', 'quete_annuler_choix', 'quete_apres_renvoi',
    'quete_choisir', 'quete_engager', 'quete_retirer', 'quetes_annuler_instance',
    'quetes_instance', 'recrutement_attribuer_lit', 'sac_dos_envoyer', 'sac_dos_retirer',
    'sertissage_lancer', 'sertissage_recuperer']
  loop
    for r in select p.oid::regprocedure as sig from pg_proc p
             where p.pronamespace = 'public'::regnamespace and p.proname = f
    loop
      execute format('alter function %s owner to fortress_fn', r.sig);
    end loop;
  end loop;
end;
$$;
revoke create on schema public from fortress_fn;

-- ---------------------------------------------------------------------------
-- 10. Gestion des sessions (MJ) et invitations liées à une session
-- ---------------------------------------------------------------------------
create function session_creer(p_nom text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  insert into session (nom, cree_par) values (btrim(p_nom), auth.uid()) returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'Une session porte déjà ce nom.';
end;
$$;

create function session_renommer(p_session uuid, p_nom text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  update session set nom = btrim(p_nom) where id = p_session;
  if not found then
    raise exception 'Session introuvable.';
  end if;
exception
  when unique_violation then
    raise exception 'Une session porte déjà ce nom.';
end;
$$;

-- Choisir la session où l'on joue ; NULL = base de départ (MJ seulement).
create function session_choisir(p_session uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if p_session is null then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    insert into session_active (user_id, session_id, contexte_base)
      values (auth.uid(), null, true)
      on conflict (user_id) do update set session_id = null, contexte_base = true;
  else
    if not est_membre(p_session) then
      raise exception 'Vous ne faites pas partie de cette session.';
    end if;
    insert into session_active (user_id, session_id, contexte_base)
      values (auth.uid(), p_session, false)
      on conflict (user_id) do update set session_id = p_session, contexte_base = false;
  end if;
end;
$$;

-- Lancement (premier « +1 Instance » du MJ) : copie du contenu de la base et état de
-- départ. Ne fait avancer aucun compteur.
create function session_lancer(p_session uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_lancee timestamptz;
  v_inv uuid;
  v_or integer;
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  select lancee_le into v_lancee from session where id = p_session for update;
  if not found then
    raise exception 'Session introuvable.';
  end if;
  if v_lancee is not null then
    raise exception 'Cette session est déjà lancée.';
  end if;
  perform _cloner_contenu(null, p_session);
  select or_compagnie into v_or from base_depart where id;
  insert into partie_etat (session_id, or_compagnie) values (p_session, coalesce(v_or, 1000));
  insert into dortoir_reglage (session_id) values (p_session);
  insert into entrainement_reglage (session_id) values (p_session);
  insert into infirmerie_reglage (session_id) values (p_session);
  insert into forge_sertissage (session_id) values (p_session);
  insert into inventaire (type, nom, session_id) values ('arsenal', 'Arsenal', p_session)
    returning id into v_inv;
  insert into ligne_inventaire (inventaire_id, objet_id, quantite, session_id)
    select v_inv, os.id, d.quantite, p_session
    from base_depart_ligne d
    join objet_catalogue ob on ob.id = d.objet_id and ob.session_id is null
    join objet_catalogue os on os.session_id = p_session and os.code_unique = ob.code_unique;
  update session set lancee_le = now() where id = p_session;
  return jsonb_build_object('session_id', p_session, 'or', coalesce(v_or, 1000));
end;
$$;

-- Remise à zéro par le MJ : sauvegarde automatique, puis la session redevient « non lancée ».
create function session_reinitialiser(p_session uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  t text;
  v_donnees jsonb := '{}'::jsonb;
  v_table jsonb;
  v_ordre text[] := array[
    'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
    'ligne_inventaire', 'inventaire', 'atelier_fabrication', 'forge_sertissage', 'employe',
    'partie_journal', 'partie_etat', 'dortoir_reglage', 'entrainement_reglage',
    'infirmerie_reglage', 'quete_recompense', 'quete', 'ingredient_recette', 'recette',
    'mercenaire', 'objet_catalogue', 'categorie', 'classe', 'budget_poste'];
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

-- Invitations : le code est lié à une session (défaut : session active du MJ).
create or replace function verifier_invitation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_code text := normaliser_invitation(new.raw_user_meta_data ->> 'invitation');
  v_session uuid;
begin
  update invitation
     set utilise_par = new.id, utilise_le = now()
   where code = v_code and utilise_par is null
   returning session_id into v_session;
  if not found then
    raise exception 'Invitation invalide ou deja utilisee';
  end if;
  insert into session_membre (session_id, user_id) values (v_session, new.id)
    on conflict do nothing;
  insert into session_active (user_id, session_id) values (new.id, v_session)
    on conflict (user_id) do update set session_id = excluded.session_id, contexte_base = false;
  return new;
end;
$$;

-- Compte existant : rejoindre une session avec un nouveau code.
create function session_rejoindre(p_code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_session uuid;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  update invitation
     set utilise_par = auth.uid(), utilise_le = now()
   where code = normaliser_invitation(p_code) and utilise_par is null
   returning session_id into v_session;
  if not found then
    raise exception 'Invitation invalide ou déjà utilisée.';
  end if;
  insert into session_membre (session_id, user_id) values (v_session, auth.uid())
    on conflict do nothing;
  insert into session_active (user_id, session_id, contexte_base) values (auth.uid(), v_session, false)
    on conflict (user_id) do update set session_id = v_session, contexte_base = false;
  return v_session;
end;
$$;

revoke all on function est_membre(uuid), ctx_session(), ctx_est_base(), session_lancee(uuid),
  _cloner_contenu(uuid, uuid), session_creer(text), session_renommer(uuid, text),
  session_choisir(uuid), session_lancer(uuid), session_reinitialiser(uuid),
  session_rejoindre(text) from public;
grant execute on function est_membre(uuid), ctx_session(), ctx_est_base(), session_lancee(uuid),
  session_creer(text), session_renommer(uuid, text), session_choisir(uuid),
  session_lancer(uuid), session_reinitialiser(uuid), session_rejoindre(text)
  to authenticated, fortress_fn;
