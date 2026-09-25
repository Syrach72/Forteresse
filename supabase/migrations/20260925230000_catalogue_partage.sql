-- CATALOGUE PARTAGÉ entre toutes les sessions (décision de Bruno, 2026-09-25).
--
-- Jusqu'ici chaque session avait sa propre COPIE du catalogue (20260925200000). Désormais un seul
-- catalogue (catégories, classes, objets, recettes, mercenaires, quêtes) sert toutes les sessions :
-- ce que le MJ crée ou modifie est visible partout, tout de suite. Ce qui évolue EN JEU reste propre
-- à chaque session :
--   * la vétérance d'un mercenaire   -> table mercenaire_etat (repli : vétérance du catalogue) ;
--   * l'état d'une quête (choisie, accomplie, instances restantes) -> table quete_etat ;
--   * le budget (postes de recettes/dépenses) reste copié par session au lancement ;
--   * or, arsenal, recrutements, lits, ateliers, journal, etc. (déjà par session).
-- Le contenu de la « Session test » (que le MJ éditait) est FUSIONNÉ avec la base : union des deux,
-- en cas de conflit la valeur de la Session test l'emporte si elle est renseignée. Les identifiants
-- de la Session test sont remplacés par ceux du catalogue partagé dans tout son état (arsenal,
-- recrutements, quêtes, journal…). Rien n'est perdu.
-- Suppression : _cloner_contenu, session_envoyer, _env_* (plus de copie de contenu).

-- ---------------------------------------------------------------------------
-- 1. État par session de ce qui évolue en jeu
-- ---------------------------------------------------------------------------
create table mercenaire_etat (
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  veterance integer not null check (veterance >= 0),
  primary key (session_id, mercenaire_id)
);
create table quete_etat (
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  quete_id uuid not null references quete (id) on delete cascade,
  en_cours boolean not null default false,
  terminee_le timestamptz,
  instances_restantes smallint check (instances_restantes is null or instances_restantes >= 0),
  primary key (session_id, quete_id)
);
create unique index quete_etat_une_seule_en_cours on quete_etat (session_id) where en_cours;

-- ---------------------------------------------------------------------------
-- 2. Fusion de la Session test dans le catalogue partagé
-- ---------------------------------------------------------------------------
do $$
declare
  v_test uuid;
  v_autres integer;
  r record;
