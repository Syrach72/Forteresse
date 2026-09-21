-- Budget de la compagnie PARTAGE (regle de Bruno, 2026-09-21) :
--  * Recettes et postes de depenses sont enregistres en base (visibles par tous,
--    modifiables par l'administrateur seul) ;
--  * au debut de chaque nouvelle instance (+1 Instance, administrateur), le solde
--    de la tresorerie recoit (recettes - depenses) ; les depenses = tous les postes
--    + l'entretien calcule (10 Po x vétérance de tous les mercenaires du dortoir) ;
--  * un solde negatif ne bloque rien (voir la migration 20260921170000).
-- Les postes autres que l'entretien sont fictifs pour le moment : Bruno choisira
-- ceux qu'il garde et ils seront relies aux bonnes pages un par un.

create table budget_poste (
  code text primary key,
  libelle text not null,
  nature text not null check (nature in ('recette', 'depense')),
  montant integer not null default 0 check (montant between 0 and 10000000),
  auto boolean not null default false,
  ordre smallint not null default 0
);
alter table budget_poste enable row level security;
create policy "budget_poste: lecture par les joueurs connectes"
  on budget_poste for select to authenticated using (true);
create policy "budget_poste: ecriture admin"
  on budget_poste for all to authenticated using (is_admin()) with check (is_admin());

insert into budget_poste (code, libelle, nature, montant, auto, ordre) values
  ('recettes', 'Recettes', 'recette', 3000, false, 0),
  ('entretien', 'Entretien', 'depense', 0, true, 1),
  ('dortoir', 'Lits Dortoir', 'depense', 1000, false, 2),
  ('infirmerie', 'Lits Infirmerie', 'depense', 150, false, 3),
  ('medecin', 'Médecin', 'depense', 80, false, 4),
  ('maitre', 'Maître d’Armes', 'depense', 200, false, 5),
  ('entrainement', 'Entraînement', 'depense', 120, false, 6),
  ('forgeron', 'Forgeron', 'depense', 100, false, 7),
  ('armurier', 'Armurier', 'depense', 150, false, 8),
  ('mage', 'Mage', 'depense', 60, false, 9),
  ('reste', 'Autres frais à détailler', 'depense', 85, false, 10);

-- Modifier le montant d'un poste (l'entretien est calcule, pas saisi).
create function budget_modifier(p_code text, p_montant integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_montant is null or p_montant < 0 or p_montant > 10000000 then
    raise exception 'Saisissez un entier de 0 à 10 000 000.';
  end if;
  if (select auto from budget_poste where code = p_code) then
    raise exception 'Ce poste est calculé automatiquement.';
  end if;
  update budget_poste set montant = p_montant where code = p_code;
  if not found then
    raise exception 'Poste inconnu.';
  end if;
end;
$$;

-- Remplace l'ancien prelevement de l'entretien seul.
drop function entretien_prelever();
drop function entretien_annuler(integer);

-- Debut d'une nouvelle instance : le solde recoit recettes - depenses (meme s'il
-- devient negatif). Renvoie { recettes, depenses, entretien, net, solde }.
create function budget_appliquer_instance()
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
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  v_or := _verrou_partie();
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

-- Annulation du dernier +1 Instance : retire ce que l'instance avait applique.
create function budget_annuler_instance(p_net integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_net is null or p_net = 0 or abs(p_net) > 100000000 then
    raise exception 'Montant invalide.';
  end if;
  perform _verrou_partie();
  update partie_etat set or_compagnie = or_compagnie - p_net where id;
  perform _journal('annulation',
    'Budget de l''instance annulé (+1 Instance annulé) : ' || case when -p_net > 0 then '+' else '' end || (-p_net) || ' Po.',
    -p_net, null);
end;
$$;

revoke all on function budget_modifier(text, integer) from public;
revoke all on function budget_appliquer_instance() from public;
revoke all on function budget_annuler_instance(integer) from public;
grant execute on function budget_modifier(text, integer) to authenticated;
grant execute on function budget_appliquer_instance() to authenticated;
grant execute on function budget_annuler_instance(integer) to authenticated;

-- Mise a jour en direct chez tous les joueurs (Supabase Realtime).
do $$
begin
  alter publication supabase_realtime add table budget_poste;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
