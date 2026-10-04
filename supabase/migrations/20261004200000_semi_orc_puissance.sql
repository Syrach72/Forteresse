-- Compétence passive « Semi-Orc » (Bruno, 2026-10-04) : +1 Puissance tous les 3 niveaux de vétérance, à
-- partir du niveau 3, comme « Nain des Montagnes » (dont la description dit désormais la même chose).
-- Reprend _bonus_puissance() de 20261004120000 : les deux compétences donnent vétérance ÷ 3 (arrondi
-- inférieur). Identique à l'ancien palier 3/6/9 jusqu'à la vétérance 11 (la grille de compétences
-- s'arrête à 10).

create or replace function _bonus_puissance(p_mercenaire uuid)
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
        and lower(btrim(o.nom)) in ('nain des montagnes', 'semi-orc'))
    then _vet(p_mercenaire) / 3
    else 0
  end;
$$;
