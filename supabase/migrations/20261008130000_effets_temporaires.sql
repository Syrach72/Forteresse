-- Effets temporaires des missions (demande de Bruno, 2026-10-08).
--  * Une mission individuelle peut donner un EFFET TEMPORAIRE à l'un des mercenaires du joueur : +N en Puissance,
--    Vélocité, Mental, Mouvement, Santé max ou Énergie max, ou N PV temporaires (en plus des PV).
--  * Il reste en réserve (table mercenaire_effet) tant que le mercenaire n'est pas engagé dans une quête ; il
--    s'applique tant que le mercenaire est dans une quête, et chaque quête terminée (réussie ou échouée) retire
--    une quête de sa durée (1 à 3). Les PV temporaires disparaissent à la fin de la 1re quête.
--  * Non transférable ; il disparaît si le mercenaire est renvoyé.
--  * Le serveur applique les bonus : _puissance / _velocite / _mental / _sante_max / énergie max (fonctions
--    reprises ci-dessous) ajoutent _effet_temp(). Le Mouvement et les PV temporaires sont affichés par la fiche.
--  * Quand les effets cessent, santé et énergie actuelles sont ramenées au nouveau maximum.

-- 1. Récompense « effet » d'une mission
alter table mission
  add column recompense_effet_stat text
    check (recompense_effet_stat in ('puissance', 'velocite', 'mental', 'mouvement', 'sante_max', 'energie_max', 'pv_temp')),
  add column recompense_effet_valeur smallint check (recompense_effet_valeur between 1 and 99),
  add column recompense_effet_quetes smallint not null default 1 check (recompense_effet_quetes between 1 and 3);
alter table mission add constraint mission_effet_individuelle_check
  check (recompense_effet_stat is null or (rubrique = 'individuelle' and recompense_effet_valeur is not null));
alter table mission_attribution
  add column effet_stat text,
  add column effet_valeur smallint,
  add column effet_quetes smallint;

-- 2. Effets en réserve / actifs d'un mercenaire
create table mercenaire_effet (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  stat text not null check (stat in ('puissance', 'velocite', 'mental', 'mouvement', 'sante_max', 'energie_max', 'pv_temp')),
  valeur smallint not null check (valeur >= 1),
  quetes_restantes smallint not null default 1 check (quetes_restantes between 0 and 3),
  mission_id uuid references mission (id) on delete set null,
  created_at timestamptz not null default now()
);
create index mercenaire_effet_merc on mercenaire_effet (session_id, mercenaire_id);
alter table mercenaire_effet enable row level security;
create policy "mercenaire_effet: lecture" on mercenaire_effet for select to authenticated
  using (session_id = ctx_session());
create policy "mercenaire_effet: ecriture admin" on mercenaire_effet for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "mercenaire_effet: fonctions serveur" on mercenaire_effet for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on mercenaire_effet to authenticated, fortress_fn;
revoke all on mercenaire_effet from anon;
do $$
begin
  alter publication supabase_realtime add table mercenaire_effet;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- 3. Somme des effets ACTIFS (mercenaire engagé dans une quête) d'une caractéristique
create or replace function _effet_temp(p_mercenaire uuid, p_stat text)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(sum(e.valeur), 0)::integer
  from mercenaire_effet e
  where e.mercenaire_id = p_mercenaire and e.stat = p_stat and e.session_id = ctx_session()
    and exists (select 1 from quete_mercenaire q where q.mercenaire_id = p_mercenaire and q.session_id = ctx_session());
$$;

-- 4. Caractéristiques et maxima : + effets temporaires
create or replace function _puissance(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.attaque from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.attaque from mercenaire m where m.id = p_mercenaire),
    0) + _bonus_puissance(p_mercenaire) + _effet_temp(p_mercenaire, 'puissance');
$$;
create or replace function _velocite(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.defense from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.defense from mercenaire m where m.id = p_mercenaire),
    0) + _bonus_velocite(p_mercenaire) + _effet_temp(p_mercenaire, 'velocite');
$$;
create or replace function _mental(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.esprit from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.esprit from mercenaire m where m.id = p_mercenaire),
    0) + _bonus_mental(p_mercenaire) + _effet_temp(p_mercenaire, 'mental');
