-- Tests for BWX-21 and BWX-22: nesting, depth and cycle rules, breadcrumbs,
-- sub-events, and links between snapshots. Run with `supabase test db`.
--
-- Cast: owner builds "University" > "Orientation" > "Move-in day" > ...;
-- editor and member belong to University only; outsider to nothing.

begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

insert into auth.users (id, email, raw_user_meta_data) values
  ('0e000000-0000-0000-0000-000000000001', 'n_owner@example.com', '{"username": "n_owner"}'),
  ('0e000000-0000-0000-0000-000000000002', 'n_editor@example.com', '{"username": "n_editor"}'),
  ('0e000000-0000-0000-0000-000000000003', 'n_member@example.com', '{"username": "n_member"}'),
  ('0e000000-0000-0000-0000-000000000004', 'n_outsider@example.com', '{"username": "n_outsider"}');

-- Building a comb -----------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$insert into public.snapshot (status, title, place_name)
    values ('published', 'University', 'Waterloo')$$,
  'the owner creates a top-level snapshot'
);

select lives_ok(
  $$insert into public.snapshot (status, title, parent_id)
    select 'published', 'Orientation', id from public.snapshot where title = 'University'$$,
  'and nests a sub-event under it'
);

select lives_ok(
  $$insert into public.snapshot (status, title, parent_id)
    select 'published', 'Move-in day', id from public.snapshot where title = 'Orientation'$$,
  'and another level below that'
);

select ok(
  set_config('test.orientation',
    (select id::text from public.snapshot where title = 'Orientation'), true) is not null,
  'remember Orientation''s id for people who cannot look it up'
);

insert into public.snapshot (status, title, parent_id)
  select 'published', 'Level 4', id from public.snapshot where title = 'Move-in day';
insert into public.snapshot (status, title, parent_id)
  select 'published', 'Level 5', id from public.snapshot where title = 'Level 4';
insert into public.snapshot (status, title, parent_id)
  select 'published', 'Level 6', id from public.snapshot where title = 'Level 5';

select throws_ok(
  $$insert into public.snapshot (status, title, parent_id)
    select 'published', 'Level 7', id from public.snapshot where title = 'Level 6'$$,
  '23514', null,
  'nesting stops at six levels'
);

select throws_ok(
  $$update public.snapshot
    set parent_id = (select id from public.snapshot where title = 'Move-in day')
    where title = 'University'$$,
  '23514', null,
  'a snapshot cannot move inside its own sub-event'
);

select throws_ok(
  $$update public.snapshot set parent_id = id where title = 'Orientation'$$,
  '23514', null,
  'a snapshot cannot contain itself'
);

insert into public.snapshot (status, title) values ('published', 'Second root');
insert into public.snapshot (status, title, parent_id)
  select 'published', 'Second child', id from public.snapshot where title = 'Second root';

select throws_ok(
  $$update public.snapshot
    set parent_id = (select id from public.snapshot where title = 'Second child')
    where title = 'Orientation'$$,
  '23514', null,
  'moving a subtree is refused if its deepest cell would pass six levels'
);

select is(
  (select string_agg(title, ' < ' order by level)
    from public.snapshot_ancestors((select id from public.snapshot where title = 'Move-in day'))),
  'Orientation < University',
  'breadcrumbs list the ancestors, nearest first'
);

-- Members of the parent only --------------------------------------------------

reset role;
insert into public.snapshot_member (snapshot_id, account_id, role)
  select id, '0e000000-0000-0000-0000-000000000002', 'editor' from public.snapshot
  where title = 'University';
insert into public.snapshot_member (snapshot_id, account_id, role)
  select id, '0e000000-0000-0000-0000-000000000003', 'contributor' from public.snapshot
  where title = 'University';
insert into public.person (id, created_by, display_name)
  values ('0f000000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000001', 'Grandma Noor');
insert into public.snapshot_participant (snapshot_id, person_id)
  select id, '0f000000-0000-0000-0000-000000000001' from public.snapshot where title = 'University';
set local role authenticated;

-- Sub-events ------------------------------------------------------------------

select ok(
  set_config('test.child', public.create_child_snapshot(
    (select id from public.snapshot where title = 'University'), 'Frosh week')::text, true)
    is not null,
  'the owner can start a sub-event from a parent'
);

select is(
  (select s.place_name || ' / ' || s.status || ' / '
      || (select count(*) from public.snapshot_participant p where p.snapshot_id = s.id)
    from public.snapshot s where s.id = current_setting('test.child')::uuid),
  'Waterloo / draft / 1',
  'it starts as a draft with the parent''s place and participants'
);

-- As the editor of University -------------------------------------------------

