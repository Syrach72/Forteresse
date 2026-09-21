-- 1. Second groupe d'instruction au terrain d'entrainement (instructeur + 3 places
--    d'eleves, comme le premier), 2. DEBLOCAGES RESERVES A L'ADMINISTRATEUR sur
--    toutes les pages, 3. nouveaux prix de l'infirmerie (6 lits).
--
-- Regles de Bruno (2026-09-21) :
--  * seul l'administrateur debloque les cellules bloquees (dortoir, infirmerie,
--    entrainement) ; l'argent est preleve sur la tresorerie commune ;
--  * entrainement, groupe 1 : places d'eleves 2 et 3 a 100 Po chacune ;
--  * entrainement, groupe 2 : instructeur 1000 Po, places d'eleves 2 et 3 a 300 Po
--    chacune (la premiere place d'eleve est libre mais inutilisable sans
--    instructeur) ;
--  * infirmerie : 2 lits libres, puis 300 / 500 / 800 / 1200 Po dans l'ordre.
-- Toute suppression/mise a jour a une clause WHERE (cf. 20260921110000).

-- ---------------------------------------------------------------------------
-- 1. Groupes d'entrainement
-- ---------------------------------------------------------------------------
alter table entrainement_place
  add column groupe smallint not null default 1 check (groupe in (1, 2));
alter table entrainement_place drop constraint entrainement_place_pkey;
alter table entrainement_place add primary key (groupe, role, position);

alter table entrainement_reglage
  add column groupe2_debloque boolean not null default false,
  add column places_eleves_2 smallint not null default 1
    check (places_eleves_2 between 1 and 3);

drop function entrainement_choisir_instructeur(uuid);
drop function entrainement_choisir_eleve(integer, uuid);
drop function entrainement_debloquer_place();

