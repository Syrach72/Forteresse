-- Règle de Bruno (2026-10-06) : aucun mercenaire ne peut posséder plus de gemmes serties que son niveau Mental
-- (Mental effectif, bonus de race compris ; une arme avec 2 gemmes compte pour 2). « Posséder » = les objets sertis
-- équipés par le mercenaire et ceux de son sac à dos. Le contrôle se fait à l'envoi d'un objet serti de l'arsenal vers
-- le sac à dos (équiper ou déséquiper ne change pas le total). Reste de sac_dos_envoyer : 20260929150000_caleche_sac_dos.sql.

create function _gemmes_portees(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce((select sum(coalesce(cardinality(e.gemmes), 0)) from mercenaire_equipement e
                    where e.mercenaire_id = p_mercenaire), 0)::integer
       + coalesce((select sum(coalesce(cardinality(l.gemmes), 0) * l.quantite) from ligne_inventaire l
                    join inventaire i on i.id = l.inventaire_id
                    where i.type = 'campagne' and i.mercenaire_id = p_mercenaire and l.quantite > 0), 0)::integer;
$$;
revoke all on function _gemmes_portees(uuid) from public;
grant execute on function _gemmes_portees(uuid) to authenticated, fortress_fn;

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
  v_merc text;
  v_mental integer;
  v_portees integer;
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
  -- Gemmes serties : un mercenaire n'en porte pas plus que son niveau de Mental (une arme à 2 gemmes en compte 2).
  if v_gemmes is not null then
    v_mental := _mental(p_mercenaire);
    v_portees := _gemmes_portees(p_mercenaire);
    if v_portees + cardinality(v_gemmes) > v_mental then
      select nom into v_merc from mercenaire where id = p_mercenaire;
      raise exception '% ne peut pas porter plus de gemmes serties que son niveau de Mental : Mental %, % gemme(s) déjà portée(s), % de plus avec cette arme.',
        v_merc, v_mental, v_portees, cardinality(v_gemmes);
    end if;
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

grant create on schema public to fortress_fn;
alter function _gemmes_portees(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
