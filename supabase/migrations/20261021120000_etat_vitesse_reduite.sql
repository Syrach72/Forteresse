-- État « Vitesse réduite » (Bruno, 2026-10-21), mercenaires en quête et créatures : le nombre de cases perdues se règle
-- dans le « niveau » de l'état (1 à 9 cases) ; la durée en rounds est celle des autres états (Rd par Rd, 1 à 9).
-- Le reste est inchangé : mercenaire_definir_etat (20261005140000) et etats_sup_definir (20261012100000).
-- L'application sur la vitesse affichée se fait dans l'interface.

do $$
declare c record;
begin
  for c in
    select con.conrelid::regclass as tbl, con.conname
    from pg_constraint con
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any (con.conkey)
    where con.contype = 'c' and con.connamespace = 'public'::regnamespace
      and ((a.attname = 'etat_niveau') or (a.attname = 'niveau' and con.conrelid = 'etat_supplementaire'::regclass))
  loop
    execute format('alter table %s drop constraint %I', c.tbl, c.conname);
  end loop;
  for c in
    select table_name from information_schema.columns
    where table_schema = 'public' and column_name = 'etat_niveau'
  loop
    execute format('alter table %I add constraint %I check (etat_niveau between 1 and 9)', c.table_name, c.table_name || '_etat_niveau_check');
  end loop;
  alter table etat_supplementaire add constraint etat_supplementaire_niveau_check check (niveau between 1 and 9);
end;
$$;

create or replace function etats_sup_definir(p_cible text, p_id uuid, p_liste jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  e jsonb;
  i integer := 0;
  v_etat text;
  v_niveau integer;
  v_rounds integer;
  v_vus text[] := '{}';
begin
  perform _verrou_partie();
  if p_cible = 'creature' then
    if not is_admin() then
      raise exception 'Réservé au MJ.';
    end if;
    if not exists (select 1 from creature_quete where id = p_id and session_id = ctx_session()) then
      raise exception 'Créature inconnue.';
    end if;
  elsif p_cible in ('mercenaire', 'compagnon') then
    perform _droit_mercenaire(p_id);
    if not exists (select 1 from quete_mercenaire where mercenaire_id = p_id) then
      raise exception 'Ce mercenaire n''est pas engagé dans une quête.';
    end if;
    if p_cible = 'compagnon'
       and not exists (select 1 from mercenaire_compagnon where mercenaire_id = p_id and session_id = ctx_session()) then
      raise exception 'Ce mercenaire n''a pas de compagnon.';
    end if;
  else
    raise exception 'Cible inconnue.';
  end if;
  if p_liste is null or jsonb_typeof(p_liste) <> 'array' or jsonb_array_length(p_liste) > 2 then
    raise exception 'Trois états au maximum en même temps.';
  end if;
  delete from etat_supplementaire where session_id = ctx_session() and cible = p_cible and cible_id = p_id;
  for e in select * from jsonb_array_elements(p_liste) loop
    v_etat := e ->> 'etat';
    v_niveau := coalesce((e ->> 'niveau')::integer, 1);
    v_rounds := coalesce((e ->> 'rounds')::integer, 0);
    if v_etat is null or v_etat not in ('a_terre', 'abri_partiel', 'abri_total', 'affaibli', 'agrippe', 'assourdi',
        'aveugle', 'charme', 'concentration', 'confus', 'desoriente', 'effraye', 'empoisonne', 'endormi', 'enrage',
        'entrave', 'epuise', 'etourdi', 'fascine', 'fatigue', 'flou', 'immobilise', 'lenteur', 'muet', 'nauseeux',
        'paralyse', 'petrifie', 'possede', 'suffocation', 'vitesse_reduite') then
      raise exception 'État inconnu (l''Inconscient est toujours le premier état).';
    end if;
    if v_etat = any (v_vus) then
      raise exception 'Le même état ne peut pas être appliqué deux fois.';
    end if;
    if v_niveau < 1 or (v_etat = 'epuise' and v_niveau > 3) or (v_etat = 'vitesse_reduite' and v_niveau > 9) or (v_etat not in ('epuise', 'vitesse_reduite') and v_niveau <> 1) then
      raise exception 'Niveau d''état invalide.';
    end if;
    if v_rounds < 0 or v_rounds > 9 then
      raise exception 'La durée est un nombre de rounds de 0 à 9.';
    end if;
    i := i + 1;
    insert into etat_supplementaire (cible, cible_id, position, etat, niveau, rounds)
      values (p_cible, p_id, i, v_etat, v_niveau, v_rounds);
    v_vus := v_vus || v_etat;
  end loop;
end;
$$;

create or replace function mercenaire_definir_etat(
  p_mercenaire uuid, p_etat text, p_niveau integer default 1, p_rounds integer default 0)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_prev text;
  v_sante integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  select etat, sante_actuelle into v_prev, v_sante from mercenaire_etat
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  if p_etat is null then
    update mercenaire_etat
      set etat = null, etat_niveau = 1, etat_rounds = 0, etat_efface = null, etat_decremente = false,
          inconscient_rounds = null, inconscient_dec = false, mort_champ = false
      where session_id = ctx_session() and mercenaire_id = p_mercenaire;
    return;
  end if;
  if p_etat not in ('a_terre', 'abri_partiel', 'abri_total', 'affaibli', 'agrippe', 'assourdi', 'aveugle', 'charme', 'concentration', 'confus',
                    'desoriente', 'effraye', 'empoisonne', 'endormi', 'enrage', 'entrave', 'epuise', 'etourdi',
                    'fascine', 'fatigue', 'flou', 'immobilise', 'inconscient', 'lenteur', 'muet', 'nauseeux', 'paralyse',
                    'petrifie', 'possede', 'suffocation', 'vitesse_reduite') then
    raise exception 'État inconnu.';
  end if;
  if p_niveau is null or p_niveau < 1 or (p_etat = 'epuise' and p_niveau > 3) or (p_etat = 'vitesse_reduite' and p_niveau > 9) or (p_etat not in ('epuise', 'vitesse_reduite') and p_niveau <> 1) then
    raise exception 'Niveau d''état invalide.';
  end if;
  if p_rounds is null or p_rounds < 0 or p_rounds > 9 then
    raise exception 'La durée est un nombre de rounds de 0 à 9.';
  end if;
  if not exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire n''est pas engagé dans une quête.';
  end if;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
    on conflict (session_id, mercenaire_id) do nothing;
  update mercenaire_etat
    set etat = p_etat, etat_niveau = p_niveau, etat_rounds = p_rounds, etat_efface = null, etat_decremente = false,
        inconscient_rounds = case when p_etat <> 'inconscient' or v_sante is distinct from 0 then null
                                  when v_prev = 'inconscient' then coalesce(inconscient_rounds, 3)
                                  else 3 end,
        inconscient_dec = case when p_etat = 'inconscient' and v_prev = 'inconscient' then inconscient_dec else false end,
        mort_champ = case when p_etat = 'inconscient' and v_prev = 'inconscient' then mort_champ else false end
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
end;
$$;