create function entrainement_choisir_instructeur(p_mercenaire uuid, p_groupe integer default 1)
returns void
language plpgsql
security definer set search_path = public
as $$
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
  if p_groupe = 2 and not (select groupe2_debloque from entrainement_reglage) then
    raise exception 'Le second groupe d''instruction n''est pas debloque.';
  end if;
  if exists (
    select 1 from entrainement_place where role = 'instructeur' and groupe = p_groupe
  ) then
    raise exception 'Un instructeur est deja en place dans ce groupe : renvoyez-le d''abord au dortoir.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est deja a l''entrainement.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est a l''infirmerie.';
  end if;
  insert into entrainement_place (groupe, role, position, mercenaire_id)
    values (p_groupe, 'instructeur', 0, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Un instructeur vient d''etre place par un autre joueur.';
end;
$$;

create function entrainement_choisir_eleve(p_position integer, p_mercenaire uuid, p_groupe integer default 1)
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
  if coalesce(v_instr.veterance, 0) - coalesce(v_eleve.veterance, 0) < 3 then
    raise exception 'L''instructeur doit avoir au moins 3 points de veterance de plus que l''eleve.';
  end if;
  insert into entrainement_place (groupe, role, position, mercenaire_id)
    values (p_groupe, 'eleve', p_position, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Cette place vient d''etre prise.';
end;
$$;

-- Renvoyer un mercenaire au dortoir : renvoyer un instructeur ramene les eleves
-- de SON groupe seulement.
create or replace function entrainement_renvoyer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_role text;
  v_groupe integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  select role, groupe into v_role, v_groupe
    from entrainement_place where mercenaire_id = p_mercenaire;
  if not found then
    return;
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Seul son recruteur peut renvoyer ce mercenaire.';
  end if;
  if v_role = 'instructeur' then
    delete from entrainement_place where groupe = v_groupe;
  else
    delete from entrainement_place where mercenaire_id = p_mercenaire;
  end if;
end;
$$;

create or replace function entrainement_apres_renvoi()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_groupe integer;
begin
  select groupe into v_groupe
    from entrainement_place
    where role = 'instructeur' and mercenaire_id = old.mercenaire_id;
  if found then
    delete from entrainement_place where groupe = v_groupe;
  else
    delete from entrainement_place where mercenaire_id = old.mercenaire_id;
  end if;
  return old;
end;
$$;

-- +1 Instance (administrateur) : chaque groupe avance separement.
create or replace function entrainement_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_instr mercenaire%rowtype;
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
    select m.* into v_instr
      from entrainement_place p join mercenaire m on m.id = p.mercenaire_id
      where p.role = 'instructeur' and p.groupe = v_g;
    if not found then
      continue;
    end if;
    for r in
      select p.position, m.id as mid, coalesce(m.veterance, 0) as vet
      from entrainement_place p join mercenaire m on m.id = p.mercenaire_id
      where p.role = 'eleve' and p.groupe = v_g
      order by p.position
      for update of m
    loop
      v_avant := r.vet;
      if v_avant >= coalesce(v_instr.veterance, 0) then
        v_apres := v_avant;
        v_gradue := true;
      else
        v_apres := v_avant + 1;
        update mercenaire set veterance = v_apres where id = r.mid;
        v_gradue := v_apres >= coalesce(v_instr.veterance, 0);
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
      update mercenaire
        set veterance = (g ->> 'de')::integer
        where id = v_id and veterance = (g ->> 'a')::integer;
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

-- ---------------------------------------------------------------------------
-- 2. Deblocages : ADMINISTRATEUR SEUL
-- ---------------------------------------------------------------------------
-- Place d'eleve : 100 Po (groupe 1) ou 300 Po (groupe 2), 3 places au maximum.
create function entrainement_debloquer_place(p_groupe integer default 1)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_or integer;
  v_prix integer;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  if p_groupe not in (1, 2) then
    raise exception 'Groupe d''instruction inconnu.';
  end if;
  v_or := _verrou_partie();
  v_prix := case p_groupe when 1 then 100 else 300 end;
  if v_or < v_prix then
    raise exception 'Trésorerie insuffisante.';
  end if;
  if p_groupe = 1 then
    update entrainement_reglage
      set places_eleves = places_eleves + 1
      where places_eleves < 3
      returning places_eleves into v_places;
  else
    update entrainement_reglage
      set places_eleves_2 = places_eleves_2 + 1
      where places_eleves_2 < 3
      returning places_eleves_2 into v_places;
  end if;
  if not found then
    raise exception 'Toutes les places élèves sont ouvertes.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - v_prix where id;
  perform _journal('depense',
    'Place élève débloquée (groupe ' || p_groupe || ') : −' || v_prix || ' Po.', -v_prix, null);
  return v_places;
end;
$$;

-- Instructeur du second groupe : 1000 Po.
create function entrainement_debloquer_groupe2()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  v_or := _verrou_partie();
  if (select groupe2_debloque from entrainement_reglage) then
    raise exception 'Le second groupe d’instruction est déjà débloqué.';
  end if;
  if v_or < 1000 then
    raise exception 'Trésorerie insuffisante.';
  end if;
  update entrainement_reglage set groupe2_debloque = true where id;
  update partie_etat set or_compagnie = or_compagnie - 1000 where id;
  perform _journal('depense',
    'Second groupe d’instruction débloqué : −1000 Po.', -1000, null);
end;
$$;

-- Lits du dortoir : meme grille de prix, administrateur seul.
create or replace function dortoir_debloquer_place()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_or integer;
  v_prix integer;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  v_or := _verrou_partie();
  select places into v_places from dortoir_reglage;
  if v_places >= 18 then
    raise exception 'Tous les emplacements du dortoir sont déjà débloqués.';
  end if;
  v_prix := case
    when v_places < 9 then 100
    when v_places < 12 then 150
    when v_places < 15 then 200
    else 300
  end;
  if v_or < v_prix then
    raise exception 'Trésorerie insuffisante.';
  end if;
  update dortoir_reglage
    set places = places + 1
    where places < 18
    returning places into v_places;
  update partie_etat set or_compagnie = or_compagnie - v_prix where id;
  perform _journal('depense',
    'Emplacement de dortoir débloqué : −' || v_prix || ' Po.', -v_prix, null);
  return v_places;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Infirmerie : 6 lits, 2 libres puis 300 / 500 / 800 / 1200 Po
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select conrelid::regclass as t, conname
    from pg_constraint
    where contype = 'c'
      and (
        (conrelid = 'infirmerie_reglage'::regclass and pg_get_constraintdef(oid) ilike '%places%')
        or (conrelid = 'infirmerie_place'::regclass and pg_get_constraintdef(oid) ilike '%position%')
      )
  loop
    execute format('alter table %s drop constraint %I', c.t, c.conname);
  end loop;
end;
$$;
alter table infirmerie_reglage
  add constraint infirmerie_reglage_places_borne check (places between 2 and 6);
alter table infirmerie_place
  add constraint infirmerie_place_position_borne check (position between 0 and 5);

create or replace function infirmerie_debloquer_place()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_or integer;
  v_prix integer;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  v_or := _verrou_partie();
  select places into v_places from infirmerie_reglage;
  if v_places >= 6 then
    raise exception 'Tous les lits d’infirmerie sont déjà débloqués.';
  end if;
  v_prix := case v_places when 2 then 300 when 3 then 500 when 4 then 800 else 1200 end;
  if v_or < v_prix then
    raise exception 'Trésorerie insuffisante.';
  end if;
  update infirmerie_reglage
    set places = places + 1
    where places < 6
    returning places into v_places;
  update partie_etat set or_compagnie = or_compagnie - v_prix where id;
  perform _journal('depense',
    'Lit d’infirmerie débloqué : −' || v_prix || ' Po.', -v_prix, null);
  return v_places;
end;
$$;

-- Droits d'execution des fonctions creees ou recreees ci-dessus.
revoke all on function entrainement_choisir_instructeur(uuid, integer) from public;
revoke all on function entrainement_choisir_eleve(integer, uuid, integer) from public;
revoke all on function entrainement_debloquer_place(integer) from public;
revoke all on function entrainement_debloquer_groupe2() from public;
grant execute on function entrainement_choisir_instructeur(uuid, integer) to authenticated;
grant execute on function entrainement_choisir_eleve(integer, uuid, integer) to authenticated;
grant execute on function entrainement_debloquer_place(integer) to authenticated;
grant execute on function entrainement_debloquer_groupe2() to authenticated;
