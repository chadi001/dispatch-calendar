-- ============================================================
-- FIX TECH VISIBILITY FOR a.hannoune@aigleinfo.ca
-- Paste in Supabase SQL Editor and click RUN
-- ============================================================

-- STEP 1: First run this to see the current state
-- (Copy results and share if still broken after fix)

-- A) What tech names are in jobs table?
select distinct tech_name, count(*) as job_count
from public.jobs
where cancelled = false
group by tech_name
order by job_count desc;

-- B) Current mappings
select 'tech_profiles' as source, tp.user_id, tp.display_name, tp.tech_code, tp.is_active, u.email
from public.tech_profiles tp
join auth.users u on u.id = tp.user_id
union all
select 'tech_name_map' as source, tnm.user_id, tnm.tech_name, null, tnm.is_active, u.email
from public.tech_name_map tnm
join auth.users u on u.id = tnm.user_id;

-- ============================================================
-- STEP 2: APPLY FIX (run after reviewing step 1)
-- ============================================================

begin;

-- Map a.hannoune@aigleinfo.ca to tech_name = "Abdel"
-- (Change 'Abdel' if jobs table uses different spelling)

insert into public.tech_profiles (user_id, display_name, tech_code, is_active)
select 
  u.id,
  'Abdel',
  'abdel',
  true
from auth.users u
where u.email ilike '%a.hannoune@aigleinfo.ca'
on conflict (user_id) do update set
  display_name = 'Abdel',
  tech_code = 'abdel',
  is_active = true;

insert into public.tech_name_map (user_id, tech_name, is_active)
select 
  u.id,
  'Abdel',
  true
from auth.users u
where u.email ilike '%a.hannoune@aigleinfo.ca'
on conflict (user_id) do update set
  tech_name = 'Abdel',
  is_active = true;

commit;

-- ============================================================
-- STEP 3: VERIFY (run after step 2)
-- ============================================================

select 
  u.email,
  tp.display_name,
  tnm.tech_name,
  (select count(*) from public.jobs where tech_name = 'Abdel' and cancelled = false) as abdel_jobs_in_db
from auth.users u
left join public.tech_profiles tp on tp.user_id = u.id
left join public.tech_name_map tnm on tnm.user_id = u.id
where u.email ilike '%a.hannoune%';
