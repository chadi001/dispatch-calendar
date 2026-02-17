-- ============================================================
-- FIX TECH VISIBILITY FOR a.hannoune@aigleinfo.ca
-- Paste in Supabase SQL Editor - Run each section separately
-- ============================================================

-- STEP 1: See what tech_name values exist in jobs
-- Run this first and note the exact spelling of Abdel's tech_name
select distinct tech_name, count(*) as job_count
from public.jobs
where cancelled = false
group by tech_name
order by job_count desc;

-- ============================================================
-- STEP 2: Find the user_id for a.hannoune@aigleinfo.ca
-- Run this and copy the user_id
select id as user_id, email from auth.users 
where email ilike '%a.hannoune%';

-- ============================================================
-- STEP 3: Add/update the mapping
-- Replace 'PASTE_USER_ID_HERE' with the user_id from step 2
-- Change 'Abdel' if the tech_name in jobs is spelled differently
-- ============================================================

-- First delete any existing entries for this user (to avoid duplicates)
delete from public.tech_profiles where user_id = 'PASTE_USER_ID_HERE';
delete from public.tech_name_map where user_id = 'PASTE_USER_ID_HERE';

-- Then insert fresh mappings
-- REPLACE 'PASTE_USER_ID_HERE' with the actual user_id from step 2
-- Make sure 'Abdel' matches EXACTLY what you see in jobs.tech_name from step 1

insert into public.tech_profiles (user_id, display_name, tech_code, is_active)
values ('PASTE_USER_ID_HERE', 'Abdel', 'abdel', true);

insert into public.tech_name_map (user_id, tech_name, is_active)
values ('PASTE_USER_ID_HERE', 'Abdel', true);

-- ============================================================
-- STEP 4: Verify the mapping
-- ============================================================
select 'tech_profiles' as tbl, user_id, display_name, is_active from public.tech_profiles
where user_id = 'PASTE_USER_ID_HERE'
union all
select 'tech_name_map' as tbl, user_id, tech_name, is_active from public.tech_name_map
where user_id = 'PASTE_USER_ID_HERE';
