-- Terrain favori du Druide « Cercle de la Terre » (Bruno, 2026-10-13) : un terrain favori au recrutement, puis un
-- de plus aux vétérances 4, 6, 8 et 10 (jusqu'à 5). Même table, même panneau et mêmes types que l'Explorateur-né
-- du Rôdeur (1 / vétérance 4 / vétérance 8), sans exiger la compétence.

do $$
declare
  c record;
begin
  for c in select conname from pg_constraint
    where conrelid = 'mercenaire_terrain_favori'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%rang%'
  loop
    execute format('alter table mercenaire_terrain_favori drop constraint %I', c.conname);
  end loop;
end;
$$;
alter table mercenaire_terrain_favori add constraint mercenaire_terrain_favori_rang_check check (rang between 1 and 5);

create or replace function terrain_favori_choisir(p_mercenaire uuid, p_type text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_vet integer;
  v_n integer;
  v_rang integer;
  v_nom text;
  v_requis integer;
  v_classe text;
  v_sous text;
  v_druide boolean;
  v_rangs integer[];
begin
  perform _verrou_partie();
  perform _droit_mercenaire(p_mercenaire);
  if p_type is null or p_type not in ('arctique', 'désert', 'forêt', 'littoral', 'marais', 'montagne', 'plaine', 'outreterre') then
    raise exception 'Choisissez un type de terrain dans la liste.';
  end if;
  select translate(lower(coalesce(c.nom, '')), 'êîéèô', 'eieeo'),
         translate(lower(btrim(coalesce(m.sous_classe, ''))), 'êîéèô', 'eieeo')
    into v_classe, v_sous
    from mercenaire m left join classe c on c.id = m.classe_id
    where m.id = p_mercenaire;
  v_druide := v_classe = 'druide' and v_sous = 'cercle de la terre';
  if v_druide then
    v_rangs := array[1, 4, 6, 8, 10];
  else
    if not _possede_competence(p_mercenaire, array['explorateur-né']) then
      raise exception 'Ce mercenaire ne possède pas la compétence Explorateur-né.';
    end if;
    v_rangs := array[1, 4, 8];
  end if;
  v_vet := _vet(p_mercenaire);
  select count(*) into v_n from mercenaire_terrain_favori
    where mercenaire_id = p_mercenaire and session_id = ctx_session();
  v_rang := v_n + 1;
  if v_rang > array_length(v_rangs, 1) then
    raise exception 'Les % terrains favoris de ce mercenaire sont déjà choisis.', array_length(v_rangs, 1);
  end if;
  v_requis := v_rangs[v_rang];
  if v_vet < v_requis then
    raise exception 'Le prochain terrain favori se choisit à la vétérance %.', v_requis;
  end if;
  if exists (select 1 from mercenaire_terrain_favori
             where mercenaire_id = p_mercenaire and session_id = ctx_session() and type = p_type) then
    raise exception 'Ce terrain favori est déjà choisi pour ce mercenaire : choisissez un autre terrain.';
  end if;
  insert into mercenaire_terrain_favori (mercenaire_id, rang, type) values (p_mercenaire, v_rang, p_type);
  select nom into v_nom from mercenaire where id = p_mercenaire;
  perform _journal('equipement', v_nom || ' : terrain favori n°' || v_rang || ' = ' || p_type || '.', 0,
    jsonb_build_object('mercenaire_id', p_mercenaire, 'terrain_favori', p_type, 'rang', v_rang));
  return jsonb_build_object('rang', v_rang, 'type', p_type);
end;
$$;
