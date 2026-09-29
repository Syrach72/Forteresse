-- Réinitialisation du compteur de round (MJ seul, avec confirmation côté interface) : remet le
-- round à 0 à tout moment. L'énergie des mercenaires n'est pas modifiée.
create or replace function round_reinitialiser()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Réservé à l''administrateur.';
  end if;
  perform _verrou_partie();
  update partie_etat set round_courant = 0 where session_id = ctx_session();
end;
$$;

grant create on schema public to fortress_fn;
alter function round_reinitialiser() owner to fortress_fn;
revoke create on schema public from fortress_fn;
revoke all on function round_reinitialiser() from public;
grant execute on function round_reinitialiser() to authenticated;
