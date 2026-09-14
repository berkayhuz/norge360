-- Keep relocation-plan writes monotonic so a stale request cannot overwrite
-- a newer snapshot after an offline reconnect or a delayed network response.
alter table public.user_relocation_plans
  add column if not exists revision bigint not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_relocation_plans_revision_nonnegative'
      and conrelid = 'public.user_relocation_plans'::regclass
  ) then
    alter table public.user_relocation_plans
      add constraint user_relocation_plans_revision_nonnegative check (revision >= 0);
  end if;
end;
$$;

create or replace function public.save_user_relocation_plan(
  target_plan jsonb,
  target_revision bigint
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_revision bigint;
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authenticated user required';
  end if;

  if target_plan is null or target_revision is null or target_revision < 0 then
    raise exception 'invalid relocation plan snapshot';
  end if;

  insert into public.user_relocation_plans (user_id, plan, revision)
  values (current_user_id, target_plan, target_revision)
  on conflict (user_id) do nothing;

  select revision
    into current_revision
    from public.user_relocation_plans
    where user_id = current_user_id
    for update;

  if target_revision > current_revision then
    update public.user_relocation_plans
       set plan = target_plan,
           revision = target_revision
     where user_id = current_user_id;
    return target_revision;
  end if;

  return current_revision;
end;
$$;

revoke all on function public.save_user_relocation_plan(jsonb, bigint) from public, anon;
grant execute on function public.save_user_relocation_plan(jsonb, bigint) to authenticated;
