-- Tests for BWX-38 (prompts) and BWX-60 (sealing and reflections).
-- Run with `supabase test db`.
--
-- Cast: in "Graduation", owner seals, editor arranges, contrib has a photo,
-- a story and is a participant, viewer only reads.

begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

insert into auth.users (id, email, raw_user_meta_data) values
  ('5a000000-0000-0000-0000-000000000001', 's_owner@example.com', '{"username": "s_owner"}'),
  ('5a000000-0000-0000-0000-000000000002', 's_editor@example.com', '{"username": "s_editor"}'),
  ('5a000000-0000-0000-0000-000000000003', 's_contrib@example.com', '{"username": "s_contrib"}'),
  ('5a000000-0000-0000-0000-000000000004', 's_viewer@example.com', '{"username": "s_viewer"}');

insert into public.snapshot (id, owner_id, creator_id, status, title) values
  ('5b000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000001',
   '5a000000-0000-0000-0000-000000000001', 'published', 'Graduation'),
  ('5b000000-0000-0000-0000-000000000002', '5a000000-0000-0000-0000-000000000001',
   '5a000000-0000-0000-0000-000000000001', 'draft', 'Unfinished');

insert into public.snapshot_member (snapshot_id, account_id, role) values
  ('5b000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000002', 'editor'),
  ('5b000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000003', 'contributor'),
  ('5b000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000004', 'viewer');

insert into public.snapshot_moment (id, snapshot_id, title, position) values
  ('5e000000-0000-0000-0000-000000000001', '5b000000-0000-0000-0000-000000000001', 'Ceremony', 1);

insert into public.snapshot_participant (snapshot_id, person_id)
select '5b000000-0000-0000-0000-000000000001', p.id
from public.person p
where p.account_id = '5a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;

insert into public.media_item (
  snapshot_id, uploaded_by, contributor_person_id, kind, status, idempotency_key, mime_type, caption
)
select '5b000000-0000-0000-0000-000000000001', p.account_id, p.id, 'photo', 'ready',
  gen_random_uuid(), 'image/jpeg', 'Cap toss'
from public.person p
where p.account_id = '5a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;

insert into public.recollection (snapshot_id, author_person_id, written_by, kind, body)
select '5b000000-0000-0000-0000-000000000001', p.id, p.account_id, 'story', 'The speech ran long.'
from public.person p
where p.account_id = '5a000000-0000-0000-0000-000000000003' and p.created_by = p.account_id;

-- Prompts -------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "5a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.prompt where use = 'recollection'),
  8,
  'the starter questions are there'
);

