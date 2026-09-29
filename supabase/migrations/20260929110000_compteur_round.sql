-- Compteur de round (demande de Bruno, 2026-09-29) : bouton « RD » réservé à l'administrateur/MJ,
-- de 0 à 99. Chaque clic fait avancer le round de 1 et rend 1 point d'énergie actuelle à chaque
-- mercenaire recruté de la partie, sans dépasser son énergie max (2 × Mental). Énergie actuelle
-- vide (null) = énergie max : le mercenaire est déjà plein, il ne change pas.
-- Annuler recule le round de 1 et retire 1 point aux seuls mercenaires qui en avaient réellement
-- gagné (liste renvoyée par round_avancer), comme les autres annulations d'instance.

alter table partie_etat
  add column round_courant integer not null default 0
  check (round_courant between 0 and 99);

create or replace function round_avancer()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_round integer;
  v_gains jsonb := '[]'::jsonb;
  r record;
  v_max integer;
  v_act integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select round_courant into v_round from partie_etat where session_id = ctx_session() for update;
  if v_round >= 99 then
    raise exception 'Le compteur de round est déjà à 99.';
  end if;
  update partie_etat set round_courant = round_courant + 1
    where session_id = ctx_session()
    returning round_courant into v_round;
  for r in select distinct mercenaire_id from recrutement where session_id = ctx_session() loop
    v_max := 2 * _mental(r.mercenaire_id);
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), r.mercenaire_id, _vet(r.mercenaire_id))
      on conflict (session_id, mercenaire_id) do nothing;
    select coalesce(e.energie_actuelle, v_max) into v_act
      from mercenaire_etat e
      where e.session_id = ctx_session() and e.mercenaire_id = r.mercenaire_id
      for update;
    if v_act < v_max then
      update mercenaire_etat set energie_actuelle = v_act + 1
        where session_id = ctx_session() and mercenaire_id = r.mercenaire_id;
      v_gains := v_gains || to_jsonb(r.mercenaire_id);
    end if;
  end loop;
  return jsonb_build_object('round', v_round, 'gains', v_gains);
end;
$$;

create or replace function round_annuler(p_gains jsonb)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_round integer;
  g text;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  update partie_etat set round_courant = greatest(round_courant - 1, 0)
    where session_id = ctx_session()
    returning round_courant into v_round;
  for g in select jsonb_array_elements_text(coalesce(p_gains, '[]'::jsonb)) loop
    update mercenaire_etat set energie_actuelle = greatest(energie_actuelle - 1, 0)
      where session_id = ctx_session() and mercenaire_id = g::uuid and energie_actuelle is not null;
  end loop;
  return v_round;
end;
$$;

grant create on schema public to fortress_fn;
alter function round_avancer() owner to fortress_fn;
alter function round_annuler(jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function round_avancer() from public;
revoke all on function round_annuler(jsonb) from public;
grant execute on function round_avancer() to authenticated;
grant execute on function round_annuler(jsonb) to authenticated;
