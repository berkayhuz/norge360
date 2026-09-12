-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
declare
  view_definition text;
begin
  select lower(pg_get_viewdef('public.community_member_profile_stats'::regclass, true))
    into view_definition;

  if view_definition is null then
    raise exception 'community_member_profile_stats view definition is missing';
  end if;

  if position('post_counts' in view_definition) = 0
    or position('like_counts' in view_definition) = 0
    or position('comment_counts' in view_definition) = 0 then
    raise exception 'profile stats must aggregate posts, likes, and comments independently';
  end if;

  if position('left join public.community_post_likes' in view_definition) > 0
    or position('left join public.community_comments' in view_definition) > 0 then
    raise exception 'profile stats must not join likes and comments to the same post rows';
  end if;
end $$;

rollback;
