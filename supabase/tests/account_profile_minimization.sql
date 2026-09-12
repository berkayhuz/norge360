-- Run against a disposable fully migrated database as its owner.
-- Everything rolls back. The private account contract must not retain
-- identity or demographic fields that have no current product consumer.
begin;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_account_profiles'
      and column_name in ('full_name', 'gender', 'birth_date')
  ) then
    raise exception 'unused identity/demographic account fields still exist';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_account_profiles'
      and column_name = 'preferred_locale'
  ) then
    raise exception 'preferred locale account field is missing';
  end if;
end $$;

insert into auth.users(id)
values ('96000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '96000000-0000-4000-8000-000000000001',
  true
);

insert into public.user_account_profiles(user_id, preferred_locale)
values ('96000000-0000-4000-8000-000000000001', 'en');

do $$
begin
  if not exists (
    select 1
    from public.user_account_profiles
    where user_id = '96000000-0000-4000-8000-000000000001'
      and preferred_locale = 'en'
  ) then
    raise exception 'minimal account profile could not be persisted';
  end if;
end $$;

reset role;
rollback;
