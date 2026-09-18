-- Recrutement des mercenaires (page Personnages > fiche > « Recruter »).
--
-- Un mercenaire créé dans l'administration ne peut être recruté que par UN
-- seul joueur (clé primaire sur mercenaire_id). Une fois recruté, il est grisé
-- et inaccessible pour les autres joueurs ; seuls son recruteur et
-- l'administrateur ont accès à sa fiche.
--
-- La table ne se lit directement que pour ses propres recrutements (ou tous
-- pour l'admin) : les autres joueurs savent seulement QUELS mercenaires sont
-- déjà pris, via la fonction mercenaires_recrutes() (identifiants uniquement,
-- sans savoir qui les a recrutés).
--
-- nom_joueur : nom écrit par le joueur sur la fiche avant de recruter. Il reste
-- attaché au recrutement (affiché sur le mercenaire au Dortoir, etc.) et
-- disparaît avec lui quand le mercenaire est renvoyé. Tout le reste du
-- mercenaire (vétérance, fiche) vit dans la table mercenaire et n'est jamais
-- touché par un renvoi.

create table recrutement (
  mercenaire_id uuid primary key references mercenaire (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  nom_joueur text not null check (length(btrim(nom_joueur)) > 0),
  created_at timestamptz not null default now()
);

alter table recrutement enable row level security;

create policy "recrutement: lecture de ses recrutements (tous pour l'admin)"
  on recrutement for select
  using (auth.uid() = user_id or is_admin());

create policy "recrutement: un joueur recrute pour lui-meme"
  on recrutement for insert
  with check (auth.uid() = user_id);

create policy "recrutement: liberation par le recruteur ou l'admin"
  on recrutement for delete
  using (auth.uid() = user_id or is_admin());

-- Identifiants des mercenaires déjà recrutés (par n'importe quel joueur).
create function mercenaires_recrutes()
returns setof uuid
language sql
stable
security definer set search_path = public
as $$
  select mercenaire_id from recrutement;
$$;

revoke all on function mercenaires_recrutes() from public;
grant execute on function mercenaires_recrutes() to authenticated;
