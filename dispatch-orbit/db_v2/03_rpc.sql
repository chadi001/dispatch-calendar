begin;

create or replace function public.dispatch_v2_current_profile()
returns table(user_id uuid, display_name text, role text)
language sql
stable
security definer
set search_path = public
as $$
  select p.user_id, p.display_name, p.role
  from public.dispatch_v2_profiles p
  where p.user_id = auth.uid()
    and p.active = true;
$$;

create or replace function public.dispatch_v2_list_visible_jobs(
  p_from date default null,
  p_to date default null,
  p_include_cancelled boolean default true
)
returns table(
  id uuid,
  work_order text,
  client_code text,
  site_code text,
  site_name text,
  address text,
  city text,
  province text,
  postal_code text,
  scheduled_date date,
  scheduled_slot text,
  status text,
  cancel_reason_code text,
  cancel_reason_note text,
  actual_start_at timestamptz,
  actual_end_at timestamptz,
  primary_assignee text,
  assignees text[]
)
language sql
stable
security definer
set search_path = public
as $$
  select
    j.id,
    j.work_order,
    j.client_code,
    j.site_code,
    j.site_name,
    j.address,
    j.city,
    j.province,
    j.postal_code,
    j.scheduled_date,
    j.scheduled_slot,
    j.status,
    j.cancel_reason_code,
    j.cancel_reason_note,
    j.actual_start_at,
    j.actual_end_at,
    (
      select p.display_name
      from public.dispatch_v2_job_assignments a
      join public.dispatch_v2_profiles p on p.user_id = a.user_id
      where a.job_id = j.id
      order by a.is_primary desc, a.assignment_role asc, p.display_name asc
      limit 1
    ) as primary_assignee,
    (
      select coalesce(array_agg(p.display_name order by a.is_primary desc, p.display_name), '{}')
      from public.dispatch_v2_job_assignments a
      join public.dispatch_v2_profiles p on p.user_id = a.user_id
      where a.job_id = j.id
    ) as assignees
  from public.dispatch_v2_jobs j
  where public.dispatch_v2_can_access_job(j.id)
    and (p_from is null or j.scheduled_date >= p_from)
    and (p_to is null or j.scheduled_date <= p_to)
    and (p_include_cancelled or j.status <> 'cancelled')
  order by j.scheduled_date asc, j.scheduled_slot asc, j.work_order asc;
$$;

