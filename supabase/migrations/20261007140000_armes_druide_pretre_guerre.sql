-- Armes et classes (Bruno, 2026-10-07) :
--  * Un Prêtre du domaine de la Guerre (classe Prêtre, sous-classe contenant « guerre ») peut équiper les
--    armes de guerre, comme les Paladins et les Guerriers.
--  * Nouvelle coche « Interdite aux Druides » sur la fiche catalogue d'une arme, COCHÉE PAR DÉFAUT : une arme
--    n'est utilisable par un Druide que si le MJ la décoche (armes de guerre comprises, cf. page Règles).
--    Sans objet pour les armes de moine, que seuls les Moines peuvent équiper.
-- Les armes déjà équipées ne sont pas retirées. Le reste de sac_dos_equiper() reprend 20261004110000.

alter table objet_catalogue add column interdit_druide boolean not null default true;

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
  v_sous_classe text;
  v_restriction text;
  v_interdit_druide boolean;
  v_lourde boolean;
  v_bouclier boolean;
  v_emp text;
  v_max integer;
  v_pos integer;
  v_sac uuid;
  v_ligne uuid;
  v_qte integer;
  v_vet_requise integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  if v_merc is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id), _est_bouclier(categorie_id), categorie_id, interdit_druide
    into v_nom, v_racine, v_bouclier, v_categorie, v_interdit_druide
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
  -- Vétérance requise (fiche de l objet) : impossible d équiper tant que celle du mercenaire est inférieure.
  select veterance_requise into v_vet_requise from objet_catalogue where id = p_objet;
  if v_vet_requise is not null and _vet(p_mercenaire) < v_vet_requise then
    raise exception 'Vétérance insuffisante : % (vétérance %) ne peut pas équiper % qui exige la vétérance %.',
      v_merc, _vet(p_mercenaire), v_nom, v_vet_requise;
  end if;
  -- Restriction par classe : armes de guerre = Paladins, Guerriers et Prêtres de la Guerre ; armes de moine =
  -- Moines. Un Druide n'équipe une arme (de guerre ou non) que si elle n'est pas « interdite aux Druides ».
  if v_emp = 'arme' then
    select c.nom, m.sous_classe into v_classe, v_sous_classe from mercenaire m join classe c on c.id = m.classe_id
      where m.id = p_mercenaire;
    v_classe := lower(coalesce(v_classe, ''));
    with recursive chaine as (
      select id, nom, parent_id from categorie where id = v_categorie
      union all
      select c.id, c.nom, c.parent_id from categorie c join chaine ch on c.id = ch.parent_id
    )
    select case
        when bool_or(lower(btrim(nom)) = 'armes de guerre') then 'guerre'
        when bool_or(lower(btrim(nom)) = 'armes de moine') then 'moine' end
      into v_restriction from chaine;
    if v_restriction = 'moine' and v_classe <> 'moine' then
      raise exception '% ne peut pas équiper % : les armes de moine sont réservées aux Moines.', v_merc, v_nom;
    end if;
    if v_classe = 'druide' and v_restriction is distinct from 'moine' and coalesce(v_interdit_druide, true) then
      raise exception '% ne peut pas équiper % : cette arme est interdite aux Druides.', v_merc, v_nom;
    end if;
    if v_restriction = 'guerre'
       and not (v_classe in ('paladin', 'guerrier')
                or (v_classe in ('prêtre', 'pretre') and lower(coalesce(v_sous_classe, '')) like '%guerre%')
                or v_classe = 'druide') then
      raise exception '% ne peut pas équiper % : les armes de guerre sont réservées aux Paladins, aux Guerriers et aux Prêtres de la Guerre.', v_merc, v_nom;
    end if;
  end if;
  -- Restrictions d'armures par classe (Bruno, 2026-09-30). Le matériau se lit dans le nom
  -- de l'objet : « (Tissus) », « (Cuir) », « (Métal) » ; boucliers « en Bois » / « en Acier ».
  --  * Armure lourde : Guerrier, Paladin, Prêtre uniquement.
  --  * Incantateur, Moine : armures en tissu seulement, aucun bouclier.
  --  * Druide : aucune armure en métal ; seuls les boucliers « en bois ».
  if v_emp in ('armure', 'bouclier') then
    select c.nom into v_classe from mercenaire m join classe c on c.id = m.classe_id
      where m.id = p_mercenaire;
    v_classe := lower(coalesce(v_classe, ''));
    with recursive chaine as (
      select id, nom, parent_id from categorie where id = v_categorie
      union all
      select c.id, c.nom, c.parent_id from categorie c join chaine ch on c.id = ch.parent_id
    )
    select coalesce(bool_or(lower(btrim(nom)) = 'armure lourde'), false) into v_lourde from chaine;
    if v_lourde and v_classe not in ('guerrier', 'paladin', 'prêtre') then
      raise exception '% ne peut pas porter % : les armures lourdes sont réservées aux Guerriers, Paladins et Prêtres.', v_merc, v_nom;
    end if;
    if v_classe in ('incantateur', 'moine') then
      if v_emp = 'bouclier' then
        raise exception '% ne peut pas porter % : les Incantateurs et les Moines ne portent pas de bouclier.', v_merc, v_nom;
      elsif lower(v_nom) not like '%tissu%' then
        raise exception '% ne peut pas porter % : les Incantateurs et les Moines ne portent que des armures en tissu.', v_merc, v_nom;
      end if;
    end if;
    if v_classe = 'druide' then
      if v_emp = 'armure' and lower(v_nom) like '%métal%' then
        raise exception '% ne peut pas porter % : les Druides ne portent pas d''armure en métal.', v_merc, v_nom;
      elsif v_emp = 'bouclier' and lower(v_nom) not like '%en bois%' then
        raise exception '% ne peut pas porter % : les Druides ne portent que des boucliers en bois.', v_merc, v_nom;
      end if;
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
