-- Récompense mystère (Bruno, 2026-09-30) : toutes les quêtes affichent un « ? » parmi leurs
-- récompenses ; à l'accomplissement il devient un objet tiré au hasard (Armes, Boucliers, Objets
-- divers, Produits alchimiques). L'objet entre dans l'arsenal et dans la liste `items` du +1 Instance,
-- donc quetes_annuler_instance() (inchangée) le retire aussi en cas d'annulation.
-- Reprend quetes_instance() de 20260926220000.

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
  if q.recompense_or > 0 then
    update partie_etat set or_compagnie = or_compagnie + q.recompense_or where id;
  end if;
  for r in select objet_id, quantite from quete_recompense where quete_id = q.id order by position
  loop
    perform _arsenal_ajouter(r.objet_id, r.quantite);
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
    perform _arsenal_ajouter(v_myst_id, 1);
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
    set en_cours = false, terminee_le = now(), instances_restantes = 0
    where quete_id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : +' || q.recompense_or || ' Po, ' || jsonb_array_length(v_items) || ' objet(s) rejoignent l''arsenal'
      || coalesce(' (récompense mystère : ' || v_myst_nom || ')', '') || ', '
      || v_gagnants || ' mercenaire(s) gagnent +1 de vétérance ; l''énergie des mercenaires engagés revient au maximum.',
    q.recompense_or, jsonb_build_object('quete_id', q.id, 'items', v_items, 'mercenaires', v_mercs));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs, 'mystere_nom', v_myst_nom);
end;
$$;

