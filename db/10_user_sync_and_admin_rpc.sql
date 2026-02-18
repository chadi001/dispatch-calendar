-- Dispatch Calendar - auth.users mirror + admin RPCs
-- Run once in Supabase SQL editor as project owner

begin;

-- 1) Public mirror of auth users (safe to query with RLS)
create table if not exists public.app_users (
  user_id uuid primary key,
  email text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  is_disabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists idx_app_users_email on public.app_users(email);

-- Backfill from existing auth users
insert into public.app_users (user_id, email, created_at, last_sign_in_at, is_disabled, updated_at)
select
  u.id,
  u.email,
  u.created_at,
  u.last_sign_in_at,
  coalesce(u.banned_until is not null and u.banned_until > now(), false) as is_disabled,
  now()
from auth.users u
on conflict (user_id) do update set
  email = excluded.email,
  created_at = excluded.created_at,
  last_sign_in_at = excluded.last_sign_in_at,
  is_disabled = excluded.is_disabled,
  updated_at = now();

-- Keep mirror in sync with auth.users
create or replace function public.sync_app_user_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_users (user_id, email, created_at, last_sign_in_at, is_disabled, updated_at)
  values (
    new.id,
    new.email,
    new.created_at,
    new.last_sign_in_at,
    coalesce(new.banned_until is not null and new.banned_until > now(), false),
    now()
  )
  on conflict (user_id) do update set
    email = excluded.email,
    created_at = excluded.created_at,
    last_sign_in_at = excluded.last_sign_in_at,
    is_disabled = excluded.is_disabled,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_sync_app_user_from_auth on auth.users;
create trigger trg_sync_app_user_from_auth
after insert or update on auth.users
for each row execute function public.sync_app_user_from_auth();

-- 2) Constraints for mapping tables (ignore legacy null rows)
create unique index if not exists ux_tech_name_map_user_id_not_null
  on public.tech_name_map(user_id)
  where user_id is not null;

create unique index if not exists ux_tech_profiles_user_id_not_null
  on public.tech_profiles(user_id)
  where user_id is not null;

-- 3) RLS for app_users
alter table public.app_users enable row level security;

drop policy if exists app_users_admin_select on public.app_users;
create policy app_users_admin_select on public.app_users
for select using (public.is_admin_user());

drop policy if exists app_users_self_select on public.app_users;
create policy app_users_self_select on public.app_users
for select using (user_id = auth.uid());

-- 4) Admin RPC: list users + mapping status
create or replace function public.admin_list_user_tech_mappings()
returns table (
  user_id uuid,
  email text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  is_disabled boolean,
  tech_name text,
  mapping_active boolean,
  is_admin boolean
)
language sql
security definer
set search_path = public
as $$
  select
    au.user_id,
    au.email,
    au.created_at,
    au.last_sign_in_at,
    au.is_disabled,
    coalesce(tnm.tech_name, tp.display_name) as tech_name,
    coalesce(tnm.is_active, tp.is_active, false) as mapping_active,
    exists (select 1 from public.admin_users ad where ad.user_id = au.user_id) as is_admin
  from public.app_users au
  left join public.tech_name_map tnm on tnm.user_id = au.user_id
  left join public.tech_profiles tp on tp.user_id = au.user_id
  where public.is_admin_user()
  order by coalesce(au.email, ''), au.user_id;
$$;

-- 5) Admin RPC: set mapping by user_id
create or replace function public.admin_set_user_tech_mapping(
  p_user_id uuid,
  p_tech_name text,
  p_is_active boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'admin only';
  end if;

  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  if p_tech_name is null or btrim(p_tech_name) = '' then
    raise exception 'p_tech_name is required';
  end if;

  insert into public.tech_name_map (user_id, tech_name, is_active)
  values (p_user_id, btrim(p_tech_name), p_is_active)
  on conflict (user_id) do update set
    tech_name = excluded.tech_name,
    is_active = excluded.is_active;

  insert into public.tech_profiles (user_id, display_name, tech_code, is_active)
  values (p_user_id, btrim(p_tech_name), lower(replace(btrim(p_tech_name), ' ', '')), p_is_active)
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    tech_code = excluded.tech_code,
    is_active = excluded.is_active;
end;
$$;

-- 6) Admin RPC: clear mapping for a user
create or replace function public.admin_clear_user_tech_mapping(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'admin only';
  end if;

  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  delete from public.tech_name_map where user_id = p_user_id;
  update public.tech_profiles set is_active = false where user_id = p_user_id;
end;
$$;

grant execute on function public.admin_list_user_tech_mappings() to authenticated;
grant execute on function public.admin_set_user_tech_mapping(uuid, text, boolean) to authenticated;
grant execute on function public.admin_clear_user_tech_mapping(uuid) to authenticated;

commit;
