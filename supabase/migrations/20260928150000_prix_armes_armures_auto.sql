-- Coût d'achat des Armes et Armures calculé automatiquement (règle de Bruno,
-- 2026-09-28) : 3x la somme des matières premières de la recette pour une
-- arme, 6x pour une armure (une armure demande plus de travail d'adaptation
-- qu'une arme pour une même quantité de matière).
--
-- Bois, Fer et Cuir valent 1 Po/unité dans ce calcul UNIQUEMENT : cette
-- valeur n'est pas écrite dans leur propre cout_achat_or (qui reste NULL,
-- volontairement — ces matières ne s'achètent pas au Marché, seulement
-- produites par les employés de la Collecte). Un composant qui aurait son
-- propre cout_achat_or (aucun cas actuellement : toutes les recettes
-- d'armes/armures n'utilisent que Bois/Fer/Cuir) est pris en compte via ce
-- prix, en repli.
--
-- Comme pour les Produits Alchimiques (migration 20260928130000), le prix
-- n'est plus saisi à la main pour les objets qui ont une recette active :
-- cout_achat_or reste la colonne existante, mais un trigger la recalcule dès
-- qu'une recette ou un de ses ingrédients change. Les objets sans recette
-- (armes improvisées type Coup de Poing, Crochet...) gardent leur prix saisi
-- à la main.

create or replace function _valeur_matiere_premiere(p_objet uuid)
returns numeric
language sql
stable
security definer set search_path = public
as $$
  select case
    when o.nom in ('Bois', 'Fer', 'Cuir') then 1
    else coalesce(o.cout_achat_or, 0)
  end
  from objet_catalogue o where o.id = p_objet;
$$;

create or replace function _prix_equipement(p_objet uuid)
returns numeric
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_racine text;
  v_multiplicateur integer;
  v_recette_id uuid;
  v_total numeric;
begin
  select _racine_categorie(categorie_id) into v_racine from objet_catalogue where id = p_objet;
  if v_racine = 'Armes' then
    v_multiplicateur := 3;
  elsif v_racine = 'Armures' then
    v_multiplicateur := 6;
  else
    return (select cout_achat_or from objet_catalogue where id = p_objet);
  end if;
  select id into v_recette_id from recette where resultat_objet_id = p_objet and actif limit 1;
  if v_recette_id is null then
    -- Pas de recette active (arme improvisée...) : repli sur le prix déjà en base.
    return (select cout_achat_or from objet_catalogue where id = p_objet);
  end if;
  select coalesce(sum(quantite_requise * _valeur_matiere_premiere(objet_id)), 0) into v_total
    from ingredient_recette where recette_id = v_recette_id;
  return ceil(v_total * v_multiplicateur);
end;
$$;

create or replace function _recalculer_prix_equipement_tous()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_count integer;
begin
  update objet_catalogue o
    set cout_achat_or = _prix_equipement(o.id)::integer
    where _racine_categorie(o.categorie_id) in ('Armes', 'Armures')
      and exists (select 1 from recette r where r.resultat_objet_id = o.id and r.actif);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Garde-fou sur pg_trigger_depth() : évite que la mise à jour de cout_achat_or
-- faite ici ne redéclenche ce même trigger en boucle.
create or replace function _trg_prix_equipement()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if pg_trigger_depth() <= 1 then
    perform _recalculer_prix_equipement_tous();
  end if;
  return null;
end;
$$;

drop trigger if exists trg_prix_equipement_ingredients on ingredient_recette;
create trigger trg_prix_equipement_ingredients
  after insert or update or delete on ingredient_recette
  for each statement execute function _trg_prix_equipement();

drop trigger if exists trg_prix_equipement_recette on recette;
create trigger trg_prix_equipement_recette
  after insert or update or delete on recette
  for each statement execute function _trg_prix_equipement();

grant create on schema public to fortress_fn;
alter function _valeur_matiere_premiere(uuid) owner to fortress_fn;
alter function _prix_equipement(uuid) owner to fortress_fn;
alter function _recalculer_prix_equipement_tous() owner to fortress_fn;
alter function _trg_prix_equipement() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _valeur_matiere_premiere(uuid) from public;
revoke all on function _prix_equipement(uuid) from public;
revoke all on function _recalculer_prix_equipement_tous() from public;
grant execute on function _valeur_matiere_premiere(uuid) to authenticated, fortress_fn;
grant execute on function _prix_equipement(uuid) to authenticated, fortress_fn;
grant execute on function _recalculer_prix_equipement_tous() to authenticated, fortress_fn;

-- Calcule immédiatement les prix actuels (remplace les valeurs saisies à la main).
select _recalculer_prix_equipement_tous();
