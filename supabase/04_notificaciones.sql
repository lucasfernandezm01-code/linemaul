-- ============ LINE & MAUL · notificaciones push ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez).

-- Celulares que activaron las notificaciones (uno por dispositivo).
create table if not exists public.push_subs (
  endpoint text primary key,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  sub jsonb not null,
  prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.push_subs enable row level security;
drop policy if exists "push: ver propio" on public.push_subs;
drop policy if exists "push: crear propio" on public.push_subs;
drop policy if exists "push: cambiar propio" on public.push_subs;
drop policy if exists "push: borrar propio" on public.push_subs;
create policy "push: ver propio" on public.push_subs for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "push: crear propio" on public.push_subs for insert to authenticated with check (user_id = auth.uid());
create policy "push: cambiar propio" on public.push_subs for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "push: borrar propio" on public.push_subs for delete to authenticated using (user_id = auth.uid());

-- Avisos manuales que el admin manda desde el sitio.
create table if not exists public.push_queue (
  id bigint generated always as identity primary key,
  title text not null,
  body text not null,
  url text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  sent_count int
);
alter table public.push_queue enable row level security;
drop policy if exists "cola: admin" on public.push_queue;
create policy "cola: admin" on public.push_queue for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Registro para no mandar dos veces el mismo aviso.
create table if not exists public.push_log (key text primary key, sent_at timestamptz not null default now());
alter table public.push_log enable row level security;

-- Clave del robot que envía (solo se guarda su huella).
create table if not exists public.push_secret (id int primary key default 1, hash text not null);
alter table public.push_secret enable row level security;
insert into public.push_secret (id, hash) values (1, '8fcfcb587001f9ba521fcc4f917e5f62fb206355bb6f01e12436cd01c1c50106')
  on conflict (id) do update set hash = excluded.hash;

create or replace function public.push_ok(tok text) returns boolean
language sql stable security definer set search_path = public, extensions
as $$ select exists (select 1 from public.push_secret where hash = encode(extensions.digest(tok, 'sha256'), 'hex')) $$;

-- Para el robot: a quién mandar y qué le falta en la fecha.
create or replace function public.push_targets(tok text, fid text)
returns table (endpoint text, sub jsonb, prefs jsonb, has_xv boolean, has_prode boolean)
language plpgsql stable security definer set search_path = public, extensions
as $$ begin
  if not public.push_ok(tok) then raise exception 'no autorizado'; end if;
  return query select s.endpoint, s.sub, s.prefs,
    exists (select 1 from public.equipos e where e.user_id = s.user_id and e.fecha_id = fid and coalesce(e.data->'picks','{}'::jsonb) <> '{}'::jsonb),
    exists (select 1 from public.prode p where p.user_id = s.user_id and p.fecha_id = fid and coalesce(p.data,'{}'::jsonb) <> '{}'::jsonb)
  from public.push_subs s;
end $$;

-- Marca un aviso como enviado. Devuelve false si ya se había mandado.
create or replace function public.push_mark(tok text, k text) returns boolean
language plpgsql security definer set search_path = public, extensions
as $$ begin
  if not public.push_ok(tok) then raise exception 'no autorizado'; end if;
  insert into public.push_log (key) values (k) on conflict do nothing;
  return found;
end $$;

-- Avisos manuales pendientes.
create or replace function public.push_take(tok text) returns setof public.push_queue
language plpgsql security definer set search_path = public, extensions
as $$ begin
  if not public.push_ok(tok) then raise exception 'no autorizado'; end if;
  return query update public.push_queue set sent_at = now() where sent_at is null returning *;
end $$;

create or replace function public.push_done(tok text, qid bigint, n int) returns void
language plpgsql security definer set search_path = public, extensions
as $$ begin
  if not public.push_ok(tok) then raise exception 'no autorizado'; end if;
  update public.push_queue set sent_count = n where id = qid;
end $$;

-- Borra celulares que ya no aceptan avisos.
create or replace function public.push_drop(tok text, ep text) returns void
language plpgsql security definer set search_path = public, extensions
as $$ begin
  if not public.push_ok(tok) then raise exception 'no autorizado'; end if;
  delete from public.push_subs where endpoint = ep;
end $$;

grant select, insert, update, delete on public.push_subs to authenticated;
grant select, insert, update, delete on public.push_queue to authenticated;
grant execute on function public.push_targets(text, text), public.push_mark(text, text), public.push_take(text), public.push_done(text, bigint, int), public.push_drop(text, text) to anon, authenticated;
