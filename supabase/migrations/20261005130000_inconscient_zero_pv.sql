-- Précision de Bruno (2026-10-05) sur 20261005120000 : la mort définitive ne concerne que le mercenaire à la
-- fois Inconscient ET à 0 PV. Passer à 0 PV (mercenaire engagé dans une quête) le rend automatiquement
-- Inconscient et lance le compte à rebours de 3 rounds ; un mercenaire Inconscient avec des PV n'a ni
-- message ni compte. Remonter au-dessus de 0 PV (soin) arrête le compte et ranime le mercenaire mort sur
-- le champ de bataille ; l'état Inconscient reste jusqu'à ce qu'on le retire.
--  * _inconscient_si_zero_pv : déclencheur sur mercenaire_etat (toute écriture de sante_actuelle).
--  * mercenaire_definir_etat : le compte ne démarre que si la santé actuelle est 0.
--  * Nettoyage : les comptes déjà lancés pour un mercenaire qui a des PV sont supprimés.

create or replace function _inconscient_si_zero_pv()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.sante_actuelle = 0 and (tg_op = 'INSERT' or old.sante_actuelle is distinct from 0) then
    if exists (select 1 from quete_mercenaire q
               where q.mercenaire_id = new.mercenaire_id and q.session_id = new.session_id) then
      new.etat := 'inconscient';
      new.etat_niveau := 1;
      new.etat_rounds := 0;
      new.etat_efface := null;
      new.etat_decremente := false;
      new.inconscient_rounds := 3;
      new.inconscient_dec := false;
      new.mort_champ := false;
    end if;
  elsif tg_op = 'UPDATE' and old.sante_actuelle = 0 and new.sante_actuelle is distinct from 0 then
    new.inconscient_rounds := null;
    new.inconscient_dec := false;
    new.mort_champ := false;
  end if;
  return new;
end;
$$;

create trigger mercenaire_etat_inconscient_zero_pv
  before insert or update of sante_actuelle on mercenaire_etat
  for each row execute function _inconscient_si_zero_pv();

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
  if p_etat not in ('abri_partiel', 'abri_total', 'affaibli', 'agrippe', 'assourdi', 'aveugle', 'charme', 'confus',
                    'desoriente', 'effraye', 'empoisonne', 'endormi', 'enrage', 'entrave', 'epuise', 'etourdi',
                    'fascine', 'fatigue', 'immobilise', 'inconscient', 'lenteur', 'muet', 'nauseeux', 'paralyse',
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

update mercenaire_etat
  set inconscient_rounds = null, inconscient_dec = false, mort_champ = false
  where sante_actuelle is distinct from 0 and (inconscient_rounds is not null or mort_champ);

grant create on schema public to fortress_fn;
alter function _inconscient_si_zero_pv() owner to fortress_fn;
alter function mercenaire_definir_etat(uuid, text, integer, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _inconscient_si_zero_pv() from public;
revoke all on function mercenaire_definir_etat(uuid, text, integer, integer) from public;
grant execute on function mercenaire_definir_etat(uuid, text, integer, integer) to authenticated;