begin
  select id into v_test from session where nom = 'Session test';
  if v_test is null then
    raise exception 'Session test introuvable';
  end if;
  select count(*) into v_autres from (
    select session_id from objet_catalogue where session_id is not null and session_id <> v_test
    union all select session_id from mercenaire where session_id is not null and session_id <> v_test
    union all select session_id from categorie where session_id is not null and session_id <> v_test
    union all select session_id from quete where session_id is not null and session_id <> v_test) x;
  if v_autres > 0 then
    raise exception 'Une autre session que la Session test a son propre contenu : fusion manuelle nécessaire';
  end if;

  create temp table mp_categorie (old uuid primary key, new uuid not null) on commit drop;
  create temp table mp_classe (old uuid primary key, new uuid not null) on commit drop;
  create temp table mp_objet (old uuid primary key, new uuid not null) on commit drop;
  create temp table mp_recette (old uuid primary key, new uuid not null) on commit drop;
  create temp table mp_mercenaire (old uuid primary key, new uuid not null) on commit drop;
  create temp table mp_quete (old uuid primary key, new uuid not null) on commit drop;

  -- Catégories : correspondance par chemin (Armes > Armes courantes…) ; les autres sont promues.
  with recursive t as (
      select id, parent_id, nom::text as chemin from categorie where session_id = v_test and parent_id is null
      union all
      select c.id, c.parent_id, t.chemin || ' > ' || c.nom from categorie c join t on c.parent_id = t.id where c.session_id = v_test),
    b as (
      select id, parent_id, nom::text as chemin from categorie where session_id is null and parent_id is null
      union all
      select c.id, c.parent_id, b.chemin || ' > ' || c.nom from categorie c join b on c.parent_id = b.id where c.session_id is null)
  insert into mp_categorie select t.id, b.id from t join b on b.chemin = t.chemin;
  for r in
    with recursive t as (
      select id, parent_id, 0 as prof from categorie where session_id = v_test and parent_id is null
      union all
      select c.id, c.parent_id, t.prof + 1 from categorie c join t on c.parent_id = t.id where c.session_id = v_test)
    select t.id, t.parent_id from t where t.id not in (select old from mp_categorie) order by t.prof
  loop
    update categorie set session_id = null,
      parent_id = (select new from mp_categorie where old = r.parent_id)
      where id = r.id;
    insert into mp_categorie values (r.id, r.id);
  end loop;

  -- Classes (par nom)
  insert into mp_classe select t.id, b.id from classe t
    join classe b on b.session_id is null and b.nom = t.nom where t.session_id = v_test;
  for r in select id from classe where session_id = v_test and id not in (select old from mp_classe) loop
    update classe set session_id = null where id = r.id;
    insert into mp_classe values (r.id, r.id);
  end loop;

  -- Objets (par code)
  insert into mp_objet select t.id, b.id from objet_catalogue t
    join objet_catalogue b on b.session_id is null and b.code_unique = t.code_unique where t.session_id = v_test;
  for r in select id from objet_catalogue where session_id = v_test and id not in (select old from mp_objet) loop
    update objet_catalogue set session_id = null where id = r.id;
    insert into mp_objet values (r.id, r.id);
  end loop;
  -- objets promus : liens vers le catalogue partagé
  update objet_catalogue o set
    categorie_id = coalesce((select new from mp_categorie where old = o.categorie_id), o.categorie_id),
    emploi_materiau_id = coalesce((select new from mp_objet where old = o.emploi_materiau_id), o.emploi_materiau_id),
    emploi_outil_id = coalesce((select new from mp_objet where old = o.emploi_outil_id), o.emploi_outil_id)
    where o.session_id is null and o.id in (select old from mp_objet where old = new);
  -- objets présents des deux côtés : union (la Session test l'emporte quand elle renseigne une valeur)
  update objet_catalogue b set
    nom = t.nom,
    description = coalesce(t.description, b.description),
    icone = coalesce(t.icone, b.icone),
    empilable = t.empilable, utilisable = t.utilisable, actif = t.actif,
    categorie_id = coalesce((select new from mp_categorie where old = t.categorie_id), b.categorie_id),
    veterance_requise = coalesce(t.veterance_requise, b.veterance_requise),
    duree_fabrication_instances = coalesce(t.duree_fabrication_instances, b.duree_fabrication_instances),
    cout_achat_or = coalesce(t.cout_achat_or, b.cout_achat_or),
    portee = coalesce(t.portee, b.portee),
    protection = coalesce(t.protection, b.protection),
    type_armure = coalesce(t.type_armure, b.type_armure),
    malus_discretion = coalesce(t.malus_discretion, b.malus_discretion),
    malus_vitesse = coalesce(t.malus_vitesse, b.malus_vitesse),
    malus_esquive = coalesce(t.malus_esquive, b.malus_esquive),
    parade = coalesce(t.parade, b.parade),
    allonge = coalesce(t.allonge, b.allonge),
    type_degats = coalesce(t.type_degats, b.type_degats),
    emploi_materiau_id = coalesce((select new from mp_objet where old = t.emploi_materiau_id), b.emploi_materiau_id),
    emploi_production = coalesce(t.emploi_production, b.emploi_production),
    emploi_production_outil = coalesce(t.emploi_production_outil, b.emploi_production_outil),
    emploi_outil_id = coalesce((select new from mp_objet where old = t.emploi_outil_id), b.emploi_outil_id),
    emploi_entretien = coalesce(t.emploi_entretien, b.emploi_entretien),
    deux_mains = t.deux_mains, legere = t.legere
  from objet_catalogue t join mp_objet m on m.old = t.id
  where b.id = m.new and m.old <> m.new and t.session_id = v_test;

  -- Recettes (par code) et leurs ingrédients
  insert into mp_recette select t.id, b.id from recette t
    join recette b on b.session_id is null and b.code_unique = t.code_unique where t.session_id = v_test;
  for r in select id from recette where session_id = v_test and id not in (select old from mp_recette) loop
    update recette set session_id = null,
      resultat_objet_id = (select new from mp_objet where old = resultat_objet_id)
      where id = r.id;
    insert into mp_recette values (r.id, r.id);
  end loop;
  update ingredient_recette i set session_id = null,
    objet_id = (select new from mp_objet where old = i.objet_id)
    where i.session_id = v_test and i.recette_id in (select old from mp_recette where old = new);
  update recette b set nom = t.nom, atelier = t.atelier,
    resultat_objet_id = (select new from mp_objet where old = t.resultat_objet_id),
    quantite_produite = t.quantite_produite, actif = t.actif
  from recette t join mp_recette m on m.old = t.id
  where b.id = m.new and m.old <> m.new and t.session_id = v_test;
  delete from ingredient_recette where recette_id in (select new from mp_recette where old <> new);
  insert into ingredient_recette (recette_id, objet_id, quantite_requise, session_id)
    select m.new, mo.new, i.quantite_requise, null
    from ingredient_recette i
    join mp_recette m on m.old = i.recette_id and m.old <> m.new
    join mp_objet mo on mo.old = i.objet_id
    where i.session_id = v_test;

  -- Mercenaires (par nom) : la fiche est partagée, la vétérance actuelle devient l'état de la Session test
  insert into mp_mercenaire select t.id, b.id from mercenaire t
    join mercenaire b on b.session_id is null and b.nom = t.nom where t.session_id = v_test;
  for r in select id from mercenaire where session_id = v_test and id not in (select old from mp_mercenaire) loop
    update mercenaire set session_id = null,
      classe_id = coalesce((select new from mp_classe where old = classe_id), classe_id)
      where id = r.id;
    insert into mp_mercenaire values (r.id, r.id);
  end loop;
  update mercenaire b set
    nom = t.nom, portrait = coalesce(t.portrait, b.portrait), role = coalesce(t.role, b.role),
    attaque = coalesce(t.attaque, b.attaque), defense = coalesce(t.defense, b.defense),
    esprit = coalesce(t.esprit, b.esprit), mouvement = coalesce(t.mouvement, b.mouvement),
    mana = coalesce(t.mana, b.mana), sante = coalesce(t.sante, b.sante),
    notes = coalesce(t.notes, b.notes), actif = t.actif,
    classe_id = coalesce((select new from mp_classe where old = t.classe_id), b.classe_id)
  from mercenaire t join mp_mercenaire m on m.old = t.id
  where b.id = m.new and m.old <> m.new and t.session_id = v_test;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    select v_test, m.new, coalesce(t.veterance, 0)
    from mercenaire t join mp_mercenaire m on m.old = t.id
    where t.session_id = v_test or m.old = m.new
    on conflict do nothing;

  -- Quêtes (par nom) : contenu partagé, avancement = état de la Session test
  insert into mp_quete select t.id, b.id from quete t
    join quete b on b.session_id is null and b.nom = t.nom where t.session_id = v_test;
  for r in select id from quete where session_id = v_test and id not in (select old from mp_quete) loop
    update quete set session_id = null where id = r.id;
    insert into mp_quete values (r.id, r.id);
  end loop;
  insert into quete_etat (session_id, quete_id, en_cours, terminee_le, instances_restantes)
    select v_test, m.new, q.en_cours, q.terminee_le, q.instances_restantes
    from quete q join mp_quete m on m.old = q.id
    where q.en_cours or q.terminee_le is not null or q.instances_restantes is not null;
  update quete b set
    description = case when t.description <> '' then t.description else b.description end,
    veterance_requise = t.veterance_requise, icone = coalesce(t.icone, b.icone),
    recompense_or = t.recompense_or, actif = t.actif, instances_requises = t.instances_requises
  from quete t join mp_quete m on m.old = t.id
  where b.id = m.new and m.old <> m.new and t.session_id = v_test;
  update quete_recompense qr set session_id = null,
    objet_id = (select new from mp_objet where old = qr.objet_id)
    where qr.session_id = v_test and qr.quete_id in (select old from mp_quete where old = new);
  delete from quete_recompense where quete_id in (select new from mp_quete where old <> new);
  insert into quete_recompense (quete_id, position, objet_id, quantite, session_id)
    select m.new, qr.position, mo.new, qr.quantite, null
    from quete_recompense qr
    join mp_quete m on m.old = qr.quete_id and m.old <> m.new
    join mp_objet mo on mo.old = qr.objet_id
    where qr.session_id = v_test;

  -- État de la Session test : identifiants du catalogue partagé
  update ligne_inventaire l set objet_id = m.new from mp_objet m
    where l.objet_id = m.old and m.old <> m.new and l.session_id = v_test;
  update ligne_inventaire l set gemmes = (
      select array_agg(coalesce((select new from mp_objet where old = g), g) order by ord)
      from unnest(l.gemmes) with ordinality as u(g, ord))
    where l.session_id = v_test and l.gemmes is not null and array_length(l.gemmes, 1) > 0;
  update atelier_fabrication a set objet_id = m.new from mp_objet m
    where a.objet_id = m.old and m.old <> m.new and a.session_id = v_test;
  update employe e set objet_id = m.new from mp_objet m
    where e.objet_id = m.old and m.old <> m.new and e.session_id = v_test;
  update forge_sertissage f set
    arme_objet_id = coalesce((select new from mp_objet where old = f.arme_objet_id), f.arme_objet_id),
    gemme_objet_id = coalesce((select new from mp_objet where old = f.gemme_objet_id), f.gemme_objet_id),
    arme_gemmes = coalesce((
      select array_agg(coalesce((select new from mp_objet where old = g), g) order by ord)
      from unnest(f.arme_gemmes) with ordinality as u(g, ord)), f.arme_gemmes)
    where f.session_id = v_test;
  update recrutement x set mercenaire_id = m.new from mp_mercenaire m
    where x.mercenaire_id = m.old and m.old <> m.new and x.session_id = v_test;
  update entrainement_place x set mercenaire_id = m.new from mp_mercenaire m
    where x.mercenaire_id = m.old and m.old <> m.new and x.session_id = v_test;
  update infirmerie_place x set mercenaire_id = m.new from mp_mercenaire m
    where x.mercenaire_id = m.old and m.old <> m.new and x.session_id = v_test;
  update quete_mercenaire x set mercenaire_id = m.new from mp_mercenaire m
    where x.mercenaire_id = m.old and m.old <> m.new and x.session_id = v_test;
  update quete_mercenaire x set quete_id = m.new from mp_quete m
    where x.quete_id = m.old and m.old <> m.new and x.session_id = v_test;
  update inventaire x set mercenaire_id = m.new from mp_mercenaire m
    where x.mercenaire_id = m.old and m.old <> m.new and x.session_id = v_test;
  -- journal (détails JSON : identifiants d'objets et de mercenaires pour les annulations)
  for r in select old, new from mp_objet where old <> new loop
    update partie_journal set details = replace(details::text, r.old::text, r.new::text)::jsonb
      where session_id = v_test and details is not null and details::text like '%' || r.old::text || '%';
  end loop;
  for r in select old, new from mp_mercenaire where old <> new loop
    update partie_journal set details = replace(details::text, r.old::text, r.new::text)::jsonb
      where session_id = v_test and details is not null and details::text like '%' || r.old::text || '%';
  end loop;

  -- La copie de la Session test n'a plus lieu d'être
  delete from quete_recompense where session_id = v_test;
  delete from quete where session_id = v_test;
  delete from ingredient_recette where session_id = v_test;
  delete from recette where session_id = v_test;
  delete from mercenaire where session_id = v_test;
  delete from objet_catalogue where session_id = v_test;
  delete from categorie where session_id = v_test;
  delete from classe where session_id = v_test;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2b. Un même mercenaire / objet du catalogue peut servir dans plusieurs sessions : les unicités
--     des tables d'état (une ligne par mercenaire, par objet employé…) deviennent « par session ».
-- ---------------------------------------------------------------------------
create function pg_temp._unique_par_session(p_table text, p_cols text[], p_nouvelle text[], p_pk boolean)
returns void
language plpgsql
as $f$
declare
  c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    where con.conrelid = ('public.' || p_table)::regclass
      and con.contype in ('p', 'u')
      and (select array_agg(a.attname::text order by a.attname::text)
             from unnest(con.conkey) k join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k)
          = (select array_agg(x order by x) from unnest(p_cols) x)
  loop
    execute format('alter table %I drop constraint %I', p_table, c.conname);
  end loop;
  execute format('alter table %I add %s (%s)', p_table,
    case when p_pk then 'primary key' else 'unique' end, array_to_string(p_nouvelle, ', '));
end;
$f$;
select pg_temp._unique_par_session('recrutement', array['mercenaire_id'], array['session_id', 'mercenaire_id'], true);
select pg_temp._unique_par_session('entrainement_place', array['mercenaire_id'], array['session_id', 'mercenaire_id'], false);
select pg_temp._unique_par_session('infirmerie_place', array['mercenaire_id'], array['session_id', 'mercenaire_id'], false);
select pg_temp._unique_par_session('quete_mercenaire', array['mercenaire_id'], array['session_id', 'mercenaire_id'], false);
select pg_temp._unique_par_session('quete_mercenaire', array['position', 'quete_id'],
  array['session_id', 'quete_id', 'position'], true);
select pg_temp._unique_par_session('employe', array['objet_id', 'outil'], array['session_id', 'objet_id', 'outil'], false);
-- les fonctions d'embauche/collecte utilisent « on conflict (objet_id, outil) »
do $$
declare
  r record;
  d text;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prosrc like '%on conflict (objet_id, outil)%'
  loop
    d := replace(pg_get_functiondef(r.sig), 'on conflict (objet_id, outil)', 'on conflict (session_id, objet_id, outil)');
    execute d;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Le contenu n'a plus de session : colonnes, unicités, règles de sécurité
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  p record;
begin
  foreach t in array array['categorie', 'classe', 'objet_catalogue', 'recette', 'ingredient_recette',
                           'mercenaire', 'quete', 'quete_recompense'] loop
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on %I', p.policyname, t);
    end loop;
  end loop;
end;
$$;
drop index if exists quete_une_seule_en_cours;
drop index if exists categorie_session_parent_nom;
drop index if exists classe_session_nom;
drop index if exists objet_catalogue_session_code;
drop index if exists recette_session_code;
alter table quete drop column en_cours, drop column terminee_le, drop column instances_restantes;
alter table categorie drop column session_id;
alter table classe drop column session_id;
alter table objet_catalogue drop column session_id;
alter table recette drop column session_id;
alter table ingredient_recette drop column session_id;
alter table mercenaire drop column session_id;
alter table quete drop column session_id;
alter table quete_recompense drop column session_id;
alter table categorie add constraint categorie_nom_parent_key unique (parent_id, nom);
alter table classe add constraint classe_nom_key unique (nom);
alter table objet_catalogue add constraint objet_catalogue_code_unique_key unique (code_unique);
alter table recette add constraint recette_code_unique_key unique (code_unique);

do $$
declare
  t text;
begin
  foreach t in array array['categorie', 'classe', 'objet_catalogue', 'recette', 'ingredient_recette',
                           'mercenaire', 'quete', 'quete_recompense'] loop
    execute format('alter table %I enable row level security', t);
    execute format($f$create policy "%1$s: lecture" on %1$I for select to authenticated using (true)$f$, t);
    execute format($f$create policy "%1$s: ecriture admin" on %1$I for all to authenticated
      using (is_admin()) with check (is_admin())$f$, t);
  end loop;
  -- état par session
  foreach t in array array['mercenaire_etat', 'quete_etat'] loop
    execute format('alter table %I enable row level security', t);
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
grant select, insert, update, delete on mercenaire_etat, quete_etat to authenticated;
revoke all on mercenaire_etat, quete_etat from anon;

-- La rubrique « Objet divers » existe déjà : ses objets peuvent être FABRIQUÉS (recette, coût,
-- durée) à la forge OU à l'armurerie (bouton « Catalogue des objets » de ces deux pages). Les
-- sous-catégories « Objets » d'Armes / Armures, créées la veille, n'ont plus lieu d'être : leurs
-- objets éventuels rejoignent « Objet divers ».
update objet_catalogue set categorie_id = (
    select id from categorie where parent_id is null and lower(btrim(nom)) = 'objet divers' limit 1)
  where categorie_id in (select id from categorie where parent_id is not null and lower(btrim(nom)) = 'objets')
    and exists (select 1 from categorie where parent_id is null and lower(btrim(nom)) = 'objet divers');
delete from categorie where parent_id is not null and lower(btrim(nom)) = 'objets'
  and not exists (select 1 from objet_catalogue where categorie_id = categorie.id);

-- ---------------------------------------------------------------------------
-- 4. Fonctions : vétérance et quêtes par session
-- ---------------------------------------------------------------------------
create function _vet(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.veterance from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.veterance from mercenaire m where m.id = p_mercenaire),
    0);
$$;
revoke all on function _vet(uuid) from public;
grant execute on function _vet(uuid) to authenticated, fortress_fn;

create or replace function entretien_montant()
returns integer
language sql
stable
security definer set search_path = public
as $$
  select (coalesce(sum(_vet(r.mercenaire_id)), 0) * 10)::integer from recrutement r;
$$;

create or replace function entrainement_choisir_eleve(p_position integer, p_mercenaire uuid, p_groupe integer default 1)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_instr mercenaire%rowtype;
  v_eleve mercenaire%rowtype;
  v_places integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if p_groupe not in (1, 2) then
    raise exception 'Groupe d''instruction inconnu.';
  end if;
  if not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recrute par vous.';
  end if;
  select m.* into v_instr
    from entrainement_place p join mercenaire m on m.id = p.mercenaire_id
    where p.role = 'instructeur' and p.groupe = p_groupe;
  if not found then
    raise exception 'Choisissez d''abord un instructeur.';
  end if;
  select case p_groupe when 1 then places_eleves else places_eleves_2 end
    into v_places from entrainement_reglage;
  if p_position is null or p_position < 0 or p_position >= v_places then
    raise exception 'Cette place eleve n''est pas debloquee.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est deja a l''entrainement.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est a l''infirmerie.';
  end if;
  select * into v_eleve from mercenaire where id = p_mercenaire;
  if v_eleve.classe_id is distinct from v_instr.classe_id then
    raise exception 'L''eleve doit etre de la meme classe que l''instructeur.';
  end if;
  if _vet(v_instr.id) - _vet(v_eleve.id) < 3 then
    raise exception 'L''instructeur doit avoir au moins 3 points de veterance de plus que l''eleve.';
  end if;
  insert into entrainement_place (groupe, role, position, mercenaire_id)
    values (p_groupe, 'eleve', p_position, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Cette place vient d''etre prise.';
end;
$$;

create or replace function entrainement_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_instr uuid;
  v_vinstr integer;
  v_g integer;
  r record;
  v_avant integer;
  v_apres integer;
  v_gradue boolean;
  v_gains jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for v_g in 1..2 loop
    select p.mercenaire_id into v_instr
      from entrainement_place p where p.role = 'instructeur' and p.groupe = v_g;
    if not found then
      continue;
    end if;
    v_vinstr := _vet(v_instr);
    for r in
      select p.position, p.mercenaire_id as mid, _vet(p.mercenaire_id) as vet
      from entrainement_place p
      where p.role = 'eleve' and p.groupe = v_g
      order by p.position
      for update of p
    loop
      v_avant := r.vet;
      if v_avant >= v_vinstr then
        v_apres := v_avant;
        v_gradue := true;
      else
        v_apres := v_avant + 1;
        insert into mercenaire_etat (session_id, mercenaire_id, veterance)
          values (ctx_session(), r.mid, v_apres)
          on conflict (session_id, mercenaire_id) do update set veterance = excluded.veterance;
        v_gradue := v_apres >= v_vinstr;
      end if;
      if v_gradue then
        delete from entrainement_place where mercenaire_id = r.mid;
      end if;
      v_gains := v_gains || jsonb_build_object(
        'mercenaire_id', r.mid, 'groupe', v_g, 'position', r.position,
        'de', v_avant, 'a', v_apres, 'gradue', v_gradue);
    end loop;
  end loop;
  return v_gains;
end;
$$;

create or replace function entrainement_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
  v_id uuid;
  v_g integer;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    v_id := (g ->> 'mercenaire_id')::uuid;
    v_g := coalesce((g ->> 'groupe')::integer, 1);
    if (g ->> 'de')::integer <> (g ->> 'a')::integer then
      update mercenaire_etat
        set veterance = (g ->> 'de')::integer
        where mercenaire_id = v_id and veterance = (g ->> 'a')::integer;
    end if;
    if (g ->> 'gradue')::boolean
       and exists (select 1 from entrainement_place where role = 'instructeur' and groupe = v_g)
       and not exists (select 1 from entrainement_place where mercenaire_id = v_id)
       and not exists (
         select 1 from entrainement_place
         where role = 'eleve' and groupe = v_g and position = (g ->> 'position')::integer)
    then
      insert into entrainement_place (groupe, role, position, mercenaire_id)
        values (v_g, 'eleve', (g ->> 'position')::integer, v_id);
    end if;
  end loop;
end;
$$;

-- Quêtes : l'état (choisie / accomplie / instances restantes) est propre à la session.
create or replace function quete_choisir(p_quete uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  if exists (select 1 from quete_etat where en_cours) then
    raise exception 'Une quête est déjà en cours : annulez-la d''abord.';
  end if;
  if not exists (select 1 from quete where id = p_quete and actif)
     or exists (select 1 from quete_etat where quete_id = p_quete and terminee_le is not null) then
    raise exception 'Cette quête n''est pas disponible.';
  end if;
  insert into quete_etat (quete_id, en_cours, instances_restantes)
    select id, true, instances_requises from quete where id = p_quete
    on conflict (session_id, quete_id)
    do update set en_cours = true, instances_restantes = excluded.instances_restantes;
end;
$$;

create or replace function quete_annuler_choix()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  perform _verrou_partie();
  select quete_id into v_id from quete_etat where en_cours;
  if v_id is null then
    return;
  end if;
  delete from quete_mercenaire where quete_id = v_id;
  update quete_etat set en_cours = false, instances_restantes = null where quete_id = v_id;
end;
$$;

create or replace function quete_engager(p_position integer, p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_quete uuid;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  perform _verrou_partie();
  select quete_id into v_quete from quete_etat where en_cours;
  if v_quete is null then
    raise exception 'Choisissez d''abord la quête.';
  end if;
  if p_position is null or p_position < 0 or p_position > 5 then
    raise exception 'Cet emplacement n''existe pas.';
  end if;
  if not exists (select 1 from recrutement where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire n''est pas au dortoir.';
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recruté par vous.';
  end if;
  if exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est déjà engagé dans une quête.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est à l''entraînement : renvoyez-le d''abord au dortoir.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est à l''infirmerie.';
  end if;
  insert into quete_mercenaire (quete_id, position, mercenaire_id)
    values (v_quete, p_position, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Cet emplacement vient d''être pris.';
end;
$$;

create or replace function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  e quete_etat%rowtype;
  r record;
  v_avant integer;
  v_apres integer;
  v_items jsonb := '[]'::jsonb;
  v_mercs jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select * into e from quete_etat where en_cours for update;
  if not found then
    return null;
  end if;
  select * into q from quete where id = e.quete_id;
  v_avant := coalesce(e.instances_restantes, q.instances_requises);
  v_apres := greatest(v_avant - 1, 0);
  if v_apres > 0 then
    update quete_etat set instances_restantes = v_apres where quete_id = q.id;
    return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
      'avant', v_avant, 'apres', v_apres, 'termine', false);
  end if;
  if q.recompense_or > 0 then
    update partie_etat set or_compagnie = or_compagnie + q.recompense_or where id;
  end if;
  for r in select objet_id, quantite from quete_recompense where quete_id = q.id order by position
  loop
    perform _arsenal_ajouter(r.objet_id, r.quantite);
    v_items := v_items || jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite);
  end loop;
  for r in select position, mercenaire_id from quete_mercenaire where quete_id = q.id order by position
  loop
    v_mercs := v_mercs || jsonb_build_object('mercenaire_id', r.mercenaire_id, 'position', r.position);
  end loop;
  delete from quete_mercenaire where quete_id = q.id;
  update quete_etat
    set en_cours = false, terminee_le = now(), instances_restantes = 0
    where quete_id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : +' || q.recompense_or || ' Po, ' || jsonb_array_length(v_items) || ' objet(s) rejoignent l''arsenal.',
    q.recompense_or, jsonb_build_object('quete_id', q.id, 'items', v_items));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs);
end;
$$;

create or replace function quetes_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  i jsonb;
  v_quete uuid;
  v_merc uuid;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_gains is null then
    return;
  end if;
  perform _verrou_partie();
  v_quete := (p_gains ->> 'quete_id')::uuid;
  if not coalesce((p_gains ->> 'termine')::boolean, true) then
    update quete_etat
      set instances_restantes = (p_gains ->> 'avant')::integer
      where quete_id = v_quete and en_cours
        and instances_restantes = (p_gains ->> 'apres')::integer;
    return;
  end if;
  if exists (select 1 from quete_etat where en_cours and quete_id <> v_quete) then
    raise exception 'Une autre quête est en cours : impossible de rouvrir celle-ci.';
  end if;
  if coalesce((p_gains ->> 'or')::integer, 0) > 0 then
    update partie_etat set or_compagnie = or_compagnie - (p_gains ->> 'or')::integer where id;
  end if;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'items', '[]'::jsonb))
  loop
    perform _arsenal_retirer((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
  end loop;
  update quete_etat
    set en_cours = true, terminee_le = null,
        instances_restantes = greatest(coalesce((p_gains ->> 'avant')::integer, 1), 1)
    where quete_id = v_quete;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'mercenaires', '[]'::jsonb))
  loop
    v_merc := (i ->> 'mercenaire_id')::uuid;
    if exists (select 1 from recrutement where mercenaire_id = v_merc)
       and not exists (select 1 from quete_mercenaire where mercenaire_id = v_merc)
       and not exists (select 1 from entrainement_place where mercenaire_id = v_merc)
       and not exists (select 1 from infirmerie_place where mercenaire_id = v_merc)
       and not exists (
         select 1 from quete_mercenaire
         where quete_id = v_quete and position = (i ->> 'position')::integer)
    then
      insert into quete_mercenaire (quete_id, position, mercenaire_id)
        values (v_quete, (i ->> 'position')::integer, v_merc);
    end if;
  end loop;
  perform _journal('annulation', 'Quête accomplie annulée (+1 Instance annulé).',
    -coalesce((p_gains ->> 'or')::integer, 0), jsonb_build_object('annule_quete', p_gains ->> 'quete_id'));