$$;
create or replace function _sante_max(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select 3 + 2 * _puissance(p_mercenaire) + _bonus_sante(p_mercenaire) + _effet_temp(p_mercenaire, 'sante_max');
$$;

-- 5. Énergie max : 2 × Mental + effets temporaires d'énergie (fonctions reprises à l'identique)
create or replace function mercenaire_depenser_energie(p_mercenaire uuid, p_montant integer)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_max integer;
  v_actuelle integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  if p_montant is null or p_montant < 1 or p_montant > 10 then
    raise exception 'Le montant à dépenser est un entier de 1 à 10.';
  end if;
  v_max := (2 * _mental(p_mercenaire) + _effet_temp(p_mercenaire, 'energie_max'));
  -- Ligne d'état créée si besoin, puis verrouillée pour éviter deux dépenses simultanées.
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
    on conflict (session_id, mercenaire_id) do nothing;
  select coalesce(e.energie_actuelle, v_max) into v_actuelle
    from mercenaire_etat e
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire
    for update;
  if v_actuelle < p_montant then
    raise exception 'Énergie insuffisante : % disponible(s), % demandée(s).', v_actuelle, p_montant;
  end if;
  update mercenaire_etat
    set energie_actuelle = v_actuelle - p_montant
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  return v_actuelle - p_montant;
end;
$$;

create or replace function round_avancer()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_round integer;
  v_gains jsonb := '[]'::jsonb;
  r record;
  v_max integer;
  v_act integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select round_courant into v_round from partie_etat where session_id = ctx_session() for update;
  if v_round >= 99 then
    raise exception 'Le compteur de round est déjà à 99.';
  end if;
  update partie_etat set round_courant = round_courant + 1
    where session_id = ctx_session()
    returning round_courant into v_round;
  for r in select distinct mercenaire_id from recrutement where session_id = ctx_session() loop
    v_max := (2 * _mental(r.mercenaire_id) + _effet_temp(r.mercenaire_id, 'energie_max'));
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), r.mercenaire_id, _vet(r.mercenaire_id))
      on conflict (session_id, mercenaire_id) do nothing;
    select coalesce(e.energie_actuelle, v_max) into v_act
      from mercenaire_etat e
      where e.session_id = ctx_session() and e.mercenaire_id = r.mercenaire_id
      for update;
    if v_act < v_max then
      update mercenaire_etat set energie_actuelle = v_act + 1
        where session_id = ctx_session() and mercenaire_id = r.mercenaire_id;
      v_gains := v_gains || to_jsonb(r.mercenaire_id);
    end if;
  end loop;
  return jsonb_build_object('round', v_round, 'gains', v_gains);
end;
$$;

create or replace function mercenaire_restauration_arcanique(p_mercenaire uuid)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_gain integer;
  v_max integer;
  v_act integer;
  v_nouvelle integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  v_vet := _vet(p_mercenaire);
  v_gain := case when v_vet >= 10 then 5 when v_vet >= 7 then 4 when v_vet >= 4 then 3 else 2 end;
  v_max := (2 * _mental(p_mercenaire) + _effet_temp(p_mercenaire, 'energie_max'));
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, v_vet)
    on conflict (session_id, mercenaire_id) do nothing;
  select coalesce(e.energie_actuelle, v_max) into v_act
    from mercenaire_etat e
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire
    for update;
  v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
  update mercenaire_etat set energie_actuelle = v_nouvelle
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  return v_nouvelle - v_act;
end;
$$;

