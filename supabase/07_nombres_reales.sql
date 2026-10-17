-- ============ LINE & MAUL · nombre y apellido real (solo admin) ============
-- Pegar en Supabase → SQL Editor → Run (una sola vez).
-- El nombre real se guarda en la cuenta (no en profiles), así nadie más lo ve. Solo el admin lo lee con esta función.
create or replace function public.nombres_reales(p_ids uuid[]) returns table (id uuid, nombre_real text, email text)
language sql stable security definer set search_path = public, auth
as $$ select u.id, coalesce(nullif(u.raw_user_meta_data->>'nombre_real', ''), u.raw_user_meta_data->>'nombre'), u.email::text
  from auth.users u where public.is_admin() and u.id = any(p_ids) $$;
grant execute on function public.nombres_reales(uuid[]) to authenticated;
