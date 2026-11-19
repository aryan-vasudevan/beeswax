-- Tests for BWX-95 and BWX-100: moments inside a snapshot, placing media
-- and recollections in them, and recollections as each person's own account.
-- Run with `supabase test db`.
--
-- Cast: in "Toronto weekend", owner and editor arrange; contrib and contrib2
-- remember things differently; viewer reads; stranger sees it once public.

begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (id, email, raw_user_meta_data) values
  ('2a000000-0000-0000-0000-000000000001', 'r_owner@example.com', '{"username": "r_owner"}'),
  ('2a000000-0000-0000-0000-000000000002', 'r_editor@example.com', '{"username": "r_editor"}'),
  ('2a000000-0000-0000-0000-000000000003', 'r_contrib@example.com', '{"username": "r_contrib"}'),
  ('2a000000-0000-0000-0000-000000000004', 'r_contrib2@example.com', '{"username": "r_contrib2"}'),
  ('2a000000-0000-0000-0000-000000000005', 'r_viewer@example.com', '{"username": "r_viewer"}'),
  ('2a000000-0000-0000-0000-000000000006', 'r_stranger@example.com', '{"username": "r_stranger"}');

insert into public.snapshot (id, owner_id, creator_id, status, title) values
  ('2b000000-0000-0000-0000-000000000001', '2a000000-0000-0000-0000-000000000001',
   '2a000000-0000-0000-0000-000000000001', 'published', 'Toronto weekend'),
  ('2b000000-0000-0000-0000-000000000002', '2a000000-0000-0000-0000-000000000001',
   '2a000000-0000-0000-0000-000000000001', 'published', 'Other memory');

insert into public.snapshot_member (snapshot_id, account_id, role) values
  ('2b000000-0000-0000-0000-000000000001', '2a000000-0000-0000-0000-000000000002', 'editor'),
  ('2b000000-0000-0000-0000-000000000001', '2a000000-0000-0000-0000-000000000003', 'contributor'),
  ('2b000000-0000-0000-0000-000000000001', '2a000000-0000-0000-0000-000000000004', 'contributor'),
  ('2b000000-0000-0000-0000-000000000001', '2a000000-0000-0000-0000-000000000005', 'viewer');

insert into public.media_item (
  id, snapshot_id, uploaded_by, contributor_person_id, kind, status, idempotency_key, mime_type, caption
)
select '2c000000-0000-0000-0000-000000000001', '2b000000-0000-0000-0000-000000000001',
  '2a000000-0000-0000-0000-000000000003', p.id, 'photo', 'ready',
  '2d000000-0000-0000-0000-000000000001', 'image/jpeg', 'Pasta'
from public.person p
where p.account_id = '2a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;

insert into public.snapshot_moment (id, snapshot_id, title, position) values
  ('2e000000-0000-0000-0000-000000000099', '2b000000-0000-0000-0000-000000000002', 'Elsewhere', 1);

-- Arranging, as the editor --------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$insert into public.snapshot_moment (snapshot_id, title, position) values
    ('2b000000-0000-0000-0000-000000000001', 'Arrival', 1),
    ('2b000000-0000-0000-0000-000000000001', 'Dinner', 2)$$,
  'an editor can lay out moments'
);

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select throws_ok(
  $$insert into public.snapshot_moment (snapshot_id, title, position)
    values ('2b000000-0000-0000-0000-000000000001', 'Mine', 3)$$,
  '42501', null,
  'a contributor cannot add moments'
);

-- Contributing, as the contributor ------------------------------------------

select lives_ok(
  $$update public.media_item
    set moment_id = (select id from public.snapshot_moment where title = 'Dinner')
    where caption = 'Pasta'$$,
  'a contributor can place their own photo in a moment'
);

select lives_ok(
  $$insert into public.recollection (snapshot_id, moment_id, kind, body)
    select '2b000000-0000-0000-0000-000000000001', id, 'unphotographed',
      'The waiter sang to us.'
    from public.snapshot_moment where title = 'Dinner'$$,
  'and write what nobody photographed'
);

select is(
  (select p.display_name from public.recollection r
    join public.person p on p.id = r.author_person_id
    where r.body = 'The waiter sang to us.'),
  'r_contrib',
  'the recollection is attributed to its writer'
);

-- A different account of the same moment -----------------------------------

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

update public.media_item
  set moment_id = (select id from public.snapshot_moment where title = 'Arrival')
  where caption = 'Pasta';
