-- Tests for BWX-13: snapshots, participants, members, invitations,
-- audience, drafts, soft delete, audit log and ownership handover.
-- Run with `supabase test db`.
--
-- Cast, by account:
--   owner      creates "Orientation Week"
--   editor     invited as editor
--   contrib    invited as contributor
--   latecomer  invited by the editor, declines
--   audience   allowed to look when visibility is custom
--   outsider   nothing to do with it, later blocked by the owner
-- plus "Grandpa Yusuf", an identity the owner adds as a participant.

begin;
create extension if not exists pgtap with schema extensions;
select plan(53);

insert into auth.users (id, email, raw_user_meta_data) values
  ('0a000000-0000-0000-0000-000000000001', 'owner@example.com', '{"username": "t_owner"}'),
  ('0a000000-0000-0000-0000-000000000002', 'editor@example.com', '{"username": "t_editor"}'),
  ('0a000000-0000-0000-0000-000000000003', 'contrib@example.com', '{"username": "t_contrib"}'),
  ('0a000000-0000-0000-0000-000000000004', 'outsider@example.com', '{"username": "t_outsider"}'),
  ('0a000000-0000-0000-0000-000000000005', 'audience@example.com', '{"username": "t_audience"}'),
  ('0a000000-0000-0000-0000-000000000006', 'late@example.com', '{"username": "t_latecomer"}');

-- As the owner: creating ------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$insert into public.snapshot (status, title, starts_at, ends_at, timezone, place_name)
    values ('published', 'Orientation Week', '2026-09-01 09:00-04', '2026-09-07 23:00-04',
      'America/Toronto', 'Waterloo')$$,
  'a user can create and publish a snapshot'
);

select is(
  (select m.role::text from public.snapshot_member m
    join public.snapshot s on s.id = m.snapshot_id
    where s.title = 'Orientation Week'),
  'owner',
  'the owner is its only member, with role owner'
);

select lives_ok(
  $$insert into public.snapshot (description) values ('half a thought')$$,
  'a draft needs nothing at all'
);

select lives_ok(
  $$insert into public.snapshot (status, title, starts_at, date_precision)
    values ('published', 'Solo trip', '2008-06-01', 'season')$$,
  'an approximate date needs no timezone'
);

select throws_ok(
  $$insert into public.snapshot (status) values ('published')$$,
  '23514', null,
  'a published snapshot needs a title'
);

select throws_ok(
  $$insert into public.snapshot (title, starts_at, timezone)
    values ('Nowhere', now(), 'Mars/Olympus_Mons')$$,
  '22023', null,
  'an unknown timezone is rejected'
);

select throws_ok(
  $$insert into public.snapshot (title, starts_at, ends_at)
    values ('Backwards', '2026-09-02', '2026-09-01')$$,
  '23514', null,
  'a snapshot cannot end before it starts'
);

select throws_ok(
  $$insert into public.snapshot (title, starts_at, date_precision)
    values ('Exact', now(), 'minute')$$,
  '23514', null,
  'an exact time needs a timezone'
);

insert into public.person (display_name) values ('Grandpa Yusuf');

select lives_ok(
  $$insert into public.snapshot_participant (snapshot_id, person_id)
    select s.id, p.id from public.snapshot s, public.person p
    where s.title = 'Orientation Week' and p.display_name = 'Grandpa Yusuf'$$,
  'the owner can add an identity as a participant'
);

select lives_ok(
  $$insert into public.snapshot_invitation (snapshot_id, invitee_account_id, role)
    select s.id, r.account::uuid, r.role::public.snapshot_role
    from public.snapshot s
    cross join (values
      ('0a000000-0000-0000-0000-000000000002', 'editor'),
      ('0a000000-0000-0000-0000-000000000003', 'contributor')
    ) as r (account, role)
    where s.title = 'Orientation Week'$$,
  'the owner can invite an editor and a contributor'
);

