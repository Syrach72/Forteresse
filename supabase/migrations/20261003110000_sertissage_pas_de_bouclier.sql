-- Les boucliers (rangés sous Armures) ne se sertissent pas (Bruno, 2026-10-03).
create or replace function sertissage_lancer(p_arme_objet uuid, p_arme_gemmes uuid[], p_gemme_objet uuid,
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
  if _est_bouclier(v_arme.categorie_id) then
    raise exception 'Un bouclier ne peut pas être serti.';
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

