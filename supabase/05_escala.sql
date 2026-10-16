-- ============ LINE & MAUL · preparado para muchos usuarios ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez; se puede volver a correr).
-- Las tablas de posiciones se calculan en la base: cada celular baja solo lo que ve.

-- Puntos de cada usuario en cada fecha y juego ('dt' = Fantasy; 'top14', 'primeraA' = Prode).
-- Los escribe el admin al publicar una fecha.
create table if not exists public.puntos (
  user_id uuid not null references auth.users on delete cascade,
  juego text not null,
  fecha_id text not null references public.fechas on delete cascade,
  pts int not null default 0,
  extra jsonb not null default '{}'::jsonb,
  primary key (user_id, juego, fecha_id)
);
create index if not exists puntos_juego_fecha on public.puntos (juego, fecha_id);

-- Insignias de cada fecha publicada (Fantasy).
create table if not exists public.insignias (
  user_id uuid not null references auth.users on delete cascade,
  juego text not null,
  fecha_id text not null references public.fechas on delete cascade,
  b text[] not null default '{}',
  primary key (user_id, juego, fecha_id)
);

create index if not exists equipos_fecha on public.equipos (fecha_id);
create index if not exists prode_fecha on public.prode (fecha_id);
create index if not exists miembros_user on public.liga_miembros (user_id);
create index if not exists profiles_club on public.profiles (lower(club));

alter table public.puntos enable row level security;
alter table public.insignias enable row level security;
drop policy if exists "puntos: todos leen" on public.puntos;
drop policy if exists "puntos: admin" on public.puntos;
drop policy if exists "insignias: todos leen" on public.insignias;
drop policy if exists "insignias: admin" on public.insignias;
create policy "puntos: todos leen" on public.puntos for select to anon, authenticated using (true);
create policy "puntos: admin" on public.puntos for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "insignias: todos leen" on public.insignias for select to anon, authenticated using (true);
create policy "insignias: admin" on public.insignias for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select on public.puntos, public.insignias to anon, authenticated;
grant insert, update, delete on public.puntos, public.insignias to authenticated;

-- Tabla de posiciones ya calculada.
--   p_juegos: {'dt'} o las competencias del prode, p.ej. {'top14','primeraA'}
--   p_fecha:  null = tabla general; si no, la tabla de esa fecha
--   p_last:   última fecha publicada (para la columna "Últ." y las flechas)
--   p_club / p_liga: filtros (tabla del club o torneo privado)
--   p_limit:  cuántos devolver (siempre agrega tu propia fila)
create or replace function public.tabla(p_juegos text[], p_fecha text, p_last text, p_club text, p_liga text, p_limit int default 100)
returns table (user_id uuid, nombre text, equipo text, club text, total int, fpts int, lpts int, plenos int, badges text[],
  rank bigint, prev_rank bigint, played_before boolean, n bigint, pos bigint)
language sql stable security definer set search_path = public
as $$
  with dt as (select 'dt' = any(p_juegos) as es),
  base as (
    select p.user_id, sum(p.pts)::int as total,
      coalesce(sum(p.pts) filter (where p.fecha_id = p_fecha), 0)::int as fpts,
      coalesce(sum(p.pts) filter (where p.fecha_id = p_last), 0)::int as lpts,
      coalesce(sum(coalesce((p.extra->>'pl')::int, 0)), 0)::int as plenos,
      bool_or(p.fecha_id is distinct from p_last) as played_before,
      bool_or(p.fecha_id = p_fecha) as en_fecha
    from puntos p where p.juego = any(p_juegos) group by p.user_id
  ),
  -- los que participaron aunque todavía no tengan puntos publicados
  part as (
    select e.user_id from equipos e, dt where dt.es and coalesce(e.data->'picks', '{}'::jsonb) <> '{}'::jsonb
      and (p_fecha is null or (e.fecha_id = p_fecha and (not public.fecha_abierta(p_fecha) or e.user_id = auth.uid())))
    union
    select r.user_id from prode r, dt where not dt.es and r.comps && p_juegos
      and (p_fecha is null or (r.fecha_id = p_fecha and (not public.fecha_abierta(p_fecha) or r.user_id = auth.uid())))
  ),
  u as (
    select coalesce(b.user_id, pa.user_id) as user_id, coalesce(b.total, 0) as total,
      case when p_fecha is null then 0 else coalesce(b.fpts, 0) end as fpts,
      coalesce(b.lpts, 0) as lpts, coalesce(b.plenos, 0) as plenos, coalesce(b.played_before, false) as played_before,
      (p_fecha is null or coalesce(b.en_fecha, false) or pa.user_id is not null) as armo
    from base b full join (select distinct part.user_id from part) pa on pa.user_id = b.user_id
  ),
  f as (
    select u.*, pr.nombre, pr.equipo, pr.club from u join profiles pr on pr.id = u.user_id
    where u.armo
      and (p_club is null or lower(pr.club) = lower(p_club))
      and (p_liga is null or exists (select 1 from liga_miembros m where m.code = p_liga and m.user_id = u.user_id))
  ),
  r as (
    select f.*,
      rank() over (order by (case when p_fecha is null then f.total else f.fpts end) desc) as rk,
      rank() over (order by (f.total - f.lpts) desc) as prk,
      row_number() over (order by (case when p_fecha is null then f.total else f.fpts end) desc, f.total desc, lower(coalesce(f.equipo, f.nombre, ''))) as rn,
      count(*) over () as cnt
    from f
  )
  select r.user_id, r.nombre, r.equipo, r.club, r.total, r.fpts, r.lpts, r.plenos,
    (select i.b from insignias i where i.user_id = r.user_id and i.juego = 'dt' and i.fecha_id = coalesce(p_fecha, p_last)),
    r.rk, r.prk, r.played_before, r.cnt, r.rn
  from r where r.rn <= greatest(p_limit, 1) or r.user_id = auth.uid()
  order by r.rn
