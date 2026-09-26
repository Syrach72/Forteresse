-- Santé actuelle et énergie actuelle d'un mercenaire (Bruno, 2026-09-26).
--
-- Les maxima (santé max, énergie max) sont des champs de la fiche du catalogue (colonnes
-- `sante` et `mana` de `mercenaire`, renommées à l'écran). Les valeurs ACTUELLES évoluent en
-- jeu : elles sont propres à la session (table mercenaire_etat, comme la vétérance) et le
-- joueur qui a recruté le mercenaire (ou le MJ) les modifie. Vide = pas encore modifiée : la
-- fiche affiche alors le maximum.

alter table mercenaire_etat
  add column energie_actuelle integer check (energie_actuelle >= 0),
  add column sante_actuelle integer check (sante_actuelle >= 0);

create function mercenaire_definir_actuel(p_mercenaire uuid, p_energie integer, p_sante integer)
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
  if (p_energie is not null and (p_energie < 0 or p_energie > 9999))
     or (p_sante is not null and (p_sante < 0 or p_sante > 9999)) then
    raise exception 'Saisissez des entiers de 0 à 9999.';
  end if;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance, energie_actuelle, sante_actuelle)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire), p_energie, p_sante)
    on conflict (session_id, mercenaire_id) do update
      set energie_actuelle = excluded.energie_actuelle, sante_actuelle = excluded.sante_actuelle;
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_definir_actuel(uuid, integer, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_definir_actuel(uuid, integer, integer) from public;
grant execute on function mercenaire_definir_actuel(uuid, integer, integer) to authenticated;