create or replace function public.dispatch_v2_ensure_job_checklist(p_job_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template_id uuid;
  v_inserted int := 0;
begin
  if not public.dispatch_v2_can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  if exists(select 1 from public.dispatch_v2_job_checklist_items i where i.job_id = p_job_id) then
    return 0;
  end if;

  select t.id
  into v_template_id
  from public.dispatch_v2_jobs j
  join public.dispatch_v2_checklist_templates t
    on t.active = true
   and (t.client_code is null or upper(t.client_code) = upper(j.client_code))
  where j.id = p_job_id
  order by case when t.client_code is null then 1 else 0 end, t.created_at asc
  limit 1;

  if v_template_id is null then
    return 0;
  end if;

  insert into public.dispatch_v2_job_checklist_items(
    job_id, template_item_id, segment, sort_order, label, is_required
  )
  select
    p_job_id,
    i.id,
    i.segment,
    i.sort_order,
    i.label,
    i.is_required
  from public.dispatch_v2_checklist_template_items i
  where i.template_id = v_template_id
    and i.active = true
  order by i.sort_order;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create or replace function public.dispatch_v2_start_job(p_job_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.dispatch_v2_can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  update public.dispatch_v2_jobs
  set status = 'in_progress',
      actual_start_at = coalesce(actual_start_at, now())
  where id = p_job_id;

  insert into public.dispatch_v2_job_work_sessions(job_id, user_id, started_at, notes)
  values (p_job_id, auth.uid(), now(), nullif(trim(coalesce(p_note,'')), ''));

  insert into public.dispatch_v2_job_events(job_id, event_type, note, actor_user_id)
  values (p_job_id, 'start', nullif(trim(coalesce(p_note,'')), ''), auth.uid());
end;
$$;

create or replace function public.dispatch_v2_end_session(p_job_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.dispatch_v2_can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  update public.dispatch_v2_job_work_sessions
  set ended_at = now(),
      notes = coalesce(notes, nullif(trim(coalesce(p_note,'')), ''))
  where id = (
    select s.id
    from public.dispatch_v2_job_work_sessions s
    where s.job_id = p_job_id
      and s.user_id = auth.uid()
      and s.ended_at is null
    order by s.started_at desc
    limit 1
  );

  insert into public.dispatch_v2_job_events(job_id, event_type, note, actor_user_id)
  values (p_job_id, 'end_session', nullif(trim(coalesce(p_note,'')), ''), auth.uid());
end;
$$;

create or replace function public.dispatch_v2_mark_completed(p_job_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_missing int;
begin
  if not public.dispatch_v2_can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  select count(*) into v_missing
  from public.dispatch_v2_job_checklist_items i
  where i.job_id = p_job_id
    and i.is_required = true
    and i.completed = false;

  if v_missing > 0 then
    raise exception 'required checklist items are not completed';
  end if;

  update public.dispatch_v2_jobs
  set status = 'completed',
      actual_end_at = coalesce(actual_end_at, now())
  where id = p_job_id;

  update public.dispatch_v2_job_work_sessions
  set ended_at = now()
  where job_id = p_job_id
    and ended_at is null;

  insert into public.dispatch_v2_job_events(job_id, event_type, note, actor_user_id)
  values (p_job_id, 'complete', nullif(trim(coalesce(p_note,'')), ''), auth.uid());
end;
$$;

create or replace function public.dispatch_v2_set_cancelled(
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
begin
  if not public.dispatch_v2_can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  update public.dispatch_v2_jobs
  set status = case when p_cancelled then 'cancelled' else 'scheduled' end,
      cancel_reason_code = case when p_cancelled then nullif(trim(coalesce(p_reason_code,'')), '') else null end,
      cancel_reason_note = case when p_cancelled then nullif(trim(coalesce(p_reason_note,'')), '') else null end
  where id = p_job_id;

  insert into public.dispatch_v2_job_events(job_id, event_type, payload, note, actor_user_id)
  values (
    p_job_id,
    case when p_cancelled then 'cancel' else 'restore' end,
    jsonb_build_object('reason_code', p_reason_code),
    nullif(trim(coalesce(p_reason_note,'')), ''),
    auth.uid()
  );
end;
$$;

create or replace function public.dispatch_v2_toggle_checklist_item(
  p_item_id uuid,
  p_completed boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job uuid;
begin
  select i.job_id into v_job
  from public.dispatch_v2_job_checklist_items i
  where i.id = p_item_id;

  if v_job is null then
    raise exception 'checklist item not found';
  end if;
  if not public.dispatch_v2_can_access_job(v_job) then
    raise exception 'access denied';
  end if;

  update public.dispatch_v2_job_checklist_items
  set completed = p_completed,
      completed_at = case when p_completed then now() else null end,
      completed_by = case when p_completed then auth.uid() else null end,
      notes = case when nullif(trim(coalesce(p_note,'')), '') is not null then nullif(trim(coalesce(p_note,'')), '') else notes end
  where id = p_item_id;

  insert into public.dispatch_v2_job_events(job_id, event_type, payload, actor_user_id)
  values (v_job, 'checklist_toggle', jsonb_build_object('item_id', p_item_id, 'completed', p_completed), auth.uid());
end;
$$;

create or replace function public.dispatch_v2_add_note(p_job_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_note text;
begin
  if not public.dispatch_v2_can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;
  v_note := nullif(trim(coalesce(p_note,'')), '');
  if v_note is null then
    raise exception 'note is required';
  end if;

  insert into public.dispatch_v2_job_events(job_id, event_type, note, actor_user_id)
  values (p_job_id, 'note', v_note, auth.uid());
end;
$$;

grant execute on function public.dispatch_v2_current_profile() to authenticated;
grant execute on function public.dispatch_v2_list_visible_jobs(date, date, boolean) to authenticated;
grant execute on function public.dispatch_v2_ensure_job_checklist(uuid) to authenticated;
grant execute on function public.dispatch_v2_start_job(uuid, text) to authenticated;
grant execute on function public.dispatch_v2_end_session(uuid, text) to authenticated;
grant execute on function public.dispatch_v2_mark_completed(uuid, text) to authenticated;
grant execute on function public.dispatch_v2_set_cancelled(uuid, boolean, text, text) to authenticated;
grant execute on function public.dispatch_v2_toggle_checklist_item(uuid, boolean, text) to authenticated;
grant execute on function public.dispatch_v2_add_note(uuid, text) to authenticated;

commit;
