-- Forme Sauvage : la bête devient un réglage INDÉPENDANT du compagnon (Bruno, 2026-10-13).
-- Une même fiche peut servir de compagnon à un joueur ET de forme sauvage à un autre : `creature.forme_sauvage`
-- (2 / 5 / 8 = vétérance minimale du Druide) remplace les étiquettes 'forme_sauvage_N' de `creature.compagnon`.

alter table creature add column forme_sauvage smallint check (forme_sauvage in (2, 5, 8));

-- Reprise des étiquettes posées par la migration précédente, puis retour de la contrainte d'origine.
update creature
  set forme_sauvage = substring(compagnon from '([0-9]+)$')::smallint, compagnon = null
  where compagnon like 'forme\_sauvage\_%';
alter table creature drop constraint creature_compagnon_check;
alter table creature add constraint creature_compagnon_check
  check (compagnon in ('faucon', 'chien', 'panthere', 'familier'));

-- Une fiche de bête (ou de compagnon) est lisible par les joueurs, avec ses capacités et ses armes.
drop policy "creature: lecture compagnons" on creature;
create policy "creature: lecture compagnons" on creature for select to authenticated
  using ((compagnon is not null or forme_sauvage is not null) and actif);

create or replace function _creature_est_compagnon(p_creature uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from creature
      where id = p_creature and (compagnon is not null or forme_sauvage is not null) and actif);
$$;

-- Prendre la forme : la bête est lue dans `forme_sauvage` (palier) et non plus dans l'étiquette de compagnon.
create or replace function forme_sauvage_activer(p_mercenaire uuid, p_competence uuid, p_creature uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_inst integer;
  v_classe text;
  v_palier integer;
  v_pv integer;
  v_nom_creature text;
  v_merc text;
  v_rounds integer;
  v_ligne mercenaire_forme_sauvage%rowtype;
  v_usages integer := 0;
  v_existe boolean;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  v_vet := _vet(p_mercenaire);
  select m.nom, translate(lower(coalesce(c.nom, '')), 'êîéèô', 'eieeo')
    into v_merc, v_classe
    from mercenaire m left join classe c on c.id = m.classe_id
    where m.id = p_mercenaire;
  if v_classe <> 'druide' then
    raise exception 'Seul un Druide peut prendre la forme sauvage.';
  end if;
  if not exists (
    select 1 from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
      where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
        and mc.veterance <= v_vet and o.nom ~* '(forme|force) sauvage'
  ) then
    raise exception 'Cette compétence n''est pas la Forme Sauvage active de ce mercenaire.';
  end if;
  select forme_sauvage, nom, sante_max into v_palier, v_nom_creature, v_pv
    from creature where id = p_creature and actif;
  if v_palier is null then
    raise exception 'Cette bête n''est pas disponible pour la forme sauvage.';
  end if;
  if v_palier > v_vet then
    raise exception 'Cette bête demande la vétérance %.', v_palier;
  end if;

  select * into v_ligne from mercenaire_forme_sauvage
    where mercenaire_id = p_mercenaire and session_id = ctx_session() for update;
  v_existe := found;
  if v_existe and v_ligne.actif then
    raise exception 'Ce mercenaire est déjà sous forme sauvage.';
  end if;
  select instance_courante into v_inst from partie_etat where session_id = ctx_session();
  v_inst := coalesce(v_inst, 0);
  if v_existe and v_ligne.instance_no = v_inst then
    v_usages := v_ligne.usages;
  end if;
  if v_usages >= 2 then
    raise exception 'Forme Sauvage : les 2 utilisations de cette instance sont déjà dépensées.';
  end if;
  v_rounds := greatest(2 * _mental(p_mercenaire), 1);

  perform mercenaire_depenser_energie(p_mercenaire, 2);

  insert into mercenaire_forme_sauvage
    (mercenaire_id, creature_id, actif, rounds_restants, rounds_total, dernier_rd, instance_no, usages, sante_actuelle)
    values (p_mercenaire, p_creature, true, v_rounds, v_rounds, false, v_inst, v_usages + 1, v_pv)
    on conflict (session_id, mercenaire_id) do update set
      creature_id = excluded.creature_id, actif = true, rounds_restants = excluded.rounds_restants,
      rounds_total = excluded.rounds_total, dernier_rd = false, instance_no = excluded.instance_no,
      usages = excluded.usages, sante_actuelle = excluded.sante_actuelle, energie_actuelle = null,
      etat = null, etat_niveau = 1, etat_rounds = 0, commentaires = '';
  perform _journal('equipement', v_merc || ' prend la forme sauvage : ' || v_nom_creature || ' (' || v_rounds || ' rounds, '
    || (v_usages + 1) || ' / 2 cette instance).', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'forme_sauvage', v_nom_creature));
  return jsonb_build_object('rounds', v_rounds, 'utilisees', v_usages + 1);
end;
$$;
