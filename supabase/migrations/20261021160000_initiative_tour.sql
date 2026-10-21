-- Barre d'initiative (Bruno, 2026-10-21), comme dans un jeu de rôle vidéo : une barre fixe en haut de l'écran montre, de gauche à
-- droite, l'ordre des tours (meilleure initiative → moins bonne), mercenaires ET créatures. Chacun clique « Fin de tour » : son
-- icône passe à droite de la barre et se grise jusqu'à ce que le MJ clique sur Rd (qui rend la barre active pour un nouveau tour).
--
--  * `initiative_tour` : une ligne par participant, créée quand l'initiative est classée (rang attribué). Lisible par toute la
--    session (l'ordre et le titre d'onglet des créatures sont publics ; le jet reste secret dans `initiative`).
--  * `joue_ordre` : null = n'a pas encore joué ce tour ; sinon numéro d'ordre de fin de tour (les icônes grisées se rangent à
--    droite dans l'ordre où elles ont fini).
--  * Rd : tout le monde redevient actif ; l'annulation du Rd restitue l'état précédent (`joue_prec`).
--  * Un mercenaire qui quitte la quête (mort, retrait, fin) disparaît de la barre.
-- Les déclencheurs restent propriété de postgres (comme _initiative_cycle) : ils agissent sur la session de la ligne modifiée.

create table initiative_tour (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  initiative_id uuid not null references initiative (id) on delete cascade,
  kind text not null check (kind in ('mercenaire', 'creature')),
  mercenaire_id uuid references mercenaire (id) on delete cascade,
  creature_quete_id uuid references creature_quete (id) on delete cascade,
  label text,
  rang smallint not null,
  joue_ordre integer,
  joue_prec integer,
  unique (initiative_id)
);
alter table initiative_tour enable row level security;
create policy "initiative_tour: lecture" on initiative_tour for select to authenticated
  using (session_id = ctx_session());
create policy "initiative_tour: fonctions serveur" on initiative_tour for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select on initiative_tour to authenticated;
grant select, insert, update, delete on initiative_tour to fortress_fn;
revoke all on initiative_tour from anon;
do $$
begin
  alter publication supabase_realtime add table initiative_tour;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- Quand le classement attribue un rang, le participant entre dans la barre.
create function _initiative_tour_ajouter()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.rang is not null and old.rang is null then
    insert into initiative_tour (session_id, initiative_id, kind, mercenaire_id, creature_quete_id, label, rang)
      values (new.session_id, new.id, new.kind, new.mercenaire_id, new.creature_quete_id,
        (select c.nom_onglet from creature_quete c where c.id = new.creature_quete_id), new.rang)
      on conflict (initiative_id) do update set rang = excluded.rang;
  end if;
  return new;
end;
$$;
create trigger initiative_tour_ajouter
  after update of rang on initiative
  for each row execute function _initiative_tour_ajouter();

-- Un mercenaire qui quitte la quête sort de la barre.
create function _initiative_tour_retirer_merc()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from initiative_tour where session_id = old.session_id and mercenaire_id = old.mercenaire_id;
  return old;
end;
$$;
create trigger quete_mercenaire_initiative_tour
  after delete on quete_mercenaire
  for each row execute function _initiative_tour_retirer_merc();

-- Rd : nouveau tour (tout le monde redevient actif) ; annulation du Rd : on restitue.
create function _initiative_tour_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = old.round_courant + 1 then
    update initiative_tour set joue_prec = joue_ordre, joue_ordre = null where session_id = new.session_id;
  elsif new.round_courant = old.round_courant - 1 then
    update initiative_tour set joue_ordre = joue_prec, joue_prec = null where session_id = new.session_id;
  end if;
  return new;
end;
$$;
create trigger partie_etat_initiative_tour
  after update of round_courant on partie_etat
  for each row execute function _initiative_tour_round();

-- « Fin de tour » : le mercenaire (son joueur ou le MJ) ou la créature (MJ) passe à droite de la barre et se grise.
create function initiative_fin_tour(p_kind text, p_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_joue integer;
begin
  perform _verrou_partie();
  if p_kind = 'mercenaire' then
    perform _droit_mercenaire(p_id);
    select id, joue_ordre into v_id, v_joue from initiative_tour
      where session_id = ctx_session() and mercenaire_id = p_id for update;
  elsif p_kind = 'creature' then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    select id, joue_ordre into v_id, v_joue from initiative_tour
      where session_id = ctx_session() and creature_quete_id = p_id for update;
  else
    raise exception 'Participant inconnu.';
  end if;
  if v_id is null then
    raise exception 'Ce participant n''est pas dans l''ordre d''initiative.';
  end if;
  if v_joue is not null then
    raise exception 'Tour déjà terminé : attendez le prochain Rd.';
  end if;
  update initiative_tour
    set joue_ordre = coalesce((select max(t.joue_ordre) from initiative_tour t where t.session_id = ctx_session()), 0) + 1
    where id = v_id;
end;
$$;

grant create on schema public to fortress_fn;
alter function initiative_fin_tour(text, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function initiative_fin_tour(text, uuid) from public, anon;
grant execute on function initiative_fin_tour(text, uuid) to authenticated;
revoke all on function _initiative_tour_ajouter() from public, anon, authenticated;
revoke all on function _initiative_tour_retirer_merc() from public, anon, authenticated;
revoke all on function _initiative_tour_round() from public, anon, authenticated;

-- Reprise des classements déjà faits (initiative en cours au moment de la migration).
insert into initiative_tour (session_id, initiative_id, kind, mercenaire_id, creature_quete_id, label, rang)
  select i.session_id, i.id, i.kind, i.mercenaire_id, i.creature_quete_id,
    (select c.nom_onglet from creature_quete c where c.id = i.creature_quete_id), i.rang
  from initiative i where i.rang is not null;
