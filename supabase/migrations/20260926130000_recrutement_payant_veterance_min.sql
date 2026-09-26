-- Recrutement payant et vétérance minimale (règles de Bruno, 2026-09-26).
--
-- 1. Recruter un mercenaire coûte 100 Po × sa vétérance, prélevés sur la trésorerie
--    de la session. Un mercenaire renvoyé se recrute de nouveau, et se paie de nouveau
--    (aucun remboursement au renvoi). Le recrutement passe désormais par une fonction
--    serveur qui paie et recrute dans la même opération ; l'insertion directe par un
--    joueur est supprimée (elle aurait permis de recruter gratuitement).
-- 2. Aucun mercenaire ne peut avoir moins de 1 de vétérance : les fiches à 0 (ou vides)
--    passent à 1, la valeur par défaut devient 1, et la base refuse désormais 0.

-- ---------------------------------------------------------------------------
-- 2. Vétérance minimale : 1
-- ---------------------------------------------------------------------------
update mercenaire set veterance = 1 where veterance is null or veterance < 1;
alter table mercenaire alter column veterance set default 1;
alter table mercenaire add constraint mercenaire_veterance_min_check check (veterance >= 1);

update mercenaire_etat set veterance = 1 where veterance < 1;
do $$
declare
  v_conname text;
begin
  select con.conname into v_conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    where rel.relname = 'mercenaire_etat' and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%veterance%';
  if v_conname is not null then
    execute format('alter table mercenaire_etat drop constraint %I', v_conname);
  end if;
end;
$$;
alter table mercenaire_etat add constraint mercenaire_etat_veterance_min_check check (veterance >= 1);

-- Repli sur 1 (et non 0) quand aucune vétérance n'est renseignée.
create or replace function _vet(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select greatest(1, coalesce(
    (select e.veterance from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.veterance from mercenaire m where m.id = p_mercenaire),
    1));
$$;

create or replace function mercenaire_definir_veterance(p_mercenaire uuid, p_valeur integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_valeur is null or p_valeur < 1 or p_valeur > 999 then
    raise exception 'Saisissez un entier de 1 à 999 (la vétérance minimale est 1).';
  end if;
  if ctx_est_base() then
    update mercenaire set veterance = p_valeur where id = p_mercenaire;
  else
    perform _verrou_partie();
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), p_mercenaire, p_valeur)
      on conflict (session_id, mercenaire_id) do update set veterance = excluded.veterance;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Recrutement payant
-- ---------------------------------------------------------------------------
create function mercenaire_recruter(p_mercenaire uuid, p_nom_joueur text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  v_nom text;
  v_vet integer;
  v_cout integer;
  v_joueur text := left(btrim(coalesce(p_nom_joueur, '')), 24);
begin
  v_or := _verrou_partie();
  if v_joueur = '' then
    raise exception 'Inscrivez votre nom de joueur avant de recruter.';
  end if;
  select nom into v_nom from mercenaire where id = p_mercenaire;
  if v_nom is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  v_vet := _vet(p_mercenaire);
  v_cout := 100 * v_vet;
  if v_or < v_cout then
    raise exception 'Trésorerie insuffisante : recruter % coûte % Po (100 Po × vétérance %).', v_nom, v_cout, v_vet;
  end if;
  -- L'insertion attribue le lit (ou refuse s'il n'y en a plus, ou si le mercenaire est déjà
  -- recruté) : rien n'est payé dans ces cas, l'opération entière est annulée.
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (p_mercenaire, auth.uid(), v_joueur);
  update partie_etat set or_compagnie = or_compagnie - v_cout where id;
  perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : −' || v_cout || ' Po.', -v_cout,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', v_cout));
  return jsonb_build_object('cout', v_cout, 'or', v_or - v_cout);
end;
$$;

-- Plus de recrutement direct par un joueur (il contournerait le paiement).
drop policy "recrutement: un joueur recrute pour lui-meme" on recrutement;

grant create on schema public to fortress_fn;
alter function mercenaire_recruter(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_recruter(uuid, text) from public;
grant execute on function mercenaire_recruter(uuid, text) to authenticated;
