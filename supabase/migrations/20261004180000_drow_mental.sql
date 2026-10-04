-- Compétence passive « Drow » (Bruno, 2026-10-04) : même bonus de Mental que Haut-Elfe et Elfe Sylvestre,
-- +1 Mental tous les 3 niveaux de vétérance à partir du niveau 3. Reprend _bonus_mental() de
-- 20261004170000 en acceptant aussi cette compétence (pas de cumul : une seule race par mercenaire).

create or replace function _bonus_mental(p_mercenaire uuid)
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
        and lower(btrim(o.nom)) in ('haut-elfe', 'elfe sylvestre', 'drow'))
    then _vet(p_mercenaire) / 3
    else 0
  end;
$$;
