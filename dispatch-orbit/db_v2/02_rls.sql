begin;

create or replace function public.dispatch_v2_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.dispatch_v2_profiles p
    where p.user_id = auth.uid()
      and p.active = true
      and p.role = 'admin'
  );
$$;

create or replace function public.dispatch_v2_can_access_job(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.dispatch_v2_is_admin()
    or exists (
      select 1
      from public.dispatch_v2_job_assignments a
      where a.job_id = p_job_id
        and a.user_id = auth.uid()
    );
$$;

alter table public.dispatch_v2_profiles enable row level security;
alter table public.dispatch_v2_jobs enable row level security;
alter table public.dispatch_v2_job_assignments enable row level security;
alter table public.dispatch_v2_checklist_templates enable row level security;
alter table public.dispatch_v2_checklist_template_items enable row level security;
alter table public.dispatch_v2_job_checklist_items enable row level security;
alter table public.dispatch_v2_job_work_sessions enable row level security;
alter table public.dispatch_v2_job_events enable row level security;

drop policy if exists dispatch_v2_profiles_select on public.dispatch_v2_profiles;
create policy dispatch_v2_profiles_select on public.dispatch_v2_profiles
for select
using (dispatch_v2_is_admin() or user_id = auth.uid());

drop policy if exists dispatch_v2_profiles_update on public.dispatch_v2_profiles;
create policy dispatch_v2_profiles_update on public.dispatch_v2_profiles
for update
using (dispatch_v2_is_admin() or user_id = auth.uid())
with check (dispatch_v2_is_admin() or user_id = auth.uid());

drop policy if exists dispatch_v2_jobs_select on public.dispatch_v2_jobs;
create policy dispatch_v2_jobs_select on public.dispatch_v2_jobs
for select
using (dispatch_v2_can_access_job(id));

drop policy if exists dispatch_v2_jobs_admin_write on public.dispatch_v2_jobs;
create policy dispatch_v2_jobs_admin_write on public.dispatch_v2_jobs
for all
using (dispatch_v2_is_admin())
with check (dispatch_v2_is_admin());

drop policy if exists dispatch_v2_assign_select on public.dispatch_v2_job_assignments;
create policy dispatch_v2_assign_select on public.dispatch_v2_job_assignments
for select
using (dispatch_v2_is_admin() or user_id = auth.uid() or dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_assign_admin_write on public.dispatch_v2_job_assignments;
create policy dispatch_v2_assign_admin_write on public.dispatch_v2_job_assignments
for all
using (dispatch_v2_is_admin())
with check (dispatch_v2_is_admin());

drop policy if exists dispatch_v2_templates_select on public.dispatch_v2_checklist_templates;
create policy dispatch_v2_templates_select on public.dispatch_v2_checklist_templates
for select
using (auth.uid() is not null);

drop policy if exists dispatch_v2_templates_admin_write on public.dispatch_v2_checklist_templates;
create policy dispatch_v2_templates_admin_write on public.dispatch_v2_checklist_templates
for all
using (dispatch_v2_is_admin())
with check (dispatch_v2_is_admin());

drop policy if exists dispatch_v2_template_items_select on public.dispatch_v2_checklist_template_items;
create policy dispatch_v2_template_items_select on public.dispatch_v2_checklist_template_items
for select
using (auth.uid() is not null);

drop policy if exists dispatch_v2_template_items_admin_write on public.dispatch_v2_checklist_template_items;
create policy dispatch_v2_template_items_admin_write on public.dispatch_v2_checklist_template_items
for all
using (dispatch_v2_is_admin())
with check (dispatch_v2_is_admin());

drop policy if exists dispatch_v2_job_checklist_select on public.dispatch_v2_job_checklist_items;
create policy dispatch_v2_job_checklist_select on public.dispatch_v2_job_checklist_items
for select
using (dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_job_checklist_update on public.dispatch_v2_job_checklist_items;
create policy dispatch_v2_job_checklist_update on public.dispatch_v2_job_checklist_items
for update
using (dispatch_v2_can_access_job(job_id))
with check (dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_job_checklist_insert on public.dispatch_v2_job_checklist_items;
create policy dispatch_v2_job_checklist_insert on public.dispatch_v2_job_checklist_items
for insert
with check (dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_job_work_select on public.dispatch_v2_job_work_sessions;
create policy dispatch_v2_job_work_select on public.dispatch_v2_job_work_sessions
for select
using (dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_job_work_insert on public.dispatch_v2_job_work_sessions;
create policy dispatch_v2_job_work_insert on public.dispatch_v2_job_work_sessions
for insert
with check (dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_job_work_update on public.dispatch_v2_job_work_sessions;
create policy dispatch_v2_job_work_update on public.dispatch_v2_job_work_sessions
for update
using (dispatch_v2_can_access_job(job_id))
with check (dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_job_events_select on public.dispatch_v2_job_events;
create policy dispatch_v2_job_events_select on public.dispatch_v2_job_events
for select
using (dispatch_v2_can_access_job(job_id));

drop policy if exists dispatch_v2_job_events_insert on public.dispatch_v2_job_events;
create policy dispatch_v2_job_events_insert on public.dispatch_v2_job_events
for insert
with check (dispatch_v2_can_access_job(job_id));

grant execute on function public.dispatch_v2_is_admin() to authenticated;
grant execute on function public.dispatch_v2_can_access_job(uuid) to authenticated;

commit;
