-- Infirmerie : refus d'un mercenaire à 0 PV actuels (au moins 1 PV requis pour être placé).
create or replace function infirmerie_soigner(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_pos integer;
  v_sante integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recrute par vous.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est deja a l''infirmerie.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est a l''entrainement : renvoyez-le d''abord au dortoir.';
  end if;
  select places into v_places from infirmerie_reglage;
  select p into v_pos
    from generate_series(0, v_places - 1) as p
    where not exists (select 1 from infirmerie_place where position = p)
    order by p
    limit 1;
  if v_pos is null then
    raise exception 'Aucun lit libre a l''infirmerie.';
  end if;
  select e.sante_actuelle into v_sante
    from mercenaire_etat e
    where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session();
  -- Règle de Bruno (2026-09-29) : un mercenaire à 0 PV ne peut pas être placé à l'infirmerie, il lui
  -- faut au moins 1 PV (une potion de vie peut les lui rendre).
  if v_sante is not null and v_sante <= 0 then
    raise exception 'Un mercenaire à 0 PV ne peut pas être soigné à l''infirmerie : il lui faut au moins 1 PV.';
  end if;
  insert into infirmerie_place (position, mercenaire_id, restant)
    values (v_pos, p_mercenaire, greatest(1, _soins_instances(p_mercenaire, v_sante)));
exception
  when unique_violation then
    raise exception 'Ce lit vient d''etre pris par un autre joueur.';
end;
$$;

grant create on schema public to fortress_fn;
alter function infirmerie_soigner(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
