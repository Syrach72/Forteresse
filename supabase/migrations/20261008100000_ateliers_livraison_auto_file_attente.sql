-- Ateliers : livraison automatique et liste d'attente (demande de Bruno, 2026-10-08).
--  * Quand une fabrication (forge, armurerie, tour du mage, laboratoire) ou un sertissage atteint 0 à un
--    +1 Instance, l'objet rejoint TOUT SEUL l'arsenal : plus de bouton « Envoyer à l'Arsenal ».
--  * Chaque atelier de fabrication a une liste d'attente de 2 objets (table atelier_file). Les ressources
--    sont retirées de l'arsenal dès l'ajout en file. Dès que l'objet en cours est livré, le premier de la file
--    prend le relais avec sa durée d'instance complète (il ne décompte qu'au +1 Instance suivant).
--    Le sertissage n'a pas de liste d'attente.
--  * ateliers_instance() livre et fait le relais ; ateliers_annuler_instance() défait tout (reprise de l'objet
--    dans l'arsenal ; refusée avec un message si l'objet n'y est plus).
--  * partie_annuler() sait annuler un objet en liste d'attente (rembourse) et fait le relais si l'objet annulé
--    était celui en cours.
--  * Les fabrications déjà terminées (restant = 0) mais pas encore récupérées sont livrées au prochain +1 Instance.

-- ---------------------------------------------------------------------------
-- 1. Liste d'attente
-- ---------------------------------------------------------------------------
create table atelier_file (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  atelier text not null check (atelier in ('forge', 'armurerie', 'alchimie', 'mage')),
  position smallint not null check (position between 1 and 2),
  objet_id uuid not null references objet_catalogue (id),
  quantite smallint not null default 1 check (quantite >= 1),
  duree smallint not null check (duree >= 1),
  journal_id uuid,
  created_at timestamptz not null default now(),
  unique (session_id, atelier, position)
);
alter table atelier_file enable row level security;
create policy "atelier_file: lecture" on atelier_file for select to authenticated
  using (session_id = ctx_session());
create policy "atelier_file: ecriture admin" on atelier_file for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "atelier_file: fonctions serveur" on atelier_file for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());
grant select, insert, update, delete on atelier_file to authenticated, fortress_fn;
revoke all on atelier_file from anon;

do $$
begin
  alter publication supabase_realtime add table atelier_file;
