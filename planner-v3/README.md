# Dispatch Planner V3

This is a separate planning app layer for GOCO and MCN workflows.

## Purpose

- Keep `index.html` as the operational calendar/viewer.
- Move planning, optimization, and approval cycles into a dedicated app.
- Publish approved plans to operational `jobs` data only when ready.

## Core Workflow

1. Import one or many files into a planning run.
2. Normalize and enrich jobs (client, region, constraints).
3. Generate a proposal version.
4. Submit GOCO proposal for approval.
5. Receive approvals/rejections and create next version.
6. Publish approved jobs to live dispatch.

## Client Behavior

- GOCO: suggested dates are preserved by default and require approval for date changes.
- MCN: optimize dates/routes by regional clustering; 1 or 2 tech assignment per job.

## Safety Rule

The planner stores all rounds and decisions. The live calendar should read only published/approved state.

## Phase 1 Runbook (Supabase)

1. Run migration: `planner-v3/db/30_planner_v3_workflow.sql`
   - If you already ran it before, run it again to apply latest idempotent updates (publish audit + dynamic constraints).
2. Execute smoke tests:

```sql
-- create run + round 1
select public.planner_create_run('GOCO-MCN Pilot', 2026) as run_id;

-- get version id
select id, run_id, round_no, version_status
from public.planner_versions
order by created_at desc
limit 5;

-- seed jobs for a date window
select public.planner_seed_version_from_live_jobs(
  '<version_uuid_here>',
  date '2026-01-01',
  date '2026-03-31',
  null
) as seeded_rows;

-- check planner status view
select *
from public.v_planner_version_status
where version_id = '<version_uuid_here>'::uuid;

-- publish mode (GOCO approved only)
select *
from public.planner_publish_version('<version_uuid_here>'::uuid, 'approved_only');

-- apply dynamic constraints to current proposal version
select *
from public.planner_apply_constraints('<version_uuid_here>'::uuid, true);

-- audit publish items
select action, result, count(*)
from public.planner_publish_items
group by action, result
order by action, result;

-- verify dynamic constraint table
select tech_name, allowed_clients, mobility_mode, region_scope, goco_max_per_day, total_max_per_day, mcn_team_default, fallback_rank, is_active
from public.planner_tech_constraints
order by fallback_rank, tech_name;
```
