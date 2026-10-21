-- Deux règles de quête (Bruno, 2026-10-21) :
-- 1. Un mercenaire mort sur le champ de bataille (Inconscient à 0 PV, compte à rebours de 3 Rd épuisé) est retiré du panneau
--    de quête et envoyé AU CIMETIÈRE sur-le-champ, au Rd qui le tue (plus à la fin de l'instance). Équipement et sac
--    retournent à l'arsenal. Le « Annuler » du Rd le rappelle (recrutement, équipement, sac, place dans la quête, Inconscient
--    à 1 Rd). Le bloc est protégé : une erreur ne doit jamais empêcher le Rd lui-même.
-- 2. Une quête lancée à plusieurs instances accepte de nouveaux mercenaires AUX INSTANCES SUIVANTES (après la première),
--    dans la limite des 6 places ; sur une seule instance, ou pendant la première, plus personne ne peut la rejoindre.
-- Reste de _creatures_round : 20261005120000_inconscient_mort_definitive.sql.

alter table cimetiere add column annulable_rd integer, add column rd_donnees jsonb;

create function _cimetiere_envoyer_morts(p_session uuid, p_round integer)
returns void
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
  v_quete uuid;
  v_position smallint;
begin
  if p_session is distinct from ctx_session() then
    return;
  end if;
  for r in
    select rec.mercenaire_id, rec.user_id, rec.nom_joueur
    from recrutement rec
      join mercenaire_etat e on e.mercenaire_id = rec.mercenaire_id and e.session_id = p_session
    where rec.session_id = p_session and e.mort_champ
    order by rec.lit
  loop
    select nom into v_nom from mercenaire where id = r.mercenaire_id;
    select quete_id, position into v_quete, v_position from quete_mercenaire
      where mercenaire_id = r.mercenaire_id and session_id = p_session;
    select coalesce(jsonb_agg(jsonb_build_object(
        'emplacement', emplacement, 'position', position, 'objet_id', objet_id, 'gemmes', gemmes)), '[]'::jsonb)
      into v_eq from mercenaire_equipement where mercenaire_id = r.mercenaire_id and session_id = p_session;
    v_sac := _sac_dos_id(r.mercenaire_id);
    select coalesce(jsonb_agg(jsonb_build_object(
        'objet_id', objet_id, 'quantite', quantite, 'gemmes', gemmes)), '[]'::jsonb)
      into v_contenu from ligne_inventaire where inventaire_id = v_sac and quantite > 0;
    for l in select objet_id, gemmes from mercenaire_equipement
             where mercenaire_id = r.mercenaire_id and session_id = p_session loop
      perform _arsenal_ajouter(l.objet_id, 1, l.gemmes);
    end loop;
    delete from mercenaire_equipement where mercenaire_id = r.mercenaire_id and session_id = p_session;
    for l in select objet_id, quantite, gemmes from ligne_inventaire
             where inventaire_id = v_sac and quantite > 0 loop
      perform _arsenal_ajouter(l.objet_id, l.quantite, l.gemmes);
    end loop;
    delete from ligne_inventaire where inventaire_id = v_sac;
    insert into cimetiere (mercenaire_id, user_id, nom_joueur, annulable_rd, rd_donnees)
      values (r.mercenaire_id, r.user_id, r.nom_joueur, p_round,
        jsonb_build_object('equipement', v_eq, 'sac', v_contenu, 'quete_id', v_quete, 'position', v_position));
    -- Le lit est libéré ; entraînement, infirmerie et quête sont quittés (déclencheurs du recrutement).
    delete from recrutement where mercenaire_id = r.mercenaire_id and session_id = p_session;
    update mercenaire_etat
      set mort_champ = false, inconscient_rounds = null, inconscient_dec = false
      where mercenaire_id = r.mercenaire_id and session_id = p_session;
    perform _journal('equipement', coalesce(v_nom, 'Un mercenaire') || ' est mort sur le champ de bataille (Inconscient) : il quitte la quête et repose au cimetière, son équipement est rendu à l''arsenal.', 0,
      jsonb_build_object('mercenaire_id', r.mercenaire_id, 'cimetiere', true));
  end loop;
end;
$$;

