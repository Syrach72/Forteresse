-- Pseudo de session et radiation d'un joueur (Bruno, 2026-10-05).
--
-- Pseudo utilisé pour cette session : propre à chaque membre d'une session (session_membre.pseudo), saisi une
-- fois à l'entrée dans la session, unique dans la session (sans tenir compte de la casse) ; c'est le nom
-- inscrit sur les mercenaires qu'il recrute.
--
-- Radiation par le MJ :
--  * temporaire (24 h) : session_membre.radie_jusqua ; définitive : radie_definitive. Un radié n'est plus membre
--    actif (est_membre / ctx_session le refusent), donc ne voit plus rien de la session ; la fin des 24 h
--    le réintègre toute seule (la date est comparée à now(), aucune tâche planifiée). Un radié définitif
--    revient avec une nouvelle invitation (session_rejoindre efface la radiation) ; son compte n'est pas bloqué.
--  * Ses mercenaires restent à la Caserne, avec équipement et sac, « en attente d'un joueur » (propriétaire
--    radié). N'importe quel autre membre actif ayant un pseudo peut les reprendre (mercenaire_reprendre) :
--    radiation définitive -> le mercenaire lui appartient pour de bon ; radiation temporaire -> le recrutement
--    garde l'origine (origine_user_id / origine_nom) et revient au joueur d'origine à la fin du délai
--    (retour_le), même si le mercenaire est en quête. Sans repreneur, il reste en attente.
--  * Le MJ peut renvoyer définitivement un mercenaire en attente d'un radié définitif (mercenaire_renvoi_definitif) :
--    équipement et sac rendus à l'arsenal, vétérance 1, compteurs et états remis à zéro, équipement de base
--    redonné au prochain recrutement.

alter table session_membre
  add column pseudo text check (pseudo is null or length(btrim(pseudo)) between 2 and 24),
  add column radie_jusqua timestamptz,
  add column radie_definitive boolean not null default false;
create unique index session_membre_pseudo_unique on session_membre (session_id, lower(btrim(pseudo)))
  where pseudo is not null;

alter table recrutement
  add column origine_user_id uuid references auth.users (id) on delete set null,
  add column origine_nom text,
  add column retour_le timestamptz;

