-- Username availability for the sign-up form (BWX-10).
--
-- Callable before you have an account, so it runs for `anon` too. It only
-- answers yes or no for one exact name, which uniqueness forces us to reveal
-- anyway; it never lists or suggests names. Rate limiting is BWX-86.
--
-- Mirrors account.username_format, so the form and the database agree on
-- what a valid username is. Taken in any letter case counts as taken.
create function public.username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select lower(trim(p_username)) ~ '^[a-z0-9_.]{3,30}$'
    and not exists (
      select 1 from public.account
      where username = lower(trim(p_username))::extensions.citext
    );
$$;

comment on function public.username_available(text) is
  'True if the username is valid and nobody has it. Used by the sign-up form.';

revoke execute on function public.username_available(text) from public;
grant execute on function public.username_available(text) to anon, authenticated;
