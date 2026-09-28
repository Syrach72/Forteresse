-- Économie de la Collecte (règle de Bruno, 2026-09-28) :
-- - Bûcheron/Mineur/Tanneur : embauche 100 Po (au lieu de 300), entretien
--   10 Po/instance (déjà le cas pour Bûcheron/Mineur ; complété pour Tanneur).
-- - Scierie/Camp de Mineur/Tannerie : 1000 Po, un seul exemplaire par partie
--   (bâtiment, pas un employé qu'on peut recruter en nombre). Tant qu'il est
--   possédé, il double la production du métier associé.
-- - Production par instance : aléatoire entre 5 et 10 unités, tirée
--   indépendamment pour chaque ouvrier et à chaque instance (un Bûcheron peut
--   très bien produire 7 quand le Mineur en produit 10 dans la même
--   instance). Ceci remplace la production fixe (emploi_production) pour ces
--   trois métiers seulement ; les colonnes emploi_production/
--   emploi_production_outil sont vidées pour eux (elles ne servent plus à
--   rien, pour ne pas laisser une valeur trompeuse visible dans l'admin).
--
-- Le lien métier -> bâtiment (emploi_outil_id) n'était câblé que pour
-- Bûcheron -> Scierie. On le complète pour Mineur -> Camp de Mineur et
-- Tanneur -> Tannerie, sur le même principe.
--
-- Le mécanisme précédent (employe_equiper_outil, qui consommait l'outil
-- depuis l'arsenal pour "équiper" des ouvriers un par un) ne correspond plus
-- à "un seul bâtiment, qui profite à tout le métier" : on ne le supprime pas
-- (il ne fait de mal à personne, inutilisé), mais employes_instance() ne s'en
-- sert plus pour ces trois métiers — le bonus s'applique dès que le bâtiment
-- est possédé (quantité >= 1), sans étape d'équipement séparée.

update objet_catalogue set cout_achat_or = 100
  where id in (
    '79dbcc99-6575-4b81-864f-0e7d75ba7fd0', -- Bucheron
    '01ee1d40-839b-4d9f-854c-37792d23d52d', -- Mineur
    '7c5b5fb4-ba81-414c-9deb-3cea1d365156'  -- Tanneur
  );

update objet_catalogue set cout_achat_or = 1000
  where id in (
    '7f83a81a-95d8-4bff-88c0-3067c3bde1a4', -- Scierie
    'ee5d0c5b-c035-4e63-9cae-9e59c7ff0b59', -- Camp de Mineur
    '2c1e6724-8279-4978-ad88-ee1f726cf0dd'  -- Tannerie
  );

update objet_catalogue set emploi_entretien = 10
  where id in (
    '79dbcc99-6575-4b81-864f-0e7d75ba7fd0', -- Bucheron
    '01ee1d40-839b-4d9f-854c-37792d23d52d', -- Mineur
    '7c5b5fb4-ba81-414c-9deb-3cea1d365156'  -- Tanneur
  );

update objet_catalogue set emploi_outil_id = '7f83a81a-95d8-4bff-88c0-3067c3bde1a4' -- Scierie
  where id = '79dbcc99-6575-4b81-864f-0e7d75ba7fd0'; -- Bucheron
update objet_catalogue set emploi_outil_id = 'ee5d0c5b-c035-4e63-9cae-9e59c7ff0b59' -- Camp de Mineur
  where id = '01ee1d40-839b-4d9f-854c-37792d23d52d'; -- Mineur
update objet_catalogue set emploi_outil_id = '2c1e6724-8279-4978-ad88-ee1f726cf0dd' -- Tannerie
  where id = '7c5b5fb4-ba81-414c-9deb-3cea1d365156'; -- Tanneur

update objet_catalogue set emploi_production = null, emploi_production_outil = null
  where id in (
    '79dbcc99-6575-4b81-864f-0e7d75ba7fd0', -- Bucheron
    '01ee1d40-839b-4d9f-854c-37792d23d52d', -- Mineur
    '7c5b5fb4-ba81-414c-9deb-3cea1d365156'  -- Tanneur
  );

-- Embauche : un bâtiment (Scierie/Camp de Mineur/Tannerie — repéré par le
-- fait qu'un autre objet le référence comme emploi_outil_id) est limité à un
-- seul exemplaire par partie.
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
    on conflict (objet_id, outil) do update set quantite = employe.quantite + excluded.quantite, updated_at = now();
  v_jid := _journal('embauche', p_quantite || ' ' || o.nom || '(s) embauché(s) : −' || v_cout || ' Po.',
    -v_cout, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
  return jsonb_build_object('journal_id', v_jid, 'or', v_or - v_cout);
end;
$$;

-- Production et entretien, +1 Instance : les trois métiers de Collecte
-- produisent un nombre aléatoire (5 à 10) d'unités par ouvrier, tiré
-- indépendamment à chaque instance ; doublé si le bâtiment associé est
-- possédé. Les autres employés éventuels (futurs) gardent la formule fixe
-- précédente (emploi_production).
create or replace function employes_instance()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  o objet_catalogue%rowtype;
  v_gains jsonb := '[]'::jsonb;
  v_production integer;
  v_entretien integer;
  v_total_entretien integer := 0;
  v_batiment_possede boolean;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  for r in select * from employe where quantite > 0 order by objet_id, outil for update
  loop
    select * into o from objet_catalogue where id = r.objet_id;
    if _racine_categorie(o.categorie_id) = 'Collecte' and o.emploi_materiau_id is not null then
      select coalesce(sum((floor(random() * 6) + 5)::integer), 0) into v_production
        from generate_series(1, r.quantite);
      if o.emploi_outil_id is not null then
        select exists (
          select 1 from employe where objet_id = o.emploi_outil_id and quantite >= 1
        ) into v_batiment_possede;
        if v_batiment_possede then
          v_production := v_production * 2;
        end if;
      end if;
    else
      v_production := r.quantite * (coalesce(o.emploi_production, 0)
        + case when r.outil then coalesce(o.emploi_production_outil, 0) else 0 end);
    end if;
    v_entretien := r.quantite * coalesce(o.emploi_entretien, 0);
    if v_production > 0 and o.emploi_materiau_id is not null then
      perform _arsenal_ajouter(o.emploi_materiau_id, v_production);
    end if;
    v_total_entretien := v_total_entretien + v_entretien;
    v_gains := v_gains || jsonb_build_object(
      'objet_id', r.objet_id, 'outil', r.outil,
      'materiau_id', o.emploi_materiau_id, 'produit', v_production, 'entretien', v_entretien);
  end loop;
  if v_total_entretien > 0 then
    update partie_etat set or_compagnie = or_compagnie - v_total_entretien where id;
  end if;
  if jsonb_array_length(v_gains) > 0 then
    perform _journal('production', 'Production des employés : entretien −' || v_total_entretien || ' Po.',
      -v_total_entretien, jsonb_build_object('gains', v_gains));
  end if;
  return v_gains;
end;
$$;

revoke all on function employe_embaucher(uuid, integer) from public;
grant execute on function employe_embaucher(uuid, integer) to authenticated;
revoke all on function employes_instance() from public;
grant execute on function employes_instance() to authenticated;