$$;

-- Insignias de una fecha (las calcula la base cuando el admin publica).
--   p_prev: fechas publicadas anteriores, en orden
create or replace function public.calc_insignias(p_fid text, p_prev text[]) returns int
language plpgsql security definer set search_path = public
as $$ declare mx int; n int;
begin
  if not public.is_admin() then raise exception 'no autorizado'; end if;
  delete from insignias where juego = 'dt' and fecha_id = p_fid;
  create temp table if not exists _ins (user_id uuid, b text) on commit drop;
  truncate _ins;
  with t as (
    select user_id,
      sum(pts) as now_t,
      coalesce(sum(pts) filter (where fecha_id = any(coalesce(p_prev, '{}'))), 0) as prev_t,
      bool_or(fecha_id = any(coalesce(p_prev, '{}'))) as pb
    from puntos where juego = 'dt' and (fecha_id = p_fid or fecha_id = any(coalesce(p_prev, '{}'))) group by user_id
  ), rk as (
    select t.*, rank() over (order by prev_t desc) as r_prev, rank() over (order by now_t desc) as r_now from t
  )
  insert into _ins
    select user_id, 'lider' from t where now_t = (select max(now_t) from t) and now_t > 0
    union all
    select user_id, 'racha' from rk where pb and (r_prev - r_now) = (select max(r_prev - r_now) from rk where pb) and (r_prev - r_now) > 0;
  insert into _ins
    select user_id, 'mvp' from puntos where juego = 'dt' and fecha_id = p_fid
      and pts = (select max(pts) from puntos where juego = 'dt' and fecha_id = p_fid) and pts > 0;
  insert into _ins
    select user_id, 'ojo' from puntos where juego = 'dt' and fecha_id = p_fid and extra ? 'cap'
      and (extra->>'cap')::int = (select max((extra->>'cap')::int) from puntos where juego = 'dt' and fecha_id = p_fid and extra ? 'cap')
      and (extra->>'cap')::int > 0;
  insert into insignias (user_id, juego, fecha_id, b)
    select user_id, 'dt', p_fid, array_agg(b order by array_position(array['lider','mvp','racha','ojo'], b)) from _ins group by user_id;
  get diagnostics n = row_count;
  return n;
end $$;

-- Para el admin: los equipos de una fecha (para calcular puntos), sin bajar todo.
create or replace function public.picks_fecha(p_fid text) returns table (pid text)
language sql stable security definer set search_path = public
as $$ select distinct v.value #>> '{}' from equipos e, jsonb_each(coalesce(e.data->'picks', '{}'::jsonb)) v
  where public.is_admin() and e.fecha_id = p_fid $$;

-- Para el admin: cuántos armaron Fantasy y Prode en cada fecha.
create or replace function public.conteos() returns table (fecha_id text, xv bigint, pr bigint)
language sql stable security definer set search_path = public
as $$ select f.id,
    (select count(*) from equipos e where e.fecha_id = f.id and coalesce(e.data->'picks', '{}'::jsonb) <> '{}'::jsonb),
    (select count(*) from prode p where p.fecha_id = f.id and coalesce(p.data, '{}'::jsonb) <> '{}'::jsonb)
  from fechas f where public.is_admin() $$;

