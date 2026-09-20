-- Suivi du maintien actif : chaque appel de api/keepalive.js note ici l'heure de
-- son dernier passage, par origine (vercel = tache planifiee Vercel, github =
-- tache planifiee GitHub, manuel = tout autre appel). L'admin affiche « dernier
-- maintien actif : il y a X h » et peut ainsi voir d'un coup d'oeil si le
-- mecanisme (qui evite la pause du projet gratuit) tourne toujours.
--
-- La table n'est lisible que par l'administrateur ; l'ecriture passe par la
-- fonction enregistrer_maintien(), appelable sans connexion (le point de
-- maintien n'a que la cle publique) et qui ne peut rien faire d'autre que
-- noter l'heure.

create table maintien (
  source text primary key check (source in ('vercel', 'github', 'manuel')),
  dernier timestamptz not null default now()
);

alter table maintien enable row level security;

create policy "maintien: lecture par admin"
  on maintien for select
  using (is_admin());

create function enregistrer_maintien(p_source text)
returns void
language sql
security definer set search_path = public
as $$
  insert into maintien (source, dernier)
  values (case when p_source in ('vercel', 'github') then p_source else 'manuel' end, now())
  on conflict (source) do update set dernier = excluded.dernier;
$$;
revoke all on function enregistrer_maintien(text) from public;
grant execute on function enregistrer_maintien(text) to anon, authenticated;
