-- Points de caractéristique à la montée de vétérance (Bruno, 2026-10-06) : à chaque niveau de vétérance gagné,
-- le joueur qui contrôle le mercenaire ajoute 1 point à la caractéristique de son choix (Puissance, Vélocité
-- ou Mental, plafond 9). Il ne peut plus modifier ses caractéristiques autrement : seul le MJ garde la saisie
-- manuelle.
--
-- * mercenaire_etat.points_carac : points encore à dépenser (propre à la session).
-- * Un déclencheur crédite les points à chaque hausse de vétérance, quelle qu'en soit l'origine (entraînement,
--   quête, correction du MJ) ; une baisse (annulation d'un +1 Instance) retire des points, sans descendre sous 0.
-- * mercenaire_depenser_point : le joueur (ou le MJ pour lui) dépense 1 point, définitivement.
-- * mercenaire_definir_caracteristiques : désormais réservée au MJ.

alter table mercenaire_etat
  add column points_carac integer not null default 0 check (points_carac >= 0);

create function _mercenaire_etat_points()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_avant integer;
begin
  if tg_op = 'INSERT' then
    -- Première ligne d'état de la session : on compare à la vétérance de la fiche du catalogue.
    select m.veterance into v_avant from mercenaire m where m.id = new.mercenaire_id;
  else
    v_avant := old.veterance;
  end if;
  if v_avant is not null and new.veterance is distinct from v_avant then
    new.points_carac := greatest(0, coalesce(case when tg_op = 'INSERT' then 0 else old.points_carac end, 0)
                                    + (new.veterance - v_avant));
  end if;
  return new;
end;
$$;

create trigger mercenaire_etat_points
  before insert or update of veterance on mercenaire_etat
  for each row execute function _mercenaire_etat_points();

create function mercenaire_depenser_point(p_mercenaire uuid, p_carac text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_points integer;
  v_att integer;
  v_def integer;
  v_esp integer;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_carac not in ('puissance', 'velocite', 'mental') then
    raise exception 'Choisissez la Puissance, la Vélocité ou le Mental.';
  end if;
  select e.points_carac, coalesce(e.attaque, m.attaque, 0), coalesce(e.defense, m.defense, 0), coalesce(e.esprit, m.esprit, 0)
    into v_points, v_att, v_def, v_esp
    from mercenaire_etat e join mercenaire m on m.id = e.mercenaire_id
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire
    for update of e;
  if not found or v_points <= 0 then
    raise exception 'Aucun point de caractéristique à dépenser.';
  end if;
  if (p_carac = 'puissance' and v_att >= 9) or (p_carac = 'velocite' and v_def >= 9) or (p_carac = 'mental' and v_esp >= 9) then
    raise exception 'Cette caractéristique est déjà au maximum (9) : choisissez-en une autre.';
  end if;
  update mercenaire_etat
    set attaque = v_att + (p_carac = 'puissance')::int,
        defense = v_def + (p_carac = 'velocite')::int,
        esprit = v_esp + (p_carac = 'mental')::int,
        points_carac = points_carac - 1
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
end;
$$;

-- Saisie manuelle des caractéristiques : le MJ seul.
create or replace function mercenaire_definir_caracteristiques(
  p_mercenaire uuid, p_puissance integer, p_velocite integer, p_mental integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Les caractéristiques ne se modifient que par les points gagnés à chaque niveau de vétérance.';
  end if;
  perform _verrou_partie();
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  if (p_puissance is not null and (p_puissance < 0 or p_puissance > 9))
     or (p_velocite is not null and (p_velocite < 0 or p_velocite > 9))
     or (p_mental is not null and (p_mental < 0 or p_mental > 9)) then
    raise exception 'Chaque caractéristique est un entier de 0 à 9.';
  end if;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance, attaque, defense, esprit)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire), p_puissance, p_velocite, p_mental)
    on conflict (session_id, mercenaire_id) do update
      set attaque = excluded.attaque, defense = excluded.defense, esprit = excluded.esprit;
end;
$$;

grant create on schema public to fortress_fn;
alter function _mercenaire_etat_points() owner to fortress_fn;
alter function mercenaire_depenser_point(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _mercenaire_etat_points() from public;
revoke all on function mercenaire_depenser_point(uuid, text) from public;
grant execute on function mercenaire_depenser_point(uuid, text) to authenticated;
