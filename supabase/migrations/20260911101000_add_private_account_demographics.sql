-- These fields are private account data. Existing owner-only RLS remains in
-- force and no community/public profile view selects these columns.
alter table public.user_account_profiles
  add column if not exists gender text not null default 'prefer_not_to_say'
    check (gender in ('woman', 'man', 'non_binary', 'prefer_not_to_say')),
  add column if not exists birth_date date;

-- Existing accounts must provide a date through the next account-details flow;
-- keep the migration non-destructive while the product has no backfill source.
