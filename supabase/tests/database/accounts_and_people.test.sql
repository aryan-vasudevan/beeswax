-- Tests for BWX-9: sign-up trigger, people, relationships, settings and the
-- row-level security around them. Run with `supabase test db`.
--
-- The seed users in supabase/seed.sql exist too, so counts are scoped to
-- this file's users.
--
-- Each block switches to the `authenticated` role with a JWT `sub`, which is
-- exactly how PostgREST runs a signed-in user's request.

begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

-- Users ---------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com',
    '{"username": "Alice", "display_name": "Alice A"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com',
    '{"username": "bob"}'),
  -- Apple/Google style: a name, no username.
  ('33333333-3333-3333-3333-333333333333', 'carol@example.com',
    '{"full_name": "Carol Provider"}');

-- Sign-up trigger -----------------------------------------------------------

select is(
  (select username::text from public.account where id = '11111111-1111-1111-1111-111111111111'),
  'alice',
  'sign-up creates an account with the username, lowercased'
);

select is(
  (select display_name from public.person
    where account_id = '11111111-1111-1111-1111-111111111111' and created_by = account_id),
  'Alice A',
  'sign-up creates a self person with the display name'
);

select is(
  (select display_name from public.person
    where account_id = '22222222-2222-2222-2222-222222222222' and created_by = account_id),
  'bob',
  'display name falls back to the username'
);

select ok(
  (select username is null from public.account where id = '33333333-3333-3333-3333-333333333333'),
  'provider sign-up without a username leaves it null'
);

select is(
  (select display_name from public.person
    where account_id = '33333333-3333-3333-3333-333333333333' and created_by = account_id),
  'Carol Provider',
  'display name comes from the provider full_name'
);

select is(
  (select count(*)::int from public.account_settings
    where account_id in ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333')),
  3,
  'sign-up creates settings for each account'
);

select throws_ok(
  $$insert into auth.users (id, email, raw_user_meta_data) values
    ('44444444-4444-4444-4444-444444444444', 'dup@example.com', '{"username": "ALICE"}')$$,
  '23505',
  null,
  'a username taken in another case fails the sign-up'
);

-- As Alice ------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select is(
  (select count(*)::int from public.person
    where account_id = created_by and account_id in ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333')),
  3,
  'Alice sees every self person'
);

select lives_ok(
  $$insert into public.person (display_name, email)
    values ('Grandpa', 'grandpa@example.com')$$,
  'Alice can create an identity'
);

select throws_ok(
  $$insert into public.person (display_name, account_id)
    values ('Fake Bob', '22222222-2222-2222-2222-222222222222')$$,
  '42501',
  null,
  'Alice cannot create a person already linked to an account'
);

select throws_ok(
  $$update public.person set email = 'alice@example.com'
    where account_id = '11111111-1111-1111-1111-111111111111'$$,
  '23514',
  null,
  'a self person cannot carry contact details'
);

update public.account set username = 'hacked'
  where id = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$update public.account set username = 'alice_a'
    where id = '11111111-1111-1111-1111-111111111111'$$,
  'Alice can change her own username'
);

select throws_ok(
  $$update public.account set username = 'no spaces'
    where id = '11111111-1111-1111-1111-111111111111'$$,
  '23514',
  null,
  'usernames must match the allowed format'
);

delete from public.person where account_id = '11111111-1111-1111-1111-111111111111';
select is(
  (select count(*)::int from public.person
    where account_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Alice cannot delete her own self person'
);

select lives_ok(
  $$insert into public.relationship (person_id, label)
    select id, 'friend' from public.person
    where account_id = '22222222-2222-2222-2222-222222222222'$$,
  'Alice can add Bob to her people'
);

select lives_ok(
  $$insert into public.relationship (person_id, label)
    select id, 'family' from public.person where display_name = 'Grandpa'$$,
  'Alice can add her identity to her people'
);

select throws_ok(
  $$insert into public.relationship (person_id)
    select id from public.person
    where account_id = '11111111-1111-1111-1111-111111111111'$$,
  '42501',
  null,
  'Alice cannot add herself to her people'
);

select lives_ok(
  $$update public.account_settings set push_notifications = false, timezone = 'America/Toronto'$$,
  'Alice can update her settings'
);

-- As Bob --------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select is(
  (select count(*)::int from public.person where display_name = 'Grandpa'),
  0,
  'Bob cannot see Alice''s identity'
);

select is(
  (select count(*)::int from public.relationship),
  0,
  'Bob cannot see Alice''s relationships'
);

select is(
  (select count(*)::int from public.account_settings),
  1,
  'Bob sees only his own settings'
);

select is(
  (select username::text from public.account where id = '22222222-2222-2222-2222-222222222222'),
  'bob',
  'Alice''s earlier update to Bob''s username changed nothing'
);

-- Anonymous -----------------------------------------------------------------

reset role;
set local role anon;
select is(
  (select count(*)::int from public.person),
  0,
  'anonymous requests see no people'
);

-- Account deletion ----------------------------------------------------------

reset role;
delete from auth.users where id = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from public.account where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'deleting a user deletes their account'
);

select ok(
  exists (
    select 1 from public.person
    where display_name = 'Alice A' and account_id is null and created_by is null
  ),
  'a deleted user stays behind as a name-only person'
);

select ok(
  exists (
    select 1 from public.person
    where display_name = 'Grandpa' and created_by is null and email is null
  ),
  'their identities stay too, with contact details removed'
);

select is(
  (select count(*)::int from public.relationship
    where account_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'a deleted user''s relationships are removed'
);

select * from finish();
rollback;
