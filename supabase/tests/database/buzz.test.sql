-- Tests for BWX-101: the Buzz inbox, batching, quiet hours and blocks.
-- Run with `supabase test db`.
--
-- Cast: alice owns "Lake trip"; bob befriends her; carol is invited; dan is
-- added by the owner's side; eve knocks through an open link.

begin;
create extension if not exists pgtap with schema extensions;
select plan(42);

insert into auth.users (id, email, raw_user_meta_data) values
  ('4a000000-0000-0000-0000-000000000001', 'z_alice@example.com', '{"username": "z_alice"}'),
  ('4a000000-0000-0000-0000-000000000002', 'z_bob@example.com', '{"username": "z_bob"}'),
  ('4a000000-0000-0000-0000-000000000003', 'z_carol@example.com', '{"username": "z_carol"}'),
  ('4a000000-0000-0000-0000-000000000004', 'z_dan@example.com', '{"username": "z_dan"}'),
  ('4a000000-0000-0000-0000-000000000005', 'z_eve@example.com', '{"username": "z_eve"}');

insert into public.snapshot (id, owner_id, creator_id, status, title) values
  ('4b000000-0000-0000-0000-000000000001', '4a000000-0000-0000-0000-000000000001',
   '4a000000-0000-0000-0000-000000000001', 'published', 'Lake trip');

-- Friends -------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000002", "role": "authenticated"}';
insert into public.friendship (addressee_id) values ('4a000000-0000-0000-0000-000000000001');

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select kind::text from public.buzz),
  'friend_request',
  'a friend request buzzes the person asked'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz),
  0,
  'nobody else sees it'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
update public.friendship set status = 'accepted'
  where requester_id = '4a000000-0000-0000-0000-000000000002';

select ok(
  (select read_at is not null from public.buzz where kind = 'friend_request'),
  'answering a request marks it read'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  (select kind::text from public.buzz),
  'friend_accepted',
  'the requester hears it was accepted'
);

-- Invitations ---------------------------------------------------------------

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
insert into public.snapshot_invitation (snapshot_id, invitee_account_id, role)
  values ('4b000000-0000-0000-0000-000000000001', '4a000000-0000-0000-0000-000000000003', 'contributor');

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select kind::text from public.buzz),
  'invitation',
  'an invitation buzzes the invitee'
);

select is(
  (select snapshot_title from public.buzz_inbox()),
  null,
  'it never says what the memory is'
);

select is(
  (select actor_names from public.buzz_inbox()),
  array['z_alice'],
  'only who invited them'
);

select lives_ok(
  $$select public.respond_to_invitation((select subject_id from public.buzz), true)$$,
  'the invitee accepts from the buzz'
);

select ok(
  (select read_at is not null from public.buzz where kind = 'invitation'),
  'accepting marks the invitation read'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select actor_ids from public.buzz where kind = 'member_joined'),
  array['4a000000-0000-0000-0000-000000000003'::uuid],
  'the inviter hears they arrived'
);

-- Someone else lets dan in --------------------------------------------------

reset role;
set local request.jwt.claims to '';
insert into public.snapshot_member (snapshot_id, account_id, role, added_by)
  values ('4b000000-0000-0000-0000-000000000001', '4a000000-0000-0000-0000-000000000004',
    'contributor', '4a000000-0000-0000-0000-000000000001');
set local role authenticated;

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select kind::text from public.buzz),
  'welcome',
  'someone let in by another is welcomed'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select cardinality(actor_ids) from public.buzz where kind = 'member_joined'),
  2,
  'arrivals batch into one buzz'
);

-- Contributions -------------------------------------------------------------

reset role;
set local request.jwt.claims to '';
insert into public.media_item (
  snapshot_id, uploaded_by, contributor_person_id, kind, status, idempotency_key, mime_type, caption
)
select '4b000000-0000-0000-0000-000000000001', p.account_id, p.id, t.kind::public.media_kind, 'ready',
  gen_random_uuid(), t.mime, t.caption
from public.person p
join (values
  ('4a000000-0000-0000-0000-000000000003'::uuid, 'photo', 'image/jpeg', 'Dock'),
  ('4a000000-0000-0000-0000-000000000003'::uuid, 'photo', 'image/jpeg', 'Canoe'),
  ('4a000000-0000-0000-0000-000000000004'::uuid, 'video', 'video/mp4', 'Jump')
) as t (account_id, kind, mime, caption) on t.account_id = p.account_id
where p.created_by = p.account_id;
set local role authenticated;

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000003", "role": "authenticated"}';
insert into public.recollection (snapshot_id, body)
  values ('4b000000-0000-0000-0000-000000000001', 'The loon at dawn.');

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz where kind = 'new_contributions'),
  1,
  'contributions batch into one buzz per memory'
);

select is(
  (select item_count || '/' || (details ->> 'photo') || '/' || (details ->> 'video')
      || '/' || (details ->> 'recollection')
    from public.buzz where kind = 'new_contributions'),
  '4/2/1/1',
  'counting each kind of thing added'
);

select is(
  (select actor_names from public.buzz_inbox() where kind = 'new_contributions'),
  array['z_carol', 'z_dan'],
  'newest contributor first'
);

select ok(
  (select deliver_after > now() + interval '9 minutes'
    from public.buzz where kind = 'new_contributions'),
  'a batch waits before it may push'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select item_count from public.buzz where kind = 'new_contributions'),
  1,
  'nobody is buzzed about their own contributions'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
