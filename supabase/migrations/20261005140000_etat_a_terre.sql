-- Nouveaux états « À Terre », « Concentration » et « Flou » (Bruno, 2026-10-05), mercenaires et créatures : ajouté à la liste acceptée par
-- mercenaire_definir_etat (reste de la fonction : 20261005130000).

create or replace function mercenaire_definir_etat(
  p_mercenaire uuid, p_etat text, p_niveau integer default 1, p_rounds integer default 0)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_prev text;
  v_sante integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  select etat, sante_actuelle into v_prev, v_sante from mercenaire_etat
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  if p_etat is null then
    update mercenaire_etat
      set etat = null, etat_niveau = 1, etat_rounds = 0, etat_efface = null, etat_decremente = false,
          inconscient_rounds = null, inconscient_dec = false, mort_champ = false
      where session_id = ctx_session() and mercenaire_id = p_mercenaire;
    return;
  end if;
  if p_etat not in ('a_terre', 'abri_partiel', 'abri_total', 'affaibli', 'agrippe', 'assourdi', 'aveugle', 'charme', 'concentration', 'confus',
                    'desoriente', 'effraye', 'empoisonne', 'endormi', 'enrage', 'entrave', 'epuise', 'etourdi',
                    'fascine', 'fatigue', 'flou', 'immobilise', 'inconscient', 'lenteur', 'muet', 'nauseeux', 'paralyse',
                    'petrifie', 'possede', 'suffocation') then
    raise exception 'État inconnu.';
  end if;
  if p_niveau is null or p_niveau < 1 or p_niveau > 3 or (p_etat <> 'epuise' and p_niveau <> 1) then
    raise exception 'Niveau d''état invalide.';
  end if;
  if p_rounds is null or p_rounds < 0 or p_rounds > 9 then
    raise exception 'La durée est un nombre de rounds de 0 à 9.';
  end if;
  if not exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire n''est pas engagé dans une quête.';
  end if;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
    on conflict (session_id, mercenaire_id) do nothing;
  update mercenaire_etat
    set etat = p_etat, etat_niveau = p_niveau, etat_rounds = p_rounds, etat_efface = null, etat_decremente = false,
        inconscient_rounds = case when p_etat <> 'inconscient' or v_sante is distinct from 0 then null
                                  when v_prev = 'inconscient' then coalesce(inconscient_rounds, 3)
                                  else 3 end,
        inconscient_dec = case when p_etat = 'inconscient' and v_prev = 'inconscient' then inconscient_dec else false end,
        mort_champ = case when p_etat = 'inconscient' and v_prev = 'inconscient' then mort_champ else false end
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_definir_etat(uuid, text, integer, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_definir_etat(uuid, text, integer, integer) from public;
grant execute on function mercenaire_definir_etat(uuid, text, integer, integer) to authenticated;
