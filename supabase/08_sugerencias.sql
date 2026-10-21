-- ============ LINE & MAUL · buzón de sugerencias ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez).
-- Cualquier usuario con cuenta puede mandar sugerencias (máx. 5 por día). Solo el admin las lee, las marca y las borra.
create table if not exists public.sugerencias (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  tipo text not null default 'idea' check (tipo in ('idea','mejora','ayuda','otro')),
  texto text not null check (char_length(texto) between 3 and 1000),
  leida boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists sugerencias_fecha on public.sugerencias (created_at desc);
alter table public.sugerencias enable row level security;
-- cuántas mandó el usuario en las últimas 24 h (la política no puede leer la tabla por RLS, por eso va en una función)
create or replace function public.sug_hoy() returns int language sql stable security definer set search_path = public
as $$ select count(*)::int from sugerencias where user_id = auth.uid() and created_at > now() - interval '1 day' $$;
drop policy if exists "sugerencias: mandar" on public.sugerencias;
create policy "sugerencias: mandar" on public.sugerencias for insert to authenticated
  with check (user_id = auth.uid() and leida = false
    and public.sug_hoy() < 5);
drop policy if exists "sugerencias: admin" on public.sugerencias;
create policy "sugerencias: admin" on public.sugerencias for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.sugerencias to authenticated;
