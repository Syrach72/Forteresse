-- Armes : cellule "Deux Mains" (oui/non) dans le catalogue admin.
-- Booleen, jamais nul, faux par defaut : seules les armes la renseignent,
-- les autres categories l'ignorent (comme allonge/type_degats).

alter table objet_catalogue
  add column deux_mains boolean not null default false;
