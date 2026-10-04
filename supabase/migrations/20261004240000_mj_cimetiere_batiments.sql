-- Deux pouvoirs du MJ (Bruno, 2026-10-04) :
--  1. Retirer un mercenaire du cimetière : il redevient recrutable. Son équipement a déjà été rendu à
--     l'arsenal à sa mort et son recrutement supprimé ; il garde sa vétérance. Sa santé actuelle (0 PV)
--     est remise au maximum (valeur vide = maximum), sinon il retomberait au cimetière à la prochaine
--     instance dès son recrutement.
--  2. Détruire un bâtiment (Camp de Mineur, Scierie, Tannerie : objet qui sert d'outil à un métier de
--     Collecte). Il disparaît de la partie (la production redevient simple, sans le doublement du
--     bâtiment) et peut être reconstruit au prix normal. Aucun remboursement.
-- Les fonctions appartiennent à fortress_fn (isolation par session) et sont réservées au MJ.

create function cimetiere_retirer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_nom text;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select nom into v_nom from mercenaire where id = p_mercenaire;
  if v_nom is null then
    raise exception 'Mercenaire inconnu.';
  end if;
  delete from cimetiere where mercenaire_id = p_mercenaire and session_id = ctx_session();
  if not found then
    raise exception '% ne repose pas au cimetière.', v_nom;
  end if;
  update mercenaire_etat set sante_actuelle = null
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  perform _journal('equipement', v_nom || ' quitte le cimetière : il est de nouveau recrutable, à pleine santé.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'cimetiere_retire', true));
end;
$$;

create function batiment_detruire(p_objet uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_nom text;
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  select nom into v_nom from objet_catalogue where id = p_objet;
  if v_nom is null then
    raise exception 'Objet inconnu.';
  end if;
  if not exists (select 1 from objet_catalogue where emploi_outil_id = p_objet) then
    raise exception '% n''est pas un bâtiment.', v_nom;
  end if;
  delete from employe where objet_id = p_objet and outil = false;
  if not found then
    raise exception '% n''est pas construit.', v_nom;
  end if;
  perform _journal('congediement', v_nom || ' est détruit(e).', 0,
    jsonb_build_object('objet_id', p_objet, 'batiment_detruit', true));
end;
$$;

grant create on schema public to fortress_fn;
alter function cimetiere_retirer(uuid) owner to fortress_fn;
alter function batiment_detruire(uuid) owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function cimetiere_retirer(uuid) from public;
revoke all on function batiment_detruire(uuid) from public;
grant execute on function cimetiere_retirer(uuid) to authenticated;
grant execute on function batiment_detruire(uuid) to authenticated;