-- Un radié n'est plus membre actif.
create or replace function est_membre(p_session uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select is_admin() or exists (
    select 1 from session_membre
    where session_id = p_session and user_id = auth.uid()
      and not radie_definitive and (radie_jusqua is null or radie_jusqua <= now()));
$$;

create or replace function ctx_session()
returns uuid
language sql
stable
security definer set search_path = public
as $$
  select sa.session_id
  from session_active sa
  where sa.user_id = auth.uid()
    and not sa.contexte_base
    and sa.session_id is not null
    and (is_admin() or exists (
      select 1 from session_membre m
      where m.session_id = sa.session_id and m.user_id = sa.user_id
        and not m.radie_definitive and (m.radie_jusqua is null or m.radie_jusqua <= now())));
$$;

-- Radiation d'un utilisateur dans la session active (lecture réservée aux fonctions : session_membre ne se
-- lit que pour soi). Propriétaire postgres, filtre explicite sur ctx_session().
create function _user_radie(p_user uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select coalesce((select m.radie_definitive or coalesce(m.radie_jusqua > now(), false)
                   from session_membre m
                   where m.session_id = ctx_session() and m.user_id = p_user), false);
$$;

-- Fin de la radiation temporaire (null si définitive ou non radié).
create function _user_radie_jusqua(p_user uuid)
returns timestamptz
language sql
stable
security definer set search_path = public
as $$
  select case when m.radie_definitive then null
              when m.radie_jusqua > now() then m.radie_jusqua end
  from session_membre m
  where m.session_id = ctx_session() and m.user_id = p_user;
$$;

create function session_pseudo_definir(p_pseudo text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v text := btrim(coalesce(p_pseudo, ''));
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  if length(v) < 2 or length(v) > 24 then
    raise exception 'Le pseudo doit faire de 2 à 24 caractères.';
  end if;
  update session_membre set pseudo = v
    where session_id = ctx_session() and user_id = auth.uid();
  if not found then
    raise exception 'Réservé aux joueurs de la session.';
  end if;
exception
  when unique_violation then
    raise exception 'Ce pseudo est déjà utilisé dans cette session.';
end;
$$;

-- MJ : joueurs d'une session (pseudo de compte, pseudo de session, radiation, nombre de mercenaires).
create function session_membres_liste(p_session uuid)
returns table (user_id uuid, email text, pseudo_compte text, pseudo_session text,
               radie_jusqua timestamptz, radie_definitive boolean, mercenaires integer)
language plpgsql
stable
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  return query
    select m.user_id, u.email::text, (u.raw_user_meta_data ->> 'pseudo'), m.pseudo,
           m.radie_jusqua, m.radie_definitive,
           (select count(*)::integer from recrutement r
              where r.session_id = p_session and r.user_id = m.user_id)
    from session_membre m join auth.users u on u.id = m.user_id
    where m.session_id = p_session
    order by m.created_at;
end;
$$;

create function session_radier(p_session uuid, p_user uuid, p_definitif boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  update session_membre
    set radie_definitive = coalesce(p_definitif, false),
        radie_jusqua = case when coalesce(p_definitif, false) then null else now() + interval '24 hours' end
    where session_id = p_session and user_id = p_user;
  if not found then
    raise exception 'Ce joueur ne fait pas partie de cette session.';
  end if;
end;
$$;

create function session_reintegrer(p_session uuid, p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  update session_membre set radie_definitive = false, radie_jusqua = null
    where session_id = p_session and user_id = p_user;
end;
$$;

-- Un radié définitif revient avec une nouvelle invitation : la radiation est effacée.
create or replace function session_rejoindre(p_code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_session uuid;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  update invitation
     set utilise_par = auth.uid(), utilise_le = now()
   where code = normaliser_invitation(p_code) and utilise_par is null
   returning session_id into v_session;
  if not found then
    raise exception 'Invitation invalide ou déjà utilisée.';
  end if;
  insert into session_membre (session_id, user_id) values (v_session, auth.uid())
    on conflict (session_id, user_id) do update set radie_definitive = false, radie_jusqua = null;
  insert into session_active (user_id, session_id, contexte_base) values (auth.uid(), v_session, false)
    on conflict (user_id) do update set session_id = v_session, contexte_base = false;
  return v_session;
end;
$$;

-- Retour des mercenaires prêtés à la fin de la radiation de leur propriétaire d'origine, puis liste des
-- mercenaires « en attente d'un joueur » (propriétaire radié ; `definitif` = radiation définitive) de la session active. Appelée à chaque
-- synchronisation du client : le retour ne dépend d'aucune tâche planifiée.
create function radiations_etat()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  v_attente jsonb;
begin
  if auth.uid() is null or ctx_session() is null then
    return '[]'::jsonb;
  end if;
  for r in select mercenaire_id, origine_user_id, origine_nom from recrutement
           where session_id = ctx_session() and retour_le is not null and retour_le <= now() loop
    if r.origine_user_id is not null then
      update recrutement
        set user_id = r.origine_user_id, nom_joueur = coalesce(r.origine_nom, nom_joueur),
            origine_user_id = null, origine_nom = null, retour_le = null
        where session_id = ctx_session() and mercenaire_id = r.mercenaire_id;
    else
      update recrutement set origine_nom = null, retour_le = null
        where session_id = ctx_session() and mercenaire_id = r.mercenaire_id;
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('mercenaire_id', mercenaire_id, 'definitif', _user_radie_jusqua(user_id) is null)), '[]'::jsonb) into v_attente
    from recrutement where session_id = ctx_session() and _user_radie(user_id);
  return v_attente;
end;
$$;

create function mercenaire_reprendre(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  r recrutement%rowtype;
  v_pseudo text;
  v_retour timestamptz;
  v_nom text;
begin
  perform _verrou_partie();
  select pseudo into v_pseudo from session_membre
    where session_id = ctx_session() and user_id = auth.uid();
  if v_pseudo is null then
    raise exception 'Inscrivez d''abord votre pseudo pour cette session.';
  end if;
  select * into r from recrutement
    where session_id = ctx_session() and mercenaire_id = p_mercenaire for update;
  if not found or not _user_radie(r.user_id) then
    raise exception 'Ce mercenaire n''est pas en attente d''un joueur.';
  end if;
  v_retour := _user_radie_jusqua(r.user_id);
  select nom into v_nom from mercenaire where id = p_mercenaire;
  if v_retour is not null then
    -- Radiation temporaire : le mercenaire est prêté jusqu'à la fin du délai.
    update recrutement
      set origine_user_id = coalesce(origine_user_id, r.user_id),
          origine_nom = coalesce(origine_nom, r.nom_joueur),
          retour_le = v_retour, user_id = auth.uid(), nom_joueur = v_pseudo
      where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  else
    update recrutement
      set origine_user_id = null, origine_nom = null, retour_le = null,
          user_id = auth.uid(), nom_joueur = v_pseudo
      where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  end if;
  perform _journal('equipement', coalesce(v_nom, 'Un mercenaire') || ' est repris par ' || v_pseudo
    || case when v_retour is not null then ' (en attendant le retour de ' || r.nom_joueur || ').' else '.' end,
    0, jsonb_build_object('mercenaire_id', p_mercenaire, 'repris', true));
end;
$$;

-- MJ : renvoi définitif d'un mercenaire en attente d'un joueur radié définitivement. Repart de zéro.
create function mercenaire_renvoi_definitif(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  r recrutement%rowtype;
  l record;
  v_nom text;
  v_sac uuid;
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  perform _verrou_partie();
  select * into r from recrutement
    where session_id = ctx_session() and mercenaire_id = p_mercenaire for update;
  if not found or not _user_radie(r.user_id) or _user_radie_jusqua(r.user_id) is not null then
    raise exception 'Seul un mercenaire en attente d''un joueur radié définitivement peut être renvoyé ainsi.';
  end if;
  select nom into v_nom from mercenaire where id = p_mercenaire;
  -- Équipement porté et sac à dos : rendus à l'arsenal (comme au cimetière).
  for l in select objet_id, gemmes from mercenaire_equipement
           where mercenaire_id = p_mercenaire and session_id = ctx_session() loop
    perform _arsenal_ajouter(l.objet_id, 1, l.gemmes);
  end loop;
  delete from mercenaire_equipement where mercenaire_id = p_mercenaire and session_id = ctx_session();
  v_sac := _sac_dos_id(p_mercenaire);
  for l in select objet_id, quantite, gemmes from ligne_inventaire
           where inventaire_id = v_sac and quantite > 0 loop
    perform _arsenal_ajouter(l.objet_id, l.quantite, l.gemmes);
  end loop;
  delete from ligne_inventaire where inventaire_id = v_sac;
  -- Le recrutement disparaît : lit, entraînement, infirmerie et quête sont quittés (déclencheurs existants).
  delete from recrutement where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  update mercenaire_etat
    set veterance = 1, sante_actuelle = null, energie_actuelle = null,
        attaque = null, defense = null, esprit = null,
        etat = null, etat_niveau = 1, etat_rounds = 0, etat_efface = null, etat_decremente = false,
        inconscient_rounds = null, inconscient_dec = false, mort_champ = false,
        humain_bonus_utilise = false, equipement_base_donne = false
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  perform _journal('equipement', coalesce(v_nom, 'Un mercenaire') || ' est renvoyé définitivement : il repart de zéro (vétérance 1, équipement de base au prochain recrutement), son équipement est rendu à l''arsenal.',
    0, jsonb_build_object('mercenaire_id', p_mercenaire, 'renvoi_definitif', true));
end;
$$;

grant create on schema public to fortress_fn;
alter function radiations_etat() owner to fortress_fn;
alter function mercenaire_reprendre(uuid) owner to fortress_fn;
alter function mercenaire_renvoi_definitif(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _user_radie(uuid), _user_radie_jusqua(uuid), session_pseudo_definir(text),
  session_membres_liste(uuid), session_radier(uuid, uuid, boolean), session_reintegrer(uuid, uuid),
  session_rejoindre(text), radiations_etat(), mercenaire_reprendre(uuid), mercenaire_renvoi_definitif(uuid)
  from public;
grant execute on function _user_radie(uuid), _user_radie_jusqua(uuid) to authenticated, fortress_fn;
grant execute on function session_pseudo_definir(text), session_membres_liste(uuid),
  session_radier(uuid, uuid, boolean), session_reintegrer(uuid, uuid), session_rejoindre(text),
  radiations_etat(), mercenaire_reprendre(uuid), mercenaire_renvoi_definitif(uuid) to authenticated;
