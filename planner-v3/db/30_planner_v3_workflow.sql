-- Planner V3 foundation: proposal rounds + GOCO approval cycle + publish gate
begin;

create table if not exists public.planner_client_profiles (
  client_code text primary key,
  keep_suggested_date boolean not null default false,
  require_external_approval boolean not null default false,
  default_team_size int not null default 1,
  allow_date_shift boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (default_team_size between 1 and 4)
);

insert into public.planner_client_profiles (client_code, keep_suggested_date, require_external_approval, default_team_size, allow_date_shift)
values
  ('GOCO', true, true, 1, false),
  ('MCN', false, false, 2, true)
on conflict (client_code) do nothing;

create table if not exists public.planner_runs (
  id uuid primary key default gen_random_uuid(),
  run_name text not null,
  run_year int not null,
  status text not null default 'draft',
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status in ('draft','submitted','partially_approved','approved','published','archived'))
);

create table if not exists public.planner_versions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.planner_runs(id) on delete cascade,
  round_no int not null,
  version_status text not null default 'draft',
  submitted_at timestamptz,
  reviewed_at timestamptz,
  published_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique(run_id, round_no),
  check (version_status in ('draft','submitted','partially_approved','approved','published','rejected'))
);

create table if not exists public.planner_jobs (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.planner_versions(id) on delete cascade,
  source_job_id uuid,
  client_code text not null,
  wo text,
  site text,
  region text,
  suggested_date date,
  proposed_date date not null,
  proposed_slot text not null default 'AM',
  lead_tech_name text not null default 'UNASSIGNED',
  required_tech_count int not null default 1,
  additional_tech_names text[] not null default '{}',
  is_locked boolean not null default false,
  created_at timestamptz not null default now(),
  check (proposed_slot in ('AM','PM')),
  check (required_tech_count between 1 and 4)
);

create index if not exists idx_planner_jobs_version on public.planner_jobs(version_id);
create index if not exists idx_planner_jobs_source_job on public.planner_jobs(source_job_id);

create table if not exists public.planner_goco_decisions (
  id uuid primary key default gen_random_uuid(),
  planner_job_id uuid not null references public.planner_jobs(id) on delete cascade,
  decision text not null default 'pending',
  decided_date date,
  decision_note text,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  check (decision in ('pending','approved','rejected','counter_proposed'))
);

create unique index if not exists uq_planner_goco_decision_job on public.planner_goco_decisions(planner_job_id);

create table if not exists public.planner_publish_events (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.planner_versions(id) on delete cascade,
  published_by uuid,
  published_at timestamptz not null default now(),
  mode text not null default 'approved_only',
  note text,
  check (mode in ('approved_only','approved_and_internal'))
);

create table if not exists public.planner_publish_items (
  id uuid primary key default gen_random_uuid(),
  publish_event_id uuid not null references public.planner_publish_events(id) on delete cascade,
  planner_job_id uuid not null references public.planner_jobs(id) on delete cascade,
  target_job_id uuid references public.jobs(id) on delete set null,
  action text not null,
  result text not null,
  error_message text,
  created_at timestamptz not null default now(),
  check (action in ('insert','update','skip')),
  check (result in ('success','error'))
);

create or replace view public.v_planner_version_status as
select
  v.id as version_id,
  v.run_id,
  v.round_no,
  v.version_status,
  count(pj.id) as jobs_total,
  count(*) filter (where lower(coalesce(pj.client_code,''))='goco') as goco_jobs,
  count(*) filter (where gd.decision='approved') as approved_jobs,
  count(*) filter (where gd.decision='rejected') as rejected_jobs,
  count(*) filter (where gd.decision='pending') as pending_jobs
from public.planner_versions v
left join public.planner_jobs pj on pj.version_id = v.id
left join public.planner_goco_decisions gd on gd.planner_job_id = pj.id
group by v.id, v.run_id, v.round_no, v.version_status;

