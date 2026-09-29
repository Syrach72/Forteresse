-- Badge F d'une arme ou d'un bouclier équipé (Bruno, 2026-09-29) : quand F est rouge sur la fiche, il
-- s'affiche aussi comme badge informatif sur l'icône de l'objet, jusqu'à ce qu'il redevienne blanc.
-- L'état est donc enregistré (par session, sur la ligne d'équipement) et partagé.
alter table mercenaire_equipement add column badge_f boolean not null default false;

create function equipement_definir_badge_f(p_mercenaire uuid, p_emplacement text, p_position integer, p_actif boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  update mercenaire_equipement set badge_f = coalesce(p_actif, false)
    where session_id = ctx_session() and mercenaire_id = p_mercenaire
      and emplacement = p_emplacement and position = p_position;
  if not found then
    raise exception 'Rien n''est équipé à cet emplacement.';
  end if;
end;
$$;

grant create on schema public to fortress_fn;
alter function equipement_definir_badge_f(uuid, text, integer, boolean) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function equipement_definir_badge_f(uuid, text, integer, boolean) from public;
grant execute on function equipement_definir_badge_f(uuid, text, integer, boolean) to authenticated;
