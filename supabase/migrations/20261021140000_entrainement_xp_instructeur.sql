-- XP de l'instructeur (Bruno, 2026-10-21) : à chaque +1 Instance, l'instructeur gagne une fraction de l'XP gagnée par chacun de ses élèves :
-- 1/2 pour le premier élève, 1/3 pour le deuxième, 1/4 pour le troisième (arrondi à l'inférieur, élèves pris par position).
-- Une ligne « instructeur » est ajoutée au récapitulatif ; entrainement_annuler_instance (inchangée) la reprend comme celle d'un élève.
-- Reste de la fonction : 20261011110000_missions_evenements.sql.

create or replace function entrainement_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_instr uuid;
  v_vinstr integer;
  v_g integer;
  r record;
  v_avant integer;
  v_apres integer;
  v_gradue boolean;
  v_pal integer;
  v_n integer;
  v_gain integer;
  v_res jsonb;
  v_termine boolean;
  v_xp_avant integer;
  v_xp_apres integer;
  v_gains jsonb := '[]'::jsonb;
  v_k integer;
  v_ig integer;
  v_ires jsonb;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  for v_g in 1..2 loop
    select p.mercenaire_id into v_instr
      from entrainement_place p where p.role = 'instructeur' and p.groupe = v_g;
    if not found then
      continue;
    end if;
    v_vinstr := _vet(v_instr);
    v_k := 0;
    v_ig := 0;
    for r in
      select p.position, p.mercenaire_id as mid, _vet(p.mercenaire_id) as vet
      from entrainement_place p
      where p.role = 'eleve' and p.groupe = v_g
      order by p.position
      for update of p
    loop
      v_k := v_k + 1;
      v_avant := r.vet;
      select e.xp into v_xp_avant from mercenaire_etat e
        where e.session_id = ctx_session() and e.mercenaire_id = r.mid;
      v_xp_avant := coalesce(v_xp_avant, 0);
      v_pal := _xp_palier(v_avant);
      v_n := 0;
      v_termine := false;
      v_gain := 0;
      if v_avant >= v_vinstr or v_pal is null then
        -- Déjà au niveau de l'instructeur (ou au niveau maximum) : il retourne à la caserne.
        v_apres := v_avant;
        v_xp_apres := v_xp_avant;
        v_gradue := true;
      else
        -- Une part du palier par instance : 1 instance par niveau à 3 niveaux d'écart ou plus, 2 à 2 niveaux,
        -- 3 à 1 niveau (arrondi au supérieur pour ne jamais ajouter d'instance).
        v_n := _xp_formation_instances(v_vinstr - v_avant);
        v_gain := ceil(v_pal::numeric / v_n)::integer;
        v_res := _xp_ajouter(r.mid, v_gain);
        -- L'instructeur gagne 1/2 (1er élève), 1/3 (2e) ou 1/4 (3e) de l'XP de cet élève.
        v_ig := v_ig + floor(v_gain::numeric / (v_k + 1))::integer;
        v_apres := (v_res ->> 'veterance_apres')::integer;
        v_xp_apres := (v_res ->> 'xp_apres')::integer;
        v_gradue := v_apres >= v_vinstr;
        v_termine := v_gradue;
      end if;
      if v_termine then
        -- Mission « entraînement terminé » : au profit du recruteur de l'élève.
        perform _mission_evenement('entrainement_termine',
          (select rc.user_id from recrutement rc where rc.mercenaire_id = r.mid));
      end if;
      if v_gradue then
        delete from entrainement_place where mercenaire_id = r.mid;
      end if;
      v_gains := v_gains || jsonb_build_object(
        'mercenaire_id', r.mid, 'groupe', v_g, 'position', r.position,
        'de', v_avant, 'a', v_apres, 'gradue', v_gradue,
        'xp_gain', v_gain, 'xp_avant', v_xp_avant, 'xp_apres', v_xp_apres, 'instances', v_n,
        'termine', v_termine);
    end loop;
    if v_ig > 0 then
      v_ires := _xp_ajouter(v_instr, v_ig);
      v_gains := v_gains || jsonb_build_object(
        'mercenaire_id', v_instr, 'groupe', v_g, 'position', 0,
        'de', (v_ires ->> 'veterance_avant')::integer, 'a', (v_ires ->> 'veterance_apres')::integer,
        'gradue', false, 'termine', false, 'instructeur', true,
        'xp_gain', v_ig, 'xp_avant', (v_ires ->> 'xp_avant')::integer, 'xp_apres', (v_ires ->> 'xp_apres')::integer,
        'instances', 0);
    end if;
  end loop;
  return v_gains;
end;
$$;

grant create on schema public to fortress_fn;
alter function entrainement_instance() owner to fortress_fn;
revoke create on schema public from fortress_fn;
