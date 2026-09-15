-- Policies d'ecriture pour l'interface d'administration (Admin.jsx).
-- Catalogue/recettes : reference partagee, pas encore de rol MJ/admin
-- distinct -> ouvert a tout utilisateur connecte pour l'instant (un seul
-- compte, Bruno). A restreindre a un role admin explicite des qu'il y
-- aura plusieurs comptes.

create policy "objet_catalogue: ecriture par tout utilisateur connecte"
  on objet_catalogue for insert
  with check (auth.role() = 'authenticated');
create policy "objet_catalogue: mise a jour par tout utilisateur connecte"
  on objet_catalogue for update
  using (auth.role() = 'authenticated');
create policy "objet_catalogue: suppression par tout utilisateur connecte"
  on objet_catalogue for delete
  using (auth.role() = 'authenticated');

create policy "recette: ecriture par tout utilisateur connecte"
  on recette for insert
  with check (auth.role() = 'authenticated');
create policy "recette: mise a jour par tout utilisateur connecte"
  on recette for update
  using (auth.role() = 'authenticated');
create policy "recette: suppression par tout utilisateur connecte"
  on recette for delete
  using (auth.role() = 'authenticated');

create policy "ingredient_recette: ecriture par tout utilisateur connecte"
  on ingredient_recette for insert
  with check (auth.role() = 'authenticated');
create policy "ingredient_recette: suppression par tout utilisateur connecte"
  on ingredient_recette for delete
  using (auth.role() = 'authenticated');

-- Compagnie : permettre a un membre (MJ) de renommer sa compagnie.
create policy "compagnie: mise a jour par les membres"
  on compagnie for update
  using (est_membre_compagnie(id));

-- Adhesion : un utilisateur peut creer sa propre adhesion (ex: en creant
-- sa compagnie et en devenant MJ dessus).
create policy "adhesion: creation de sa propre adhesion"
  on adhesion_compagnie for insert
  with check (utilisateur_id = auth.uid());

-- Inventaire / ligne_inventaire : ecriture reservee aux membres de la
-- compagnie proprietaire.
create policy "inventaire: creation par les membres de la compagnie"
  on inventaire for insert
  with check (est_membre_compagnie(compagnie_id));

create policy "ligne_inventaire: ecriture par les membres de la compagnie"
  on ligne_inventaire for insert
  with check (
    exists (
      select 1 from inventaire
      where inventaire.id = ligne_inventaire.inventaire_id
        and est_membre_compagnie(inventaire.compagnie_id)
    )
  );
create policy "ligne_inventaire: mise a jour par les membres de la compagnie"
  on ligne_inventaire for update
  using (
    exists (
      select 1 from inventaire
      where inventaire.id = ligne_inventaire.inventaire_id
        and est_membre_compagnie(inventaire.compagnie_id)
    )
  );
create policy "ligne_inventaire: suppression par les membres de la compagnie"
  on ligne_inventaire for delete
  using (
    exists (
      select 1 from inventaire
      where inventaire.id = ligne_inventaire.inventaire_id
        and est_membre_compagnie(inventaire.compagnie_id)
    )
  );

-- Mercenaire : deja en lecture (migration precedente) ; ajout ecriture.
create policy "mercenaire: creation par les membres de la compagnie"
  on mercenaire for insert
  with check (est_membre_compagnie(compagnie_id));
create policy "mercenaire: mise a jour par les membres de la compagnie"
  on mercenaire for update
  using (est_membre_compagnie(compagnie_id));
create policy "mercenaire: suppression par les membres de la compagnie"
  on mercenaire for delete
  using (est_membre_compagnie(compagnie_id));
