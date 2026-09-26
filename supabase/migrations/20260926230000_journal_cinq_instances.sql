-- Journal de la compagnie : seules les activités des 5 dernières instances sont conservées
-- (Bruno, 2026-09-26). Les plus anciennes s'effacent.
--
-- Chaque partie (session) a un compteur d'instances (partie_etat.instance_courante), qui monte de 1 à
-- chaque « +1 Instance » du MJ (budget_appliquer_instance, appelée en premier). Chaque ligne du journal
-- note l'instance pendant laquelle elle a été écrite (partie_journal.instance_no). À chaque nouvelle
-- instance N, on efface les lignes des instances antérieures à N - 4 : on garde l'instance en cours et
-- les 4 précédentes (5 au total). Les lignes déjà présentes comptent comme l'instance 0.
-- Annuler le dernier +1 Instance fait reculer le compteur (journal_instance_annuler) : les lignes de
-- l'instance annulée rejoignent la précédente. Les lignes déjà effacées ne reviennent pas.

alter table partie_etat add column instance_courante integer not null default 0;
alter table partie_journal add column instance_no integer not null default 0;

create or replace function _journal(p_type text, p_message text, p_montant integer, p_details jsonb)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into partie_journal (type, message, montant, details, auteur_id, instance_no)
    values (p_type, p_message, p_montant, p_details, auth.uid(),
      coalesce((select e.instance_courante from partie_etat e where e.session_id = ctx_session()), 0))
    returning id into v_id;
  return v_id;
end;
$$;

create or replace function budget_appliquer_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  v_recettes integer;
  v_autres integer;
  v_entretien integer;
  v_depenses integer;
  v_net integer;
  v_instance integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  v_or := _verrou_partie();
  -- Nouvelle instance : le compteur monte, le journal ne garde que les 5 dernières instances.
  update partie_etat set instance_courante = instance_courante + 1
    where id and session_id = ctx_session()
    returning instance_courante into v_instance;
  delete from partie_journal
    where session_id = ctx_session() and instance_no < v_instance - 4;
  select coalesce(sum(montant) filter (where nature = 'recette'), 0),
         coalesce(sum(montant) filter (where nature = 'depense' and not auto), 0)
    into v_recettes, v_autres from budget_poste;
  v_entretien := entretien_montant();
  v_depenses := v_autres + v_entretien;
  v_net := v_recettes - v_depenses;
  if v_net <> 0 then
    update partie_etat set or_compagnie = or_compagnie + v_net where id;
    perform _journal(case when v_net > 0 then 'or' else 'depense' end,
      'Nouvelle instance : recettes +' || v_recettes || ' Po, dépenses −' || v_depenses
        || ' Po (dont entretien ' || v_entretien || ' Po) : '
        || case when v_net > 0 then '+' else '' end || v_net || ' Po.',
      v_net,
      jsonb_build_object('recettes', v_recettes, 'depenses', v_depenses, 'entretien', v_entretien));
  end if;
  return jsonb_build_object('recettes', v_recettes, 'depenses', v_depenses,
    'entretien', v_entretien, 'net', v_net, 'solde', v_or + v_net);
end;
$$;

-- Annulation du dernier +1 Instance : le compteur recule, les lignes de l'instance annulée (dont les
-- annulations écrites pendant cette opération) rejoignent l'instance précédente.
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
end;
$$;

grant create on schema public to fortress_fn;
alter function _journal(text, text, integer, jsonb) owner to fortress_fn;
alter function budget_appliquer_instance() owner to fortress_fn;
alter function journal_instance_annuler() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _journal(text, text, integer, jsonb) from public;
revoke all on function budget_appliquer_instance() from public;
revoke all on function journal_instance_annuler() from public;
grant execute on function budget_appliquer_instance() to authenticated;
grant execute on function journal_instance_annuler() to authenticated;
