-- Sertissage de puissance a la Forge (regle de Bruno, 2026-09-22) : le joueur
-- place une arme et une gemme prelevees dans l'arsenal ; 1 instance plus tard,
-- l'arme sertie (jusqu'a 3 gemmes) rejoint l'arsenal. Independant de la
-- fabrication normale de la forge (atelier_fabrication) : les deux peuvent
-- etre en cours en meme temps et avancent ensemble au +1 Instance.
--
-- Une arme sertie n'est plus le meme "exemplaire" qu'une arme nue du meme
-- catalogue : ligne_inventaire gagne une colonne gemmes (tableau d'ids), et
-- les outils partages _arsenal_quantite/_ajouter/_retirer (et partie_vendre/
-- partie_detruire) apprennent a filtrer dessus, pour ne jamais melanger le
-- stock d'une arme nue avec celui d'une arme sertie du meme modele.

alter table ligne_inventaire add column if not exists gemmes uuid[];

-- ---------------------------------------------------------------------------
-- Outils partages, desormais sensibles aux gemmes (p_gemmes absent ou null =
-- exemplaire nu, comme avant). Remplace les fonctions de
-- 20260921130000_economie_partagee.sql : leurs appelants existants (plpgsql,
-- jamais lies par OID) continuent de fonctionner sans etre modifies.
-- ---------------------------------------------------------------------------
drop function if exists _arsenal_quantite(uuid);
create function _arsenal_quantite(p_objet uuid, p_gemmes uuid[] default null)
returns integer
language sql
security definer set search_path = public
as $$
  select coalesce(sum(quantite), 0)::integer
  from ligne_inventaire
  where inventaire_id = _arsenal_id() and objet_id = p_objet and gemmes is not distinct from p_gemmes;
$$;

drop function if exists _arsenal_ajouter(uuid, integer);
create function _arsenal_ajouter(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update ligne_inventaire
    set quantite = quantite + p_quantite, updated_at = now()
    where id = (
      select id from ligne_inventaire
      where inventaire_id = _arsenal_id() and objet_id = p_objet and gemmes is not distinct from p_gemmes
      order by created_at, id limit 1);
  if not found then
    insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
      values (_arsenal_id(), p_objet, p_quantite, p_gemmes);
  end if;
end;
$$;

drop function if exists _arsenal_retirer(uuid, integer);
create function _arsenal_retirer(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  l record;
  v_reste integer := p_quantite;
  v_pris integer;
begin
  if _arsenal_quantite(p_objet, p_gemmes) < p_quantite then
    raise exception 'Quantité insuffisante dans l''arsenal.';
  end if;
  for l in
    select id, quantite from ligne_inventaire
    where inventaire_id = _arsenal_id() and objet_id = p_objet and gemmes is not distinct from p_gemmes and quantite > 0
    order by created_at, id
    for update
  loop
    exit when v_reste <= 0;
    v_pris := least(l.quantite, v_reste);
    if v_pris = l.quantite then
      delete from ligne_inventaire where id = l.id;
    else
      update ligne_inventaire
        set quantite = quantite - v_pris, updated_at = now()
        where id = l.id;
    end if;
    v_reste := v_reste - v_pris;
  end loop;
end;
$$;

-- Vente et destruction : meme genre d'extension, pour pouvoir cibler
-- specifiquement une arme sertie depuis la fiche de l'arsenal.
drop function if exists partie_vendre(uuid, integer);
create function partie_vendre(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  o objet_catalogue%rowtype;
  v_gain integer;
begin
  v_or := _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  if not found or coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if _arsenal_quantite(p_objet, p_gemmes) < p_quantite then
    raise exception 'Quantité invalide : cet objet n''est pas disponible en telle quantité dans l''arsenal.';
  end if;
  if o.cout_achat_or is null then
    raise exception 'La valeur de cet objet n''est pas définie : vente impossible.';
  end if;
  v_gain := floor((o.cout_achat_or * p_quantite) / 2.0);
  perform _arsenal_retirer(p_objet, p_quantite, p_gemmes);
  update partie_etat set or_compagnie = or_compagnie + v_gain where id;
  perform _journal('vente', 'Vente de ' || o.nom || ' ×' || p_quantite || ' : +' || v_gain || ' Po.',
    v_gain, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite, 'gemmes', p_gemmes));
  return jsonb_build_object('or', v_or + v_gain, 'gain', v_gain);
end;
$$;

drop function if exists partie_detruire(uuid, integer);
create function partie_detruire(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
begin
  perform _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  if not found or coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if _arsenal_quantite(p_objet, p_gemmes) < p_quantite then
    raise exception 'Quantité invalide : cet objet n''est pas disponible en telle quantité dans l''arsenal.';
  end if;
  perform _arsenal_retirer(p_objet, p_quantite, p_gemmes);
  perform _journal('destruction', 'Destruction de ' || o.nom || ' ×' || p_quantite || '.', 0,
    jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite, 'gemmes', p_gemmes));
end;
$$;

-- ---------------------------------------------------------------------------
-- Sertissage en cours a la Forge : une seule ligne (comme partie_etat), vide
-- (arme_objet_id null) tant qu'aucun sertissage n'est lance.
-- ---------------------------------------------------------------------------
create table forge_sertissage (
  id boolean primary key default true check (id),
  arme_objet_id uuid references objet_catalogue (id),
  arme_gemmes uuid[] not null default '{}',
  gemme_objet_id uuid references objet_catalogue (id),
  restant smallint check (restant between 0 and 1),
  journal_id uuid,
  created_at timestamptz not null default now()
);
insert into forge_sertissage default values;

alter table forge_sertissage enable row level security;
create policy "forge_sertissage: lecture par les joueurs connectes"
  on forge_sertissage for select to authenticated using (true);
create policy "forge_sertissage: ecriture admin"
  on forge_sertissage for all to authenticated using (is_admin()) with check (is_admin());

-- Lance un sertissage : l'arme (identifiee par son objet ET les gemmes
-- qu'elle porte deja, pour retirer le bon exemplaire de l'arsenal) et la
-- gemme sont debitees de l'arsenal ; 1 instance plus tard (+1 Instance,
-- comme les ateliers), l'arme sertie est prete a rejoindre l'arsenal.
create function sertissage_lancer(p_arme_objet uuid, p_arme_gemmes uuid[], p_gemme_objet uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_arme objet_catalogue%rowtype;
  v_gemme objet_catalogue%rowtype;
  v_gemmes uuid[];
  v_jid uuid;
begin
  perform _verrou_partie();
  if exists (select 1 from forge_sertissage where arme_objet_id is not null) then
    raise exception 'Un sertissage est déjà en cours à la forge.';
  end if;
  v_gemmes := (select coalesce(array_agg(x order by x), '{}'::uuid[]) from unnest(coalesce(p_arme_gemmes, '{}'::uuid[])) x);
  if coalesce(array_length(v_gemmes, 1), 0) >= 3 then
    raise exception 'Cette arme porte déjà 3 gemmes : elle ne peut pas en recevoir davantage.';
  end if;
  select * into v_arme from objet_catalogue where id = p_arme_objet;
  if not found then
    raise exception 'Arme inconnue.';
  end if;
  if _racine_categorie(v_arme.categorie_id) is distinct from 'Armes' then
    raise exception 'Seule une arme peut être envoyée au sertissage.';
  end if;
  select * into v_gemme from objet_catalogue where id = p_gemme_objet;
  if not found then
    raise exception 'Gemme inconnue.';
  end if;
  if _racine_categorie(v_gemme.categorie_id) is distinct from 'Gemmes' then
    raise exception 'Seule une gemme peut être employée pour un sertissage.';
  end if;
  if _arsenal_quantite(p_arme_objet, v_gemmes) < 1 then
    raise exception 'Cette arme n''est plus disponible dans l''arsenal.';
  end if;
  if _arsenal_quantite(p_gemme_objet, null) < 1 then
    raise exception 'Cette gemme n''est plus disponible dans l''arsenal.';
  end if;
  perform _arsenal_retirer(p_arme_objet, 1, v_gemmes);
  perform _arsenal_retirer(p_gemme_objet, 1, null);
  v_jid := _journal('sertissage', v_gemme.nom || ' envoyée au sertissage sur ' || v_arme.nom || '.', 0,
    jsonb_build_object('arme_objet_id', p_arme_objet, 'arme_gemmes', v_gemmes, 'gemme_objet_id', p_gemme_objet));
  update forge_sertissage set arme_objet_id = p_arme_objet, arme_gemmes = v_gemmes,
    gemme_objet_id = p_gemme_objet, restant = 1, journal_id = v_jid where id;
  return jsonb_build_object('journal_id', v_jid);
end;
$$;

-- Recupere un sertissage termine (restant a 0) : l'arme, desormais sertie
-- d'une gemme de plus, rejoint l'arsenal ; la forge est liberee.
create function sertissage_recuperer()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  s forge_sertissage%rowtype;
  o objet_catalogue%rowtype;
  v_gemmes_apres uuid[];
  v_message text;
begin
  perform _verrou_partie();
  select * into s from forge_sertissage where id for update;
  if s.arme_objet_id is null then
    raise exception 'Aucun sertissage à récupérer.';
  end if;
  if s.restant > 0 then
    raise exception 'Le sertissage n''est pas encore terminé.';
  end if;
  v_gemmes_apres := (select array_agg(x order by x) from unnest(s.arme_gemmes || s.gemme_objet_id) x);
  perform _arsenal_ajouter(s.arme_objet_id, 1, v_gemmes_apres);
  select * into o from objet_catalogue where id = s.arme_objet_id;
  v_message := o.nom || ' sertie rejoint l’arsenal.';
  perform _journal('recuperation', v_message, 0,
    jsonb_build_object('objet_id', s.arme_objet_id, 'gemmes', v_gemmes_apres));
  update forge_sertissage set arme_objet_id = null, arme_gemmes = '{}', gemme_objet_id = null,
    restant = null, journal_id = null where id;
  return jsonb_build_object('message', v_message);
end;
$$;

-- ---------------------------------------------------------------------------
-- +1 Instance : le sertissage en cours avance en meme temps que les ateliers
-- (meme bouton administrateur), et son annulation suit le meme mecanisme.
-- ---------------------------------------------------------------------------
create or replace function ateliers_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  v_apres integer;
  v_gains jsonb := '[]'::jsonb;
  s forge_sertissage%rowtype;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for r in select atelier, restant from atelier_fabrication order by atelier for update
  loop
    v_apres := greatest(r.restant - 1, 0);
    update atelier_fabrication set restant = v_apres where atelier = r.atelier;
    v_gains := v_gains || jsonb_build_object('atelier', r.atelier, 'de', r.restant, 'a', v_apres);
  end loop;
  select * into s from forge_sertissage where id for update;
  if s.arme_objet_id is not null and s.restant > 0 then
    v_apres := greatest(s.restant - 1, 0);
    update forge_sertissage set restant = v_apres where id;
    v_gains := v_gains || jsonb_build_object('atelier', 'sertissage', 'de', s.restant, 'a', v_apres);
  end if;
  return v_gains;
end;
$$;

create or replace function ateliers_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    if g ->> 'atelier' = 'sertissage' then
      update forge_sertissage
        set restant = (g ->> 'de')::integer
        where id and restant = (g ->> 'a')::integer;
    else
      update atelier_fabrication
        set restant = (g ->> 'de')::integer
        where atelier = g ->> 'atelier' and restant = (g ->> 'a')::integer;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Nouveau type de journal (le sertissage), meme mecanisme que les migrations
-- precedentes : on cherche le nom reel de la contrainte plutot que de le
-- supposer.
-- ---------------------------------------------------------------------------
do $$
declare
  v_conname text;
begin
  select con.conname into v_conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    where rel.relname = 'partie_journal' and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%type%';
  if v_conname is not null then
    execute format('alter table partie_journal drop constraint %I', v_conname);
  end if;
end;
$$;
alter table partie_journal add constraint partie_journal_type_check
  check (type in ('achat', 'vente', 'destruction', 'fabrication', 'recuperation', 'depense', 'or',
    'annulation', 'sac_envoi', 'sac_retour', 'sertissage'));

-- ---------------------------------------------------------------------------
-- Droits.
-- ---------------------------------------------------------------------------
revoke all on function _arsenal_quantite(uuid, uuid[]) from public;
revoke all on function _arsenal_ajouter(uuid, integer, uuid[]) from public;
revoke all on function _arsenal_retirer(uuid, integer, uuid[]) from public;
revoke all on function sertissage_lancer(uuid, uuid[], uuid) from public;
revoke all on function sertissage_recuperer() from public;
revoke all on function partie_vendre(uuid, integer, uuid[]) from public;
revoke all on function partie_detruire(uuid, integer, uuid[]) from public;
revoke all on function ateliers_instance() from public;
revoke all on function ateliers_annuler_instance(jsonb) from public;
grant execute on function partie_vendre(uuid, integer, uuid[]) to authenticated;
grant execute on function partie_detruire(uuid, integer, uuid[]) to authenticated;
grant execute on function sertissage_lancer(uuid, uuid[], uuid) to authenticated;
grant execute on function sertissage_recuperer() to authenticated;
grant execute on function ateliers_instance() to authenticated;
grant execute on function ateliers_annuler_instance(jsonb) to authenticated;

do $$
begin
  alter publication supabase_realtime add table forge_sertissage;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;