select is(
  (select count(*)::int from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')),
  3,
  'a contributor is offered three'
);

select is(
  (select count(*)::int from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')
    where use = 'recollection'),
  3,
  'about what happened, while the memory is fresh'
);

select is(
  array(select id from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')),
  array(select id from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')),
  'the same ones each time, not reshuffled'
);

select ok(
  set_config('test.first',
    (select id from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001') limit 1), true)
    is not null,
  'remember the first prompt'
);

insert into public.prompt_dismissal (snapshot_id, prompt_id)
  values ('5b000000-0000-0000-0000-000000000001', current_setting('test.first'));

select ok(
  current_setting('test.first') not in (
    select id from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')),
  'a dismissed prompt is never asked again'
);

select is(
  (select count(*)::int from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')),
  3,
  'another takes its place'
);

select ok(
  set_config('test.answered',
    (select id from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001') limit 1), true)
    is not null,
  'remember the next prompt'
);

insert into public.recollection (snapshot_id, body, prompt_id)
  values ('5b000000-0000-0000-0000-000000000001', 'Everyone cried.', current_setting('test.answered'));

select ok(
  current_setting('test.answered') not in (
    select id from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')),
  'nor one already answered'
);

set local request.jwt.claims to '{"sub": "5a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')),
  0,
  'viewers are not asked'
);

set local request.jwt.claims to '{"sub": "5a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  (select count(*)::int from public.prompt_dismissal),
  0,
  'dismissals are private'
);

select throws_ok(
  $$insert into public.prompt (id, use, body) values ('mine', 'recollection', 'Why?')$$,
  '42501', null,
  'clients cannot write prompts'
);

-- Sealing -------------------------------------------------------------------

select throws_ok(
  $$update public.snapshot set sealed_at = now() where title = 'Graduation'$$,
  '42501', null,
  'an editor cannot seal'
);

set local request.jwt.claims to '{"sub": "5a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$update public.snapshot set sealed_at = '2000-01-01' where title = 'Graduation'$$,
  'the owner seals the memory'
);

select ok(
  (select sealed_at = now() and sealed_by = '5a000000-0000-0000-0000-000000000001'
    from public.snapshot where title = 'Graduation'),
  'stamped with when and by whom'
);

select ok(
  exists (select 1 from public.snapshot_audit_log where action = 'sealed'),
  'and audited'
);

select throws_ok(
  $$update public.snapshot set title = 'Grad' where title = 'Graduation'$$,
  '55000', null,
  'its details are frozen'
);

select lives_ok(
  $$update public.snapshot set visibility = 'public' where title = 'Graduation'$$,
  'but the owner still controls who sees it'
);

-- Inside a sealed memory, as the contributor ---------------------------------

set local request.jwt.claims to '{"sub": "5a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select throws_ok(
  $$insert into public.media_item (snapshot_id, kind, idempotency_key, mime_type)
    values ('5b000000-0000-0000-0000-000000000001', 'photo', gen_random_uuid(), 'image/jpeg')$$,
  '55000', null,
  'no new photos'
);

select throws_ok(
  $$update public.media_item set caption = 'Hats off' where caption = 'Cap toss'$$,
  '55000', null,
  'existing ones stay as they were'
);

select lives_ok(
  $$update public.media_item set audience = 'public_ok' where caption = 'Cap toss'$$,
  'a contributor still decides who sees theirs'
);

select throws_ok(
  $$insert into public.recollection (snapshot_id, body)
    values ('5b000000-0000-0000-0000-000000000001', 'One more thing')$$,
  '55000', null,
  'no new stories'
);

select throws_ok(
  $$update public.recollection set body = 'The speech was short.'
    where body = 'The speech ran long.'$$,
  '55000', null,
  'stories stay as written'
);

select lives_ok(
  $$insert into public.recollection (snapshot_id, kind, body)
    values ('5b000000-0000-0000-0000-000000000001', 'reflection',
      'Five years on, I barely remember the speech, only who was there.')$$,
  'but reflections can still be added'
);

select throws_ok(
  $$insert into public.recollection (snapshot_id, kind, body, moment_id)
    values ('5b000000-0000-0000-0000-000000000001', 'reflection', 'About the ceremony',
      '5e000000-0000-0000-0000-000000000001')$$,
  '23514', null,
  'a reflection is about the whole memory, not one moment'
);

delete from public.snapshot_participant
  where snapshot_id = '5b000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.snapshot_participant
    where snapshot_id = '5b000000-0000-0000-0000-000000000001'),
  0,
  'people can still take themselves out'
);

select lives_ok(
  $$update public.media_item set deleted_at = now() where caption = 'Cap toss'$$,
  'and delete their own things'
);

select is(
  (select count(*)::int from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')
    where use = 'reflection'),
  3,
  'a sealed memory asks for reflections'
);

set local request.jwt.claims to '{"sub": "5a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select throws_ok(
  $$insert into public.snapshot_moment (snapshot_id, title, position)
    values ('5b000000-0000-0000-0000-000000000001', 'After party', 2)$$,
  '55000', null,
  'moments are frozen'
);

-- As the owner --------------------------------------------------------------

set local request.jwt.claims to '{"sub": "5a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select (details ->> 'reflection')::int from public.buzz
    where kind = 'new_contributions' and read_at is null),
  1,
  'a reflection buzzes as a reflection'
);

select lives_ok(
  $$update public.snapshot set sealed_at = null where title = 'Graduation'$$,
  'the owner can unseal'
);

select lives_ok(
  $$update public.snapshot set title = 'Graduation day' where title = 'Graduation'$$,
  'and edit it again'
);

select throws_ok(
  $$update public.snapshot set sealed_at = now() where title = 'Unfinished'$$,
  '22023', null,
  'a draft cannot be sealed'
);

reset role;
set local role anon;

select throws_ok(
  $$select * from public.snapshot_prompts('5b000000-0000-0000-0000-000000000001')$$,
  '42501', null,
  'anonymous requests get no prompts'
);

select * from finish();
rollback;
