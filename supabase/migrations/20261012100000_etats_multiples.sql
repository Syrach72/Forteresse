-- États multiples (Bruno, 2026-10-12) : un mercenaire, une créature, un compagnon animal ou un familier peut cumuler
-- jusqu'à TROIS états en même temps (par exemple Fasciné et Épuisé), chacun avec ses propres rounds restants.
--
-- * Le premier état reste dans les colonnes historiques (etat, etat_niveau, etat_rounds, etc.) : toute la logique
--   existante (Inconscient, 0 PV, mort sur le champ de bataille, Rd, annulation du Rd) continue de s'y appliquer.
--   L'Inconscient reste donc toujours le premier état.
-- * Les deux états supplémentaires sont dans `etat_supplementaire` (position 1 ou 2), avec la même mécanique :
--   chaque Rd retire 1 round (0 = sans durée) ; à 0 l'état disparaît, mémorisé dans `efface` pour qu'« Annuler » le
--   Rd le rende.
-- * Quitter la quête (mercenaire) ou la disparition d'une créature efface ses états supplémentaires.
-- * Écriture uniquement par la fonction etats_sup_definir (droit sur le mercenaire, ou MJ pour une créature).

create table etat_supplementaire (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  cible text not null check (cible in ('mercenaire', 'compagnon', 'creature')),
  cible_id uuid not null,
  position smallint not null check (position between 1 and 2),
  etat text check (etat is null or length(etat) <= 30),
  niveau smallint not null default 1 check (niveau between 1 and 3),
  rounds smallint not null default 0 check (rounds between 0 and 9),
  efface text,
  decremente boolean not null default false,
  unique (session_id, cible, cible_id, position)
);
alter table etat_supplementaire enable row level security;
create policy "etat_supplementaire: lecture" on etat_supplementaire for select to authenticated
  using (session_id = ctx_session());
create policy "etat_supplementaire: fonctions serveur" on etat_supplementaire for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select on etat_supplementaire to authenticated;
grant select, insert, update, delete on etat_supplementaire to fortress_fn;
revoke all on etat_supplementaire from anon;

do $$
begin
  alter publication supabase_realtime add table etat_supplementaire;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- Définit les états supplémentaires (0 à 2) d'une cible ; remplace la liste précédente.
create function etats_sup_definir(p_cible text, p_id uuid, p_liste jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  e jsonb;
  i integer := 0;
  v_etat text;
  v_niveau integer;
  v_rounds integer;
  v_vus text[] := '{}';
begin
  perform _verrou_partie();
  if p_cible = 'creature' then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    if not exists (select 1 from creature_quete where id = p_id and session_id = ctx_session()) then
      raise exception 'Créature inconnue.';
    end if;
  elsif p_cible in ('mercenaire', 'compagnon') then
    perform _droit_mercenaire(p_id);
    if not exists (select 1 from quete_mercenaire where mercenaire_id = p_id) then
      raise exception 'Ce mercenaire n''est pas engagé dans une quête.';
    end if;
    if p_cible = 'compagnon'
       and not exists (select 1 from mercenaire_compagnon where mercenaire_id = p_id and session_id = ctx_session()) then
      raise exception 'Ce mercenaire n''a pas de compagnon.';
    end if;
  else
    raise exception 'Cible inconnue.';
  end if;
  if p_liste is null or jsonb_typeof(p_liste) <> 'array' or jsonb_array_length(p_liste) > 2 then
    raise exception 'Trois états au maximum en même temps.';
  end if;
  delete from etat_supplementaire where session_id = ctx_session() and cible = p_cible and cible_id = p_id;
  for e in select * from jsonb_array_elements(p_liste) loop
    v_etat := e ->> 'etat';
    v_niveau := coalesce((e ->> 'niveau')::integer, 1);
    v_rounds := coalesce((e ->> 'rounds')::integer, 0);
    if v_etat is null or v_etat not in ('a_terre', 'abri_partiel', 'abri_total', 'affaibli', 'agrippe', 'assourdi',
        'aveugle', 'charme', 'concentration', 'confus', 'desoriente', 'effraye', 'empoisonne', 'endormi', 'enrage',
        'entrave', 'epuise', 'etourdi', 'fascine', 'fatigue', 'flou', 'immobilise', 'lenteur', 'muet', 'nauseeux',
        'paralyse', 'petrifie', 'possede', 'suffocation') then
      raise exception 'État inconnu (l''Inconscient est toujours le premier état).';
    end if;
    if v_etat = any (v_vus) then
      raise exception 'Le même état ne peut pas être appliqué deux fois.';
    end if;
    if v_niveau < 1 or v_niveau > 3 or (v_etat <> 'epuise' and v_niveau <> 1) then
      raise exception 'Niveau d''état invalide.';
    end if;
    if v_rounds < 0 or v_rounds > 9 then
      raise exception 'La durée est un nombre de rounds de 0 à 9.';
    end if;
    i := i + 1;
    insert into etat_supplementaire (cible, cible_id, position, etat, niveau, rounds)
      values (p_cible, p_id, i, v_etat, v_niveau, v_rounds);
    v_vus := v_vus || v_etat;
  end loop;
end;
$$;

-- Rd : chaque état supplémentaire perd 1 round ; à 0 il disparaît (mémorisé pour annuler le Rd).
-- Propriétaire postgres, comme _creatures_round : il s'exécute pour la session de la ligne modifiée.
create function _etats_sup_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = old.round_courant + 1 then
    update etat_supplementaire set decremente = false, efface = null
      where session_id = new.session_id and (decremente or efface is not null);
    delete from etat_supplementaire where session_id = new.session_id and etat is null;
    update etat_supplementaire
      set rounds = rounds - 1, decremente = true,
          efface = case when rounds = 1 then etat end,
          etat = case when rounds = 1 then null else etat end
      where session_id = new.session_id and etat is not null and rounds > 0;
  elsif new.round_courant = old.round_courant - 1 then
    update etat_supplementaire
      set rounds = least(rounds + 1, 9), decremente = false,
          etat = coalesce(etat, efface), efface = null
      where session_id = new.session_id and decremente;
  end if;
  return new;
end;
$$;
create trigger partie_etat_round_etats_sup
  after update of round_courant on partie_etat
  for each row execute function _etats_sup_round();

-- Un mercenaire qui quitte la quête perd ses états supplémentaires (et ceux de son compagnon) ; une créature
-- supprimée aussi.
create function _etats_sup_apres_quete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from etat_supplementaire
    where session_id = old.session_id and cible in ('mercenaire', 'compagnon') and cible_id = old.mercenaire_id;
  return old;
end;
$$;
create trigger quete_mercenaire_etats_sup
  after delete on quete_mercenaire
  for each row execute function _etats_sup_apres_quete();

create function _etats_sup_creature_supprimee()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from etat_supplementaire
    where session_id = old.session_id and cible = 'creature' and cible_id = old.id;
  return old;
end;
$$;
create trigger creature_quete_etats_sup
  after delete on creature_quete
  for each row execute function _etats_sup_creature_supprimee();

grant create on schema public to fortress_fn;
alter function etats_sup_definir(text, uuid, jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function etats_sup_definir(text, uuid, jsonb) from public;
grant execute on function etats_sup_definir(text, uuid, jsonb) to authenticated;
-- Les trois fonctions de déclencheur restent propriété de postgres (comme _creatures_round).
revoke all on function _etats_sup_round() from public;
revoke all on function _etats_sup_apres_quete() from public;
revoke all on function _etats_sup_creature_supprimee() from public;