select throws_ok(
  $$insert into public.snapshot_invitation (snapshot_id, invitee_account_id)
    select id, '0a000000-0000-0000-0000-000000000003' from public.snapshot
    where title = 'Orientation Week'$$,
  '23505', null,
  'no duplicate pending invitations'
);

-- As the outsider ---------------------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  0,
  'an outsider cannot see a private snapshot'
);

select is(
  (select count(*)::int from public.snapshot_invitation),
  0,
  'an outsider cannot see its invitations'
);

-- As the contributor: before and after accepting ----------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  0,
  'an invitation alone does not let you in'
);

select is(
  (select count(*)::int from public.person
    where account_id = '0a000000-0000-0000-0000-000000000001'),
  1,
  'you can see who invited you'
);

select lives_ok(
  $$select public.respond_to_invitation(id, true) from public.snapshot_invitation$$,
  'the contributor accepts'
);

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  1,
  'once accepted, the member can see the snapshot'
);

select is(
  (select count(*)::int from public.person where display_name = 'Grandpa Yusuf'),
  1,
  'members can see the participants, even identities someone else created'
);

update public.snapshot set title = 'Hijacked' where title = 'Orientation Week';
select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  1,
  'a contributor cannot edit the details'
);

select throws_ok(
  $$insert into public.snapshot_invitation (snapshot_id, invitee_account_id)
    select id, '0a000000-0000-0000-0000-000000000004' from public.snapshot
    where title = 'Orientation Week'$$,
  '42501', null,
  'a contributor cannot invite'
);

select throws_ok(
  $$insert into public.snapshot_participant (snapshot_id, person_id)
    select s.id, p.id from public.snapshot s, public.person p
    where s.title = 'Orientation Week'
      and p.account_id = '0a000000-0000-0000-0000-000000000003'$$,
  '42501', null,
  'a contributor cannot add participants'
);

-- As the editor -------------------------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$select public.respond_to_invitation(id, true) from public.snapshot_invitation
    where invitee_account_id = '0a000000-0000-0000-0000-000000000002'$$,
  'the editor accepts'
);

select lives_ok(
  $$update public.snapshot set description = 'First week in Waterloo'
    where title = 'Orientation Week'$$,
  'an editor can edit the details'
);

select is(
  (select description from public.snapshot where title = 'Orientation Week'),
  'First week in Waterloo',
  'the edit is saved'
);

select throws_ok(
  $$update public.snapshot set visibility = 'public' where title = 'Orientation Week'$$,
  '42501', null,
  'an editor cannot change who can see it'
);

select throws_ok(
  $$update public.snapshot set archived_at = now() where title = 'Orientation Week'$$,
  '42501', null,
  'an editor cannot archive it'
);

select throws_ok(
  $$insert into public.snapshot_invitation (snapshot_id, invitee_account_id, role)
    select id, '0a000000-0000-0000-0000-000000000006', 'editor' from public.snapshot
    where title = 'Orientation Week'$$,
  '42501', null,
  'an editor cannot invite another editor'
);

select lives_ok(
  $$insert into public.snapshot_invitation (snapshot_id, invitee_account_id)
    select id, '0a000000-0000-0000-0000-000000000006' from public.snapshot
    where title = 'Orientation Week'$$,
  'an editor can invite a contributor'
);

delete from public.snapshot_member where role = 'owner';
select is(
  (select count(*)::int from public.snapshot_member where role = 'owner'),
  1,
  'an editor cannot remove the owner'
);

-- As the latecomer: declining ---------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000006", "role": "authenticated"}';

select lives_ok(
  $$select public.respond_to_invitation(id, false) from public.snapshot_invitation$$,
  'an invitee can decline'
);

select throws_ok(
  $$select public.respond_to_invitation(id, true) from public.snapshot_invitation$$,
  '22023', null,
  'an answered invitation cannot be answered again'
);

