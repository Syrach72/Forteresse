-- Inconscient : mort définitive après 3 rounds (Bruno, 2026-10-05). Quand un mercenaire en quête passe à
-- l'état Inconscient, un compte à rebours de 3 rounds démarre ; chaque clic sur « Rd » en retire 1 (annuler
-- le Rd le rend). À 0 le mercenaire est « mort sur le champ de bataille » (mort_champ) : grisé avec la
-- pierre tombale, mais encore recruté, car un autre personnage peut le ramener à la vie (il suffit de
-- retirer l'état Inconscient). Il n'est envoyé au cimetière qu'à la fin de l'instance (+1 Instance).
--  * mercenaire_etat.inconscient_rounds : rounds restants (null hors Inconscient) ; inconscient_dec : a été
--    décrémenté par le dernier Rd (pour pouvoir l'annuler) ; mort_champ : compte à rebours épuisé.
--  * mercenaire_definir_etat : passer à Inconscient lance le compte à 3 (sans le remettre à 3 si l'état
--    est déjà Inconscient) ; tout autre état, ou l'effacement, le supprime et ranime le mercenaire.
--  * _creatures_round (déclencheur du Rd) : décompte et annulation.
--  * cimetiere_instance : envoie aussi au cimetière les mercenaires mort_champ (en plus des 0 PV) ;
--    cimetiere_annuler_instance leur rend leur drapeau.
--  Quitter la quête efface l'état mais PAS mort_champ : un mercenaire mort sur le champ de bataille ne
--  peut pas être « sauvé » en le retirant de la quête.

alter table mercenaire_etat
  add column inconscient_rounds smallint check (inconscient_rounds is null or inconscient_rounds between 0 and 3),
  add column inconscient_dec boolean not null default false,
  add column mort_champ boolean not null default false;

create or replace function mercenaire_definir_etat(
  p_mercenaire uuid, p_etat text, p_niveau integer default 1, p_rounds integer default 0)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_prev text;
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  select etat into v_prev from mercenaire_etat
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
  if p_etat is null then
    update mercenaire_etat
      set etat = null, etat_niveau = 1, etat_rounds = 0, etat_efface = null, etat_decremente = false,
          inconscient_rounds = null, inconscient_dec = false, mort_champ = false
      where session_id = ctx_session() and mercenaire_id = p_mercenaire;
    return;
  end if;
  if p_etat not in ('abri_partiel', 'abri_total', 'affaibli', 'agrippe', 'assourdi', 'aveugle', 'charme', 'confus',
                    'desoriente', 'effraye', 'empoisonne', 'endormi', 'enrage', 'entrave', 'epuise', 'etourdi',
                    'fascine', 'fatigue', 'immobilise', 'inconscient', 'lenteur', 'muet', 'nauseeux', 'paralyse',
                    'petrifie', 'possede', 'suffocation') then
    raise exception 'État inconnu.';
  end if;
  if p_niveau is null or p_niveau < 1 or p_niveau > 3 or (p_etat <> 'epuise' and p_niveau <> 1) then
    raise exception 'Niveau d''état invalide.';
  end if;
  if p_rounds is null or p_rounds < 0 or p_rounds > 9 then
    raise exception 'La durée est un nombre de rounds de 0 à 9.';
  end if;
  if not exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire n''est pas engagé dans une quête.';
  end if;
  insert into mercenaire_etat (session_id, mercenaire_id, veterance)
    values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
    on conflict (session_id, mercenaire_id) do nothing;
  update mercenaire_etat
    set etat = p_etat, etat_niveau = p_niveau, etat_rounds = p_rounds, etat_efface = null, etat_decremente = false,
        inconscient_rounds = case when p_etat <> 'inconscient' then null
                                  when v_prev = 'inconscient' then inconscient_rounds
                                  else 3 end,
        inconscient_dec = case when p_etat = 'inconscient' and v_prev = 'inconscient' then inconscient_dec else false end,
        mort_champ = case when p_etat = 'inconscient' and v_prev = 'inconscient' then mort_champ else false end
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
end;
$$;

-- Rd : même déclencheur que les états (20261002110000), avec le compte à rebours de l'Inconscient.
create or replace function _creatures_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = old.round_courant + 1 then
    update creature_quete set gain_round = false, etat_decremente = false, etat_efface = null
      where session_id = new.session_id;
    update creature_quete c
      set energie_actuelle = c.energie_actuelle + 1, gain_round = true
      from creature k
      where k.id = c.creature_id and c.session_id = new.session_id
        and c.energie_actuelle is not null and c.energie_actuelle < k.energie_max;
    update creature_quete
      set etat_rounds = etat_rounds - 1, etat_decremente = true,
          etat_efface = case when etat_rounds = 1 then etat end,
          etat = case when etat_rounds = 1 then null else etat end
      where session_id = new.session_id and etat_rounds > 0;
    update mercenaire_etat set etat_decremente = false, etat_efface = null
      where session_id = new.session_id and (etat_decremente or etat_efface is not null);
    -- Inconscient : un round de moins ; à 0 le mercenaire est mort sur le champ de bataille. Avant la
    -- durée de l'état, pour qu'il soit encore Inconscient au moment du décompte.
    update mercenaire_etat set inconscient_dec = false
      where session_id = new.session_id and inconscient_dec;
    update mercenaire_etat
      set inconscient_rounds = inconscient_rounds - 1, inconscient_dec = true,
          mort_champ = (inconscient_rounds = 1)
      where session_id = new.session_id and etat = 'inconscient' and inconscient_rounds > 0;
    update mercenaire_etat
      set etat_rounds = etat_rounds - 1, etat_decremente = true,
          etat_efface = case when etat_rounds = 1 then etat end,
          etat = case when etat_rounds = 1 then null else etat end
      where session_id = new.session_id and etat_rounds > 0;
  elsif new.round_courant = old.round_courant - 1 then
    update creature_quete
      set energie_actuelle = greatest(energie_actuelle - 1, 0), gain_round = false
      where session_id = new.session_id and gain_round and energie_actuelle is not null;
    update creature_quete
      set etat_rounds = least(etat_rounds + 1, 9), etat_decremente = false,
          etat = coalesce(etat, etat_efface), etat_efface = null
      where session_id = new.session_id and etat_decremente;
    update mercenaire_etat
      set etat_rounds = least(etat_rounds + 1, 9), etat_decremente = false,
          etat = coalesce(etat, etat_efface), etat_efface = null
      where session_id = new.session_id and etat_decremente;
    update mercenaire_etat
      set inconscient_rounds = inconscient_rounds + 1, inconscient_dec = false, mort_champ = false
      where session_id = new.session_id and inconscient_dec;
  end if;
  return new;
end;
$$;

-- Fin d'instance : au cimetière, les recrutés à 0 PV ET ceux morts sur le champ de bataille (mort_champ).
create or replace function cimetiere_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  l record;
  v_nom text;
  v_sac uuid;
  v_eq jsonb;
  v_contenu jsonb;
  v_gains jsonb := '[]'::jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  for r in
    select rec.mercenaire_id, rec.user_id, rec.nom_joueur, e.mort_champ
    from recrutement rec
      join mercenaire_etat e on e.mercenaire_id = rec.mercenaire_id and e.session_id = ctx_session()
    where rec.session_id = ctx_session() and (e.sante_actuelle = 0 or e.mort_champ)
    order by rec.lit
  loop
    select nom into v_nom from mercenaire where id = r.mercenaire_id;
    select coalesce(jsonb_agg(jsonb_build_object(
        'emplacement', emplacement, 'position', position, 'objet_id', objet_id, 'gemmes', gemmes)), '[]'::jsonb)
      into v_eq from mercenaire_equipement where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    v_sac := _sac_dos_id(r.mercenaire_id);
    select coalesce(jsonb_agg(jsonb_build_object(
        'objet_id', objet_id, 'quantite', quantite, 'gemmes', gemmes)), '[]'::jsonb)
      into v_contenu from ligne_inventaire where inventaire_id = v_sac and quantite > 0;
    -- Tout l'équipement retourne à l'arsenal.
    for l in select objet_id, gemmes from mercenaire_equipement
             where mercenaire_id = r.mercenaire_id and session_id = ctx_session() loop
      perform _arsenal_ajouter(l.objet_id, 1, l.gemmes);
    end loop;
    delete from mercenaire_equipement where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    for l in select objet_id, quantite, gemmes from ligne_inventaire
             where inventaire_id = v_sac and quantite > 0 loop
      perform _arsenal_ajouter(l.objet_id, l.quantite, l.gemmes);
    end loop;
    delete from ligne_inventaire where inventaire_id = v_sac;
    insert into cimetiere (mercenaire_id, user_id, nom_joueur) values (r.mercenaire_id, r.user_id, r.nom_joueur);
    -- Le lit est libéré ; entraînement, infirmerie et quête sont quittés (déclencheurs du recrutement).
    delete from recrutement where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    update mercenaire_etat
      set mort_champ = false, inconscient_rounds = null, inconscient_dec = false
      where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    perform _journal('equipement', coalesce(v_nom, 'Un mercenaire') || case when r.mort_champ
        then ' est mort sur le champ de bataille (Inconscient) : il repose au cimetière, son équipement est rendu à l''arsenal.'
        else ' est tombé à 0 PV : il repose au cimetière, son équipement est rendu à l''arsenal.' end, 0,
      jsonb_build_object('mercenaire_id', r.mercenaire_id, 'cimetiere', true));
    v_gains := v_gains || jsonb_build_object(
      'mercenaire_id', r.mercenaire_id, 'user_id', r.user_id, 'nom_joueur', r.nom_joueur,
      'equipement', v_eq, 'sac', v_contenu, 'mort_champ', coalesce(r.mort_champ, false));
  end loop;
  return v_gains;
end;
$$;

create or replace function cimetiere_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g jsonb;
  x jsonb;
  v_id uuid;
  v_sac uuid;
  v_gemmes uuid[];
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  for g in select * from jsonb_array_elements(coalesce(p_gains, '[]'::jsonb)) loop
    v_id := (g ->> 'mercenaire_id')::uuid;
    if not exists (select 1 from cimetiere where mercenaire_id = v_id and session_id = ctx_session()) then
      continue;
    end if;
    begin
      insert into recrutement (mercenaire_id, user_id, nom_joueur)
        values (v_id, (g ->> 'user_id')::uuid, g ->> 'nom_joueur');
    exception when others then
      continue;
    end;
    delete from cimetiere where mercenaire_id = v_id and session_id = ctx_session();
    if coalesce((g ->> 'mort_champ')::boolean, false) then
      update mercenaire_etat set mort_champ = true
        where mercenaire_id = v_id and session_id = ctx_session();
    end if;
    for x in select * from jsonb_array_elements(coalesce(g -> 'equipement', '[]'::jsonb)) loop
      v_gemmes := case when jsonb_typeof(x -> 'gemmes') = 'array'
        then array(select jsonb_array_elements_text(x -> 'gemmes')::uuid) else null end;
      if _arsenal_quantite((x ->> 'objet_id')::uuid, v_gemmes) >= 1 then
        perform _arsenal_retirer((x ->> 'objet_id')::uuid, 1, v_gemmes);
        insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id, gemmes)
          values (v_id, x ->> 'emplacement', (x ->> 'position')::smallint, (x ->> 'objet_id')::uuid, v_gemmes)
          on conflict do nothing;
      end if;
    end loop;
    v_sac := _sac_dos_id(v_id);
    for x in select * from jsonb_array_elements(coalesce(g -> 'sac', '[]'::jsonb)) loop
      v_gemmes := case when jsonb_typeof(x -> 'gemmes') = 'array'
        then array(select jsonb_array_elements_text(x -> 'gemmes')::uuid) else null end;
      if _arsenal_quantite((x ->> 'objet_id')::uuid, v_gemmes) >= (x ->> 'quantite')::integer then
        perform _arsenal_retirer((x ->> 'objet_id')::uuid, (x ->> 'quantite')::integer, v_gemmes);
        insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
          values (v_sac, (x ->> 'objet_id')::uuid, (x ->> 'quantite')::integer, v_gemmes);
      end if;
    end loop;
  end loop;
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_definir_etat(uuid, text, integer, integer) owner to fortress_fn;
alter function _creatures_round() owner to fortress_fn;
alter function cimetiere_instance() owner to fortress_fn;
alter function cimetiere_annuler_instance(jsonb) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_definir_etat(uuid, text, integer, integer) from public;
revoke all on function _creatures_round() from public;
revoke all on function cimetiere_instance() from public;
revoke all on function cimetiere_annuler_instance(jsonb) from public;
grant execute on function mercenaire_definir_etat(uuid, text, integer, integer) to authenticated;
grant execute on function cimetiere_instance() to authenticated;
grant execute on function cimetiere_annuler_instance(jsonb) to authenticated;
