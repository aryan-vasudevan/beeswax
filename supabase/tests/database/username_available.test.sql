-- Tests for BWX-10: username availability. Run with `supabase test db`.

begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data) values
  ('0b000000-0000-0000-0000-000000000001', 'taken@example.com', '{"username": "taken_name"}');

set local role anon;

select ok(public.username_available('fresh_name'), 'an unused valid username is available');
select ok(not public.username_available('taken_name'), 'a taken username is not');
select ok(not public.username_available('TAKEN_NAME'), 'taken in another case is still taken');
select ok(not public.username_available('ab'), 'too short is not available');
select ok(not public.username_available('has space'), 'invalid characters are not available');
select ok(public.username_available('  Fresh.Name_2  '), 'input is trimmed and lowercased first');

select * from finish();
rollback;
