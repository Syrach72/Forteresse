-- « Envoyer à la session » (MJ) : ajoute à la main, dans une session DÉJÀ LANCÉE, un élément
-- de la base de départ (objet + recette, mercenaire ou quête) avec ce dont il dépend
-- (catégories, ingrédients, matériaux, outils, classe, objets de récompense). Rien n'est
-- écrasé : un élément déjà présent dans la session (même code, même nom) est refusé.
-- Fonctions propriétaires postgres (elles lisent la base ET écrivent dans une session) : elles
-- vérifient is_admin() elles-mêmes.

create function _env_categorie(p_session uuid, p_cat uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  c categorie%rowtype;
  v_parent uuid;
  v_id uuid;
begin
  select * into c from categorie where id = p_cat and session_id is null;
  if not found then
    raise exception 'Catégorie de la base introuvable.';
  end if;
  if c.parent_id is not null then
    v_parent := _env_categorie(p_session, c.parent_id);
  end if;
  select id into v_id from categorie
    where session_id = p_session and nom = c.nom and parent_id is not distinct from v_parent;
  if v_id is null then
    insert into categorie (nom, actif, parent_id, session_id)
      values (c.nom, c.actif, v_parent, p_session) returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- Objet de la base -> objet de la session (créé s'il n'y est pas encore, avec sa recette).
create function _env_objet(p_session uuid, p_objet uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
  v_id uuid;
  v_mat uuid;
  v_outil uuid;
  r recette%rowtype;
  v_rec uuid;
  i record;
begin
  select * into o from objet_catalogue where id = p_objet and session_id is null;
  if not found then
    raise exception 'Objet de la base introuvable.';
  end if;
  select id into v_id from objet_catalogue where session_id = p_session and code_unique = o.code_unique;
  if v_id is not null then
    return v_id;
  end if;
  insert into objet_catalogue (
    code_unique, nom, description, icone, empilable, utilisable, actif, categorie_id,
    veterance_requise, duree_fabrication_instances, cout_achat_or, portee, protection,
    type_armure, malus_discretion, malus_vitesse, malus_esquive, parade, allonge, type_degats,
    emploi_production, emploi_production_outil, emploi_entretien, deux_mains, session_id)
    values (
      o.code_unique, o.nom, o.description, o.icone, o.empilable, o.utilisable, o.actif,
      _env_categorie(p_session, o.categorie_id), o.veterance_requise, o.duree_fabrication_instances,
      o.cout_achat_or, o.portee, o.protection, o.type_armure, o.malus_discretion, o.malus_vitesse,
      o.malus_esquive, o.parade, o.allonge, o.type_degats, o.emploi_production,
      o.emploi_production_outil, o.emploi_entretien, o.deux_mains, p_session)
    returning id into v_id;
  -- matériau produit / outil d'un employé : créés après coup (évite les boucles)
  if o.emploi_materiau_id is not null then
    v_mat := _env_objet(p_session, o.emploi_materiau_id);
  end if;
  if o.emploi_outil_id is not null then
    v_outil := _env_objet(p_session, o.emploi_outil_id);
  end if;
  update objet_catalogue set emploi_materiau_id = v_mat, emploi_outil_id = v_outil where id = v_id;
  -- recette(s) qui produisent cet objet
  for r in select * from recette where session_id is null and resultat_objet_id = p_objet loop
    if not exists (select 1 from recette where session_id = p_session and code_unique = r.code_unique) then
      insert into recette (code_unique, nom, atelier, resultat_objet_id, quantite_produite, actif, session_id)
        values (r.code_unique, r.nom, r.atelier, v_id, r.quantite_produite, r.actif, p_session)
        returning id into v_rec;
      for i in select objet_id, quantite_requise from ingredient_recette where recette_id = r.id loop
        insert into ingredient_recette (recette_id, objet_id, quantite_requise, session_id)
          values (v_rec, _env_objet(p_session, i.objet_id), i.quantite_requise, p_session);
      end loop;
    end if;
  end loop;
  return v_id;
end;
$$;

create function session_envoyer(p_session uuid, p_type text, p_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_avant integer;
  v_apres integer;
  v_nom text;
  m mercenaire%rowtype;
  q quete%rowtype;
  v_classe uuid;
  v_classe_nom text;
  v_quete uuid;
  rw record;
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  if not session_lancee(p_session) then
    raise exception 'Cette session n''est pas encore lancée : elle prendra la base telle quelle à son lancement.';
  end if;
  select count(*) into v_avant from objet_catalogue where session_id = p_session;

  if p_type = 'objet' then
    select nom into v_nom from objet_catalogue where id = p_id and session_id is null;
    if v_nom is null then
      raise exception 'Objet de la base introuvable.';
    end if;
    if exists (
      select 1 from objet_catalogue s join objet_catalogue b on b.code_unique = s.code_unique
      where s.session_id = p_session and b.id = p_id) then
      raise exception 'Cet objet est déjà présent dans la session.';
    end if;
    perform _env_objet(p_session, p_id);

  elsif p_type = 'mercenaire' then
    select * into m from mercenaire where id = p_id and session_id is null;
    if not found then
      raise exception 'Mercenaire de la base introuvable.';
    end if;
    v_nom := m.nom;
    if exists (select 1 from mercenaire where session_id = p_session and nom = m.nom) then
      raise exception 'Un mercenaire de ce nom existe déjà dans la session.';
    end if;
    select nom into v_classe_nom from classe where id = m.classe_id;
    if v_classe_nom is not null then
      select id into v_classe from classe where session_id = p_session and nom = v_classe_nom;
      if v_classe is null then
        insert into classe (nom, actif, session_id)
          select nom, actif, p_session from classe where id = m.classe_id returning id into v_classe;
      end if;
    end if;
    insert into mercenaire (
      nom, portrait, role, veterance, attaque, defense, esprit, mouvement, mana, sante,
      notes, actif, classe_id, session_id)
      values (m.nom, m.portrait, m.role, m.veterance, m.attaque, m.defense, m.esprit,
        m.mouvement, m.mana, m.sante, m.notes, m.actif, v_classe, p_session);

  elsif p_type = 'quete' then
    select * into q from quete where id = p_id and session_id is null;
    if not found then
      raise exception 'Quête de la base introuvable.';
    end if;
    v_nom := q.nom;
    if exists (select 1 from quete where session_id = p_session and nom = q.nom) then
      raise exception 'Une quête de ce nom existe déjà dans la session.';
    end if;
    insert into quete (
      nom, description, veterance_requise, icone, recompense_or, actif, instances_requises, session_id)
      values (q.nom, q.description, q.veterance_requise, q.icone, q.recompense_or, q.actif,
        q.instances_requises, p_session)
      returning id into v_quete;
    for rw in select position, objet_id, quantite from quete_recompense where quete_id = p_id loop
      insert into quete_recompense (quete_id, position, objet_id, quantite, session_id)
        values (v_quete, rw.position, _env_objet(p_session, rw.objet_id), rw.quantite, p_session);
    end loop;

  else
    raise exception 'Type inconnu : objet, mercenaire ou quete.';
  end if;

  select count(*) into v_apres from objet_catalogue where session_id = p_session;
  return jsonb_build_object('type', p_type, 'nom', v_nom, 'objets_ajoutes', v_apres - v_avant);
end;
$$;

revoke all on function _env_categorie(uuid, uuid), _env_objet(uuid, uuid), session_envoyer(uuid, text, uuid) from public;
grant execute on function session_envoyer(uuid, text, uuid) to authenticated;
