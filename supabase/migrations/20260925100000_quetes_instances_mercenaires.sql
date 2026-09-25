-- Quetes : duree en instances + mercenaires engages (regle de Bruno, 2026-09-25).
--
--  * Chaque quete a un nombre d'instances requises (modifiable en admin, 1 par
--    defaut = comportement precedent). Choisir la quete initialise le compteur ;
--    chaque +1 Instance (administrateur) le decompte de 1. A 0 la quete est
--    accomplie : l'or rejoint la tresorerie, les objets rejoignent l'arsenal, les
--    mercenaires engages retournent au dortoir et la quete devient indisponible.
--  * Jusqu'a 6 mercenaires engages par quete (table quete_mercenaire), pris parmi
--    ceux du dortoir. Tant qu'ils sont engages ils sont "absents" du dortoir
--    (affiches grises, ils gardent leur lit), comme a l'entrainement ou a
--    l'infirmerie : ils ne peuvent pas etre dans deux endroits a la fois.
--  * Un joueur n'engage / ne retire que ses propres mercenaires (l'administrateur
--    tous) ; seul l'administrateur fait avancer l'instance et l'annule.
--
-- Reutilise _verrou_partie(), _arsenal_ajouter()/_arsenal_retirer(), _journal()
-- (20260921130000_economie_partagee.sql) et les fonctions de
-- 20260922100000_quetes.sql, dont quete_choisir / quete_annuler_choix /
-- quetes_instance / quetes_annuler_instance sont ici remplacees (create or
-- replace : droits conserves). Toute suppression a une clause WHERE explicite
-- (pg_safeupdate, cf. 20260921110000).

alter table quete
  add column instances_requises smallint not null default 1
    check (instances_requises between 1 and 99),
  add column instances_restantes smallint
    check (instances_restantes is null or instances_restantes >= 0);

