-- Premier socle Forteresse : comptes, compagnie, catalogue, inventaire, recettes.
-- Cf. section 8 de CLAUDE.md. Ne couvre volontairement pas encore
-- Mercenaire/Campagne/Emplacement/Tresorerie : a ajouter dans une migration
-- separee une fois ces regles validees avec Bruno.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Utilisateur : profil applicatif lie a auth.users (Supabase Auth, lien magique)
-- ---------------------------------------------------------------------------
create table profil (
  id uuid primary key references auth.users (id) on delete cascade,
  nom_affiche text not null,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create function handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into profil (id, nom_affiche)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nom_affiche', split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- Compagnie et adhesion
-- ---------------------------------------------------------------------------
create table compagnie (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  actif boolean not null default true,
  cree_par uuid not null references profil (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create type role_compagnie as enum ('mj', 'joueur');

create table adhesion_compagnie (
  id uuid primary key default gen_random_uuid(),
  utilisateur_id uuid not null references profil (id) on delete cascade,
  compagnie_id uuid not null references compagnie (id) on delete cascade,
  role role_compagnie not null default 'joueur',
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  unique (utilisateur_id, compagnie_id)
);

-- ---------------------------------------------------------------------------
-- Catalogue (modeles d'objets, aucune quantite possedee ici)
-- ---------------------------------------------------------------------------
create table objet_catalogue (
  id uuid primary key default gen_random_uuid(),
  code_unique text not null unique,
  nom text not null,
  description text,
  icone text,
  categorie text not null,
  empilable boolean not null default true,
  utilisable boolean not null default false,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Inventaire et lignes de possession
-- ---------------------------------------------------------------------------
create type type_inventaire as enum ('arsenal', 'campagne');

create table inventaire (
  id uuid primary key default gen_random_uuid(),
  compagnie_id uuid not null references compagnie (id) on delete cascade,
  type type_inventaire not null,
  nom text not null,
  campagne_id uuid,
  mercenaire_id uuid,
  created_at timestamptz not null default now()
);

create table ligne_inventaire (
  id uuid primary key default gen_random_uuid(),
  inventaire_id uuid not null references inventaire (id) on delete cascade,
  objet_id uuid not null references objet_catalogue (id),
  quantite integer not null default 0 check (quantite >= 0),
  equipe_par uuid,
  durabilite integer,
  nom_personnalise text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index ligne_inventaire_inventaire_idx on ligne_inventaire (inventaire_id);

-- ---------------------------------------------------------------------------
-- Recettes (une ligne par ingredient requis, cf. section 8 CLAUDE.md)
-- ---------------------------------------------------------------------------
create type atelier_recette as enum ('alchimie', 'forge', 'armurerie');

create table recette (
  id uuid primary key default gen_random_uuid(),
  code_unique text not null unique,
  nom text not null,
  atelier atelier_recette not null,
  resultat_objet_id uuid not null references objet_catalogue (id),
  quantite_produite integer not null default 1 check (quantite_produite > 0),
  actif boolean not null default true
);

create table ingredient_recette (
  id uuid primary key default gen_random_uuid(),
  recette_id uuid not null references recette (id) on delete cascade,
  objet_id uuid not null references objet_catalogue (id),
  quantite_requise integer not null check (quantite_requise > 0),
  unique (recette_id, objet_id)
);

-- ---------------------------------------------------------------------------
-- RLS : catalogue et recettes en lecture pour tout utilisateur connecte ;
-- compagnie/inventaire restreints aux membres de la compagnie concernee.
-- ---------------------------------------------------------------------------
alter table profil enable row level security;
alter table compagnie enable row level security;
alter table adhesion_compagnie enable row level security;
alter table objet_catalogue enable row level security;
alter table inventaire enable row level security;
alter table ligne_inventaire enable row level security;
alter table recette enable row level security;
alter table ingredient_recette enable row level security;

create function est_membre_compagnie(cible_compagnie_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from adhesion_compagnie
    where compagnie_id = cible_compagnie_id
      and utilisateur_id = auth.uid()
      and actif
  );
$$;

create policy "profil: lecture de son propre profil"
  on profil for select
  using (id = auth.uid());

create policy "profil: mise a jour de son propre profil"
  on profil for update
  using (id = auth.uid());

create policy "compagnie: lecture par les membres"
  on compagnie for select
  using (est_membre_compagnie(id));

create policy "compagnie: creation par un utilisateur connecte"
  on compagnie for insert
  with check (cree_par = auth.uid());

create policy "adhesion: lecture par les membres de la compagnie"
  on adhesion_compagnie for select
  using (est_membre_compagnie(compagnie_id));

create policy "objet_catalogue: lecture par tout utilisateur connecte"
  on objet_catalogue for select
  using (auth.role() = 'authenticated');

create policy "recette: lecture par tout utilisateur connecte"
  on recette for select
  using (auth.role() = 'authenticated');

create policy "ingredient_recette: lecture par tout utilisateur connecte"
  on ingredient_recette for select
  using (auth.role() = 'authenticated');

create policy "inventaire: acces reserve aux membres de la compagnie"
  on inventaire for select
  using (est_membre_compagnie(compagnie_id));

create policy "ligne_inventaire: acces reserve aux membres de la compagnie"
  on ligne_inventaire for select
  using (
    exists (
      select 1 from inventaire
      where inventaire.id = ligne_inventaire.inventaire_id
        and est_membre_compagnie(inventaire.compagnie_id)
    )
  );

-- Les mutations (insert/update/delete) sur inventaire/ligne_inventaire
-- passeront par des fonctions serveur (RPC) qui revalident stock et droits,
-- plutot que par des policies d'ecriture directes ici (cf. section 9 CLAUDE.md).
