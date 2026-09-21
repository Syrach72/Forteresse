-- Entretien de la compagnie (regle de Bruno, 2026-09-21) :
--  * l'entretien = (somme des veterances de tous les mercenaires du dortoir,
--    c'est-a-dire tous les recrutes, actifs ou grises) x 10 Po ;
--  * il est preleve sur la tresorerie au debut de chaque nouvelle instance
--    (+1 Instance, administrateur seul) ;
--  * un solde negatif ne bloque rien : la contrainte "or >= 0" est levee (les
--    achats restent refuses faute de fonds, par les fonctions partie_*).

do $$
declare
  c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.partie_etat'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%or_compagnie%'
  loop
    execute format('alter table public.partie_etat drop constraint %I', c.conname);
  end loop;
end;
$$;

-- Montant de l'entretien d'une instance (lisible par les joueurs connectes).
create function entretien_montant()
returns integer
language sql
stable
security definer set search_path = public
as $$
  select (coalesce(sum(coalesce(m.veterance, 0)), 0) * 10)::integer
  from recrutement r
  join mercenaire m on m.id = r.mercenaire_id;
$$;

-- Debut d'une nouvelle instance : preleve l'entretien, meme si le solde devient
-- negatif. Renvoie { montant, mercenaires, solde }.
create function entretien_prelever()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  v_montant integer;
  v_nb integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  v_or := _verrou_partie();
  v_montant := entretien_montant();
  select count(*) into v_nb from recrutement;
  if v_montant > 0 then
    update partie_etat set or_compagnie = or_compagnie - v_montant where id;
    perform _journal('depense',
      'Entretien de la compagnie (nouvelle instance) : −' || v_montant || ' Po.',
      -v_montant, jsonb_build_object('mercenaires', v_nb));
  end if;
  return jsonb_build_object('montant', v_montant, 'mercenaires', v_nb, 'solde', v_or - v_montant);
end;
$$;

-- Annulation du dernier +1 Instance : rend l'entretien preleve.
create function entretien_annuler(p_montant integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_montant is null or p_montant < 1 or p_montant > 10000000 then
    raise exception 'Montant invalide.';
  end if;
  perform _verrou_partie();
  update partie_etat set or_compagnie = or_compagnie + p_montant where id;
  perform _journal('annulation',
    'Entretien remboursé (+1 Instance annulé) : +' || p_montant || ' Po.', p_montant, null);
end;
$$;

revoke all on function entretien_montant() from public;
revoke all on function entretien_prelever() from public;
revoke all on function entretien_annuler(integer) from public;
grant execute on function entretien_montant() to authenticated;
grant execute on function entretien_prelever() to authenticated;
grant execute on function entretien_annuler(integer) to authenticated;
