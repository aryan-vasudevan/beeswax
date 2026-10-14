-- Tests for BWX-75: waggle links (knock and addressed), join requests,
-- previews, and declined invitations leaving no trace.
-- Run with `supabase test db`.
--
-- Tokens are only ever returned once, so each test stashes the one it gets
-- in a transaction-local setting (test.<name>) and reads it back.
--
-- Cast: owner, editor and contrib are members of "Lake weekend";
-- knocker and newbie use open links; target has the verified email an
-- addressed link was made for; wrong is someone else; unverified has the
-- right email for a second link but never confirmed it; blocked is blocked
-- by the owner.

begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('0c000000-0000-0000-0000-000000000001', 'owner@example.com', now(), '{"username": "w_owner", "display_name": "Owner O"}'),
  ('0c000000-0000-0000-0000-000000000002', 'editor@example.com', now(), '{"username": "w_editor"}'),
  ('0c000000-0000-0000-0000-000000000003', 'contrib@example.com', now(), '{"username": "w_contrib"}'),
  ('0c000000-0000-0000-0000-000000000004', 'knocker@example.com', now(), '{"username": "w_knocker"}'),
  ('0c000000-0000-0000-0000-000000000005', 'target@example.com', now(), '{"username": "w_target"}'),
  ('0c000000-0000-0000-0000-000000000006', 'wrong@example.com', now(), '{"username": "w_wrong"}'),
  ('0c000000-0000-0000-0000-000000000007', 'unverified@example.com', null, '{"username": "w_unverified"}'),
  ('0c000000-0000-0000-0000-000000000008', 'blocked@example.com', now(), '{"username": "w_blocked"}'),
  ('0c000000-0000-0000-0000-000000000009', 'newbie@example.com', now(), '{"username": "w_newbie"}');

insert into public.snapshot (id, owner_id, creator_id, status, title)
values ('0d000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000001',
  '0c000000-0000-0000-0000-000000000001', 'published', 'Lake weekend');

insert into public.snapshot_member (snapshot_id, account_id, role) values
  ('0d000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000002', 'editor'),
  ('0d000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000003', 'contributor');

-- Owner makes links -----------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select isnt(
  set_config('test.knock', public.create_invite_link(
    '0d000000-0000-0000-0000-000000000001', 'knock'), true),
  null,
  'the owner can make an open (knock) link'
);

select is(length(current_setting('test.knock')), 32, 'tokens are 32 URL-safe characters');

select isnt(
  set_config('test.addressed', public.create_invite_link(
    '0d000000-0000-0000-0000-000000000001', 'addressed', 'contributor', 'Target@Example.com'), true),
  null,
  'the owner can make a link addressed to an email'
);

select isnt(
  set_config('test.unverified', public.create_invite_link(
    '0d000000-0000-0000-0000-000000000001', 'addressed', 'viewer', 'unverified@example.com'), true),
  null,
  'and another for someone who has not verified their email'
);

select throws_ok(
  $$select public.create_invite_link('0d000000-0000-0000-0000-000000000001', 'knock', 'owner')$$,
  '42501', null,
  'no link can make someone owner'
);

-- Editor ----------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select throws_ok(
  $$select public.create_invite_link('0d000000-0000-0000-0000-000000000001', 'knock', 'editor')$$,
  '42501', null,
  'an editor cannot hand out editor links'
);

select isnt(
  set_config('test.editor_knock', public.create_invite_link(
    '0d000000-0000-0000-0000-000000000001', 'knock'), true),
  null,
  'an editor can make a contributor link'
);

select throws_ok(
  $$select token_hash from public.snapshot_invite_link$$,
  '42501', null,
  'nobody can read token hashes'
);

select is(
  (select count(*)::int from public.snapshot_invite_link),
  4,
  'editors can see the snapshot''s links'
);

-- Contributor -----------------------------------------------------------------

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select throws_ok(
  $$select public.create_invite_link('0d000000-0000-0000-0000-000000000001', 'knock')$$,
  '42501', null,
  'a contributor cannot make links'
);

-- Previews, signed out --------------------------------------------------------

reset role;
set local role anon;

select is(
  (select inviter_name from public.preview_invite_link(current_setting('test.knock'))),
  'Owner O',
  'a signed-out preview shows who invited you'
);

select is(
  (select count(*)::int from public.preview_invite_link('not-a-real-token')),
  0,
  'an unknown token previews nothing'
);

select throws_ok(
  format('select public.redeem_invite_link(%L)', current_setting('test.knock')),
  '42501', null,
  'you must be signed in to use a link'
);

