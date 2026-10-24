-- Tests for BWX-122: hatching.
-- Run with `supabase test db`.
--
-- Cast: in "Road trip", owner, editor, amy and ben (contributors) can add;
-- viewer only reads. "Old news" already has amy's photo. "Early" and
-- "Overdue" test hatching early and on time.

begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users (id, email, raw_user_meta_data) values
  ('6a000000-0000-0000-0000-000000000001', 'k_owner@example.com', '{"username": "k_owner"}'),
  ('6a000000-0000-0000-0000-000000000002', 'k_editor@example.com', '{"username": "k_editor"}'),
  ('6a000000-0000-0000-0000-000000000003', 'k_amy@example.com', '{"username": "k_amy"}'),
  ('6a000000-0000-0000-0000-000000000004', 'k_ben@example.com', '{"username": "k_ben"}'),
  ('6a000000-0000-0000-0000-000000000005', 'k_viewer@example.com', '{"username": "k_viewer"}');

insert into public.snapshot (id, owner_id, creator_id, status, title, hatch_at, hatched_at) values
  ('6b000000-0000-0000-0000-000000000001', '6a000000-0000-0000-0000-000000000001',
   '6a000000-0000-0000-0000-000000000001', 'published', 'Road trip', null, null),
  ('6b000000-0000-0000-0000-000000000002', '6a000000-0000-0000-0000-000000000001',
   '6a000000-0000-0000-0000-000000000001', 'published', 'Old news', null, null),
  ('6b000000-0000-0000-0000-000000000003', '6a000000-0000-0000-0000-000000000001',
   '6a000000-0000-0000-0000-000000000001', 'published', 'Early', now() + interval '1 day', null),
  ('6b000000-0000-0000-0000-000000000004', '6a000000-0000-0000-0000-000000000001',
   '6a000000-0000-0000-0000-000000000001', 'published', 'Overdue', now() - interval '1 hour', null);

insert into public.snapshot_member (snapshot_id, account_id, role)
select s.id, m.account_id, m.role::public.snapshot_role
from (values
  ('6b000000-0000-0000-0000-000000000001'::uuid),
  ('6b000000-0000-0000-0000-000000000002'::uuid),
  ('6b000000-0000-0000-0000-000000000003'::uuid),
  ('6b000000-0000-0000-0000-000000000004'::uuid)
) as s (id)
cross join (values
  ('6a000000-0000-0000-0000-000000000002'::uuid, 'editor'),
  ('6a000000-0000-0000-0000-000000000003'::uuid, 'contributor'),
  ('6a000000-0000-0000-0000-000000000004'::uuid, 'contributor'),
  ('6a000000-0000-0000-0000-000000000005'::uuid, 'viewer')
) as m (account_id, role);

-- Amy's photos in "Old news", "Early" and "Overdue".
insert into public.media_item (
  snapshot_id, uploaded_by, contributor_person_id, kind, status, idempotency_key, mime_type, caption
)
select s.id, p.account_id, p.id, 'photo', 'ready', gen_random_uuid(), 'image/jpeg', s.caption
from public.person p
cross join (values
  ('6b000000-0000-0000-0000-000000000002'::uuid, 'Old photo'),
  ('6b000000-0000-0000-0000-000000000003'::uuid, 'Early photo'),
  ('6b000000-0000-0000-0000-000000000004'::uuid, 'Overdue photo')
) as s (id, caption)
where p.account_id = '6a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;

-- Starting a brood cell -----------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select throws_ok(
  $$update public.snapshot set hatch_at = now() + interval '2 days' where title = 'Road trip'$$,
  '42501', null,
  'an editor cannot start hatching'
);

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok(
  $$update public.snapshot set hatch_at = now() + interval '60 days' where title = 'Road trip'$$,
  '22023', null,
  'a memory hatches within 30 days'
);

select lives_ok(
  $$update public.snapshot set hatch_at = now() + interval '2 days' where title = 'Road trip'$$,
  'the owner starts it as brood'
);

select throws_ok(
  $$update public.snapshot set hatch_at = now() + interval '2 days' where title = 'Old news'$$,
  '22023', null,
  'but not once others have added things'
);

-- Before hatching -----------------------------------------------------------

