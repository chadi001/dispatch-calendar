-- Checklist update: remove MCN-only tail and add tech notes RPC
begin;

create or replace function public.ensure_job_checklist(p_job_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  if p_job_id is null then
    return 0;
  end if;

  if exists(select 1 from public.job_checklist_items i where i.job_id = p_job_id) then
    return 0;
  end if;

  insert into public.job_checklist_items(job_id, sort_order, title, is_required)
  values
    (p_job_id, 10, 'Park vehicle safely and according to site/customer rules', true),
    (p_job_id, 20, 'Check in with customer / site contact on arrival', true),
    (p_job_id, 30, 'Review work order, scope, and site constraints', true),
    (p_job_id, 40, 'Validate route/cable plan and decide execution approach', true),
    (p_job_id, 50, 'Capture BEFORE photos (key areas / cable paths)', true),
    (p_job_id, 60, 'Install/route cables according to plan and standards', true),
    (p_job_id, 70, 'Install and secure wall plate / plaque mural', true),
    (p_job_id, 80, 'Terminate and organize patch panel connections', true),
    (p_job_id, 90, 'Label/tag all new cables for identification', true),
    (p_job_id, 100, 'Run validation tests (signal/continuity/quality)', true),
    (p_job_id, 110, 'Capture AFTER photos (final state and labels)', true),
    (p_job_id, 120, 'Customer walkthrough and delivery/sign-off confirmation', true),
    (p_job_id, 130, 'Clean work area and remove debris/packaging', true),
    (p_job_id, 140, 'Closeout notes completed before leaving site', true),
    (p_job_id, 150, 'Leave site and mark departure', true);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.tech_add_job_note(p_job_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor text;
  v_clean text;
begin
  if not public.can_access_job(p_job_id) then
    raise exception 'access denied';
  end if;

  v_clean := nullif(trim(coalesce(p_note,'')), '');
  if v_clean is null then
    raise exception 'note is required';
  end if;

  v_actor := coalesce(public.current_tech_name(), '');

  insert into public.job_events(job_id, event_type, notes, actor_user_id, actor_tech_name)
  values (p_job_id, 'tech_note', v_clean, auth.uid(), nullif(v_actor,''));
end;
$$;

delete from public.job_checklist_items
where title like 'MCN:%'
   or sort_order >= 160;

grant execute on function public.ensure_job_checklist(uuid) to authenticated;
grant execute on function public.tech_add_job_note(uuid, text) to authenticated;

commit;