-- Knocking --------------------------------------------------------------------

reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  public.redeem_invite_link(current_setting('test.knock')),
  'requested',
  'an open link knocks'
);

select is(
  public.redeem_invite_link(current_setting('test.knock')),
  'requested',
  'knocking twice is harmless'
);

select is(
  (select count(*)::int from public.snapshot_join_request where status = 'pending'),
  1,
  'one pending request per person'
);

select is(
  (select count(*)::int from public.snapshot where title = 'Lake weekend'),
  0,
  'knocking does not let you in'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$select public.respond_to_join_request(id, true) from public.snapshot_join_request
    where account_id = '0c000000-0000-0000-0000-000000000004'$$,
  'the owner can approve a knock'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Lake weekend'),
  1,
  'once approved, the knocker is in'
);

select is(
  public.redeem_invite_link(current_setting('test.knock')),
  'already_member',
  'a member using the link again changes nothing'
);

-- Addressed links -------------------------------------------------------------

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000006", "role": "authenticated"}';

select throws_ok(
  format('select public.redeem_invite_link(%L)', current_setting('test.addressed')),
  '22023', null,
  'an addressed link does not work for someone else'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000007", "role": "authenticated"}';

select throws_ok(
  format('select public.redeem_invite_link(%L)', current_setting('test.unverified')),
  '22023', null,
  'or for the right email before it is verified'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  public.redeem_invite_link(current_setting('test.addressed')),
  'joined',
  'the verified recipient joins at once'
);

select is(
  (select count(*)::int from public.snapshot where title = 'Lake weekend'),
  1,
  'and can see the snapshot'
);

reset role;

select is(
  (select use_count from public.snapshot_invite_link where addressed_email = 'target@example.com'),
  1,
  'an addressed link is used up after one join'
);

-- Revoked, expired and blocked ------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$select public.revoke_invite_link(id) from public.snapshot_invite_link
    where mode = 'knock' and created_by = '0c000000-0000-0000-0000-000000000001'$$,
  'the owner can revoke a link'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000009", "role": "authenticated"}';

select throws_ok(
  format('select public.redeem_invite_link(%L)', current_setting('test.knock')),
  '22023', null,
  'a revoked link no longer works'
);

reset role;
update public.snapshot_invite_link set expires_at = now() - interval '1 day'
  where created_by = '0c000000-0000-0000-0000-000000000002';
set local role authenticated;

select throws_ok(
  format('select public.redeem_invite_link(%L)', current_setting('test.editor_knock')),
  '22023', null,
  'an expired link no longer works'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000001", "role": "authenticated"}';
insert into public.block (blocked_id) values ('0c000000-0000-0000-0000-000000000008');
select ok(
  set_config('test.knock2', public.create_invite_link(
    '0d000000-0000-0000-0000-000000000001', 'knock'), true) is not null,
  'the owner makes a new open link'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000008", "role": "authenticated"}';

select throws_ok(
  format('select public.redeem_invite_link(%L)', current_setting('test.knock2')),
  '22023', null,
  'someone the owner blocked cannot use their links'
);

-- An editor answers a knock ---------------------------------------------------

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000009", "role": "authenticated"}';

select is(
  public.redeem_invite_link(current_setting('test.knock2')),
  'requested',
  'a newcomer knocks'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$select public.respond_to_join_request(id, false) from public.snapshot_join_request
    where account_id = '0c000000-0000-0000-0000-000000000009'$$,
  'an editor can deny a contributor knock'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000009", "role": "authenticated"}';

select is(
  (select status::text from public.snapshot_join_request),
  'denied',
  'the requester sees the answer'
);

-- Declining an in-app invitation leaves no trace ------------------------------

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000001", "role": "authenticated"}';
insert into public.snapshot_invitation (snapshot_id, invitee_account_id)
  values ('0d000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000009');

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000009", "role": "authenticated"}';
select lives_ok(
  $$select public.respond_to_invitation(id, false) from public.snapshot_invitation$$,
  'the invitee declines'
);

set local request.jwt.claims to '{"sub": "0c000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot_invitation
    where invitee_account_id = '0c000000-0000-0000-0000-000000000009'),
  0,
  'the inviter no longer sees a declined invitation'
);

select is(
  (select count(*)::int from public.snapshot_audit_log where action = 'invitation_declined'),
  0,
  'and the audit log does not record it'
);

select is(
  (select count(distinct action)::int from public.snapshot_audit_log
    where action in ('link_created', 'link_revoked')),
  2,
  'creating and revoking links is audited'
);

select * from finish();
rollback;
