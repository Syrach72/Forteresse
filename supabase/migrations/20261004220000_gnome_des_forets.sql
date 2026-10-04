-- Compétence passive « Gnome des Forêts » (Bruno, 2026-10-04) : +1 Vélocité tous les 3 niveaux de
-- vétérance, à partir du niveau 3, comme « Halflin Pied Léger ». Reprend _bonus_velocite() de
-- 20261004210000 en acceptant aussi cette compétence (pas de cumul : une seule race par mercenaire).

create or replace function _bonus_velocite(p_mercenaire uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select case
    when _possede_competence(p_mercenaire, array['halflin pied léger', 'gnome des forêts'])
    then _vet(p_mercenaire) / 3
    else 0
  end;
$$;
