# Dispatch Orbit V2 Plan

## Why V2

- V1 has accumulated hotfix-driven complexity.
- Identity/access relies on both names and user ids in different places.
- Frontend has one very large script surface and mixed responsibilities.

## Approach

- Keep V1 running.
- Build V2 as parallel app (`dispatch-orbit/`).
- Migrate data in controlled stages.
- Cut over only after parity checks pass.

## Cutover phases

1. Deploy V2 schema + RLS + RPC (`db_v2/01..03`).
2. Backfill a copy of current data into V2 (`db_v2/04`).
3. Validate with admin + 2 tech accounts:
   - visible job counts,
   - onsite actions,
   - checklist enforcement,
   - cancel/restore,
   - KPI consistency.
4. Freeze V1 writes and run final incremental sync.
5. Switch links to V2 pages.

## Validation checklist

- Same number of visible jobs between admin and expected tech permissions.
- No name-based visibility mismatch.
- Completed jobs always visible and green-marked in calendar.
- Onsite actions update status/events/work sessions correctly.
- Postal code normalized and shown where intended.
