-- New posts require a title while the description remains optional.
-- Existing title-less posts receive a neutral legacy title before the column
-- becomes mandatory; their existing content is otherwise preserved.
update public.community_posts
set title = 'Community post'
where title is null or char_length(trim(title)) = 0;

alter table public.community_posts
  drop constraint if exists community_posts_title_check;

alter table public.community_posts
  alter column title set not null;

alter table public.community_posts
  add constraint community_posts_title_check
  check (char_length(trim(title)) between 1 and 220);

alter table public.community_posts
  drop constraint if exists community_posts_body_check;

alter table public.community_posts
  add constraint community_posts_body_check
  check (char_length(trim(body)) between 0 and 4000);
