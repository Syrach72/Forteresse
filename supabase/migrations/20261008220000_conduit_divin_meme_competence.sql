-- Conduit Divin (Bruno, 2026-10-08) : précision de la règle.
--  * Les 2 ou 3 utilisations d'une instance peuvent être celles de la MÊME compétence CD : plus de limite par compétence,
--    seulement le total par instance (1 / 2 / 3 selon la vétérance 1 / 4 / 8).
--  * Annuler un +1 Instance s'applique comme pour le reste : les utilisations faites pendant l'instance annulée
--    rejoignent l'instance précédente (même traitement que les lignes du journal, journal_instance_annuler).

do $$
declare
  c record;
begin
  for c in select conname from pg_constraint
    where conrelid = 'mercenaire_conduit_divin'::regclass and contype = 'u'
  loop
    execute format('alter table mercenaire_conduit_divin drop constraint %I', c.conname);
  end loop;
end;
$$;

create or replace function conduit_divin_utiliser(p_mercenaire uuid, p_competence uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_inst integer;
  v_total integer;
  v_n integer;
  v_nom text;
  v_merc text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select instance_courante into v_inst from partie_etat where session_id = ctx_session();
  v_inst := coalesce(v_inst, 0);
  select o.nom into v_nom
    from mercenaire_competence mc join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire and mc.competence_id = p_competence and mc.type = 'active'
      and mc.veterance <= _vet(p_mercenaire)
      and o.nom ~ '(^|[^A-Za-z])CD([^A-Za-z]|$)'
    limit 1;
  if v_nom is null then
    raise exception 'Cette compétence n''est pas une compétence Conduit Divin (CD) active de ce mercenaire.';
  end if;
  v_vet := _vet(p_mercenaire);
  v_total := 1 + (v_vet >= 4)::integer + (v_vet >= 8)::integer;
  select count(*) into v_n from mercenaire_conduit_divin
    where session_id = ctx_session() and mercenaire_id = p_mercenaire and instance_no = v_inst;
  if v_n >= v_total then
    raise exception 'Conduit Divin : les % utilisation(s) de cette instance sont déjà dépensées.', v_total;
  end if;
  insert into mercenaire_conduit_divin (mercenaire_id, competence_id, instance_no)
    values (p_mercenaire, p_competence, v_inst);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_merc || ' utilise ' || v_nom || ' (Conduit Divin : ' || (v_n + 1) || ' / ' || v_total || ').', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'competence_id', p_competence, 'conduit_divin', v_n + 1));
  return jsonb_build_object('utilisees', v_n + 1, 'total', v_total);
end;
$$;

create or replace function journal_instance_annuler()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_instance integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  update partie_etat set instance_courante = greatest(instance_courante - 1, 0)
    where id and session_id = ctx_session()
    returning instance_courante into v_instance;
  update partie_journal set instance_no = v_instance
    where session_id = ctx_session() and instance_no > v_instance;
  -- Conduit Divin : les utilisations faites pendant l'instance annulée rejoignent l'instance précédente (comme le journal).
  update mercenaire_conduit_divin set instance_no = v_instance
    where session_id = ctx_session() and instance_no > v_instance;
end;
$$;

grant create on schema public to fortress_fn;
alter function conduit_divin_utiliser(uuid, uuid) owner to fortress_fn;
alter function journal_instance_annuler() owner to fortress_fn;
revoke create on schema public from fortress_fn;
