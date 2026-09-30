-- Vente annulable (Bruno, 2026-09-30) : après une vente d'objet, une bannière propose « Annuler la vente ».
--  * partie_vendre renvoie l'identifiant du journal (journal_id) ;
--  * partie_annuler accepte le type 'vente' : l'objet (et ses gemmes) revient à l'arsenal, l'or gagné est
--    repris. Refusé si la trésorerie ne couvre plus le gain. Seul l'auteur (ou le MJ) peut annuler.
-- Reprend partie_vendre de 20260922170000 et partie_annuler de 20260921130000.

create or replace function partie_vendre(p_objet uuid, p_quantite integer, p_gemmes uuid[] default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  v_jid uuid;
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
  v_jid := _journal('vente', 'Vente de ' || o.nom || ' ×' || p_quantite || ' : +' || v_gain || ' Po.',
    v_gain, jsonb_build_object('objet_id', p_objet, 'quantite', p_quantite, 'gemmes', v_gemmes));
  return jsonb_build_object('or', v_or + v_gain, 'gain', v_gain, 'journal_id', v_jid);
end;
$$;

create or replace function partie_annuler(p_journal uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_or integer;
  j partie_journal%rowtype;
  o objet_catalogue%rowtype;
  i jsonb;
  v_message text;
  v_gemmes uuid[];
begin
  v_or := _verrou_partie();
  select * into j from partie_journal where id = p_journal for update;
  if not found then
    raise exception 'Opération introuvable.';
  end if;
  if not is_admin() and j.auteur_id is distinct from auth.uid() then
    raise exception 'Seul l''auteur de l''opération peut l''annuler.';
  end if;
  if j.annule then
    raise exception 'Cette opération est déjà annulée.';
  end if;
  if j.type not in ('achat', 'fabrication', 'vente') then
    raise exception 'Cette opération ne peut pas être annulée.';
  end if;
  select * into o from objet_catalogue where id = (j.details ->> 'objet_id')::uuid;
  if j.type = 'vente' then
    -- Vente annulée : l'objet retourne à l'arsenal, l'or gagné est repris (refusé si la trésorerie
    -- ne le couvre plus, par exemple après un achat fait entre-temps).
    if v_or < j.montant then
      raise exception 'Annulation impossible : la trésorerie ne couvre plus le montant de la vente (% Po).', j.montant;
    end if;
    v_gemmes := case when jsonb_typeof(j.details -> 'gemmes') = 'array'
      then array(select jsonb_array_elements_text(j.details -> 'gemmes')::uuid) end;
    perform _arsenal_ajouter(o.id, (j.details ->> 'quantite')::integer, v_gemmes);
    update partie_etat set or_compagnie = or_compagnie - j.montant where id;
    v_message := 'Vente annulée : objet rendu à l’arsenal, pièces d’or reprises.';
  elsif j.type = 'achat' then
    if _arsenal_quantite(o.id) < 1 then
      raise exception 'Annulation impossible : cet objet n''est plus disponible.';
    end if;
    perform _arsenal_retirer(o.id, 1);
    update partie_etat set or_compagnie = or_compagnie - j.montant where id;
    v_message := 'Achat annulé : pièces d’or remboursées.';
  else
    if (j.details ->> 'file')::boolean then
      if not exists (select 1 from atelier_fabrication where journal_id = p_journal) then
        raise exception 'Annulation impossible : la fabrication a déjà été récupérée.';
      end if;
      delete from atelier_fabrication where journal_id = p_journal;
    else
      if _arsenal_quantite(o.id) < (j.details ->> 'quantite')::integer then
        raise exception 'Annulation impossible : cet objet n''est plus disponible.';
      end if;
      perform _arsenal_retirer(o.id, (j.details ->> 'quantite')::integer);
    end if;
    for i in select * from jsonb_array_elements(j.details -> 'ingredients')
    loop
      perform _arsenal_ajouter((i ->> 'objet_id')::uuid, (i ->> 'quantite')::integer);
    end loop;
    v_message := 'Fabrication annulée : ressources restituées, atelier libéré.';
  end if;
  update partie_journal set annule = true where id = p_journal;
  perform _journal('annulation', v_message, -j.montant, jsonb_build_object('annule', p_journal));
  return jsonb_build_object('message', v_message);
end;
$$;


grant create on schema public to fortress_fn;
alter function partie_vendre(uuid, integer, uuid[]) owner to fortress_fn;
alter function partie_annuler(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
