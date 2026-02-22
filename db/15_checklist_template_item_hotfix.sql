-- Hotfix: relax legacy checklist constraints for current workflow
begin;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'job_checklist_items'
      AND column_name = 'template_item_id'
  ) THEN
    EXECUTE 'ALTER TABLE public.job_checklist_items ALTER COLUMN template_item_id DROP NOT NULL';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'job_checklist_items'
      AND column_name = 'job_checklist_id'
  ) THEN
    EXECUTE 'ALTER TABLE public.job_checklist_items ALTER COLUMN job_checklist_id DROP DEFAULT';
    EXECUTE 'ALTER TABLE public.job_checklist_items ALTER COLUMN job_checklist_id DROP NOT NULL';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'job_checklist_items'
      AND constraint_name = 'job_checklist_items_job_checklist_id_fkey'
  ) THEN
    EXECUTE 'ALTER TABLE public.job_checklist_items DROP CONSTRAINT job_checklist_items_job_checklist_id_fkey';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'job_checklist_items'
      AND constraint_name = 'job_checklist_items_template_item_id_fkey'
  ) THEN
    EXECUTE 'ALTER TABLE public.job_checklist_items DROP CONSTRAINT job_checklist_items_template_item_id_fkey';
  END IF;
END $$;

commit;
