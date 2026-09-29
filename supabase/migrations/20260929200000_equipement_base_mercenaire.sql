-- Équipement de base d'un mercenaire (Bruno, 2026-09-29) : défini en administration à partir du
-- catalogue, dans les mêmes emplacements que la fiche (3 armes, 1 armure, 1 bouclier, 3 objets). Il est
-- installé sur le PREMIER mercenaire gratuit d'un joueur (voir 20260929190000) ; ensuite il se gère
-- comme n'importe quel équipement (déséquiper -> sac à dos -> arsenal, puis vendre ou détruire).
create table mercenaire_equipement_base (
  id uuid primary key default gen_random_uuid(),
  mercenaire_id uuid not null references mercenaire (id) on delete cascade,
  emplacement text not null check (emplacement in ('arme', 'armure', 'bouclier', 'objet')),
  position smallint not null check (position between 0 and 2),
  objet_id uuid not null references objet_catalogue (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint mercenaire_equipement_base_cle unique (mercenaire_id, emplacement, position),
  constraint mercenaire_equipement_base_unique_check
    check (emplacement not in ('armure', 'bouclier') or position = 0)
);
alter table mercenaire_equipement_base enable row level security;
create policy "mercenaire_equipement_base: lecture" on mercenaire_equipement_base for select to authenticated using (true);
create policy "mercenaire_equipement_base: ecriture admin" on mercenaire_equipement_base for all to authenticated
  using (is_admin()) with check (is_admin());
create policy "mercenaire_equipement_base: fonctions serveur" on mercenaire_equipement_base for select to fortress_fn using (true);
grant select, insert, update, delete on mercenaire_equipement_base to authenticated;
revoke all on mercenaire_equipement_base from anon;

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
    -- Le premier mercenaire gratuit arrive équipé de son équipement de base (défini dans l'administration).
    -- Les objets viennent du catalogue : le joueur peut les déséquiper, puis les vendre ou les détruire.
    insert into mercenaire_equipement (mercenaire_id, emplacement, position, objet_id)
      select b.mercenaire_id, b.emplacement, b.position, b.objet_id
      from mercenaire_equipement_base b where b.mercenaire_id = p_mercenaire
      on conflict do nothing;
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : premier mercenaire de '
      || v_joueur || ', gratuit.', 0,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', 0, 'gratuit', true));
  else
    update partie_etat set or_compagnie = or_compagnie - v_cout where id;
    perform _journal('depense', 'Recrutement de ' || v_nom || ' (vétérance ' || v_vet || ') : −' || v_cout || ' Po.', -v_cout,
      jsonb_build_object('mercenaire_id', p_mercenaire, 'veterance', v_vet, 'cout', v_cout));
  end if;
  return jsonb_build_object('cout', v_cout, 'or', v_or - v_cout, 'gratuit', v_gratuit);
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_recruter(uuid, text) owner to fortress_fn;
revoke create on schema public from fortress_fn;
