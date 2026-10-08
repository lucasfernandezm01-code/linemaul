-- ============ LINE & MAUL · base de datos ============
-- Pegar todo en Supabase → SQL Editor → Run. Se puede correr una sola vez.

-- Admins (vos). Se completa después de registrarte en el sitio.
create table public.admins (user_id uuid primary key references auth.users on delete cascade);
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

-- Configuración general: planteles, camisetas, entrenadores, puntajes, etc.
create table public.config (
  key text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Fechas: partidos, resultados y horarios de apertura y cierre.
create table public.fechas (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  abre timestamptz,
  cierra timestamptz,
  updated_at timestamptz not null default now()
);

-- Perfil de cada usuario: nombre de su equipo y club (el club queda fijo).
create table public.profiles (
  id uuid primary key references auth.users on delete cascade default auth.uid(),
  nombre text,
  club text,
  created_at timestamptz not null default now()
);

-- Equipo (Gran DT) de cada usuario en cada fecha.
create table public.equipos (
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  fecha_id text not null references public.fechas on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, fecha_id)
);

-- Prode de cada usuario en cada fecha.
create table public.prode (
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  fecha_id text not null references public.fechas on delete cascade,
  data jsonb not null,
  comps text[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (user_id, fecha_id)
);

-- Torneos privados y sus miembros.
create table public.ligas (
  code text primary key,
  juego text not null check (juego in ('dt','prode')),
  nombre text not null,
  comps text[] not null default '{}',
  owner uuid not null references auth.users on delete cascade default auth.uid(),
  created_at timestamptz not null default now()
);
create table public.liga_miembros (
  code text not null references public.ligas on delete cascade,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  joined_at timestamptz not null default now(),
  primary key (code, user_id)
);

-- ¿La fecha está abierta ahora?
create or replace function public.fecha_abierta(fid text) returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.fechas f where f.id = fid
  and (f.abre is null or now() >= f.abre) and (f.cierra is null or now() < f.cierra)) $$;

-- El club no se puede cambiar una vez elegido (salvo el admin).
create or replace function public.club_fijo() returns trigger
language plpgsql security definer set search_path = public
as $$ begin
  if old.club is not null and old.club <> '' and new.club is distinct from old.club and not public.is_admin() then
    new.club := old.club;
  end if;
  return new;
end $$;
create trigger profiles_club_fijo before update on public.profiles for each row execute function public.club_fijo();

-- ============ Permisos ============
alter table public.admins enable row level security;
alter table public.config enable row level security;
alter table public.fechas enable row level security;
alter table public.profiles enable row level security;
alter table public.equipos enable row level security;
alter table public.prode enable row level security;
alter table public.ligas enable row level security;
alter table public.liga_miembros enable row level security;

create policy "admins: ver propio" on public.admins for select to authenticated using (user_id = auth.uid() or public.is_admin());

create policy "config: todos leen" on public.config for select to anon, authenticated using (true);
create policy "config: admin escribe" on public.config for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "fechas: todos leen" on public.fechas for select to anon, authenticated using (true);
create policy "fechas: admin escribe" on public.fechas for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "profiles: todos leen" on public.profiles for select to anon, authenticated using (true);
create policy "profiles: crear el propio" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profiles: editar el propio" on public.profiles for update to authenticated using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

-- Equipos y prodes: el tuyo lo ves siempre; los de los demás, recién cuando cierra la fecha.
-- Solo podés guardar o cambiar mientras la fecha está abierta.
create policy "equipos: ver" on public.equipos for select to anon, authenticated
  using (user_id = auth.uid() or not public.fecha_abierta(fecha_id) or public.is_admin());
create policy "equipos: crear" on public.equipos for insert to authenticated
  with check (user_id = auth.uid() and public.fecha_abierta(fecha_id));
create policy "equipos: cambiar" on public.equipos for update to authenticated
  using (user_id = auth.uid() and public.fecha_abierta(fecha_id))
  with check (user_id = auth.uid() and public.fecha_abierta(fecha_id));
create policy "equipos: admin" on public.equipos for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "prode: ver" on public.prode for select to anon, authenticated
  using (user_id = auth.uid() or not public.fecha_abierta(fecha_id) or public.is_admin());
create policy "prode: crear" on public.prode for insert to authenticated
  with check (user_id = auth.uid() and public.fecha_abierta(fecha_id));
create policy "prode: cambiar" on public.prode for update to authenticated
  using (user_id = auth.uid() and public.fecha_abierta(fecha_id))
  with check (user_id = auth.uid() and public.fecha_abierta(fecha_id));
create policy "prode: admin" on public.prode for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Torneos privados: las competencias quedan fijas (no se pueden editar), el creador puede borrarlo.
create policy "ligas: todos leen" on public.ligas for select to anon, authenticated using (true);
create policy "ligas: crear" on public.ligas for insert to authenticated with check (owner = auth.uid());
create policy "ligas: borrar el propio" on public.ligas for delete to authenticated using (owner = auth.uid() or public.is_admin());

create policy "miembros: todos leen" on public.liga_miembros for select to anon, authenticated using (true);
create policy "miembros: sumarse" on public.liga_miembros for insert to authenticated with check (user_id = auth.uid());
create policy "miembros: salirse" on public.liga_miembros for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- Permisos de las tablas para la web
grant usage on schema public to anon, authenticated;
grant select on all tables in schema public to anon, authenticated;
grant insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.is_admin(), public.fecha_abierta(text) to anon, authenticated;
