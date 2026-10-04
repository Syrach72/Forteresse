-- Nain des Collines (Bruno, 2026-10-04, correction) : +1 point de Santé max par niveau de vétérance, dès
-- le niveau 1 (vétérance 1 -> +1, vétérance 4 -> +4), et non au-delà du premier. Reprend _bonus_sante()
-- de 20261004130000 ; _sante_max() n'a pas à changer.

create or replace function _bonus_sante(p_mercenaire uuid)
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
    then _vet(p_mercenaire)
    else 0
  end;
$$;
