# Supabase Table Grant Matrix

## Scope

This document records the effective PostgreSQL CRUD privileges for the
`anon`, `authenticated`, and `service_role` roles over relations in the
`public` schema.

The baseline below was observed against the local database after applying all
95 migrations through `20260912140000_secure_profile_projection_grants.sql`
with:

```text
supabase db reset --local --no-seed
```

The matrix is an access-control inventory, not a replacement for RLS policy
review. A table grant is only the coarse database boundary; RLS policies still
decide which rows a non-privileged role may access. `service_role` has the
Supabase privileged-role semantics and bypasses RLS; it must never be shipped
in the iOS client.

## Notation

- `S` — `SELECT`
- `I` — `INSERT`
- `U` — `UPDATE`
- `D` — `DELETE`
- `SIUD` — all four CRUD privileges
- `—` — no effective CRUD privilege
- `*` — column-scoped privilege, not permission to read or write every column
- `RLS yes` — row-level security is enabled
- `RLS n/a` — relation is a view; inspect its definition and underlying-table boundary

The matrix intentionally reports effective CRUD privileges. PostgreSQL may also
report non-CRUD privileges such as `REFERENCES`, `TRIGGER`, or `TRUNCATE`; those
are not included in this product-facing matrix.

## Effective CRUD matrix

| Relation | Type | RLS | anon | authenticated | service_role |
|---|---|---|---:|---:|---:|
| `public.community_comment_hashtags` | table | yes | SIUD | SIUD | SIUD |
| `public.community_comments` | table | yes | SIUD | SIUD | SIUD |
| `public.community_conversation_members` | table | yes | — | S | SIUD |
| `public.community_conversation_preferences` | table | yes | — | S | SIUD |
| `public.community_conversations` | table | yes | — | S | SIUD |
| `public.community_direct_message_attachments` | table | yes | — | — | SIUD |
| `public.community_event_invitations` | table | yes | — | — | SIUD |
| `public.community_event_likes` | table | yes | S | S | SIUD |
| `public.community_event_rsvps` | table | yes | SIUD | SIUD | SIUD |
| `public.community_events` | table | yes | SIUD | SIUD | SIUD |
| `public.community_follow_visibility` | table | yes | — | — | SIUD |
| `public.community_follows` | table | yes | SIUD | SIUD | SIUD |
| `public.community_group_bans` | table | yes | SIUD | SIUD | SIUD |
| `public.community_group_chat_attachments` | table | yes | — | — | SIUD |
| `public.community_group_chat_member_reads` | table | yes | — | — | SIUD |
| `public.community_group_chat_message_member_hides` | table | yes | — | — | SIUD |
| `public.community_group_chat_messages` | table | yes | — | S | SIUD |
| `public.community_group_chat_preferences` | table | yes | — | — | SIUD |
| `public.community_group_chat_push_fanout_jobs` | table | yes | — | — | SIUD |
| `public.community_group_chat_signals` | table | yes | — | S | SIUD |
| `public.community_group_invitations` | table | yes | — | S | SIUD |
| `public.community_group_join_requests` | table | yes | SIUD | SIUD | SIUD |
| `public.community_group_memberships` | table | yes | SIUD | SIUD | SIUD |
| `public.community_group_moderation_audit` | table | yes | SIUD | SIUD | SIUD |
| `public.community_group_removed_post_media` | table | yes | SIUD | SIUD | SIUD |
| `public.community_groups` | table | yes | SIUD | SIUD | SIUD |
| `public.community_liked_posts_visibility` | table | yes | — | — | SIUD |
| `public.community_media_view_rate_limits` | table | yes | — | — | SIUD |
| `public.community_member_profile_stats` | view | n/a | — | S | SIUD |
| `public.community_member_restrictions` | table | yes | SIUD | SIUD | SIUD |
| `public.community_message_member_hides` | table | yes | — | S | SIUD |
| `public.community_message_preferences` | table | yes | — | S | SIUD |
| `public.community_message_signals` | table | yes | — | S | SIUD |
| `public.community_messages` | table | yes | — | S | SIUD |
| `public.community_moderation_action_audit` | table | yes | SIUD | SIUD | SIUD |
| `public.community_moderation_review_audit` | table | yes | SIUD | SIUD | SIUD |
| `public.community_moderator_roles` | table | yes | SIUD | SIUD | SIUD |
| `public.community_notifications` | table | yes | SIUD | SIUD | SIUD |
| `public.community_post_edit_history` | table | yes | SIUD | SIUD | SIUD |
| `public.community_post_hashtags` | table | yes | SIUD | SIUD | SIUD |
| `public.community_request_rate_limits` | table | yes | — | — | SIUD |
| `public.community_storage_cleanup_outbox` | table | yes | — | — | SIUD |
| `public.community_post_likes` | table | yes | S | S | SIUD |
| `public.community_post_media` | table | yes | SIUD | SIUD | SIUD |
| `public.community_posts` | table | yes | SIUD | SIUD | SIUD |
| `public.community_profile_media_cleanup_outbox` | table | yes | — | — | SIUD |
| `public.community_profiles` | table | yes | — | S* I* U* D | SIUD |
| `public.community_public_profiles` | view | n/a | — | S | SIUD |
| `public.community_push_delivery_ledger` | table | yes | — | — | SIUD |
| `public.community_push_devices` | table | yes | — | — | SIUD |
| `public.community_push_preferences` | table | yes | — | S | SIUD |
| `public.community_reports` | table | yes | SIUD | SIUD | SIUD |
| `public.user_account_profiles` | table | yes | SIUD | SIUD | SIUD |
| `public.user_blocks` | table | yes | SIUD | SIUD | SIUD |
| `public.user_relocation_plans` | table | yes | SIUD | SIUD | SIUD |

