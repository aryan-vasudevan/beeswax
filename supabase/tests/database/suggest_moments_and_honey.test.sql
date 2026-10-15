-- Tests for BWX-96 (suggested moments) and BWX-44 (honey).
-- Run with `supabase test db`.
--
-- "Concert night" has photos at 19:20, 19:40, 21:15, 21:30 and 23:50, plus
-- one with only an estimated time. Owner, editor, contrib and viewer are
-- members; Grandpa is a participant without an account.

begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users (id, email, raw_user_meta_data) values
  ('3a000000-0000-0000-0000-000000000001', 'h_owner@example.com', '{"username": "h_owner"}'),
  ('3a000000-0000-0000-0000-000000000002', 'h_editor@example.com', '{"username": "h_editor"}'),
  ('3a000000-0000-0000-0000-000000000003', 'h_contrib@example.com', '{"username": "h_contrib"}'),
  ('3a000000-0000-0000-0000-000000000004', 'h_viewer@example.com', '{"username": "h_viewer"}'),
  ('3a000000-0000-0000-0000-000000000005', 'h_outsider@example.com', '{"username": "h_outsider"}');

insert into public.snapshot (id, owner_id, creator_id, status, title) values
  ('3b000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000001',
   '3a000000-0000-0000-0000-000000000001', 'published', 'Concert night');

insert into public.snapshot_member (snapshot_id, account_id, role) values
  ('3b000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000002', 'editor'),
  ('3b000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000003', 'contributor'),
  ('3b000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000004', 'viewer');

insert into public.person (id, created_by, display_name) values
  ('3c000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000001', 'Grandpa');
insert into public.snapshot_participant (snapshot_id, person_id) values
  ('3b000000-0000-0000-0000-000000000001', '3c000000-0000-0000-0000-000000000001');

insert into public.media_item (
  snapshot_id, uploaded_by, contributor_person_id, kind, status,
  idempotency_key, mime_type, caption, captured_at, captured_at_estimated
)
select '3b000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000003', p.id,
  'photo', 'ready', gen_random_uuid(), 'image/jpeg', t.caption, t.at::timestamptz, t.estimated
from public.person p
cross join (values
  ('arrive 1', '2026-10-10 19:20-04', false),
  ('arrive 2', '2026-10-10 19:40-04', false),
  ('show 1',   '2026-10-10 21:15-04', false),
  ('show 2',   '2026-10-10 21:30-04', false),
  ('alone',    '2026-10-10 23:50-04', false),
  ('guess',    '2026-10-10 20:00-04', true)
) as t (caption, at, estimated)
where p.account_id = '3a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;

-- Suggesting ----------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "3a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select throws_ok(
  $$select public.suggest_moments('3b000000-0000-0000-0000-000000000001')$$,
  '42501', null,
  'a contributor cannot ask for suggestions'
);

set local request.jwt.claims to '{"sub": "3a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  public.suggest_moments('3b000000-0000-0000-0000-000000000001'),
  2,
  'photos split into moments at gaps longer than 90 minutes'
);

select is(
  (select string_agg(caption, ', ' order by captured_at) from public.media_item i
    join public.snapshot_moment m on m.id = i.moment_id
    where m.starts_at = '2026-10-10 19:20-04'),
  'arrive 1, arrive 2',
  'the first moment holds the arrival photos'
);

select ok(
  (select moment_id is null from public.media_item where caption = 'alone'),
  'a lone photo is not a moment'
);

select ok(
  (select moment_id is null from public.media_item where caption = 'guess'),
  'a photo with only an estimated time is never clustered'
);

set local request.jwt.claims to '{"sub": "3a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot_moment),
  0,
  'viewers do not see suggestions'
);

-- Dismissing and confirming -------------------------------------------------

set local request.jwt.claims to '{"sub": "3a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$update public.snapshot_moment set status = 'dismissed'
    where starts_at = '2026-10-10 19:20-04'$$,
  'an editor can dismiss a suggestion'
);

select ok(
  (select moment_id is null from public.media_item where caption = 'arrive 1'),
  'its photos become unplaced'
);

select is(
  public.suggest_moments('3b000000-0000-0000-0000-000000000001'),
  1,
  'suggesting again does not bring back what was dismissed'
);

select lives_ok(
  $$update public.snapshot_moment set status = 'confirmed', title = 'The show'
    where status = 'suggested'$$,
  'an editor can confirm a suggestion'
);

set local request.jwt.claims to '{"sub": "3a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select title from public.snapshot_moment where status = 'confirmed'),
  'The show',
  'once confirmed, everyone sees the moment'
);

-- Honey ---------------------------------------------------------------------

select is(
  (select people || '/' || contributed || '/' || honey
    from public.snapshot_honey(array['3b000000-0000-0000-0000-000000000001'::uuid])),
  '5/1/0.20',
  'honey is the share of the memory''s people who have added something'
);

set local request.jwt.claims to '{"sub": "3a000000-0000-0000-0000-000000000004", "role": "authenticated"}';
reset role;
insert into public.recollection (snapshot_id, author_person_id, written_by, body)
select '3b000000-0000-0000-0000-000000000001', p.id, p.account_id, 'Best encore ever.'
from public.person p
where p.account_id = '3a000000-0000-0000-0000-000000000002' and p.created_by = p.account_id;
set local role authenticated;

select is(
  (select honey from public.snapshot_honey(array['3b000000-0000-0000-0000-000000000001'::uuid])),
  0.40,
  'a written memory counts as much as a photo'
);

set local request.jwt.claims to '{"sub": "3a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int
    from public.snapshot_honey(array['3b000000-0000-0000-0000-000000000001'::uuid])),
  0,
  'honey is never reported for a memory you cannot see'
);

select throws_ok(
  format('select * from public.snapshot_honey(%L::uuid[])',
    (select array_agg(gen_random_uuid())::text from generate_series(1, 501))),
  '22023', null,
  'at most 500 cells at a time'
);

select * from finish();
rollback;
