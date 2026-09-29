-- Calèche (règle de Bruno, 2026-09-29) : dès que la compagnie possède l'objet de quête « Calèche »
-- (arsenal commun), le sac à dos de TOUS les mercenaires, présents ou à venir, gagne 3 emplacements
-- (9 -> 12). La capacité est calculée à chaque envoi plutôt que stockée : aucun sac à mettre à jour,
-- et les futurs mercenaires en bénéficient automatiquement.
create or replace function _sac_capacite()
returns integer
language sql
stable
security definer set search_path = public
as $$
  select 9 + case when exists (
    select 1 from ligne_inventaire l
      join objet_catalogue o on o.id = l.objet_id
    where l.inventaire_id = _arsenal_id() and l.quantite > 0
      and lower(o.nom) in ('calèche', 'caleche')
  ) then 3 else 0 end;
$$;
revoke all on function _sac_capacite() from public;
grant execute on function _sac_capacite() to authenticated, fortress_fn;

-- Les deux fonctions qui plafonnaient le sac à 9 utilisent désormais _sac_capacite().
create or replace function sac_dos_envoyer(p_mercenaire uuid, p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
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
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
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
  if v_racine is null or v_racine not in ('Composants', 'Objet divers', 'Armes', 'Armures', 'Produits Alchimiques') then
    raise exception 'Seuls les composants alchimiques, les produits alchimiques, les armes, les armures et les objets divers peuvent rejoindre un sac à dos.';
  end if;
  if v_gemmes is not null and p_quantite <> 1 then
    raise exception 'Une arme sertie s''envoie une par une.';
  end if;
  if _arsenal_quantite(p_objet, v_gemmes) < p_quantite then
    raise exception 'Quantité insuffisante dans l''arsenal.';
  end if;
  v_sac := _sac_dos_id(p_mercenaire);
  if v_gemmes is null then
    select quantite into v_actuel from ligne_inventaire
      where inventaire_id = v_sac and objet_id = p_objet and gemmes is null and quantite > 0
      order by created_at, id limit 1;
  end if;
  if v_actuel is not null then
    if v_actuel + p_quantite > 3 then
      raise exception 'Cet emplacement du sac à dos ne peut pas dépasser 3 (encore % disponible(s)) : libérez d''abord de la place avant de transférer l''objet.', 3 - v_actuel;
    end if;
    update ligne_inventaire set quantite = quantite + p_quantite, updated_at = now()
      where id = (
        select id from ligne_inventaire
        where inventaire_id = v_sac and objet_id = p_objet and gemmes is null and quantite > 0
        order by created_at, id limit 1);
  else
    if p_quantite > 3 then
      raise exception 'Un emplacement du sac à dos ne peut pas dépasser 3.';
    end if;
    select count(*) into v_compte from ligne_inventaire where inventaire_id = v_sac and quantite > 0;
    if v_compte >= _sac_capacite() then
      raise exception 'Le sac à dos est plein : libérez d''abord un emplacement avant de pouvoir transférer l''objet.';
    end if;
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (v_sac, p_objet, p_quantite, v_gemmes);
  end if;
  perform _arsenal_retirer(p_objet, p_quantite, v_gemmes);
  perform _journal('sac_envoi', v_nom || ' ×' || p_quantite || ' envoyé au sac à dos.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'quantite', p_quantite, 'gemmes', v_gemmes));
end;
$$;

create or replace function _sac_dos_ajouter(p_sac uuid, p_objet uuid, p_quantite integer, p_gemmes uuid[], p_action text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_empilable boolean;
  v_ligne uuid;
  v_actuel integer;
  v_compte integer;
begin
  select empilable into v_empilable from objet_catalogue where id = p_objet;
  if v_gemmes is null and coalesce(v_empilable, true) then
    select id, quantite into v_ligne, v_actuel from ligne_inventaire
      where inventaire_id = p_sac and objet_id = p_objet and gemmes is null and quantite > 0
      order by created_at, id limit 1
      for update;
  end if;
  if v_ligne is not null then
    if v_actuel + p_quantite > 3 then
      raise exception 'Cet emplacement du sac à dos est complet (3 au plus) : libérez d''abord de la place avant de %.', p_action;
    end if;
    update ligne_inventaire set quantite = quantite + p_quantite, updated_at = now() where id = v_ligne;
  else
    select count(*) into v_compte from ligne_inventaire where inventaire_id = p_sac and quantite > 0;
    if v_compte >= _sac_capacite() then
      raise exception 'Le sac à dos est plein : libérez d''abord un emplacement avant de %.', p_action;
    end if;
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (p_sac, p_objet, p_quantite, v_gemmes);
  end if;
end;
$$;

grant create on schema public to fortress_fn;
alter function _sac_capacite() owner to fortress_fn;
revoke create on schema public from fortress_fn;
