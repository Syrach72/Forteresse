-- Infirmerie PARTAGEE : un joueur envoie son mercenaire se faire soigner depuis
-- sa fiche (bouton « Soigner »). Le mercenaire occupe un lit avec un delai de 5
-- instances ; a chaque +1 Instance (administrateur) le compteur baisse de 1 ;
-- a 0 il quitte l'infirmerie et retrouve sa place au dortoir (le lit du dortoir
-- ne bouge jamais : il apparait seulement grise pendant les soins).
--
-- Meme principe que le terrain d'entrainement : les tables se lisent par tous
-- les joueurs connectes et ne s'ecrivent que par les fonctions ci-dessous
-- (security definer). Un joueur n'envoie / ne rappelle que ses propres
-- mercenaires ; seul l'administrateur fait avancer l'instance et l'annule.
-- Toute suppression a une clause WHERE explicite (Supabase refuse sinon, cf.
-- 20260921110000_entrainement_correctif_where.sql).

create table infirmerie_reglage (
  id boolean primary key default true check (id),
  places smallint not null default 2 check (places between 2 and 3)
);
insert into infirmerie_reglage default values;

create table infirmerie_place (
  position smallint primary key check (position between 0 and 2),
  mercenaire_id uuid not null unique references mercenaire (id) on delete cascade,
  restant smallint not null check (restant between 0 and 5),
  created_at timestamptz not null default now()
);

alter table infirmerie_reglage enable row level security;
alter table infirmerie_place enable row level security;

create policy "infirmerie_reglage: lecture par les joueurs connectes"
  on infirmerie_reglage for select to authenticated using (true);
create policy "infirmerie_reglage: ecriture admin"
  on infirmerie_reglage for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "infirmerie_place: lecture par les joueurs connectes"
  on infirmerie_place for select to authenticated using (true);
create policy "infirmerie_place: ecriture admin"
  on infirmerie_place for all to authenticated
  using (is_admin()) with check (is_admin());