update public.buzz set read_at = now() where read_at is null;

select is(
  (select count(*)::int from public.buzz where read_at is null),
  0,
  'everything can be marked read'
);

reset role;
set local request.jwt.claims to '';
insert into public.media_item (
  snapshot_id, uploaded_by, contributor_person_id, kind, status, idempotency_key, mime_type, caption
)
select '4b000000-0000-0000-0000-000000000001', p.account_id, p.id, 'photo', 'ready',
  gen_random_uuid(), 'image/jpeg', 'Fire'
from public.person p
where p.account_id = '4a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;
set local role authenticated;
set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz where kind = 'new_contributions'),
  2,
  'after reading, new contributions start a new buzz'
);

select throws_ok(
  $$update public.buzz set kind = 'welcome'$$,
  '42501', null,
  'buzz cannot be rewritten'
);

select throws_ok(
  $$insert into public.buzz (recipient_id, kind)
    values ('4a000000-0000-0000-0000-000000000001', 'welcome')$$,
  '42501', null,
  'or forged'
);

-- Knocks --------------------------------------------------------------------

select ok(
  set_config('test.token',
    public.create_invite_link('4b000000-0000-0000-0000-000000000001', 'knock'), true) is not null,
  'the owner makes an open link'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000005", "role": "authenticated"}';
select is(
  public.redeem_invite_link(current_setting('test.token')),
  'requested',
  'a stranger knocks'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz where kind = 'knock' and read_at is null),
  1,
  'a knock buzzes the owner'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz where kind = 'knock'),
  0,
  'but not contributors, who cannot answer it'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
select lives_ok(
  $$select public.respond_to_join_request(
    (select subject_id from public.buzz where kind = 'knock'), true)$$,
  'the owner lets them in from the buzz'
);

select ok(
  (select read_at is not null from public.buzz where kind = 'knock'),
  'answering a knock marks it read'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select kind::text from public.buzz),
  'welcome',
  'and the knocker is welcomed in'
);

-- Roles and going public ----------------------------------------------------

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
update public.snapshot_member set role = 'editor'
  where account_id = '4a000000-0000-0000-0000-000000000003';
update public.snapshot set visibility = 'public'
  where id = '4b000000-0000-0000-0000-000000000001';

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select details ->> 'to' from public.buzz where kind = 'role_changed'),
  'editor',
  'a role change buzzes the member'
);

select is(
  (select count(*)::int from public.buzz where kind = 'public_consent'),
  1,
  'going public asks contributors about their members-only items'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz where kind = 'public_consent'),
  0,
  'but not members with nothing in it'
);

-- Quiet hours ---------------------------------------------------------------

reset role;
set local request.jwt.claims to '';
update public.account_settings
  set quiet_hours_start = '22:00', quiet_hours_end = '07:00', timezone = 'America/Toronto'
  where account_id = '4a000000-0000-0000-0000-000000000005';

select is(
  private.buzz_deliver_after('4a000000-0000-0000-0000-000000000005', '2026-10-15 23:30-04'),
  '2026-10-16 07:00-04'::timestamptz,
  'a push during quiet hours waits until they end'
);

select is(
  private.buzz_deliver_after('4a000000-0000-0000-0000-000000000005', '2026-10-16 03:00-04'),
  '2026-10-16 07:00-04'::timestamptz,
  'including after midnight'
);

select is(
  private.buzz_deliver_after('4a000000-0000-0000-0000-000000000005', '2026-10-15 12:00-04'),
  '2026-10-15 12:00-04'::timestamptz,
  'outside quiet hours it goes at once'
);

update public.account_settings set timezone = 'Not/A_Zone'
  where account_id = '4a000000-0000-0000-0000-000000000005';

select is(
  private.buzz_deliver_after('4a000000-0000-0000-0000-000000000005', '2026-10-15 23:30Z'),
  '2026-10-16 07:00Z'::timestamptz,
  'an unknown time zone falls back to UTC'
);

-- Blocks --------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000003", "role": "authenticated"}';
insert into public.block (blocked_id) values ('4a000000-0000-0000-0000-000000000001');

select is(
  (select count(*)::int from public.buzz
    where actor_id = '4a000000-0000-0000-0000-000000000001'
      or '4a000000-0000-0000-0000-000000000001' = any(actor_ids)),
  0,
  'blocking clears buzz from that person'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz
    where '4a000000-0000-0000-0000-000000000003' = any(actor_ids)),
  0,
  'in both directions'
);

select ok(
  exists (
    select 1 from public.buzz
    where kind = 'new_contributions'
      and actor_ids = array['4a000000-0000-0000-0000-000000000004'::uuid]
  ),
  'batches keep everyone else'
);

-- Leaving and deleting ------------------------------------------------------

delete from public.snapshot_member where account_id = '4a000000-0000-0000-0000-000000000004';

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.buzz),
  0,
  'leaving a memory silently clears its buzz'
);

set local request.jwt.claims to '{"sub": "4a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
update public.snapshot set deleted_at = now() where id = '4b000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.buzz where snapshot_id is not null),
  0,
  'deleting a memory clears all its buzz'
);

select is(
  (select count(*)::int from public.buzz where kind = 'friend_request'),
  1,
  'and nothing else'
);

reset role;
set local role anon;

select is(
  (select count(*)::int from public.buzz),
  0,
  'anonymous requests see no buzz'
);

select * from finish();
rollback;
