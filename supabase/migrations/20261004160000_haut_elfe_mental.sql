-- Compétence passive « Haut-Elfe » (Bruno, 2026-10-04) : +1 Mental tous les 3 niveaux de vétérance, à
-- partir du niveau 3 (3, 6, 9 -> +1 à 3-5, +2 à 6-8, +3 à partir de 9). Même principe que « Nain des
-- Montagnes » : la compétence doit figurer dans les passives du mercenaire sur une ligne de vétérance
-- déjà atteinte ; le bonus est CALCULÉ (jamais écrit) et entre dans _mental(), donc dans l'Énergie max
-- serveur (2 × Mental : dépense, Restauration Arcanique, potions, compteur de round).

create function _bonus_mental(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select case
    when exists (
      select 1 from mercenaire_competence mc
        join objet_catalogue o on o.id = mc.competence_id
      where mc.mercenaire_id = p_mercenaire
        and mc.type = 'passive'
        and mc.veterance <= _vet(p_mercenaire)
        and lower(btrim(o.nom)) = 'haut-elfe')
    then _vet(p_mercenaire) / 3
    else 0
  end;
$$;
revoke all on function _bonus_mental(uuid) from public;
grant execute on function _bonus_mental(uuid) to authenticated, fortress_fn;

create or replace function _mental(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.esprit from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.esprit from mercenaire m where m.id = p_mercenaire),
    0) + _bonus_mental(p_mercenaire);
$$;
