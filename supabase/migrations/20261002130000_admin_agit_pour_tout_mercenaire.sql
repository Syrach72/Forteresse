-- L'administrateur (MJ) agit pour n'importe quel mercenaire recruté, comme s'il était le joueur qui le
-- possède (demande de Bruno, 2026-10-02) : fiche, renvoi, instructeur, élève, soins, quête, équipement.
-- La plupart des fonctions le permettaient déjà (_droit_mercenaire, quete_engager, entrainement_renvoyer…).
-- Restent trois fonctions qui exigeaient d'être le recruteur : entrainement_choisir_instructeur,
-- entrainement_choisir_eleve et infirmerie_soigner. Leur contrôle devient « admin OU recruteur » ; le reste
-- de leur code est inchangé (la définition en base est relue puis réécrite, propriétaire conservé).
do $$
declare
  f record;
  d text;
  ancien constant text := E'if not exists (\n    select 1 from recrutement\n    where mercenaire_id = p_mercenaire and user_id = auth.uid()\n  ) then';
  nouveau constant text := E'if not is_admin() and not exists (\n    select 1 from recrutement\n    where mercenaire_id = p_mercenaire and user_id = auth.uid()\n  ) then';
begin
  for f in
    select p.oid, p.proname, pg_get_functiondef(p.oid) as def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where p.proname in ('entrainement_choisir_instructeur', 'entrainement_choisir_eleve', 'infirmerie_soigner')
  loop
    if position(ancien in f.def) = 0 then
      raise exception 'Contrôle du recruteur introuvable dans %, migration à adapter.', f.proname;
    end if;
    d := replace(f.def, ancien, nouveau);
    execute d;
  end loop;
end;
$$;
