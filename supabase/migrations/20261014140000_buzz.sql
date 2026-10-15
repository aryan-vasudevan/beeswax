-- Buzz: the in-app inbox (BWX-101).
--
--   buzz    one thing worth telling someone, or a batch of similar things
--
-- Rows are written only by triggers on the tables where things happen, so
-- the inbox can never say something the data doesn't. Push and email
-- (BWX-42) read the same rows: deliver_after says when a push may go out,
-- pushed_at that it did.
--
-- Rules (docs/product.md, section 7 and Decisions 5 and 6):
--
-- * Quiet by default. No "declined" or "denied" buzz, no "removed you", no
--   "seen", no activity counts. Being told no is something you notice by
--   its absence, not something that pings you.
-- * Similar things batch: while a "new contributions" buzz for a memory is
--   unread, more photos and stories add to it ("Sarah and 2 others added
--   14 photos") instead of stacking up. A batch waits ten minutes after its
--   latest addition before it may push, so a burst of uploads is one buzz.
-- * Quiet hours hold pushes until they end, in the recipient's time zone.
--   The inbox itself always shows everything.
-- * Nothing from someone across a block, in either direction; blocking
--   clears what was already there.
-- * Answered things go read; withdrawn things go away.
--
-- Kinds for features not built yet (reflections, identity-link requests,
-- capsule unlocks, anniversaries) are added with those features.

-- Table ---------------------------------------------------------------------

create type public.buzz_kind as enum (
  'friend_request',      -- someone asked to be your friend
  'friend_accepted',     -- your request was accepted
  'invitation',          -- you were invited to a memory
  'knock',               -- someone used an open link to ask in (owners, editors)
  'member_joined',       -- people you let in arrived (batched per memory)
  'welcome',             -- someone else let you in
  'role_changed',        -- your role in a memory changed
  'ownership_received',  -- a memory is now yours
  'new_contributions',   -- photos and stories added (batched per memory)
  'public_consent'       -- a memory went public: allow your items? (BWX-90)
);

create table public.buzz (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.account (id) on delete cascade,
  kind public.buzz_kind not null,
  snapshot_id uuid references public.snapshot (id) on delete cascade,
  -- Who did it most recently, and everyone who did, newest first.
  actor_id uuid references public.account (id) on delete set null,
  actor_ids uuid[] not null default '{}',
  -- The row to act on: a friendship, invitation or join request.
  subject_id uuid,
  item_count integer not null default 1 constraint item_count_positive check (item_count > 0),
  -- Kind-specific facts, e.g. {"photo": 12, "recollection": 2} or
  -- {"from": "viewer", "to": "contributor"}.
  details jsonb not null default '{}'::jsonb,
  -- Set for batching kinds; one unread row per key and recipient.
  -- updated_at is the latest activity, not the latest edit: marking read
  -- must not move a buzz to the top, so there is no set_updated_at trigger.
  batch_key text,
  deliver_after timestamptz not null default now(),
  pushed_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.buzz is
  'The Buzz inbox (BWX-101). Written only by triggers; push and email (BWX-42) read it too.';

create index buzz_inbox on public.buzz (recipient_id, updated_at desc);
create unique index buzz_one_open_batch
  on public.buzz (recipient_id, batch_key) where read_at is null;
create index buzz_to_push on public.buzz (deliver_after) where pushed_at is null and read_at is null;
create index buzz_snapshot_id on public.buzz (snapshot_id);
create index buzz_actor_id on public.buzz (actor_id);
create index buzz_subject_id on public.buzz (subject_id);

alter table public.buzz enable row level security;

create policy "Users can read their own buzz"
  on public.buzz for select to authenticated
  using (recipient_id = (select auth.uid()));

create policy "Users can mark their own buzz read"
  on public.buzz for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

create policy "Users can clear their own buzz"
  on public.buzz for delete to authenticated
  using (recipient_id = (select auth.uid()));

revoke insert, update on public.buzz from anon, authenticated;
grant update (read_at) on public.buzz to authenticated;

-- Quiet hours ---------------------------------------------------------------

-- When a push for p_account may go out, if it would otherwise go at p_at:
-- p_at itself, or the end of their quiet hours if p_at falls inside them.
-- Quiet hours are local times in the account's time zone (UTC if unset or
-- unrecognised) and may wrap midnight, e.g. 22:00 to 07:00.
create function private.buzz_deliver_after(p_account uuid, p_at timestamptz)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  q_start time;
  q_end time;
  tz text;
  local_at timestamp;
  t time;
  ends timestamp;
begin
  select quiet_hours_start, quiet_hours_end, coalesce(timezone, 'UTC')
  into q_start, q_end, tz
  from public.account_settings
  where account_id = p_account;

  if q_start is null or q_start = q_end then
    return p_at;
  end if;

  begin
    local_at := p_at at time zone tz;
  exception when others then
    tz := 'UTC';
    local_at := p_at at time zone tz;
  end;

  t := local_at::time;
  if (q_start < q_end and t >= q_start and t < q_end)
    or (q_start > q_end and (t >= q_start or t < q_end))
  then
    ends := local_at::date + q_end;
    if ends <= local_at then
      ends := ends + interval '1 day';
    end if;
    return ends at time zone tz;
  end if;

  return p_at;
end;
$$;

comment on function private.buzz_deliver_after(uuid, timestamptz) is
  'When a push may go out: the given time, or the end of the recipient''s quiet hours.';

-- Writing buzz --------------------------------------------------------------

-- The one way rows get written. Skips buzzing yourself and anyone across a
-- block. Batching kinds fold into the recipient's open (unread) batch for
-- the same memory: actors are added newest first, counts summed, and the
-- push is pushed back.
create function private.buzz(
  p_recipient uuid,
  p_kind public.buzz_kind,
  p_snapshot_id uuid,
  p_actor uuid,
  p_subject_id uuid default null,
  p_details jsonb default '{}'::jsonb,
  p_items integer default 1
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  batched boolean := p_kind in ('member_joined', 'new_contributions', 'public_consent');
begin
  if p_recipient is null
    or p_recipient = p_actor
    or (p_actor is not null and private.is_blocked(p_recipient, p_actor))
  then
    return;
  end if;

  insert into public.buzz as b (
    recipient_id, kind, snapshot_id, actor_id, actor_ids, subject_id,
    item_count, details, batch_key, deliver_after
  ) values (
    p_recipient, p_kind, p_snapshot_id, p_actor,
    case when p_actor is null then '{}'::uuid[] else array[p_actor] end,
    p_subject_id, p_items, p_details,
    case when batched then p_kind::text || ':' || coalesce(p_snapshot_id::text, '') end,
    private.buzz_deliver_after(
      p_recipient,
      now() + case when batched then interval '10 minutes' else interval '0' end
    )
  )
  on conflict (recipient_id, batch_key) where read_at is null
  do update set
    actor_id = coalesce(excluded.actor_id, b.actor_id),
    actor_ids = case
      when excluded.actor_id is null then b.actor_ids
      else excluded.actor_id || array_remove(b.actor_ids, excluded.actor_id)
    end,
    item_count = b.item_count + excluded.item_count,
    details = coalesce((
      select jsonb_object_agg(
        k,
        coalesce((b.details ->> k)::integer, 0) + coalesce((excluded.details ->> k)::integer, 0)
      )
      from jsonb_object_keys(b.details || excluded.details) as k
    ), '{}'::jsonb),
    deliver_after = excluded.deliver_after,
    pushed_at = null,
    updated_at = now();
end;
$$;

comment on function private.buzz(uuid, public.buzz_kind, uuid, uuid, uuid, jsonb, integer) is
  'Write or batch a buzz. Skips self and blocks. Used only by triggers.';

-- Forget everything p_actor did in p_recipient's inbox: rows that were only
-- them go, batches lose them.
create function private.forget_buzz_actor(p_recipient uuid, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.buzz
  where recipient_id = p_recipient
    and (actor_ids = array[p_actor] or (actor_id = p_actor and cardinality(actor_ids) = 0));

  update public.buzz
  set actor_ids = array_remove(actor_ids, p_actor),
      actor_id = case
        when actor_id = p_actor then (array_remove(actor_ids, p_actor))[1]
        else actor_id
      end
  where recipient_id = p_recipient and p_actor = any(actor_ids);
end;
$$;

comment on function private.forget_buzz_actor(uuid, uuid) is
  'Remove one actor from someone''s inbox, as when they are blocked.';

revoke execute on function private.buzz_deliver_after(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function private.buzz(uuid, public.buzz_kind, uuid, uuid, uuid, jsonb, integer) from public, anon, authenticated;
revoke execute on function private.forget_buzz_actor(uuid, uuid) from public, anon, authenticated;

-- Reading buzz --------------------------------------------------------------

-- The Buzz tab. Rows are readable directly, but this also resolves names:
-- the first two actors' display names and how many there are in all, so
-- the app can say "Sarah, Omar and 3 others". A memory's title appears
-- only if the reader can see the memory -- an invitation says who invited
-- you, never what to (the same rule as waggle link previews). Invitations
-- that expired unanswered drop out.
create function public.buzz_inbox(p_before timestamptz default null, p_limit integer default 30)
returns table (
  id uuid,
  kind public.buzz_kind,
  snapshot_id uuid,
  snapshot_title text,
  subject_id uuid,
  actor_names text[],
  actor_count integer,
  item_count integer,
  details jsonb,
  updated_at timestamptz,
  read_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    b.id,
    b.kind,
    case when private.can_view_snapshot(b.snapshot_id) then b.snapshot_id end,
    case when private.can_view_snapshot(b.snapshot_id) then s.title end,
    b.subject_id,
    array(
      select p.display_name
      from unnest(b.actor_ids) with ordinality as a (account_id, n)
      join public.person p on p.account_id = a.account_id and p.created_by = a.account_id
      order by a.n
      limit 2
    ),
    cardinality(b.actor_ids),
    b.item_count,
    b.details,
    b.updated_at,
    b.read_at
  from public.buzz b
  left join public.snapshot s on s.id = b.snapshot_id
  where b.recipient_id = (select auth.uid())
    and (p_before is null or b.updated_at < p_before)
    and not exists (
      select 1 from public.snapshot_invitation i
      where b.kind = 'invitation'
        and i.id = b.subject_id
        and i.status = 'pending'
        and i.expires_at <= now()
    )
  order by b.updated_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 100);
$$;

comment on function public.buzz_inbox(timestamptz, integer) is
  'The caller''s Buzz, newest first, with actor names resolved. Page with p_before.';

revoke execute on function public.buzz_inbox(timestamptz, integer) from public, anon;
grant execute on function public.buzz_inbox(timestamptz, integer) to authenticated;

-- Friends -------------------------------------------------------------------

create function private.buzz_friendship()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.buzz(new.addressee_id, 'friend_request', null, new.requester_id, new.id);
  elsif tg_op = 'UPDATE' then
    if new.status = 'accepted' and old.status = 'pending' then
      update public.buzz set read_at = now()
      where subject_id = new.id and kind = 'friend_request' and read_at is null;
      perform private.buzz(new.requester_id, 'friend_accepted', null, new.addressee_id, new.id);
    end if;
  else
    -- Declined, cancelled or unfriended: nothing to act on any more.
    delete from public.buzz
    where subject_id = old.id and kind in ('friend_request', 'friend_accepted');
  end if;
  return null;
end;
$$;

comment on function private.buzz_friendship() is
  'Trigger function: buzz for friend requests and acceptances; clears them when the friendship ends.';

create trigger buzz_friendship
  after insert or update of status or delete on public.friendship
  for each row execute function private.buzz_friendship();

-- Invitations ---------------------------------------------------------------

create function private.buzz_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'pending' then
      perform private.buzz(new.invitee_account_id, 'invitation', new.snapshot_id, new.invited_by, new.id);
    end if;
  elsif new.status is distinct from old.status then
    if new.status = 'revoked' then
      delete from public.buzz where subject_id = new.id and kind = 'invitation';
    else
      update public.buzz set read_at = now()
      where subject_id = new.id and kind = 'invitation' and read_at is null;
    end if;
  end if;
  return null;
end;
$$;

comment on function private.buzz_invitation() is
  'Trigger function: buzz invitees; answered invitations go read, revoked ones go away.';

create trigger buzz_invitation
  after insert or update of status on public.snapshot_invitation
  for each row execute function private.buzz_invitation();

-- Knocks --------------------------------------------------------------------

-- Everyone who could answer the knock hears it: the owner always, editors
-- when the role asked for is below editor (respond_to_join_request's rule).
-- Once anyone answers, it goes read for all of them.
create function private.buzz_join_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.buzz(m.account_id, 'knock', new.snapshot_id, new.account_id, new.id)
    from public.snapshot_member m
    where m.snapshot_id = new.snapshot_id
      and (m.role = 'owner' or (m.role = 'editor' and new.role < 'editor'));
  elsif new.status is distinct from old.status then
    update public.buzz set read_at = now()
    where subject_id = new.id and kind = 'knock' and read_at is null;
  end if;
  return null;
end;
$$;

comment on function private.buzz_join_request() is
  'Trigger function: buzz owners and editors about knocks; answered knocks go read.';

create trigger buzz_join_request
  after insert or update of status on public.snapshot_join_request
  for each row execute function private.buzz_join_request();

-- Membership ----------------------------------------------------------------

-- Joining: whoever let someone in hears that they arrived, unless they let
-- them in just now themselves (approving a knock). The newcomer hears
-- "welcome" unless they did it themselves (accepting an invitation, using
-- an addressed link). Role changes buzz the member; becoming owner is told
-- by ownership_received instead. Leaving or being removed takes that
-- memory's buzz out of the person's inbox, without a word.
create function private.buzz_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    if new.role <> 'owner' then
      if new.added_by is distinct from me then
        perform private.buzz(new.added_by, 'member_joined', new.snapshot_id, new.account_id);
      end if;
      if new.account_id is distinct from me then
        perform private.buzz(
          new.account_id, 'welcome', new.snapshot_id, coalesce(me, new.added_by),
          null, jsonb_build_object('role', new.role)
        );
      end if;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.role is distinct from old.role and 'owner' not in (new.role, old.role) then
      perform private.buzz(
        new.account_id, 'role_changed', new.snapshot_id, me,
        null, jsonb_build_object('from', old.role, 'to', new.role)
      );
    end if;
  else
    delete from public.buzz
    where recipient_id = old.account_id and snapshot_id = old.snapshot_id;
  end if;
  return null;
end;
$$;

comment on function private.buzz_member() is
  'Trigger function: buzz arrivals, welcomes and role changes; clears a leaver''s buzz for that memory.';

create trigger buzz_member
  after insert or update of role or delete on public.snapshot_member
  for each row execute function private.buzz_member();

-- Snapshot changes ----------------------------------------------------------

-- A new owner hears about it (a handover, or a transfer). Going public asks
-- everyone with members-only contributions whether theirs may be shown --
-- nothing of theirs goes public until they say so (BWX-90); going back
-- withdraws the question. Deleting a memory clears all its buzz.
create function private.buzz_snapshot_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from public.buzz where snapshot_id = new.id;
    return null;
  end if;

  if new.owner_id is distinct from old.owner_id then
    perform private.buzz(new.owner_id, 'ownership_received', new.id, me);
  end if;

  if new.visibility = 'public' and old.visibility <> 'public' and new.status = 'published' then
    perform private.buzz(c.account_id, 'public_consent', new.id, me)
    from (
      select uploaded_by as account_id from public.media_item
      where snapshot_id = new.id and audience = 'members'
        and status = 'ready' and deleted_at is null
      union
      select written_by from public.recollection
      where snapshot_id = new.id and audience = 'members' and deleted_at is null
    ) c;
  elsif old.visibility = 'public' and new.visibility <> 'public' then
    delete from public.buzz
    where snapshot_id = new.id and kind = 'public_consent' and read_at is null;
  end if;

  return null;
end;
$$;

comment on function private.buzz_snapshot_change() is
  'Trigger function: buzz new owners and, on going public, contributors whose items are members-only.';

create trigger buzz_snapshot_change
  after update of owner_id, visibility, deleted_at on public.snapshot
  for each row execute function private.buzz_snapshot_change();

-- Contributions -------------------------------------------------------------

-- New photos, videos, audio (once ready) and recollections batch into one
-- buzz per memory for each other member. Only published, live memories:
-- a draft has nobody to tell.
create function private.buzz_contribution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  item jsonb := to_jsonb(new);
  author uuid;
  what text;
begin
  -- One function for both tables, so columns are read through jsonb.
  if tg_table_name = 'media_item' then
    if item ->> 'status' <> 'ready'
      or item ->> 'deleted_at' is not null
      or (tg_op = 'UPDATE' and to_jsonb(old) ->> 'status' = 'ready')
    then
      return null;
    end if;
    author := (item ->> 'uploaded_by')::uuid;
    what := item ->> 'kind';
  else
    author := (item ->> 'written_by')::uuid;
    what := 'recollection';
  end if;

  perform private.buzz(
    m.account_id, 'new_contributions', new.snapshot_id, author,
    null, jsonb_build_object(what, 1)
  )
  from public.snapshot_member m
  join public.snapshot s on s.id = m.snapshot_id
  where m.snapshot_id = new.snapshot_id
    and s.status = 'published'
    and s.deleted_at is null;

  return null;
end;
$$;

comment on function private.buzz_contribution() is
  'Trigger function: batch new media and recollections into each member''s buzz.';

create trigger buzz_contribution
  after insert or update of status on public.media_item
  for each row execute function private.buzz_contribution();

create trigger buzz_contribution
  after insert on public.recollection
  for each row execute function private.buzz_contribution();

-- Blocks --------------------------------------------------------------------

create function private.buzz_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.forget_buzz_actor(new.blocker_id, new.blocked_id);
  perform private.forget_buzz_actor(new.blocked_id, new.blocker_id);
  return null;
end;
$$;

comment on function private.buzz_block() is
  'Trigger function: clears buzz between two accounts when one blocks the other.';

create trigger buzz_block
  after insert on public.block
  for each row execute function private.buzz_block();
