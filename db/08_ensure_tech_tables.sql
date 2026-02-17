-- Dispatch Calendar - Ensure tech mapping tables exist
-- Run in Supabase SQL Editor

begin;

-- Create tech_profiles if not exists
create table if not exists public.tech_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique not null,
  display_name text,
  tech_code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Create tech_name_map if not exists
create table if not exists public.tech_name_map (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique not null,
  tech_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Add indexes
create index if not exists idx_tech_profiles_user on public.tech_profiles(user_id);
create index if not exists idx_tech_name_map_user on public.tech_name_map(user_id);
create index if not exists idx_tech_name_map_tech on public.tech_name_map(tech_name);

-- Enable RLS
alter table public.tech_profiles enable row level security;
alter table public.tech_name_map enable row level security;

-- Add RLS policies (idempotent)
drop policy if exists tech_profiles_admin_all on public.tech_profiles;
create policy tech_profiles_admin_all on public.tech_profiles
for all using (
  exists (select 1 from public.admin_users au where au.user_id = auth.uid())
) with check (
  exists (select 1 from public.admin_users au where au.user_id = auth.uid())
);

drop policy if exists tech_profiles_self_read on public.tech_profiles;
create policy tech_profiles_self_read on public.tech_profiles
for select using (user_id = auth.uid());

drop policy if exists tech_name_map_admin_all on public.tech_name_map;
create policy tech_name_map_admin_all on public.tech_name_map
for all using (
  exists (select 1 from public.admin_users au where au.user_id = auth.uid())
) with check (
  exists (select 1 from public.admin_users au where au.user_id = auth.uid())
);

drop policy if exists tech_name_map_self_read on public.tech_name_map;
create policy tech_name_map_self_read on public.tech_name_map
for select using (user_id = auth.uid());

commit;

-- Verify
select 'tech_profiles columns:' as info;
select column_name, data_type from information_schema.columns 
where table_schema = 'public' and table_name = 'tech_profiles';

select 'tech_name_map columns:' as info;
select column_name, data_type from information_schema.columns 
where table_schema = 'public' and table_name = 'tech_name_map';

select 'Current mappings:' as info;
select tp.user_id, tp.display_name, tp.is_active as tp_active,
       tnm.tech_name, tnm.is_active as tnm_active
from public.tech_profiles tp
full outer join public.tech_name_map tnm on tnm.user_id = tp.user_id;
