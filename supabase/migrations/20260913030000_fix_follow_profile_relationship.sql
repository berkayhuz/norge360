-- Keep follower and following lists explicitly separated at the database boundary.
-- This reasserts the function after earlier migrations that used the same RPC name.
drop function if exists public.list_community_follow_profiles(uuid, text);

create function public.list_community_follow_profiles(
    target_user_id uuid,
    relationship text
)
returns setof public.community_public_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_id uuid := (select auth.uid());
begin
    if actor_id is null then
        raise exception 'authentication required';
    end if;
    if relationship not in ('followers', 'following') then
        raise exception 'invalid follow relationship';
    end if;
    if not public.can_view_community_follow_list(target_user_id, relationship) then
        raise exception 'follow list unavailable';
    end if;

    if relationship = 'followers' then
        return query
        select profile.*
        from public.community_follows as follow
        join public.community_public_profiles as profile
            on profile.user_id = follow.follower_id
        where follow.following_id = target_user_id
        order by follow.created_at desc
        limit 100;
    end if;

    return query
    select profile.*
    from public.community_follows as follow
    join public.community_public_profiles as profile
        on profile.user_id = follow.following_id
    where follow.follower_id = target_user_id
    order by follow.created_at desc
    limit 100;
end;
$$;

revoke all on function public.list_community_follow_profiles(uuid, text) from public;
grant execute on function public.list_community_follow_profiles(uuid, text) to authenticated;
