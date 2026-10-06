-- Armes des créatures (Bruno, 2026-10-06) : jusqu'à 3 armes par créature, choisies dans le catalogue des
-- objets (rubrique Armes), comme les 3 emplacements d'armes d'un mercenaire. Catalogue commun aux sessions,
-- visible et modifiable par le MJ seul (même règle que les autres tables de créatures).
create table creature_arme (
  creature_id uuid not null references creature (id) on delete cascade,
  position smallint not null check (position between 0 and 2),
  objet_id uuid not null references objet_catalogue (id) on delete cascade,
  primary key (creature_id, position)
);

alter table creature_arme enable row level security;

create policy "creature_arme: lecture admin" on creature_arme for select to authenticated
  using (is_admin());
create policy "creature_arme: ecriture admin" on creature_arme for all to authenticated
  using (is_admin()) with check (is_admin());

grant select, insert, update, delete on creature_arme to authenticated, fortress_fn;
revoke all on creature_arme from anon;