exception when undefined_object then null; when duplicate_object then null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Relais : le premier de la file prend la place de l'atelier (vide). Renvoie sa description ou null.
-- ---------------------------------------------------------------------------
create or replace function _atelier_promouvoir(p_atelier text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  f atelier_file%rowtype;
  v_nom text;
begin
  select * into f from atelier_file where atelier = p_atelier order by position limit 1;
  if not found then
    return null;
  end if;
  insert into atelier_fabrication (atelier, objet_id, quantite, restant, journal_id)
    values (p_atelier, f.objet_id, f.quantite, f.duree, f.journal_id);
  delete from atelier_file where id = f.id;
  update atelier_file set position = position - 1 where atelier = p_atelier;
  select nom into v_nom from objet_catalogue where id = f.objet_id;
  return jsonb_build_object('objet_id', f.objet_id, 'quantite', f.quantite, 'duree', f.duree,
    'journal_id', f.journal_id, 'nom', v_nom);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Fabrication : atelier occupé = liste d'attente (2 objets au plus)
-- ---------------------------------------------------------------------------
create or replace function partie_fabriquer(p_objet uuid, p_atelier text default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  o objet_catalogue%rowtype;
  rec recette%rowtype;
  i record;
  v_route text;
  v_duree integer;
  v_quantite integer;
  v_message text;
  v_jid uuid;
  v_file boolean;
  v_attente boolean := false;
  v_n integer := 0;
  v_ingredients jsonb;
begin
  perform _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  select * into rec from recette
    where resultat_objet_id = p_objet and coalesce(actif, true)
    order by code_unique limit 1;
  if o.id is null or rec.id is null then
    raise exception 'Cette recette n''existe pas.';
  end if;
  if not exists (select 1 from ingredient_recette where recette_id = rec.id) then
    raise exception 'Cette recette n''a pas encore d''ingrédients définis.';
  end if;
  v_route := case rec.atelier::text when 'magie' then 'mage' else rec.atelier::text end;
  if lower(coalesce(_racine_categorie(o.categorie_id), '')) = 'objet divers' then
    if p_atelier is null or p_atelier not in ('forge', 'armurerie') then
      raise exception 'Choisissez la forge ou l''armurerie pour fabriquer cet objet.';
    end if;
    v_route := p_atelier;
  end if;
  v_duree := coalesce(o.duree_fabrication_instances, 0);
  v_file := v_duree > 0;
  if v_file and exists (select 1 from atelier_fabrication where atelier = v_route) then
    select count(*) into v_n from atelier_file where atelier = v_route;
    if v_n >= 2 then
      raise exception 'La liste d''attente de cet atelier est pleine (2 objets).';
    end if;
    v_attente := true;
  end if;
  for i in select objet_id, quantite_requise from ingredient_recette where recette_id = rec.id
  loop
    if _arsenal_quantite(i.objet_id) < i.quantite_requise then
      raise exception 'Ressources insuffisantes pour cette fabrication.';
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('objet_id', objet_id, 'quantite', quantite_requise)), '[]'::jsonb)
    into v_ingredients from ingredient_recette where recette_id = rec.id;
  for i in select objet_id, quantite_requise from ingredient_recette where recette_id = rec.id
  loop
    perform _arsenal_retirer(i.objet_id, i.quantite_requise);
  end loop;
  v_quantite := coalesce(rec.quantite_produite, 1);
  if v_attente then
    v_message := o.nom || ' : ajouté à la liste d’attente de l’atelier. Il prendra le relais automatiquement.';
  elsif v_file then
    v_message := o.nom || ' : fabrication lancée. Elle rejoindra l’arsenal toute seule une fois la durée d’instance à 0.';
  else
    perform _arsenal_ajouter(p_objet, v_quantite);
    v_message := o.nom || ' fabriqué et ajouté au stock.';
  end if;
  v_jid := _journal('fabrication', v_message, 0, jsonb_build_object(
    'objet_id', p_objet, 'quantite', v_quantite, 'atelier', v_route,
    'file', v_file, 'attente', v_attente, 'ingredients', v_ingredients));
  if v_attente then
    insert into atelier_file (atelier, position, objet_id, quantite, duree, journal_id)
      values (v_route, v_n + 1, p_objet, v_quantite, v_duree, v_jid);
  elsif v_file then
    insert into atelier_fabrication (atelier, objet_id, quantite, restant, journal_id)
      values (v_route, p_objet, v_quantite, v_duree, v_jid);
  end if;
  return jsonb_build_object('journal_id', v_jid, 'atelier', v_route, 'file', v_file,
    'attente', v_attente, 'message', v_message);
exception
  when unique_violation then
    raise exception 'Une fabrication est déjà en cours dans cet atelier.';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Annulation d'une fabrication (fiche) : prise en compte de la liste d'attente
