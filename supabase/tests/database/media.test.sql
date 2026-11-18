-- Tests for BWX-29 and BWX-90: media items, storage access, moderation,
-- per-item audience, location privacy, covers and caps.
-- Run with `supabase test db`.
--
-- Cast: owner, editor, contrib and viewer are members of "Beach day";
-- stranger only ever sees it through its public link.

begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

insert into auth.users (id, email, raw_user_meta_data) values
  ('1a000000-0000-0000-0000-000000000001', 'm_owner@example.com', '{"username": "m_owner"}'),
  ('1a000000-0000-0000-0000-000000000002', 'm_editor@example.com', '{"username": "m_editor"}'),
  ('1a000000-0000-0000-0000-000000000003', 'm_contrib@example.com', '{"username": "m_contrib"}'),
  ('1a000000-0000-0000-0000-000000000004', 'm_viewer@example.com', '{"username": "m_viewer"}'),
  ('1a000000-0000-0000-0000-000000000005', 'm_stranger@example.com', '{"username": "m_stranger"}');

insert into public.snapshot (id, owner_id, creator_id, status, title) values
  ('1b000000-0000-0000-0000-000000000001', '1a000000-0000-0000-0000-000000000001',
   '1a000000-0000-0000-0000-000000000001', 'published', 'Beach day');

insert into public.snapshot_member (snapshot_id, account_id, role) values
  ('1b000000-0000-0000-0000-000000000001', '1a000000-0000-0000-0000-000000000002', 'editor'),
  ('1b000000-0000-0000-0000-000000000001', '1a000000-0000-0000-0000-000000000003', 'contributor'),
  ('1b000000-0000-0000-0000-000000000001', '1a000000-0000-0000-0000-000000000004', 'viewer');

-- Uploading, as the contributor ---------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select lives_ok(
  $$insert into public.media_item (snapshot_id, kind, idempotency_key, mime_type, caption)
    values ('1b000000-0000-0000-0000-000000000001', 'photo',
      '1c000000-0000-0000-0000-000000000001', 'image/jpeg', 'Sunset')$$,
  'a contributor can start an upload'
);

select is(
  (select p.display_name from public.media_item m
    join public.person p on p.id = m.contributor_person_id
    where m.caption = 'Sunset'),
  'm_contrib',
  'the item is attributed to the uploader''s own person'
);

select throws_ok(
  $$insert into public.media_item (snapshot_id, kind, idempotency_key, mime_type)
    values ('1b000000-0000-0000-0000-000000000001', 'photo',
      '1c000000-0000-0000-0000-000000000001', 'image/jpeg')$$,
  '23505', null,
  'a retried upload with the same key does not duplicate'
);

select throws_ok(
  $$insert into public.media_item (snapshot_id, kind, idempotency_key, mime_type)
    values ('1b000000-0000-0000-0000-000000000001', 'photo',
      '1c000000-0000-0000-0000-000000000009', 'video/mp4')$$,
  '23514', null,
  'the file type must match the kind'
);

select ok(
  set_config('test.media', (select id::text from public.media_item where caption = 'Sunset'), true)
    is not null,
  'remember the item id'
);

select lives_ok(
  format($$insert into storage.objects (bucket_id, name)
    values ('media', '1b000000-0000-0000-0000-000000000001/%s/original.jpg')$$,
    current_setting('test.media')),
  'the uploader can store the original at its path'
);

select throws_ok(
  format($$insert into storage.objects (bucket_id, name)
    values ('media', '1b000000-0000-0000-0000-000000000001/%s/thumb.webp')$$,
    current_setting('test.media')),
  '42501', null,
  'but nothing else under it -- thumbnails are the job''s'
);

select lives_ok(
  format('select public.finish_media_upload(%L)', current_setting('test.media')),
  'the uploader finishes the upload'
);

select is(
  (select status::text from public.media_item where caption = 'Sunset'),
  'ready',
  'the item is ready'
);

insert into public.media_location (media_id, latitude, longitude)
  values (current_setting('test.media')::uuid, 43.47, -80.54);

