-- Ressourcement (Bruno, 2026-10-13) : le Druide transforme autant d'énergie qu'il le souhaite (1 à 10) en PV
-- temporaires pour lui-même. Une utilisation par instance et par terrain favori (inchangé).
--
--  * Même mécanique que les autres compétences à énergie : l'énergie choisie est dépensée par le serveur
--    (mercenaire_depenser_energie, refusée si insuffisante : rien n'est alors compté ni crédité).
--  * Les PV temporaires sont une ligne `mercenaire_effet` (stat 'pv_temp'), donc affichés et dépensés comme ceux des
--    missions : actifs tant que le mercenaire est engagé en quête, disparus à la fin de la quête.
--  * Pour une créature consentante touchée par le Druide, les PV restent à reporter à la main.

drop function ressourcement_utiliser(uuid, uuid);

create function ressourcement_utiliser(p_mercenaire uuid, p_competence uuid, p_montant integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_inst integer;
  v_total integer;
  v_n integer;
  v_nom text;
  v_merc text;
  v_classe text;
  v_sous text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_montant is null or p_montant < 1 or p_montant > 10 then
    raise exception 'Le montant à dépenser est un entier de 1 à 10.';
  end if;
  select m.nom, translate(lower(coalesce(c.nom, '')), 'êîéèô', 'eieeo'),
         translate(lower(btrim(coalesce(m.sous_classe, ''))), 'êîéèô', 'eieeo')
    into v_merc, v_classe, v_sous
    from mercenaire m left join classe c on c.id = m.classe_id
    where m.id = p_mercenaire;
  if v_classe <> 'druide' or v_sous <> 'cercle de la terre' then
    raise exception 'Seul un Druide du Cercle de la Terre peut utiliser le Ressourcement.';
  end if;
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
      and o.nom ~* 'ressourcement'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas le Ressourcement actif de ce mercenaire.';
  end if;
  select instance_courante into v_inst from partie_etat where session_id = ctx_session();
  v_inst := coalesce(v_inst, 0);
  select count(*) into v_total from mercenaire_terrain_favori
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  select count(*) into v_n from mercenaire_ressourcement
    where mercenaire_id = p_mercenaire and session_id = ctx_session() and instance_no = v_inst;
  if v_n >= v_total then
    raise exception 'Ressourcement : les % utilisation(s) de cette instance sont déjà dépensées.', v_total;
  end if;

  -- Dépense d'énergie (refusée si elle est insuffisante), puis crédit des PV temporaires.
  perform mercenaire_depenser_energie(p_mercenaire, p_montant);
  insert into mercenaire_effet (mercenaire_id, stat, valeur, quetes_restantes)
    values (p_mercenaire, 'pv_temp', p_montant, 1);
  insert into mercenaire_ressourcement (mercenaire_id, competence_id, instance_no)
    values (p_mercenaire, p_competence, v_inst);
  perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' : ' || p_montant || ' énergie(s) en PV temporaires ('
    || (v_n + 1) || ' / ' || v_total || ' cette instance).', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'competence_id', p_competence, 'ressourcement', v_n + 1,
      'pv_temp', p_montant));
  return jsonb_build_object('utilisees', v_n + 1, 'total', v_total, 'pv_temp', p_montant);
end;
$$;

grant create on schema public to fortress_fn;
alter function ressourcement_utiliser(uuid, uuid, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function ressourcement_utiliser(uuid, uuid, integer) from public;
grant execute on function ressourcement_utiliser(uuid, uuid, integer) to authenticated;
