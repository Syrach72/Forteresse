-- Sac a dos par mercenaire (regle de Bruno, 2026-09-22), en remplacement de
-- l'ancien "inventaire de campagne" (jamais branche a la base, purement
-- local, desormais sans point d'entree dans l'interface) :
--  * 9 emplacements, chacun un seul type d'objet, empilable jusqu'a 3 ;
--  * depuis l'Arsenal, un joueur peut envoyer vers le sac a dos d'un
--    mercenaire recrute la quantite qu'il veut d'un objet des rubriques
--    Composants ou Objet divers UNIQUEMENT ;
--  * depuis le sac a dos (fiche du mercenaire), n'importe quel objet qui s'y
--    trouve peut repartir vers l'arsenal, sans restriction de categorie.
--
-- Reutilise le type_inventaire 'campagne' et inventaire.mercenaire_id, deja
-- prevus dans le schema initial (20260911120000_init_socle.sql) mais jamais
-- exploites, ainsi que les outils communs de 20260921130000_economie_partagee.sql
-- (_verrou_partie, _arsenal_quantite/_ajouter/_retirer, _journal).

-- ---------------------------------------------------------------------------
-- Racine (categorie sans parent) d'une categorie donnee : meme principe que
-- la fonction cote client (Admin.jsx racineDe), pour verifier serveur que
-- l'objet envoye vient bien de Composants ou Objet divers.
-- ---------------------------------------------------------------------------
create function _racine_categorie(p_categorie uuid)
returns text
language sql
stable
security definer set search_path = public
as $$
  with recursive chaine as (
    select id, nom, parent_id from categorie where id = p_categorie
    union all
    select c.id, c.nom, c.parent_id from categorie c join chaine ch on c.id = ch.parent_id
  )
  select nom from chaine where parent_id is null limit 1;
$$;

create function _sac_dos_id(p_mercenaire uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from inventaire
    where type = 'campagne' and mercenaire_id = p_mercenaire
    order by created_at, id limit 1;
  if v_id is null then
    insert into inventaire (type, nom, mercenaire_id)
      values ('campagne', 'Sac à dos', p_mercenaire)
      returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Arsenal -> sac a dos. Cree l'emplacement si l'objet n'y est pas deja (echoue
-- si les 9 sont pris), sinon complete l'empilement existant (echoue au-dela
-- de 3). Quantite retiree de l'arsenal commun.
-- ---------------------------------------------------------------------------
create function sac_dos_envoyer(p_mercenaire uuid, p_objet uuid, p_quantite integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_sac uuid;
  v_racine text;
  v_actuel integer;
  v_compte integer;
  v_nom text;
begin
  perform _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id) into v_nom, v_racine
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  if v_racine is distinct from 'Composants' and v_racine is distinct from 'Objet divers' then
    raise exception 'Seuls les composants alchimiques et les objets divers peuvent rejoindre un sac à dos.';
  end if;
  if _arsenal_quantite(p_objet) < p_quantite then
    raise exception 'Quantité insuffisante dans l''arsenal.';
  end if;
  v_sac := _sac_dos_id(p_mercenaire);
  select quantite into v_actuel from ligne_inventaire
    where inventaire_id = v_sac and objet_id = p_objet;
  if v_actuel is not null then
    if v_actuel + p_quantite > 3 then
      raise exception 'Cet emplacement ne peut pas dépasser 3 (encore % disponible(s)).', 3 - v_actuel;
    end if;
    update ligne_inventaire set quantite = quantite + p_quantite, updated_at = now()
      where inventaire_id = v_sac and objet_id = p_objet;
  else
    if p_quantite > 3 then
      raise exception 'Un emplacement du sac à dos ne peut pas dépasser 3.';
    end if;
    select count(*) into v_compte from ligne_inventaire where inventaire_id = v_sac and quantite > 0;
    if v_compte >= 9 then
      raise exception 'Le sac à dos est plein (9 emplacements).';
    end if;
    insert into ligne_inventaire (inventaire_id, objet_id, quantite) values (v_sac, p_objet, p_quantite);
  end if;
  perform _arsenal_retirer(p_objet, p_quantite);
  perform _journal('sac_envoi', v_nom || ' ×' || p_quantite || ' envoyé au sac à dos.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'quantite', p_quantite));
end;
$$;

-- ---------------------------------------------------------------------------
-- Sac a dos -> arsenal. N'importe quel objet du sac, sans restriction.
-- ---------------------------------------------------------------------------
create function sac_dos_retirer(p_mercenaire uuid, p_objet uuid, p_quantite integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_sac uuid;
  v_actuel integer;
  v_nom text;
begin
  perform _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  select nom into v_nom from objet_catalogue where id = p_objet;
  v_sac := _sac_dos_id(p_mercenaire);
  select quantite into v_actuel from ligne_inventaire
    where inventaire_id = v_sac and objet_id = p_objet;
  if v_actuel is null or v_actuel < p_quantite then
    raise exception 'Cet objet n''est pas disponible en telle quantité dans le sac à dos.';
  end if;
  if v_actuel = p_quantite then
    delete from ligne_inventaire where inventaire_id = v_sac and objet_id = p_objet;
  else
    update ligne_inventaire set quantite = quantite - p_quantite, updated_at = now()
      where inventaire_id = v_sac and objet_id = p_objet;
  end if;
  perform _arsenal_ajouter(p_objet, p_quantite);
  perform _journal('sac_retour', coalesce(v_nom, 'Objet') || ' ×' || p_quantite || ' rendu à l''arsenal depuis le sac à dos.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'quantite', p_quantite));
end;
$$;

-- ---------------------------------------------------------------------------
-- Nouveaux types de journal (le contrainte existante ne les listait pas).
-- Recherche le nom reel de la contrainte plutot que de le supposer.
-- ---------------------------------------------------------------------------
do $$
declare
  v_conname text;
begin
  select con.conname into v_conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    where rel.relname = 'partie_journal' and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%type%';
  if v_conname is not null then
    execute format('alter table partie_journal drop constraint %I', v_conname);
  end if;
end;
$$;
alter table partie_journal add constraint partie_journal_type_check
  check (type in ('achat', 'vente', 'destruction', 'fabrication', 'recuperation', 'depense', 'or', 'annulation', 'sac_envoi', 'sac_retour'));

revoke all on function _racine_categorie(uuid) from public;
revoke all on function _sac_dos_id(uuid) from public;
revoke all on function sac_dos_envoyer(uuid, uuid, integer) from public;
revoke all on function sac_dos_retirer(uuid, uuid, integer) from public;
grant execute on function sac_dos_envoyer(uuid, uuid, integer) to authenticated;
grant execute on function sac_dos_retirer(uuid, uuid, integer) to authenticated;
