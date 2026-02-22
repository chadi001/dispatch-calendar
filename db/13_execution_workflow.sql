-- Dispatch Calendar - execution workflow, sessions, checklist, events
-- Run after db/02_rls_policies.sql, db/10_user_sync_and_admin_rpc.sql, db/12_tech_specialties_priority.sql

begin;

alter table if exists public.jobs
  add column if not exists status text,
  add column if not exists cancel_reason_code text,
  add column if not exists cancel_reason_note text,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid,
  add column if not exists actual_start_at timestamptz,
  add column if not exists actual_end_at timestamptz,
  add column if not exists completed_by uuid,
  add column if not exists on_hold_reason text,
  add column if not exists is_multi_day boolean default false,
  add column if not exists expected_days int;

update public.jobs
set status = case when coalesce(cancelled,false) then 'cancelled' else 'scheduled' end
where coalesce(status,'') = '';

alter table public.jobs
  alter column status set default 'scheduled';

create table if not exists public.job_work_sessions (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  tech_name text not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  constraint chk_work_session_dates check (ended_at is null or ended_at >= started_at)
);

create table if not exists public.job_events (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  event_type text not null,
  old_status text,
  new_status text,
  reason_code text,
  notes text,
  actor_user_id uuid,
  actor_tech_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.job_checklist_items (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  sort_order int not null default 100,
  title text not null,
  is_required boolean not null default true,
  completed boolean not null default false,
  completed_at timestamptz,
  completed_by uuid,
  created_at timestamptz not null default now()
);


-- harden against pre-existing legacy tables with missing columns
alter table if exists public.job_work_sessions
  add column if not exists job_id uuid,
  add column if not exists tech_name text,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists notes text,
  add column if not exists created_by uuid,
  add column if not exists created_at timestamptz;

alter table if exists public.job_events
  add column if not exists job_id uuid,
  add column if not exists event_type text,
  add column if not exists old_status text,
  add column if not exists new_status text,
  add column if not exists reason_code text,
  add column if not exists notes text,
  add column if not exists actor_user_id uuid,
  add column if not exists actor_tech_name text,
  add column if not exists created_at timestamptz;

alter table if exists public.job_checklist_items
  add column if not exists job_id uuid,
  add column if not exists sort_order int,
  add column if not exists title text,
  add column if not exists is_required boolean,
  add column if not exists completed boolean,
  add column if not exists completed_at timestamptz,
  add column if not exists completed_by uuid,
  add column if not exists created_at timestamptz;

create index if not exists idx_job_work_sessions_job on public.job_work_sessions(job_id, started_at desc);
create index if not exists idx_job_work_sessions_tech on public.job_work_sessions(tech_name, started_at desc);
create index if not exists idx_job_events_job on public.job_events(job_id, created_at desc);
create index if not exists idx_job_checklist_job on public.job_checklist_items(job_id, sort_order, created_at);

create or replace function public.normalize_client_code(p text)
returns text
language sql
immutable
as $$
  select case upper(trim(coalesce(p,'')))
    when 'COGO' then 'GOCO'
    else upper(trim(coalesce(p,'')))
  end;
$$;

create or replace function public.current_tech_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select tnm.tech_name
  from public.tech_name_map tnm
  where tnm.user_id = auth.uid()
    and coalesce(tnm.is_active, true)
  limit 1;
$$;

create or replace function public.can_access_job(p_job_id uuid)
returns boolean
language sql
stable
as $$
  select
    public.is_admin_user()
    or exists (
      select 1
      from public.jobs j
      where j.id = p_job_id
        and lower(btrim(coalesce(j.tech_name,''))) = lower(btrim(coalesce(public.current_tech_name(),'')))
    )
    or exists (
      select 1
      from public.job_assignments ja
      where ja.job_id = p_job_id
        and lower(btrim(coalesce(ja.tech_name,''))) = lower(btrim(coalesce(public.current_tech_name(),'')))
    );
$$;

create or replace function public.job_checklist_owner_tech(p_job_id uuid)
returns text
language sql
stable
as $$
  with lead_assign as (
    select ja.tech_name
    from public.job_assignments ja
    where ja.job_id = p_job_id
      and (ja.is_primary = true or lower(coalesce(ja.role,'')) = 'lead')
    order by ja.is_primary desc, ja.created_at asc
    limit 1
  )
  select coalesce((select tech_name from lead_assign), (select j.tech_name from public.jobs j where j.id = p_job_id));
$$;
create or replace function public.ensure_job_checklist(p_job_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client text;
  v_count int := 0;
begin
  if p_job_id is null then
    return 0;
  end if;

  select public.normalize_client_code(j.client) into v_client
  from public.jobs j
  where j.id = p_job_id;

  if exists(select 1 from public.job_checklist_items i where i.job_id = p_job_id) then
    return 0;
  end if;

  if v_client = 'MCN' then
    insert into public.job_checklist_items(job_id, sort_order, title, is_required)
    values
      (p_job_id, 10, 'Site access confirmed', true),
      (p_job_id, 20, 'Safety checks completed', true),
      (p_job_id, 30, 'Install steps completed', true),
      (p_job_id, 40, 'Signal and quality validated', true),
      (p_job_id, 50, 'Client walkthrough completed', true),
      (p_job_id, 60, 'Photos/report links attached', false);
  else
    insert into public.job_checklist_items(job_id, sort_order, title, is_required)
    values
      (p_job_id, 10, 'Arrival and access confirmed', true),
      (p_job_id, 20, 'Work completed and validated', true),
      (p_job_id, 30, 'Client informed / notes added', false);
  end if;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.tech_start_job(p_job_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_actor text;
begin
  if not public.can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  select coalesce(status,'scheduled') into v_old from public.jobs where id = p_job_id;
  v_actor := coalesce(public.current_tech_name(), '');

  update public.jobs
  set status = 'in_progress',
      actual_start_at = coalesce(actual_start_at, now()),
      cancelled = false,
      cancel_reason_code = null,
      cancel_reason_note = null,
      cancelled_at = null,
      cancelled_by = null
  where id = p_job_id;

  insert into public.job_work_sessions(job_id, tech_name, started_at, notes, created_by)
  values (p_job_id, coalesce(nullif(v_actor,''), 'UNKNOWN'), now(), nullif(trim(coalesce(p_note,'')),''), auth.uid());

  perform public.ensure_job_checklist(p_job_id);

  insert into public.job_events(job_id, event_type, old_status, new_status, notes, actor_user_id, actor_tech_name)
  values (p_job_id, 'start_work', v_old, 'in_progress', nullif(trim(coalesce(p_note,'')),''), auth.uid(), nullif(v_actor,''));
end;
$$;

create or replace function public.tech_end_work_session(p_job_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor text;
  v_sid uuid;
begin
  if not public.can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  v_actor := coalesce(public.current_tech_name(), '');

  select s.id into v_sid
  from public.job_work_sessions s
  where s.job_id = p_job_id
    and s.ended_at is null
    and lower(coalesce(s.tech_name,'')) = lower(coalesce(v_actor,''))
  order by s.started_at desc
  limit 1;

  if v_sid is null then
    return;
  end if;

  update public.job_work_sessions
  set ended_at = now(),
      notes = coalesce(nullif(trim(coalesce(notes,'')),''), nullif(trim(coalesce(p_note,'')),''))
  where id = v_sid;

  insert into public.job_events(job_id, event_type, notes, actor_user_id, actor_tech_name)
  values (p_job_id, 'end_session', nullif(trim(coalesce(p_note,'')),''), auth.uid(), nullif(v_actor,''));
end;
$$;
create or replace function public.tech_toggle_checklist_item(p_item_id uuid, p_completed boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id uuid;
  v_owner text;
  v_actor text;
begin
  select i.job_id into v_job_id from public.job_checklist_items i where i.id = p_item_id;
  if v_job_id is null then
    raise exception 'checklist item not found';
  end if;

  if not public.can_access_job(v_job_id) then
    raise exception 'access denied';
  end if;

  v_owner := coalesce(public.job_checklist_owner_tech(v_job_id), '');
  v_actor := coalesce(public.current_tech_name(), '');
  if not public.is_admin_user() and lower(v_owner) <> lower(v_actor) then
    raise exception 'only lead tech can update checklist';
  end if;

  update public.job_checklist_items
  set completed = p_completed,
      completed_at = case when p_completed then now() else null end,
      completed_by = case when p_completed then auth.uid() else null end
  where id = p_item_id;
end;
$$;

create or replace function public.tech_set_job_cancelled(
  p_job_id uuid,
  p_cancelled boolean,
  p_reason_code text default null,
  p_reason_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_new text;
  v_actor text;
  v_reason text;
begin
  if not public.can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  select coalesce(status,'scheduled') into v_old from public.jobs where id = p_job_id;
  v_new := case when p_cancelled then 'cancelled' else 'scheduled' end;
  v_actor := coalesce(public.current_tech_name(), '');
  v_reason := lower(trim(coalesce(p_reason_code,'')));

  if p_cancelled and v_reason = '' then
    raise exception 'cancel reason is required';
  end if;

  update public.jobs
  set
    cancelled = p_cancelled,
    status = v_new,
    cancel_reason_code = case when p_cancelled then v_reason else null end,
    cancel_reason_note = case when p_cancelled then nullif(trim(coalesce(p_reason_note,'')),'') else null end,
    cancelled_at = case when p_cancelled then now() else null end,
    cancelled_by = case when p_cancelled then auth.uid() else null end
  where id = p_job_id;

  insert into public.job_events(job_id, event_type, old_status, new_status, reason_code, notes, actor_user_id, actor_tech_name)
  values (
    p_job_id,
    case when p_cancelled then 'cancel_job' else 'restore_job' end,
    v_old,
    v_new,
    case when p_cancelled then v_reason else null end,
    nullif(trim(coalesce(p_reason_note,'')),''),
    auth.uid(),
    nullif(v_actor,'')
  );
end;
$$;

create or replace function public.tech_mark_job_completed(p_job_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_actor text;
  v_owner text;
  v_client text;
  v_missing int;
begin
  if not public.can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  v_actor := coalesce(public.current_tech_name(), '');
  v_owner := coalesce(public.job_checklist_owner_tech(p_job_id), '');
  if not public.is_admin_user() and lower(v_owner) <> lower(v_actor) then
    raise exception 'only lead tech can complete this job';
  end if;

  perform public.ensure_job_checklist(p_job_id);

  select public.normalize_client_code(client), coalesce(status,'scheduled')
  into v_client, v_old
  from public.jobs
  where id = p_job_id;

  if v_client = 'MCN' then
    select count(*) into v_missing
    from public.job_checklist_items i
    where i.job_id = p_job_id
      and i.is_required = true
      and coalesce(i.completed,false) = false;
    if v_missing > 0 then
      raise exception 'required checklist items are incomplete';
    end if;
  end if;

  update public.jobs
  set status = 'completed',
      actual_start_at = coalesce(actual_start_at, now()),
      actual_end_at = now(),
      completed_by = auth.uid(),
      cancelled = false,
      cancel_reason_code = null,
      cancel_reason_note = null,
      cancelled_at = null,
      cancelled_by = null
  where id = p_job_id;

  update public.job_work_sessions
  set ended_at = coalesce(ended_at, now())
  where job_id = p_job_id
    and ended_at is null;

  insert into public.job_events(job_id, event_type, old_status, new_status, notes, actor_user_id, actor_tech_name)
  values (p_job_id, 'complete_job', v_old, 'completed', nullif(trim(coalesce(p_note,'')),''), auth.uid(), nullif(v_actor,''));
end;
$$;

alter table public.job_work_sessions enable row level security;
alter table public.job_events enable row level security;
alter table public.job_checklist_items enable row level security;

drop policy if exists job_work_sessions_admin_all on public.job_work_sessions;
create policy job_work_sessions_admin_all on public.job_work_sessions
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists job_work_sessions_tech_select on public.job_work_sessions;
create policy job_work_sessions_tech_select on public.job_work_sessions
for select using (public.can_access_job(job_id));

drop policy if exists job_events_admin_all on public.job_events;
create policy job_events_admin_all on public.job_events
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists job_events_tech_select on public.job_events;
create policy job_events_tech_select on public.job_events
for select using (public.can_access_job(job_id));

drop policy if exists job_checklist_items_admin_all on public.job_checklist_items;
create policy job_checklist_items_admin_all on public.job_checklist_items
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists job_checklist_items_tech_select on public.job_checklist_items;
create policy job_checklist_items_tech_select on public.job_checklist_items
for select using (public.can_access_job(job_id));

grant execute on function public.current_tech_name() to authenticated;
grant execute on function public.ensure_job_checklist(uuid) to authenticated;
grant execute on function public.tech_start_job(uuid, text) to authenticated;
grant execute on function public.tech_end_work_session(uuid, text) to authenticated;
grant execute on function public.tech_toggle_checklist_item(uuid, boolean) to authenticated;
grant execute on function public.tech_set_job_cancelled(uuid, boolean, text, text) to authenticated;
grant execute on function public.tech_mark_job_completed(uuid, text) to authenticated;

commit;
