-- Backfill jobs.postal_code from public.staging_jobs_import
-- Safe update: only fills missing/invalid postal values in jobs.

begin;

with src as (
  select
    trim(coalesce(work_order, '')) as wo,
    upper(trim(coalesce(postal_code, ''))) as postal_raw
  from public.staging_jobs_import
  where trim(coalesce(work_order, '')) <> ''
), normalized as (
  select
    wo,
    regexp_replace(postal_raw, '[^A-Z0-9]', '', 'g') as compact
  from src
), valid as (
  select
    wo,
    compact as postal_code
  from normalized
  where compact ~ '^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$'
), dedup as (
  select wo, min(postal_code) as postal_code
  from valid
  group by wo
)
update public.jobs j
set postal_code = d.postal_code
from dedup d
where trim(coalesce(j.wo, '')) = d.wo
  and coalesce(trim(j.postal_code), '') !~ '^[A-Za-z][0-9][A-Za-z][ -]?[0-9][A-Za-z][0-9]$';

-- Verification snapshot
select
  count(*) as total_jobs,
  count(*) filter (where coalesce(trim(postal_code), '') = '') as missing_postal,
  count(*) filter (where upper(regexp_replace(coalesce(trim(postal_code), ''), '[^A-Z0-9]', '', 'g')) ~ '^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$') as valid_postal
from public.jobs;

commit;
