-- Read-only diagnostic: shows every check constraint currently attached to
-- the group-chat attachment table. It changes no data or schema.
select
  constraints.constraint_name,
  checks.check_clause
from information_schema.check_constraints checks
join information_schema.table_constraints constraints
  on constraints.constraint_catalog = checks.constraint_catalog
  and constraints.constraint_schema = checks.constraint_schema
  and constraints.constraint_name = checks.constraint_name
where constraints.table_schema = 'public'
  and constraints.table_name = 'community_group_chat_attachments'
order by constraint_name;
