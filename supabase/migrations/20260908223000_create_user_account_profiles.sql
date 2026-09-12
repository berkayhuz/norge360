-- Account setup data deliberately excludes the phone number. Supabase Auth owns
-- the verified phone credential; this table keeps only product preferences.
create table if not exists public.user_account_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) between 1 and 120),
  preferred_locale text not null check (preferred_locale in (
    'en', 'nb', 'tr', 'ar', 'fa', 'fr', 'es', 'de', 'uk', 'ru', 'pl', 'so', 'ti', 'am', 'ur', 'fa-AF'
  )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_account_profiles enable row level security;

drop policy if exists "Users can read their own account profile" on public.user_account_profiles;
create policy "Users can read their own account profile"
on public.user_account_profiles for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their own account profile" on public.user_account_profiles;
create policy "Users can create their own account profile"
on public.user_account_profiles for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own account profile" on public.user_account_profiles;
create policy "Users can update their own account profile"
on public.user_account_profiles for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create or replace function public.set_user_account_profiles_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_user_account_profiles_updated_at on public.user_account_profiles;
create trigger set_user_account_profiles_updated_at
before update on public.user_account_profiles
for each row execute procedure public.set_user_account_profiles_updated_at();
