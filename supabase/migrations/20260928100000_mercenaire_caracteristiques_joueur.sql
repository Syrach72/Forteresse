-- Puissance, Vélocité, Mental modifiables par le joueur, plafonnées à 9 (règle de Bruno,
-- 2026-09-28). Nouvelles formules des maxima, qui remplacent le calcul par la vétérance :
--   Santé max  = 3 + 2 × Puissance
--   Énergie max = 2 × Mental
-- (auparavant : Puissance/Mental × vétérance, minimum 6). Les colonnes de la base gardent
-- leurs anciens noms (attaque = Puissance, defense = Vélocité, esprit = Mental).

-- Normalise les valeurs existantes avant d'ajouter la contrainte (aucune fiche actuelle ne
-- dépasse 9, mais on ne suppose rien).
update mercenaire set attaque = least(9, attaque) where attaque > 9;
update mercenaire set defense = least(9, defense) where defense > 9;
update mercenaire set esprit = least(9, esprit) where esprit > 9;

alter table mercenaire
  add constraint mercenaire_attaque_max_check check (attaque is null or attaque between 0 and 9),
  add constraint mercenaire_defense_max_check check (defense is null or defense between 0 and 9),
  add constraint mercenaire_esprit_max_check check (esprit is null or esprit between 0 and 9);

-- Le joueur qui a recruté le mercenaire (ou le MJ) règle désormais Puissance, Vélocité et
-- Mental directement sur la fiche (même droit que mercenaire_definir_actuel).
create function mercenaire_definir_caracteristiques(
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
  update mercenaire
    set attaque = p_puissance, defense = p_velocite, esprit = p_mental
    where id = p_mercenaire and session_id = ctx_session();
end;
$$;

-- Santé max = 3 + 2 × Puissance (remplace Puissance × vétérance) : reprise par l'infirmerie
-- (_soins_instances) sans autre changement.
create or replace function _sante_max(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select 3 + 2 * coalesce(m.attaque, 0) from mercenaire m where m.id = p_mercenaire;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_definir_caracteristiques(uuid, integer, integer, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_definir_caracteristiques(uuid, integer, integer, integer) from public;
grant execute on function mercenaire_definir_caracteristiques(uuid, integer, integer, integer) to authenticated;