create or replace function public.planner_create_run(
  p_run_name text,
  p_run_year int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin only';
  end if;
  if coalesce(btrim(p_run_name),'') = '' then
    raise exception 'p_run_name is required';
  end if;
  if p_run_year < 2000 or p_run_year > 2100 then
    raise exception 'p_run_year is invalid';
  end if;

  insert into public.planner_runs(run_name, run_year, status, created_by)
  values (btrim(p_run_name), p_run_year, 'draft', auth.uid())
  returning id into v_run_id;

  insert into public.planner_versions(run_id, round_no, version_status, created_by)
  values (v_run_id, 1, 'draft', auth.uid());

  return v_run_id;
end;
$$;

create or replace function public.planner_seed_version_from_live_jobs(
  p_version_id uuid,
  p_date_from date,
  p_date_to date,
  p_client_filter text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows int := 0;
begin
  if not public.is_admin_user() then
    raise exception 'Admin only';
  end if;
  if p_version_id is null then
    raise exception 'p_version_id is required';
  end if;
  if p_date_from is null or p_date_to is null or p_date_to < p_date_from then
    raise exception 'Invalid date range';
  end if;

  insert into public.planner_jobs(
    version_id, source_job_id, client_code, wo, site, region,
    suggested_date, proposed_date, proposed_slot, lead_tech_name,
    required_tech_count, additional_tech_names, is_locked
  )
  select
    p_version_id,
    j.id,
    upper(coalesce(nullif(btrim(j.client),''), 'UNKNOWN')),
    j.wo,
    coalesce(j.site, j.prov_site),
    j.city,
    j.job_date,
    j.job_date,
    coalesce(nullif(btrim(coalesce(j.plage, j.slot)),''), 'AM'),
    coalesce(nullif(btrim(j.tech_name),''), 'UNASSIGNED'),
    case when upper(coalesce(j.client,''))='MCN' then 2 else 1 end,
    '{}'::text[],
    false
  from public.jobs j
  where j.job_date between p_date_from and p_date_to
    and (p_client_filter is null or upper(coalesce(j.client,'')) = upper(p_client_filter));

  get diagnostics v_rows = row_count;

  insert into public.planner_goco_decisions(planner_job_id, decision)
  select pj.id, 'pending'
  from public.planner_jobs pj
  where pj.version_id = p_version_id
    and upper(coalesce(pj.client_code,''))='GOCO'
  on conflict (planner_job_id) do nothing;

  return v_rows;
end;
$$;

create or replace function public.planner_publish_version(
  p_version_id uuid,
  p_mode text default 'approved_only'
)
returns table(updated_jobs int, inserted_jobs int, skipped_jobs int, failed_jobs int)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_publish_id uuid;
  v_updated int := 0;
  v_inserted int := 0;
  v_skipped int := 0;
  v_failed int := 0;
  v_apply boolean;
  v_target_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin only';
  end if;
  if p_version_id is null then
    raise exception 'p_version_id is required';
  end if;
  if p_mode not in ('approved_only','approved_and_internal') then
    raise exception 'Invalid mode';
  end if;

  insert into public.planner_publish_events(version_id, published_by, mode)
  values (p_version_id, auth.uid(), p_mode)
  returning id into v_publish_id;

  for r in
    select
      pj.*,
      coalesce(gd.decision, case when upper(coalesce(pj.client_code,''))='GOCO' then 'pending' else 'approved' end) as decision
    from public.planner_jobs pj
    left join public.planner_goco_decisions gd on gd.planner_job_id = pj.id
    where pj.version_id = p_version_id
    order by pj.created_at asc
  loop
    v_apply := false;
    if upper(coalesce(r.client_code,''))='GOCO' then
      v_apply := (r.decision = 'approved');
    else
      v_apply := (p_mode = 'approved_and_internal' or p_mode = 'approved_only');
    end if;

    if not v_apply then
      v_skipped := v_skipped + 1;
      insert into public.planner_publish_items(
        publish_event_id, planner_job_id, target_job_id, action, result, error_message
      ) values (
        v_publish_id, r.id, r.source_job_id, 'skip', 'success', 'not eligible by decision/mode'
      );
      continue;
    end if;

    begin
      if r.source_job_id is not null then
        update public.jobs
        set
          job_date = r.proposed_date,
          tech_name = r.lead_tech_name,
          slot = r.proposed_slot,
          plage = r.proposed_slot
        where id = r.source_job_id;
        v_target_id := r.source_job_id;
        v_updated := v_updated + 1;
        insert into public.planner_publish_items(
          publish_event_id, planner_job_id, target_job_id, action, result
        ) values (
          v_publish_id, r.id, v_target_id, 'update', 'success'
        );
      else
        insert into public.jobs(
          job_date, tech_name, slot, plage, client, wo, site, city, status
        ) values (
          r.proposed_date,
          r.lead_tech_name,
          r.proposed_slot,
          r.proposed_slot,
          r.client_code,
          r.wo,
          r.site,
          r.region,
          'scheduled'
        ) returning id into v_target_id;
        v_inserted := v_inserted + 1;
        insert into public.planner_publish_items(
          publish_event_id, planner_job_id, target_job_id, action, result
        ) values (
          v_publish_id, r.id, v_target_id, 'insert', 'success'
        );
      end if;
    exception when others then
      v_failed := v_failed + 1;
      insert into public.planner_publish_items(
        publish_event_id, planner_job_id, target_job_id, action, result, error_message
      ) values (
        v_publish_id, r.id, r.source_job_id, case when r.source_job_id is null then 'insert' else 'update' end, 'error', sqlerrm
      );
    end;
  end loop;

  update public.planner_versions
  set version_status = case when v_failed = 0 then 'published' else version_status end,
      published_at = case when v_failed = 0 then now() else published_at end
  where id = p_version_id;

  return query select v_updated, v_inserted, v_skipped, v_failed;
end;
$$;

create or replace function public.planner_region_match(rule_region text, job_region text)
returns boolean
language sql
immutable
as $$
  select case
    when nullif(btrim(coalesce(rule_region,'')), '') is null then true
    when nullif(btrim(coalesce(job_region,'')), '') is null then false
    else lower(btrim(job_region)) = lower(btrim(rule_region))
      or lower(btrim(job_region)) like ('%' || lower(btrim(rule_region)) || '%')
      or lower(btrim(rule_region)) like ('%' || lower(btrim(job_region)) || '%')
  end;
$$;

create table if not exists public.planner_tech_constraints (
  id uuid primary key default gen_random_uuid(),
  tech_name text not null unique,
  allowed_clients text[] not null default array['ALL']::text[],
  mobility_mode text not null default 'flex',
  region_scope text,
  goco_max_per_day int not null default 2,
  total_max_per_day int not null default 2,
  mcn_team_default int not null default 2,
  fallback_rank int not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (mobility_mode in ('strict','preferred','flex')),
  check (goco_max_per_day between 0 and 8),
  check (total_max_per_day between 0 and 8),
  check (mcn_team_default between 1 and 4),
  check (fallback_rank between 1 and 999)
);

insert into public.planner_tech_constraints(
  tech_name, allowed_clients, mobility_mode, region_scope,
  goco_max_per_day, total_max_per_day, mcn_team_default, fallback_rank, is_active
)
values
  ('Adil',  array['GOCO'],         'strict',    'Montreal', 2, 2, 1, 10, true),
  ('Abdel', array['MCN','GOCO'],   'preferred', 'Distant',  2, 2, 2, 20, true),
  ('Chadi', array['ALL'],          'flex',      null,       2, 2, 1, 30, true),
  ('Tech A',array['ALL'],          'flex',      null,       2, 2, 1, 80, true),
  ('Tech B',array['ALL'],          'flex',      null,       2, 2, 1, 90, true)
on conflict (tech_name) do nothing;

alter table if exists public.planner_client_profiles enable row level security;
alter table if exists public.planner_runs enable row level security;
alter table if exists public.planner_versions enable row level security;
alter table if exists public.planner_jobs enable row level security;
alter table if exists public.planner_goco_decisions enable row level security;
alter table if exists public.planner_publish_events enable row level security;
alter table if exists public.planner_publish_items enable row level security;
alter table if exists public.planner_tech_constraints enable row level security;

drop policy if exists planner_client_profiles_admin_all on public.planner_client_profiles;
create policy planner_client_profiles_admin_all on public.planner_client_profiles
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planner_runs_admin_all on public.planner_runs;
create policy planner_runs_admin_all on public.planner_runs
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planner_versions_admin_all on public.planner_versions;
create policy planner_versions_admin_all on public.planner_versions
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planner_jobs_admin_all on public.planner_jobs;
create policy planner_jobs_admin_all on public.planner_jobs
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planner_goco_decisions_admin_all on public.planner_goco_decisions;
create policy planner_goco_decisions_admin_all on public.planner_goco_decisions
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planner_publish_events_admin_all on public.planner_publish_events;
create policy planner_publish_events_admin_all on public.planner_publish_events
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planner_publish_items_admin_all on public.planner_publish_items;
create policy planner_publish_items_admin_all on public.planner_publish_items
for all using (public.is_admin_user()) with check (public.is_admin_user());

drop policy if exists planner_tech_constraints_admin_all on public.planner_tech_constraints;
create policy planner_tech_constraints_admin_all on public.planner_tech_constraints
for all using (public.is_admin_user()) with check (public.is_admin_user());

create or replace function public.planner_apply_constraints(
  p_version_id uuid,
  p_keep_existing boolean default true
)
returns table(updated_jobs int, unresolved_jobs int)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_choice record;
  v_updated int := 0;
  v_unresolved int := 0;
  v_client text;
begin
  if not public.is_admin_user() then
    raise exception 'Admin only';
  end if;
  if p_version_id is null then
    raise exception 'p_version_id is required';
  end if;

  create temp table if not exists tmp_planner_day_load(
    work_date date not null,
    tech_name text not null,
    total_count int not null default 0,
    goco_count int not null default 0,
    primary key(work_date, tech_name)
  ) on commit drop;

  truncate table tmp_planner_day_load;

  if p_keep_existing then
    insert into tmp_planner_day_load(work_date, tech_name, total_count, goco_count)
    select
      pj.proposed_date,
      pj.lead_tech_name,
      count(*)::int as total_count,
      count(*) filter (where upper(coalesce(pj.client_code,''))='GOCO')::int as goco_count
    from public.planner_jobs pj
    where pj.version_id = p_version_id
      and upper(coalesce(pj.lead_tech_name,'')) <> 'UNASSIGNED'
    group by pj.proposed_date, pj.lead_tech_name;
  end if;

  for r in
    select
      pj.id,
      pj.proposed_date,
      upper(coalesce(pj.client_code,'')) as client_code,
      coalesce(pj.region,'') as region,
      coalesce(pj.lead_tech_name,'UNASSIGNED') as current_tech
    from public.planner_jobs pj
    where pj.version_id = p_version_id
    order by pj.proposed_date asc, pj.created_at asc
  loop
    v_client := r.client_code;

    select
      c.tech_name,
      c.mcn_team_default
    into v_choice
    from public.planner_tech_constraints c
    left join tmp_planner_day_load l
      on l.work_date = r.proposed_date
     and l.tech_name = c.tech_name
    where c.is_active
      and (
        'ALL' = any(c.allowed_clients)
        or v_client = any(c.allowed_clients)
      )
      and (
        c.mobility_mode <> 'strict'
        or public.planner_region_match(c.region_scope, r.region)
      )
      and coalesce(l.total_count, 0) < c.total_max_per_day
      and (
        v_client <> 'GOCO'
        or coalesce(l.goco_count, 0) < c.goco_max_per_day
      )
    order by
      case
        when c.mobility_mode = 'preferred' and not public.planner_region_match(c.region_scope, r.region) then 1
        else 0
      end,
      coalesce(l.total_count, 0) asc,
      c.fallback_rank asc,
      c.tech_name asc
    limit 1;

    if v_choice.tech_name is null then
      update public.planner_jobs
      set lead_tech_name = 'UNASSIGNED',
          required_tech_count = case when v_client = 'MCN' then 2 else 1 end,
          additional_tech_names = '{}'::text[]
      where id = r.id;
      v_unresolved := v_unresolved + 1;
      continue;
    end if;

    update public.planner_jobs
    set lead_tech_name = v_choice.tech_name,
        required_tech_count = case when v_client = 'MCN' then greatest(1, coalesce(v_choice.mcn_team_default, 2)) else 1 end,
        additional_tech_names = '{}'::text[]
    where id = r.id;
    v_updated := v_updated + 1;

    insert into tmp_planner_day_load(work_date, tech_name, total_count, goco_count)
    values (r.proposed_date, v_choice.tech_name, 1, case when v_client = 'GOCO' then 1 else 0 end)
    on conflict (work_date, tech_name) do update
      set total_count = tmp_planner_day_load.total_count + 1,
          goco_count = tmp_planner_day_load.goco_count + case when v_client = 'GOCO' then 1 else 0 end;
  end loop;

  return query select v_updated, v_unresolved;
end;
$$;

grant select on public.v_planner_version_status to authenticated;
grant execute on function public.planner_create_run(text, int) to authenticated;
grant execute on function public.planner_seed_version_from_live_jobs(uuid, date, date, text) to authenticated;
grant execute on function public.planner_publish_version(uuid, text) to authenticated;
grant execute on function public.planner_apply_constraints(uuid, boolean) to authenticated;
grant select, insert, update, delete on public.planner_tech_constraints to authenticated;

commit;
