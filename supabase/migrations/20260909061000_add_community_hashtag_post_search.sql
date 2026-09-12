create or replace function public.search_community_hashtag_posts(tag_prefix text)
returns table (post_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select post.id
  from public.community_post_hashtags as post_tag
  join public.community_posts as post on post.id = post_tag.post_id
  join public.community_profiles as author on author.user_id = post.author_id
  where post_tag.tag = lower(trim(tag_prefix))
    and author.is_public
    and public.can_view_community_user(post.author_id)
  order by post.created_at desc
  limit 50;
$$;

revoke all on function public.search_community_hashtag_posts(text) from public;
grant execute on function public.search_community_hashtag_posts(text) to authenticated;