## Column-scoped exception

`public.community_profiles` is intentionally not represented by a simple
table-level `authenticated` grant:

- `SELECT` is limited to the public/profile-safe columns.
- `INSERT` is limited to onboarding fields.
- `UPDATE` is limited to editable profile fields.
- `DELETE` is table-level for the authenticated owner path and remains subject
  to RLS.
- Private relocation context is handled through the owner-only RPC rather than
  a broad direct table read.

The authoritative column list is in
`supabase/migrations/20260912130000_restore_community_profile_write_grants.sql`.

## Migration evidence

The grant boundary is currently distributed across migrations rather than
defined in one schema policy file. Representative examples are:

- Direct-message base tables: `20260909120000_add_safe_direct_message_foundation.sql`
- Private message preferences and member hides: `20260909123000_add_direct_message_privacy_and_member_hide.sql`
- APNs device and preference tables: `20260909125000_add_private_apns_device_registration.sql`
- Group-chat private tables: `20260909130000_add_safe_group_chat_foundation.sql` and later group-chat migrations
- Push/cleanup transport retention: `20260913150000_add_transport_retention_purge.sql`
- Public profile view and base-table boundary: `20260911210000_secure_public_profile_projection.sql`
- Explicit profile column grants: `20260912130000_restore_community_profile_write_grants.sql`
- Read-only projection grants: `20260912140000_secure_profile_projection_grants.sql`
- Group-scoped content/storage visibility and invoker projections: `20260913180000_harden_group_scoped_content_visibility.sql`
- Push delivery worker ledger: `20260912120000_async_push_delivery.sql`

When adding a new table, the migration must explicitly document its intended
role boundary, enable RLS where appropriate, and add the table to this matrix.

## Reproducible verification query

Run this read-only query against the target database after migrations are
applied. It reports effective CRUD privileges, so it also catches privileges
inherited through existing role grants.

```sql
with relations as (
  select
    c.oid,
    n.nspname as schema_name,
    c.relname as relation_name,
    case c.relkind
      when 'r' then 'table'
      when 'p' then 'partitioned table'
      when 'v' then 'view'
      when 'm' then 'materialized view'
      else c.relkind::text
    end as relation_type,
    c.relrowsecurity as rls_enabled
  from pg_class as c
  join pg_namespace as n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r', 'p', 'v', 'm')
)
select
  schema_name || '.' || relation_name as relation,
  relation_type,
  rls_enabled,
  has_table_privilege('anon', oid, 'SELECT') as anon_select,
  has_table_privilege('anon', oid, 'INSERT') as anon_insert,
  has_table_privilege('anon', oid, 'UPDATE') as anon_update,
  has_table_privilege('anon', oid, 'DELETE') as anon_delete,
  has_table_privilege('authenticated', oid, 'SELECT') as authenticated_select,
  has_table_privilege('authenticated', oid, 'INSERT') as authenticated_insert,
  has_table_privilege('authenticated', oid, 'UPDATE') as authenticated_update,
  has_table_privilege('authenticated', oid, 'DELETE') as authenticated_delete,
  has_table_privilege('service_role', oid, 'SELECT') as service_select,
  has_table_privilege('service_role', oid, 'INSERT') as service_insert,
  has_table_privilege('service_role', oid, 'UPDATE') as service_update,
  has_table_privilege('service_role', oid, 'DELETE') as service_delete
from relations
order by relation;
```

For a release check, compare the result against this document and investigate
any unexpected grant, revoke, newly exposed relation, or RLS-disabled table.

## Known follow-up boundaries

This document does not claim that every existing base-table grant is the
least-privilege design. Broad legacy CRUD grants on some RLS-protected base
tables still require a separate RLS and authorization review. The public
profile and aggregate stats views are explicitly read-only for the client
roles by `20260912140000_secure_profile_projection_grants.sql`.