-- Envoyer un mercenaire a l'infirmerie (bouton « Soigner » de la fiche) : premier
-- lit libre, delai de 5 instances.
create function infirmerie_soigner(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_pos integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recrute par vous.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est deja a l''infirmerie.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est a l''entrainement : renvoyez-le d''abord au dortoir.';
  end if;
  select places into v_places from infirmerie_reglage;
  select p into v_pos
    from generate_series(0, v_places - 1) as p
    where not exists (select 1 from infirmerie_place where position = p)
    order by p
    limit 1;
  if v_pos is null then
    raise exception 'Aucun lit libre a l''infirmerie.';
  end if;
  insert into infirmerie_place (position, mercenaire_id, restant)
    values (v_pos, p_mercenaire, 5);
exception
  when unique_violation then
    raise exception 'Ce lit vient d''etre pris par un autre joueur.';
end;
$$;

-- Rappeler un mercenaire au dortoir avant la fin des soins (son recruteur ou
-- l'administrateur).
create function infirmerie_renvoyer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if not exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    return;
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Seul son recruteur peut rappeler ce mercenaire.';
  end if;
  delete from infirmerie_place where mercenaire_id = p_mercenaire;
end;
$$;

-- Debloquer le troisieme lit (le debit en pieces d'or reste cote application).
create function infirmerie_debloquer_place()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  update infirmerie_reglage
    set places = places + 1
    where places < 3
    returning places into v_places;
  if not found then
    raise exception 'Tous les lits d''infirmerie sont deja debloques.';
  end if;
  return v_places;
end;
$$;

-- +1 Instance (administrateur) : chaque compteur baisse de 1 ; a 0 le
-- mercenaire quitte l'infirmerie. Renvoie, pour chaque lit : mercenaire_id,
-- position, de (avant), a (apres), sorti (true s'il retourne au dortoir).
create function infirmerie_instance()
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
    raise exception 'Reserve a l''administrateur.';
  end if;
  for r in
    select position, mercenaire_id, restant
    from infirmerie_place
    order by position
    for update
  loop
    v_apres := greatest(r.restant - 1, 0);
    if v_apres = 0 then
      delete from infirmerie_place where mercenaire_id = r.mercenaire_id;
    else
      update infirmerie_place set restant = v_apres
        where mercenaire_id = r.mercenaire_id;
    end if;
    v_gains := v_gains || jsonb_build_object(
      'mercenaire_id', r.mercenaire_id, 'position', r.position,
      'de', r.restant, 'a', v_apres, 'sorti', v_apres = 0);
  end loop;
  return v_gains;
end;
$$;

-- Annuler le dernier +1 Instance (administrateur) a partir de ce qu'il a
-- renvoye : remet les compteurs d'avant et replace les mercenaires sortis si
-- leur lit est encore libre et s'ils ne sont pas repartis ailleurs.
create function infirmerie_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
  v_id uuid;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    v_id := (g ->> 'mercenaire_id')::uuid;
    if (g ->> 'sorti')::boolean then
      if not exists (select 1 from infirmerie_place where mercenaire_id = v_id)
         and not exists (select 1 from entrainement_place where mercenaire_id = v_id)
         and not exists (
           select 1 from infirmerie_place
           where position = (g ->> 'position')::integer)
      then
        insert into infirmerie_place (position, mercenaire_id, restant)
          values ((g ->> 'position')::integer, v_id, (g ->> 'de')::integer);
      end if;
    else
      update infirmerie_place
        set restant = (g ->> 'de')::integer
        where mercenaire_id = v_id and restant = (g ->> 'a')::integer;
    end if;
  end loop;
end;
$$;

-- Un mercenaire renvoye de la compagnie quitte aussi l'infirmerie.
create function infirmerie_apres_renvoi()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from infirmerie_place where mercenaire_id = old.mercenaire_id;
  return old;
end;
$$;

create trigger recrutement_quitte_infirmerie
  after delete on recrutement
  for each row execute function infirmerie_apres_renvoi();

-- Un mercenaire soigne ne peut pas etre place a l'entrainement : les deux
-- fonctions de placement du terrain d'entrainement le verifient desormais
-- (memes corps que 20260921100000, avec la verification en plus).
create or replace function entrainement_choisir_instructeur(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recrute par vous.';
  end if;
  if exists (select 1 from entrainement_place where role = 'instructeur') then
    raise exception 'Un instructeur est deja en place : renvoyez-le d''abord au dortoir.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est deja a l''entrainement.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est a l''infirmerie.';
  end if;
  insert into entrainement_place (role, position, mercenaire_id)
    values ('instructeur', 0, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Un instructeur vient d''etre place par un autre joueur.';
end;
$$;

create or replace function entrainement_choisir_eleve(p_position integer, p_mercenaire uuid)
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
  if not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recrute par vous.';
  end if;
  select m.* into v_instr
    from entrainement_place p join mercenaire m on m.id = p.mercenaire_id
    where p.role = 'instructeur';
  if not found then
    raise exception 'Choisissez d''abord un instructeur.';
  end if;
  select places_eleves into v_places from entrainement_reglage;
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
  insert into entrainement_place (role, position, mercenaire_id)
    values ('eleve', p_position, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Cette place vient d''etre prise.';
end;
$$;

-- Droits (create or replace conserve ceux des deux fonctions d'entrainement).
revoke all on function infirmerie_soigner(uuid) from public;
revoke all on function infirmerie_renvoyer(uuid) from public;
revoke all on function infirmerie_debloquer_place() from public;
revoke all on function infirmerie_instance() from public;
revoke all on function infirmerie_annuler_instance(jsonb) from public;
revoke all on function infirmerie_apres_renvoi() from public;
grant execute on function infirmerie_soigner(uuid) to authenticated;
grant execute on function infirmerie_renvoyer(uuid) to authenticated;
grant execute on function infirmerie_debloquer_place() to authenticated;
grant execute on function infirmerie_instance() to authenticated;
grant execute on function infirmerie_annuler_instance(jsonb) to authenticated;

-- Mise a jour en direct chez tous les joueurs (Supabase Realtime).
do $$
begin
  alter publication supabase_realtime add table infirmerie_place;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table infirmerie_reglage;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
