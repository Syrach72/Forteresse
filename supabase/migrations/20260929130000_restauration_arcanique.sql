-- Compétence « Restauration Arcanique » (Mage) : rend de l'énergie selon la vétérance du mercenaire
-- (1 : +2, 4 : +3, 7 : +4, 10 : +5), sans dépasser l'énergie max (2 × Mental). Le palier est
-- calculé par le serveur à partir de la vétérance ; renvoie l'énergie réellement gagnée.
create or replace function mercenaire_restauration_arcanique(p_mercenaire uuid)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_gain integer;
  v_max integer;
  v_act integer;
  v_nouvelle integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  v_vet := _vet(p_mercenaire);
  v_gain := case when v_vet >= 10 then 5 when v_vet >= 7 then 4 when v_vet >= 4 then 3 else 2 end;
  v_max := 2 * _mental(p_mercenaire);
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, v_vet)
    on conflict (session_id, mercenaire_id) do nothing;
  select coalesce(e.energie_actuelle, v_max) into v_act
    from mercenaire_etat e
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire
    for update;
  v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
  update mercenaire_etat set energie_actuelle = v_nouvelle
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  return v_nouvelle - v_act;
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_restauration_arcanique(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_restauration_arcanique(uuid) from public;
grant execute on function mercenaire_restauration_arcanique(uuid) to authenticated;
