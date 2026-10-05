-- Un mercenaire qui débute (vétérance 1) arrive avec une Potion de Vie Mineure et une Potion d'Energie Mineure dans son
-- sac à dos (Bruno, 2026-10-06) : une seule fois par session, comme l'équipement de base. Reste de la fonction : celui de
-- 20261005160000_recrutement_pseudo_serveur.sql.

create or replace function mercenaire_recruter(p_mercenaire uuid, p_nom_joueur text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  v_nom text;
  v_vet integer;
  v_cout integer;
  v_joueur text := left(btrim(coalesce(p_nom_joueur, '')), 24);
  v_pseudo text;
  v_cle text;
  v_gratuit boolean;
  v_donne boolean;
  v_equipe boolean := false;
  v_potions boolean := false;
  v_sac uuid;
  v_vie uuid;
  v_energie uuid;
begin
  v_or := _verrou_partie();
  if not is_admin() then
    select pseudo into v_pseudo from session_membre
      where session_id = ctx_session() and user_id = auth.uid();
    if v_pseudo is not null then
      v_joueur := v_pseudo;
    end if;
  end if;
  if v_joueur = '' then
    raise exception 'Inscrivez votre nom de joueur avant de recruter.';
  end if;
  v_cle := lower(v_joueur);
  select nom into v_nom from mercenaire where id = p_mercenaire;
  if v_nom is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  v_vet := _vet(p_mercenaire);
  if exists (select 1 from cimetiere where session_id = ctx_session() and mercenaire_id = p_mercenaire) then
    raise exception '% repose au cimetière et ne peut plus être recruté.', v_nom;
  end if;
  v_gratuit := not exists (
    select 1 from recrutement_gratuit where session_id = ctx_session() and nom_cle = v_cle);
  v_cout := case when v_gratuit then 0 else 100 * v_vet end;
  if v_or < v_cout then
    raise exception 'Trésorerie insuffisante : recruter % coûte % Po (100 Po × vétérance %).', v_nom, v_cout, v_vet;
  end if;
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (p_mercenaire, auth.uid(), v_joueur);
  if v_gratuit then
    insert into recrutement_gratuit (nom_cle, mercenaire_id) values (v_cle, p_mercenaire);
  end if;

  select coalesce(e.equipement_base_donne, false) into v_donne from mercenaire_etat e
    where e.session_id = ctx_session() and e.mercenaire_id = p_mercenaire;
  if not coalesce(v_donne, false) then
    if not exists (select 1 from mercenaire_equipement q
                   where q.session_id = ctx_session() and q.mercenaire_id = p_mercenaire) then
      insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id)
        select b.mercenaire_id, b.emplacement, b.position, b.objet_id
        from mercenaire_equipement_base b where b.mercenaire_id = p_mercenaire
        on conflict do nothing;
      v_equipe := found;
    end if;
    insert into mercenaire_etat (session_id, mercenaire_id, veterance, equipement_base_donne)
      values (ctx_session(), p_mercenaire, v_vet, true)
      on conflict (session_id, mercenaire_id) do update set equipement_base_donne = true;
    -- Mercenaire de vétérance 1 : une potion de vie et une potion d'énergie mineures dans son sac à dos.
    if v_vet = 1 then
      select id into v_vie from objet_catalogue where lower(btrim(nom)) = 'potion de vie mineure' limit 1;
      select id into v_energie from objet_catalogue where lower(btrim(nom)) = 'potion d''energie mineure' limit 1;
      if v_vie is not null and v_energie is not null then
        v_sac := _sac_dos_id(p_mercenaire);
        perform _sac_dos_ajouter(v_sac, v_vie, 1, null, 'recruter');
        perform _sac_dos_ajouter(v_sac, v_energie, 1, null, 'recruter');
        v_potions := true;
      end if;
    end if;
  end if;

  if v_gratuit then
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : premier mercenaire de '
      || v_joueur || ', gratuit.' || case when v_equipe then ' Il arrive avec son équipement de base.' else '' end
      || case when v_potions then ' Il reçoit une potion de vie et une potion d''énergie mineures dans son sac à dos.' else '' end, 0,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', 0, 'gratuit', true));
  else
    update partie_etat set or_compagnie = or_compagnie - v_cout where id;
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : −' || v_cout || ' Po.'
      || case when v_equipe then ' Il arrive avec son équipement de base.' else '' end
      || case when v_potions then ' Il reçoit une potion de vie et une potion d''énergie mineures dans son sac à dos.' else '' end, -v_cout,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', v_cout));
  end if;
  return jsonb_build_object('cout', v_cout, 'or', v_or - v_cout, 'gratuit', v_gratuit);
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_recruter(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_recruter(uuid, text) from public;
grant execute on function mercenaire_recruter(uuid, text) to authenticated;