-- Drafts ------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where status = 'draft'),
  0,
  'nobody else sees the owner''s drafts'
);

-- Custom audience -----------------------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$update public.snapshot set visibility = 'custom' where title = 'Orientation Week'$$,
  'the owner can change visibility'
);

select lives_ok(
  $$insert into public.snapshot_audience (snapshot_id, account_id)
    select id, '0a000000-0000-0000-0000-000000000005' from public.snapshot
    where title = 'Orientation Week'$$,
  'the owner can add someone to the audience'
);

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  1,
  'the audience can see a custom snapshot'
);

select is(
  (select count(*)::int from public.snapshot_audit_log),
  0,
  'only the owner reads the audit log'
);

-- Soft delete and restore ---------------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$update public.snapshot set deleted_at = now() where title = 'Orientation Week'$$,
  'the owner can delete a snapshot'
);

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  0,
  'a deleted snapshot disappears for members'
);

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$update public.snapshot set deleted_at = null where title = 'Orientation Week'$$,
  'the owner can restore it'
);

select is(
  (select count(distinct action)::int from public.snapshot_audit_log
    where action in ('member_added', 'invited', 'invitation_declined',
                     'visibility_changed', 'deleted', 'restored')),
  6,
  'the audit log records invitations, members, visibility, deletion and restore'
);

delete from public.snapshot where title = 'Orientation Week';
select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  1,
  'a published snapshot cannot be hard-deleted'
);

delete from public.snapshot where status = 'draft';
select is(
  (select count(*)::int from public.snapshot where status = 'draft'),
  0,
  'a draft can be discarded'
);

-- Leaving -------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select lives_ok(
  $$delete from public.snapshot_member
    where account_id = '0a000000-0000-0000-0000-000000000003'$$,
  'a member can leave'
);

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  0,
  'after leaving, the snapshot is gone from their hive'
);

-- Linking an identity grants nothing ----------------------------------------

reset role;
set local request.jwt.claims to '';
update public.person set account_id = '0a000000-0000-0000-0000-000000000004'
  where display_name = 'Grandpa Yusuf';

set local role authenticated;
set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  0,
  'being linked to a participant identity grants no access'
);

-- Public, and blocks --------------------------------------------------------

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
update public.snapshot set visibility = 'public' where title = 'Orientation Week';

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  1,
  'any signed-in user with the link can see a public snapshot'
);

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
insert into public.block (blocked_id) values ('0a000000-0000-0000-0000-000000000004');

set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation Week'),
  0,
  'someone the owner blocked cannot see their public snapshots'
);

-- Anonymous -----------------------------------------------------------------

reset role;
set local role anon;
select is(
  (select count(*)::int from public.snapshot),
  0,
  'anonymous requests see no snapshots'
);

-- The owner deletes their account -------------------------------------------

reset role;
set local request.jwt.claims to '';
delete from auth.users where id = '0a000000-0000-0000-0000-000000000001';

select is(
  (select owner_id from public.snapshot where title = 'Orientation Week'),
  '0a000000-0000-0000-0000-000000000002'::uuid,
  'the snapshot passes to the editor'
);

select is(
  (select role::text from public.snapshot_member m
    join public.snapshot s on s.id = m.snapshot_id
    where s.title = 'Orientation Week'
      and m.account_id = '0a000000-0000-0000-0000-000000000002'),
  'owner',
  'the editor becomes its owner member'
);

select is(
  (select count(*)::int from public.snapshot where title = 'Solo trip'),
  0,
  'a snapshot nobody else was in is deleted with the account'
);

set local role authenticated;
set local request.jwt.claims to '{"sub": "0a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  (select count(*)::int from public.person where display_name = 'Grandpa Yusuf'),
  1,
  'the new owner still sees the people in it'
);

select lives_ok(
  $$update public.snapshot set visibility = 'private' where title = 'Orientation Week'$$,
  'the new owner can manage it'
);

select * from finish();
rollback;
