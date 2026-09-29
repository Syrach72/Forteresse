-- Dépense d'énergie depuis la fenêtre d'une compétence active (demande de Bruno, 2026-09-29) :
-- le joueur choisit un montant de 1 à 10 et confirme ; l'énergie actuelle du mercenaire baisse
-- d'autant. L'énergie n'est plus saisie à la main sur la fiche (le rechargement viendra plus tard).
-- Énergie actuelle vide (null) = énergie max (2 × Mental de la session), comme sur la fiche.
-- Le retrait est fait côté base en une seule instruction, sans lecture préalable côté navigateur.
create or replace function mercenaire_depenser_energie(p_mercenaire uuid, p_montant integer)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_max integer;
  v_actuelle integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  if p_montant is null or p_montant < 1 or p_montant > 10 then
    raise exception 'Le montant à dépenser est un entier de 1 à 10.';
  end if;
  v_max := 2 * _mental(p_mercenaire);
  -- Ligne d'état créée si besoin, puis verrouillée pour éviter deux dépenses simultanées.
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
    on conflict (session_id, mercenaire_id) do nothing;
  select coalesce(e.energie_actuelle, v_max) into v_actuelle
    from mercenaire_etat e
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire
    for update;
  if v_actuelle < p_montant then
    raise exception 'Énergie insuffisante : % disponible(s), % demandée(s).', v_actuelle, p_montant;
  end if;
  update mercenaire_etat
    set energie_actuelle = v_actuelle - p_montant
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  return v_actuelle - p_montant;
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_depenser_energie(uuid, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_depenser_energie(uuid, integer) from public;
grant execute on function mercenaire_depenser_energie(uuid, integer) to authenticated;
