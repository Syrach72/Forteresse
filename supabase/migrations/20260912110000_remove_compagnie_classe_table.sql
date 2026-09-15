-- Decision de Bruno du 12/09 : supprimer la notion de compagnie. Chaque
-- joueur choisit librement un mercenaire dans une liste commune ; il n'y
-- a plus de groupe/compagnie proprietaire. L'arsenal et la liste des
-- mercenaires deviennent globaux (partages par tous), au lieu d'etre
-- rattaches a une compagnie_id.
--
-- Verifie avant migration : 0 ligne dans compagnie/adhesion_compagnie/
-- mercenaire/inventaire/ligne_inventaire sur la base liee -> suppression
-- sans perte de donnees reelles. objet_catalogue (100 lignes) n'est pas
-- touche.
--
-- Deuxieme changement de cette migration : la classe d'un mercenaire
-- (Guerrier, Roublard, ...) etait du texte libre ; comme pour categorie
-- (migration precedente), Bruno veut pouvoir ajouter/renommer/supprimer
-- une classe depuis l'administration -> nouvelle table classe, reference
-- par mercenaire.classe_id.

-- ---------------------------------------------------------------------------
-- Retrait des policies dependant de est_membre_compagnie, avant de pouvoir
-- supprimer la fonction et les tables compagnie/adhesion_compagnie.
-- ---------------------------------------------------------------------------
drop policy "mercenaire: acces reserve aux membres de la compagnie" on mercenaire;
drop policy "mercenaire: creation par les membres de la compagnie" on mercenaire;
drop policy "mercenaire: mise a jour par les membres de la compagnie" on mercenaire;
drop policy "mercenaire: suppression par les membres de la compagnie" on mercenaire;

drop policy "inventaire: acces reserve aux membres de la compagnie" on inventaire;
drop policy "inventaire: creation par les membres de la compagnie" on inventaire;

drop policy "ligne_inventaire: acces reserve aux membres de la compagnie" on ligne_inventaire;
drop policy "ligne_inventaire: ecriture par les membres de la compagnie" on ligne_inventaire;
drop policy "ligne_inventaire: mise a jour par les membres de la compagnie" on ligne_inventaire;
drop policy "ligne_inventaire: suppression par les membres de la compagnie" on ligne_inventaire;

-- ---------------------------------------------------------------------------
-- Retrait de compagnie / adhesion_compagnie et des colonnes compagnie_id.
-- Les deux tables sont supprimees avant la fonction : leurs propres
-- policies (qui en dependent aussi) partent avec elles.
-- ---------------------------------------------------------------------------
alter table mercenaire drop column compagnie_id;
alter table inventaire drop column compagnie_id;

drop table adhesion_compagnie;
drop table compagnie;
drop function est_membre_compagnie(uuid);
drop type role_compagnie;

-- ---------------------------------------------------------------------------
-- Table classe (remplace le texte libre mercenaire.classe).
-- ---------------------------------------------------------------------------
create table classe (
  id uuid primary key default gen_random_uuid(),
  nom text not null unique,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

insert into classe (nom) values
  ('Légende'), ('Guerrier'), ('Roublard'), ('Rôdeur'),
  ('Prêtre'), ('Druide'), ('Incantateur'), ('Paladin');

alter table mercenaire add column classe_id uuid references classe (id);

update mercenaire m
set classe_id = c.id
from classe c
where c.nom = m.classe;

alter table mercenaire drop column classe;

-- ---------------------------------------------------------------------------
-- Arsenal commun global : une seule ligne desormais (plus de compagnie_id).
-- ---------------------------------------------------------------------------
insert into inventaire (type, nom)
select 'arsenal', 'Arsenal'
where not exists (select 1 from inventaire where type = 'arsenal');

-- ---------------------------------------------------------------------------
-- Nouvelles policies, simplifiees : reference partagee, un seul compte
-- pour l'instant -> ouvert a tout utilisateur connecte, meme principe que
-- objet_catalogue/categorie (a restreindre a un role admin explicite des
-- qu'il y aura plusieurs comptes).
-- ---------------------------------------------------------------------------
alter table classe enable row level security;
create policy "classe: lecture par tout utilisateur connecte"
  on classe for select
  using (auth.role() = 'authenticated');
create policy "classe: creation par tout utilisateur connecte"
  on classe for insert
  with check (auth.role() = 'authenticated');
create policy "classe: mise a jour par tout utilisateur connecte"
  on classe for update
  using (auth.role() = 'authenticated');
create policy "classe: suppression par tout utilisateur connecte"
  on classe for delete
  using (auth.role() = 'authenticated');

create policy "mercenaire: lecture par tout utilisateur connecte"
  on mercenaire for select
  using (auth.role() = 'authenticated');
create policy "mercenaire: creation par tout utilisateur connecte"
  on mercenaire for insert
  with check (auth.role() = 'authenticated');
create policy "mercenaire: mise a jour par tout utilisateur connecte"
  on mercenaire for update
  using (auth.role() = 'authenticated');
create policy "mercenaire: suppression par tout utilisateur connecte"
  on mercenaire for delete
  using (auth.role() = 'authenticated');

create policy "inventaire: lecture par tout utilisateur connecte"
  on inventaire for select
  using (auth.role() = 'authenticated');
create policy "inventaire: creation par tout utilisateur connecte"
  on inventaire for insert
  with check (auth.role() = 'authenticated');

create policy "ligne_inventaire: lecture par tout utilisateur connecte"
  on ligne_inventaire for select
  using (auth.role() = 'authenticated');
create policy "ligne_inventaire: ecriture par tout utilisateur connecte"
  on ligne_inventaire for insert
  with check (auth.role() = 'authenticated');
create policy "ligne_inventaire: mise a jour par tout utilisateur connecte"
  on ligne_inventaire for update
  using (auth.role() = 'authenticated');
create policy "ligne_inventaire: suppression par tout utilisateur connecte"
  on ligne_inventaire for delete
  using (auth.role() = 'authenticated');
