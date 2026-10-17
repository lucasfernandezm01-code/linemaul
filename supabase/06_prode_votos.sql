-- ============ LINE & MAUL · votos del prode (métricas del admin) ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez).
-- Cuántos eligieron a cada equipo (o empate) en cada partido de una fecha, y con qué diferencia.
create or replace function public.prode_votos(p_fid text) returns table (partido text, w text, d int, n bigint)
language sql stable security definer set search_path = public
as $$ select x.k, x.v->>'w', case when (x.v->>'d') ~ '^[0-9]+$' then (x.v->>'d')::int else 0 end, count(*)
  from prode p, jsonb_each(p.data) as x(k, v)
  where public.is_admin() and p.fecha_id = p_fid and jsonb_typeof(x.v) = 'object' and x.v->>'w' in ('L', 'V', 'E')
  group by 1, 2, 3 $$;
grant execute on function public.prode_votos(text) to authenticated;
