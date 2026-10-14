-- Combs and connections: nested snapshots and links between them (BWX-21),
-- plus creating a sub-event from a parent (BWX-22).
--
-- Nesting (snapshot.parent_id) builds combs: University > Orientation >
-- Move-in day. Links (snapshot_link) connect cells that are not parent and
-- child: a sequel, a tradition's next year, the same trip.
--
-- Rules (docs/product.md, sections 5 and 7):
--
-- * No cycles, and at most six levels -- deep enough for a life chapter
--   down to an evening, shallow enough to stay navigable.
-- * To nest one snapshot under another you must be an owner or editor of
--   both. The child's own row-level security still decides who sees it:
--   access to a parent never implies access to a child, and a parent's
--   visibility never widens a child's.
-- * Deleting a parent moves its children up to the grandparent (or the top
--   level), never deletes them.
-- * A link is visible only to someone who can see both ends, so a link can
--   never reveal a snapshot you are not allowed to see. Suggested links
--   (BWX-52) are visible only to editors until confirmed.

-- Nesting -------------------------------------------------------------------

alter table public.snapshot
  add column parent_id uuid references public.snapshot (id) on delete set null;

create index snapshot_parent_id on public.snapshot (parent_id);

grant insert (parent_id), update (parent_id) on public.snapshot to authenticated;

-- How many levels deep a snapshot sits (a top-level snapshot is 1).
create function private.snapshot_depth(p_snapshot_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with recursive up as (
    select id, parent_id, 1 as depth from public.snapshot where id = p_snapshot_id
    union all
    select s.id, s.parent_id, up.depth + 1
    from public.snapshot s
    join up on s.id = up.parent_id
    where up.depth < 50
  )
  select max(depth) from up;
$$;

-- How many levels a snapshot and its descendants span (a leaf is 1).
create function private.snapshot_height(p_snapshot_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with recursive down as (
    select id, 1 as height from public.snapshot where id = p_snapshot_id
    union all
    select s.id, down.height + 1
    from public.snapshot s
    join down on s.parent_id = down.id
    where down.height < 50
  )
  select coalesce(max(height), 1) from down;
$$;

revoke execute on function private.snapshot_depth(uuid) from public;
revoke execute on function private.snapshot_height(uuid) from public;

-- Validates every change of parent: not itself, no cycle, no deeper than six
-- levels counting the whole subtree being moved, a live parent, and the
-- caller an owner or editor of the parent. (Their role on the child is
-- already checked by the insert and update policies.)
--
-- Reparenting takes a transaction-scoped advisory lock so two moves cannot
-- race each other into a cycle.
create function private.check_snapshot_nesting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Moving children up a level when their parent is deleted cannot create a
  -- cycle or deepen anything, and is not the caller's choice, so it skips
  -- every check.
  if new.parent_id is null
    or (tg_op = 'UPDATE' and new.parent_id is not distinct from old.parent_id)
    or coalesce(current_setting('beeswax.moving_children', true), '') = 'on'
  then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('beeswax.snapshot_tree'));

  if new.parent_id = new.id then
    raise exception 'A memory cannot contain itself' using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.snapshot where id = new.parent_id and deleted_at is null
  ) then
    raise exception 'That memory no longer exists' using errcode = '23503';
  end if;

  if (select auth.uid()) is not null
    and coalesce(private.snapshot_role(new.parent_id) >= 'editor', false) is false
  then
    raise exception 'You need to be an owner or editor of the memory you are nesting under'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and exists (
    with recursive up as (
      select id, parent_id from public.snapshot where id = new.parent_id
      union
      select s.id, s.parent_id from public.snapshot s join up on s.id = up.parent_id
    )
    select 1 from up where id = new.id
  ) then
    raise exception 'A memory cannot be nested inside its own sub-event'
      using errcode = '23514';
  end if;

  if private.snapshot_depth(new.parent_id)
      + (case when tg_op = 'UPDATE' then private.snapshot_height(new.id) else 1 end)
      > 6
  then
    raise exception 'Memories nest at most six levels deep' using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.check_snapshot_nesting() is
  'Trigger function: no self-nesting, no cycles, at most six levels, editor on the parent.';

create trigger check_snapshot_nesting
  before insert or update of parent_id on public.snapshot
  for each row execute function private.check_snapshot_nesting();

-- Before a snapshot is removed for good (a discarded draft, or the purge of
-- a soft-deleted one), its children move up a level.
create function private.move_children_up()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('beeswax.moving_children', 'on', true);
  update public.snapshot set parent_id = old.parent_id where parent_id = old.id;
  perform set_config('beeswax.moving_children', 'off', true);
  return old;
end;
$$;

comment on function private.move_children_up() is
  'Trigger function: re-parents a deleted snapshot''s children to its parent.';

create trigger move_children_up
  before delete on public.snapshot
  for each row execute function private.move_children_up();

create function private.audit_parent_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.snapshot_audit_log (snapshot_id, actor_id, action, details)
  values (new.id, (select auth.uid()), 'parent_changed',
    jsonb_build_object('from', old.parent_id, 'to', new.parent_id));
  return new;
end;
$$;

comment on function private.audit_parent_change() is
  'Trigger function: logs a snapshot moving to a different parent.';

create trigger audit_parent_change
  after update of parent_id on public.snapshot
  for each row when (old.parent_id is distinct from new.parent_id)
  execute function private.audit_parent_change();

-- Breadcrumbs ---------------------------------------------------------------