end;
$$;

-- Fabrication : les objets de la rubrique « Objet divers » se fabriquent à la forge OU à l'armurerie
-- (atelier choisi par le joueur) ; les autres suivent l'atelier de leur recette.
drop function partie_fabriquer(uuid);
create function partie_fabriquer(p_objet uuid, p_atelier text default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
  rec recette%rowtype;
  i record;
  v_route text;
  v_duree integer;
  v_quantite integer;
  v_message text;
  v_jid uuid;
  v_file boolean;
  v_ingredients jsonb;
begin
  perform _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  select * into rec from recette
    where resultat_objet_id = p_objet and coalesce(actif, true)
    order by code_unique limit 1;
  if o.id is null or rec.id is null then
    raise exception 'Cette recette n''existe pas.';
  end if;
  if not exists (select 1 from ingredient_recette where recette_id = rec.id) then
    raise exception 'Cette recette n''a pas encore d''ingrédients définis.';
  end if;
  v_route := case rec.atelier::text when 'magie' then 'mage' else rec.atelier::text end;
  if lower(coalesce(_racine_categorie(o.categorie_id), '')) = 'objet divers' then
    if p_atelier is null or p_atelier not in ('forge', 'armurerie') then
      raise exception 'Choisissez la forge ou l''armurerie pour fabriquer cet objet.';
    end if;
    v_route := p_atelier;
  end if;
  v_duree := coalesce(o.duree_fabrication_instances, 0);
  v_file := v_duree > 0;
  if v_file and exists (select 1 from atelier_fabrication where atelier = v_route) then
    raise exception 'Une fabrication est déjà en cours dans cet atelier.';
  end if;
  for i in select objet_id, quantite_requise from ingredient_recette where recette_id = rec.id
  loop
    if _arsenal_quantite(i.objet_id) < i.quantite_requise then
      raise exception 'Ressources insuffisantes pour cette fabrication.';
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('objet_id', objet_id, 'quantite', quantite_requise)), '[]'::jsonb)
    into v_ingredients from ingredient_recette where recette_id = rec.id;
  for i in select objet_id, quantite_requise from ingredient_recette where recette_id = rec.id
  loop
    perform _arsenal_retirer(i.objet_id, i.quantite_requise);
  end loop;
  v_quantite := coalesce(rec.quantite_produite, 1);
  if v_file then
    v_message := o.nom || ' : fabrication lancée. Elle rejoindra l’arsenal une fois la durée d’instance à 0.';
  else
    perform _arsenal_ajouter(p_objet, v_quantite);
    v_message := o.nom || ' fabriqué et ajouté au stock.';
  end if;
  v_jid := _journal('fabrication', v_message, 0, jsonb_build_object(
    'objet_id', p_objet, 'quantite', v_quantite, 'atelier', v_route,
    'file', v_file, 'ingredients', v_ingredients));
  if v_file then
    insert into atelier_fabrication (atelier, objet_id, quantite, restant, journal_id)
      values (v_route, p_objet, v_quantite, v_duree, v_jid);
  end if;
  return jsonb_build_object('journal_id', v_jid, 'atelier', v_route, 'file', v_file, 'message', v_message);
