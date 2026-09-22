-- Une arme sertie vaut plus cher a la revente (regle de Bruno) : son prix de
-- revente habituel (moitie de la valeur) est multiplie par 2 pour 1 gemme,
-- 3 pour 2 gemmes, 5 pour 3 gemmes.
create or replace function partie_vendre(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  o objet_catalogue%rowtype;
  v_gain integer;
  v_gemmes uuid[] := nullif(p_gemmes, '{}'::uuid[]);
  v_mult numeric := case coalesce(array_length(v_gemmes, 1), 0)
    when 1 then 2 when 2 then 3 when 3 then 5 else 1 end;
begin
  v_or := _verrou_partie();
  select * into o from objet_catalogue where id = p_objet;
  if not found or coalesce(p_quantite, 0) < 1 then
    raise exception 'Quantité invalide.';
  end if;
  if _arsenal_quantite(p_objet, v_gemmes) < p_quantite then
    raise exception 'Quantité invalide : cet objet n''est pas disponible en telle quantité dans l''arsenal.';
  end if;
  if o.cout_achat_or is null then
    raise exception 'La valeur de cet objet n''est pas définie : vente impossible.';
  end if;
  v_gain := floor((o.cout_achat_or * p_quantite * v_mult) / 2.0);
  perform _arsenal_retirer(p_objet, p_quantite, v_gemmes);
  update partie_etat set or_compagnie = or_compagnie + v_gain where id;
  perform _journal('vente', 'Vente de ' || o.nom || ' ×' || p_quantite || ' : +' || v_gain || ' Po.',
    v_gain, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite, 'gemmes', v_gemmes));
  return jsonb_build_object('or', v_or + v_gain, 'gain', v_gain);
end;
$$;
