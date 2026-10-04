-- Compétence passive « Humain » (Bruno, 2026-10-04) : à son recrutement, le joueur augmente de 1 point la
-- caractéristique de son choix (Puissance, Vélocité ou Mental) du mercenaire. Une seule fois par
-- mercenaire et par session (un renvoi puis un nouveau recrutement ne redonne pas le point) : le drapeau
-- humain_bonus_utilise de mercenaire_etat le mémorise. Le point s'ajoute à la valeur de base (plafond 9,
-- comme toute saisie de caractéristique) ; le serveur vérifie la compétence (passive, ligne de vétérance
-- atteinte), le droit sur le mercenaire et le plafond.

alter table mercenaire_etat add column humain_bonus_utilise boolean not null default false;

-- Le mercenaire possède-t-il l'une de ces compétences passives (sur une ligne de vétérance atteinte) ?
create function _possede_competence(p_mercenaire uuid, p_noms text[])
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from mercenaire_competence mc
      join objet_catalogue o on o.id = mc.competence_id
    where mc.mercenaire_id = p_mercenaire
      and mc.type = 'passive'
      and mc.veterance <= _vet(p_mercenaire)
      and lower(btrim(o.nom)) = any (p_noms));
$$;
revoke all on function _possede_competence(uuid, text[]) from public;
grant execute on function _possede_competence(uuid, text[]) to authenticated, fortress_fn;

create function mercenaire_humain_bonus(p_mercenaire uuid, p_carac text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_att integer;
  v_def integer;
  v_esp integer;
  v_deja boolean;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_carac not in ('puissance', 'velocite', 'mental') then
    raise exception 'Choisissez la Puissance, la Vélocité ou le Mental.';
  end if;
  if not _possede_competence(p_mercenaire, array['humain']) then
    raise exception 'Ce mercenaire ne possède pas la compétence Humain.';
  end if;
  v_vet := _vet(p_mercenaire);
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, v_vet)
    on conflict (session_id, mercenaire_id) do nothing;
  select coalesce(e.attaque, m.attaque, 0), coalesce(e.defense, m.defense, 0), coalesce(e.esprit, m.esprit, 0),
         e.humain_bonus_utilise
    into v_att, v_def, v_esp, v_deja
    from mercenaire_etat e join mercenaire m on m.id = e.mercenaire_id
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire
    for update of e;
  if v_deja then
    raise exception 'Le bonus Humain a déjà été utilisé pour ce mercenaire.';
  end if;
  if (p_carac = 'puissance' and v_att >= 9) or (p_carac = 'velocite' and v_def >= 9) or (p_carac = 'mental' and v_esp >= 9) then
    raise exception 'Cette caractéristique est déjà au maximum (9) : choisissez-en une autre.';
  end if;
  update mercenaire_etat
    set attaque = v_att + (p_carac = 'puissance')::int,
        defense = v_def + (p_carac = 'velocite')::int,
        esprit = v_esp + (p_carac = 'mental')::int,
        humain_bonus_utilise = true
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_humain_bonus(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_humain_bonus(uuid, text) from public;
grant execute on function mercenaire_humain_bonus(uuid, text) to authenticated;
