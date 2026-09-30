-- Tribut du village indexé sur la vétérance moyenne des mercenaires embauchés
-- (formule A de Bruno, 2026-09-30) : de 25 × moyenne à 50 × moyenne Po par instance
-- (ex. moyenne 2 : 50 à 100 Po, comme avant ; moyenne 4 : 100 à 200 Po).
-- Le reste de budget_appliquer_instance() est inchangé.

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
  v_tribut integer;
  v_phrase text;
  v_moy numeric;
  v_phrases text[] := array[
    'Le village a payé sa dîme.',
    'Un marchand de passage fait un don à la compagnie.',
    'Le seigneur récompense vos services.',
    'Les faveurs du suzerain remplissent un peu les caisses.',
    'Le tribut du village est arrivé à bon port.',
    'Une collecte locale profite à la compagnie.',
    'Un noble reconnaissant envoie quelques pièces.',
    'La vente d''un surplus au village rapporte quelques Po.'
  ];
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
  -- Formule A (Bruno, 2026-09-30) : fourchette = moyenne de vétérance de TOUS les
  -- mercenaires embauchés à la Caserne (grisés compris) × 25 à × 50 Po.
  -- Sans mercenaire embauché : pas de tribut.
  select coalesce(avg(_vet(r.mercenaire_id)), 0) into v_moy from recrutement r;
  v_tribut := round(v_moy * 25)::integer
    + floor(random() * (round(v_moy * 50) - round(v_moy * 25) + 1))::integer;
  v_phrase := v_phrases[1 + floor(random() * array_length(v_phrases, 1))::integer];
  v_net := v_recettes - v_depenses + v_tribut;
  if v_recettes <> 0 or v_depenses <> 0 then
    perform _journal(case when (v_recettes - v_depenses) >= 0 then 'or' else 'depense' end,
      'Nouvelle instance : recettes +' || v_recettes || ' Po, dépenses −' || v_depenses
        || ' Po (dont entretien ' || v_entretien || ' Po) : '
        || case when (v_recettes - v_depenses) > 0 then '+' else '' end || (v_recettes - v_depenses) || ' Po.',
      v_recettes - v_depenses,
      jsonb_build_object('recettes', v_recettes, 'depenses', v_depenses, 'entretien', v_entretien));
  end if;
  perform _journal('or', v_phrase || ' +' || v_tribut || ' Po.', v_tribut,
    jsonb_build_object('tribut', v_tribut));
  update partie_etat set or_compagnie = or_compagnie + v_net where id;
  return jsonb_build_object('recettes', v_recettes, 'depenses', v_depenses,
    'entretien', v_entretien, 'net', v_net, 'solde', v_or + v_net,
    'tribut', v_tribut, 'tribut_phrase', v_phrase);
end;
$$;

