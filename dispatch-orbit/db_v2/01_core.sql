begin;

create extension if not exists pgcrypto;

create or replace function public.dispatch_v2_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.dispatch_v2_normalize_postal_code()
returns trigger
language plpgsql
as $$
declare
  v text;
begin
  if new.postal_code is null then
    return new;
  end if;
  v := upper(regexp_replace(coalesce(new.postal_code, ''), '[^A-Z0-9]', '', 'g'));
  if v ~ '^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$' then
    new.postal_code := v;
  elsif v = '' then
    new.postal_code := null;
  else
    raise exception 'Invalid postal code format';
  end if;
  return new;
end;
$$;

create table if not exists public.dispatch_v2_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('admin','tech')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dispatch_v2_jobs (
  id uuid primary key default gen_random_uuid(),
  work_order text not null,
  client_code text not null,
  site_code text,
  site_name text,
  address text,
  city text,
  province text,
  postal_code text,
  scheduled_date date not null,
  scheduled_slot text not null check (scheduled_slot in ('AM','PM')),
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled','on_hold')),
  cancel_reason_code text,
  cancel_reason_note text,
  actual_start_at timestamptz,
  actual_end_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dispatch_v2_jobs_postal_chk check (
    postal_code is null or upper(regexp_replace(postal_code, '[^A-Z0-9]', '', 'g')) ~ '^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$'
  )
);

create unique index if not exists dispatch_v2_jobs_wo_date_slot_ux
  on public.dispatch_v2_jobs(work_order, scheduled_date, scheduled_slot);
create index if not exists dispatch_v2_jobs_date_idx
  on public.dispatch_v2_jobs(scheduled_date, status);
create index if not exists dispatch_v2_jobs_client_idx
  on public.dispatch_v2_jobs(client_code);

create table if not exists public.dispatch_v2_job_assignments (
  job_id uuid not null references public.dispatch_v2_jobs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assignment_role text not null default 'tech' check (assignment_role in ('lead','tech','support')),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (job_id, user_id)
);

create index if not exists dispatch_v2_assign_user_idx
  on public.dispatch_v2_job_assignments(user_id, job_id);
create index if not exists dispatch_v2_assign_job_idx
  on public.dispatch_v2_job_assignments(job_id, is_primary desc);

create table if not exists public.dispatch_v2_checklist_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  client_code text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (name)
);

create table if not exists public.dispatch_v2_checklist_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.dispatch_v2_checklist_templates(id) on delete cascade,
  segment text not null,
  sort_order int not null,
  label text not null,
  is_required boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (template_id, sort_order, label)
);

create table if not exists public.dispatch_v2_job_checklist_items (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.dispatch_v2_jobs(id) on delete cascade,
  template_item_id uuid not null references public.dispatch_v2_checklist_template_items(id) on delete restrict,
  segment text not null,
  sort_order int not null,
  label text not null,
  is_required boolean not null default true,
  completed boolean not null default false,
  completed_by uuid references auth.users(id),
  completed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  unique (job_id, template_item_id)
);

create index if not exists dispatch_v2_job_checklist_job_idx
  on public.dispatch_v2_job_checklist_items(job_id, sort_order);

create table if not exists public.dispatch_v2_job_work_sessions (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.dispatch_v2_jobs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  constraint dispatch_v2_work_session_time_chk check (ended_at is null or ended_at >= started_at)
);

create index if not exists dispatch_v2_work_job_idx
  on public.dispatch_v2_job_work_sessions(job_id, started_at desc);
create index if not exists dispatch_v2_work_user_idx
  on public.dispatch_v2_job_work_sessions(user_id, started_at desc);

create table if not exists public.dispatch_v2_job_events (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.dispatch_v2_jobs(id) on delete cascade,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  note text,
  actor_user_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists dispatch_v2_events_job_idx
  on public.dispatch_v2_job_events(job_id, created_at desc);

drop trigger if exists trg_dispatch_v2_profiles_updated_at on public.dispatch_v2_profiles;
create trigger trg_dispatch_v2_profiles_updated_at
before update on public.dispatch_v2_profiles
for each row execute function public.dispatch_v2_set_updated_at();

drop trigger if exists trg_dispatch_v2_jobs_updated_at on public.dispatch_v2_jobs;
create trigger trg_dispatch_v2_jobs_updated_at
before update on public.dispatch_v2_jobs
for each row execute function public.dispatch_v2_set_updated_at();

drop trigger if exists trg_dispatch_v2_jobs_postal on public.dispatch_v2_jobs;
create trigger trg_dispatch_v2_jobs_postal
before insert or update of postal_code on public.dispatch_v2_jobs
for each row execute function public.dispatch_v2_normalize_postal_code();

insert into public.dispatch_v2_checklist_templates(name, client_code)
values ('Default Onsite Template', null)
on conflict (name) do nothing;

insert into public.dispatch_v2_checklist_template_items(template_id, segment, sort_order, label, is_required)
select t.id, x.segment, x.sort_order, x.label, x.is_required
from public.dispatch_v2_checklist_templates t
cross join (
  values
    ('Arrival and safety', 10, 'Park safely and respect site safety rules', true),
    ('Arrival and safety', 20, 'Check in with customer/site contact', true),
    ('Arrival and safety', 30, 'Review scope and constraints before work', true),
    ('Installation and validation', 40, 'Execute installation according to plan', true),
    ('Installation and validation', 50, 'Label and verify all connections', true),
    ('Installation and validation', 60, 'Run validation tests', true),
    ('Closeout and departure', 70, 'Capture final photos', true),
    ('Closeout and departure', 80, 'Customer walkthrough and sign-off', true),
    ('Closeout and departure', 90, 'Clean site and close notes', true)
) as x(segment, sort_order, label, is_required)
where t.name = 'Default Onsite Template'
  and not exists (
    select 1
    from public.dispatch_v2_checklist_template_items i
    where i.template_id = t.id and i.sort_order = x.sort_order and i.label = x.label
  );

commit;
