-- +1 Instance : l'énergie de TOUS les mercenaires revient à son maximum (Bruno, 2026-09-30).
-- Avant, seule la fin d'une quête remettait l'énergie au maximum, et seulement pour les mercenaires
-- engagés. Ici, à chaque +1 Instance, toute énergie actuelle enregistrée (mercenaire_etat.energie_actuelle
-- non nulle) est remise à « vide » = maximum. Les valeurs d'avant sont renvoyées pour que l'annulation
-- du +1 Instance puisse les rétablir (seulement si l'énergie n'a pas été modifiée depuis).

create or replace function energie_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_gains jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select coalesce(jsonb_agg(jsonb_build_object('mercenaire_id', mercenaire_id, 'energie_avant', energie_actuelle)), '[]'::jsonb)
    into v_gains
    from mercenaire_etat
    where session_id = ctx_session() and energie_actuelle is not null;
  update mercenaire_etat set energie_actuelle = null
    where session_id = ctx_session() and energie_actuelle is not null;
  if jsonb_array_length(v_gains) > 0 then
    perform _journal('or',
      'Nouvelle instance : l''énergie de ' || jsonb_array_length(v_gains) || ' mercenaire(s) revient au maximum.',
      0, jsonb_build_object('energie_instance', jsonb_array_length(v_gains)));
  end if;
  return v_gains;
end;
$$;

create or replace function energie_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  i jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_gains is null then
    return;
  end if;
  perform _verrou_partie();
  for i in select * from jsonb_array_elements(p_gains)
  loop
    update mercenaire_etat
      set energie_actuelle = (i ->> 'energie_avant')::integer
      where mercenaire_id = (i ->> 'mercenaire_id')::uuid and session_id = ctx_session()
        and energie_actuelle is null;
  end loop;
end;
$$;

grant create on schema public to fortress_fn;
alter function energie_instance() owner to fortress_fn;
alter function energie_annuler_instance(jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function energie_instance() from public;
revoke all on function energie_annuler_instance(jsonb) from public;
grant execute on function energie_instance() to authenticated;
grant execute on function energie_annuler_instance(jsonb) to authenticated;
