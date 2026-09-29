-- Potions d'énergie et de vie (Bruno, 2026-09-29) : utilisées depuis un sac à dos, elles rendent au
-- mercenaire 3 (mineure), 5 (médiane) ou 8 (majeure) points d'énergie ou de santé, sans dépasser le
-- maximum (énergie max = 2 × Mental, santé max = 3 + 2 × Puissance). Les autres produits
-- alchimiques restent sans effet automatique. La fonction renvoie maintenant un texte décrivant
-- l'effet appliqué (elle renvoyait void) ; un mercenaire à l'infirmerie voit son compteur de soins
-- recalculé, comme quand sa santé est modifiée sur la fiche.
drop function if exists sac_dos_utiliser(uuid, uuid, uuid[]);
create function sac_dos_utiliser(p_mercenaire uuid, p_objet uuid, p_gemmes uuid[] default null)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_merc text;
  v_nom text;
  v_racine text;
  v_sac uuid;
  v_ligne uuid;
  v_qte integer;
  v_type text;
  v_gain integer;
  v_max integer;
  v_act integer;
  v_nouvelle integer;
  v_reste integer;
  v_effet text := '';
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  select nom into v_merc from mercenaire where id = p_mercenaire;
  if v_merc is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  select nom, _racine_categorie(categorie_id) into v_nom, v_racine
    from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  if v_racine is distinct from 'Produits Alchimiques' then
    raise exception 'Seuls les produits alchimiques peuvent être utilisés.';
  end if;
  v_sac := _sac_dos_id(p_mercenaire);
  select id, quantite into v_ligne, v_qte from ligne_inventaire
    where inventaire_id = v_sac and objet_id = p_objet and gemmes is not distinct from v_gemmes and quantite > 0
    order by created_at, id limit 1
    for update;
  if v_ligne is null then
    raise exception 'Cet objet n''est pas dans le sac à dos.';
  end if;
  if v_qte = 1 then
    delete from ligne_inventaire where id = v_ligne;
  else
    update ligne_inventaire set quantite = quantite - 1, updated_at = now() where id = v_ligne;
  end if;

  -- Effet des potions d'énergie et de vie.
  v_type := case
    when lower(v_nom) like 'potion d''energie %' or lower(v_nom) like 'potion d''énergie %' then 'energie'
    when lower(v_nom) like 'potion de vie %' then 'sante'
  end;
  v_gain := case
    when lower(v_nom) like '% mineure' then 3
    when lower(v_nom) like '% médiane' or lower(v_nom) like '% mediane' then 5
    when lower(v_nom) like '% majeure' then 8
  end;
  if v_type is not null and v_gain is not null then
    insert into mercenaire_etat (session_id, mercenaire_id, veterance)
      values (ctx_session(), p_mercenaire, _vet(p_mercenaire))
      on conflict (session_id, mercenaire_id) do nothing;
    if v_type = 'energie' then
      v_max := 2 * _mental(p_mercenaire);
      select coalesce(e.energie_actuelle, v_max) into v_act from mercenaire_etat e
        where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire for update;
      v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
      update mercenaire_etat set energie_actuelle = case when v_nouvelle >= v_max then null else v_nouvelle end
        where session_id = ctx_session() and mercenaire_id = p_mercenaire;
      v_effet := '+' || (v_nouvelle - v_act) || ' énergie';
    else
      v_max := _sante_max(p_mercenaire);
      select coalesce(e.sante_actuelle, v_max) into v_act from mercenaire_etat e
        where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire for update;
      v_nouvelle := least(v_act + v_gain, greatest(v_max, v_act));
      update mercenaire_etat set sante_actuelle = case when v_nouvelle >= v_max then null else v_nouvelle end
        where session_id = ctx_session() and mercenaire_id = p_mercenaire;
      v_effet := '+' || (v_nouvelle - v_act) || ' santé';
      if exists (select 1 from infirmerie_place where mercenaire_id = p_mercenaire) then
        v_reste := _soins_instances(p_mercenaire, case when v_nouvelle >= v_max then null else v_nouvelle end);
        if v_reste = 0 then
          delete from infirmerie_place where mercenaire_id = p_mercenaire;
        else
          update infirmerie_place set restant = v_reste where mercenaire_id = p_mercenaire;
        end if;
      end if;
    end if;
  end if;

  perform _journal('equipement',
    v_nom || ' utilisé par ' || v_merc || case when v_effet <> '' then ' (' || v_effet || ')' else '' end || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'objet_id', p_objet, 'quantite', 1));
  return v_effet;
end;
$$;

grant create on schema public to fortress_fn;
alter function sac_dos_utiliser(uuid, uuid, uuid[]) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function sac_dos_utiliser(uuid, uuid, uuid[]) from public;
grant execute on function sac_dos_utiliser(uuid, uuid, uuid[]) to authenticated;
