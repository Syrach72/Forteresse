-- Embauches de Collecte verrouillées par des quêtes (Bruno, 2026-10-04) : Bûcheron, Mineur et Tanneur ne
-- peuvent plus être embauchés tant que la quête qui permet d'obtenir « un premier » ouvrier de ce métier
-- n'est pas réussie ; le déblocage est automatique.
--  * quete.debloque_objet_id : le métier que cette quête débloque (réglé par le MJ dans l'Administration).
--  * Un métier est débloqué dans la session si une quête qui le débloque y est TERMINÉE, ou s'il a déjà des
--    ouvriers embauchés (les parties en cours ne perdent pas leurs ouvriers). Le calcul est dérivé de l'état
--    des quêtes : annuler le +1 Instance qui a terminé la quête reverrouille le métier.
--  * employe_embaucher refuse un métier verrouillé (le serveur fait foi, pas seulement l'affichage).
--  * metiers_embauche() : pour chaque métier, s'il est débloqué et le nom de la quête qui le débloque.

alter table quete add column debloque_objet_id uuid references objet_catalogue (id) on delete set null;

create function _metier_debloque(p_objet uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
           select 1 from employe e
           where e.objet_id = p_objet and e.session_id = ctx_session() and e.quantite > 0)
      or exists (
           select 1 from quete q join quete_etat s on s.quete_id = q.id
           where q.debloque_objet_id = p_objet and s.session_id = ctx_session() and s.terminee_le is not null);
$$;
revoke all on function _metier_debloque(uuid) from public;
grant execute on function _metier_debloque(uuid) to authenticated, fortress_fn;

create function metiers_embauche()
returns table (objet_id uuid, debloque boolean, quete_nom text)
language sql
stable
security definer set search_path = public
as $$
  select o.id, _metier_debloque(o.id),
         (select q.nom from quete q where q.debloque_objet_id = o.id order by q.nom limit 1)
  from objet_catalogue o
  where o.emploi_materiau_id is not null
    and o.actif is not false
    and _racine_categorie(o.categorie_id) = 'Collecte';
$$;
revoke all on function metiers_embauche() from public;
grant execute on function metiers_embauche() to authenticated;

create or replace function employe_embaucher(p_objet uuid, p_quantite integer)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  o objet_catalogue%rowtype;
  v_cout integer;
  v_jid uuid;
  v_batiment boolean;
  v_deja integer;
begin
  v_or := _verrou_partie();
  if coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  select * into o from objet_catalogue where id = p_objet and actif is not false;
  if not found then
    raise exception 'Objet inconnu.';
  end if;
  if _racine_categorie(o.categorie_id) is distinct from 'Collecte' then
    raise exception 'Cet objet ne peut pas être embauché.';
  end if;
  if o.emploi_materiau_id is not null and not _metier_debloque(p_objet) then
    raise exception 'Ce métier est verrouillé : il se débloque en réussissant la quête qui permet d''obtenir un premier ouvrier.';
  end if;
  if o.cout_achat_or is null or o.cout_achat_or < 0 then
    raise exception 'Le coût d''embauche de ce métier n''est pas encore défini.';
  end if;
  select exists (select 1 from objet_catalogue where emploi_outil_id = p_objet) into v_batiment;
  if v_batiment then
    select coalesce(quantite, 0) into v_deja from employe where objet_id = p_objet and outil = false;
    if coalesce(v_deja, 0) + p_quantite > 1 then
      raise exception 'Un seul % peut être construit.', o.nom;
    end if;
  end if;
  v_cout := o.cout_achat_or * p_quantite;
  if v_or < v_cout then
    raise exception 'Vous n''avez pas assez de pièces d''or.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - v_cout where id;
  insert into employe (objet_id, outil, quantite) values (p_objet, false, p_quantite)
    on conflict (session_id, objet_id, outil) do update set quantite = employe.quantite + excluded.quantite, updated_at = now();
  v_jid := _journal('embauche', p_quantite || ' ' || o.nom || '(s) embauché(s) : −' || v_cout || ' Po.',
    -v_cout, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
  return jsonb_build_object('journal_id', v_jid, 'or', v_or - v_cout);
end;
$$;
