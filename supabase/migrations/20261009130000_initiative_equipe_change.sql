-- Initiative : l'équipe engagée change pendant la quête (Bruno, 2026-10-09).
--  * Un mercenaire retiré de la quête : son jet disparaît et l'ordre (1 = premier) est redistribué sur ceux qui restent.
--  * Un mercenaire ajouté : l'ordre est suspendu (plus de rang) jusqu'à ce qu'il ait lancé son propre d20 ; quand il a
--    lancé, l'ordre est recalculé en l'incluant. Si son total égale celui d'un groupe déjà départagé, ce groupe relance.
-- Toute suppression/mise à jour a une clause WHERE explicite (pg_safeupdate).

create or replace function _initiative_resoudre()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_quete uuid;
  v_attendus integer;
  v_faits integer;
  v_tours integer := 0;
begin
  select quete_id into v_quete from initiative_etat where session_id = ctx_session();
  if v_quete is null then
    return;
  end if;
  select (select count(*) from quete_mercenaire where quete_id = v_quete and session_id = ctx_session())
       + (select count(*) from creature_quete where quete_id = v_quete and session_id = ctx_session())
    into v_attendus;
  select count(*) into v_faits from initiative where session_id = ctx_session() and quete_id = v_quete;
  if v_attendus = 0 or v_faits < v_attendus
     or exists (select 1 from initiative where session_id = ctx_session() and rang is not null) then
    return;
  end if;
  -- Groupe déjà départagé qui accueille un nouvel arrivant (même total, relances encore vides) : tout le groupe relance.
  update initiative i set departage = '{}'
    where i.session_id = ctx_session() and i.departage <> '{}'
      and exists (select 1 from initiative j
                  where j.session_id = i.session_id and j.id <> i.id and j.total = i.total and j.departage = '{}');
  -- Ex æquo (même total et même suite de relances) : tous relancent, jusqu'à ce que plus personne ne soit à égalité.
  loop
    update initiative i
      set departage = i.departage || (1 + floor(random() * 20))::smallint
      where i.session_id = ctx_session()
        and exists (select 1 from initiative j
                    where j.session_id = i.session_id and j.id <> i.id
                      and j.total = i.total and j.departage = i.departage);
    exit when not found;
    v_tours := v_tours + 1;
    exit when v_tours >= 100;
  end loop;
  update initiative i set rang = r.rang
    from (select id, (row_number() over (order by total desc, departage desc))::smallint as rang
            from initiative where session_id = ctx_session()) r
    where i.id = r.id and i.session_id = ctx_session();
end;
$$;

create function _initiative_equipe()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_session uuid;
  v_quete uuid;
  v_merc uuid;
begin
  if tg_op = 'DELETE' then
    v_session := old.session_id; v_quete := old.quete_id; v_merc := old.mercenaire_id;
  else
    v_session := new.session_id; v_quete := new.quete_id;
  end if;
  if not exists (select 1 from initiative_etat where session_id = v_session and quete_id = v_quete) then
    return null;
  end if;
  if tg_op = 'DELETE' then
    delete from initiative where session_id = v_session and mercenaire_id = v_merc;
  end if;
  -- Les rangs sont remis en cause ; ils sont recalculés tout de suite si tout le monde a déjà lancé.
  update initiative set rang = null where session_id = v_session and rang is not null;
  perform _initiative_resoudre();
  return null;
end;
$$;

create trigger quete_mercenaire_initiative_ajout
  after insert on quete_mercenaire
  for each row execute function _initiative_equipe();
create trigger quete_mercenaire_initiative_retrait
  after delete on quete_mercenaire
  for each row execute function _initiative_equipe();

grant create on schema public to fortress_fn;
alter function _initiative_equipe() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _initiative_equipe() from public;
