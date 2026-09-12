-- Stores only a user's private relocation profile and task-progress snapshot.
-- Canonical task content/rules remain in the iOS app for this MVP.
create table if not exists public.user_relocation_plans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_relocation_plans enable row level security;

drop policy if exists "Users can read their own relocation plan" on public.user_relocation_plans;
create policy "Users can read their own relocation plan"
on public.user_relocation_plans for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their own relocation plan" on public.user_relocation_plans;
create policy "Users can create their own relocation plan"
on public.user_relocation_plans for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own relocation plan" on public.user_relocation_plans;
create policy "Users can update their own relocation plan"
on public.user_relocation_plans for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own relocation plan" on public.user_relocation_plans;
create policy "Users can delete their own relocation plan"
on public.user_relocation_plans for delete
to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.set_user_relocation_plans_updated_at()
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

drop trigger if exists set_user_relocation_plans_updated_at on public.user_relocation_plans;
create trigger set_user_relocation_plans_updated_at
before update on public.user_relocation_plans
for each row execute procedure public.set_user_relocation_plans_updated_at();
