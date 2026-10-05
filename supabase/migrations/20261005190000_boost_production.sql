-- Boost de production (Bruno, 2026-10-05) : l'objet de quête « Boost de production » (code boost) n'entre PAS à
-- l'arsenal. Quand la quête qui le donne est accomplie (+1 Instance), la production d'un matériau (bois, fer ou
-- cuir, choisi dans quete_recompense.materiau) est doublée pendant 3 instances : celle du +1 Instance qui accomplit
-- la quête (la quête est traitée avant les employés) puis les deux suivantes. Le compte est dans partie_etat
-- (boost_bois / boost_fer / boost_cuir = instances restantes), donc propre à la session et remis à zéro avec elle.
--  * quetes_instance : le boost est activé au lieu d'être donné ; il figure dans la fenêtre de récompenses
--    (recompenses_attente.boosts) mais pas dans les objets. Sans matériau choisi il n'est pas appliqué.
--  * quetes_annuler_instance : annuler l'accomplissement rétablit le compte d'avant.
--  * employes_instance : production x2 des ouvriers du matériau concerné (bâtiment x2 compris : cumul x4).
--  * boosts_instance / boosts_annuler_instance : décompte d'une instance (appelé APRÈS les employés) et son annulation.
--  * boosts_production : matériaux boostés et instances restantes, pour l'affichage.

alter table partie_etat
  add column boost_bois smallint not null default 0 check (boost_bois between 0 and 99),
  add column boost_fer smallint not null default 0 check (boost_fer between 0 and 99),
  add column boost_cuir smallint not null default 0 check (boost_cuir between 0 and 99);

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