create or replace function sac_dos_utiliser(p_mercenaire uuid, p_objet uuid, p_gemmes uuid[] default null)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_merc text;
  v_nom text;
  v_racine text;
  v_sac uuid;
  v_ligne uuid;
  v_qte integer;
  v_type text;
  v_gain integer;
  v_max integer;
  v_act integer;
  v_nouvelle integer;
  v_reste integer;
  v_effet text := '';
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  if v_merc is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id) into v_nom, v_racine
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  if v_racine is distinct from 'Produits Alchimiques' then
    raise exception 'Seuls les produits alchimiques peuvent être utilisés.';
  end if;
  v_sac := _sac_dos_id(p_mercenaire);
  select id, quantite into v_ligne, v_qte from ligne_inventaire
    where inventaire_id = v_sac and objet_id = p_objet and gemmes is not distinct from v_gemmes and quantite > 0
    order by created_at, id limit 1
    for update;
  if v_ligne is null then
    raise exception 'Cet objet n''est pas dans le sac à dos.';
  end if;
  if v_qte = 1 then
    delete from ligne_inventaire where id = v_ligne;
  else
    update ligne_inventaire set quantite = quantite - 1, updated_at = now() where id = v_ligne;
  end if;

  -- Effet des potions d'énergie et de vie.
  v_type := case
    when lower(v_nom) like 'potion d''energie %' or lower(v_nom) like 'potion d''énergie %' then 'energie'
    when lower(v_nom) like 'potion de vie %' then 'sante'
  end;
  v_gain := case
    when lower(v_nom) like '% mineure' then 3
    when lower(v_nom) like '% médiane' or lower(v_nom) like '% mediane' then 5
    when lower(v_nom) like '% majeure' then 8
  end;
  if v_type is not null and v_gain is not null then
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
      on conflict (session_id, mercenaire_id) do nothing;
    if v_type = 'energie' then
      v_max := (2 * _mental(p_mercenaire) + _effet_temp(p_mercenaire, 'energie_max'));
      select coalesce(e.energie_actuelle, v_max) into v_act from mercenaire_etat e
        where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire for update;
      v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
      update mercenaire_etat set energie_actuelle = case when v_nouvelle >= v_max then null else v_nouvelle end
        where session_id = ctx_session() and mercenaire_id = p_mercenaire;
      v_effet := '+' || (v_nouvelle - v_act) || ' énergie';
    else
      v_max := _sante_max(p_mercenaire);
      select coalesce(e.sante_actuelle, v_max) into v_act from mercenaire_etat e
        where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire for update;
      v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
      update mercenaire_etat set sante_actuelle = case when v_nouvelle >= v_max then null else v_nouvelle end
        where session_id = ctx_session() and mercenaire_id = p_mercenaire;
      v_effet := '+' || (v_nouvelle - v_act) || ' santé';
      if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
        v_reste := _soins_instances(p_mercenaire, case when v_nouvelle >= v_max then null else v_nouvelle end);
        if v_reste = 0 then
          delete from infirmerie_place where mercenaire_id = p_mercenaire;
        else
          update infirmerie_place set restant = v_reste where mercenaire_id = p_mercenaire;
        end if;
      end if;
    end if;
  end if;

  perform _journal('equipement',
    v_nom || ' utilisé par ' || v_merc || case when v_effet <> '' then ' (' || v_effet || ')' else '' end || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'quantite', 1));
  return v_effet;
end;
$$;

