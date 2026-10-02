-- Créatures (demande de Bruno, 2026-10-02) : catalogue de créatures, créatures d'une quête en cours,
-- visibles et modifiables par le MJ SEUL (lecture comme écriture : aucune policy pour les joueurs).
--
--  * `creature` : catalogue COMMUN à toutes les sessions (comme objets, quêtes…). Santé et énergie
--    max, trois caractéristiques (Puissance, Vélocité, Mental), FP, défenses (listes), 12 emplacements
--    d'icônes cliquables. Les listes de valeurs (types, tailles, dégâts, états, sens) sont dans le code.
--  * `capacite_creature` : capacités PARTAGÉES par titre (titre unique, texte, icône). Corriger le
--    texte met à jour toutes les créatures qui l'utilisent, y compris celles déjà en jeu.
--  * `creature_capacite` : les cinq listes extensibles d'une créature (capacité, action, action
--    bonus, réaction, action légendaire), dans l'ordre. `creature_icone` : les 12 emplacements.
--  * `quete_creature` : créatures « piochées » pour une quête (avec quantité).
--  * `creature_quete` : une ligne PAR créature en jeu, propre à la session : seulement l'état
--    (santé actuelle, énergie actuelle, nom de l'onglet, commentaires). La fiche reste lue dans le
--    catalogue : une correction du catalogue s'applique donc immédiatement aux créatures en jeu.
--    Santé/énergie actuelle vide (null) = maximum, comme l'énergie des mercenaires.
--  * Cycle de vie (triggers sur quete_etat) : choisir une quête crée des copies neuves ; annuler le
--    choix les supprime ; l'accomplissement les garde (un « Annuler » du dernier +1 Instance rouvre la
--    quête) jusqu'à ce que la quête soit choisie de nouveau, ce qui les réinitialise.
--  * Énergie : creature_depenser_energie (1 à 10, refusée si insuffisante, comme les mercenaires).
--    Chaque clic sur « RD » rend 1 point d'énergie à chaque créature en jeu (sans dépasser le max) ;
--    annuler le RD retire ce point aux seules créatures qui l'avaient gagné. Chaque RD retire aussi
--    1 round à l'état en cours (etat_rounds, 1 à 9) ; annuler le RD le rend. +1 Instance remet
--    l'énergie de toutes les créatures de la session au maximum (comme les mercenaires).
--  * Santé : saisie à la main, jamais en dessous de 0 (0 = créature détruite, pas de valeur négative).
--
-- Fonctions et triggers appartiennent à fortress_fn (isolation par session, cf. docs/SESSIONS.md),
-- sauf _creatures_quete_cycle (voir la note en fin de fichier).
-- Toute suppression/mise à jour a une clause WHERE explicite (pg_safeupdate).

-- ---------------------------------------------------------------------------
-- 1. Catalogue
-- ---------------------------------------------------------------------------
create table capacite_creature (
  id uuid primary key default gen_random_uuid(),
  titre text not null check (length(btrim(titre)) > 0),
  texte text not null default '',
  icone text,
  created_at timestamptz not null default now()
);
create unique index capacite_creature_titre_unique on capacite_creature (lower(btrim(titre)));

