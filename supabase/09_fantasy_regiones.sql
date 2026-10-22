-- ============ LINE & MAUL · Fantasy por región (Buenos Aires / Córdoba) ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez).
-- La tabla del Fantasy de Córdoba usa el juego 'dt_cba'. Cada región muestra solo a los que armaron equipo en sus fechas.
create or replace function public.tabla(p_juegos text[], p_fecha text, p_last text, p_club text, p_liga text, p_limit int default 100)
returns table (user_id uuid, nombre text, equipo text, club text, total int, fpts int, lpts int, plenos int, badges text[],
  rank bigint, prev_rank bigint, played_before boolean, n bigint, pos bigint)
language sql stable security definer set search_path = public
as $$
  -- Fantasy: 'dt' = Buenos Aires, 'dt_cba' = Córdoba. Cada región cuenta solo los equipos de sus fechas.
  with dt as (select exists (select 1 from unnest(p_juegos) j where j like 'dt%') as es,
                     case when 'dt_cba' = any(p_juegos) then 'cba' else 'ba' end as reg),
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
    select e.user_id from equipos e join fechas fe on fe.id = e.fecha_id, dt where dt.es and coalesce(fe.data->>'reg', 'ba') = dt.reg
      and coalesce(e.data->'picks', '{}'::jsonb) <> '{}'::jsonb
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
