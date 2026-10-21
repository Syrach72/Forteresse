-- « Lancer la quête » (Bruno, 2026-10-21). Le MJ lance la quête en cours (confirmation côté interface) : tant qu'elle n'est
-- ni réussie ni échouée, les joueurs ne peuvent plus retirer leurs mercenaires de la quête, ni les renvoyer, ni changer
-- leur lit (aucune interaction avec la forteresse). Sur une quête de plusieurs instances, les joueurs peuvent AJOUTER des
-- mercenaires pendant qu'elle est lancée, jamais retirer ceux déjà présents. Le MJ garde la main (corrections).
-- Le drapeau retombe tout seul quand la quête n'est plus en cours (échec, dernière réussite, annulation du choix) ;
-- une réussite intermédiaire d'une quête à plusieurs instances la laisse lancée.

alter table quete_etat add column lancee boolean not null default false;

create function _quete_lancee_efface()
returns trigger
language plpgsql
as $$
begin
  if new.en_cours is not true then
    new.lancee := false;
  end if;
  return new;
end;
$$;
create trigger quete_etat_lancee_efface
  before update of en_cours on quete_etat
  for each row execute function _quete_lancee_efface();

create function quete_lancer()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  e quete_etat%rowtype;
begin
  if not is_admin() then
    raise exception 'Réservé au MJ.';
  end if;
  perform _verrou_partie();
  select * into e from quete_etat where en_cours for update;
  if not found then
    raise exception 'Aucune quête n''est en cours.';
  end if;
  if e.lancee then
    raise exception 'Cette quête est déjà lancée.';
  end if;
  if not exists (select 1 from quete_mercenaire where quete_id = e.quete_id) then
    raise exception 'Engagez au moins un mercenaire avant de lancer la quête.';
  end if;
  update quete_etat set lancee = true where quete_id = e.quete_id;
end;
$$;

-- Fonction interne : refuse l'action d'un joueur sur un mercenaire d'une quête lancée.
create function _refuser_si_quete_lancee(p_mercenaire uuid, p_session uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not is_admin() and exists (
    select 1 from quete_mercenaire qm
    join quete_etat qe on qe.quete_id = qm.quete_id and qe.session_id = qm.session_id
    where qm.mercenaire_id = p_mercenaire and qm.session_id = p_session and qe.lancee
  ) then
    raise exception 'La quête est lancée : ce mercenaire est absent de la forteresse jusqu''à la réussite ou l''échec de la quête.';
  end if;
end;
$$;

-- Renvoi (suppression du recrutement) et changement de lit refusés pour un mercenaire d'une quête lancée.
create function _recrutement_pas_en_quete_lancee()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform _refuser_si_quete_lancee(old.mercenaire_id, old.session_id);
    return old;
  end if;
  if new.lit is distinct from old.lit then
    perform _refuser_si_quete_lancee(old.mercenaire_id, old.session_id);
  end if;
  return new;
end;
$$;
create trigger recrutement_pas_en_quete_lancee
  before delete or update of lit on recrutement
  for each row execute function _recrutement_pas_en_quete_lancee();

create or replace function quete_retirer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  perform _verrou_partie();
  if not exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    return;
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Seul son recruteur peut retirer ce mercenaire de la quête.';
  end if;
  perform _refuser_si_quete_lancee(p_mercenaire, ctx_session());
  delete from quete_mercenaire where mercenaire_id = p_mercenaire;
end;
$$;

create or replace function quete_annuler_choix()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_lancee boolean;
begin
  perform _verrou_partie();
  select quete_id, lancee into v_id, v_lancee from quete_etat where en_cours;
  if v_id is null then
    return;
  end if;
  if v_lancee and not is_admin() then
    raise exception 'La quête est lancée : seul le MJ peut l''interrompre.';
  end if;
  delete from quete_mercenaire where quete_id = v_id;
  update quete_etat set en_cours = false, instances_restantes = null where quete_id = v_id;
end;
$$;

create or replace function quete_engager(p_position integer, p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_quete uuid;
  v_lancee boolean;
  v_instances integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  perform _verrou_partie();
  select quete_id, lancee into v_quete, v_lancee from quete_etat where en_cours;
  if v_quete is null then
    raise exception 'Choisissez d''abord la quête.';
  end if;
  if v_lancee and not is_admin() then
    select instances_requises into v_instances from quete where id = v_quete;
    if coalesce(v_instances, 1) <= 1 then
      raise exception 'La quête est lancée : plus aucun mercenaire ne peut la rejoindre.';
    end if;
  end if;
  if p_position is null or p_position < 0 or p_position > 5 then
    raise exception 'Cet emplacement n''existe pas.';
  end if;
  if not exists (select 1 from recrutement where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire n''est pas au dortoir.';
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recruté par vous.';
  end if;
  if exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est déjà engagé dans une quête.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est à l''entraînement : renvoyez-le d''abord au dortoir.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est à l''infirmerie.';
  end if;
  insert into quete_mercenaire (quete_id, position, mercenaire_id)
    values (v_quete, p_position, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Cet emplacement vient d''être pris.';
end;
$$;

grant create on schema public to fortress_fn;
alter function quete_lancer() owner to fortress_fn;
alter function _refuser_si_quete_lancee(uuid, uuid) owner to fortress_fn;
alter function _recrutement_pas_en_quete_lancee() owner to fortress_fn;
alter function quete_retirer(uuid) owner to fortress_fn;
alter function quete_annuler_choix() owner to fortress_fn;
alter function quete_engager(integer, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function quete_lancer() from public, anon;
grant execute on function quete_lancer() to authenticated;
revoke all on function _refuser_si_quete_lancee(uuid, uuid) from public, anon, authenticated;
revoke all on function _recrutement_pas_en_quete_lancee() from public, anon, authenticated;