-- ---------------------------------------------------------------------------
create or replace function partie_annuler(p_journal uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  j partie_journal%rowtype;
  o objet_catalogue%rowtype;
  i jsonb;
  v_message text;
  v_gemmes uuid[];
  v_atelier text;
  v_pos integer;
begin
  v_or := _verrou_partie();
  select * into j from partie_journal where id = p_journal for update;
  if not found then
    raise exception 'Opération introuvable.';
  end if;
  if not is_admin() and j.auteur_id is distinct from auth.uid() then
    raise exception 'Seul l''auteur de l''opération peut l''annuler.';
  end if;
  if j.annule then
    raise exception 'Cette opération est déjà annulée.';
  end if;
  if j.type not in ('achat', 'fabrication', 'vente') then
    raise exception 'Cette opération ne peut pas être annulée.';
  end if;
  select * into o from objet_catalogue where id = (j.details ->> 'objet_id')::uuid;
  if j.type = 'vente' then
    if v_or < j.montant then
      raise exception 'Annulation impossible : la trésorerie ne couvre plus le montant de la vente (% Po).', j.montant;
    end if;
    v_gemmes := case when jsonb_typeof(j.details -> 'gemmes') = 'array'
      then array(select jsonb_array_elements_text(j.details -> 'gemmes')::uuid) end;
    perform _arsenal_ajouter(o.id, (j.details ->> 'quantite')::integer, v_gemmes);
    update partie_etat set or_compagnie = or_compagnie - j.montant where id;
    v_message := 'Vente annulée : objet rendu à l’arsenal, pièces d’or reprises.';
  elsif j.type = 'achat' then
    if _arsenal_quantite(o.id) < 1 then
      raise exception 'Annulation impossible : cet objet n''est plus disponible.';
    end if;
    perform _arsenal_retirer(o.id, 1);
    update partie_etat set or_compagnie = or_compagnie - j.montant where id;
    v_message := 'Achat annulé : pièces d’or remboursées.';
  else
    if (j.details ->> 'file')::boolean then
      select atelier into v_atelier from atelier_fabrication where journal_id = p_journal;
      if found then
        -- objet en cours : l'atelier est libéré, le premier de la liste d'attente prend le relais
        delete from atelier_fabrication where journal_id = p_journal;
        perform _atelier_promouvoir(v_atelier);
      else
        select atelier, position into v_atelier, v_pos from atelier_file where journal_id = p_journal;
        if not found then
          raise exception 'Annulation impossible : la fabrication est déjà terminée et livrée.';
        end if;
        delete from atelier_file where journal_id = p_journal;
        update atelier_file set position = position - 1 where atelier = v_atelier and position > v_pos;
      end if;
    else
      if _arsenal_quantite(o.id) < (j.details ->> 'quantite')::integer then
        raise exception 'Annulation impossible : cet objet n''est plus disponible.';
      end if;
      perform _arsenal_retirer(o.id, (j.details ->> 'quantite')::integer);
    end if;
    for i in select * from jsonb_array_elements(j.details -> 'ingredients')
    loop
      perform _arsenal_ajouter((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
    end loop;
    v_message := 'Fabrication annulée : ressources restituées.';
  end if;
  update partie_journal set annule = true where id = p_journal;
  perform _journal('annulation', v_message, -j.montant, jsonb_build_object('annule', p_journal));
  return jsonb_build_object('message', v_message);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. +1 Instance : décompte, livraison automatique à l'arsenal, relais de la liste d'attente
--    Chaque gain : { atelier, de, a } ; à 0 il ajoute livre, objet_id, nom, quantite, journal_id,
--    livraison_journal et, s'il y a relais, promu { objet_id, quantite, duree, journal_id, nom }.
--    Un sertissage livré ajoute gemmes_avant, gemme_objet_id, gemmes_apres.
-- ---------------------------------------------------------------------------
create or replace function ateliers_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  s forge_sertissage%rowtype;
  o objet_catalogue%rowtype;
  v_apres integer;
  v_gains jsonb := '[]'::jsonb;
  v_g jsonb;
  v_promu jsonb;
  v_jid uuid;
  v_gemmes_apres uuid[];
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  for r in select * from atelier_fabrication order by atelier for update
  loop
    v_apres := greatest(r.restant - 1, 0);
    update atelier_fabrication set restant = v_apres where atelier = r.atelier;
    v_g := jsonb_build_object('atelier', r.atelier, 'de', r.restant, 'a', v_apres);
    if v_apres = 0 then
      select * into o from objet_catalogue where id = r.objet_id;
      perform _arsenal_ajouter(r.objet_id, r.quantite);
      v_jid := _journal('recuperation', o.nom || ' est terminé et a rejoint l’arsenal.', 0,
        jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite, 'atelier', r.atelier, 'auto', true));
      delete from atelier_fabrication where atelier = r.atelier;
      v_g := v_g || jsonb_build_object('livre', true, 'objet_id', r.objet_id, 'nom', o.nom,
        'quantite', r.quantite, 'journal_id', r.journal_id, 'livraison_journal', v_jid);
      v_promu := _atelier_promouvoir(r.atelier);
      if v_promu is not null then
        v_g := v_g || jsonb_build_object('promu', v_promu);
        perform _journal('recuperation', (v_promu ->> 'nom') || ' prend le relais dans l’atelier.', 0,
          jsonb_build_object('objet_id', (v_promu ->> 'objet_id')::uuid, 'atelier', r.atelier, 'relais', true));
      end if;
    end if;
    v_gains := v_gains || v_g;
  end loop;
  for s in select * from forge_sertissage where arme_objet_id is not null order by atelier for update
  loop
    v_apres := greatest(s.restant - 1, 0);
    v_g := jsonb_build_object(
      'atelier', case when s.atelier = 'forge' then 'sertissage' else 'sertissage-' || s.atelier end,
      'de', s.restant, 'a', v_apres);
    if v_apres = 0 then
      v_gemmes_apres := (select array_agg(x order by x) from unnest(s.arme_gemmes || s.gemme_objet_id) x);
      perform _arsenal_ajouter(s.arme_objet_id, 1, v_gemmes_apres);
      select * into o from objet_catalogue where id = s.arme_objet_id;
      v_jid := _journal('recuperation', o.nom || ' sertie a rejoint l’arsenal.', 0,
        jsonb_build_object('objet_id', s.arme_objet_id, 'gemmes', v_gemmes_apres, 'auto', true));
      v_g := v_g || jsonb_build_object('livre', true, 'objet_id', s.arme_objet_id, 'nom', o.nom,
        'quantite', 1, 'journal_id', s.journal_id, 'livraison_journal', v_jid,
        'gemmes_avant', to_jsonb(s.arme_gemmes), 'gemme_objet_id', s.gemme_objet_id,
        'gemmes_apres', to_jsonb(v_gemmes_apres));
      if s.atelier = 'forge' then
        update forge_sertissage set arme_objet_id = null, arme_gemmes = '{}', gemme_objet_id = null,
          restant = null, journal_id = null where atelier = 'forge';
      else
        delete from forge_sertissage where atelier = s.atelier;
      end if;
    else
      update forge_sertissage set restant = v_apres where atelier = s.atelier;
    end if;
    v_gains := v_gains || v_g;
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
  v_atelier text;
  v_promu jsonb;
  v_obj uuid;
  v_gemmes_apres uuid[];
  v_gemmes_avant uuid[];
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb))
  loop
    v_atelier := g ->> 'atelier';
    if coalesce((g ->> 'livre')::boolean, false) then
      v_obj := (g ->> 'objet_id')::uuid;
      if v_atelier like 'sertissage%' then
        v_gemmes_apres := array(select jsonb_array_elements_text(g -> 'gemmes_apres')::uuid);
        v_gemmes_avant := array(select jsonb_array_elements_text(g -> 'gemmes_avant')::uuid);
        if _arsenal_quantite(v_obj, v_gemmes_apres) < 1 then
          raise exception 'Annulation impossible : % (sertissage) n''est plus dans l''arsenal.', g ->> 'nom';
        end if;
        perform _arsenal_retirer(v_obj, 1, v_gemmes_apres);
        insert into forge_sertissage (atelier, arme_objet_id, arme_gemmes, gemme_objet_id, restant, journal_id)
          values (case when v_atelier = 'sertissage' then 'forge' else 'armurerie' end,
            v_obj, v_gemmes_avant, (g ->> 'gemme_objet_id')::uuid, (g ->> 'de')::integer,
            nullif(g ->> 'journal_id', '')::uuid)
          on conflict (session_id, atelier) do update
            set arme_objet_id = excluded.arme_objet_id, arme_gemmes = excluded.arme_gemmes,
                gemme_objet_id = excluded.gemme_objet_id, restant = excluded.restant,
                journal_id = excluded.journal_id;
      else
        if _arsenal_quantite(v_obj) < (g ->> 'quantite')::integer then
          raise exception 'Annulation impossible : % n''est plus dans l''arsenal.', g ->> 'nom';
        end if;
        v_promu := g -> 'promu';
        if v_promu is not null then
          -- le relais est défait : l'objet repasse en tête de la liste d'attente
          delete from atelier_fabrication
            where atelier = v_atelier and journal_id = nullif(v_promu ->> 'journal_id', '')::uuid
              and restant = (v_promu ->> 'duree')::integer;
          if not found then
            raise exception 'Annulation impossible : l''objet qui a pris le relais a déjà changé.';
          end if;
          if (select count(*) from atelier_file where atelier = v_atelier) >= 2 then
            raise exception 'Annulation impossible : la liste d''attente de l''atelier est pleine.';
          end if;
          update atelier_file set position = position + 1 where atelier = v_atelier;
          insert into atelier_file (atelier, position, objet_id, quantite, duree, journal_id)
            values (v_atelier, 1, (v_promu ->> 'objet_id')::uuid, (v_promu ->> 'quantite')::integer,
              (v_promu ->> 'duree')::integer, nullif(v_promu ->> 'journal_id', '')::uuid);
        end if;
        perform _arsenal_retirer(v_obj, (g ->> 'quantite')::integer);
        insert into atelier_fabrication (atelier, objet_id, quantite, restant, journal_id)
          values (v_atelier, v_obj, (g ->> 'quantite')::integer, (g ->> 'de')::integer,
            nullif(g ->> 'journal_id', '')::uuid);
      end if;
      -- les lignes de journal de la livraison (et du relais) disparaissent avec l'instance annulée
      delete from partie_journal
        where session_id = ctx_session() and id = nullif(g ->> 'livraison_journal', '')::uuid;
    elsif v_atelier = 'sertissage' then
      update forge_sertissage
        set restant = (g ->> 'de')::integer
        where atelier = 'forge' and restant = (g ->> 'a')::integer;
    elsif v_atelier = 'sertissage-armurerie' then
      update forge_sertissage
        set restant = (g ->> 'de')::integer
        where atelier = 'armurerie' and restant = (g ->> 'a')::integer;
    else
      update atelier_fabrication
        set restant = (g ->> 'de')::integer
        where atelier = v_atelier and restant = (g ->> 'a')::integer;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Remise à zéro d'une session : la liste d'attente part aussi
