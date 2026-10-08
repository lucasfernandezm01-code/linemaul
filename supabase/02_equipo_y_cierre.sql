alter table public.profiles add column if not exists equipo text;
create or replace function public.fecha_abierta(fid text) returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.fechas f where f.id = fid
  and coalesce(f.data->>'estado','abierta') not in ('cerrada','final')
  and ((coalesce(f.data->>'estado','') = 'abierta' and coalesce((f.data->>'manual')::boolean, false))
    or ((f.abre is null or now() >= f.abre) and (f.cierra is null or now() < f.cierra)))) $$;
