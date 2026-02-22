-- Hotfix: legacy checklist schema + richer onsite checklist protocol
begin;

-- 1) Legacy compatibility: some environments have job_checklist_id NOT NULL without default
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='job_checklist_items'
      AND column_name='job_checklist_id'
  ) THEN
    EXECUTE 'ALTER TABLE public.job_checklist_items ALTER COLUMN job_checklist_id SET DEFAULT gen_random_uuid()';
    EXECUTE 'UPDATE public.job_checklist_items SET job_checklist_id = gen_random_uuid() WHERE job_checklist_id IS NULL';
  END IF;
END$$;

-- 2) Ensure postal_code field exists for dispatch visibility
ALTER TABLE IF EXISTS public.jobs
  ADD COLUMN IF NOT EXISTS postal_code text;

-- 3) Rich standardized checklist protocol (arrival -> delivery -> exit)
CREATE OR REPLACE FUNCTION public.ensure_job_checklist(p_job_id uuid)
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

  -- Shared protocol for all jobs (arrival + closeout discipline)
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

  -- MCN-specific quality controls
  if v_client = 'MCN' then
    insert into public.job_checklist_items(job_id, sort_order, title, is_required)
    values
      (p_job_id, 160, 'MCN: Verify wall outlet and rack standard compliance', true),
      (p_job_id, 170, 'MCN: Confirm patch panel port map and naming convention', true),
      (p_job_id, 180, 'MCN: Upload report links and mandatory evidence', true);
  end if;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.ensure_job_checklist(uuid) to authenticated;

commit;
