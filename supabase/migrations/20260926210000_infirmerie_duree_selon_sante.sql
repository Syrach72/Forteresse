-- Soins à l'infirmerie selon la santé perdue (Bruno, 2026-09-26).
--
-- Plus de durée fixe (5 instances) : la santé max est découpée en trois tiers.
--  * Chaque +1 Instance (MJ) rend un tiers de la santé max (arrondi à l'entier supérieur) sur la
--    santé actuelle de la fiche du mercenaire (mercenaire_etat.sante_actuelle, propre à la session).
--  * Le mercenaire retourne au dortoir dès que sa santé actuelle a rejoint sa santé max.
--  * Le compteur affiché (infirmerie_place.restant) = nombre d'instances encore nécessaires :
--    perte jusqu'à 1 tiers -> 1, jusqu'à 2 tiers -> 2, au-delà -> 3 (minimum 1 à l'arrivée).
--  * Si la santé est modifiée à la main sur la fiche pendant les soins, le compteur est recalculé
--    et le mercenaire sort aussitôt si sa santé a atteint le maximum.
-- Santé max = Puissance x vétérance (minimum 6), comme sur la fiche.

create or replace function _sante_max(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select greatest(6, coalesce(m.attaque, 0) * _vet(m.id)) from mercenaire m where m.id = p_mercenaire;
$$;

-- Instances de soins encore nécessaires pour une santé donnée (null = santé max) : 0 si pleine.
create or replace function _soins_instances(p_mercenaire uuid, p_sante integer)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select ceil(
    (m - greatest(0, least(coalesce(p_sante, m), m)))::numeric / ceil(m / 3.0)
  )::integer
  from (select _sante_max(p_mercenaire) as m) t;
$$;

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
  insert into infirmerie_place (position, mercenaire_id, restant)
    values (v_pos, p_mercenaire, greatest(1, _soins_instances(p_mercenaire, v_sante)));
exception
  when unique_violation then
    raise exception 'Ce lit vient d''etre pris par un autre joueur.';
end;
$$;

-- +1 Instance : chaque mercenaire soigné regagne un tiers de sa santé max ; à la santé max il quitte
-- l'infirmerie. Renvoie, pour chaque lit : mercenaire_id, position, de/a (compteur), sorti,
-- sante_de/sante_a (santé actuelle avant/après).
create or replace function infirmerie_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  v_max integer;
  v_avant integer;
  v_nouvelle integer;
  v_apres integer;
  v_gains jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for r in
    select position, mercenaire_id, restant
    from infirmerie_place
    order by position
    for update
  loop
    v_max := _sante_max(r.mercenaire_id);
    select e.sante_actuelle into v_avant
      from mercenaire_etat e
      where e.mercenaire_id = r.mercenaire_id and e.session_id = ctx_session();
    v_avant := greatest(0, least(coalesce(v_avant, v_max), v_max));
    v_nouvelle := least(v_max, v_avant + ceil(v_max / 3.0)::integer);
    insert into mercenaire_etat (session_id, mercenaire_id, veterance, sante_actuelle)
      values (ctx_session(), r.mercenaire_id, _vet(r.mercenaire_id), v_nouvelle)
      on conflict (session_id, mercenaire_id) do update set sante_actuelle = excluded.sante_actuelle;
    v_apres := _soins_instances(r.mercenaire_id, v_nouvelle);
    if v_apres = 0 then
      delete from infirmerie_place where mercenaire_id = r.mercenaire_id;
    else
      update infirmerie_place set restant = v_apres where mercenaire_id = r.mercenaire_id;
    end if;
    v_gains := v_gains || jsonb_build_object(
      'mercenaire_id', r.mercenaire_id, 'position', r.position,
      'de', r.restant, 'a', v_apres, 'sorti', v_apres = 0,
      'sante_de', v_avant, 'sante_a', v_nouvelle);
  end loop;
  return v_gains;
end;
$$;

create or replace function infirmerie_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
  v_id uuid;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    v_id := (g ->> 'mercenaire_id')::uuid;
    -- La santé rendue par cette instance est reprise (seulement si elle n'a pas bougé depuis).
    if g ? 'sante_de' and (g ->> 'sante_de') is distinct from (g ->> 'sante_a') then
      update mercenaire_etat
        set sante_actuelle = (g ->> 'sante_de')::integer
        where mercenaire_id = v_id and session_id = ctx_session()
          and sante_actuelle = (g ->> 'sante_a')::integer;
    end if;
    if (g ->> 'sorti')::boolean then
      if not exists (select 1 from infirmerie_place where mercenaire_id = v_id)
         and not exists (select 1 from entrainement_place where mercenaire_id = v_id)
         and not exists (
           select 1 from infirmerie_place
           where position = (g ->> 'position')::integer)
      then
        insert into infirmerie_place (position, mercenaire_id, restant)
          values ((g ->> 'position')::integer, v_id, (g ->> 'de')::integer);
      end if;
    else
      update infirmerie_place
        set restant = (g ->> 'de')::integer
        where mercenaire_id = v_id and restant = (g ->> 'a')::integer;
    end if;
  end loop;
end;
$$;

-- Santé actuelle modifiée sur la fiche : si le mercenaire est en soin, son compteur est recalculé et
-- il retourne au dortoir dès que sa santé a atteint le maximum.
create or replace function mercenaire_definir_actuel(p_mercenaire uuid, p_energie integer, p_sante integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_reste integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  if (p_energie is not null and (p_energie < 0 or p_energie > 9999))
     or (p_sante is not null and (p_sante < 0 or p_sante > 9999)) then
    raise exception 'Saisissez des entiers de 0 à 9999.';
  end if;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance, energie_actuelle, sante_actuelle)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire), p_energie, p_sante)
    on conflict (session_id, mercenaire_id) do update
      set energie_actuelle = excluded.energie_actuelle, sante_actuelle = excluded.sante_actuelle;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    v_reste := _soins_instances(p_mercenaire, p_sante);
    if v_reste = 0 then
      delete from infirmerie_place where mercenaire_id = p_mercenaire;
    else
      update infirmerie_place set restant = v_reste where mercenaire_id = p_mercenaire;
    end if;
  end if;
end;
$$;

grant create on schema public to fortress_fn;
alter function _sante_max(uuid) owner to fortress_fn;
alter function _soins_instances(uuid, integer) owner to fortress_fn;
alter function infirmerie_soigner(uuid) owner to fortress_fn;
alter function infirmerie_instance() owner to fortress_fn;
alter function infirmerie_annuler_instance(jsonb) owner to fortress_fn;
alter function mercenaire_definir_actuel(uuid, integer, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _sante_max(uuid) from public;
revoke all on function _soins_instances(uuid, integer) from public;
revoke all on function infirmerie_soigner(uuid) from public;
revoke all on function infirmerie_instance() from public;
revoke all on function infirmerie_annuler_instance(jsonb) from public;
revoke all on function mercenaire_definir_actuel(uuid, integer, integer) from public;
grant execute on function infirmerie_soigner(uuid) to authenticated;
grant execute on function infirmerie_instance() to authenticated;
grant execute on function infirmerie_annuler_instance(jsonb) to authenticated;
grant execute on function mercenaire_definir_actuel(uuid, integer, integer) to authenticated;
