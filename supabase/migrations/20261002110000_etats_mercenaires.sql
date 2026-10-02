-- États des mercenaires en quête (demande de Bruno, 2026-10-02) : sur la fiche d'un mercenaire engagé
-- dans une quête, les JOUEURS eux-mêmes choisissent son état parmi les quinze états du jeu (un seul à la
-- fois ; « épuisé » a trois niveaux) et une durée en rounds (1 à 9). Chaque clic du MJ sur « RD » retire
-- 1 round ; à 0 l'état disparaît. Annuler le RD le rend. Même règle que les créatures (migration
-- 20261002100000), dont le déclencheur `_creatures_round` est ici étendu aux mercenaires.
--
--  * mercenaire_etat : colonnes etat / etat_niveau / etat_rounds (+ etat_decremente, etat_efface pour
--    pouvoir annuler un RD), propres à la session.
--  * mercenaire_definir_etat : le joueur du mercenaire (ou le MJ) définit ou efface l'état ; refusé si le
--    mercenaire n'est pas engagé dans une quête (on peut toujours effacer).
--  * Quitter la quête (retrait, accomplissement, renvoi) efface l'état (déclencheur sur quete_mercenaire).
--  * Realtime : creature_quete est ajoutée à la publication (mise à jour en direct de la page MJ).

alter table mercenaire_etat
  add column etat text,
  add column etat_niveau smallint not null default 1 check (etat_niveau between 1 and 3),
  add column etat_rounds smallint not null default 0 check (etat_rounds between 0 and 9),
  add column etat_decremente boolean not null default false,
  add column etat_efface text;

create function mercenaire_definir_etat(
  p_mercenaire uuid, p_etat text, p_niveau integer default 1, p_rounds integer default 0)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if not exists (select 1 from mercenaire where id = p_mercenaire) then
    raise exception 'Mercenaire inconnu.';
  end if;
  if p_etat is null then
    update mercenaire_etat
      set etat = null, etat_niveau = 1, etat_rounds = 0, etat_efface = null, etat_decremente = false
      where session_id = ctx_session() and mercenaire_id = p_mercenaire;
    return;
  end if;
  if p_etat not in ('agrippe', 'assourdi', 'aveugle', 'charme', 'desoriente', 'effraye', 'empoisonne',
                    'endormi', 'entrave', 'epuise', 'etourdi', 'fascine', 'inconscient', 'paralyse', 'petrifie') then
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
    set etat = p_etat, etat_niveau = p_niveau, etat_rounds = p_rounds, etat_efface = null, etat_decremente = false
    where session_id = ctx_session() and mercenaire_id = p_mercenaire;
end;
$$;

-- Un mercenaire qui quitte la quête perd son état. Propriétaire postgres, session_id de la ligne
-- supprimée (comme _creatures_quete_cycle) : s'exécute aussi quand c'est une fonction d'une autre
-- session qui supprime l'engagement.
create function _etat_apres_quete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update mercenaire_etat
    set etat = null, etat_niveau = 1, etat_rounds = 0, etat_efface = null, etat_decremente = false
    where session_id = old.session_id and mercenaire_id = old.mercenaire_id and etat is not null;
  return old;
end;
$$;

create trigger quete_mercenaire_efface_etat
  after delete on quete_mercenaire
  for each row execute function _etat_apres_quete();

-- RD : même déclencheur que les créatures, étendu aux mercenaires.
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
    -- Dernier round écoulé : l'état disparaît (mémorisé dans etat_efface pour annuler le RD).
    update creature_quete
      set etat_rounds = etat_rounds - 1, etat_decremente = true,
          etat_efface = case when etat_rounds = 1 then etat end,
          etat = case when etat_rounds = 1 then null else etat end
      where session_id = new.session_id and etat_rounds > 0;
    update mercenaire_etat set etat_decremente = false, etat_efface = null
      where session_id = new.session_id and (etat_decremente or etat_efface is not null);
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
  end if;
  return new;
end;
$$;

-- Mise à jour en direct de la page MJ des créatures.
do $$
begin
  alter publication supabase_realtime add table creature_quete;
exception
  when undefined_object then null;
  when duplicate_object then null;
end;
$$;

grant create on schema public to fortress_fn;
alter function mercenaire_definir_etat(uuid, text, integer, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function mercenaire_definir_etat(uuid, text, integer, integer) from public;
revoke all on function _etat_apres_quete() from public;
grant execute on function mercenaire_definir_etat(uuid, text, integer, integer) to authenticated;
-- _etat_apres_quete reste propriété de postgres (exception volontaire, voir le commentaire plus haut).
