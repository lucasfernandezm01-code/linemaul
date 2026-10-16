-- ============ LINE & MAUL · nombre del equipo fijo ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez).
-- El nombre del equipo se puede cambiar una sola vez, hasta el 30/4/2027 (hora argentina).
alter table public.profiles add column if not exists equipo_cambios int not null default 0;

create or replace function public.equipo_fijo() returns trigger
language plpgsql security definer set search_path = public
as $$ begin
  if public.is_admin() then return new; end if;
  if tg_op = 'INSERT' then new.equipo_cambios := 0; return new; end if;
  new.equipo_cambios := old.equipo_cambios;
  if coalesce(old.equipo, '') <> '' and new.equipo is distinct from old.equipo then
    if old.equipo_cambios < 1 and now() < timestamptz '2027-05-01 00:00:00-03' and coalesce(new.equipo, '') <> '' then
      new.equipo_cambios := old.equipo_cambios + 1;
    else
      new.equipo := old.equipo;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_equipo_fijo on public.profiles;
create trigger profiles_equipo_fijo before insert or update on public.profiles for each row execute function public.equipo_fijo();