exception
  when unique_violation then
    raise exception 'Une fabrication est déjà en cours dans cet atelier.';
end;
$$;
revoke all on function partie_fabriquer(uuid, text) from public;
grant execute on function partie_fabriquer(uuid, text) to authenticated, fortress_fn;

-- ---------------------------------------------------------------------------
-- 5. Sessions : lancement et remise à zéro sans copie de contenu
-- ---------------------------------------------------------------------------
create or replace function session_lancer(p_session uuid)
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
  -- le budget (recettes / dépenses) est propre à la session : copié depuis les valeurs de départ
  insert into budget_poste (code, libelle, nature, montant, auto, ordre, session_id)
    select b.code, b.libelle, b.nature, b.montant, b.auto, b.ordre, p_session
    from budget_poste b where b.session_id is null;
  select or_compagnie into v_or from base_depart where id;
  insert into partie_etat (session_id, or_compagnie) values (p_session, coalesce(v_or, 1000));
  insert into dortoir_reglage (session_id) values (p_session);
  insert into entrainement_reglage (session_id) values (p_session);
  insert into infirmerie_reglage (session_id) values (p_session);
  insert into forge_sertissage (session_id) values (p_session);
  insert into inventaire (type, nom, session_id) values ('arsenal', 'Arsenal', p_session)
    returning id into v_inv;
  insert into ligne_inventaire (inventaire_id, objet_id, quantite, session_id)
    select v_inv, d.objet_id, d.quantite, p_session from base_depart_ligne d;
  update session set lancee_le = now() where id = p_session;
  return jsonb_build_object('session_id', p_session, 'or', coalesce(v_or, 1000));
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
    'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
    'ligne_inventaire', 'inventaire', 'atelier_fabrication', 'forge_sertissage', 'employe',
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