-- 6. Fin de quête (réussie ou échouée) : chaque effet perd une quête ; les PV temporaires disparaissent.
create or replace function _effets_fin_quete(p_quete uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
begin
  for r in select mercenaire_id from quete_mercenaire where quete_id = p_quete and session_id = ctx_session()
  loop
    update mercenaire_effet set quetes_restantes = quetes_restantes - 1
      where mercenaire_id = r.mercenaire_id and session_id = ctx_session() and stat <> 'pv_temp';
    delete from mercenaire_effet
      where mercenaire_id = r.mercenaire_id and session_id = ctx_session()
        and (stat = 'pv_temp' or quetes_restantes <= 0);
  end loop;
end;
$$;

create or replace function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  e quete_etat%rowtype;
  r record;
  b jsonb;
  v_avant integer;
  v_apres integer;
  v_vet_avant integer;
  v_vet_apres integer;
  v_energie integer;
  v_gagnants integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_mercs jsonb := '[]'::jsonb;
  v_boosts jsonb := '[]'::jsonb;
  v_boosts_gain jsonb := '[]'::jsonb;
  v_mat text;
  v_prev integer;
  v_myst_id uuid;
  v_myst_nom text;
  n integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select * into e from quete_etat where en_cours for update;
  if not found then
    return null;
  end if;
  select * into q from quete where id = e.quete_id;
  v_avant := coalesce(e.instances_restantes, q.instances_requises);
  v_apres := greatest(v_avant - 1, 0);
  if v_apres > 0 then
    update quete_etat set instances_restantes = v_apres where quete_id = q.id;
    return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
      'avant', v_avant, 'apres', v_apres, 'termine', false);
  end if;
  -- Les récompenses (or + objets + objet mystère) ne rejoignent l'arsenal qu'à la fermeture de la
  -- fenêtre de récompenses (quete_recompenses_recuperer) : ici elles sont seulement mises en attente.
  -- Un emplacement de récompense peut contenir l'objet « Récompense mystère » (code recompense-mystere) :
  -- il n'entre jamais dans l'arsenal, mais est remplacé, quantité fois, par un objet tiré au hasard
  -- (Armes, Boucliers, Objets divers, Produits alchimiques). L'objet « Boost de production » (code boost)
  -- n'entre pas non plus à l'arsenal : il active un boost de production (voir plus bas).
  for r in
    select qr.objet_id, qr.quantite, qr.materiau,
           (o.code_unique = 'recompense-mystere') as myst,
           (o.code_unique = 'boost') as boost,
           (select ch.objet_id from quete_recompense_choix ch where ch.quete_id = qr.quete_id and ch.position = qr.position) as choix
      from quete_recompense qr join objet_catalogue o on o.id = qr.objet_id
      where qr.quete_id = q.id order by qr.position
  loop
    if r.boost then
      if r.materiau is not null then
        v_boosts := v_boosts || jsonb_build_object('objet_id', r.objet_id, 'materiau', r.materiau, 'instances', 3);
      end if;
    elsif r.myst and r.choix is not null then
      -- Récompense choisie par le MJ mais cachée aux joueurs (« ? ») : donnée telle quelle, sans tirage.
      select o2.nom into v_myst_nom from objet_catalogue o2 where o2.id = r.choix;
      v_items := v_items || jsonb_build_object('objet_id', r.choix, 'quantite', r.quantite, 'mystere', true, 'nom', v_myst_nom);
    elsif r.myst then
      for n in 1..r.quantite loop
        select t.id, t.nom into v_myst_id, v_myst_nom from _objet_mystere_tirer() t;
        if v_myst_id is not null then
          v_items := v_items || jsonb_build_object('objet_id', v_myst_id, 'quantite', 1, 'mystere', true, 'nom', v_myst_nom);
        end if;
      end loop;
    else
      v_items := v_items || jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite);
    end if;
  end loop;
  -- Boosts de production : actifs tout de suite (3 instances, celle-ci comprise), renouvelés à 3 s'il en restait.
  for b in select * from jsonb_array_elements(v_boosts)
  loop
    v_mat := b ->> 'materiau';
    select case v_mat when 'bois' then boost_bois when 'fer' then boost_fer else boost_cuir end
      into v_prev from partie_etat where id;
    update partie_etat
      set boost_bois = case when v_mat = 'bois' then 3 else boost_bois end,
          boost_fer = case when v_mat = 'fer' then 3 else boost_fer end,
          boost_cuir = case when v_mat = 'cuir' then 3 else boost_cuir end
      where id;
    v_boosts_gain := v_boosts_gain || jsonb_build_object('materiau', v_mat, 'avant', coalesce(v_prev, 0), 'apres', 3);
  end loop;
  for r in select position, mercenaire_id from quete_mercenaire where quete_id = q.id order by position
  loop
    v_vet_avant := _vet(r.mercenaire_id);
    select st.energie_actuelle into v_energie
      from mercenaire_etat st
      where st.mercenaire_id = r.mercenaire_id and st.session_id = ctx_session();
    if v_vet_avant > q.facteur_puissance then
      v_vet_apres := v_vet_avant;
    else
      v_vet_apres := v_vet_avant + 1;
      insert into mercenaire_etat (session_id, mercenaire_id, veterance)
        values (ctx_session(), r.mercenaire_id, v_vet_apres)
        on conflict (session_id, mercenaire_id) do update set veterance = excluded.veterance;
      v_gagnants := v_gagnants + 1;
    end if;
    -- Énergie : retour au maximum (vide = maximum).
    update mercenaire_etat set energie_actuelle = null
      where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    v_mercs := v_mercs || jsonb_build_object('mercenaire_id', r.mercenaire_id, 'position', r.position,
      'veterance_avant', v_vet_avant, 'veterance_apres', v_vet_apres, 'energie_avant', v_energie);
  end loop;
  perform _effets_fin_quete(q.id);
  delete from quete_mercenaire where quete_id = q.id;
  update quete_etat
    set en_cours = false, terminee_le = now(), instances_restantes = 0,
        recompenses_attente = jsonb_build_object('quete_id', q.id, 'nom', q.nom,
          'or', q.recompense_or, 'items', v_items, 'boosts', v_boosts)
    where quete_id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : récompenses à récupérer, '
      || v_gagnants || ' mercenaire(s) gagnent +1 de vétérance ; l''énergie des mercenaires engagés revient au maximum.'
      || case when jsonb_array_length(v_boosts) > 0 then ' Boost de production activé.' else '' end,
    0, jsonb_build_object('quete_terminee', q.id, 'mercenaires', v_mercs, 'boosts', v_boosts_gain));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs, 'mystere_nom', v_myst_nom,
    'boosts', v_boosts, 'boosts_gain', v_boosts_gain,
    'attente', true);
