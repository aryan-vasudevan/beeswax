-- Tests for BWX-9: sign-up, people, private notes, relationships, friends,
-- blocks, finding people, and account deletion. Run with `supabase test db`.
--
-- The seed users in supabase/seed.sql exist too, so this file uses its own
-- users and scopes its counts to them.
--
-- Each block switches to the `authenticated` role with a JWT `sub`, which is
-- exactly how PostgREST runs a signed-in user's request.

begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com',
    '{"username": "Test_Alice", "display_name": "Alice A"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com',
    '{"username": "test_bob"}'),
  ('33333333-3333-3333-3333-333333333333', 'carol@example.com',
    '{"username": "test_carol", "display_name": "Carol C"}'),
  -- Apple/Google style: a name, no username.
  ('44444444-4444-4444-4444-444444444444', 'dave@example.com',
    '{"full_name": "Dave Provider"}');

-- Sign-up -------------------------------------------------------------------

select is(
  (select username::text from public.account where id = '11111111-1111-1111-1111-111111111111'),
  'test_alice',
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
  'test_bob',
  'display name falls back to the username'
);

select ok(
  (select username is null from public.account where id = '44444444-4444-4444-4444-444444444444'),
  'provider sign-up without a username leaves it null'
);

select is(
  (select display_name from public.person
    where account_id = '44444444-4444-4444-4444-444444444444' and created_by = account_id),
  'Dave Provider',
  'display name comes from the provider full_name'
);

select is(
  (select count(*)::int from public.account_settings
    where account_id in (
      '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
      '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444')),
  4,
  'sign-up creates settings for each account'
);

select throws_ok(
  $$insert into auth.users (id, email, raw_user_meta_data) values
    ('55555555-5555-5555-5555-555555555555', 'dup@example.com', '{"username": "TEST_ALICE"}')$$,
  '23505',
  null,
  'a username taken in another case fails the sign-up'
);

-- As Alice: people are not browsable ----------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select is(
  (select count(*)::int from public.person
    where account_id in ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333')),
  0,
  'Alice cannot see people she has no connection to'
);

select is(
  (select count(*)::int from public.find_account('test_bob')),
  1,
  'Alice can find Bob by exact username'
);

select is(
  (select count(*)::int from public.find_account('test_b')),
  0,
  'partial usernames find nobody'
);

-- Identities and private notes ----------------------------------------------

select lives_ok(
  $$insert into public.person (display_name, nickname) values ('Grandpa Yusuf', 'Jiddo')$$,
  'Alice can create an identity'
);

select throws_ok(
  $$insert into public.person (display_name, account_id)
    values ('Fake Bob', '22222222-2222-2222-2222-222222222222')$$,
  '42501',
  null,
  'Alice cannot create a person already linked to an account'
);

select lives_ok(
  $$insert into public.person_private (person_id, notes, email)
    select id, 'Loves backgammon', 'yusuf@example.com'
    from public.person where display_name = 'Grandpa Yusuf'$$,
  'Alice can keep private notes and contact details for her identity'
);

select throws_ok(
  $$update public.person set bio = 'Not his own words' where display_name = 'Grandpa Yusuf'$$,
  '23514',
  null,
  'only a self person can have a bio'
);

-- People list ---------------------------------------------------------------

select lives_ok(
  $$insert into public.relationship (person_id, label)
    select person_id, 'friend' from public.find_account('test_bob')$$,
  'Alice can add Bob, found by username, to her people'
);

select is(
  (select count(*)::int from public.person
    where account_id = '22222222-2222-2222-2222-222222222222'),
  1,
  'once on her list, Alice can see Bob'
);

select throws_ok(
  $$insert into public.relationship (person_id)
    select id from public.person
    where account_id = '11111111-1111-1111-1111-111111111111'$$,
  '42501',
  null,
  'Alice cannot add herself to her people'
);

-- Friend request ------------------------------------------------------------

select lives_ok(
  $$insert into public.friendship (addressee_id)
    values ('33333333-3333-3333-3333-333333333333')$$,
  'Alice can send Carol a friend request'
);

update public.friendship set status = 'accepted'
  where addressee_id = '33333333-3333-3333-3333-333333333333';
select is(
  (select status::text from public.friendship
    where addressee_id = '33333333-3333-3333-3333-333333333333'),
  'pending',
  'Alice cannot accept her own request'
);

-- Account and settings ------------------------------------------------------

select lives_ok(
  $$update public.account set username = 'test_alice_a'
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
  $$update public.account_settings
    set push_notifications = false, timezone = 'America/Toronto',
        quiet_hours_start = '22:00', quiet_hours_end = '08:00'$$,
  'Alice can update her settings'
);

-- As Bob --------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select is(
  (select count(*)::int from public.person where display_name = 'Grandpa Yusuf'),
  0,
  'Bob cannot see Alice''s identity'
);

select is(
  (select count(*)::int from public.person_private),
  0,
  'Bob cannot see anyone''s private notes'
);

select is(
  (select count(*)::int from public.relationship),
  0,
  'Bob cannot see Alice''s people list'
);

select lives_ok(
  $$update public.account_settings set discoverable = false$$,
  'Bob can make himself undiscoverable'
);

-- As Carol ------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';

select is(
  (select count(*)::int from public.find_account('test_bob')),
  0,
  'an undiscoverable user cannot be found'
);

select is(
  (select count(*)::int from public.person
    where account_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Carol can see who sent her a friend request'
);

select lives_ok(
  $$update public.friendship set status = 'accepted'
    where requester_id = '11111111-1111-1111-1111-111111111111'$$,
  'Carol can accept the request'
);

select ok(
  (select responded_at is not null from public.friendship
    where requester_id = '11111111-1111-1111-1111-111111111111'),
  'accepting records when it was answered'
);

select lives_ok(
  $$insert into public.block (blocked_id) values ('11111111-1111-1111-1111-111111111111')$$,
  'Carol can block Alice'
);

select is(
  (select count(*)::int from public.friendship),
  0,
  'blocking ends the friendship'
);

-- As Alice, blocked ---------------------------------------------------------

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select is(
  (select count(*)::int from public.find_account('test_carol')),
  0,
  'a blocked user cannot find the person who blocked them'
);

select throws_ok(
  $$insert into public.friendship (addressee_id)
    values ('33333333-3333-3333-3333-333333333333')$$,
  '42501',
  null,
  'a blocked user cannot send another request'
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
    where display_name = 'Grandpa Yusuf' and created_by is null
  ),
  'identities they created stay too'
);

select is(
  (select count(*)::int from public.person_private p
    join public.person pe on pe.id = p.person_id
    where pe.display_name = 'Grandpa Yusuf'),
  0,
  'their private notes are deleted'
);

select is(
  (select count(*)::int from public.relationship
    where account_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'their people list is deleted'
);

select * from finish();
rollback;
