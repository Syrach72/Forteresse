-- Halflins (Bruno, 2026-10-04) : à partir du niveau 3, +1 tous les 3 niveaux de vétérance.
--  * « Halflin Robuste » : +1 PUISSANCE (rejoint Nain des Montagnes et Semi-Orc dans _bonus_puissance).
--  * « Halflin Pied Léger » : +1 VÉLOCITÉ, comme l'écrit sa description dans le catalogue
--    (nouveau _bonus_velocite, ajouté à _velocite()).
-- Bonus calculés, jamais écrits ; la compétence doit être dans les passives sur une ligne de vétérance atteinte.

create or replace function _bonus_puissance(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select case
    when _possede_competence(p_mercenaire, array['nain des montagnes', 'semi-orc', 'halflin robuste'])
    then _vet(p_mercenaire) / 3
    else 0
  end;
$$;

create function _bonus_velocite(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select case
    when _possede_competence(p_mercenaire, array['halflin pied léger'])
    then _vet(p_mercenaire) / 3
    else 0
  end;
$$;
revoke all on function _bonus_velocite(uuid) from public;
grant execute on function _bonus_velocite(uuid) to authenticated, fortress_fn;

create or replace function _velocite(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.defense from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.defense from mercenaire m where m.id = p_mercenaire),
    0) + _bonus_velocite(p_mercenaire);
$$;
