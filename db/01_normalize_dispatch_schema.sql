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