reset role;
set local request.jwt.claims to '';
insert into public.media_item (
  snapshot_id, uploaded_by, contributor_person_id, kind, status, idempotency_key, mime_type, caption
)
select '6b000000-0000-0000-0000-000000000001', p.account_id, p.id, 'photo', 'ready',
  gen_random_uuid(), 'image/jpeg', 'Amy at the wheel'
from public.person p
where p.account_id = '6a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;
set local role authenticated;

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000004", "role": "authenticated"}';
insert into public.recollection (snapshot_id, body)
  values ('6b000000-0000-0000-0000-000000000001', 'Ben: we got lost twice.');

select is(
  (select count(*)::int from public.recollection where body like 'Ben:%'),
  1,
  'you see your own'
);

select is(
  (select count(*)::int from public.media_item where caption = 'Amy at the wheel'),
  0,
  'but nobody else''s'
);

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item where snapshot_id = '6b000000-0000-0000-0000-000000000001')
    + (select count(*)::int from public.recollection where snapshot_id = '6b000000-0000-0000-0000-000000000001'),
  0,
  'not even the owner'
);

select is(
  (select contributed from public.snapshot_honey(array['6b000000-0000-0000-0000-000000000001'::uuid])),
  2,
  'honey still shows how many have added something'
);

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok(
  $$update public.snapshot set hatch_at = null where title = 'Road trip'$$,
  '22023', null,
  'hatching cannot be turned off'
);

select throws_ok(
  $$update public.snapshot set sealed_at = now() where title = 'Road trip'$$,
  '22023', null,
  'a brood cell cannot be sealed'
);

select lives_ok(
  $$update public.snapshot set hatch_at = now() + interval '3 days' where title = 'Road trip'$$,
  'the owner can move the hatch time'
);

-- Hatching when everyone is in ----------------------------------------------

insert into public.recollection (snapshot_id, body)
  values ('6b000000-0000-0000-0000-000000000001', 'Owner: best playlist ever.');

select ok(
  (select hatched_at is null from public.snapshot where title = 'Road trip'),
  'still brood while someone has not added anything'
);

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000002", "role": "authenticated"}';
insert into public.recollection (snapshot_id, body)
  values ('6b000000-0000-0000-0000-000000000001', 'Editor: the motel had a pool.');

select ok(
  (select hatched_at is not null from public.snapshot where title = 'Road trip'),
  'once everyone has added something, it hatches'
);

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item where snapshot_id = '6b000000-0000-0000-0000-000000000001')
    + (select count(*)::int from public.recollection where snapshot_id = '6b000000-0000-0000-0000-000000000001'),
  4,
  'and everything appears at once'
);

select is(
  (select count(*)::int from public.buzz where kind = 'hatched'),
  1,
  'every member is told'
);

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok(
  $$update public.snapshot set hatched_at = null where title = 'Road trip'$$,
  '22023', null,
  'nothing un-hatches'
);

select throws_ok(
  $$update public.snapshot set hatch_at = now() + interval '1 day' where title = 'Road trip'$$,
  '22023', null,
  'and a hatched cell cannot go back to brood'
);

-- Hatching early ------------------------------------------------------------

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select throws_ok(
  $$update public.snapshot set hatched_at = now() where title = 'Early'$$,
  '42501', null,
  'only the owner hatches early'
);

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$update public.snapshot set hatched_at = '2000-01-01' where title = 'Early'$$,
  'the owner can hatch early'
);

select ok(
  (select hatched_at = now() from public.snapshot where title = 'Early'),
  'stamped with the real time'
);

-- Hatching on time ----------------------------------------------------------

set local request.jwt.claims to '{"sub": "6a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item where caption = 'Overdue photo'),
  1,
  'once the hatch time passes, it is open even before the job runs'
);

reset role;
set local request.jwt.claims to '';

select is(
  private.hatch_due_snapshots(),
  1,
  'the job stamps overdue cells'
);

select ok(
  exists (
    select 1 from public.buzz b
    join public.snapshot s on s.id = b.snapshot_id
    where s.title = 'Overdue' and b.kind = 'hatched'
  ),
  'and their members are told'
);

select * from finish();
rollback;