set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$insert into public.snapshot (status, title, parent_id)
    select 'published', 'Editor''s trip', id from public.snapshot where title = 'University'$$,
  'an editor of the parent can nest their own snapshot under it'
);

select throws_ok(
  format($$insert into public.snapshot (status, title, parent_id)
    values ('published', 'Sneaky', %L)$$, current_setting('test.orientation')),
  '42501', null,
  'but not under a sub-event they are not an editor of'
);

-- As a contributor of University ------------------------------------------

set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot where title = 'University'),
  1,
  'a member of the parent sees the parent'
);

select is(
  (select count(*)::int from public.snapshot where title = 'Orientation'),
  0,
  'but not its children: access never flows down'
);

select throws_ok(
  $$insert into public.snapshot (status, title, parent_id)
    select 'published', 'Mine', id from public.snapshot where title = 'University'$$,
  '42501', null,
  'a contributor cannot nest under the parent'
);

-- As the outsider -----------------------------------------------------------

set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select throws_ok(
  format('select public.create_child_snapshot(%L)', current_setting('test.orientation')),
  '42501', null,
  'an outsider cannot start a sub-event'
);

insert into public.snapshot (status, title) values ('published', 'Outsider thing');

-- Links ---------------------------------------------------------------------

set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000001", "role": "authenticated"}';
insert into public.snapshot (status, title) values ('published', 'Second year');

select lives_ok(
  $$insert into public.snapshot_link (from_snapshot_id, to_snapshot_id, kind)
    select a.id, b.id, 'continues' from public.snapshot a, public.snapshot b
    where a.title = 'Orientation' and b.title = 'Second year'$$,
  'the owner can link one memory to the next'
);

select throws_ok(
  $$insert into public.snapshot_link (from_snapshot_id, to_snapshot_id, kind)
    select a.id, b.id, 'continues' from public.snapshot a, public.snapshot b
    where a.title = 'Orientation' and b.title = 'Second year'$$,
  '23505', null,
  'the same link cannot be made twice'
);

select throws_ok(
  $$insert into public.snapshot_link (from_snapshot_id, to_snapshot_id)
    select id, id from public.snapshot where title = 'Orientation'$$,
  '23514', null,
  'a snapshot cannot link to itself'
);

select lives_ok(
  $$insert into public.snapshot_link (from_snapshot_id, to_snapshot_id)
    select a.id, b.id from public.snapshot a, public.snapshot b
    where a.title = 'University' and b.title = 'Level 4'$$,
  'the owner can link University to a cell deep in its comb'
);

set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot_link),
  0,
  'a link is hidden from anyone who cannot see both ends'
);

set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select lives_ok(
  $$insert into public.snapshot_link (from_snapshot_id, to_snapshot_id, kind)
    select a.id, b.id, 'same_trip' from public.snapshot a, public.snapshot b
    where a.title = 'Editor''s trip' and b.title = 'University'$$,
  'an editor can link their snapshot to one they can see'
);

set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000004", "role": "authenticated"}';

select throws_ok(
  format($$insert into public.snapshot_link (from_snapshot_id, to_snapshot_id)
    values ((select id from public.snapshot where title = 'Outsider thing'), %L)$$,
    current_setting('test.orientation')),
  '42501', null,
  'nobody can link to a snapshot they cannot see'
);

-- Suggested links -----------------------------------------------------------

reset role;
insert into public.snapshot_link (from_snapshot_id, to_snapshot_id, kind, status, created_by)
  select a.id, b.id, 'related', 'suggested', null from public.snapshot a, public.snapshot b
  where a.title = 'Orientation' and b.title = 'Second root';
set local role authenticated;
set local request.jwt.claims to '{"sub": "0e000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.snapshot_link where status = 'suggested'),
  1,
  'an editor sees suggested links'
);

select lives_ok(
  $$update public.snapshot_link set status = 'dismissed' where status = 'suggested'$$,
  'and can dismiss them'
);

-- Deleting a parent -----------------------------------------------------------

insert into public.snapshot (title) values ('Draft parent');
insert into public.snapshot (title, parent_id)
  select 'Draft child', id from public.snapshot where title = 'Draft parent';
delete from public.snapshot where title = 'Draft parent';

select ok(
  (select parent_id is null from public.snapshot where title = 'Draft child'),
  'deleting a parent moves its children up instead of deleting them'
);

select is(
  (select count(*)::int from public.snapshot_audit_log a
    join public.snapshot s on s.id = a.snapshot_id
    where s.title = 'Draft child' and a.action = 'parent_changed'),
  1,
  'the move is audited'
);

select * from finish();
rollback;