-- Annuler l'accomplissement rétablit aussi le compte des boosts d'avant (seulement si personne ne l'a changé).
create or replace function quetes_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  i jsonb;
  v_quete uuid;
  v_merc uuid;
  v_attente jsonb;
  v_mat text;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_gains is null then
    return;
  end if;
  perform _verrou_partie();
  v_quete := (p_gains ->> 'quete_id')::uuid;
  if not coalesce((p_gains ->> 'termine')::boolean, true) then
    update quete_etat
      set instances_restantes = (p_gains ->> 'avant')::integer
      where quete_id = v_quete and en_cours
        and instances_restantes = (p_gains ->> 'apres')::integer;
    return;
  end if;
  if exists (select 1 from quete_etat where en_cours and quete_id <> v_quete) then
    raise exception 'Une autre quête est en cours : impossible de rouvrir celle-ci.';
  end if;
  select recompenses_attente into v_attente from quete_etat where quete_id = v_quete;
  if v_attente is not null then
    -- Récompenses pas encore récupérées : rien n'est entré dans l'arsenal, on les abandonne.
    update quete_etat set recompenses_attente = null where quete_id = v_quete;
  else
    if coalesce((p_gains ->> 'or')::integer, 0) > 0 then
      update partie_etat set or_compagnie = or_compagnie - (p_gains ->> 'or')::integer where id;
    end if;
    for i in select * from jsonb_array_elements(coalesce(p_gains -> 'items', '[]'::jsonb))
    loop
      perform _arsenal_retirer((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
    end loop;
  end if;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'boosts_gain', '[]'::jsonb))
  loop
    v_mat := i ->> 'materiau';
    update partie_etat
      set boost_bois = case when v_mat = 'bois' and boost_bois = (i ->> 'apres')::integer then (i ->> 'avant')::integer else boost_bois end,
          boost_fer = case when v_mat = 'fer' and boost_fer = (i ->> 'apres')::integer then (i ->> 'avant')::integer else boost_fer end,
          boost_cuir = case when v_mat = 'cuir' and boost_cuir = (i ->> 'apres')::integer then (i ->> 'avant')::integer else boost_cuir end
      where id;
  end loop;
  update quete_etat
    set en_cours = true, terminee_le = null,
        instances_restantes = greatest(coalesce((p_gains ->> 'avant')::integer, 1), 1)
    where quete_id = v_quete;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'mercenaires', '[]'::jsonb))
  loop
    v_merc := (i ->> 'mercenaire_id')::uuid;
    -- La vétérance gagnée à la fin de la quête est reprise (seulement si elle n'a pas bougé depuis).
    if coalesce((i ->> 'veterance_apres')::integer, 0) > coalesce((i ->> 'veterance_avant')::integer, 0) then
      update mercenaire_etat
        set veterance = (i ->> 'veterance_avant')::integer
        where mercenaire_id = v_merc and session_id = ctx_session()
          and veterance = (i ->> 'veterance_apres')::integer;
    end if;
    -- L'énergie d'avant la fin de la quête est reprise (seulement si elle n'a pas été modifiée depuis).
    if (i ->> 'energie_avant') is not null then
      update mercenaire_etat
        set energie_actuelle = (i ->> 'energie_avant')::integer
        where mercenaire_id = v_merc and session_id = ctx_session() and energie_actuelle is null;
    end if;
    if exists (select 1 from recrutement where mercenaire_id = v_merc)
       and not exists (select 1 from quete_mercenaire where mercenaire_id = v_merc)
       and not exists (select 1 from entrainement_place where mercenaire_id = v_merc)
       and not exists (select 1 from infirmerie_place where mercenaire_id = v_merc)
       and not exists (
         select 1 from quete_mercenaire
         where quete_id = v_quete and position = (i ->> 'position')::integer)
    then
      insert into quete_mercenaire (quete_id, position, mercenaire_id)
        values (v_quete, (i ->> 'position')::integer, v_merc);
    end if;
  end loop;
  perform _journal('annulation', 'Quête accomplie annulée (+1 Instance annulé).',
    case when v_attente is null then -coalesce((p_gains ->> 'or')::integer, 0) else 0 end, jsonb_build_object('annule_quete', p_gains ->> 'quete_id'));
end;
$$;

create or replace function employes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  o objet_catalogue%rowtype;
  v_gains jsonb := '[]'::jsonb;
  v_production integer;
  v_entretien integer;
  v_total_entretien integer := 0;
  v_batiment_possede boolean;
  v_code text;
  v_b_bois integer := 0;
  v_b_fer integer := 0;
  v_b_cuir integer := 0;
  v_boost boolean;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  select boost_bois, boost_fer, boost_cuir into v_b_bois, v_b_fer, v_b_cuir from partie_etat where id;
  for r in select * from employe where quantite > 0 order by objet_id, outil for update
  loop
    v_boost := false;
    select * into o from objet_catalogue where id = r.objet_id;
    if _racine_categorie(o.categorie_id) = 'Collecte' and o.emploi_materiau_id is not null then
      select coalesce(sum((floor(random() * 6) + 5)::integer), 0) into v_production
        from generate_series(1, r.quantite);
      if o.emploi_outil_id is not null then
        select exists (
          select 1 from employe where objet_id = o.emploi_outil_id and quantite >= 1
        ) into v_batiment_possede;
        if v_batiment_possede then
          v_production := v_production * 2;
        end if;
      end if;
      -- Boost de production du matériau (bois, métal = « fer », cuir) : x2.
      select code_unique into v_code from objet_catalogue where id = o.emploi_materiau_id;
      if (v_code = 'bois' and coalesce(v_b_bois, 0) > 0)
         or (v_code = 'metal' and coalesce(v_b_fer, 0) > 0)
         or (v_code = 'cuir' and coalesce(v_b_cuir, 0) > 0) then
        v_production := v_production * 2;
        v_boost := true;
      end if;
    else
      v_production := r.quantite * (coalesce(o.emploi_production, 0)
        + case when r.outil then coalesce(o.emploi_production_outil, 0) else 0 end);
    end if;
    v_entretien := r.quantite * coalesce(o.emploi_entretien, 0);
    if v_production > 0 and o.emploi_materiau_id is not null then
      perform _arsenal_ajouter(o.emploi_materiau_id, v_production);
    end if;
    v_total_entretien := v_total_entretien + v_entretien;
    v_gains := v_gains || jsonb_build_object(
      'objet_id', r.objet_id, 'outil', r.outil,
      'materiau_id', o.emploi_materiau_id, 'produit', v_production, 'entretien', v_entretien, 'boost', v_boost);
  end loop;
  if v_total_entretien > 0 then
    update partie_etat set or_compagnie = or_compagnie - v_total_entretien where id;
  end if;
  if jsonb_array_length(v_gains) > 0 then
    perform _journal('production', 'Production des employés : entretien −' || v_total_entretien || ' Po.'
      || case when coalesce(v_b_bois, 0) + coalesce(v_b_fer, 0) + coalesce(v_b_cuir, 0) > 0 then ' Boost de production en cours.' else '' end,
      -v_total_entretien, jsonb_build_object('gains', v_gains));
  end if;
  return v_gains;
end;
$$;

-- Décompte d'une instance des boosts (à appeler après employes_instance) : renvoie les matériaux décomptés.
create function boosts_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  p partie_etat%rowtype;
  v jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  select * into p from partie_etat where id;
  if not found then
    return v;
  end if;
  if p.boost_bois > 0 then v := v || '"bois"'::jsonb; end if;
  if p.boost_fer > 0 then v := v || '"fer"'::jsonb; end if;
  if p.boost_cuir > 0 then v := v || '"cuir"'::jsonb; end if;
  update partie_etat
    set boost_bois = greatest(boost_bois - 1, 0),
        boost_fer = greatest(boost_fer - 1, 0),
        boost_cuir = greatest(boost_cuir - 1, 0)
    where id;
  return v;
end;
$$;

create function boosts_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  m text;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for m in select jsonb_array_elements_text(coalesce(p_gains, '[]'::jsonb))
  loop
    update partie_etat
      set boost_bois = case when m = 'bois' then least(boost_bois + 1, 99) else boost_bois end,
          boost_fer = case when m = 'fer' then least(boost_fer + 1, 99) else boost_fer end,
          boost_cuir = case when m = 'cuir' then least(boost_cuir + 1, 99) else boost_cuir end
      where id;
  end loop;
end;
$$;

-- Matériaux boostés (instances restantes), avec l'objet du catalogue : pour l'affichage chez tous les joueurs.
create function boosts_production()
returns table (materiau text, objet_id uuid, restant integer)
language sql
stable
security definer set search_path = public
as $$
  select m.mat, o.id, m.restant
  from (
    select 'bois'::text as mat, 'bois'::text as code, p.boost_bois::integer as restant from partie_etat p where p.id
    union all
    select 'fer', 'metal', p.boost_fer::integer from partie_etat p where p.id
    union all
    select 'cuir', 'cuir', p.boost_cuir::integer from partie_etat p where p.id
  ) m
  join objet_catalogue o on o.code_unique = m.code
  where m.restant > 0;
$$;

grant create on schema public to fortress_fn;
alter function quetes_instance() owner to fortress_fn;
alter function quetes_annuler_instance(jsonb) owner to fortress_fn;
alter function employes_instance() owner to fortress_fn;
alter function boosts_instance() owner to fortress_fn;
alter function boosts_annuler_instance(jsonb) owner to fortress_fn;
alter function boosts_production() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function boosts_instance(), boosts_annuler_instance(jsonb), boosts_production() from public;
grant execute on function quetes_instance(), quetes_annuler_instance(jsonb), employes_instance(),
  boosts_instance(), boosts_annuler_instance(jsonb), boosts_production() to authenticated;
