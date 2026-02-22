-- Dispatch Calendar - import batch tracking + scoped reset
-- Run after 01_normalize_dispatch_schema.sql and 02_rls_policies.sql

begin;

create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  filename text not null,
  imported_by uuid,
  imported_at timestamptz not null default now(),
  row_count int not null default 0,
  note text
);

alter table if exists public.jobs
  add column if not exists import_batch_id uuid references public.import_batches(id) on delete set null,
  add column if not exists imported_at timestamptz,
  add column if not exists import_source text;

create index if not exists idx_jobs_import_batch on public.jobs(import_batch_id);

create table if not exists public.import_batch_job_baseline (
  batch_id uuid not null references public.import_batches(id) on delete cascade,
  job_id uuid not null references public.jobs(id) on delete cascade,
  baseline_job_date date not null,
  baseline_tech_name text not null default 'UNASSIGNED',
  baseline_slot text not null default 'AM',
  baseline_plage text not null default 'AM',
  baseline_cancelled boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (batch_id, job_id)
);

create index if not exists idx_baseline_batch on public.import_batch_job_baseline(batch_id);

alter table public.import_batches enable row level security;
alter table public.import_batch_job_baseline enable row level security;

drop policy if exists import_batches_admin_all on public.import_batches;
create policy import_batches_admin_all on public.import_batches
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists import_batch_baseline_admin_all on public.import_batch_job_baseline;
create policy import_batch_baseline_admin_all on public.import_batch_job_baseline
for all using (public.is_admin_user()) with check (public.is_admin_user());

create or replace function public.admin_reset_import_batch(p_batch_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  if not public.is_admin_user() then
    raise exception 'Admin only';
  end if;

  update public.jobs j
  set
    job_date = b.baseline_job_date,
    tech_name = b.baseline_tech_name,
    slot = b.baseline_slot,
    plage = b.baseline_plage,
    cancelled = b.baseline_cancelled
  from public.import_batch_job_baseline b
  where b.batch_id = p_batch_id
    and b.job_id = j.id;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.admin_reset_import_batch(uuid) from public;
grant execute on function public.admin_reset_import_batch(uuid) to authenticated;

commit;