-- The chain above a snapshot, nearest first, for breadcrumbs and for zooming
-- out of a comb. Stops at the first ancestor the caller cannot see, so a
-- breadcrumb never reveals a parent you have no access to.
create function public.snapshot_ancestors(p_snapshot_id uuid)
returns table (id uuid, title text, level integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_id uuid;
  step integer := 0;
begin
  if not private.can_view_snapshot(p_snapshot_id) then
    return;
  end if;

  select s.parent_id into current_id from public.snapshot s where s.id = p_snapshot_id;

  while current_id is not null and step < 6 loop
    exit when not private.can_view_snapshot(current_id);
    step := step + 1;
    return query select s.id, s.title, step from public.snapshot s where s.id = current_id;
    select s.parent_id into current_id from public.snapshot s where s.id = current_id;
  end loop;
end;
$$;

comment on function public.snapshot_ancestors(uuid) is
  'Breadcrumbs above a snapshot, nearest first, stopping at the first one the caller cannot see.';

revoke execute on function public.snapshot_ancestors(uuid) from public, anon;
grant execute on function public.snapshot_ancestors(uuid) to authenticated;

-- Sub-events (BWX-22) -------------------------------------------------------

-- Start a sub-event under a parent, as a draft owned by the caller, with
-- the parent's details as editable defaults: dates, place, timezone,
-- visibility (and its audience, if custom) and participants.
--
-- Members are not copied: becoming a member always takes a yes. The app
-- offers to invite the parent's members after creating the child.
create function public.create_child_snapshot(p_parent_id uuid, p_title text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent public.snapshot;
  child_id uuid;
begin
  if coalesce(private.snapshot_role(p_parent_id) >= 'editor', false) is false then
    raise exception 'You need to be an owner or editor of the parent memory'
      using errcode = '42501';
  end if;

  select * into parent from public.snapshot where id = p_parent_id;

  insert into public.snapshot (
    owner_id, creator_id, parent_id, status, title,
    starts_at, ends_at, date_precision, timezone,
    place_name, latitude, longitude, visibility
  ) values (
    (select auth.uid()), (select auth.uid()), parent.id, 'draft', nullif(trim(p_title), ''),
    parent.starts_at, parent.ends_at, parent.date_precision, parent.timezone,
    parent.place_name, parent.latitude, parent.longitude, parent.visibility
  )
  returning id into child_id;

  insert into public.snapshot_participant (snapshot_id, person_id, added_by)
  select child_id, person_id, (select auth.uid())
  from public.snapshot_participant
  where snapshot_id = parent.id;

  if parent.visibility = 'custom' then
    insert into public.snapshot_audience (snapshot_id, account_id, added_by)
    select child_id, account_id, (select auth.uid())
    from public.snapshot_audience
    where snapshot_id = parent.id;
  end if;

  return child_id;
end;
$$;

comment on function public.create_child_snapshot(uuid, text) is
  'Start a draft sub-event with the parent''s dates, place, visibility and participants as defaults.';

revoke execute on function public.create_child_snapshot(uuid, text) from public, anon;
grant execute on function public.create_child_snapshot(uuid, text) to authenticated;

-- Links ---------------------------------------------------------------------

create type public.snapshot_link_kind as enum (
  'continues',   -- the next chapter: first year, then second year
  'milestone',   -- an earlier or later milestone on the same path
  'tradition',   -- the same tradition, another year (BWX-54)
  'same_trip',
  'same_people',
  'same_place',
  'related'
);

create type public.snapshot_link_status as enum ('confirmed', 'suggested', 'dismissed');

create table public.snapshot_link (
  id uuid primary key default gen_random_uuid(),
  -- Direction matters for 'continues' and 'milestone' (from comes first);
  -- the other kinds read both ways.
  from_snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  to_snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  kind public.snapshot_link_kind not null default 'related',
  -- Suggestions come from the suggested-links job (BWX-52) with status
  -- 'suggested' and no creator; an editor confirms or dismisses them.
  status public.snapshot_link_status not null default 'confirmed',
  created_by uuid default auth.uid() references public.account (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint not_self check (from_snapshot_id <> to_snapshot_id),
  unique (from_snapshot_id, to_snapshot_id, kind)
);

comment on table public.snapshot_link is
  'Connections between snapshots that are not parent and child. Visible only to people who can see both ends.';

create index snapshot_link_to on public.snapshot_link (to_snapshot_id);
create index snapshot_link_created_by on public.snapshot_link (created_by);

create trigger set_updated_at before update on public.snapshot_link
  for each row execute function private.set_updated_at();

alter table public.snapshot_link enable row level security;

create policy "Users can read links between snapshots they can see"
  on public.snapshot_link for select to authenticated
  using (
    private.can_view_snapshot(from_snapshot_id)
    and private.can_view_snapshot(to_snapshot_id)
    and (status = 'confirmed' or private.snapshot_role(from_snapshot_id) >= 'editor')
  );

-- Link from a snapshot you edit to any snapshot you can see.
create policy "Editors can link to snapshots they can see"
  on public.snapshot_link for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and status = 'confirmed'
    and private.snapshot_role(from_snapshot_id) >= 'editor'
    and private.can_view_snapshot(to_snapshot_id)
  );

create policy "Editors can confirm or dismiss suggested links"
  on public.snapshot_link for update to authenticated
  using (private.snapshot_role(from_snapshot_id) >= 'editor')
  with check (private.snapshot_role(from_snapshot_id) >= 'editor');

create policy "Editors or the link's creator can remove it"
  on public.snapshot_link for delete to authenticated
  using (
    created_by = (select auth.uid())
    or private.snapshot_role(from_snapshot_id) >= 'editor'
  );

revoke insert, update on public.snapshot_link from anon, authenticated;
grant insert (from_snapshot_id, to_snapshot_id, kind) on public.snapshot_link to authenticated;
grant update (status) on public.snapshot_link to authenticated;
