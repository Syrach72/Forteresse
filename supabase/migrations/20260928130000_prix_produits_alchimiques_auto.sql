-- Coût d'achat des Produits Alchimiques calculé automatiquement (règle de Bruno, 2026-09-28) :
-- 3× la somme des coûts d'achat des composants de la recette (quantité × coût de chacun),
-- ramené à l'unité produite. Un composant qui est lui-même un Produit Alchimique est évalué
-- par la même règle, récursivement (son propre prix n'est jamais lu directement : il est
-- toujours recalculé depuis ses propres composants, jusqu'aux matières premières).
--
-- Le prix n'est plus saisi à la main : cout_achat_or reste la colonne existante (rien ne change
-- ailleurs dans le code, Marché/Admin/achat la lisent comme avant), mais elle est désormais
-- maintenue par un trigger qui la recalcule dès qu'une recette, un ingrédient de recette, ou le
-- prix de n'importe quel objet du catalogue change.

create or replace function _prix_produit_alchimique(p_objet uuid, p_profondeur integer default 0)
returns numeric
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_racine text;
  v_recette_id uuid;
  v_quantite_produite integer;
  v_total numeric := 0;
  v_ing record;
begin
  select _racine_categorie(categorie_id) into v_racine from objet_catalogue where id = p_objet;
  if v_racine is distinct from 'Produits Alchimiques' then
    return (select cout_achat_or from objet_catalogue where id = p_objet);
  end if;
  if p_profondeur > 15 then
    raise exception 'Recette circulaire détectée pour l''objet %.', p_objet;
  end if;
  select id, quantite_produite into v_recette_id, v_quantite_produite
    from recette where resultat_objet_id = p_objet and actif limit 1;
  if v_recette_id is null then
    -- Pas de recette active : repli sur le prix déjà en base (rien à calculer).
    return (select cout_achat_or from objet_catalogue where id = p_objet);
  end if;
  for v_ing in select objet_id, quantite_requise from ingredient_recette where recette_id = v_recette_id
  loop
    -- Un composant sans prix d'achat propre (matière non vendue au marché) compte pour 0 : rien
    -- d'autre à utiliser à sa place.
    v_total := v_total + v_ing.quantite_requise * coalesce(_prix_produit_alchimique(v_ing.objet_id, p_profondeur + 1), 0);
  end loop;
  return ceil(v_total * 3 / greatest(coalesce(v_quantite_produite, 1), 1));
end;
$$;

create or replace function _recalculer_prix_alchimie_tous()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_count integer;
begin
  update objet_catalogue o
    set cout_achat_or = _prix_produit_alchimique(o.id)::integer
    where _racine_categorie(o.categorie_id) = 'Produits Alchimiques';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Déclenché par toute modification pouvant changer un prix (recette, ingrédient, ou coût d'achat
-- d'un objet quelconque, matière première comprise). Le garde-fou sur pg_trigger_depth() évite
-- que la mise à jour de cout_achat_or faite ici ne redéclenche ce même trigger en boucle.
create or replace function _trg_prix_alchimie()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if pg_trigger_depth() <= 1 then
    perform _recalculer_prix_alchimie_tous();
  end if;
  return null;
end;
$$;

drop trigger if exists trg_prix_alchimie_ingredients on ingredient_recette;
create trigger trg_prix_alchimie_ingredients
  after insert or update or delete on ingredient_recette
  for each statement execute function _trg_prix_alchimie();

drop trigger if exists trg_prix_alchimie_recette on recette;
create trigger trg_prix_alchimie_recette
  after insert or update or delete on recette
  for each statement execute function _trg_prix_alchimie();

drop trigger if exists trg_prix_alchimie_objets on objet_catalogue;
create trigger trg_prix_alchimie_objets
  after update of cout_achat_or on objet_catalogue
  for each statement execute function _trg_prix_alchimie();

grant create on schema public to fortress_fn;
alter function _prix_produit_alchimique(uuid, integer) owner to fortress_fn;
alter function _recalculer_prix_alchimie_tous() owner to fortress_fn;
alter function _trg_prix_alchimie() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _prix_produit_alchimique(uuid, integer) from public;
revoke all on function _recalculer_prix_alchimie_tous() from public;
grant execute on function _prix_produit_alchimique(uuid, integer) to authenticated, fortress_fn;
grant execute on function _recalculer_prix_alchimie_tous() to authenticated, fortress_fn;

-- Calcule immédiatement les prix actuels (remplace les valeurs saisies à la main jusqu'ici).
select _recalculer_prix_alchimie_tous();
