-- Équipement de base et renvoi (précisions de Bruno, 2026-09-29) :
--  * TOUT mercenaire arrive avec son propre équipement de base la première fois qu'il est recruté dans
--    une session (la gratuité du premier mercenaire est indépendante de cela) ;
--  * renvoyer un mercenaire le laisse « hors jeu » avec sa vétérance, son équipement, son sac à dos et
--    ses PV actuels ; SEULE son énergie revient au maximum ;
--  * le recruter de nouveau ne réinitialise rien (équipement, PV, vétérance) et se paie à hauteur de la
--    vétérance acquise (100 Po × vétérance, comme avant).
-- Le drapeau `equipement_base_donne` (par session, dans mercenaire_etat) garantit que l'équipement de
-- base n'est donné qu'une fois : un mercenaire renvoyé puis recruté de nouveau ne le reçoit pas deux fois.
alter table mercenaire_etat add column equipement_base_donne boolean not null default false;

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
  v_cle text;
  v_gratuit boolean;
  v_donne boolean;
  v_equipe boolean := false;
begin
  v_or := _verrou_partie();
  if v_joueur = '' then
    raise exception 'Inscrivez votre nom de joueur avant de recruter.';
  end if;
  v_cle := lower(v_joueur);
  select nom into v_nom from mercenaire where id = p_mercenaire;
  if v_nom is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  v_vet := _vet(p_mercenaire);
  v_gratuit := not exists (
    select 1 from recrutement_gratuit where session_id = ctx_session() and nom_cle = v_cle);
  v_cout := case when v_gratuit then 0 else 100 * v_vet end;
  if v_or < v_cout then
    raise exception 'Trésorerie insuffisante : recruter % coûte % Po (100 Po × vétérance %).', v_nom, v_cout, v_vet;
  end if;
  -- L'insertion attribue le lit (ou refuse s'il n'y en a plus, ou si le mercenaire est déjà
  -- recruté) : rien n'est payé ni consommé dans ces cas, l'opération entière est annulée.
  insert into recrutement (mercenaire_id, user_id, nom_joueur) values (p_mercenaire, auth.uid(), v_joueur);
  if v_gratuit then
    insert into recrutement_gratuit (nom_cle, mercenaire_id) values (v_cle, p_mercenaire);
  end if;

  -- Équipement de base (défini dans l'administration) : donné une seule fois par session, seulement
  -- si le mercenaire n'a encore rien d'équipé (aucun écrasement d'un équipement acquis).
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
  end if;

  if v_gratuit then
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : premier mercenaire de '
      || v_joueur || ', gratuit.' || case when v_equipe then ' Il arrive avec son équipement de base.' else '' end, 0,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', 0, 'gratuit', true));
  else
    update partie_etat set or_compagnie = or_compagnie - v_cout where id;
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : −' || v_cout || ' Po.'
      || case when v_equipe then ' Il arrive avec son équipement de base.' else '' end, -v_cout,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', v_cout));
  end if;
  return jsonb_build_object('cout', v_cout, 'or', v_or - v_cout, 'gratuit', v_gratuit);
end;
$$;

-- Renvoi : l'énergie du mercenaire revient au maximum (énergie actuelle vide = maximum). Sa vétérance,
-- son équipement, son sac à dos et ses PV actuels ne sont pas touchés.
create function recrutement_renvoi_energie_max()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update mercenaire_etat set energie_actuelle = null
    where session_id = old.session_id and mercenaire_id = old.mercenaire_id;
  return old;
end;
$$;

create trigger recrutement_renvoi_energie
  after delete on recrutement
  for each row execute function recrutement_renvoi_energie_max();

grant create on schema public to fortress_fn;
alter function mercenaire_recruter(uuid, text) owner to fortress_fn;
alter function recrutement_renvoi_energie_max() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function recrutement_renvoi_energie_max() from public;
