-- Récompense mystère (Bruno, 2026-09-30, version 2) : le « ? » n'est plus automatique sur toutes les
-- quêtes ; c'est un objet du catalogue (« Récompense mystère », rubrique Objets de Quête) que le MJ place
-- dans les emplacements de récompense des quêtes voulues. Et la fenêtre de récompenses s'affiche chez tous
-- les joueurs : n'importe lequel peut la fermer, la première fermeture fait rejoindre les récompenses.
-- Reprend quetes_instance() et quete_recompenses_recuperer() de 20260930140000.

-- L'objet « Récompense mystère » : à placer dans un emplacement de récompense d'une quête (quantité =
-- nombre d'objets tirés au hasard). Rubrique « Objets de Quête » (le catalogue est commun à toutes les sessions).
insert into objet_catalogue (code_unique, nom, description, icone, categorie_id, empilable, utilisable, actif)
select 'recompense-mystere', 'Récompense mystère',
  'Objet aléatoire : à la fin de la quête, il est remplacé par un objet tiré au hasard parmi les armes, boucliers, objets divers et produits alchimiques.',
  '/assets/icons/mystere.webp', c.id, true, false, true
from categorie c
where c.nom = 'Objets de Quête' and c.parent_id is null
  and not exists (select 1 from objet_catalogue x where x.code_unique = 'recompense-mystere');

-- Tirage d'un objet au hasard, à égalité, parmi les Armes, les Boucliers, les Objets divers et les
-- Produits alchimiques du catalogue (objets actifs du catalogue).
create or replace function _objet_mystere_tirer()
returns table (id uuid, nom text)
language sql
volatile
security definer set search_path = public
as $$
  select o.id, o.nom
    from objet_catalogue o
    where o.actif
      and (
        _est_bouclier(o.categorie_id)
        or _racine_categorie(o.categorie_id) in ('Objet divers', 'Produits Alchimiques')
        or (_racine_categorie(o.categorie_id) = 'Armes'
            and not exists (
              with recursive chaine as (
                select c0.id, c0.nom, c0.parent_id from categorie c0 where c0.id = o.categorie_id
                union all
                select c.id, c.nom, c.parent_id from categorie c join chaine ch on c.id = ch.parent_id)
              select 1 from chaine where lower(btrim(chaine.nom)) = 'objets'))
      )
    order by random() limit 1;
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
  -- (Armes, Boucliers, Objets divers, Produits alchimiques).
  for r in
    select qr.objet_id, qr.quantite, (o.code_unique = 'recompense-mystere') as myst
      from quete_recompense qr join objet_catalogue o on o.id = qr.objet_id
      where qr.quete_id = q.id order by qr.position
  loop
    if r.myst then
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
  if auth.uid() is null then
    raise exception 'Connexion requise.';
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
alter function _objet_mystere_tirer() owner to fortress_fn;
alter function quetes_instance() owner to fortress_fn;
alter function quete_recompenses_recuperer() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _objet_mystere_tirer() from public;
grant execute on function quetes_instance() to authenticated;
grant execute on function quete_recompenses_recuperer() to authenticated;
