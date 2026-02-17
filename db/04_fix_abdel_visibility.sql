-- ============================================================
-- FIX TECH VISIBILITY FOR a.hannoune@aigleinfo.ca
-- Paste this entire script in Supabase SQL Editor and click RUN
-- ============================================================

begin;

-- STEP 1: Show current state (diagnostic)
raise notice '=== DIAGNOSTIC INFO ===';

-- Show tech_name values in jobs table
raise notice 'Tech names in jobs table:';
for rec in 
  select distinct tech_name, count(*) as cnt 
  from public.jobs 
  where cancelled = false 
  group by tech_name 
  order by cnt desc
loop
  raise notice '  %: % jobs', rec.tech_name, rec.cnt;
end loop;

-- STEP 2: Find user_id for a.hannoune@aigleinfo.ca
raise notice '=== FINDING USER ===';

-- STEP 3: Create/update mapping for a.hannoune@aigleinfo.ca
-- The tech_name should match what's in jobs table (likely "Abdel")

-- First, let's see if there's a job with tech_name containing "abdel" or "hannoune"
-- and map the user to that tech_name

-- Update or insert into tech_profiles
insert into public.tech_profiles (user_id, display_name, tech_code, is_active)
select 
  u.id as user_id,
  'Abdel' as display_name,  -- This should match jobs.tech_name exactly
  'abdel' as tech_code,
  true as is_active
from auth.users u
where u.email ilike '%a.hannoune@aigleinfo.ca'
on conflict (user_id) do update set
  display_name = excluded.display_name,
  tech_code = excluded.tech_code,
  is_active = true;

-- Update or insert into tech_name_map (backup/resolver)
insert into public.tech_name_map (user_id, tech_name, is_active)
select 
  u.id as user_id,
  'Abdel' as tech_name,  -- This should match jobs.tech_name exactly
  true as is_active
from auth.users u
where u.email ilike '%a.hannoune@aigleinfo.ca'
on conflict (user_id) do update set
  tech_name = excluded.tech_name,
  is_active = true;

commit;

-- ============================================================
-- VERIFY - Run this after the above commits
-- ============================================================

-- Show the mapping we just created
select 
  'Mapping created' as status,
  u.email,
  tp.display_name as tech_profiles_display_name,
  tnm.tech_name as tech_name_map_value
from auth.users u
left join public.tech_profiles tp on tp.user_id = u.id
left join public.tech_name_map tnm on tnm.user_id = u.id
where u.email ilike '%a.hannoune%';

-- Show jobs this user should now see
select 
  'Jobs visible to Abdel' as label,
  count(*) as job_count
from public.jobs
where tech_name = 'Abdel'
  and cancelled = false;

-- ============================================================
-- IF STILL NOT WORKING: Check exact tech_name spelling in jobs
-- Run this separately and tell me what you see:
-- ============================================================
/*
select distinct tech_name 
from public.jobs 
where tech_name ilike '%abdel%' 
   or tech_name ilike '%hannoune%';
*/