select is(
  (select m.title from public.media_item i
    join public.snapshot_moment m on m.id = i.moment_id
    where i.caption = 'Pasta'),
  'Dinner',
  'another contributor cannot move someone else''s photo'
);

select lives_ok(
  $$insert into public.recollection (snapshot_id, moment_id, kind, body)
    select '2b000000-0000-0000-0000-000000000001', id, 'quote',
      'It was the manager, not the waiter.'
    from public.snapshot_moment where title = 'Dinner'$$,
  'and can remember the same moment differently'
);

-- As the viewer -------------------------------------------------------------

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.recollection r
    join public.snapshot_moment m on m.id = r.moment_id
    where m.title = 'Dinner'),
  2,
  'both accounts of dinner stand side by side'
);

select throws_ok(
  $$insert into public.recollection (snapshot_id, body)
    values ('2b000000-0000-0000-0000-000000000001', 'I was there too')$$,
  '42501', null,
  'a viewer cannot write recollections'
);

update public.recollection set body = 'Rewritten' where body = 'The waiter sang to us.';
select is(
  (select count(*)::int from public.recollection where body = 'The waiter sang to us.'),
  1,
  'a viewer cannot rewrite anyone''s recollection'
);

-- Moderating and arranging, as the editor -----------------------------------

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$update public.media_item
    set moment_id = (select id from public.snapshot_moment where title = 'Arrival')
    where caption = 'Pasta'$$,
  'an editor can move anyone''s photo between moments'
);

select throws_ok(
  $$update public.recollection set body = 'Edited' where body = 'The waiter sang to us.'$$,
  '42501', null,
  'but cannot rewrite anyone''s recollection'
);

select lives_ok(
  $$update public.recollection set hidden_at = now()
    where body = 'It was the manager, not the waiter.'$$,
  'an editor can hide a recollection'
);

select throws_ok(
  $$update public.media_item set moment_id = '2e000000-0000-0000-0000-000000000099'
    where caption = 'Pasta'$$,
  '23514', null,
  'a photo cannot be placed in another memory''s moment'
);

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.recollection),
  1,
  'a hidden recollection disappears for viewers'
);

-- Suggested moments ---------------------------------------------------------

reset role;
insert into public.snapshot_moment (snapshot_id, title, position, status, created_by)
  values ('2b000000-0000-0000-0000-000000000001', 'Late night', 3, 'suggested', null);
set local role authenticated;

select is(
  (select count(*)::int from public.snapshot_moment
    where snapshot_id = '2b000000-0000-0000-0000-000000000001'),
  2,
  'viewers see only confirmed moments'
);

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot_moment
    where snapshot_id = '2b000000-0000-0000-0000-000000000001'),
  3,
  'editors also see suggestions'
);

select lives_ok(
  $$update public.snapshot_moment set status = 'confirmed' where title = 'Late night'$$,
  'and can confirm one'
);

select lives_ok(
  $$update public.snapshot_moment set position = 0.5 where title = 'Dinner'$$,
  'and reorder by moving one moment between two others'
);

select is(
  (select string_agg(title, ', ' order by position) from public.snapshot_moment
    where snapshot_id = '2b000000-0000-0000-0000-000000000001'),
  'Dinner, Arrival, Late night',
  'moments read in their new order'
);

select lives_ok(
  $$delete from public.snapshot_moment where title = 'Dinner'$$,
  'an editor can remove a moment'
);

select ok(
  (select moment_id is null from public.recollection where body = 'The waiter sang to us.'),
  'its recollections stay in the memory, unplaced'
);

-- Public --------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000001", "role": "authenticated"}';
update public.snapshot set visibility = 'public' where title = 'Toronto weekend';

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000003", "role": "authenticated"}';
update public.recollection set audience = 'public_ok' where body = 'The waiter sang to us.';

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000006", "role": "authenticated"}';

select is(
  (select count(*)::int from public.recollection),
  1,
  'a stranger on the public link sees only recollections their authors made public'
);

set local request.jwt.claims to '{"sub": "2a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select lives_ok(
  $$update public.recollection set deleted_at = now() where body = 'The waiter sang to us.'$$,
  'an author can delete their recollection'
);

reset role;
set local role anon;

select is(
  (select count(*)::int from public.recollection),
  0,
  'anonymous requests see no recollections'
);

select * from finish();
rollback;
