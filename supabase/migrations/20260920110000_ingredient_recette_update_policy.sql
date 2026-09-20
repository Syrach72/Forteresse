-- Modifier la quantite d'un ingredient depuis la fiche d'un objet (admin) :
-- ingredient_recette n'avait que des policies insert/delete, pas update. Sans
-- policy update, Supabase (RLS) ignore la modification sans renvoyer
-- d'erreur : la quantite saisie ne s'enregistrait jamais. Meme regle que
-- recette et objet_catalogue (20260916100000_admin_role_and_player_writes).

create policy "ingredient_recette: mise a jour par admin"
  on ingredient_recette for update
  using (is_admin());
