-- Return visible comments with only the public projection of each comment
-- author. This keeps comment reads independent of the total profile count.
create or replace function public.list_community_post_comments(
  target_post_id uuid
)
returns table (
  comment jsonb,
  author jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    jsonb_build_object(
      'id', community_comment.id,
      'post_id', community_comment.post_id,
      'author_id', community_comment.author_id,
      'body', community_comment.body,
      'created_at', community_comment.created_at,
      'updated_at', community_comment.updated_at
    ) as comment,
    jsonb_build_object(
      'user_id', comment_author.user_id,
      'display_name', comment_author.display_name,
      'username', comment_author.username,
      'preferred_locale', comment_author.preferred_locale,
      'public_languages', comment_author.public_languages,
      'interests', comment_author.interests,
      'is_public', comment_author.is_public,
      'avatar_path', comment_author.avatar_path,
      'created_at', comment_author.created_at,
      'updated_at', comment_author.updated_at
    ) as author
  from public.community_comments as community_comment
  join public.community_profiles as comment_author
    on comment_author.user_id = community_comment.author_id
  join public.community_posts as community_post
    on community_post.id = community_comment.post_id
  join public.community_profiles as post_author
    on post_author.user_id = community_post.author_id
  where (select auth.uid()) is not null
    and community_comment.post_id = target_post_id
    and community_comment.moderation_state = 'active'
    and comment_author.is_public
    and comment_author.moderation_state = 'active'
    and public.can_view_community_user(community_comment.author_id)
    and community_post.moderation_state = 'active'
    and post_author.is_public
    and post_author.moderation_state = 'active'
    and public.can_view_community_user(community_post.author_id)
    and (
      community_post.group_id is null
      or exists (
        select 1
        from public.community_groups as community_group
        where community_group.id = community_post.group_id
          and community_group.moderation_state = 'active'
      )
    )
  order by community_comment.created_at, community_comment.id;
$$;

revoke all on function public.list_community_post_comments(uuid) from public;
grant execute on function public.list_community_post_comments(uuid) to authenticated;
