-- Équiper une arme : contrôle de la classe du mercenaire (Bruno, 2026-09-30).
--  * Armes de guerre : Paladin et Guerrier uniquement.
--  * Armes de moine  : Moine uniquement.
-- Les autres armes (courantes, objets…) restent libres. Le contrôle est côté serveur dans
-- sac_dos_equiper(), seul chemin d'équipement depuis l'inventaire / le sac à dos.

create or replace function sac_dos_equiper(p_mercenaire uuid, p_objet uuid, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_merc text;
  v_nom text;
  v_racine text;
  v_categorie uuid;
  v_classe text;
  v_restriction text;
  v_bouclier boolean;
  v_emp text;
  v_max integer;
  v_pos integer;
  v_sac uuid;
  v_ligne uuid;
  v_qte integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  if v_merc is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id), _est_bouclier(categorie_id), categorie_id
    into v_nom, v_racine, v_bouclier, v_categorie
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  v_emp := case v_racine
    when 'Armes' then 'arme'
    when 'Armures' then case when v_bouclier then 'bouclier' else 'armure' end
    when 'Objet divers' then 'objet' end;
  if v_emp is null then
    raise exception 'Seuls les armes, les armures, les boucliers et les objets divers peuvent être équipés.';
  end if;
  -- Restriction par classe (Bruno, 2026-09-30) : les armes de guerre sont réservées aux
  -- Paladins et aux Guerriers, les armes de moine aux Moines. La rubrique se lit sur
  -- la catégorie de l'objet ou l'un de ses ancêtres.
  if v_emp = 'arme' then
    select c.nom into v_classe from mercenaire m join classe c on c.id = m.classe_id
      where m.id = p_mercenaire;
    with recursive chaine as (
      select id, nom, parent_id from categorie where id = v_categorie
      union all
      select c.id, c.nom, c.parent_id from categorie c join chaine ch on c.id = ch.parent_id
    )
    select case
        when bool_or(lower(btrim(nom)) = 'armes de guerre') then 'guerre'
        when bool_or(lower(btrim(nom)) = 'armes de moine') then 'moine' end
      into v_restriction from chaine;
    if v_restriction = 'guerre' and lower(coalesce(v_classe, '')) not in ('paladin', 'guerrier') then
      raise exception '% ne peut pas équiper % : les armes de guerre sont réservées aux Paladins et aux Guerriers.', v_merc, v_nom;
    end if;
    if v_restriction = 'moine' and lower(coalesce(v_classe, '')) <> 'moine' then
      raise exception '% ne peut pas équiper % : les armes de moine sont réservées aux Moines.', v_merc, v_nom;
    end if;
  end if;
  v_max := case when v_emp in ('armure', 'bouclier') then 0 else 2 end;
  select g.p into v_pos from generate_series(0, v_max) as g(p)
    where not exists (
      select 1 from mercenaire_equipement e
      where e.mercenaire_id = p_mercenaire and e.emplacement = v_emp and e.position = g.p)
    order by g.p limit 1;
  if v_pos is null then
    raise exception '%', case v_emp
      when 'arme' then v_merc || ' porte déjà 3 armes : déséquipez-en une d''abord.'
      when 'armure' then v_merc || ' porte déjà une armure : déséquipez-la d''abord.'
      when 'bouclier' then v_merc || ' porte déjà un bouclier : déséquipez-le d''abord.'
      else v_merc || ' porte déjà 3 objets : déséquipez-en un d''abord.' end;
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
  insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id, gemmes)
    values (p_mercenaire, v_emp, v_pos, p_objet, v_gemmes);
  perform _journal('equipement', v_nom || ' équipé par ' || v_merc || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'emplacement', v_emp, 'position', v_pos));
end;
$$;

