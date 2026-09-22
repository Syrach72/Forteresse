-- Correctif : Bruno avait deja prepare Bucheron/Mineur/Tanneur sous une
-- categorie racine "Collecte" (avec leur production decrite en texte, ex.
-- "Le Bucheron produit 10 Bois au debut de chaque Instance"), avant que la
-- categorie "Embauche" ne soit creee par erreur dans la migration
-- 20260922180000_employes.sql. On bascule le systeme sur "Collecte" (deja
-- la bonne categorie, avec les 3 metiers dedans) et on retire "Embauche",
-- inutilisee. On reprend aussi les 10 Bois/Fer/Cuir deja ecrits en texte
-- dans la description de chaque metier, comme production de base.

update objet_catalogue set emploi_materiau_id = '32dd411a-a7e3-4728-b6cc-89d286031c67', emploi_production = 10
  where id = '66895300-392b-4225-a713-aa2105151108'; -- Bucheron -> Bois
update objet_catalogue set emploi_materiau_id = 'b05c9ad6-9812-488f-8454-fc53fd2913b6', emploi_production = 10
  where id = '248df5ae-bcf9-4666-bd66-7e4933706110'; -- Mineur -> Fer
update objet_catalogue set emploi_materiau_id = 'b59e404d-9942-4e85-a543-539074c3210b', emploi_production = 10
  where id = '26819787-ec7d-4c41-9354-8b7fac530ea4'; -- Tanneur -> Cuir

delete from categorie where nom = 'Embauche' and not exists (
  select 1 from objet_catalogue where categorie_id = categorie.id
);

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
  v_cout := o.cout_achat_or * p_quantite;
  if v_or < v_cout then
    raise exception 'Vous n''avez pas assez de pièces d''or.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - v_cout where id;
  insert into employe (objet_id, outil, quantite) values (p_objet, false, p_quantite)
    on conflict (objet_id, outil) do update set quantite = employe.quantite + excluded.quantite, updated_at = now();
  v_jid := _journal('embauche', p_quantite || ' ' || o.nom || '(s) embauché(s) : −' || v_cout || ' Po.',
    -v_cout, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
  return jsonb_build_object('journal_id', v_jid, 'or', v_or - v_cout);
end;
$$;
