-- Hotfix: allow checklist seeding on legacy schemas requiring template_item_id
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

commit;
