-- Scénario d'une quête (Bruno, 2026-10-01) : texte libre visible et modifiable par l'administrateur
-- (MJ) uniquement. Table séparée de `quete` (lisible par tous les joueurs) : une colonne ajoutée à
-- `quete` aurait fuité vers les joueurs via select *. Aucune policy de lecture pour les joueurs.

create table if not exists quete_scenario (
  quete_id uuid primary key references quete (id) on delete cascade,
  texte text not null default ''
);

alter table quete_scenario enable row level security;
create policy "quete_scenario: lecture et ecriture admin"
  on quete_scenario for all to authenticated using (is_admin()) with check (is_admin());
