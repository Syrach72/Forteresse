-- Récompenses de quête (Bruno, 2026-09-30) :
--  * toutes les quêtes affichent un « ? » parmi leurs récompenses ; à l'accomplissement il devient un
--    objet tiré au hasard (Armes, Boucliers, Objets divers, Produits alchimiques) ;
--  * à la fin de la quête, une fenêtre montre les récompenses ; ce n'est qu'à sa fermeture
--    (quete_recompenses_recuperer) que l'or et les objets rejoignent la compagnie. D'ici là ils
--    sont stockés dans quete_etat.recompenses_attente (une annulation du +1 Instance les abandonne).
-- Reprend quetes_instance() et quetes_annuler_instance() de 20260926220000.

alter table quete_etat add column if not exists recompenses_attente jsonb;

create or replace function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  e quete_etat%rowtype;
  r record;
  v_avant integer;
  v_apres integer;
  v_vet_avant integer;
  v_vet_apres integer;
  v_energie integer;
  v_gagnants integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_mercs jsonb := '[]'::jsonb;
  v_myst_id uuid;
  v_myst_nom text;
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
  for r in select objet_id, quantite from quete_recompense where quete_id = q.id order by position
  loop
    v_items := v_items || jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite);
  end loop;
  -- Récompense mystère « ? » (Bruno, 2026-09-30) : chaque quête accomplie donne un objet tiré au
  -- hasard, à égalité, parmi les Armes, les Boucliers, les Objets divers et les Produits alchimiques
  -- du catalogue (objets actifs, visibles dans la session).
  select o.id, o.nom into v_myst_id, v_myst_nom
    from objet_catalogue o
    where o.actif
      and (o.session_id = ctx_session()
           or (o.session_id is null
               and not exists (select 1 from objet_catalogue s
                               where s.session_id = ctx_session() and s.code_unique = o.code_unique)))
      and (
        _est_bouclier(o.categorie_id)
        or _racine_categorie(o.categorie_id) in ('Objet divers', 'Produits Alchimiques')
        or (_racine_categorie(o.categorie_id) = 'Armes'
            and not exists (
              with recursive chaine as (
                select id, nom, parent_id from categorie where id = o.categorie_id
                union all
                select c.id, c.nom, c.parent_id from categorie c join chaine ch on c.id = ch.parent_id)
              select 1 from chaine where lower(btrim(nom)) = 'objets'))
      )
    order by random() limit 1;
  if v_myst_id is not null then
    v_items := v_items || jsonb_build_object('objet_id', v_myst_id, 'quantite', 1, 'mystere', true, 'nom', v_myst_nom);
  end if;
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
          'or', q.recompense_or, 'items', v_items)
    where quete_id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : récompenses à récupérer, '
      || v_gagnants || ' mercenaire(s) gagnent +1 de vétérance ; l''énergie des mercenaires engagés revient au maximum.',
    0, jsonb_build_object('quete_terminee', q.id, 'mercenaires', v_mercs));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs, 'mystere_nom', v_myst_nom,
    'attente', true);
end;
$$;

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

-- Fermeture de la fenêtre de récompenses : l'or et les objets (dont l'objet mystère) rejoignent
-- enfin la compagnie. Renvoie les récompenses récupérées, ou null s'il n'y en avait pas.
create or replace function quete_recompenses_recuperer()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  e quete_etat%rowtype;
  i jsonb;
  v_or integer;
  v_nom text;
  v_myst text;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select * into e from quete_etat where recompenses_attente is not null
    order by terminee_le desc nulls last limit 1 for update;
  if not found then
    return null;
  end if;
  v_or := coalesce((e.recompenses_attente ->> 'or')::integer, 0);
  v_nom := e.recompenses_attente ->> 'nom';
  if v_or > 0 then
    update partie_etat set or_compagnie = or_compagnie + v_or where id;
  end if;
  for i in select * from jsonb_array_elements(coalesce(e.recompenses_attente -> 'items', '[]'::jsonb))
  loop
    perform _arsenal_ajouter((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
    if coalesce((i ->> 'mystere')::boolean, false) then
      v_myst := i ->> 'nom';
    end if;
  end loop;
  update quete_etat set recompenses_attente = null where quete_id = e.quete_id;
  perform _journal('or',
    v_nom || ' : +' || v_or || ' Po, '
      || jsonb_array_length(coalesce(e.recompenses_attente -> 'items', '[]'::jsonb))
      || ' objet(s) rejoignent l''arsenal' || coalesce(' (récompense mystère : ' || v_myst || ')', '') || '.',
    v_or, jsonb_build_object('quete_id', e.quete_id, 'items', e.recompenses_attente -> 'items'));
  return e.recompenses_attente;
end;
$$;

grant create on schema public to fortress_fn;
alter function quetes_instance() owner to fortress_fn;
alter function quetes_annuler_instance(jsonb) owner to fortress_fn;
alter function quete_recompenses_recuperer() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function quete_recompenses_recuperer() from public;
grant execute on function quete_recompenses_recuperer() to authenticated;
