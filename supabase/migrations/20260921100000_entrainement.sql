-- Terrain d'entrainement PARTAGE : un instructeur, des eleves, visibles par
-- tous les joueurs et conserves au rechargement.
--
-- Regles (Bruno) :
--  * pas d'eleve sans instructeur ;
--  * l'eleve est de la meme classe que l'instructeur, qui a au moins 3 points
--    de veterance de plus que lui ;
--  * a chaque +1 Instance (clic de l'administrateur), chaque eleve gagne 1
--    point de veterance ; quand il rejoint celle de l'instructeur il retourne
--    au dortoir avec son nouveau niveau ;
--  * un joueur peut renvoyer son eleve avant (il garde le niveau acquis) ;
--  * l'instructeur reste en place jusqu'a ce qu'on le renvoie (ses eleves
--    retournent alors aussi au dortoir).
--
-- Les tables se lisent par tous les joueurs connectes, mais ne s'ecrivent QUE
-- par les fonctions ci-dessous (security definer) : ce sont elles qui font foi
-- pour les regles, pas l'interface. Un joueur ne peut placer / renvoyer que
-- ses propres mercenaires (table recrutement) ; seul l'administrateur peut
-- faire avancer l'entrainement (+1 Instance) et l'annuler.

create table entrainement_reglage (
  id boolean primary key default true check (id),
  places_eleves smallint not null default 1
    check (places_eleves between 1 and 3)
);
insert into entrainement_reglage default values;

create table entrainement_place (
  role text not null check (role in ('instructeur', 'eleve')),
  position smallint not null check (position between 0 and 2),
  mercenaire_id uuid not null unique references mercenaire (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role, position),
  check (role <> 'instructeur' or position = 0)
);

alter table entrainement_reglage enable row level security;
alter table entrainement_place enable row level security;

create policy "entrainement_reglage: lecture par les joueurs connectes"
  on entrainement_reglage for select to authenticated using (true);
create policy "entrainement_reglage: ecriture admin"
  on entrainement_reglage for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "entrainement_place: lecture par les joueurs connectes"
  on entrainement_place for select to authenticated using (true);
create policy "entrainement_place: ecriture admin"
  on entrainement_place for all to authenticated
  using (is_admin()) with check (is_admin());

-- Choisir l'instructeur (bouton « Instructeur » de la fiche du mercenaire).
create function entrainement_choisir_instructeur(p_mercenaire uuid)
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
  insert into entrainement_place (role, position, mercenaire_id)
    values ('instructeur', 0, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Un instructeur vient d''etre place par un autre joueur.';
end;
$$;

-- Choisir un eleve (cellule « Choisir un eleve » du terrain d'entrainement).
create function entrainement_choisir_eleve(p_position integer, p_mercenaire uuid)
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

-- Renvoyer un mercenaire au dortoir. Reserve a son recruteur (ou a
-- l'administrateur). Renvoyer l'instructeur ramene aussi tous les eleves.
-- Le niveau acquis est deja sur le mercenaire : rien n'est perdu.
create function entrainement_renvoyer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  select role into v_role from entrainement_place where mercenaire_id = p_mercenaire;
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
    delete from entrainement_place;
  else
    delete from entrainement_place where mercenaire_id = p_mercenaire;
  end if;
end;
$$;

-- Debloquer une place eleve (le debit en pieces d'or reste cote application).
create function entrainement_debloquer_place()
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
  update entrainement_reglage
    set places_eleves = places_eleves + 1
    where places_eleves < 3
    returning places_eleves into v_places;
  if not found then
    raise exception 'Toutes les places eleves sont ouvertes.';
  end if;
  return v_places;
end;
$$;

-- +1 Instance (administrateur) : chaque eleve gagne 1 point de veterance ;
-- celui qui rejoint l'instructeur retourne au dortoir. L'instructeur reste.
-- Renvoie, pour chaque eleve : mercenaire_id, position, de (avant), a (apres),
-- gradue (true s'il retourne au dortoir).
create function entrainement_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_instr mercenaire%rowtype;
  r record;
  v_avant integer;
  v_apres integer;
  v_gradue boolean;
  v_gains jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  select m.* into v_instr
    from entrainement_place p join mercenaire m on m.id = p.mercenaire_id
    where p.role = 'instructeur';
  if not found then
    return v_gains;
  end if;
  for r in
    select p.position, m.id as mid, coalesce(m.veterance, 0) as vet
    from entrainement_place p join mercenaire m on m.id = p.mercenaire_id
    where p.role = 'eleve'
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
      'mercenaire_id', r.mid, 'position', r.position,
      'de', v_avant, 'a', v_apres, 'gradue', v_gradue);
  end loop;
  return v_gains;
end;
$$;

-- Annuler le dernier +1 Instance (administrateur) a partir de ce qu'il a
-- renvoye : remet la veterance d'avant (si elle n'a pas change depuis) et
-- replace les eleves renvoyes si leur place et l'instructeur sont libres.
create function entrainement_annuler_instance(p_gains jsonb)
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
    if (g ->> 'de')::integer <> (g ->> 'a')::integer then
      update mercenaire
        set veterance = (g ->> 'de')::integer
        where id = v_id and veterance = (g ->> 'a')::integer;
    end if;
    if (g ->> 'gradue')::boolean
       and exists (select 1 from entrainement_place where role = 'instructeur')
       and not exists (select 1 from entrainement_place where mercenaire_id = v_id)
       and not exists (
         select 1 from entrainement_place
         where role = 'eleve' and position = (g ->> 'position')::integer)
    then
      insert into entrainement_place (role, position, mercenaire_id)
        values ('eleve', (g ->> 'position')::integer, v_id);
    end if;
  end loop;
end;
$$;

-- Un mercenaire renvoye de la compagnie (recrutement supprime) quitte aussi
-- l'entrainement ; renvoye en tant qu'instructeur, il emmene ses eleves.
create function entrainement_apres_renvoi()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if exists (
    select 1 from entrainement_place
    where role = 'instructeur' and mercenaire_id = old.mercenaire_id
  ) then
    delete from entrainement_place;
  else
    delete from entrainement_place where mercenaire_id = old.mercenaire_id;
  end if;
  return old;
end;
$$;

create trigger recrutement_quitte_entrainement
  after delete on recrutement
  for each row execute function entrainement_apres_renvoi();

-- Droits : seules ces fonctions ecrivent ; le trigger n'est pas appelable.
revoke all on function entrainement_choisir_instructeur(uuid) from public;
revoke all on function entrainement_choisir_eleve(integer, uuid) from public;
revoke all on function entrainement_renvoyer(uuid) from public;
revoke all on function entrainement_debloquer_place() from public;
revoke all on function entrainement_instance() from public;
revoke all on function entrainement_annuler_instance(jsonb) from public;
revoke all on function entrainement_apres_renvoi() from public;
grant execute on function entrainement_choisir_instructeur(uuid) to authenticated;
grant execute on function entrainement_choisir_eleve(integer, uuid) to authenticated;
grant execute on function entrainement_renvoyer(uuid) to authenticated;
grant execute on function entrainement_debloquer_place() to authenticated;
grant execute on function entrainement_instance() to authenticated;
grant execute on function entrainement_annuler_instance(jsonb) to authenticated;

-- Mise a jour en direct chez tous les joueurs (Supabase Realtime) : le
-- terrain d'entrainement et les veterances des mercenaires.
do $$
begin
  alter publication supabase_realtime add table entrainement_place;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table entrainement_reglage;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table mercenaire;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
