-- Prix de deblocage des lits du dortoir (regle de Bruno). Les 6 premiers lits
-- sont debloques au depart ; les 12 autres se debloquent DANS L'ORDRE contre
-- des pieces d'or de la tresorerie commune :
--   lits 7 a 9   : 100 Po chacun
--   lits 10 a 12 : 150 Po chacun
--   lits 13 a 15 : 200 Po chacun
--   lits 16 a 18 : 300 Po chacun
-- Remplace dortoir_debloquer_place() (20260921140000), qui ne permettait qu'un
-- seul deblocage (7e lit a 100 Po). Meme grille cote application
-- (prixLitDortoir, src/dormitory.js).

create or replace function dortoir_debloquer_place()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_places integer;
  v_or integer;
  v_prix integer;
begin
  v_or := _verrou_partie();
  select places into v_places from dortoir_reglage;
  if v_places >= 18 then
    raise exception 'Tous les emplacements du dortoir sont déjà débloqués.';
  end if;
  -- Prix du prochain lit (numero v_places + 1) selon son rang.
  v_prix := case
    when v_places < 9 then 100
    when v_places < 12 then 150
    when v_places < 15 then 200
    else 300
  end;
  if v_or < v_prix then
    raise exception 'Trésorerie insuffisante.';
  end if;
  update dortoir_reglage
    set places = places + 1
    where places < 18
    returning places into v_places;
  update partie_etat set or_compagnie = or_compagnie - v_prix where id;
  perform _journal('depense',
    'Emplacement de dortoir débloqué : −' || v_prix || ' Po.', -v_prix, null);
  return v_places;
end;
$$;
