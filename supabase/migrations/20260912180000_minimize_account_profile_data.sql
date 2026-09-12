-- The MVP needs only the authenticated member's locale in this private
-- account table. The editable public display name remains in
-- public.community_profiles. Remove unused identity/demographic fields so
-- they are no longer retained after this migration.
alter table public.user_account_profiles
  drop column if exists full_name,
  drop column if exists gender,
  drop column if exists birth_date;
