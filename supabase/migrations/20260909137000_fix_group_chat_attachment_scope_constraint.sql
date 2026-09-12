-- Store an opaque provider reference under the owning group. The original
-- LIKE expression was valid in intent but can be evaluated unexpectedly once
-- the path is assembled by a server-side uploader. Split the first segment
-- explicitly so the database remains authoritative about group scope.

do $$
declare
  existing_constraint text;
begin
  select checks.constraint_name into existing_constraint
  from information_schema.check_constraints checks
  join information_schema.table_constraints constraints
    on constraints.constraint_catalog = checks.constraint_catalog
    and constraints.constraint_schema = checks.constraint_schema
    and constraints.constraint_name = checks.constraint_name
  where constraints.table_schema = 'public'
    and constraints.table_name = 'community_group_chat_attachments'
    and checks.check_clause like '%storage_path%group_id%'
  limit 1;

  if existing_constraint is not null then
    execute format('alter table public.community_group_chat_attachments drop constraint %I', existing_constraint);
  end if;
end;
$$;

alter table public.community_group_chat_attachments
  add constraint community_group_chat_attachments_storage_path_group_scope_check
  check (split_part(storage_path, '/', 1) = group_id::text);
