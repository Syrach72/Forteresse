-- Inscription sur invitation. Jusqu'ici n'importe qui pouvant ouvrir le site
-- pouvait creer un compte (inscriptions ouvertes, sans confirmation par e-mail).
-- Desormais un compte ne peut etre cree qu'avec un code d'invitation genere par
-- l'administrateur (onglet Invitations de l'admin), utilisable UNE seule fois.
--
-- Pas d'e-mail necessaire : le code est transmis a la main au joueur, qui le
-- saisit sur la page "Creer un compte". Le controle reel est le declencheur sur
-- auth.users (impossible a contourner depuis le navigateur) ; la fonction
-- invitation_valide() ne sert qu'a afficher un message clair avant l'envoi.
--
-- Les comptes existants ne sont pas touches (le declencheur ne joue qu'a la
-- creation). Un compte cree a la main dans le tableau de bord Supabase
-- (Authentication > Users) est aussi refuse tant que le declencheur est actif :
-- pour un depannage, le desactiver un instant :
--   alter table auth.users disable trigger verifier_invitation;
--   ... creer le compte ... puis :
--   alter table auth.users enable trigger verifier_invitation;

create table invitation (
  code text primary key check (code ~ '^[A-Z0-9]{8}$'),
  note text,                                   -- pour qui (facultatif)
  cree_le timestamptz not null default now(),
  utilise_par uuid references auth.users (id) on delete set null,
  utilise_le timestamptz
);

alter table invitation enable row level security;

-- Seul l'administrateur voit et gere les invitations. Les joueurs n'ont aucun
-- acces direct a la table (ni pour lister les codes, ni pour en creer).
create policy "invitation: gestion par admin"
  on invitation for all
  using (is_admin())
  with check (is_admin());

-- Le code saisi peut contenir des tirets ou des minuscules : on le normalise.
create function normaliser_invitation(p_code text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

-- Verification avant l'inscription (message clair cote interface).
create function invitation_valide(p_code text)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from invitation
    where code = normaliser_invitation(p_code) and utilise_par is null
  );
$$;
revoke all on function invitation_valide(text) from public;
grant execute on function invitation_valide(text) to anon, authenticated;

-- Controle reel : apres la creation du compte, le code recu dans les
-- metadonnees (raw_user_meta_data.invitation) doit exister et etre libre ; il
-- est alors consomme atomiquement. Sinon l'exception annule la creation.
create function verifier_invitation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_code text := normaliser_invitation(new.raw_user_meta_data ->> 'invitation');
  v_lignes integer;
begin
  update invitation
     set utilise_par = new.id, utilise_le = now()
   where code = v_code and utilise_par is null;
  get diagnostics v_lignes = row_count;
  if v_lignes = 0 then
    raise exception 'Invitation invalide ou deja utilisee';
  end if;
  return new;
end;
$$;

create trigger verifier_invitation
  after insert on auth.users
  for each row execute function verifier_invitation();
