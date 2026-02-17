-- Dispatch Calendar - Fix Tech Visibility
-- Run this in Supabase SQL Editor to diagnose and fix tech visibility issues
-- specifically for a.hannoune@aigleinfo.ca

-- ============================================================
-- PART 1: DIAGNOSTIC - See current state
-- ============================================================

-- 1a. Check what tech_name values exist in jobs table
select 
  tech_name,
  count(*) as job_count,
  count(*) filter (where not cancelled) as active_jobs
from public.jobs
group by tech_name
order by job_count desc;

-- 1b. Check tech_profiles entries
select 
  tp.user_id,
  tp.display_name,
  tp.tech_code,
  tp.is_active,
  u.email
from public.tech_profiles tp
left join auth.users u on u.id = tp.user_id
order by tp.display_name;

-- 1c. Check tech_name_map entries
select 
  tnm.user_id,
  tnm.tech_name,
  tnm.is_active,
  u.email
from public.tech_name_map tnm
left join auth.users u on u.id = tnm.user_id
order by tnm.tech_name;

-- 1d. Find the user_id for a.hannoune@aigleinfo.ca
select 
  id as user_id,
  email,
  raw_user_meta_data
from auth.users
where email ilike '%a.hannoune%';

-- ============================================================
-- PART 2: FIX - Match tech_name in jobs to mapping tables
-- ============================================================

-- First, run the diagnostic above to identify:
-- A) What tech_name values exist in jobs (e.g., "Abdel", "ABDEL", "Abdel Hannoune")
-- B) What display_name/tech_code/tech_name exist in mapping tables
-- C) The user_id for a.hannoune@aigleinfo.ca

-- OPTION A: If jobs.tech_name uses "Abdel" but mapping uses different value
-- Update tech_profiles to match jobs.tech_name

/*
begin;

-- Find user_id first (run the query in 1d above)
-- Then update tech_profiles.display_name to match exactly what's in jobs.tech_name

update public.tech_profiles
set display_name = 'Abdel'  -- CHANGE THIS to match jobs.tech_name exactly
where user_id = 'PASTE_USER_ID_HERE'  -- from query 1d
  and is_active = true;

-- Or update tech_name_map as fallback
insert into public.tech_name_map (user_id, tech_name, is_active)
values ('PASTE_USER_ID_HERE', 'Abdel', true)  -- CHANGE 'Abdel' to match jobs.tech_name
on conflict (user_id) do update set
  tech_name = excluded.tech_name,
  is_active = true;

commit;
*/

-- OPTION B: If mapping is correct but jobs.tech_name is different
-- Update jobs to use the mapped tech_name

/*
begin;

-- Update all jobs to use normalized tech_name
update public.jobs
set tech_name = 'Abdel'  -- CHANGE to match mapping
where tech_name ilike '%abdel%'  -- matches Abdel, ABDEL, abdel, Abdel H, etc.
  and cancelled = false;

commit;
*/

-- OPTION C: Create complete mapping if missing

/*
begin;

-- Get the user_id for a.hannoune@aigleinfo.ca
-- Then create entries in both tables for redundancy

-- Insert into tech_profiles
insert into public.tech_profiles (user_id, display_name, tech_code, is_active)
values (
  'PASTE_USER_ID_HERE',  -- from auth.users
  'Abdel',               -- Must match jobs.tech_name exactly
  'abdel',               -- Lowercase code as fallback
  true
)
on conflict (user_id) do update set
  display_name = excluded.display_name,
  tech_code = excluded.tech_code,
  is_active = true;

-- Insert into tech_name_map as backup
insert into public.tech_name_map (user_id, tech_name, is_active)
values (
  'PASTE_USER_ID_HERE',  -- from auth.users
  'Abdel',               -- Must match jobs.tech_name exactly
  true
)
on conflict (user_id) do update set
  tech_name = excluded.tech_name,
  is_active = true;

commit;
*/

-- ============================================================
-- PART 3: VERIFY - After fix, test RLS
-- ============================================================

-- Test RLS policy as the tech user (run as admin to impersonate)
-- This simulates what the tech user would see

/*
-- Set role to the tech user temporarily
set local role authenticated;
set local request.jwt.claims = '{"sub": "PASTE_USER_ID_HERE"}';

-- Now run this to see what jobs they can access
select count(*) as visible_jobs
from public.jobs
where cancelled = false;

-- Reset role
reset role;
*/

-- ============================================================
-- QUICK FIX SCRIPT - Run this if you know the user_id
-- Replace USER_ID and TECH_NAME values below
-- ============================================================

/*
begin;

-- REPLACE THESE VALUES:
-- 1. Get user_id: select id from auth.users where email ilike '%a.hannoune%';
-- 2. Get tech_name: select distinct tech_name from public.jobs where tech_name != 'UNASSIGNED';

-- Example: user_id = 'abc-123-...', tech_name = 'Abdel'

-- Ensure tech_profiles entry
insert into public.tech_profiles (user_id, display_name, tech_code, is_active)
values (
  'PASTE_USER_ID_FROM_AUTH_USERS',   -- <-- REPLACE
  'Abdel',                            -- <-- REPLACE with jobs.tech_name
  'abdel',
  true
)
on conflict (user_id) do update set
  display_name = excluded.display_name,
  tech_code = excluded.tech_code,
  is_active = true;

-- Ensure tech_name_map entry (fallback)
insert into public.tech_name_map (user_id, tech_name, is_active)
values (
  'PASTE_USER_ID_FROM_AUTH_USERS',   -- <-- REPLACE
  'Abdel',                            -- <-- REPLACE with jobs.tech_name
  true
)
on conflict (user_id) do update set
  tech_name = excluded.tech_name,
  is_active = true;

commit;

-- Verify
select 'tech_profiles' as tbl, user_id, display_name, tech_code, is_active
from public.tech_profiles
where user_id = 'PASTE_USER_ID_FROM_AUTH_USERS'
union all
select 'tech_name_map' as tbl, user_id, tech_name, is_active, null
from public.tech_name_map
where user_id = 'PASTE_USER_ID_FROM_AUTH_USERS';
*/
