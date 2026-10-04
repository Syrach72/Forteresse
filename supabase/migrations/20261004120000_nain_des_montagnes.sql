-- Compétence passive « Nain des Montagnes » (Bruno, 2026-10-04) : le mercenaire qui la possède gagne
-- +1 de Puissance aux vétérances 3, 6 et 9 (donc +1 à 3-5, +2 à 6-8, +3 à partir de 9).
-- « La possède » = elle figure dans son tableau de compétences passives sur une ligne de vétérance
-- déjà atteinte (comme pour toute compétence : une ligne se débloque quand la vétérance l'atteint).
--
-- Le bonus est CALCULÉ, jamais écrit : la Puissance saisie par le joueur (mercenaire_etat.attaque)
-- reste la valeur de base. Il suit donc la vétérance (gain de fin de quête, annulation du +1
-- Instance, réglage MJ) sans risque de compter deux fois. Il entre dans la Santé max serveur
-- (3 + 2 × Puissance) via _puissance().

create function _bonus_puissance(p_mercenaire uuid)
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
        and lower(btrim(o.nom)) = 'nain des montagnes')
    then (_vet(p_mercenaire) >= 3)::int + (_vet(p_mercenaire) >= 6)::int + (_vet(p_mercenaire) >= 9)::int
    else 0
  end;
$$;
revoke all on function _bonus_puissance(uuid) from public;
grant execute on function _bonus_puissance(uuid) to authenticated, fortress_fn;

create or replace function _puissance(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.attaque from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.attaque from mercenaire m where m.id = p_mercenaire),
    0) + _bonus_puissance(p_mercenaire);
$$;
