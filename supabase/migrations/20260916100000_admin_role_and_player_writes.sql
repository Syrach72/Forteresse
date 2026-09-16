-- Bruno ouvre desormais une vraie creation de compte pour les joueurs
-- (Supabase Auth, ecran de connexion/inscription reel). Jusqu'ici toutes
-- les policies d'ecriture admin (catalogue, recettes, categories, classes,
-- mercenaires, inventaire/arsenal, buckets d'images) etaient ouvertes a
-- "tout utilisateur connecte" (auth.role() = 'authenticated'), en
-- commentaire explicite "a restreindre a un role admin explicite des qu'il
-- y aura plusieurs comptes". C'est maintenant le cas : sans ce correctif,
-- n'importe quel joueur nouvellement inscrit obtiendrait via l'API les
-- memes droits d'ecriture que Bruno sur ces tables.
--
-- Table d'allow-list minimale (un seul compte admin pour l'instant, Bruno)
-- plutot qu'une colonne de role sur auth.users (non modifiable depuis le
-- client). is_admin() est security definer pour pouvoir lire admin_users
-- meme si l'appelant n'a pas de droit de lecture dessus (meme principe
-- que est_membre_compagnie precedemment dans ce projet).

create table admin_users (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table admin_users enable row level security;
-- Aucune policy select/insert/update/delete pour les roles anon/authenticated :
-- cette table ne se lit que via is_admin() (security definer), jamais
-- directement depuis le client.

insert into admin_users (id) values ('da7170e6-6adb-4975-89a1-e8002e09f65b');

create function is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (select 1 from admin_users where id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- objet_catalogue / recette / ingredient_recette : ecriture -> admin uniquement.
-- (lecture deja publique depuis public_read_catalogue, inchangee)
-- ---------------------------------------------------------------------------
drop policy "objet_catalogue: ecriture par tout utilisateur connecte" on objet_catalogue;
drop policy "objet_catalogue: mise a jour par tout utilisateur connecte" on objet_catalogue;
drop policy "objet_catalogue: suppression par tout utilisateur connecte" on objet_catalogue;
create policy "objet_catalogue: ecriture par admin"
  on objet_catalogue for insert
  with check (is_admin());
create policy "objet_catalogue: mise a jour par admin"
  on objet_catalogue for update
  using (is_admin());
create policy "objet_catalogue: suppression par admin"
  on objet_catalogue for delete
  using (is_admin());

drop policy "recette: ecriture par tout utilisateur connecte" on recette;
drop policy "recette: mise a jour par tout utilisateur connecte" on recette;
drop policy "recette: suppression par tout utilisateur connecte" on recette;
create policy "recette: ecriture par admin"
  on recette for insert
  with check (is_admin());
create policy "recette: mise a jour par admin"
  on recette for update
  using (is_admin());
create policy "recette: suppression par admin"
  on recette for delete
  using (is_admin());

drop policy "ingredient_recette: ecriture par tout utilisateur connecte" on ingredient_recette;
drop policy "ingredient_recette: suppression par tout utilisateur connecte" on ingredient_recette;
create policy "ingredient_recette: ecriture par admin"
  on ingredient_recette for insert
  with check (is_admin());
create policy "ingredient_recette: suppression par admin"
  on ingredient_recette for delete
  using (is_admin());

-- ---------------------------------------------------------------------------
-- categorie : ecriture -> admin uniquement (lecture deja publique).
-- ---------------------------------------------------------------------------
drop policy "categorie: creation par tout utilisateur connecte" on categorie;
drop policy "categorie: mise a jour par tout utilisateur connecte" on categorie;
drop policy "categorie: suppression par tout utilisateur connecte" on categorie;
create policy "categorie: creation par admin"
  on categorie for insert
  with check (is_admin());
create policy "categorie: mise a jour par admin"
  on categorie for update
  using (is_admin());
create policy "categorie: suppression par admin"
  on categorie for delete
  using (is_admin());

-- ---------------------------------------------------------------------------
-- classe : ecriture -> admin uniquement. Lecture laissee a "authenticated"
-- (donnee de reference non sensible, comme documente depuis l'origine).
-- ---------------------------------------------------------------------------
drop policy "classe: creation par tout utilisateur connecte" on classe;
drop policy "classe: mise a jour par tout utilisateur connecte" on classe;
drop policy "classe: suppression par tout utilisateur connecte" on classe;
create policy "classe: creation par admin"
  on classe for insert
  with check (is_admin());
create policy "classe: mise a jour par admin"
  on classe for update
  using (is_admin());
create policy "classe: suppression par admin"
  on classe for delete
  using (is_admin());

-- ---------------------------------------------------------------------------
-- mercenaire : ecriture -> admin uniquement. Lecture laissee a "authenticated".
-- ---------------------------------------------------------------------------
drop policy "mercenaire: creation par tout utilisateur connecte" on mercenaire;
drop policy "mercenaire: mise a jour par tout utilisateur connecte" on mercenaire;
drop policy "mercenaire: suppression par tout utilisateur connecte" on mercenaire;
create policy "mercenaire: creation par admin"
  on mercenaire for insert
  with check (is_admin());
create policy "mercenaire: mise a jour par admin"
  on mercenaire for update
  using (is_admin());
create policy "mercenaire: suppression par admin"
  on mercenaire for delete
  using (is_admin());

-- ---------------------------------------------------------------------------
-- inventaire / ligne_inventaire (arsenal commun) : ecriture -> admin
-- uniquement pour l'instant (pas encore de flux joueur pour equiper/rendre
-- du materiel depuis le jeu reel). Lecture laissee a "authenticated".
-- ---------------------------------------------------------------------------
drop policy "inventaire: creation par tout utilisateur connecte" on inventaire;
create policy "inventaire: creation par admin"
  on inventaire for insert
  with check (is_admin());

drop policy "ligne_inventaire: ecriture par tout utilisateur connecte" on ligne_inventaire;
drop policy "ligne_inventaire: mise a jour par tout utilisateur connecte" on ligne_inventaire;
drop policy "ligne_inventaire: suppression par tout utilisateur connecte" on ligne_inventaire;
create policy "ligne_inventaire: ecriture par admin"
  on ligne_inventaire for insert
  with check (is_admin());
create policy "ligne_inventaire: mise a jour par admin"
  on ligne_inventaire for update
  using (is_admin());
create policy "ligne_inventaire: suppression par admin"
  on ligne_inventaire for delete
  using (is_admin());

-- ---------------------------------------------------------------------------
-- Buckets images (icones catalogue, portraits mercenaires) : ecriture ->
-- admin uniquement. Lecture publique inchangee.
-- ---------------------------------------------------------------------------
drop policy "catalogue-icones: upload par utilisateur connecte" on storage.objects;
drop policy "catalogue-icones: mise a jour par utilisateur connecte" on storage.objects;
drop policy "catalogue-icones: suppression par utilisateur connecte" on storage.objects;
create policy "catalogue-icones: upload par admin"
  on storage.objects for insert
  with check (bucket_id = 'catalogue-icones' and is_admin());
create policy "catalogue-icones: mise a jour par admin"
  on storage.objects for update
  using (bucket_id = 'catalogue-icones' and is_admin());
create policy "catalogue-icones: suppression par admin"
  on storage.objects for delete
  using (bucket_id = 'catalogue-icones' and is_admin());

drop policy "mercenaire-portraits: upload par utilisateur connecte" on storage.objects;
drop policy "mercenaire-portraits: mise a jour par utilisateur connecte" on storage.objects;
drop policy "mercenaire-portraits: suppression par utilisateur connecte" on storage.objects;
create policy "mercenaire-portraits: upload par admin"
  on storage.objects for insert
  with check (bucket_id = 'mercenaire-portraits' and is_admin());
create policy "mercenaire-portraits: mise a jour par admin"
  on storage.objects for update
  using (bucket_id = 'mercenaire-portraits' and is_admin());
create policy "mercenaire-portraits: suppression par admin"
  on storage.objects for delete
  using (bucket_id = 'mercenaire-portraits' and is_admin());
