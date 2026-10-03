-- Sertissage d'armure a l'Armurerie (demande de Bruno, 2026-10-03) : meme principe que le sertissage
-- de puissance de la Forge (20260922140000_sertissage_forge.sql). Le joueur place une armure et une
-- gemme prelevees dans l'arsenal ; 1 instance plus tard, l'armure sertie (jusqu'a 3 gemmes, comme
-- une arme : a confirmer par Bruno) rejoint l'arsenal. Independant de la fabrication de l'armurerie.
--
-- On reutilise la table forge_sertissage (une ligne par session) en ajoutant une colonne `atelier`
-- ('forge' ou 'armurerie') : la ligne de l'armurerie est creee au premier sertissage et supprimee a la
-- recuperation. La Forge garde sa ligne permanente, comme avant. Les fonctions sont recreees avec un
-- parametre `p_atelier` (defaut 'forge' : l'ancien client continue de fonctionner).

alter table forge_sertissage add column if not exists atelier text not null default 'forge'
  check (atelier in ('forge', 'armurerie'));
alter table forge_sertissage drop constraint forge_sertissage_pkey, add primary key (session_id, atelier);

drop function if exists sertissage_lancer(uuid, uuid[], uuid);
create function sertissage_lancer(p_arme_objet uuid, p_arme_gemmes uuid[], p_gemme_objet uuid,
  p_atelier text default 'forge')
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_arme objet_catalogue%rowtype;
  v_gemme objet_catalogue%rowtype;
  v_gemmes uuid[];
  v_jid uuid;
  v_racine text := case when p_atelier = 'armurerie' then 'Armures' else 'Armes' end;
  v_lieu text := case when p_atelier = 'armurerie' then 'l''armurerie' else 'la forge' end;
begin
  perform _verrou_partie();
  if p_atelier not in ('forge', 'armurerie') then
    raise exception 'Atelier inconnu.';
  end if;
  if exists (select 1 from forge_sertissage where atelier = p_atelier and arme_objet_id is not null) then
    raise exception 'Un sertissage est déjà en cours à %.', v_lieu;
  end if;
  v_gemmes := (select coalesce(array_agg(x order by x), '{}'::uuid[]) from unnest(coalesce(p_arme_gemmes, '{}'::uuid[])) x);
  if coalesce(array_length(v_gemmes, 1), 0) >= 3 then
    raise exception 'Cet objet porte déjà 3 gemmes : il ne peut pas en recevoir davantage.';
  end if;
  select * into v_arme from objet_catalogue where id = p_arme_objet;
  if not found then
    raise exception 'Objet inconnu.';
  end if;
  if _racine_categorie(v_arme.categorie_id) is distinct from v_racine then
    raise exception 'Seul un objet de la rubrique % peut être envoyé au sertissage ici.', v_racine;
  end if;
  select * into v_gemme from objet_catalogue where id = p_gemme_objet;
  if not found then
    raise exception 'Gemme inconnue.';
  end if;
  if _racine_categorie(v_gemme.categorie_id) is distinct from 'Gemmes' then
    raise exception 'Seule une gemme peut être employée pour un sertissage.';
  end if;
  if _arsenal_quantite(p_arme_objet, v_gemmes) < 1 then
    raise exception 'Cet objet n''est plus disponible dans l''arsenal.';
  end if;
  if _arsenal_quantite(p_gemme_objet, null) < 1 then
    raise exception 'Cette gemme n''est plus disponible dans l''arsenal.';
  end if;
  perform _arsenal_retirer(p_arme_objet, 1, v_gemmes);
  perform _arsenal_retirer(p_gemme_objet, 1, null);
  v_jid := _journal('sertissage', v_gemme.nom || ' envoyée au sertissage sur ' || v_arme.nom || '.', 0,
    jsonb_build_object('arme_objet_id', p_arme_objet, 'arme_gemmes', v_gemmes, 'gemme_objet_id', p_gemme_objet,
      'atelier', p_atelier));
  insert into forge_sertissage (atelier, arme_objet_id, arme_gemmes, gemme_objet_id, restant, journal_id)
    values (p_atelier, p_arme_objet, v_gemmes, p_gemme_objet, 1, v_jid)
    on conflict (session_id, atelier) do update
      set arme_objet_id = excluded.arme_objet_id, arme_gemmes = excluded.arme_gemmes,
          gemme_objet_id = excluded.gemme_objet_id, restant = excluded.restant, journal_id = excluded.journal_id;
  return jsonb_build_object('journal_id', v_jid);
end;
$$;

drop function if exists sertissage_recuperer();
create function sertissage_recuperer(p_atelier text default 'forge')
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
  select * into s from forge_sertissage where atelier = p_atelier for update;
  if not found or s.arme_objet_id is null then
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
  if p_atelier = 'forge' then
    update forge_sertissage set arme_objet_id = null, arme_gemmes = '{}', gemme_objet_id = null,
      restant = null, journal_id = null where atelier = 'forge';
  else
    delete from forge_sertissage where atelier = p_atelier;
  end if;
  return jsonb_build_object('message', v_message);
end;
$$;

-- +1 Instance : les deux sertissages avancent avec les ateliers. Le gain de l'armurerie est
-- identifie par 'sertissage-armurerie' (celui de la forge reste 'sertissage', comme avant).
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
  for s in select * from forge_sertissage where arme_objet_id is not null and restant > 0 order by atelier for update
  loop
    v_apres := greatest(s.restant - 1, 0);
    update forge_sertissage set restant = v_apres where atelier = s.atelier;
    v_gains := v_gains || jsonb_build_object(
      'atelier', case when s.atelier = 'forge' then 'sertissage' else 'sertissage-' || s.atelier end,
      'de', s.restant, 'a', v_apres);
  end loop;
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
        where atelier = 'forge' and restant = (g ->> 'a')::integer;
    elsif g ->> 'atelier' = 'sertissage-armurerie' then
      update forge_sertissage
        set restant = (g ->> 'de')::integer
        where atelier = 'armurerie' and restant = (g ->> 'a')::integer;
    else
      update atelier_fabrication
        set restant = (g ->> 'de')::integer
        where atelier = g ->> 'atelier' and restant = (g ->> 'a')::integer;
    end if;
  end loop;
end;
$$;

-- Propriétaire fortress_fn (isolation par session, voir docs/SESSIONS.md) et droits.
grant create on schema public to fortress_fn;
alter function sertissage_lancer(uuid, uuid[], uuid, text) owner to fortress_fn;
alter function sertissage_recuperer(text) owner to fortress_fn;
alter function ateliers_instance() owner to fortress_fn;
alter function ateliers_annuler_instance(jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function sertissage_lancer(uuid, uuid[], uuid, text) from public;
revoke all on function sertissage_recuperer(text) from public;
revoke all on function ateliers_instance() from public;
revoke all on function ateliers_annuler_instance(jsonb) from public;
grant execute on function sertissage_lancer(uuid, uuid[], uuid, text) to authenticated;
grant execute on function sertissage_recuperer(text) to authenticated;
grant execute on function ateliers_instance() to authenticated;
grant execute on function ateliers_annuler_instance(jsonb) to authenticated;
