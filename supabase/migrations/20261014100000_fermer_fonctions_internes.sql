-- Check-up du 2026-10-14 : quatre fonctions internes restaient exécutables par un visiteur non connecté (le droit
-- venait de « PUBLIC », que la migration de durcissement 20261005200000 ne retirait pas pour elles). Aucune ne sert
-- à un visiteur : deux sont des déclencheurs de prix, une est le déclencheur de création de profil, une sert à
-- l'inscription depuis l'intérieur de la base. Les joueurs connectés (authenticated) et le service gardent leur droit.
-- Restent ouvertes aux visiteurs : invitation_valide, enregistrer_maintien (voulues) et is_admin (utilisée par des
-- règles de protection ; elle répond simplement « non » à un visiteur).
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('_trg_prix_alchimie', '_trg_prix_equipement', 'handle_new_user', 'verifier_invitation')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
end;
$$;