end;
$$;

create or replace function quetes_echec()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  v_id uuid;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  perform _verrou_partie();
  select quete_id into v_id from quete_etat where en_cours for update;
  if v_id is null then
    return null;
  end if;
  select * into q from quete where id = v_id;
  perform _effets_fin_quete(v_id);
  delete from quete_mercenaire where quete_id = v_id;
  update quete_etat
    set en_cours = false, instances_restantes = null,
        echec_attente = jsonb_build_object('id', gen_random_uuid(), 'quete_id', q.id, 'nom', q.nom, 'le', now())
    where quete_id = v_id;
  perform _journal('or', q.nom || ' : echec de la quete. Aucune recompense ; la quete redevient disponible.',
    0, jsonb_build_object('quete_echec', q.id));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom, 'echec', true);
end;
$$;

-- Quand un mercenaire quitte une quête (fin, retrait), ses effets ne s'appliquent plus : santé et énergie
-- actuelles sont ramenées au maximum de base.
create or replace function _effets_apres_quete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update mercenaire_etat
    set sante_actuelle = case when sante_actuelle is null then null else least(sante_actuelle, _sante_max(old.mercenaire_id)) end,
        energie_actuelle = case when energie_actuelle is null then null
          else least(energie_actuelle, 2 * _mental(old.mercenaire_id) + _effet_temp(old.mercenaire_id, 'energie_max')) end
    where session_id = old.session_id and mercenaire_id = old.mercenaire_id;
  return null;
exception when others then
  raise warning 'effets temporaires : %', sqlerrm;
  return null;
end;
$$;
create trigger effets_apres_quete after delete on quete_mercenaire
  for each row execute function _effets_apres_quete();

-- Mercenaire renvoyé : ses effets disparaissent.
create or replace function _effets_renvoi()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from mercenaire_effet where mercenaire_id = old.mercenaire_id and session_id = old.session_id;
  return null;
end;
$$;
create trigger effets_renvoi after delete on recrutement
  for each row execute function _effets_renvoi();

-- PV temporaires : le joueur (ou le MJ) en dépense quand le mercenaire encaisse des dégâts.
create or replace function effet_pv_temp_depenser(p_mercenaire uuid, p_montant integer)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  e mercenaire_effet%rowtype;
  v_total integer;
  v_reste integer := p_montant;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if coalesce(p_montant, 0) < 1 then
    raise exception 'Montant invalide.';
  end if;
  v_total := _effet_temp(p_mercenaire, 'pv_temp');
  if v_total < p_montant then
    raise exception 'Pas assez de PV temporaires (% disponibles).', v_total;
  end if;
  for e in select * from mercenaire_effet
    where mercenaire_id = p_mercenaire and stat = 'pv_temp' and session_id = ctx_session()
    order by created_at for update
  loop
    exit when v_reste <= 0;
    if e.valeur <= v_reste then
      v_reste := v_reste - e.valeur;
      delete from mercenaire_effet where id = e.id;
    else
      update mercenaire_effet set valeur = valeur - v_reste where id = e.id;
      v_reste := 0;
    end if;
  end loop;
  return v_total - p_montant;