create table creature (
  id uuid primary key default gen_random_uuid(),
  nom text not null check (length(btrim(nom)) > 0),
  type text,
  sous_type text,
  taille text,
  sante_max integer not null default 1 check (sante_max between 1 and 9999),
  energie_max integer not null default 0 check (energie_max between 0 and 999),
  vitesse integer not null default 0 check (vitesse between 0 and 99),
  fp integer not null default 0 check (fp between 0 and 99),
  puissance integer not null default 0 check (puissance between 0 and 99),
  velocite integer not null default 0 check (velocite between 0 and 99),
  mental integer not null default 0 check (mental between 0 and 99),
  vulnerabilites text[] not null default '{}',
  resistances text[] not null default '{}',
  immunites_degats text[] not null default '{}',
  immunites_etats text[] not null default '{}',
  sens text[] not null default '{}',
  description text,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index creature_nom_unique on creature (lower(btrim(nom)));

create table creature_capacite (
  id uuid primary key default gen_random_uuid(),
  creature_id uuid not null references creature (id) on delete cascade,
  categorie text not null check (categorie in ('capacite', 'action', 'action_bonus', 'reaction', 'legendaire')),
  position smallint not null check (position >= 0),
  capacite_id uuid not null references capacite_creature (id) on delete cascade,
  constraint creature_capacite_position_key unique (creature_id, categorie, position)
);

create table creature_icone (
  creature_id uuid not null references creature (id) on delete cascade,
  position smallint not null check (position between 0 and 11),
  capacite_id uuid not null references capacite_creature (id) on delete cascade,
  primary key (creature_id, position)
);

create table quete_creature (
  quete_id uuid not null references quete (id) on delete cascade,
  creature_id uuid not null references creature (id) on delete cascade,
  quantite smallint not null default 1 check (quantite between 1 and 20),
  primary key (quete_id, creature_id)
);

-- ---------------------------------------------------------------------------
-- 2. Créatures en jeu (état par session)
-- ---------------------------------------------------------------------------
create table creature_quete (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references session (id) on delete cascade default ctx_session(),
  quete_id uuid not null references quete (id) on delete cascade,
  creature_id uuid not null references creature (id) on delete cascade,
  ordre smallint not null default 0,
  nom_onglet text not null check (length(btrim(nom_onglet)) > 0),
  sante_actuelle integer check (sante_actuelle is null or sante_actuelle >= 0),
  energie_actuelle integer check (energie_actuelle is null or energie_actuelle >= 0),
  commentaires text not null default '',
  -- État en cours (un seul à la fois, liste dans le code ; vide = aucun) + niveau (épuisé : 1 à 3) +
  -- durée en rounds (1 à 9, 0 = sans durée) : chaque RD retire 1 round ; à 0 l'état disparaît.
  etat text,
  etat_niveau smallint not null default 1 check (etat_niveau between 1 and 3),
  etat_rounds smallint not null default 0 check (etat_rounds between 0 and 9),
  gain_round boolean not null default false,
  etat_decremente boolean not null default false,
  etat_efface text,
  created_at timestamptz not null default now()
);
create index creature_quete_session_quete on creature_quete (session_id, quete_id);

-- ---------------------------------------------------------------------------
-- 3. Sécurité (RLS) : le MJ seul lit et écrit. Aucune policy pour les joueurs.
-- ---------------------------------------------------------------------------
alter table capacite_creature enable row level security;
alter table creature enable row level security;
alter table creature_capacite enable row level security;
alter table creature_icone enable row level security;
alter table quete_creature enable row level security;
alter table creature_quete enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['capacite_creature', 'creature', 'creature_capacite', 'creature_icone', 'quete_creature']
  loop
    execute format($f$create policy "%1$s: lecture admin" on %1$I for select to authenticated
      using (is_admin())$f$, t);
    execute format($f$create policy "%1$s: ecriture admin" on %1$I for all to authenticated
      using (is_admin()) with check (is_admin())$f$, t);
  end loop;
end;
$$;

create policy "creature_quete: lecture admin" on creature_quete for select to authenticated
  using (is_admin() and session_id = ctx_session());
create policy "creature_quete: ecriture admin" on creature_quete for all to authenticated
  using (is_admin() and session_id = ctx_session())
  with check (is_admin() and session_id = ctx_session());
create policy "creature_quete: fonctions serveur" on creature_quete for all to fortress_fn
  using (session_id = ctx_session()) with check (session_id = ctx_session());

grant select, insert, update, delete on
  capacite_creature, creature, creature_capacite, creature_icone, quete_creature, creature_quete
  to authenticated, fortress_fn;
revoke all on
  capacite_creature, creature, creature_capacite, creature_icone, quete_creature, creature_quete
  from anon;

-- ---------------------------------------------------------------------------
-- 4. Cycle de vie : copies créées au choix de la quête, supprimées à l'annulation du choix
-- ---------------------------------------------------------------------------
create function _creatures_quete_cycle()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_etait_en_cours boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_etait_en_cours := old.en_cours;
  end if;
  if new.en_cours and not v_etait_en_cours then
    -- Quête (re)choisie : des copies neuves, avec nom d'onglet « Nom » ou « Nom 1, Nom 2… ».
    delete from creature_quete where session_id = new.session_id and quete_id = new.quete_id;
    insert into creature_quete (session_id, quete_id, creature_id, ordre, nom_onglet)
      select new.session_id, new.quete_id, qc.creature_id,
             (row_number() over (order by c.nom, g.n) - 1)::smallint,
             case when qc.quantite > 1 then c.nom || ' ' || g.n else c.nom end
      from quete_creature qc
      join creature c on c.id = qc.creature_id
      cross join lateral generate_series(1, qc.quantite) as g(n)
      where qc.quete_id = new.quete_id;
  elsif v_etait_en_cours and not new.en_cours and new.instances_restantes is null then
    -- Choix annulé (l'accomplissement laisse instances_restantes à 0 et garde les copies).
    delete from creature_quete where session_id = new.session_id and quete_id = new.quete_id;
  end if;
  return new;
end;
$$;

create trigger quete_etat_creatures
  after insert or update of en_cours on quete_etat
  for each row execute function _creatures_quete_cycle();

-- ---------------------------------------------------------------------------
-- 5. Énergie : dépense (1 à 10) et +1 à chaque RD
-- ---------------------------------------------------------------------------
create function creature_depenser_energie(p_creature_quete uuid, p_montant integer)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_max integer;
  v_actuelle integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_montant is null or p_montant < 1 or p_montant > 10 then
    raise exception 'Le montant à dépenser est un entier de 1 à 10.';
  end if;
  -- Ligne verrouillée : deux dépenses simultanées ne peuvent pas passer sous 0.
  select k.energie_max, coalesce(c.energie_actuelle, k.energie_max)
    into v_max, v_actuelle
    from creature_quete c join creature k on k.id = c.creature_id
    where c.id = p_creature_quete and c.session_id = ctx_session()
    for update of c;
  if not found then
    raise exception 'Créature inconnue.';
  end if;
  if v_actuelle < p_montant then
    raise exception 'Énergie insuffisante : % disponible(s), % demandée(s).', v_actuelle, p_montant;
  end if;
  update creature_quete set energie_actuelle = v_actuelle - p_montant
    where id = p_creature_quete and session_id = ctx_session();
  return v_actuelle - p_montant;
end;
$$;

-- RD (+1 au compteur) : +1 d'énergie par créature, sans dépasser le max. Annuler le RD (-1 exactement)
-- retire ce point aux seules créatures qui l'avaient gagné. Une remise à zéro du round ne touche à rien.
-- Trigger sur partie_etat : tout se passe dans la transaction de round_avancer / round_annuler.
create function _creatures_round()
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
    -- Dernier round écoulé : l'état disparaît (mémorisé dans etat_efface pour annuler le RD).
    update creature_quete
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
  end if;
  return new;
end;
$$;

create trigger partie_etat_round_creatures
  after update of round_courant on partie_etat
  for each row execute function _creatures_round();

-- +1 Instance : l'énergie de TOUTES les créatures de la session revient au maximum (vide = maximum),
-- comme celle des mercenaires. Reprend energie_instance() / energie_annuler_instance() de
-- 20260930160000 : même format de retour (tableau JSON), les entrées de créatures portent
-- « creature_quete_id » au lieu de « mercenaire_id » (l'ancien client les ignore).
create or replace function energie_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_gains jsonb;
  v_creatures jsonb;
  v_mercs integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select coalesce(jsonb_agg(jsonb_build_object('mercenaire_id', mercenaire_id, 'energie_avant', energie_actuelle)), '[]'::jsonb)
    into v_gains
    from mercenaire_etat
    where session_id = ctx_session() and energie_actuelle is not null;
  update mercenaire_etat set energie_actuelle = null
    where session_id = ctx_session() and energie_actuelle is not null;
  v_mercs := jsonb_array_length(v_gains);
  select coalesce(jsonb_agg(jsonb_build_object('creature_quete_id', id, 'energie_avant', energie_actuelle)), '[]'::jsonb)
    into v_creatures
    from creature_quete
    where session_id = ctx_session() and energie_actuelle is not null;
  update creature_quete set energie_actuelle = null
    where session_id = ctx_session() and energie_actuelle is not null;
  v_gains := v_gains || v_creatures;
  if v_mercs > 0 then
    perform _journal('or',
      'Nouvelle instance : l''énergie de ' || v_mercs || ' mercenaire(s) revient au maximum.',
      0, jsonb_build_object('energie_instance', v_mercs));
  end if;
  return v_gains;
end;
$$;

create or replace function energie_annuler_instance(p_gains jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  i jsonb;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  if p_gains is null then
    return;
  end if;
  perform _verrou_partie();
  for i in select * from jsonb_array_elements(p_gains)
  loop
    if i ? 'creature_quete_id' then
      update creature_quete
        set energie_actuelle = (i ->> 'energie_avant')::integer
        where id = (i ->> 'creature_quete_id')::uuid and session_id = ctx_session()
          and energie_actuelle is null;
    else
      update mercenaire_etat
        set energie_actuelle = (i ->> 'energie_avant')::integer
        where mercenaire_id = (i ->> 'mercenaire_id')::uuid and session_id = ctx_session()
          and energie_actuelle is null;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Propriétaire fortress_fn (isolation par session) et droits d'exécution
-- ---------------------------------------------------------------------------
grant create on schema public to fortress_fn;
alter function energie_instance() owner to fortress_fn;
alter function energie_annuler_instance(jsonb) owner to fortress_fn;
-- _creatures_quete_cycle reste propriété de postgres (EXCEPTION volontaire à la règle fortress_fn) : tout
-- joueur peut choisir une quête, mais le catalogue de créatures est réservé au MJ ; le déclencheur doit
-- donc le lire sans RLS. Il n'agit que sur la session de la ligne de quete_etat modifiée (session_id
-- explicite partout), jamais sur la session active de l'appelant.
alter function creature_depenser_energie(uuid, integer) owner to fortress_fn;
alter function _creatures_round() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function _creatures_quete_cycle() from public;
revoke all on function creature_depenser_energie(uuid, integer) from public;
revoke all on function _creatures_round() from public;
grant execute on function creature_depenser_energie(uuid, integer) to authenticated;
