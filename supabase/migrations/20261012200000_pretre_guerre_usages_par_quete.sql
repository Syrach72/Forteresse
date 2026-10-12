-- Prêtre de Guerre (Bruno, 2026-10-12) : cette compétence active ne s'utilise, dans une même QUÊTE (pas une instance),
-- par le même mercenaire, qu'un nombre de fois égal à sa Puissance (bonus et effets temporaires compris).
--
-- * Le décompte est porté par la ligne d'engagement du mercenaire dans la quête (quete_mercenaire) : il repart de zéro
--   quand le mercenaire quitte la quête (fin de quête, échec, retrait) ou qu'une nouvelle quête commence, comme la
--   réaction et les états.
-- * Hors quête (mercenaire non engagé) aucun décompte n'est tenu : il n'y a pas de quête à laquelle le rattacher.
-- * Chaque validation compte une utilisation ET dépense l'énergie choisie, en une seule opération serveur.

alter table quete_mercenaire add column usages_competence jsonb not null default '{}'::jsonb;

create or replace function competence_quete_utiliser(p_mercenaire uuid, p_competence uuid, p_montant integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_nom text;
  v_total integer;
  v_n integer := 0;
  v_en_quete boolean;
  v_usages jsonb;
  v_merc text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
      and o.nom ~* 'pr[êe]tre de guerre'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas une compétence Prêtre de Guerre active de ce mercenaire.';
  end if;
  v_total := greatest(_puissance(p_mercenaire), 0);
  select usages_competence into v_usages
    from quete_mercenaire
    where mercenaire_id = p_mercenaire and session_id = ctx_session()
    for update;
  v_en_quete := found;
  if v_en_quete then
    v_n := coalesce((v_usages ->> p_competence::text)::integer, 0);
    if v_n >= v_total then
      raise exception 'Prêtre de Guerre : les % utilisation(s) de cette quête sont déjà dépensées.', v_total;
    end if;
  end if;
  -- Dépense d'énergie (refusée si elle est insuffisante : rien n'est alors compté).
  perform mercenaire_depenser_energie(p_mercenaire, p_montant);
  if v_en_quete then
    update quete_mercenaire
      set usages_competence = jsonb_set(usages_competence, array[p_competence::text], to_jsonb(v_n + 1))
      where mercenaire_id = p_mercenaire and session_id = ctx_session();
    select nom into v_merc from mercenaire where id = p_mercenaire;
    perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' (' || (v_n + 1) || ' / ' || v_total || ' cette quête).', 0,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'competence_id', p_competence, 'utilisation_quete', v_n + 1));
  end if;
  return jsonb_build_object('utilisees', v_n + case when v_en_quete then 1 else 0 end, 'total', v_total, 'en_quete', v_en_quete);
end;
$$;

grant create on schema public to fortress_fn;
alter function competence_quete_utiliser(uuid, uuid, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function competence_quete_utiliser(uuid, uuid, integer) from public;
grant execute on function competence_quete_utiliser(uuid, uuid, integer) to authenticated;
