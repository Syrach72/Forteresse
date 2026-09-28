-- Correction de 20260928100000 : la migration précédente écrivait Puissance/Vélocité/Mental
-- directement sur la fiche catalogue partagée `mercenaire` (colonnes attaque/defense/esprit), en
-- supposant à tort une colonne session_id qui n'existe plus dessus depuis 20260925230000
-- (catalogue redevenu commun à toutes les sessions). Un joueur qui aurait modifié sa fiche aurait
-- donc changé la même valeur pour toutes les sessions/tables utilisant ce mercenaire.
--
-- Puissance/Vélocité/Mental deviennent un état PAR SESSION, exactement comme la vétérance (même
-- mécanisme : mercenaire_etat, repli sur la fiche de base hors session via coalesce).

alter table mercenaire_etat
  add column attaque integer check (attaque is null or attaque between 0 and 9),
  add column defense integer check (defense is null or defense between 0 and 9),
  add column esprit integer check (esprit is null or esprit between 0 and 9);

-- Puissance/Vélocité/Mental effectifs dans la session courante : la fiche (mercenaire_etat) si
-- modifiée cette session, sinon la fiche de base (mercenaire). Même repli que _vet().
create function _puissance(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.attaque from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.attaque from mercenaire m where m.id = p_mercenaire),
    0);
$$;
revoke all on function _puissance(uuid) from public;
grant execute on function _puissance(uuid) to authenticated, fortress_fn;

create function _velocite(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.defense from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.defense from mercenaire m where m.id = p_mercenaire),
    0);
$$;
revoke all on function _velocite(uuid) from public;
grant execute on function _velocite(uuid) to authenticated, fortress_fn;

create function _mental(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select e.esprit from mercenaire_etat e
      where e.mercenaire_id = p_mercenaire and e.session_id = ctx_session()),
    (select m.esprit from mercenaire m where m.id = p_mercenaire),
    0);
$$;
revoke all on function _mental(uuid) from public;
grant execute on function _mental(uuid) to authenticated, fortress_fn;

-- Santé max = 3 + 2 × Puissance de la session courante (plus le repli mercenaire.attaque brut de
-- 20260928100000, qui ignorait un éventuel override de session).
create or replace function _sante_max(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select 3 + 2 * _puissance(p_mercenaire);
$$;

-- Le joueur qui a recruté le mercenaire (ou le MJ) règle Puissance, Vélocité et Mental dans
-- mercenaire_etat (jamais sur la fiche catalogue partagée).
create or replace function mercenaire_definir_caracteristiques(
  p_mercenaire uuid, p_puissance integer, p_velocite integer, p_mental integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
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
