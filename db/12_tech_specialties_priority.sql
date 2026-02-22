-- Dispatch Calendar - tech specialties + priority on profiles
-- Run after db/10_user_sync_and_admin_rpc.sql

begin;

alter table if exists public.tech_profiles
  add column if not exists priority_rank int,
  add column if not exists specialties text[];

update public.tech_profiles
set priority_rank = coalesce(priority_rank, 100)
where priority_rank is null;

update public.tech_profiles
set specialties = array['ALL']::text[]
where specialties is null or cardinality(specialties)=0;

alter table public.tech_profiles
  alter column priority_rank set default 100,
  alter column specialties set default array['ALL']::text[];

drop function if exists public.admin_list_user_tech_mappings();

create or replace function public.admin_list_user_tech_mappings()
returns table (
  user_id uuid,
  email text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  is_disabled boolean,
  tech_name text,
  mapping_active boolean,
  is_admin boolean,
  priority_rank int,
  specialties text[]
)
language sql
security definer
set search_path = public
as $$
  select
    au.user_id,
    au.email,
    au.created_at,
    au.last_sign_in_at,
    au.is_disabled,
    coalesce(tnm.tech_name, tp.display_name) as tech_name,
    coalesce(tnm.is_active, tp.is_active, false) as mapping_active,
    exists (select 1 from public.admin_users ad where ad.user_id = au.user_id) as is_admin,
    coalesce(tp.priority_rank, 100) as priority_rank,
    coalesce(tp.specialties, array['ALL']::text[]) as specialties
  from public.app_users au
  left join public.tech_name_map tnm on tnm.user_id = au.user_id
  left join public.tech_profiles tp on tp.user_id = au.user_id
  where public.is_admin_user()
  order by coalesce(tp.priority_rank, 100), coalesce(au.email, ''), au.user_id;
$$;

create or replace function public.admin_set_tech_profile_options(
  p_user_id uuid,
  p_priority_rank int default 100,
  p_specialties text[] default array['ALL']::text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rank int;
  v_specs text[];
begin
  if not public.is_admin_user() then
    raise exception 'admin only';
  end if;

  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  v_rank := coalesce(p_priority_rank, 100);
  if v_rank < 1 then v_rank := 1; end if;
  if v_rank > 999 then v_rank := 999; end if;

  select coalesce(array_agg(distinct upper(btrim(x))), array['ALL']::text[])
  into v_specs
  from unnest(coalesce(p_specialties, array['ALL']::text[])) as x
  where btrim(coalesce(x,'')) <> '';

  if v_specs is null or cardinality(v_specs)=0 then
    v_specs := array['ALL']::text[];
  end if;

  update public.tech_profiles
  set priority_rank = v_rank,
      specialties = v_specs
  where user_id = p_user_id;
end;
$$;

grant execute on function public.admin_list_user_tech_mappings() to authenticated;
grant execute on function public.admin_set_tech_profile_options(uuid, int, text[]) to authenticated;

commit;
