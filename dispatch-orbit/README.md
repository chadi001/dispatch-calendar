# Dispatch Orbit (V2 Preview)

This is a fresh V2 build that runs in parallel with the legacy app.

- Legacy app remains untouched in `index.html` and `onsite-install.html`.
- New app lives in `dispatch-orbit/`.
- New backend contract lives in `dispatch-orbit/db_v2/`.

## V2 goals

- User identity based on `auth.users.id` (no name-based access control)
- Minimal and normalized schema
- Deterministic RLS and RPC-based reads/writes
- Calendar page clean for planning visibility
- Onsite page dedicated to execution actions and checklist

## Files

- `dispatch-orbit/index.html` - calendar view
- `dispatch-orbit/onsite.html` - onsite execution
- `dispatch-orbit/dashboard.html` - KPI view
- `dispatch-orbit/app.css` - shared styling
- `dispatch-orbit/app.js` - calendar logic
- `dispatch-orbit/onsite.js` - onsite logic
- `dispatch-orbit/dashboard.js` - KPI logic

## SQL order (Supabase)

1. `db_v2/01_core.sql`
2. `db_v2/02_rls.sql`
3. `db_v2/03_rpc.sql`
4. `db_v2/04_backfill_from_v1.sql` (optional for migration)
