-- Portrait en miroir (Bruno, 2026-10-13) : case à cocher dans l'administration des mercenaires. L'image d'origine
-- n'est pas modifiée ; l'affichage la retourne (gauche-droite) partout où le portrait apparaît.
alter table mercenaire add column portrait_miroir boolean not null default false;
