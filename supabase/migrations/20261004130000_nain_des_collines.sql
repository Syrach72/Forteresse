-- Compétence passive « Nain des Collines » (Bruno, 2026-10-04) : +1 point de Santé max par niveau de
-- vétérance au-delà du premier (vétérance 4 -> +3). Même principe que « Nain des Montagnes » : la
-- compétence doit figurer dans les passives du mercenaire sur une ligne de vétérance déjà atteinte, et
-- le bonus est CALCULÉ (jamais écrit), donc il suit la vétérance. Il s'ajoute à la Santé max serveur.

create function _bonus_sante(p_mercenaire uuid)
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
        and lower(btrim(o.nom)) = 'nain des collines')
    then greatest(0, _vet(p_mercenaire) - 1)
    else 0
  end;
$$;
revoke all on function _bonus_sante(uuid) from public;
grant execute on function _bonus_sante(uuid) to authenticated, fortress_fn;

create or replace function _sante_max(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select 3 + 2 * _puissance(p_mercenaire) + _bonus_sante(p_mercenaire);
$$;
