-- ============ LINE & MAUL · métricas del Panel Admin por región ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez).
-- p_reg: 'ba' (Buenos Aires), 'cba' (Córdoba) o 'all' (total). p_cba: clubes de Córdoba (para saber de qué región es cada usuario).
-- Un usuario es de una región si su club es de ahí, o si armó un XV o un prode de esa región.
create or replace function public.metricas_reg(p_cur text, p_reg text, p_cba text[]) returns jsonb
language plpgsql stable security definer set search_path = public
as $$ declare out jsonb; cs text[];
begin
  if not public.is_admin() then raise exception 'no autorizado'; end if;
  cs := case p_reg when 'cba' then array['cba'] when 'ba' then array['top14','a'] else null end;
  with fx as (select id from fechas where p_reg = 'all' or coalesce(data->>'reg', 'ba') = p_reg),
  xv as (select distinct e.user_id, e.fecha_id from equipos e join fx on fx.id = e.fecha_id
         where coalesce(e.data->'picks', '{}'::jsonb) <> '{}'::jsonb),
  pr as (select distinct p.user_id, p.fecha_id from prode p join fechas f on f.id = p.fecha_id
         where jsonb_typeof(p.data) = 'object' and p.data <> '{}'::jsonb and (cs is null or exists (
           select 1 from jsonb_object_keys(p.data) k
           join jsonb_array_elements(case when jsonb_typeof(f.data->'partidos') = 'array' then f.data->'partidos' else '[]'::jsonb end) m on m->>'id' = k
           where coalesce(nullif(m->>'c', ''), 'top14') = any(cs)))),
  pf as (select pp.* from profiles pp where p_reg = 'all'
           or (coalesce(pp.club, '') <> '' and (case when pp.club = any(p_cba) then 'cba' else 'ba' end) = p_reg)
           or exists (select 1 from xv where xv.user_id = pp.id) or exists (select 1 from pr where pr.user_id = pp.id))
  select jsonb_build_object(
    'users', (select count(*) from pf),
    'xv_ever', (select count(distinct user_id) from xv),
    'pr_ever', (select count(distinct user_id) from pr),
    'new7', (select count(*) from pf where created_at >= now() - interval '7 days'),
    'new30', (select count(*) from pf where created_at >= now() - interval '30 days'),
    'weeks', (select jsonb_agg(c order by w) from (select w, (select count(*) from pf where created_at >= now() - ((w + 1) * interval '7 days') and created_at < now() - (w * interval '7 days')) as c from generate_series(0, 9) w) s),
    'por_fecha', (select coalesce(jsonb_object_agg(f.id, jsonb_build_array(coalesce(a.n, 0), coalesce(b.n, 0))), '{}'::jsonb)
        from fechas f left join (select fecha_id, count(*) n from xv group by 1) a on a.fecha_id = f.id
        left join (select fecha_id, count(*) n from pr group by 1) b on b.fecha_id = f.id),
    'clubs', (select coalesce(jsonb_object_agg(club, n), '{}'::jsonb) from (select club, count(*) n from pf where coalesce(club, '') <> '' group by club) c),
    'ligas', (select coalesce(jsonb_agg(jsonb_build_object('code', l.code, 'nombre', l.nombre, 'juego', l.juego, 'owner', (select equipo from profiles where id = l.owner), 'n', (select count(*) from liga_miembros m where m.code = l.code))), '[]'::jsonb)
        from ligas l where p_reg = 'all' or (case when 'cba' = any(l.comps) then 'cba' else 'ba' end) = p_reg),
    'recent', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'equipo', p.equipo, 'club', p.club, 'creado', p.created_at,
          'xv', exists (select 1 from xv where xv.user_id = p.id and xv.fecha_id = p_cur),
          'pr', exists (select 1 from pr where pr.user_id = p.id and pr.fecha_id = p_cur),
          'nl', (select count(*) from liga_miembros m where m.user_id = p.id)) as x
        from pf p order by p.created_at desc limit 300) s)
  ) into out;
  return out;
end $$;
grant execute on function public.metricas_reg(text, text, text[]) to authenticated;
