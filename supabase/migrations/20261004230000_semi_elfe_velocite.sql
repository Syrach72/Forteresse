-- Compétence passive « Semi-Elfe » (Bruno, 2026-10-04) : « vous commencez votre carrière avec +1 point dans la
-- caractéristique Vélocité ». Bonus CALCULÉ et permanent (+1 dès que le mercenaire possède la compétence,
-- sans rapport avec la vétérance) : la Vélocité saisie par le joueur reste la valeur de base, et le +1 ne
-- peut pas être compté deux fois. Reprend _bonus_velocite() de 20261004220000.

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
         end
       + case when _possede_competence(p_mercenaire, array['semi-elfe']) then 1 else 0 end;
$$;