-- As a viewer ---------------------------------------------------------------

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select throws_ok(
  $$insert into public.media_item (snapshot_id, kind, idempotency_key, mime_type)
    values ('1b000000-0000-0000-0000-000000000001', 'photo',
      '1c000000-0000-0000-0000-000000000002', 'image/jpeg')$$,
  '42501', null,
  'a viewer cannot add media'
);

select is(
  (select count(*)::int from public.media_item),
  1,
  'a viewer sees ready media'
);

update public.media_item set caption = 'Not mine' where caption = 'Sunset';
select is(
  (select count(*)::int from public.media_item where caption = 'Sunset'),
  1,
  'a viewer cannot re-caption someone''s item'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok(
  $$update public.media_item set caption = 'Owner edit' where caption = 'Sunset'$$,
  '42501', null,
  'owning the snapshot does not mean owning its media'
);

-- Moderation, as the editor -------------------------------------------------

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$update public.media_item set hidden_at = now() where caption = 'Sunset'$$,
  'an editor can hide an item'
);

select is(
  (select hidden_by from public.media_item where caption = 'Sunset'),
  '1a000000-0000-0000-0000-000000000002'::uuid,
  'and is recorded as the one who hid it'
);

select throws_ok(
  $$update public.media_item set deleted_at = now() where caption = 'Sunset'$$,
  '42501', null,
  'but cannot delete someone else''s item'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item),
  0,
  'a hidden item disappears for viewers'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item),
  1,
  'its contributor still sees it'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000002", "role": "authenticated"}';
update public.media_item set hidden_at = null where caption = 'Sunset';

-- Going public --------------------------------------------------------------

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$update public.snapshot set visibility = 'public' where title = 'Beach day'$$,
  'the owner makes the snapshot public'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'Beach day'),
  1,
  'a stranger with the link sees the snapshot'
);

select is(
  (select count(*)::int from public.media_item),
  0,
  'but none of the media, until each contributor allows it'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select lives_ok(
  $$update public.media_item set audience = 'public_ok' where caption = 'Sunset'$$,
  'the contributor allows their item to be public'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000005", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item),
  1,
  'now the stranger sees that item'
);

select is(
  (select count(*)::int from public.media_location),
  0,
  'but never where it was taken'
);

select is(
  (select count(*)::int from storage.objects where bucket_id = 'media'),
  1,
  'and can read its file'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_location),
  1,
  'members can see where it was taken'
);

-- Cover ---------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  format($$update public.snapshot set cover_media_id = %L where title = 'Beach day'$$,
    current_setting('test.media')),
  'the owner can make a public item the cover'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000003", "role": "authenticated"}';
update public.media_item set audience = 'members' where caption = 'Sunset';

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select ok(
  (select cover_media_id is null from public.snapshot where title = 'Beach day'),
  'when the contributor takes it back to members-only, it stops being the public cover'
);

-- Pending items, caps and deletion ------------------------------------------

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000003", "role": "authenticated"}';
insert into public.media_item (snapshot_id, kind, idempotency_key, mime_type)
  values ('1b000000-0000-0000-0000-000000000001', 'audio',
    '1c000000-0000-0000-0000-000000000003', 'audio/m4a');

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item),
  1,
  'pending uploads are invisible to others'
);

reset role;
update public.snapshot set contribution_cap = 2 where title = 'Beach day';
set local role authenticated;
set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select throws_ok(
  $$insert into public.media_item (snapshot_id, kind, idempotency_key, mime_type)
    values ('1b000000-0000-0000-0000-000000000001', 'photo',
      '1c000000-0000-0000-0000-000000000004', 'image/png')$$,
  '23514', null,
  'an owner-set cap, when there is one, holds'
);

select lives_ok(
  $$update public.media_item set deleted_at = now() where caption = 'Sunset'$$,
  'a contributor can delete their own item'
);

set local request.jwt.claims to '{"sub": "1a000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select is(
  (select count(*)::int from public.media_item),
  0,
  'a deleted item is gone for everyone else'
);

reset role;
set local role anon;

select is(
  (select count(*)::int from public.media_item),
  0,
  'anonymous requests see no media'
);

select * from finish();
rollback;
