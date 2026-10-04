-- Récompense mystère CHOISIE (Bruno, 2026-10-04) : le « ? » (objet Récompense mystère placé dans un
-- emplacement de quête) peut maintenant cacher un objet précis choisi par le MJ au lieu d'un tirage au
-- hasard. Le choix est dans une table réservée au MJ (les joueurs lisent quete_recompense, donc le choix
-- n'y figure jamais : ils ne voient que le « ? »). Sans choix, le tirage au hasard reste inchangé.
-- À la fin de la quête, l'objet choisi est donné (quantité de l'emplacement) comme un objet tiré.
-- Reprend quetes_instance() de 20260930150000.

create table quete_recompense_choix (
  quete_id uuid not null references quete (id) on delete cascade,
  position smallint not null check (position between 1 and 5),
  objet_id uuid not null references objet_catalogue (id),
  primary key (quete_id, position)
);
alter table quete_recompense_choix enable row level security;
create policy "quete_recompense_choix: lecture et ecriture admin"
  on quete_recompense_choix for all to authenticated using (is_admin()) with check (is_admin());
-- quetes_instance() appartient à fortress_fn : lecture du choix à la fin de la quête.
create policy "quete_recompense_choix: fonctions serveur"
  on quete_recompense_choix for select to fortress_fn using (true);
grant select, insert, update, delete on quete_recompense_choix to authenticated;
grant select on quete_recompense_choix to fortress_fn;
revoke all on quete_recompense_choix from anon;

create or replace function quetes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  e quete_etat%rowtype;
  r record;
  v_avant integer;
  v_apres integer;
  v_vet_avant integer;
  v_vet_apres integer;
  v_energie integer;
  v_gagnants integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_mercs jsonb := '[]'::jsonb;
  v_myst_id uuid;
  v_myst_nom text;
  n integer;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select * into e from quete_etat where en_cours for update;
  if not found then
    return null;
  end if;
  select * into q from quete where id = e.quete_id;
  v_avant := coalesce(e.instances_restantes, q.instances_requises);
  v_apres := greatest(v_avant - 1, 0);
  if v_apres > 0 then
    update quete_etat set instances_restantes = v_apres where quete_id = q.id;
    return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
      'avant', v_avant, 'apres', v_apres, 'termine', false);
  end if;
  -- Les récompenses (or + objets + objet mystère) ne rejoignent l'arsenal qu'à la fermeture de la
  -- fenêtre de récompenses (quete_recompenses_recuperer) : ici elles sont seulement mises en attente.
  -- Un emplacement de récompense peut contenir l'objet « Récompense mystère » (code recompense-mystere) :
  -- il n'entre jamais dans l'arsenal, mais est remplacé, quantité fois, par un objet tiré au hasard
  -- (Armes, Boucliers, Objets divers, Produits alchimiques).
  for r in
    select qr.objet_id, qr.quantite, (o.code_unique = 'recompense-mystere') as myst,
           (select ch.objet_id from quete_recompense_choix ch where ch.quete_id = qr.quete_id and ch.position = qr.position) as choix
      from quete_recompense qr join objet_catalogue o on o.id = qr.objet_id
      where qr.quete_id = q.id order by qr.position
  loop
    if r.myst and r.choix is not null then
      -- Récompense choisie par le MJ mais cachée aux joueurs (« ? ») : donnée telle quelle, sans tirage.
      select o2.nom into v_myst_nom from objet_catalogue o2 where o2.id = r.choix;
      v_items := v_items || jsonb_build_object('objet_id', r.choix, 'quantite', r.quantite, 'mystere', true, 'nom', v_myst_nom);
    elsif r.myst then
      for n in 1..r.quantite loop
        select t.id, t.nom into v_myst_id, v_myst_nom from _objet_mystere_tirer() t;
        if v_myst_id is not null then
          v_items := v_items || jsonb_build_object('objet_id', v_myst_id, 'quantite', 1, 'mystere', true, 'nom', v_myst_nom);
        end if;
      end loop;
    else
      v_items := v_items || jsonb_build_object('objet_id', r.objet_id, 'quantite', r.quantite);
    end if;
  end loop;
  for r in select position, mercenaire_id from quete_mercenaire where quete_id = q.id order by position
  loop
    v_vet_avant := _vet(r.mercenaire_id);
    select st.energie_actuelle into v_energie
      from mercenaire_etat st
      where st.mercenaire_id = r.mercenaire_id and st.session_id = ctx_session();
    if v_vet_avant > q.facteur_puissance then
      v_vet_apres := v_vet_avant;
    else
      v_vet_apres := v_vet_avant + 1;
      insert into mercenaire_etat (session_id, mercenaire_id, veterance)
        values (ctx_session(), r.mercenaire_id, v_vet_apres)
        on conflict (session_id, mercenaire_id) do update set veterance = excluded.veterance;
      v_gagnants := v_gagnants + 1;
    end if;
    -- Énergie : retour au maximum (vide = maximum).
    update mercenaire_etat set energie_actuelle = null
      where mercenaire_id = r.mercenaire_id and session_id = ctx_session();
    v_mercs := v_mercs || jsonb_build_object('mercenaire_id', r.mercenaire_id, 'position', r.position,
      'veterance_avant', v_vet_avant, 'veterance_apres', v_vet_apres, 'energie_avant', v_energie);
  end loop;
  delete from quete_mercenaire where quete_id = q.id;
  update quete_etat
    set en_cours = false, terminee_le = now(), instances_restantes = 0,
        recompenses_attente = jsonb_build_object('quete_id', q.id, 'nom', q.nom,
          'or', q.recompense_or, 'items', v_items)
    where quete_id = q.id;
  perform _journal('or',
    q.nom || ' accomplie : récompenses à récupérer, '
      || v_gagnants || ' mercenaire(s) gagnent +1 de vétérance ; l''énergie des mercenaires engagés revient au maximum.',
    0, jsonb_build_object('quete_terminee', q.id, 'mercenaires', v_mercs));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom,
    'avant', v_avant, 'apres', 0, 'termine', true,
    'or', q.recompense_or, 'items', v_items, 'mercenaires', v_mercs, 'mystere_nom', v_myst_nom,
    'attente', true);
end;
$$;

grant create on schema public to fortress_fn;
alter function quetes_instance() owner to fortress_fn;
revoke create on schema public from fortress_fn;
grant execute on function quetes_instance() to authenticated;