-- Para el admin: métricas generales.
create or replace function public.metricas(p_cur text) returns jsonb
language plpgsql stable security definer set search_path = public
as $$ declare out jsonb;
begin
  if not public.is_admin() then raise exception 'no autorizado'; end if;
  with xv as (select distinct user_id, fecha_id from equipos where coalesce(data->'picks', '{}'::jsonb) <> '{}'::jsonb),
       pr as (select distinct user_id, fecha_id from prode where coalesce(data, '{}'::jsonb) <> '{}'::jsonb)
  select jsonb_build_object(
    'users', (select count(*) from profiles),
    'xv_ever', (select count(distinct user_id) from xv),
    'pr_ever', (select count(distinct user_id) from pr),
    'new7', (select count(*) from profiles where created_at >= now() - interval '7 days'),
    'new30', (select count(*) from profiles where created_at >= now() - interval '30 days'),
    'weeks', (select jsonb_agg(c order by w) from (select w, (select count(*) from profiles where created_at >= now() - ((w + 1) * interval '7 days') and created_at < now() - (w * interval '7 days')) as c from generate_series(0, 9) w) s),
    'por_fecha', (select coalesce(jsonb_object_agg(f.id, jsonb_build_array(coalesce(a.n, 0), coalesce(b.n, 0))), '{}'::jsonb)
        from fechas f left join (select fecha_id, count(*) n from xv group by 1) a on a.fecha_id = f.id
        left join (select fecha_id, count(*) n from pr group by 1) b on b.fecha_id = f.id),
    'clubs', (select coalesce(jsonb_object_agg(club, n), '{}'::jsonb) from (select club, count(*) n from profiles where coalesce(club, '') <> '' group by club) c),
    'ligas', (select coalesce(jsonb_agg(jsonb_build_object('code', l.code, 'nombre', l.nombre, 'juego', l.juego, 'owner', (select equipo from profiles where id = l.owner), 'n', (select count(*) from liga_miembros m where m.code = l.code))), '[]'::jsonb) from ligas l),
    'recent', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'equipo', p.equipo, 'club', p.club, 'creado', p.created_at,
          'xv', exists (select 1 from xv where xv.user_id = p.id and xv.fecha_id = p_cur),
          'pr', exists (select 1 from pr where pr.user_id = p.id and pr.fecha_id = p_cur),
          'nl', (select count(*) from liga_miembros m where m.user_id = p.id)) as x
        from profiles p order by p.created_at desc limit 300) s)
  ) into out;
  return out;
end $$;

-- Para el admin: jugadores más elegidos (solo titulares) en un grupo de fechas.
create or replace function public.mas_elegidos(p_fids text[]) returns jsonb
language plpgsql stable security definer set search_path = public
as $$ declare out jsonb;
begin
  if not public.is_admin() then raise exception 'no autorizado'; end if;
  with e as (select data from equipos where fecha_id = any(p_fids) and coalesce(data->'picks', '{}'::jsonb) <> '{}'::jsonb),
       pk as (select v.key::int as slot, v.value #>> '{}' as pid from e, jsonb_each(e.data->'picks') v where v.key ~ '^\d+$' and v.key::int between 1 and 15 and jsonb_typeof(v.value) = 'string')
  select jsonb_build_object(
    'teams', (select count(*) from e),
    'slot', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select slot || '|' || pid as k, count(*) n from pk group by slot, pid) s),
    'cap', (select coalesce(jsonb_object_agg(c, n), '{}'::jsonb) from (select data->>'cap' c, count(*) n from e where data->>'cap' is not null group by 1) s),
    'hc', (select coalesce(jsonb_object_agg(c, n), '{}'::jsonb) from (select data->>'hc' c, count(*) n from e where data->>'hc' is not null group by 1) s)
  ) into out;
  return out;
end $$;

-- Para unirse a un torneo privado con el código (sin bajar todos los torneos).
create or replace function public.liga_por_codigo(p_code text) returns table (code text, juego text, nombre text, comps text[], owner uuid)
language sql stable security definer set search_path = public
as $$ select code, juego, nombre, comps, owner from ligas where code = upper(p_code) $$;

grant execute on function public.tabla(text[], text, text, text, text, int), public.liga_por_codigo(text) to anon, authenticated;
grant execute on function public.calc_insignias(text, text[]), public.picks_fecha(text), public.conteos(), public.metricas(text), public.mas_elegidos(text[]) to authenticated;
