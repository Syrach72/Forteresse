-- Bucket public pour les portraits de mercenaires, uploades depuis
-- l'interface d'administration (Admin.jsx). mercenaire.portrait existe
-- deja (colonne text, migration seed_alchimie_magie_mercenaire) mais
-- rien ne l'alimentait encore. Meme logique que catalogue-icones :
-- lecture publique, ecriture reservee aux comptes connectes (a
-- restreindre a un role admin des qu'il y aura plusieurs comptes).

insert into storage.buckets (id, name, public)
values ('mercenaire-portraits', 'mercenaire-portraits', true)
on conflict (id) do nothing;

create policy "mercenaire-portraits: lecture publique"
  on storage.objects for select
  using (bucket_id = 'mercenaire-portraits');

create policy "mercenaire-portraits: upload par utilisateur connecte"
  on storage.objects for insert
  with check (bucket_id = 'mercenaire-portraits' and auth.role() = 'authenticated');

create policy "mercenaire-portraits: mise a jour par utilisateur connecte"
  on storage.objects for update
  using (bucket_id = 'mercenaire-portraits' and auth.role() = 'authenticated');

create policy "mercenaire-portraits: suppression par utilisateur connecte"
  on storage.objects for delete
  using (bucket_id = 'mercenaire-portraits' and auth.role() = 'authenticated');