drop function if exists session_envoyer(uuid, text, uuid);
drop function if exists _env_objet(uuid, uuid);
drop function if exists _env_categorie(uuid, uuid);
drop function if exists _cloner_contenu(uuid, uuid);

-- Vétérance modifiée par le MJ depuis la fiche : dans une session, c'est l'état de cette session ;
-- dans le contexte « base de départ », c'est la valeur de départ inscrite sur la fiche du catalogue.
create function mercenaire_definir_veterance(p_mercenaire uuid, p_valeur integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_valeur is null or p_valeur < 0 or p_valeur > 999 then
    raise exception 'Saisissez un entier de 0 à 999.';
  end if;
  if ctx_est_base() then
    update mercenaire set veterance = p_valeur where id = p_mercenaire;
  else
    perform _verrou_partie();
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), p_mercenaire, p_valeur)
      on conflict (session_id, mercenaire_id) do update set veterance = excluded.veterance;
  end if;
end;
$$;
revoke all on function mercenaire_definir_veterance(uuid, integer) from public;
grant execute on function mercenaire_definir_veterance(uuid, integer) to authenticated, fortress_fn;

-- Fonctions de jeu : propriétaire fortress_fn (comme les autres) ; _vet lit avec ses propres filtres.
-- (le nouveau propriétaire doit avoir le droit de créer dans le schéma : accordé le temps du changement)
grant create on schema public to fortress_fn;
do $$
declare
  f text;
  r record;
begin
  foreach f in array array['entretien_montant', 'entrainement_choisir_eleve', 'entrainement_instance',
    'entrainement_annuler_instance', 'quete_choisir', 'quete_annuler_choix', 'quete_engager',
    'quetes_instance', 'quetes_annuler_instance', 'partie_fabriquer', 'mercenaire_definir_veterance', 'session_lancer', 'session_reinitialiser']
  loop
    for r in select p.oid::regprocedure as sig, r2.rolname as proprio from pg_proc p
             join pg_roles r2 on r2.oid = p.proowner
             where p.pronamespace = 'public'::regnamespace and p.proname = f
    loop
      -- les fonctions de gestion des sessions restent propriétaires postgres (elles doivent
      -- contourner la RLS) ; les fonctions de jeu appartiennent à fortress_fn
      if f not in ('session_lancer', 'session_reinitialiser') and r.proprio <> 'fortress_fn' then
        execute format('alter function %s owner to fortress_fn', r.sig);
      end if;
    end loop;
  end loop;
end;
$$;
revoke create on schema public from fortress_fn;

do $$
begin
  alter publication supabase_realtime add table mercenaire_etat;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table quete_etat;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;
