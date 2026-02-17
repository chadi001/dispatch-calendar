-- Dispatch Calendar - schema normalization (safe, additive)
-- Run in Supabase SQL editor as admin.

begin;

-- Canonical columns used by UI/planner
alter table if exists public.jobs add column if not exists wo text;
alter table if exists public.jobs add column if not exists client text;
alter table if exists public.jobs add column if not exists site_id text;
alter table if exists public.jobs add column if not exists job_desc text;
alter table if exists public.jobs add column if not exists slot text;
alter table if exists public.jobs add column if not exists plage text;
alter table if exists public.jobs add column if not exists cancelled boolean default false;
alter table if exists public.jobs add column if not exists manual_lock boolean default false;

-- Keep old order_number for compatibility, mirror if wo missing
update public.jobs
set wo = coalesce(nullif(wo,''), nullif(order_number,''))
where coalesce(wo,'') = '';

-- Tech availability windows (vacation/leave/training)
create table if not exists public.tech_unavailability (
  id uuid primary key default gen_random_uuid(),
  tech_name text not null,
  start_date date not null,
  end_date date not null,
  reason text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint chk_unavail_dates check (end_date >= start_date)
);

create index if not exists idx_unavail_tech_dates on public.tech_unavailability(tech_name, start_date, end_date);

-- Capacity windows (AM/PM per tech can change by period)
create table if not exists public.tech_capacity (
  id uuid primary key default gen_random_uuid(),
  tech_name text not null,
  start_date date not null,
  end_date date not null,
  am_capacity int not null default 1,
  pm_capacity int not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint chk_capacity_dates check (end_date >= start_date),
  constraint chk_capacity_values check (am_capacity >= 0 and pm_capacity >= 0)
);

create index if not exists idx_capacity_tech_dates on public.tech_capacity(tech_name, start_date, end_date);

-- Multi-tech assignment (lead/trainee/team)
create table if not exists public.job_assignments (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  tech_name text not null,
  role text not null default 'lead',
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  constraint chk_role check (role in ('lead','trainee','team'))
);

create unique index if not exists ux_job_assign_tech_role on public.job_assignments(job_id, tech_name, role);
create index if not exists idx_job_assign_job on public.job_assignments(job_id);
create index if not exists idx_job_assign_tech on public.job_assignments(tech_name);

-- Planning scenario runs
create table if not exists public.planning_runs (
  id uuid primary key default gen_random_uuid(),
  created_by uuid,
  mode text not null default 'generate',
  params_json jsonb not null default '{}'::jsonb,
  summary_json jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  constraint chk_run_mode check (mode in ('generate','optimize')),
  constraint chk_run_status check (status in ('draft','applied','discarded'))
);

-- Per-job proposals in a run
create table if not exists public.planning_proposals (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.planning_runs(id) on delete cascade,
  job_id uuid,
  job_key text,
  old_date date,
  new_date date,
  old_slot text,
  new_slot text,
  old_tech text,
  new_tech text,
  score numeric,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_plan_prop_run on public.planning_proposals(run_id);

commit;

-- ------------------------------------------------------------
-- Optional: load data from staging table into jobs
-- Assumes staging table: public.staging_jobs_import
-- Required columns in staging:
--   prov_site, work_order, province, city, address, postal_code,
--   date_scheduled_raw, start_time_raw, job_desc, client
-- ------------------------------------------------------------
/*
begin;

delete from public.jobs;

with src as (
  select
    trim(coalesce(prov_site,'')) as site,
    trim(coalesce(work_order,'')) as wo,
    trim(coalesce(province,'')) as province,
    trim(coalesce(city,'')) as city,
    trim(coalesce(address,'')) as address,
    trim(coalesce(postal_code,'')) as postal_code,
    trim(coalesce(date_scheduled_raw,'')) as date_raw,
    trim(coalesce(start_time_raw,'')) as time_raw,
    trim(coalesce(job_desc,'')) as job_desc,
    trim(coalesce(client,'')) as client
  from public.staging_jobs_import
  where upper(trim(coalesce(province,''))) = 'QC'
), parsed as (
  select
    site,
    wo,
    'QC'::text as province,
    city,
    address,
    postal_code,
    case
      when date_raw ~ '^[A-Za-z]{3}-\\d{1,2}$' then to_date(date_raw || '-2026', 'Mon-DD-YYYY')
      when date_raw ~ '^\\d{4}-\\d{2}-\\d{2}$' then date_raw::date
      else null
    end as job_date,
    case
      when lower(time_raw) like '%9%' or lower(time_raw) like '%am%' then 'AM'
      when lower(time_raw) like '%12%' or lower(time_raw) like '%pm%' then 'PM'
      else null
    end as slot,
    nullif(client,'') as client,
    nullif(job_desc,'') as job_desc
  from src
)
insert into public.jobs (
  job_date, slot, plage, tech_name, client,
  province, city, address, site, prov_site,
  wo, order_number, job_desc, cancelled, manual_lock
)
select
  job_date,
  coalesce(slot,'AM'),
  coalesce(slot,'AM'),
  'UNASSIGNED',
  coalesce(client,'GOCO'),
  province,
  city,
  address,
  site,
  site,
  wo,
  wo,
  job_desc,
  false,
  false
from parsed
where job_date is not null;

commit;
*/
