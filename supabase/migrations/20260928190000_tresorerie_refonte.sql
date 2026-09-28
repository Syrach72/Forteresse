-- Refonte de la Trésorerie (règle de Bruno, 2026-09-28) : les postes de dépenses
-- fictifs (Lits Dortoir, Médecin, Maître d'Armes, Forgeron, Armurier, Mage,
-- Entraînement, « Autres frais ») ne correspondent à aucun mécanisme réel et sont
-- supprimés. Ne reste dans budget_poste que la recette manuelle du MJ (le reste —
-- entretien mercenaires, entretien collecte, achats de l'instance en cours,
-- dernière quête, dernier tribut du village — est calculé en direct, pas stocké).

delete from budget_poste where code in
  ('dortoir', 'infirmerie', 'medecin', 'maitre', 'entrainement', 'forgeron', 'armurier', 'mage', 'reste', 'entretien');

update budget_poste set libelle = 'Autre recette (MJ)' where code = 'recettes';

-- Entretien de la Collecte (Bûcheron/Mineur/Tanneur, éventuels futurs métiers) :
-- même principe qu'entretien_montant() (mercenaires), mais sur la table employe.
create or replace function entretien_collecte_montant()
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(sum(e.quantite * coalesce(o.emploi_entretien, 0)), 0)::integer
  from employe e join objet_catalogue o on o.id = e.objet_id
  where _racine_categorie(o.categorie_id) = 'Collecte';
$$;

revoke all on function entretien_collecte_montant() from public;
grant execute on function entretien_collecte_montant() to authenticated;

-- Bois/Fer/Cuir valent désormais réellement 1 Po (au lieu d'être seulement une
-- valeur de calcul interne à _valeur_matiere_premiere) : cela permet de les
-- vendre au Marché (moitié de la valeur, comme tout objet, via partie_vendre,
-- déjà existante) sans créer un mécanisme dédié. Le bouton « Acheter » reste
-- volontairement désactivé pour les Matériaux côté frontend (App.jsx) : ces
-- matières ne s'achètent toujours pas, seulement produites par la Collecte.
update objet_catalogue set cout_achat_or = 1 where nom in ('Bois', 'Fer', 'Cuir');

create or replace function _valeur_matiere_premiere(p_objet uuid)
returns numeric
language sql
stable
security definer set search_path = public
as $$
  select coalesce(o.cout_achat_or, 0) from objet_catalogue o where o.id = p_objet;
$$;