-- ---------------------------------------------------------------------------
create or replace function session_reinitialiser(p_session uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  t text;
  v_donnees jsonb := '{}'::jsonb;
  v_table jsonb;
  v_ordre text[] := array[
    'cimetiere', 'recrutement_gratuit', 'objet_quete_active', 'creature_quete', 'quete_mercenaire', 'entrainement_place', 'infirmerie_place', 'recrutement',
    'mercenaire_equipement', 'ligne_inventaire', 'inventaire', 'atelier_file', 'atelier_fabrication',
    'forge_sertissage', 'employe',
    'partie_journal', 'partie_etat', 'dortoir_reglage', 'entrainement_reglage',
    'infirmerie_reglage', 'mercenaire_etat', 'quete_etat', 'budget_poste'];
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  perform 1 from session where id = p_session for update;
  if not found then
    raise exception 'Session introuvable.';
  end if;
  foreach t in array v_ordre loop
    execute format(
      'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from %I x where x.session_id = $1', t)
      into v_table using p_session;
    v_donnees := v_donnees || jsonb_build_object(t, v_table);
  end loop;
  insert into session_sauvegarde (session_id, motif, donnees)
    values (p_session, 'Remise à zéro par le MJ', v_donnees);
  foreach t in array v_ordre loop
    execute format('delete from %I where session_id = $1', t) using p_session;
  end loop;
  update session set lancee_le = null where id = p_session;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Propriétaire fortress_fn (isolation par session) et droits
-- ---------------------------------------------------------------------------
grant create on schema public to fortress_fn;
alter function _atelier_promouvoir(text) owner to fortress_fn;
alter function partie_fabriquer(uuid, text) owner to fortress_fn;
alter function partie_annuler(uuid) owner to fortress_fn;
alter function ateliers_instance() owner to fortress_fn;
alter function ateliers_annuler_instance(jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _atelier_promouvoir(text) from public;
revoke all on function partie_fabriquer(uuid, text) from public;
revoke all on function partie_annuler(uuid) from public;
revoke all on function ateliers_instance() from public;
revoke all on function ateliers_annuler_instance(jsonb) from public;
grant execute on function partie_fabriquer(uuid, text) to authenticated, fortress_fn;
grant execute on function partie_annuler(uuid) to authenticated;
grant execute on function ateliers_instance() to authenticated;
grant execute on function ateliers_annuler_instance(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Fabrications déjà terminées mais non récupérées : livrées maintenant (à l'ancienne façon).
-- ---------------------------------------------------------------------------
-- (traitées au prochain +1 Instance par ateliers_instance(), qui livre tout ce qui est à 0.)

-- ---------------------------------------------------------------------------
-- 9. Journal de l'instance : le MJ publie le résumé du +1 Instance (phrases déjà calculées par son client),
--    lu par tous les joueurs de la session (partie_etat est déjà partagé en direct) : le panneau
--    « Journal de l'instance » s'ouvre chez tout le monde. Annuler l'instance l'efface (p_resume null).
-- ---------------------------------------------------------------------------
alter table partie_etat add column if not exists derniere_instance jsonb;

create or replace function instance_resume_publier(p_resume jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  update partie_etat set derniere_instance = p_resume
    where id and session_id = ctx_session();
end;
$$;

grant create on schema public to fortress_fn;
alter function instance_resume_publier(jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function instance_resume_publier(jsonb) from public;
grant execute on function instance_resume_publier(jsonb) to authenticated;