end;
$$;

-- 7. Missions : un effet peut accompagner (ou remplacer) l'objet d'une mission individuelle
create or replace function _effet_libelle(p_stat text, p_valeur integer, p_quetes integer)
returns text
language sql
immutable
as $$
  select case p_stat
    when 'pv_temp' then p_valeur || ' PV temporaires (jusqu''à la fin de la prochaine quête)'
    else '+' || p_valeur || ' ' || case p_stat
      when 'puissance' then 'Puissance' when 'velocite' then 'Vélocité' when 'mental' then 'Mental'
      when 'mouvement' then 'Mouvement' when 'sante_max' then 'Santé max' when 'energie_max' then 'Énergie max'
      else p_stat end
      || ' pendant ' || p_quetes || ' quête' || case when p_quetes > 1 then 's' else '' end
  end;
$$;

create or replace function _mission_attribuer(p_mission uuid, p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  m mission%rowtype;
  v_id uuid;
  v_texte text;
begin
  select * into m from mission where id = p_mission;
  insert into mission_attribution (mission_id, user_id, or_verse, objet_id, quantite,
      effet_stat, effet_valeur, effet_quetes, reclamee_le)
    values (m.id, p_user, m.recompense_or, m.recompense_objet_id, m.recompense_quantite,
      m.recompense_effet_stat, m.recompense_effet_valeur, m.recompense_effet_quetes,
      -- objet ou effet d'une mission individuelle : à réclamer (le joueur choisit le mercenaire)
      case when m.rubrique = 'individuelle'
             and (m.recompense_objet_id is not null or m.recompense_effet_stat is not null)
           then null else now() end)
    on conflict do nothing
    returning id into v_id;
  if v_id is null then
    return;
  end if;
  if m.recompense_or > 0 then
    update partie_etat set or_compagnie = or_compagnie + m.recompense_or where id;
  end if;
  if m.rubrique = 'collective' and m.recompense_objet_id is not null then
    perform _arsenal_ajouter(m.recompense_objet_id, m.recompense_quantite);
  end if;
  v_texte := concat_ws(' et ',
    case when m.recompense_or > 0 then '+' || m.recompense_or || ' Po' end,
    case when m.recompense_objet_id is not null
      then (select nom from objet_catalogue where id = m.recompense_objet_id) || ' ×' || m.recompense_quantite end,
    case when m.recompense_effet_stat is not null
      then _effet_libelle(m.recompense_effet_stat, m.recompense_effet_valeur, m.recompense_effet_quetes) end);
  perform _journal('or', 'Mission accomplie : « ' || m.nom || ' »'
    || case when v_texte <> '' then ' (' || v_texte || ').' else '.' end, m.recompense_or,
    jsonb_build_object('mission', m.id, 'rubrique', m.rubrique));
end;
$$;

create or replace function mission_reclamer(p_attribution uuid, p_mercenaire uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  a mission_attribution%rowtype;
  m mission%rowtype;
  v_nom_objet text;
  v_nom_merc text;
  v_message text;
begin
  perform _verrou_partie();
  select * into a from mission_attribution where id = p_attribution for update;
  if not found then
    raise exception 'Récompense introuvable.';
  end if;
  if a.user_id is distinct from auth.uid() then
    raise exception 'Cette récompense est destinée à un autre joueur.';
  end if;
  if a.reclamee_le is not null or (a.objet_id is null and a.effet_stat is null) then
    raise exception 'Cette récompense a déjà été reçue.';
  end if;
  if not exists (select 1 from recrutement where mercenaire_id = p_mercenaire and user_id = auth.uid()) then
    raise exception 'Choisissez l''un de vos mercenaires.';
  end if;
  select * into m from mission where id = a.mission_id;
  select nom into v_nom_merc from mercenaire where id = p_mercenaire;
  v_message := '';
  if a.objet_id is not null then
    select nom into v_nom_objet from objet_catalogue where id = a.objet_id;
    perform _sac_dos_ajouter(_sac_dos_id(p_mercenaire), a.objet_id, a.quantite, null, 'recevoir cette récompense');
    v_message := v_nom_objet || ' ×' || a.quantite || ' rejoint le sac à dos de ' || v_nom_merc || '.';
  end if;
  if a.effet_stat is not null then
    insert into mercenaire_effet (mercenaire_id, stat, valeur, quetes_restantes, mission_id)
      values (p_mercenaire, a.effet_stat, a.effet_valeur,
        case when a.effet_stat = 'pv_temp' then 1 else coalesce(a.effet_quetes, 1) end, a.mission_id);
    v_message := trim(v_message || ' ' || v_nom_merc || ' reçoit '
      || _effet_libelle(a.effet_stat, a.effet_valeur, coalesce(a.effet_quetes, 1))
      || ' (appliqué quand il part en quête).');
  end if;
  update mission_attribution set reclamee_le = now(), mercenaire_id = p_mercenaire where id = a.id;
  perform _journal(case when a.objet_id is not null then 'sac_envoi' else 'equipement' end,
    'Mission « ' || m.nom || ' » : ' || v_message, 0,
    jsonb_build_object('mission', m.id, 'mercenaire_id', p_mercenaire, 'objet_id', a.objet_id, 'effet', a.effet_stat));
  return jsonb_build_object('message', v_message);
end;
$$;

-- 8. Remise à zéro d'une session : les effets temporaires partent aussi
create or replace function session_reinitialiser(p_session uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  t text;
  v_donnees jsonb := '{}'::jsonb;
  v_table jsonb;
  v_ordre text[] := array[
    'mission_attribution', 'mission_compteur', 'mercenaire_effet',
    'cimetiere', 'recrutement_gratuit', 'objet_quete_active', 'creature_quete', 'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
    'mercenaire_equipement', 'ligne_inventaire', 'inventaire', 'atelier_file', 'atelier_fabrication',
    'forge_sertissage', 'employe',
    'partie_journal', 'partie_etat', 'dortoir_reglage', 'entrainement_reglage',
    'infirmerie_reglage', 'mercenaire_etat', 'quete_etat', 'budget_poste'];
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  perform 1 from session where id = p_session for update;
  if not found then
    raise exception 'Session introuvable.';
  end if;
  foreach t in array v_ordre loop
    execute format(
      'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from %I x where x.session_id = $1', t)
      into v_table using p_session;
    v_donnees := v_donnees || jsonb_build_object(t, v_table);
  end loop;
  insert into session_sauvegarde (session_id, motif, donnees)
    values (p_session, 'Remise à zéro par le MJ', v_donnees);
  foreach t in array v_ordre loop
    execute format('delete from %I where session_id = $1', t) using p_session;
  end loop;
  update session set lancee_le = null where id = p_session;
end;
$$;

-- 9. Propriétaire fortress_fn (isolation par session) et droits
grant create on schema public to fortress_fn;
alter function _effet_temp(uuid, text) owner to fortress_fn;
alter function _puissance(uuid) owner to fortress_fn;
alter function _velocite(uuid) owner to fortress_fn;
alter function _mental(uuid) owner to fortress_fn;
alter function _sante_max(uuid) owner to fortress_fn;
alter function mercenaire_depenser_energie(uuid, integer) owner to fortress_fn;
alter function round_avancer() owner to fortress_fn;
alter function mercenaire_restauration_arcanique(uuid) owner to fortress_fn;
alter function sac_dos_utiliser(uuid, uuid, uuid[]) owner to fortress_fn;
alter function _effets_fin_quete(uuid) owner to fortress_fn;
alter function quetes_instance() owner to fortress_fn;
alter function quetes_echec() owner to fortress_fn;
alter function _effets_apres_quete() owner to fortress_fn;
alter function _effets_renvoi() owner to fortress_fn;
alter function effet_pv_temp_depenser(uuid, integer) owner to fortress_fn;
alter function _mission_attribuer(uuid, uuid) owner to fortress_fn;
alter function mission_reclamer(uuid, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _effet_temp(uuid, text) from public;
revoke all on function _effets_fin_quete(uuid) from public;
revoke all on function _effets_apres_quete() from public;
revoke all on function _effets_renvoi() from public;
revoke all on function effet_pv_temp_depenser(uuid, integer) from public;
grant execute on function _effet_temp(uuid, text) to authenticated, fortress_fn;
grant execute on function effet_pv_temp_depenser(uuid, integer) to authenticated;
