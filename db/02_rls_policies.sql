-- Dispatch Calendar - RLS policies
-- Run after 01_normalize_dispatch_schema.sql

begin;

-- Helper: resolve current authenticated user tech name
create or replace function public.current_tech_name()
returns text
language sql
stable
as $$
  with tp as (
    select display_name as tech_name
    from public.tech_profiles
    where user_id = auth.uid() and is_active = true
    limit 1
  ), tm as (
    select tech_name
    from public.tech_name_map
    where user_id = auth.uid() and is_active = true
    limit 1
  )
  select coalesce((select tech_name from tp), (select tech_name from tm));
$$;

create or replace function public.is_admin_user()
returns boolean
language sql
stable
as $$
  select exists(
    select 1 from public.admin_users au where au.user_id = auth.uid()
  );
$$;

alter table public.jobs enable row level security;
alter table public.dispatch_override_packs enable row level security;
alter table public.tech_unavailability enable row level security;
alter table public.tech_capacity enable row level security;
alter table public.job_assignments enable row level security;
alter table public.planning_runs enable row level security;
alter table public.planning_proposals enable row level security;

-- jobs
drop policy if exists jobs_admin_all on public.jobs;
create policy jobs_admin_all on public.jobs
for all
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists jobs_tech_select_own on public.jobs;
create policy jobs_tech_select_own on public.jobs
for select
using (
  coalesce(tech_name,'') = coalesce(public.current_tech_name(),'')
  or exists (
    select 1
    from public.job_assignments ja
    where ja.job_id = jobs.id
      and ja.tech_name = public.current_tech_name()
  )
);

-- override packs (admin only)
drop policy if exists override_admin_all on public.dispatch_override_packs;
create policy override_admin_all on public.dispatch_override_packs
for all
using (public.is_admin_user())
with check (public.is_admin_user());

-- availability/capacity/admin planning tables (admin only)
drop policy if exists tech_unavailability_admin_all on public.tech_unavailability;
create policy tech_unavailability_admin_all on public.tech_unavailability
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists tech_capacity_admin_all on public.tech_capacity;
create policy tech_capacity_admin_all on public.tech_capacity
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planning_runs_admin_all on public.planning_runs;
create policy planning_runs_admin_all on public.planning_runs
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planning_proposals_admin_all on public.planning_proposals;
create policy planning_proposals_admin_all on public.planning_proposals
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists job_assignments_admin_all on public.job_assignments;
create policy job_assignments_admin_all on public.job_assignments
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists job_assignments_tech_select on public.job_assignments;
create policy job_assignments_tech_select on public.job_assignments
for select using (tech_name = public.current_tech_name());

commit;
