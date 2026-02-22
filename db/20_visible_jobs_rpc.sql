-- Provide deterministic job visibility for tech sessions
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
     or j.assigned_user_id = auth.uid()
     or exists (
       select 1
       from public.job_assignments ja
       where ja.job_id = j.id
         and ja.user_id = auth.uid()
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

grant execute on function public.current_tech_names() to authenticated;
grant execute on function public.list_visible_jobs() to authenticated;

commit;
