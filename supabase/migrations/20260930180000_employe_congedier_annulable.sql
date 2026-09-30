-- Congédiement (Bruno, 2026-09-30) :
--  * un bâtiment (Scierie, Camp de Mineur, Tannerie : objet qui sert d'outil à un métier) ne peut pas être
--    congédié ;
--  * un congédiement est annulable : employe_congedier renvoie l'identifiant du journal (journal_id) et
--    employe_annuler_congediement(journal) rétablit les employés (seul l'auteur ou le MJ, une seule fois).
-- Remplace employe_congedier de 20260922180000 (le type de retour change : void -> jsonb).

drop function if exists employe_congedier(uuid, boolean, integer);

create function employe_congedier(p_objet uuid, p_outil boolean, p_quantite integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
  v_actuel integer;
  v_outil boolean := coalesce(p_outil, false);
  v_jid uuid;
begin
  perform _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if exists (select 1 from objet_catalogue where emploi_outil_id = p_objet) then
    raise exception 'Un bâtiment ne peut pas être congédié.';
  end if;
  select quantite into v_actuel from employe where objet_id = p_objet and outil = v_outil for update;
  if v_actuel is null or v_actuel < p_quantite then
    raise exception 'Cet employé n''est pas disponible en telle quantité.';
  end if;
  select * into o from objet_catalogue where id = p_objet;
  if v_actuel = p_quantite then
    delete from employe where objet_id = p_objet and outil = v_outil;
  else
    update employe set quantite = quantite - p_quantite, updated_at = now()
      where objet_id = p_objet and outil = v_outil;
  end if;
  v_jid := _journal('congediement', p_quantite || ' ' || coalesce(o.nom, 'employé') || '(s) congédié(s).', 0,
    jsonb_build_object('objet_id', p_objet, 'outil', v_outil, 'quantite', p_quantite));
  return jsonb_build_object('journal_id', v_jid);
end;
$$;

create function employe_annuler_congediement(p_journal uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  j partie_journal%rowtype;
  v_message text := 'Congédiement annulé : employé(s) rétabli(s).';
begin
  perform _verrou_partie();
  select * into j from partie_journal where id = p_journal for update;
  if not found then
    raise exception 'Opération introuvable.';
  end if;
  if not is_admin() and j.auteur_id is distinct from auth.uid() then
    raise exception 'Seul l''auteur de l''opération peut l''annuler.';
  end if;
  if j.annule then
    raise exception 'Cette opération est déjà annulée.';
  end if;
  if j.type <> 'congediement' then
    raise exception 'Cette opération ne peut pas être annulée.';
  end if;
  insert into employe (objet_id, outil, quantite)
    values ((j.details ->> 'objet_id')::uuid, coalesce((j.details ->> 'outil')::boolean, false),
            (j.details ->> 'quantite')::integer)
    on conflict (session_id, objet_id, outil)
    do update set quantite = employe.quantite + excluded.quantite, updated_at = now();
  update partie_journal set annule = true where id = p_journal;
  perform _journal('annulation', v_message, 0, jsonb_build_object('annule', p_journal));
  return jsonb_build_object('message', v_message);
end;
$$;

grant create on schema public to fortress_fn;
alter function employe_congedier(uuid, boolean, integer) owner to fortress_fn;
alter function employe_annuler_congediement(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function employe_congedier(uuid, boolean, integer) from public;
revoke all on function employe_annuler_congediement(uuid) from public;
grant execute on function employe_congedier(uuid, boolean, integer) to authenticated;
grant execute on function employe_annuler_congediement(uuid) to authenticated;
