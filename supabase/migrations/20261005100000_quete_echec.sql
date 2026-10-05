-- Échec d'une quête (Bruno, 2026-10-05) : le MJ peut déclarer la quête en cours « échouée » (bouton rouge
-- sur la fiche de la quête, à côté de « Réussite » qui reste le +1 Instance habituel). L'échec fait
-- avancer l'instance de 1 comme tout +1 Instance (le front appelle les autres fonctions d'instance), mais
-- ici la quête n'est PAS accomplie : aucune récompense n'est créditée, les mercenaires engagés retournent
-- à la caserne, le compteur d'instances est remis à sa valeur de départ et la quête redevient disponible.
-- Une fenêtre annonce l'échec à tous les joueurs : quete_etat.echec_attente (id unique + date) la porte ;
-- chaque joueur la ferme pour lui-même (le front retient l'id déjà vu), aucun nettoyage serveur requis.

alter table quete_etat add column if not exists echec_attente jsonb;

create or replace function quetes_echec()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  q quete%rowtype;
  v_id uuid;
begin
  if not is_admin() then
    raise exception 'Reserve a l''administrateur.';
  end if;
  perform _verrou_partie();
  select quete_id into v_id from quete_etat where en_cours for update;
  if v_id is null then
    return null;
  end if;
  select * into q from quete where id = v_id;
  delete from quete_mercenaire where quete_id = v_id;
  update quete_etat
    set en_cours = false, instances_restantes = null,
        echec_attente = jsonb_build_object('id', gen_random_uuid(), 'quete_id', q.id, 'nom', q.nom, 'le', now())
    where quete_id = v_id;
  perform _journal('or', q.nom || ' : echec de la quete. Aucune recompense ; la quete redevient disponible.',
    0, jsonb_build_object('quete_echec', q.id));
  return jsonb_build_object('quete_id', q.id, 'nom', q.nom, 'echec', true);
end;
$$;

grant create on schema public to fortress_fn;
alter function quetes_echec() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function quetes_echec() from public;
grant execute on function quetes_echec() to authenticated;
