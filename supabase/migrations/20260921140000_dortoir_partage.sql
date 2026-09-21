-- Dortoir PARTAGE : tous les joueurs voient les memes lits, chacun avec le nom
-- du joueur qui a recrute le mercenaire. Seule restriction (inchangee) : la
-- FICHE d'un mercenaire n'est ouverte que par son recruteur et par
-- l'administrateur (regle d'affichage de l'application).
--
-- * le numero de lit est attribue PAR LA BASE au recrutement (premier lit libre
--   parmi les places debloquees) : `recrutement.lit`, unique. Renvoyer un
--   mercenaire libere son lit, que le suivant reprend ; un mercenaire absent du
--   dortoir (entrainement, infirmerie) garde son lit ;
-- * la capacite est partagee (`dortoir_reglage`, 6 lits au depart, un 7e
--   deblocable pour 100 Po sur la tresorerie commune) ;
-- * `recrutement` devient lisible par tous les joueurs connectes (pour afficher
--   les lits et suivre les changements en direct) ; l'ecriture reste reservee
--   (chacun recrute et renvoie pour lui-meme).
-- Toute suppression/mise a jour a une clause WHERE (cf. 20260921110000).

create table dortoir_reglage (
  id boolean primary key default true check (id),
  places smallint not null default 6 check (places between 6 and 18)
);
insert into dortoir_reglage default values;
alter table dortoir_reglage enable row level security;
create policy "dortoir_reglage: lecture par les joueurs connectes"
  on dortoir_reglage for select to authenticated using (true);
create policy "dortoir_reglage: ecriture admin"
  on dortoir_reglage for all to authenticated
  using (is_admin()) with check (is_admin());

-- Numero de lit des recrutements deja faits : dans l'ordre de recrutement
-- (comme l'application les placait jusqu'ici).
alter table recrutement add column lit smallint;
update recrutement r
  set lit = x.n
  from (
    select mercenaire_id, (row_number() over (order by created_at, mercenaire_id) - 1)::smallint as n
    from recrutement
  ) x
  where r.mercenaire_id = x.mercenaire_id;
alter table recrutement
  alter column lit set not null,
  add constraint recrutement_lit_borne check (lit between 0 and 17),
  add constraint recrutement_lit_key unique (lit);

-- Lecture par tous les joueurs connectes (l'ancienne regle ne montrait que ses
-- propres recrutements).
drop policy "recrutement: lecture de ses recrutements (tous pour l'admin)" on recrutement;
create policy "recrutement: lecture par les joueurs connectes"
  on recrutement for select to authenticated using (true);

-- Attribution du lit a l'insertion ; refus s'il n'y en a plus de libre.
create function recrutement_attribuer_lit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_lit integer;
begin
  perform pg_advisory_xact_lock(hashtext('dortoir'));
  select places into v_places from dortoir_reglage;
  select p into v_lit
    from generate_series(0, v_places - 1) as p
    where not exists (select 1 from recrutement where lit = p)
    order by p
    limit 1;
  if v_lit is null then
    raise exception 'Aucun lit libre au Dortoir : libérez un lit ou débloquez-en un pour recruter.';
  end if;
  new.lit := v_lit;
  return new;
end;
$$;
create trigger recrutement_lit
  before insert on recrutement
  for each row execute function recrutement_attribuer_lit();

-- Debloquer le 7e lit : 100 Po prelevees sur la tresorerie partagee, dans la
-- meme operation.
create function dortoir_debloquer_place()
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
  update dortoir_reglage
    set places = places + 1
    where places < 7
    returning places into v_places;
  if not found then
    raise exception 'Cet emplacement est déjà débloqué.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - 100 where id;
  perform _journal('depense', 'Emplacement de dortoir débloqué : −100 Po.', -100, null);
  return v_places;
end;
$$;

revoke all on function recrutement_attribuer_lit() from public;
revoke all on function dortoir_debloquer_place() from public;
grant execute on function dortoir_debloquer_place() to authenticated;

-- Mise a jour en direct chez tous les joueurs (Supabase Realtime).
do $$
begin
  alter publication supabase_realtime add table recrutement;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table dortoir_reglage;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
