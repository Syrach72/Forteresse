-- Quetes gerees en base (regle de Bruno, 2026-09-22) :
--  * fiche editable en admin (titre, description, veterance moyenne requise,
--    icone de type, jusqu'a 5 recompenses en objets + une recompense en or) ;
--  * une seule quete "en cours" a la fois pour toute la compagnie : la choisir
--    grise les 3 autres (plus accessibles) ; le joueur peut annuler son choix
--    a tout moment tant qu'elle n'est pas resolue ;
--  * "une quete = toujours 1 instance" : au prochain +1 Instance (administrateur),
--    l'or rejoint la tresorerie, les objets rejoignent l'arsenal, la quete est
--    marquee terminee (elle reste visible/modifiable en admin mais disparait de
--    la page Quetes des joueurs) et les 3 autres redeviennent disponibles.
--
-- Reutilise les outils deja en place dans 20260921130000_economie_partagee.sql :
-- _verrou_partie() (verrou commun a toutes les operations partagees, pas
-- seulement l'or), _arsenal_ajouter()/_arsenal_retirer(), _journal(),
-- partie_etat.or_compagnie. Les icones de quete reutilisent le bucket Storage
-- "catalogue-icones" deja admin-only : pas de nouveau bucket necessaire.

create table quete (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  description text not null default '',
  veterance_requise integer not null default 0 check (veterance_requise >= 0),
  icone text,
  recompense_or integer not null default 0 check (recompense_or >= 0),
  en_cours boolean not null default false,
  terminee_le timestamptz,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);
-- Au plus une quete en_cours a la fois (index unique partiel : deux lignes
-- avec en_cours = true entreraient en collision, une seule avec en_cours =
-- false n'est jamais indexee).
create unique index quete_une_seule_en_cours on quete (en_cours) where en_cours;

create table quete_recompense (
  id uuid primary key default gen_random_uuid(),
  quete_id uuid not null references quete (id) on delete cascade,
  position smallint not null check (position between 1 and 5),
  objet_id uuid not null references objet_catalogue (id),
  quantite integer not null default 1 check (quantite >= 1),
  unique (quete_id, position)
);

alter table quete enable row level security;
alter table quete_recompense enable row level security;
create policy "quete: lecture par les joueurs connectes"
  on quete for select to authenticated using (true);
create policy "quete: ecriture admin"
  on quete for all to authenticated using (is_admin()) with check (is_admin());
create policy "quete_recompense: lecture par les joueurs connectes"
  on quete_recompense for select to authenticated using (true);
create policy "quete_recompense: ecriture admin"
  on quete_recompense for all to authenticated using (is_admin()) with check (is_admin());

-- ---------------------------------------------------------------------------
-- Choix / annulation d'une quete (tout joueur connecte). La selection directe
-- de la colonne en_cours n'est pas ouverte aux joueurs (policy admin
-- uniquement) : seules ces deux fonctions, security definer, peuvent la
-- changer, avec le verrou commun pour eviter que deux joueurs choisissent
-- chacun une quete au meme instant.
-- ---------------------------------------------------------------------------
create function quete_choisir(p_quete uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  if exists (select 1 from quete where en_cours) then
    raise exception 'Une quête est déjà en cours : annulez-la d''abord.';
  end if;
  update quete set en_cours = true
    where id = p_quete and actif and terminee_le is null;
  if not found then
    raise exception 'Cette quête n''est pas disponible.';
  end if;
end;
$$;

create function quete_annuler_choix()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  update quete set en_cours = false where en_cours;
end;
$$;

-- ---------------------------------------------------------------------------
-- +1 Instance (administrateur) : resout la quete en cours s'il y en a une.
-- Une quete = toujours 1 instance, donc un seul appel suffit a la terminer.
-- Renvoie null si aucune quete n'etait en cours (rien a faire), sinon un
-- recapitulatif utilisable pour l'annulation du +1 Instance.
-- ---------------------------------------------------------------------------
create function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  r record;
  v_items jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select * into q from quete where en_cours for update;
  if not found then
    return null;
  end if;
  if q.recompense_or > 0 then
    update partie_etat set or_compagnie = or_compagnie + q.recompense_or where id;
  end if;
  for r in select objet_id, quantite from quete_recompense where quete_id = q.id order by position
  loop
    perform _arsenal_ajouter(r.objet_id, r.quantite);
    v_items := v_items || jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite);
  end loop;
  update quete set en_cours = false, terminee_le = now() where id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : +' || q.recompense_or || ' Po, ' || jsonb_array_length(v_items) || ' objet(s) rejoignent l''arsenal.',
    q.recompense_or, jsonb_build_object('quete_id', q.id, 'items', v_items));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom, 'or', q.recompense_or, 'items', v_items);
end;
$$;

create function quetes_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  i jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_gains is null then
    return;
  end if;
  perform _verrou_partie();
  if coalesce((p_gains ->> 'or')::integer, 0) > 0 then
    update partie_etat set or_compagnie = or_compagnie - (p_gains ->> 'or')::integer where id;
  end if;
  for i in select * from jsonb_array_elements(coalesce(p_gains -> 'items', '[]'::jsonb))
  loop
    perform _arsenal_retirer((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
  end loop;
  update quete set en_cours = true, terminee_le = null where id = (p_gains ->> 'quete_id')::uuid;
  perform _journal('annulation', 'Quête accomplie annulée (+1 Instance annulé).',
    -coalesce((p_gains ->> 'or')::integer, 0), jsonb_build_object('annule_quete', p_gains ->> 'quete_id'));
end;
$$;

revoke all on function quete_choisir(uuid) from public;
revoke all on function quete_annuler_choix() from public;
revoke all on function quetes_instance() from public;
revoke all on function quetes_annuler_instance(jsonb) from public;
grant execute on function quete_choisir(uuid) to authenticated;
grant execute on function quete_annuler_choix() to authenticated;
grant execute on function quetes_instance() to authenticated;
grant execute on function quetes_annuler_instance(jsonb) to authenticated;

-- Migration des 4 quetes actuellement codees en dur dans Quests.jsx (pas
-- d'icone de type pour l'instant : "pas encore cree", cf. echange avec Bruno).
insert into quete (nom, description, veterance_requise) values
  ('Le Marteau de Feu', 'Retrouvez l’artefact du prince Galwin dans les mines maudites de Kersang.', 3),
  ('La Faille', 'Description à renseigner.', 8),
  ('Le Dignitaire', 'Description à renseigner.', 4),
  ('Camp Gobelin', 'Description à renseigner.', 3);

-- Mise a jour en direct chez tous les joueurs (Supabase Realtime).
do $$
begin
  alter publication supabase_realtime add table quete;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
do $$
begin
  alter publication supabase_realtime add table quete_recompense;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
