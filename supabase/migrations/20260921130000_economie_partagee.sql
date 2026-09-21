-- Economie PARTAGEE : une seule tresorerie, un seul arsenal et des ateliers
-- communs a tous les joueurs (jusqu'ici chaque navigateur avait sa demo locale).
--
-- * or de la compagnie : table partie_etat (une ligne), 1000 Po au depart ;
-- * arsenal : les tables inventaire / ligne_inventaire existantes (celles de
--   l'Administration > Arsenal), desormais modifiees aussi par les achats, ventes,
--   destructions et fabrications des joueurs ;
-- * journal : partie_journal (achats, ventes, fabrications, depenses...) ;
-- * fabrications en cours : atelier_fabrication (une par atelier), avec leur
--   duree d'instance restante ; l'administrateur les fait avancer au +1 Instance.
--
-- Les tables se lisent par tous les joueurs connectes ; les joueurs n'ecrivent QUE
-- par les fonctions ci-dessous (security definer), qui verifient les regles
-- (solde, stock, recette, atelier libre...). Toutes les operations verrouillent
-- d'abord la ligne partie_etat : elles s'executent l'une apres l'autre, sans
-- double depense ni stock negatif meme si deux joueurs cliquent en meme temps.
-- Tout DELETE/UPDATE a une clause WHERE (Supabase refuse sinon depuis
-- l'application, cf. 20260921110000_entrainement_correctif_where.sql).

create table partie_etat (
  id boolean primary key default true check (id),
  or_compagnie integer not null default 1000 check (or_compagnie >= 0)
);
insert into partie_etat default values;

create table partie_journal (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in
    ('achat', 'vente', 'destruction', 'fabrication', 'recuperation', 'depense', 'or', 'annulation')),
  message text not null,
  montant integer not null default 0,
  details jsonb,
  auteur_id uuid,
  annule boolean not null default false,
  created_at timestamptz not null default now()
);
create index partie_journal_recent_idx on partie_journal (created_at desc);

create table atelier_fabrication (
  atelier text primary key check (atelier in ('forge', 'armurerie', 'alchimie', 'mage')),
  objet_id uuid not null references objet_catalogue (id),
  quantite smallint not null default 1 check (quantite >= 1),
  restant smallint not null check (restant between 0 and 5),
  journal_id uuid,
  created_at timestamptz not null default now()
);

alter table partie_etat enable row level security;
alter table partie_journal enable row level security;
alter table atelier_fabrication enable row level security;
create policy "partie_etat: lecture par les joueurs connectes"
  on partie_etat for select to authenticated using (true);
create policy "partie_etat: ecriture admin"
  on partie_etat for all to authenticated using (is_admin()) with check (is_admin());
create policy "partie_journal: lecture par les joueurs connectes"
  on partie_journal for select to authenticated using (true);
create policy "partie_journal: ecriture admin"
  on partie_journal for all to authenticated using (is_admin()) with check (is_admin());
create policy "atelier_fabrication: lecture par les joueurs connectes"
  on atelier_fabrication for select to authenticated using (true);
create policy "atelier_fabrication: ecriture admin"
  on atelier_fabrication for all to authenticated using (is_admin()) with check (is_admin());

-- ---------------------------------------------------------------------------
-- Outils internes (pas de droit d'execution pour les joueurs).
-- ---------------------------------------------------------------------------
create function _arsenal_id()
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from inventaire where type = 'arsenal' order by created_at, id limit 1;
  if v_id is null then
    insert into inventaire (type, nom) values ('arsenal', 'Arsenal') returning id into v_id;
  end if;
  return v_id;
end;
$$;

create function _arsenal_quantite(p_objet uuid)
returns integer
language sql
security definer set search_path = public
as $$
  select coalesce(sum(quantite), 0)::integer
  from ligne_inventaire
  where inventaire_id = _arsenal_id() and objet_id = p_objet;
$$;

create function _arsenal_ajouter(p_objet uuid, p_quantite integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update ligne_inventaire
    set quantite = quantite + p_quantite, updated_at = now()
    where id = (
      select id from ligne_inventaire
      where inventaire_id = _arsenal_id() and objet_id = p_objet
      order by created_at, id limit 1);
  if not found then
    insert into ligne_inventaire (inventaire_id, objet_id, quantite)
      values (_arsenal_id(), p_objet, p_quantite);
  end if;
end;
$$;

create function _arsenal_retirer(p_objet uuid, p_quantite integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  l record;
  v_reste integer := p_quantite;
  v_pris integer;
begin
  if _arsenal_quantite(p_objet) < p_quantite then
    raise exception 'Quantité insuffisante dans l''arsenal.';
  end if;
  for l in
    select id, quantite from ligne_inventaire
    where inventaire_id = _arsenal_id() and objet_id = p_objet and quantite > 0
    order by created_at, id
    for update
  loop
    exit when v_reste <= 0;
    v_pris := least(l.quantite, v_reste);
    if v_pris = l.quantite then
      delete from ligne_inventaire where id = l.id;
    else
      update ligne_inventaire
        set quantite = quantite - v_pris, updated_at = now()
        where id = l.id;
    end if;
    v_reste := v_reste - v_pris;
  end loop;
end;
$$;

create function _journal(p_type text, p_message text, p_montant integer, p_details jsonb)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into partie_journal (type, message, montant, details, auteur_id)
    values (p_type, p_message, p_montant, p_details, auth.uid())
    returning id into v_id;
  return v_id;
end;
$$;

-- Verrou commun des operations economiques.
create function _verrou_partie()
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
  select or_compagnie into v_or from partie_etat where id for update;
  return v_or;
end;
$$;

-- ---------------------------------------------------------------------------
-- Achat, vente, destruction (Marche, fiche d'objet de l'arsenal).
-- ---------------------------------------------------------------------------
create function partie_acheter(p_objet uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  o objet_catalogue%rowtype;
  v_jid uuid;
begin
  v_or := _verrou_partie();
  select * into o from objet_catalogue where id = p_objet and actif is not false;
  if not found then
    raise exception 'Objet inconnu.';
  end if;
  if o.cout_achat_or is null or o.cout_achat_or < 0 then
    raise exception 'Le coût d''achat de cet objet n''est pas encore défini.';
  end if;
  if v_or < o.cout_achat_or then
    raise exception 'Vous n''avez pas assez de pièces d''or.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - o.cout_achat_or where id;
  perform _arsenal_ajouter(p_objet, 1);
  v_jid := _journal('achat', o.nom || ' acheté : −' || o.cout_achat_or || ' Po.',
    -o.cout_achat_or, jsonb_build_object('objet_id', p_objet, 'quantite', 1));
  return jsonb_build_object('journal_id', v_jid, 'or', v_or - o.cout_achat_or);
end;
$$;

create function partie_vendre(p_objet uuid, p_quantite integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  o objet_catalogue%rowtype;
  v_gain integer;
begin
  v_or := _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  if not found or coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if _arsenal_quantite(p_objet) < p_quantite then
    raise exception 'Quantité invalide : cet objet n''est pas disponible en telle quantité dans l''arsenal.';
  end if;
  if o.cout_achat_or is null then
    raise exception 'La valeur de cet objet n''est pas définie : vente impossible.';
  end if;
  v_gain := floor((o.cout_achat_or * p_quantite) / 2.0);
  perform _arsenal_retirer(p_objet, p_quantite);
  update partie_etat set or_compagnie = or_compagnie + v_gain where id;
  perform _journal('vente', 'Vente de ' || o.nom || ' ×' || p_quantite || ' : +' || v_gain || ' Po.',
    v_gain, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
  return jsonb_build_object('or', v_or + v_gain, 'gain', v_gain);
end;
$$;

create function partie_detruire(p_objet uuid, p_quantite integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
begin
  perform _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  if not found or coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if _arsenal_quantite(p_objet) < p_quantite then
    raise exception 'Quantité invalide : cet objet n''est pas disponible en telle quantité dans l''arsenal.';
  end if;
  perform _arsenal_retirer(p_objet, p_quantite);
  perform _journal('destruction', 'Destruction de ' || o.nom || ' ×' || p_quantite || '.', 0,
    jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
end;
$$;

-- Dépense libre (ex. déblocage d'un lit du dortoir).
create function partie_depenser(p_montant integer, p_motif text)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
begin
  v_or := _verrou_partie();
  if coalesce(p_montant, 0) < 1 then
    raise exception 'Montant invalide.';
  end if;
  if v_or < p_montant then
    raise exception 'Trésorerie insuffisante.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - p_montant where id;
  perform _journal('depense', p_motif || ' : −' || p_montant || ' Po.', -p_montant, null);
  return v_or - p_montant;
end;
$$;

-- Fixer l'or de la compagnie (administrateur, champ de l'Administration).
create function partie_or_definir(p_montant integer)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_montant is null or p_montant < 0 or p_montant > 100000000 then
    raise exception 'Saisissez un entier de 0 à 100 000 000.';
  end if;
  v_or := _verrou_partie();
  update partie_etat set or_compagnie = p_montant where id;
  perform _journal('or', 'Trésorerie ajustée par l''administrateur : ' || p_montant || ' Po.',
    p_montant - v_or, null);
  return p_montant;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fabrication. La recette et l'atelier viennent de la base (jamais du
-- navigateur) : ingredients par identifiant d'objet, quantite produite et duree
-- d'instance de l'objet. Duree > 0 : mise en file dans l'atelier (une seule
-- fabrication a la fois), a recuperer une fois la duree a 0 ; sinon livraison
-- immediate a l'arsenal.
-- ---------------------------------------------------------------------------
create function partie_fabriquer(p_objet uuid)
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

-- Récupérer une fabrication terminée (durée à 0) : l'objet rejoint l'arsenal
-- et l'atelier est libéré. Ouvert à tous les joueurs (atelier commun).
create function partie_recuperer(p_atelier text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  f atelier_fabrication%rowtype;
  o objet_catalogue%rowtype;
begin
  perform _verrou_partie();
  select * into f from atelier_fabrication where atelier = p_atelier;
  if not found then
    raise exception 'Aucune fabrication à récupérer dans cet atelier.';
  end if;
  if f.restant > 0 then
    raise exception 'La fabrication n''est pas encore terminée.';
  end if;
  select * into o from objet_catalogue where id = f.objet_id;
  perform _arsenal_ajouter(f.objet_id, f.quantite);
  delete from atelier_fabrication where atelier = p_atelier;
  perform _journal('recuperation', o.nom || ' rejoint l’arsenal.', 0,
    jsonb_build_object('objet_id', f.objet_id, 'quantite', f.quantite, 'atelier', p_atelier));
  return jsonb_build_object('message', o.nom || ' rejoint l’arsenal.');
end;
$$;

-- ---------------------------------------------------------------------------
-- Annulation d'un achat ou d'une fabrication (bouton « Annuler » de la fiche) :
-- operation inverse journalisee, refusee si la situation a change (objet plus
-- disponible, fabrication deja recuperee). Reservee a l'auteur (ou a
-- l'administrateur), une seule fois.
-- ---------------------------------------------------------------------------
create function partie_annuler(p_journal uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  j partie_journal%rowtype;
  o objet_catalogue%rowtype;
  i jsonb;
  v_message text;
begin
  v_or := _verrou_partie();
  select * into j from partie_journal where id = p_journal for update;
  if not found then
    raise exception 'Opération introuvable.';
  end if;
  if not is_admin() and j.auteur_id is distinct from auth.uid() then
    raise exception 'Seul l''auteur de l''opération peut l''annuler.';
  end if;
  if j.annule then
    raise exception 'Cette opération est déjà annulée.';
  end if;
  if j.type not in ('achat', 'fabrication') then
    raise exception 'Cette opération ne peut pas être annulée.';
  end if;
  select * into o from objet_catalogue where id = (j.details ->> 'objet_id')::uuid;
  if j.type = 'achat' then
    if _arsenal_quantite(o.id) < 1 then
      raise exception 'Annulation impossible : cet objet n''est plus disponible.';
    end if;
    perform _arsenal_retirer(o.id, 1);
    update partie_etat set or_compagnie = or_compagnie - j.montant where id;
    v_message := 'Achat annulé : pièces d’or remboursées.';
  else
    if (j.details ->> 'file')::boolean then
      if not exists (select 1 from atelier_fabrication where journal_id = p_journal) then
        raise exception 'Annulation impossible : la fabrication a déjà été récupérée.';
      end if;
      delete from atelier_fabrication where journal_id = p_journal;
    else
      if _arsenal_quantite(o.id) < (j.details ->> 'quantite')::integer then
        raise exception 'Annulation impossible : cet objet n''est plus disponible.';
      end if;
      perform _arsenal_retirer(o.id, (j.details ->> 'quantite')::integer);
    end if;
    for i in select * from jsonb_array_elements(j.details -> 'ingredients')
    loop
      perform _arsenal_ajouter((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
    end loop;
    v_message := 'Fabrication annulée : ressources restituées, atelier libéré.';
  end if;
  update partie_journal set annule = true where id = p_journal;
  perform _journal('annulation', v_message, -j.montant, jsonb_build_object('annule', p_journal));
  return jsonb_build_object('message', v_message);
end;
$$;

-- ---------------------------------------------------------------------------
-- +1 Instance des ateliers (administrateur) : chaque duree baisse de 1, minimum 0.
-- Rien n'est livre tout seul : le joueur clique « Envoyer a l'Arsenal ».
-- ---------------------------------------------------------------------------
create function ateliers_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  v_apres integer;
  v_gains jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for r in select atelier, restant from atelier_fabrication order by atelier for update
  loop
    v_apres := greatest(r.restant - 1, 0);
    update atelier_fabrication set restant = v_apres where atelier = r.atelier;
    v_gains := v_gains || jsonb_build_object('atelier', r.atelier, 'de', r.restant, 'a', v_apres);
  end loop;
  return v_gains;
end;
$$;

create function ateliers_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    update atelier_fabrication
      set restant = (g ->> 'de')::integer
      where atelier = g ->> 'atelier' and restant = (g ->> 'a')::integer;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Les deblocages de places (entrainement 100 Po, infirmerie 1000 Po) debitent
-- desormais la tresorerie PARTAGEE, dans la meme operation.
-- ---------------------------------------------------------------------------
create or replace function entrainement_debloquer_place()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_or integer;
begin
  v_or := _verrou_partie();
  if v_or < 100 then
    raise exception 'Trésorerie insuffisante.';
  end if;
  update entrainement_reglage
    set places_eleves = places_eleves + 1
    where places_eleves < 3
    returning places_eleves into v_places;
  if not found then
    raise exception 'Toutes les places élèves sont ouvertes.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - 100 where id;
  perform _journal('depense', 'Place élève débloquée : −100 Po.', -100, null);
  return v_places;
end;
$$;

create or replace function infirmerie_debloquer_place()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_or integer;
begin
  v_or := _verrou_partie();
  if v_or < 1000 then
    raise exception 'Trésorerie insuffisante.';
  end if;
  update infirmerie_reglage
    set places = places + 1
    where places < 3
    returning places into v_places;
  if not found then
    raise exception 'Tous les lits d''infirmerie sont déjà débloqués.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - 1000 where id;
  perform _journal('depense', 'Lit d’infirmerie débloqué : −1000 Po.', -1000, null);
  return v_places;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits : seules les fonctions publiques ci-dessous sont appelables.
-- ---------------------------------------------------------------------------
revoke all on function _arsenal_id() from public;
revoke all on function _arsenal_quantite(uuid) from public;
revoke all on function _arsenal_ajouter(uuid, integer) from public;
revoke all on function _arsenal_retirer(uuid, integer) from public;
revoke all on function _journal(text, text, integer, jsonb) from public;
revoke all on function _verrou_partie() from public;
revoke all on function partie_acheter(uuid) from public;
revoke all on function partie_vendre(uuid, integer) from public;
revoke all on function partie_detruire(uuid, integer) from public;
revoke all on function partie_depenser(integer, text) from public;
revoke all on function partie_or_definir(integer) from public;
revoke all on function partie_fabriquer(uuid) from public;
revoke all on function partie_recuperer(text) from public;
revoke all on function partie_annuler(uuid) from public;
revoke all on function ateliers_instance() from public;
revoke all on function ateliers_annuler_instance(jsonb) from public;
grant execute on function partie_acheter(uuid) to authenticated;
grant execute on function partie_vendre(uuid, integer) to authenticated;
grant execute on function partie_detruire(uuid, integer) to authenticated;
grant execute on function partie_depenser(integer, text) to authenticated;
grant execute on function partie_or_definir(integer) to authenticated;
grant execute on function partie_fabriquer(uuid) to authenticated;
grant execute on function partie_recuperer(text) to authenticated;
grant execute on function partie_annuler(uuid) to authenticated;
grant execute on function ateliers_instance() to authenticated;
grant execute on function ateliers_annuler_instance(jsonb) to authenticated;

-- Mise a jour en direct chez tous les joueurs (Supabase Realtime).
do $$
begin
  alter publication supabase_realtime add table partie_etat;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table partie_journal;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table atelier_fabrication;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table ligne_inventaire;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
