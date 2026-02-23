begin;

insert into public.dispatch_v2_profiles(user_id, display_name, role, active)
select distinct
  tnm.user_id,
  coalesce(nullif(trim(tp.display_name), ''), nullif(trim(tnm.tech_name), ''), 'Tech') as display_name,
  case when au.user_id is not null then 'admin' else 'tech' end as role,
  coalesce(tp.is_active, tnm.is_active, true) as active
from public.tech_name_map tnm
left join public.tech_profiles tp on tp.user_id = tnm.user_id
left join public.admin_users au on au.user_id = tnm.user_id
where tnm.user_id is not null
on conflict (user_id) do update
set display_name = excluded.display_name,
    role = excluded.role,
    active = excluded.active,
    updated_at = now();

insert into public.dispatch_v2_jobs(
  work_order, client_code, site_code, site_name, address, city, province, postal_code,
  scheduled_date, scheduled_slot, status, cancel_reason_code, cancel_reason_note,
  actual_start_at, actual_end_at, created_at, updated_at
)
select
  coalesce(nullif(trim(j.wo),''), nullif(trim(j.order_number),''), 'NO-WO-' || left(j.id::text, 8)) as work_order,
  case upper(trim(coalesce(j.client,''))) when 'COGO' then 'GOCO' else upper(trim(coalesce(j.client,'GOCO'))) end as client_code,
  nullif(trim(coalesce(j.prov_site, j.site_id, '')), '') as site_code,
  nullif(trim(coalesce(j.site, j.prov_site, '')), '') as site_name,
  nullif(trim(coalesce(j.address, '')), '') as address,
  nullif(trim(coalesce(j.city, '')), '') as city,
  nullif(trim(coalesce(j.province, '')), '') as province,
  nullif(trim(coalesce(j.postal_code, '')), '') as postal_code,
  j.job_date as scheduled_date,
  case when upper(coalesce(j.plage, j.slot, 'AM')) = 'PM' then 'PM' else 'AM' end as scheduled_slot,
  case
    when coalesce(j.status,'') in ('scheduled','in_progress','completed','cancelled','on_hold') then j.status
    when coalesce(j.cancelled,false) then 'cancelled'
    else 'scheduled'
  end as status,
  nullif(trim(coalesce(j.cancel_reason_code, '')), '') as cancel_reason_code,
  nullif(trim(coalesce(j.cancel_reason_note, '')), '') as cancel_reason_note,
  j.actual_start_at,
  j.actual_end_at,
  coalesce(j.created_at, now()),
  coalesce(j.updated_at, now())
from public.jobs j
where j.job_date is not null
on conflict (work_order, scheduled_date, scheduled_slot) do nothing;

insert into public.dispatch_v2_job_assignments(job_id, user_id, assignment_role, is_primary)
select distinct
  v2.id,
  tnm.user_id,
  'lead',
  true
from public.jobs j
join public.dispatch_v2_jobs v2
  on v2.work_order = coalesce(nullif(trim(j.wo),''), nullif(trim(j.order_number),''), 'NO-WO-' || left(j.id::text, 8))
 and v2.scheduled_date = j.job_date
 and v2.scheduled_slot = case when upper(coalesce(j.plage, j.slot, 'AM')) = 'PM' then 'PM' else 'AM' end
join public.tech_name_map tnm
  on lower(trim(tnm.tech_name)) = lower(trim(coalesce(j.tech_name,'')))
 and coalesce(tnm.is_active, true)
 and tnm.user_id is not null
on conflict (job_id, user_id) do update
set assignment_role = excluded.assignment_role,
    is_primary = excluded.is_primary;

insert into public.dispatch_v2_job_assignments(job_id, user_id, assignment_role, is_primary)
select distinct
  v2.id,
  tnm.user_id,
  case lower(coalesce(ja.role,'')) when 'lead' then 'lead' when 'support' then 'support' else 'tech' end,
  coalesce(ja.is_primary, false)
from public.job_assignments ja
join public.jobs j on j.id = ja.job_id
join public.dispatch_v2_jobs v2
  on v2.work_order = coalesce(nullif(trim(j.wo),''), nullif(trim(j.order_number),''), 'NO-WO-' || left(j.id::text, 8))
 and v2.scheduled_date = j.job_date
 and v2.scheduled_slot = case when upper(coalesce(j.plage, j.slot, 'AM')) = 'PM' then 'PM' else 'AM' end
join public.tech_name_map tnm
  on lower(trim(tnm.tech_name)) = lower(trim(coalesce(ja.tech_name,'')))
 and coalesce(tnm.is_active, true)
 and tnm.user_id is not null
on conflict (job_id, user_id) do nothing;

commit;
