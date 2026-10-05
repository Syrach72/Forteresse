-- Durcissement (relecture du 2026-10-05) : par défaut Supabase donne au rôle « anon » (visiteur non connecté) tous les
-- droits sur les tables et l'exécution de toutes les fonctions du schéma public. La protection par ligne (RLS) et les
-- contrôles de connexion des fonctions les bloquaient déjà, mais autant ne rien exposer. Un visiteur non connecté n'a
-- besoin que de deux choses :
--   * invitation_valide(code) : message clair sur la page « Créer un compte » ;
--   * enregistrer_maintien(source) : le ping quotidien (api/keepalive.js) qui garde la base éveillée.
-- Les joueurs connectés (rôle authenticated) ne sont pas concernés. Les nouvelles tables et fonctions ne donneront
-- plus rien à anon automatiquement.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;
grant execute on function invitation_valide(text) to anon;
grant execute on function enregistrer_maintien(text) to anon;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon;
