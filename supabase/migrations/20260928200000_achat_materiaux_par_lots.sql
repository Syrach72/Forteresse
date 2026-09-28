-- Achat des matériaux (Bois/Fer/Cuir) au Marché, par lots de 10 uniquement,
-- 10 Po le lot (règle de Bruno, 2026-09-28). Contrairement à partie_acheter
-- (1 exemplaire par clic, utilisé pour les autres rubriques), cette fonction
-- est dédiée aux Matériaux et impose un multiple de 10.

create or replace function partie_acheter_materiau(p_objet uuid, p_quantite integer)
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
  if coalesce(p_quantite, 0) < 10 or p_quantite % 10 <> 0 then
    raise exception 'Les matériaux s''achètent par lots de 10.';
  end if;
  select * into o from objet_catalogue where id = p_objet and actif is not false;
  if not found then
    raise exception 'Objet inconnu.';
  end if;
  if _racine_categorie(o.categorie_id) is distinct from 'Matériaux' then
    raise exception 'Cet objet ne s''achète pas par lots.';
  end if;
  if o.cout_achat_or is null or o.cout_achat_or < 0 then
    raise exception 'Le coût d''achat de cet objet n''est pas encore défini.';
  end if;
  v_cout := o.cout_achat_or * p_quantite;
  if v_or < v_cout then
    raise exception 'Vous n''avez pas assez de pièces d''or.';
  end if;
  update partie_etat set or_compagnie = or_compagnie - v_cout where id;
  perform _arsenal_ajouter(p_objet, p_quantite);
  v_jid := _journal('achat', p_quantite || ' ' || o.nom || ' achetés (lot de 10) : −' || v_cout || ' Po.',
    -v_cout, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite));
  return jsonb_build_object('journal_id', v_jid, 'or', v_or - v_cout);
end;
$$;

grant create on schema public to fortress_fn;
alter function partie_acheter_materiau(uuid, integer) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function partie_acheter_materiau(uuid, integer) from public;
grant execute on function partie_acheter_materiau(uuid, integer) to authenticated;