create table quete_mercenaire (
  quete_id uuid not null references quete (id) on delete cascade,
  position smallint not null check (position between 0 and 5),
  mercenaire_id uuid not null unique references mercenaire (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (quete_id, position)
);

alter table quete_mercenaire enable row level security;
create policy "quete_mercenaire: lecture par les joueurs connectes"
  on quete_mercenaire for select to authenticated using (true);
create policy "quete_mercenaire: ecriture admin"
  on quete_mercenaire for all to authenticated
  using (is_admin()) with check (is_admin());

-- ---------------------------------------------------------------------------
-- Un mercenaire engage dans une quete ne peut pas etre place a l'entrainement
-- ni a l'infirmerie (garde sur les deux tables, sans reecrire leurs fonctions).
-- ---------------------------------------------------------------------------
create function _refuser_si_en_quete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if exists (select 1 from quete_mercenaire where mercenaire_id = new.mercenaire_id) then
    raise exception 'Ce mercenaire est en quête : retirez-le d''abord de la quête.';
  end if;
  return new;
end;
$$;

create trigger entrainement_place_pas_en_quete
  before insert on entrainement_place
  for each row execute function _refuser_si_en_quete();
create trigger infirmerie_place_pas_en_quete
  before insert on infirmerie_place
  for each row execute function _refuser_si_en_quete();

-- Un mercenaire renvoye de la compagnie quitte aussi sa quete.
create function quete_apres_renvoi()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from quete_mercenaire where mercenaire_id = old.mercenaire_id;
  return old;
end;
$$;

create trigger recrutement_quitte_quete
  after delete on recrutement
  for each row execute function quete_apres_renvoi();

-- ---------------------------------------------------------------------------
-- Choix / annulation de la quete (tout joueur connecte).
-- ---------------------------------------------------------------------------
create or replace function quete_choisir(p_quete uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  if exists (select 1 from quete where en_cours) then
    raise exception 'Une quête est déjà en cours : annulez-la d''abord.';
  end if;
  update quete
    set en_cours = true, instances_restantes = instances_requises
    where id = p_quete and actif and terminee_le is null;
  if not found then
    raise exception 'Cette quête n''est pas disponible.';
  end if;
end;
$$;

-- Annuler le choix libere aussi les mercenaires engages (ils retournent au
-- dortoir) et efface la progression.
create or replace function quete_annuler_choix()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  perform _verrou_partie();
  select id into v_id from quete where en_cours;
  if v_id is null then
    return;
  end if;
  delete from quete_mercenaire where quete_id = v_id;
  update quete set en_cours = false, instances_restantes = null where id = v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Engager / retirer un mercenaire (6 emplacements, positions 0 a 5).
-- ---------------------------------------------------------------------------
create function quete_engager(p_position integer, p_mercenaire uuid)
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
  select id into v_quete from quete where en_cours;
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

create function quete_retirer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  perform _verrou_partie();
  if not exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    return;
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Seul son recruteur peut retirer ce mercenaire de la quête.';
  end if;
  delete from quete_mercenaire where mercenaire_id = p_mercenaire;
end;
$$;

-- ---------------------------------------------------------------------------
-- +1 Instance (administrateur) : decompte la quete en cours. Renvoie null si
-- aucune quete n'est en cours ; sinon un recapitulatif utilisable pour
-- l'annulation : { quete_id, nom, avant, apres, termine, [or, items,
-- mercenaires] }. Tant que apres > 0 rien d'autre ne change ; a 0 la quete est
-- accomplie (or, objets, mercenaires liberes, quete terminee).
-- ---------------------------------------------------------------------------
create or replace function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
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
  select * into q from quete where en_cours for update;
  if not found then
    return null;
  end if;
  v_avant := coalesce(q.instances_restantes, q.instances_requises);
  v_apres := greatest(v_avant - 1, 0);
  if v_apres > 0 then
    update quete set instances_restantes = v_apres where id = q.id;
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
  update quete
    set en_cours = false, terminee_le = now(), instances_restantes = 0
    where id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : +' || q.recompense_or || ' Po, ' || jsonb_array_length(v_items) || ' objet(s) rejoignent l''arsenal.',
    q.recompense_or, jsonb_build_object('quete_id', q.id, 'items', v_items));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs);
end;
$$;

-- Annuler le dernier +1 Instance (administrateur) a partir de ce qu'il a
-- renvoye. Un simple decompte est remis comme avant ; une quete accomplie est
-- rouverte (or et objets retires, mercenaires replaces s'ils sont encore
-- libres), sauf si une autre quete est deja en cours.
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
    update quete
      set instances_restantes = (p_gains ->> 'avant')::integer
      where id = v_quete and en_cours
        and instances_restantes = (p_gains ->> 'apres')::integer;
    return;
  end if;

  if exists (select 1 from quete where en_cours and id <> v_quete) then
    raise exception 'Une autre quête est en cours : impossible de rouvrir celle-ci.';
  end if;
  if coalesce((p_gains ->> 'or')::integer, 0) > 0 then
    update partie_etat set or_compagnie = or_compagnie - (p_gains ->> 'or')::integer where id;
  end if;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'items', '[]'::jsonb))
  loop
    perform _arsenal_retirer((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
  end loop;
  update quete
    set en_cours = true, terminee_le = null,
        instances_restantes = greatest(coalesce((p_gains ->> 'avant')::integer, 1), 1)
    where id = v_quete;
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

revoke all on function _refuser_si_en_quete() from public;
revoke all on function quete_apres_renvoi() from public;
revoke all on function quete_engager(integer, uuid) from public;
revoke all on function quete_retirer(uuid) from public;
grant execute on function quete_engager(integer, uuid) to authenticated;
grant execute on function quete_retirer(uuid) to authenticated;

-- Mise a jour en direct chez tous les joueurs (Supabase Realtime).
do $$
begin
  alter publication supabase_realtime add table quete_mercenaire;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
