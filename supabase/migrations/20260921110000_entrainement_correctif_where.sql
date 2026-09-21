-- Correctif de 20260921100000_entrainement.sql : depuis l'application
-- (PostgREST), Supabase refuse tout DELETE sans clause WHERE (extension
-- pg_safeupdate : « DELETE requires a WHERE clause »), meme a l'interieur
-- d'une fonction. Renvoyer l'instructeur (qui ramene tous les eleves) et le
-- declencheur de renvoi de la compagnie vidaient la table sans condition.
-- Les deux fonctions sont recreees avec une condition explicite ; rien d'autre
-- ne change (droits d'execution conserves par create or replace).

create or replace function entrainement_renvoyer(p_mercenaire uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;
  select role into v_role from entrainement_place where mercenaire_id = p_mercenaire;
  if not found then
    return;
  end if;
  if not is_admin() and not exists (
    select 1 from recrutement
    where mercenaire_id = p_mercenaire and user_id = auth.uid()
  ) then
    raise exception 'Seul son recruteur peut renvoyer ce mercenaire.';
  end if;
  if v_role = 'instructeur' then
    delete from entrainement_place where role in ('instructeur', 'eleve');
  else
    delete from entrainement_place where mercenaire_id = p_mercenaire;
  end if;
end;
$$;

create or replace function entrainement_apres_renvoi()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if exists (
    select 1 from entrainement_place
    where role = 'instructeur' and mercenaire_id = old.mercenaire_id
  ) then
    delete from entrainement_place where role in ('instructeur', 'eleve');
  else
    delete from entrainement_place where mercenaire_id = old.mercenaire_id;
  end if;
  return old;
end;
$$;
