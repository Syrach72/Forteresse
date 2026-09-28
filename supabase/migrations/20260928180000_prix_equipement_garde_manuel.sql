-- Garde-fou manquant dans la migration 20260928150000 : contrairement aux
-- Produits Alchimiques, aucun trigger ne surveillait cout_achat_or lui-même
-- sur objet_catalogue pour les Armes/Armures. En pratique le champ est
-- maintenant désactivé côté admin pour ces objets (Admin.jsx), mais on
-- ajoute quand même le trigger, par cohérence avec l'alchimie et pour
-- qu'une modification faite par un autre chemin (import, futur outil...) se
-- fasse automatiquement recorriger plutôt que de rester une valeur figée.

drop trigger if exists trg_prix_equipement_objets on objet_catalogue;
create trigger trg_prix_equipement_objets
  after update of cout_achat_or on objet_catalogue
  for each statement execute function _trg_prix_equipement();
