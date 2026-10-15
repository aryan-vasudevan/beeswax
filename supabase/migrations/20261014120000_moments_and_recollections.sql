-- Moments and recollections: reconstructing the event inside a cell
-- (BWX-95, BWX-100).
--
--   snapshot_moment   a stretch of the event -- Arrival, Dinner, The drive
--                     home -- in time order. The comb inside a cell.
--   recollection      something someone remembers in words: a story, a
--                     quote, an inside joke, or what nobody photographed.
--
-- Contributions (media items and recollections) can sit in a moment. Rules
-- (docs/product.md, sections 5 and 6):
--
-- * Owners and editors arrange moments. The suggestion job (BWX-96) adds
--   moments as 'suggested', seen only by editors until confirmed; nothing
--   inferred ever looks verified.
-- * Contributors place their own items in moments; editors can place
--   anyone's. Placing is arranging -- it never changes who owns an item.
-- * A recollection is one person's account and says so. It belongs to its
--   author exactly as a media item belongs to its uploader: own audience,
--   only the author edits or deletes, editors may hide. Conflicting
--   recollections of the same moment simply coexist.

-- Shared rule for contributions --------------------------------------------

-- Whether the caller may see a contribution, from the row's own values (so
-- the policy needs no second lookup): they can see the snapshot; it is
-- theirs, or it is ready, not deleted, not hidden (unless they moderate),
-- and either they are an insider or the item is public_ok.
create function private.can_view_contribution(
  p_snapshot_id uuid,
  p_author_account uuid,
  p_ready boolean,
  p_deleted_at timestamptz,
  p_hidden_at timestamptz,
  p_audience public.media_audience
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_view_snapshot(p_snapshot_id)
    and (
      p_author_account = (select auth.uid())
      or (
        p_ready
        and p_deleted_at is null
        and (p_hidden_at is null or private.snapshot_role(p_snapshot_id) >= 'editor')
        and (p_audience = 'public_ok' or private.is_snapshot_insider(p_snapshot_id))
      )
    );
$$;

revoke execute on function private.can_view_contribution(uuid, uuid, boolean, timestamptz, timestamptz, public.media_audience) from public;
grant execute on function private.can_view_contribution(uuid, uuid, boolean, timestamptz, timestamptz, public.media_audience) to authenticated;

-- snapshot_moment -----------------------------------------------------------

create type public.moment_status as enum ('confirmed', 'suggested', 'dismissed');

create table public.snapshot_moment (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  title text constraint title_length check (char_length(title) <= 120),
  -- Either end may be unknown: "after dinner" has no clock time.
  starts_at timestamptz,
  ends_at timestamptz,
  -- Order within the cell. Clients drag to reorder by writing a value
  -- between two neighbours, so a move touches one row.
  position double precision not null,
  status public.moment_status not null default 'confirmed',
  created_by uuid default auth.uid() references public.account (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ends_after_start check (ends_at >= starts_at)
);

comment on table public.snapshot_moment is
  'Stretches of an event, in order: the comb inside a cell. Suggested ones are unconfirmed.';

create index snapshot_moment_snapshot on public.snapshot_moment (snapshot_id, position);
create index snapshot_moment_created_by on public.snapshot_moment (created_by);

create trigger set_updated_at before update on public.snapshot_moment
  for each row execute function private.set_updated_at();

alter table public.snapshot_moment enable row level security;

create policy "Users can read confirmed moments of snapshots they can see"
  on public.snapshot_moment for select to authenticated
  using (
    private.can_view_snapshot(snapshot_id)
    and (status = 'confirmed' or private.snapshot_role(snapshot_id) >= 'editor')
  );

create policy "Owners and editors can add moments"
  on public.snapshot_moment for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and status = 'confirmed'
    and private.snapshot_role(snapshot_id) >= 'editor'
  );

create policy "Owners and editors can arrange moments"
  on public.snapshot_moment for update to authenticated
  using (private.snapshot_role(snapshot_id) >= 'editor')
  with check (private.snapshot_role(snapshot_id) >= 'editor');

-- Removing a moment leaves its contributions in the cell, unplaced.
create policy "Owners and editors can remove moments"
  on public.snapshot_moment for delete to authenticated
  using (private.snapshot_role(snapshot_id) >= 'editor');

revoke insert, update on public.snapshot_moment from anon, authenticated;
grant insert (snapshot_id, title, starts_at, ends_at, position) on public.snapshot_moment to authenticated;
grant update (title, starts_at, ends_at, position, status) on public.snapshot_moment to authenticated;

-- Placing media in moments --------------------------------------------------

alter table public.media_item
  add column moment_id uuid references public.snapshot_moment (id) on delete set null;

create index media_item_moment_id on public.media_item (moment_id);

grant update (moment_id) on public.media_item to authenticated;

-- recollection --------------------------------------------------------------

create type public.recollection_kind as enum (
  'story',          -- what happened
  'quote',          -- something someone said
  'inside_joke',
  'unphotographed'  -- what nobody captured
);

create table public.recollection (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  moment_id uuid references public.snapshot_moment (id) on delete set null,
  -- Whose account of events this is.
  author_person_id uuid not null references public.person (id),
  written_by uuid default auth.uid() references public.account (id) on delete set null,
  kind public.recollection_kind not null default 'story',
  body text not null constraint body_length check (char_length(body) between 1 and 10000),
  audience public.media_audience not null default 'members',
  hidden_at timestamptz,
  hidden_by uuid references public.account (id) on delete set null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.recollection is
  'Stories, quotes, inside jokes and what nobody photographed. Each is one person''s account.';

create index recollection_snapshot on public.recollection (snapshot_id, created_at);
create index recollection_moment_id on public.recollection (moment_id);
create index recollection_author on public.recollection (author_person_id);
create index recollection_written_by on public.recollection (written_by);
create index recollection_hidden_by on public.recollection (hidden_by);

create trigger set_updated_at before update on public.recollection
  for each row execute function private.set_updated_at();

alter table public.recollection enable row level security;

create policy "Users can read recollections they may see"
  on public.recollection for select to authenticated
  using (private.can_view_contribution(
    snapshot_id, written_by, true, deleted_at, hidden_at, audience));

create policy "Contributors can write recollections"
  on public.recollection for insert to authenticated
  with check (
    written_by = (select auth.uid())
    and private.snapshot_role(snapshot_id) >= 'contributor'
  );

create policy "Authors and moderators can update recollections"
  on public.recollection for update to authenticated
  using (
    written_by = (select auth.uid())
    or private.snapshot_role(snapshot_id) >= 'editor'
  )
  with check (
    written_by = (select auth.uid())
    or private.snapshot_role(snapshot_id) >= 'editor'
  );

revoke insert, update, delete on public.recollection from anon, authenticated;
grant insert (snapshot_id, moment_id, kind, body, audience) on public.recollection to authenticated;
grant update (moment_id, kind, body, audience, hidden_at, deleted_at) on public.recollection to authenticated;

-- Triggers ------------------------------------------------------------------

-- A recollection is by the writer's own person.
create function private.prepare_recollection()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.written_by is not null then
    select id into new.author_person_id
    from public.person
    where account_id = new.written_by and created_by = new.written_by;
  end if;
  return new;
end;
$$;

comment on function private.prepare_recollection() is
  'Trigger function: attributes a recollection to its writer''s own person.';

create trigger prepare_recollection
  before insert on public.recollection
  for each row execute function private.prepare_recollection();

-- Who may change what on a recollection, mirroring media: the author owns
-- the words, kind, audience and deletion; moderators only hide.
create function private.check_recollection_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    return new;
  end if;

  if new.written_by is distinct from me and (
    new.body is distinct from old.body
    or new.kind is distinct from old.kind
    or new.audience is distinct from old.audience
    or new.deleted_at is distinct from old.deleted_at
  ) then
    raise exception 'Only the person who wrote this can change it' using errcode = '42501';
  end if;

  if new.hidden_at is distinct from old.hidden_at then
    if coalesce(private.snapshot_role(new.snapshot_id) >= 'editor', false) is false then
      raise exception 'Only owners and editors can hide recollections' using errcode = '42501';
    end if;
    new.hidden_by = case when new.hidden_at is null then null else me end;
  end if;

  return new;
end;
$$;

comment on function private.check_recollection_change() is
  'Trigger function: author-only fields stay with the author; hiding stays with moderators.';

create trigger check_recollection_change
  before update on public.recollection
  for each row execute function private.check_recollection_change();

-- Placing a contribution in a moment: the moment must belong to the same
-- snapshot, and only the contribution's author or a moderator may move it.
-- Shared by media_item and recollection.
create function private.check_moment_placement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  author uuid;
begin
  if new.moment_id is not distinct from (case when tg_op = 'UPDATE' then old.moment_id end) then
    return new;
  end if;

  if new.moment_id is not null and not exists (
    select 1 from public.snapshot_moment
    where id = new.moment_id and snapshot_id = new.snapshot_id
  ) then
    raise exception 'That moment belongs to a different memory' using errcode = '23514';
  end if;

  author := case tg_table_name
    when 'media_item' then (to_jsonb(new) ->> 'uploaded_by')::uuid
    else (to_jsonb(new) ->> 'written_by')::uuid
  end;

  if tg_op = 'UPDATE'
    and me is not null
    and author is distinct from me
    and coalesce(private.snapshot_role(new.snapshot_id) >= 'editor', false) is false
  then
    raise exception 'Only its author or an editor can move this' using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function private.check_moment_placement() is
  'Trigger function: a contribution''s moment must be in its snapshot; only its author or an editor moves it.';

create trigger check_moment_placement
  before insert or update of moment_id on public.media_item
  for each row execute function private.check_moment_placement();

create trigger check_moment_placement
  before insert or update of moment_id on public.recollection
  for each row execute function private.check_moment_placement();
