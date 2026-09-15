-- Bucket public pour les icones du catalogue, uploadees depuis
-- l'interface d'administration (Admin.jsx). Lecture publique (ce sont
-- des images de jeu affichees a tous), ecriture reservee aux comptes
-- connectes -- meme logique provisoire que les policies d'ecriture du
-- catalogue (a restreindre a un role admin des qu'il y aura plusieurs
-- comptes).

insert into storage.buckets (id, name, public)
values ('catalogue-icones', 'catalogue-icones', true)
on conflict (id) do nothing;

create policy "catalogue-icones: lecture publique"
  on storage.objects for select
  using (bucket_id = 'catalogue-icones');

create policy "catalogue-icones: upload par utilisateur connecte"
  on storage.objects for insert
  with check (bucket_id = 'catalogue-icones' and auth.role() = 'authenticated');

create policy "catalogue-icones: mise a jour par utilisateur connecte"
  on storage.objects for update
  using (bucket_id = 'catalogue-icones' and auth.role() = 'authenticated');

create policy "catalogue-icones: suppression par utilisateur connecte"
  on storage.objects for delete
  using (bucket_id = 'catalogue-icones' and auth.role() = 'authenticated');
