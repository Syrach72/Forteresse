-- Créatures : ajustements demandés par Bruno (2026-10-02).
--  * Les 12 icônes cliquables d'une créature viennent des COMPÉTENCES des mercenaires, qui sont des objets du
--    catalogue (rubriques « Compétences Actives » / « Compétences Passives » : nom, description, icône) :
--    creature_icone référence désormais competence_id -> objet_catalogue. La table est vide à ce jour
--    (garde-fou ci-dessous).
--  * Le texte d'une capacité/action/réaction est REPRIS d'un titre déjà utilisé mais modifiable pour une
--    seule créature : creature_capacite.texte (null = suit le texte commun de capacite_creature ; sinon
--    adaptation propre à cette créature). Le texte commun se corrige à part (bouton « Appliquer à toutes »).

do $$
begin
  if exists (select 1 from creature_icone) then
    raise exception 'creature_icone contient des lignes : migration à adapter à la main.';
  end if;
end;
$$;

alter table creature_icone drop column capacite_id;
alter table creature_icone add column competence_id uuid not null references objet_catalogue (id) on delete cascade;

alter table creature_capacite add column texte text;
