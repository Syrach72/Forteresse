-- Corrige employe_embaucher : « there is no unique or exclusion constraint
-- matching the ON CONFLICT specification » au clic sur Embaucher (signalé par
-- Bruno). La migration 20260925230000 avait déjà corrigé cette fonction pour
-- utiliser on conflict (session_id, objet_id, outil) — la vraie contrainte
-- unique depuis le passage aux sessions (table employe, unique sur ces trois
-- colonnes). Mais ma migration 20260928160000 a réécrit employe_embaucher en
-- repartant du texte d'origine (2022-09-22), non session-aware, et a donc
-- annulé ce correctif par erreur. Remet le bon conflict target.

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