-- Annulation du Rd : rappelle ceux que ce Rd venait d'envoyer au cimetière.
create function _cimetiere_rappeler_rd(p_session uuid, p_round integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  g record;
  x jsonb;
  v_sac uuid;
  v_gemmes uuid[];
  v_quete uuid;
begin
  if p_session is distinct from ctx_session() then
    return;
  end if;
  for g in select * from cimetiere where session_id = p_session and annulable_rd = p_round loop
    begin
      insert into recrutement (mercenaire_id, user_id, nom_joueur)
        values (g.mercenaire_id, g.user_id, g.nom_joueur);
    exception when others then
      continue;
    end;
    delete from cimetiere where mercenaire_id = g.mercenaire_id and session_id = p_session;
    for x in select * from jsonb_array_elements(coalesce(g.rd_donnees -> 'equipement', '[]'::jsonb)) loop
      v_gemmes := case when jsonb_typeof(x -> 'gemmes') = 'array'
        then array(select jsonb_array_elements_text(x -> 'gemmes')::uuid) else null end;
      if _arsenal_quantite((x ->> 'objet_id')::uuid, v_gemmes) >= 1 then
        perform _arsenal_retirer((x ->> 'objet_id')::uuid, 1, v_gemmes);
        insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id, gemmes)
          values (g.mercenaire_id, x ->> 'emplacement', (x ->> 'position')::smallint, (x ->> 'objet_id')::uuid, v_gemmes)
          on conflict do nothing;
      end if;
    end loop;
    v_sac := _sac_dos_id(g.mercenaire_id);
    for x in select * from jsonb_array_elements(coalesce(g.rd_donnees -> 'sac', '[]'::jsonb)) loop
      v_gemmes := case when jsonb_typeof(x -> 'gemmes') = 'array'
        then array(select jsonb_array_elements_text(x -> 'gemmes')::uuid) else null end;
      if _arsenal_quantite((x ->> 'objet_id')::uuid, v_gemmes) >= (x ->> 'quantite')::integer then
        perform _arsenal_retirer((x ->> 'objet_id')::uuid, (x ->> 'quantite')::integer, v_gemmes);
        insert into ligne_inventaire (inventaire_id, objet_id, quantite, gemmes)
          values (v_sac, (x ->> 'objet_id')::uuid, (x ->> 'quantite')::integer, v_gemmes);
      end if;
    end loop;
    v_quete := nullif(g.rd_donnees ->> 'quete_id', '')::uuid;
    if v_quete is not null
       and exists (select 1 from quete_etat where quete_id = v_quete and session_id = p_session and en_cours)
       and not exists (select 1 from quete_mercenaire
                       where quete_id = v_quete and session_id = p_session
                         and position = (g.rd_donnees ->> 'position')::smallint) then
      insert into quete_mercenaire (quete_id, position, mercenaire_id)
        values (v_quete, (g.rd_donnees ->> 'position')::smallint, g.mercenaire_id);
    end if;
    update mercenaire_etat
      set etat = 'inconscient', inconscient_rounds = 1, inconscient_dec = false, mort_champ = false
      where mercenaire_id = g.mercenaire_id and session_id = p_session;
  end loop;
end;
$$;

create or replace function _creatures_round()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.round_courant = old.round_courant + 1 then
    -- Les morts du Rd précédent ne sont plus annulables.
    update cimetiere set annulable_rd = null, rd_donnees = null
      where session_id = new.session_id and annulable_rd is not null;
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
    -- Mort sur le champ de bataille : quitte la quête et rejoint le cimetière tout de suite.
    begin
      perform _cimetiere_envoyer_morts(new.session_id, new.round_courant);
    exception when others then
      raise warning 'cimetière (Rd) : %', sqlerrm;
    end;
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
    begin
      perform _cimetiere_rappeler_rd(new.session_id, old.round_courant);
    exception when others then
      raise warning 'cimetière (annulation du Rd) : %', sqlerrm;
    end;
  end if;
  return new;
end;
$$;

create or replace function quete_engager(p_position integer, p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_quete uuid;
  v_lancee boolean;
  v_restantes integer;
  v_instances integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  perform _verrou_partie();
  select quete_id, lancee, instances_restantes into v_quete, v_lancee, v_restantes from quete_etat where en_cours;
  if v_quete is null then
    raise exception 'Choisissez d''abord la quête.';
  end if;
  if v_lancee and not is_admin() then
    select instances_requises into v_instances from quete where id = v_quete;
    if coalesce(v_instances, 1) <= 1 then
      raise exception 'La quête est lancée : plus aucun mercenaire ne peut la rejoindre.';
    end if;
    if coalesce(v_restantes, v_instances) >= v_instances then
      raise exception 'La quête est lancée : de nouveaux mercenaires pourront la rejoindre aux instances suivantes.';
    end if;
  end if;
  if p_position is null or p_position < 0 or p_position > 5 then
    raise exception 'Cet emplacement n''existe pas.';
  end if;
  if not exists (select 1 from recrutement where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire n''est pas au dortoir.';
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Ce mercenaire n''est pas recruté par vous.';
  end if;
  if exists (select 1 from quete_mercenaire where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est déjà engagé dans une quête.';
  end if;
  if exists (select 1 from entrainement_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est à l''entraînement : renvoyez-le d''abord au dortoir.';
  end if;
  if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
    raise exception 'Ce mercenaire est à l''infirmerie.';
  end if;
  insert into quete_mercenaire (quete_id, position, mercenaire_id)
    values (v_quete, p_position, p_mercenaire);
exception
  when unique_violation then
    raise exception 'Cet emplacement vient d''être pris.';
end;
$$;

grant create on schema public to fortress_fn;
alter function _cimetiere_envoyer_morts(uuid, integer) owner to fortress_fn;
alter function _cimetiere_rappeler_rd(uuid, integer) owner to fortress_fn;
alter function _creatures_round() owner to fortress_fn;
alter function quete_engager(integer, uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _cimetiere_envoyer_morts(uuid, integer) from public, anon, authenticated;
revoke all on function _cimetiere_rappeler_rd(uuid, integer) from public, anon, authenticated;
