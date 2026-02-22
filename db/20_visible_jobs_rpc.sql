-- Provide deterministic job visibility for tech sessions
begin;

-- Bridge to user-id identity (keeps tech_name compatibility)
alter table if exists public.jobs
  add column if not exists assigned_user_id uuid references auth.users(id);

alter table if exists public.job_assignments
  add column if not exists user_id uuid references auth.users(id);

create index if not exists idx_jobs_assigned_user_id on public.jobs(assigned_user_id);
create index if not exists idx_job_assignments_user_id on public.job_assignments(user_id);

update public.job_assignments ja
set user_id = coalesce(
  ja.user_id,
  (
    select tnm.user_id
    from public.tech_name_map tnm
    where lower(btrim(coalesce(tnm.tech_name, ''))) = lower(btrim(coalesce(ja.tech_name, '')))
      and coalesce(tnm.is_active, true)
    order by tnm.created_at asc nulls last
    limit 1
  ),
  (
    select tp.user_id
    from public.tech_profiles tp
    where lower(btrim(coalesce(tp.display_name, ''))) = lower(btrim(coalesce(ja.tech_name, '')))
      and coalesce(tp.is_active, true)
    order by tp.created_at asc nulls last
    limit 1
  )
)
where ja.user_id is null;

update public.jobs j
set assigned_user_id = coalesce(
  j.assigned_user_id,
  (
    select tnm.user_id
    from public.tech_name_map tnm
    where lower(btrim(coalesce(tnm.tech_name, ''))) = lower(btrim(coalesce(j.tech_name, '')))
      and coalesce(tnm.is_active, true)
    order by tnm.created_at asc nulls last
    limit 1
  ),
  (
    select tp.user_id
    from public.tech_profiles tp
    where lower(btrim(coalesce(tp.display_name, ''))) = lower(btrim(coalesce(j.tech_name, '')))
      and coalesce(tp.is_active, true)
    order by tp.created_at asc nulls last
    limit 1
  )
)
where j.assigned_user_id is null;

create or replace function public.current_actor_user_ids()
returns table(user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() as user_id
  where auth.uid() is not null

  union

  select distinct tnm.user_id
  from public.tech_name_map tnm
  where tnm.user_id = auth.uid()
    and coalesce(tnm.is_active, true)

  union

  select distinct tp.user_id
  from public.tech_profiles tp
  where tp.user_id = auth.uid()
    and coalesce(tp.is_active, true);
$$;

create or replace function public.current_tech_names()
returns table(tech_name text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct nullif(btrim(tnm.tech_name), '') as tech_name
  from public.tech_name_map tnm
  where tnm.user_id = auth.uid()
    and coalesce(tnm.is_active, true)
    and nullif(btrim(tnm.tech_name), '') is not null

  union

  select distinct nullif(btrim(tp.display_name), '') as tech_name
  from public.tech_profiles tp
  where tp.user_id = auth.uid()
    and coalesce(tp.is_active, true)
    and nullif(btrim(tp.display_name), '') is not null;
$$;

create or replace function public.list_visible_jobs()
returns setof public.jobs
language sql
stable
security definer
set search_path = public
as $$
  select j.*
  from public.jobs j
  where public.is_admin_user()
     or exists (
       select 1
       from public.current_actor_user_ids() u
       where u.user_id = j.assigned_user_id
     )
     or exists (
       select 1
       from public.job_assignments ja
       where ja.job_id = j.id
         and exists (
           select 1
           from public.current_actor_user_ids() u
           where u.user_id = ja.user_id
         )
     )
     or exists (
       select 1
       from public.current_tech_names() n
       where lower(btrim(coalesce(j.tech_name, ''))) = lower(btrim(coalesce(n.tech_name, '')))
     )
     or exists (
       select 1
       from public.job_assignments ja
       where ja.job_id = j.id
         and exists (
           select 1
           from public.current_tech_names() n
           where lower(btrim(coalesce(ja.tech_name, ''))) = lower(btrim(coalesce(n.tech_name, '')))
         )
     )
  order by j.job_date asc nulls last, j.created_at asc nulls last;
$$;

create or replace view public.v_jobs_assignment_audit as
select
  j.id,
  j.job_date,
  j.tech_name,
  j.assigned_user_id,
  exists(
    select 1
    from public.job_assignments ja
    where ja.job_id = j.id
      and coalesce(nullif(btrim(ja.tech_name), ''), 'UNASSIGNED') <> 'UNASSIGNED'
  ) as has_assignment_rows,
  case
    when coalesce(nullif(btrim(j.tech_name), ''), 'UNASSIGNED') = 'UNASSIGNED'
         and exists(
           select 1
           from public.job_assignments ja
           where ja.job_id = j.id
             and coalesce(nullif(btrim(ja.tech_name), ''), 'UNASSIGNED') <> 'UNASSIGNED'
         )
      then 'lead_missing'
    when coalesce(nullif(btrim(j.tech_name), ''), 'UNASSIGNED') <> 'UNASSIGNED'
         and j.assigned_user_id is null
      then 'missing_user_id'
    else 'ok'
  end as assignment_state
from public.jobs j;

grant execute on function public.current_tech_names() to authenticated;
grant execute on function public.current_actor_user_ids() to authenticated;
grant execute on function public.list_visible_jobs() to authenticated;

commit;
