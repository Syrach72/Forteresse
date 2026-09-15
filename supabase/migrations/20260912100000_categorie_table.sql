-- Jusqu'ici la liste des categories etait figee en dur dans Admin.jsx
-- (CATEGORIES) et objet_catalogue.categorie etait du texte libre. Bruno
-- veut pouvoir ajouter/renommer/supprimer une categorie depuis
-- l'administration : il faut une vraie table, reference par
-- objet_catalogue.categorie_id (cle etrangere stable), plutot qu'un nom
-- en texte libre qui pourrait diverger. Cf. section 8 CLAUDE.md
-- (normaliser les categories explicitement, un nom ne constitue pas une
-- identite).

create table categorie (
  id uuid primary key default gen_random_uuid(),
  nom text not null unique,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

insert into categorie (nom) values
  ('Arme'), ('Armure'), ('Produits Alchimiques'), ('Ingrédient'),
  ('Matériau'), ('Objet magique'), ('Objet divers'), ('Munition');

alter table objet_catalogue add column categorie_id uuid references categorie (id);

update objet_catalogue oc
set categorie_id = c.id
from categorie c
where c.nom = oc.categorie;

-- Filet de securite : un objet dont le texte categorie ne correspondrait
-- a aucune des 8 categories connues (faute de frappe, valeur oubliee)
-- doit rester visible plutot que d'etre silencieusement perdu au moment
-- de forcer categorie_id en not null ci-dessous.
insert into categorie (nom, actif)
select distinct oc.categorie, false
from objet_catalogue oc
where oc.categorie_id is null
  and oc.categorie is not null
on conflict (nom) do nothing;

update objet_catalogue oc
set categorie_id = c.id
from categorie c
where oc.categorie_id is null and c.nom = oc.categorie;

alter table objet_catalogue alter column categorie_id set not null;
alter table objet_catalogue drop column categorie;

alter table categorie enable row level security;

create policy "categorie: lecture par tout utilisateur connecte"
  on categorie for select
  using (auth.role() = 'authenticated');
-- Meme principe que les policies d'ecriture du catalogue/recettes
-- (migration admin_write_policies) : reference partagee, un seul compte
-- pour l'instant -> ouvert a tout utilisateur connecte, a restreindre a
-- un role admin explicite des qu'il y aura plusieurs comptes.
create policy "categorie: creation par tout utilisateur connecte"
  on categorie for insert
  with check (auth.role() = 'authenticated');
create policy "categorie: mise a jour par tout utilisateur connecte"
  on categorie for update
  using (auth.role() = 'authenticated');
create policy "categorie: suppression par tout utilisateur connecte"
  on categorie for delete
  using (auth.role() = 'authenticated');
