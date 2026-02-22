-- Fix tech visibility inconsistencies by using all active aliases
begin;

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

create or replace function public.current_tech_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  with names as (
    select lower(btrim(tech_name)) as key_name, btrim(tech_name) as raw_name
    from public.current_tech_names()
  )
  select raw_name
  from names
  order by key_name
  limit 1;
$$;

create or replace function public.can_access_job(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin_user()
    or exists (
      select 1
      from public.jobs j
      where j.id = p_job_id
        and exists (
          select 1
          from public.current_tech_names() n
          where lower(btrim(coalesce(j.tech_name, ''))) = lower(btrim(coalesce(n.tech_name, '')))
        )
    )
    or exists (
      select 1
      from public.job_assignments ja
      where ja.job_id = p_job_id
        and exists (
          select 1
          from public.current_tech_names() n
          where lower(btrim(coalesce(ja.tech_name, ''))) = lower(btrim(coalesce(n.tech_name, '')))
        )
    );
$$;

drop policy if exists jobs_tech_select_own on public.jobs;
create policy jobs_tech_select_own on public.jobs
for select
using (
  exists (
    select 1
    from public.current_tech_names() n
    where lower(btrim(coalesce(jobs.tech_name, ''))) = lower(btrim(coalesce(n.tech_name, '')))
  )
  or exists (
    select 1
    from public.job_assignments ja
    where ja.job_id = jobs.id
      and exists (
        select 1
        from public.current_tech_names() n
        where lower(btrim(coalesce(ja.tech_name, ''))) = lower(btrim(coalesce(n.tech_name, '')))
      )
  )
);

drop policy if exists job_assignments_tech_select on public.job_assignments;
create policy job_assignments_tech_select on public.job_assignments
for select
using (
  exists (
    select 1
    from public.current_tech_names() n
    where lower(btrim(coalesce(job_assignments.tech_name, ''))) = lower(btrim(coalesce(n.tech_name, '')))
  )
);

grant execute on function public.current_tech_names() to authenticated;
grant execute on function public.current_tech_name() to authenticated;
grant execute on function public.can_access_job(uuid) to authenticated;

commit;
