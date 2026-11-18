-- Snapshots: participants, members, invitations, audience, audit (BWX-13).
--
--   snapshot               one memory (a cell in the hive)
--   snapshot_participant   people who were there -- accounts or identities
--   snapshot_member        accounts with access, each with a role
--   snapshot_invitation    how an account becomes a member: asked, then accepts
--   snapshot_audience      extra accounts allowed to look (custom visibility)
--   snapshot_audit_log     every change to who can see or do what
--
-- The rules this holds (docs/product.md, sections 3, 6 and 7):
--
-- * Being in a memory never grants access to it. Participants are people;
--   access is per account, through membership, the audience, or a public
--   link. Linking an identity to an account (BWX-46) therefore grants
--   nothing on its own.
-- * Nobody becomes a member without saying yes. Owners and editors invite;
--   the invitee accepts. The only member nobody invites is the owner.
-- * Roles, weakest first so that comparisons and max() work:
--     viewer < contributor < editor < owner
--   Owners alone change visibility, roles, status, archive and delete.
-- * Drafts (brood) are seen only by their owner. Deleting is soft: the
--   snapshot is hidden from everyone but the owner, who can restore it for
--   30 days before a purge job (BWX-77) removes it.
-- * Dates can be approximate ("summer 2008"): a precision says how much of
--   starts_at to trust.
-- * An owner who deletes their account hands each snapshot to their longest-
--   standing editor, else contributor, else viewer. A snapshot with no other
--   members is deleted with the account. Named successors are BWX-66.
--
-- Not here yet: nesting and links (BWX-21), media and per-item visibility
-- (BWX-29, BWX-90), moments (BWX-95), link invitations (BWX-75).
--
-- Concurrent edits: clients send the updated_at they last read and update
-- with `... where id = $1 and updated_at = $2`. Zero rows means someone
-- else saved first; the client re-reads and merges field by field.

-- Types ---------------------------------------------------------------------

create type public.snapshot_visibility as enum (
  'private', -- members only
  'custom',  -- members plus the accounts in snapshot_audience
  'public'   -- anyone signed in who has the link; never listed or searchable
);

create type public.snapshot_role as enum ('viewer', 'contributor', 'editor', 'owner');

create type public.snapshot_status as enum ('draft', 'published');

create type public.date_precision as enum (
  'minute', 'day', 'month', 'season', 'year', 'decade'
);

create type public.invitation_status as enum ('pending', 'accepted', 'declined', 'revoked');

-- snapshot ------------------------------------------------------------------

create table public.snapshot (
  id uuid primary key default gen_random_uuid(),
  -- Who made it. Never changes, survives ownership transfer.
  creator_id uuid default auth.uid() references public.account (id) on delete set null,
  -- Who controls it now.
  owner_id uuid default auth.uid() references public.account (id) on delete set null,
  status public.snapshot_status not null default 'draft',
  -- Drafts can be untitled; a published snapshot needs a title until media
  -- lands (BWX-29), when "a title or at least one item" becomes the rule.
  title text
    constraint title_length check (char_length(title) between 1 and 120),
  description text
    constraint description_length check (char_length(description) <= 5000),
  -- Optional: some memories have no known date. With a precision coarser
  -- than a day, only the leading part is meaningful (2008-06-01 at 'season'
  -- reads "Summer 2008").
  starts_at timestamptz,
  ends_at timestamptz,
  date_precision public.date_precision not null default 'day',
  -- IANA zone the memory happened in. Needed for an exact time: a 9pm dinner
  -- in Tokyo should not read as 8am to someone in Toronto.
  timezone text,
  place_name text
    constraint place_name_length check (char_length(place_name) <= 200),
  latitude double precision
    constraint latitude_range check (latitude between -90 and 90),
  longitude double precision
    constraint longitude_range check (longitude between -180 and 180),
  visibility public.snapshot_visibility not null default 'private',
  published_at timestamptz,
  archived_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ends_after_start check (ends_at >= starts_at),
  constraint end_needs_start check (ends_at is null or starts_at is not null),
  constraint coordinates_together check ((latitude is null) = (longitude is null)),
  constraint published_needs_title check (status = 'draft' or title is not null),
  constraint exact_time_needs_timezone check (date_precision <> 'minute' or timezone is not null)
);

comment on table public.snapshot is
  'One memory. Participants, members, invitations and audience hang off it.';

create index snapshot_owner_id on public.snapshot (owner_id);
create index snapshot_creator_id on public.snapshot (creator_id);
create index snapshot_starts_at on public.snapshot (starts_at);
create index snapshot_deleted_at on public.snapshot (deleted_at) where deleted_at is not null;

create trigger set_updated_at before update on public.snapshot
  for each row execute function private.set_updated_at();

alter table public.snapshot enable row level security;

-- snapshot_participant ------------------------------------------------------

create table public.snapshot_participant (
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  person_id uuid not null references public.person (id) on delete cascade,
  added_by uuid default auth.uid() references public.account (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (snapshot_id, person_id)
);

comment on table public.snapshot_participant is
  'People who were there. Being a participant grants no access.';

create index snapshot_participant_person_id on public.snapshot_participant (person_id);
create index snapshot_participant_added_by on public.snapshot_participant (added_by);

alter table public.snapshot_participant enable row level security;

-- snapshot_member -----------------------------------------------------------

create table public.snapshot_member (
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  account_id uuid not null references public.account (id) on delete cascade,
  role public.snapshot_role not null,
  added_by uuid references public.account (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (snapshot_id, account_id)
);

comment on table public.snapshot_member is
  'Accounts with access to a snapshot. Created by accepting an invitation, or for the owner by trigger.';

create unique index snapshot_member_one_owner
  on public.snapshot_member (snapshot_id) where role = 'owner';
create index snapshot_member_account_id on public.snapshot_member (account_id);
create index snapshot_member_added_by on public.snapshot_member (added_by);

create trigger set_updated_at before update on public.snapshot_member
  for each row execute function private.set_updated_at();

alter table public.snapshot_member enable row level security;

-- snapshot_invitation -------------------------------------------------------

create table public.snapshot_invitation (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  invitee_account_id uuid not null references public.account (id) on delete cascade,
  role public.snapshot_role not null default 'contributor'
    constraint not_owner check (role <> 'owner'),
  status public.invitation_status not null default 'pending',
  invited_by uuid default auth.uid() references public.account (id) on delete set null,
  expires_at timestamptz not null default now() + interval '30 days',
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

comment on table public.snapshot_invitation is
  'In-app invitations to become a member. Link invitations are BWX-75.';

-- No duplicate pending invitations.
create unique index snapshot_invitation_one_pending
  on public.snapshot_invitation (snapshot_id, invitee_account_id) where status = 'pending';
create index snapshot_invitation_invitee on public.snapshot_invitation (invitee_account_id);
create index snapshot_invitation_invited_by on public.snapshot_invitation (invited_by);

alter table public.snapshot_invitation enable row level security;

-- snapshot_audience ---------------------------------------------------------

create table public.snapshot_audience (
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  account_id uuid not null references public.account (id) on delete cascade,
  added_by uuid default auth.uid() references public.account (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (snapshot_id, account_id)
);

comment on table public.snapshot_audience is
  'Accounts allowed to view a custom-visibility snapshot without being members.';

create index snapshot_audience_account_id on public.snapshot_audience (account_id);
create index snapshot_audience_added_by on public.snapshot_audience (added_by);

alter table public.snapshot_audience enable row level security;

-- snapshot_audit_log --------------------------------------------------------

create table public.snapshot_audit_log (
  id bigint generated always as identity primary key,
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  -- Null for server-side changes (jobs, account deletion).
  actor_id uuid references public.account (id) on delete set null,
  action text not null,
  -- The account the change was about, if any.
  subject_account_id uuid references public.account (id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.snapshot_audit_log is
  'Who changed access or status, and when (BWX-88). Written only by triggers.';

create index snapshot_audit_log_snapshot on public.snapshot_audit_log (snapshot_id, created_at);
create index snapshot_audit_log_actor_id on public.snapshot_audit_log (actor_id);
create index snapshot_audit_log_subject on public.snapshot_audit_log (subject_account_id);

alter table public.snapshot_audit_log enable row level security;

revoke insert, update, delete on public.snapshot_audit_log from anon, authenticated;

-- Access helpers ------------------------------------------------------------

-- Policies on snapshot, its child tables and person all need "can this user
-- see snapshot X?", and plain subqueries between them recurse. These
-- security definer helpers break the cycle. They live in `private`, which
-- PostgREST does not expose; BWX-9 already gave `authenticated` usage on it.

-- The caller's role in a snapshot, or null. Deleted snapshots give their
-- owner 'owner' (so they can restore) and everyone else nothing.
create function private.snapshot_role(p_snapshot_id uuid)
returns public.snapshot_role
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when s.owner_id = (select auth.uid()) then 'owner'::public.snapshot_role
    when s.deleted_at is not null or s.status = 'draft' then null
    else (
      select m.role from public.snapshot_member m
      where m.snapshot_id = s.id and m.account_id = (select auth.uid())
    )
  end
  from public.snapshot s
  where s.id = p_snapshot_id;
$$;

create function private.can_view_snapshot(p_snapshot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.snapshot s
    where s.id = p_snapshot_id
      and (
        s.owner_id = (select auth.uid())
        or (
          s.deleted_at is null
          and s.status = 'published'
          and (
            exists (
              select 1 from public.snapshot_member m
              where m.snapshot_id = s.id and m.account_id = (select auth.uid())
            )
            or (
              s.visibility = 'custom'
              and exists (
                select 1 from public.snapshot_audience a
                where a.snapshot_id = s.id and a.account_id = (select auth.uid())
              )
            )
            or (
              s.visibility = 'public'
              and not private.is_blocked(s.owner_id, (select auth.uid()))
            )
          )
        )
      )
  );
$$;

revoke execute on function private.snapshot_role(uuid) from public;
revoke execute on function private.can_view_snapshot(uuid) from public;
grant execute on function private.snapshot_role(uuid) to authenticated;
grant execute on function private.can_view_snapshot(uuid) to authenticated;

-- Widen BWX-9's person visibility: you can also see the participants of any
-- snapshot you can see, the members you share a snapshot with, and whoever
-- has invited you. This is how your cousin's "Grandpa" shows up in a memory
-- you share -- his name only; notes and contact details stay in
-- person_private, visible to their author alone.
create or replace function private.can_view_person(p_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.person p
    where p.id = p_person_id
      and (
        p.account_id = (select auth.uid())
        or p.created_by = (select auth.uid())
        or exists (
          select 1 from public.relationship r
          where r.person_id = p.id and r.account_id = (select auth.uid())
        )
        or (
          p.account_id = p.created_by
          and exists (
            select 1 from public.friendship f
            where (f.requester_id = (select auth.uid()) and f.addressee_id = p.account_id)
               or (f.addressee_id = (select auth.uid()) and f.requester_id = p.account_id)
          )
        )
        or exists (
          select 1 from public.snapshot_participant sp
          where sp.person_id = p.id and private.can_view_snapshot(sp.snapshot_id)
        )
        or (
          p.account_id = p.created_by
          and exists (
            select 1 from public.snapshot_member m
            where m.account_id = p.account_id and private.can_view_snapshot(m.snapshot_id)
          )
        )
        or (
          p.account_id = p.created_by
          and exists (
            select 1 from public.snapshot_invitation i
            where i.invited_by = p.account_id
              and i.invitee_account_id = (select auth.uid())
              and i.status = 'pending'
          )
        )
      )
  );
$$;

-- Triggers on snapshot ------------------------------------------------------

-- The owner is the one member nobody invites.
create function private.add_owner_as_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.snapshot_member (snapshot_id, account_id, role, added_by)
  values (new.id, new.owner_id, 'owner', new.owner_id);
  return new;
end;
$$;

comment on function private.add_owner_as_member() is
  'Trigger function: makes the owner of a new snapshot its owner member.';

create trigger add_owner_as_member
  after insert on public.snapshot
  for each row execute function private.add_owner_as_member();

-- Validates the timezone, stamps published_at, and keeps the owner's
-- decisions with the owner: editors may change what a memory says, not who
-- sees it or whether it exists. Requests with no user (server-side jobs)
-- skip the role check.
create function private.check_snapshot_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.timezone is not null
    and (tg_op = 'INSERT' or new.timezone is distinct from old.timezone)
    and not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone)
  then
    raise exception 'Unknown timezone: %', new.timezone using errcode = '22023';
  end if;

  if new.status = 'published' and new.published_at is null then
    new.published_at = now();
  end if;

  if tg_op = 'UPDATE'
    and (select auth.uid()) is not null
    and private.snapshot_role(old.id) is distinct from 'owner'
    and (
      new.visibility is distinct from old.visibility
      or new.status is distinct from old.status
      or new.archived_at is distinct from old.archived_at
      or new.deleted_at is distinct from old.deleted_at
    )
  then
    raise exception 'Only the owner can change visibility, publish, archive or delete'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function private.check_snapshot_change() is
  'Trigger function: validates timezone, stamps published_at, keeps owner-only fields with the owner.';

create trigger check_snapshot_change
  before insert or update on public.snapshot
  for each row execute function private.check_snapshot_change();

-- Audit -----------------------------------------------------------------------

create function private.audit_snapshot_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.visibility is distinct from old.visibility then
    insert into public.snapshot_audit_log (snapshot_id, actor_id, action, details)
    values (new.id, (select auth.uid()), 'visibility_changed',
      jsonb_build_object('from', old.visibility, 'to', new.visibility));
  end if;
  if new.owner_id is distinct from old.owner_id then
    insert into public.snapshot_audit_log (snapshot_id, actor_id, action, subject_account_id)
    values (new.id, (select auth.uid()), 'owner_changed', new.owner_id);
  end if;
  if new.status is distinct from old.status then
    insert into public.snapshot_audit_log (snapshot_id, actor_id, action, details)
    values (new.id, (select auth.uid()), 'status_changed',
      jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  if new.archived_at is distinct from old.archived_at then
    insert into public.snapshot_audit_log (snapshot_id, actor_id, action)
    values (new.id, (select auth.uid()),
      case when new.archived_at is null then 'unarchived' else 'archived' end);
  end if;
  if new.deleted_at is distinct from old.deleted_at then
    insert into public.snapshot_audit_log (snapshot_id, actor_id, action)
    values (new.id, (select auth.uid()),
      case when new.deleted_at is null then 'restored' else 'deleted' end);
  end if;
  return new;
end;
$$;

comment on function private.audit_snapshot_change() is
  'Trigger function: logs visibility, owner, status, archive and delete changes.';

create trigger audit_snapshot_change
  after update on public.snapshot
  for each row execute function private.audit_snapshot_change();

create function private.audit_member_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A snapshot being deleted takes its members with it; nothing to log.
  if tg_op = 'DELETE'
    and not exists (select 1 from public.snapshot where id = old.snapshot_id)
  then
    return old;
  end if;

  insert into public.snapshot_audit_log
    (snapshot_id, actor_id, action, subject_account_id, details)
  values (
    coalesce(new.snapshot_id, old.snapshot_id),
    (select auth.uid()),
    case tg_op
      when 'INSERT' then 'member_added'
      when 'UPDATE' then 'role_changed'
      else 'member_removed'
    end,
    coalesce(new.account_id, old.account_id),
    case tg_op
      when 'INSERT' then jsonb_build_object('role', new.role)
      when 'UPDATE' then jsonb_build_object('from', old.role, 'to', new.role)
      else jsonb_build_object('role', old.role)
    end
  );
  return coalesce(new, old);
end;
$$;

comment on function private.audit_member_change() is
  'Trigger function: logs members joining, changing role and leaving.';

create trigger audit_member_change
  after insert or update or delete on public.snapshot_member
  for each row execute function private.audit_member_change();

create function private.audit_invitation_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.snapshot_audit_log
    (snapshot_id, actor_id, action, subject_account_id, details)
  values (
    new.snapshot_id,
    (select auth.uid()),
    case when tg_op = 'INSERT' then 'invited' else 'invitation_' || new.status::text end,
    new.invitee_account_id,
    jsonb_build_object('role', new.role)
  );
  return new;
end;
$$;

comment on function private.audit_invitation_change() is
  'Trigger function: logs invitations sent, accepted, declined and revoked.';

create trigger audit_invitation_insert
  after insert on public.snapshot_invitation
  for each row execute function private.audit_invitation_change();

create trigger audit_invitation_status
  after update of status on public.snapshot_invitation
  for each row when (old.status is distinct from new.status)
  execute function private.audit_invitation_change();

-- Policies: snapshot --------------------------------------------------------

-- owner_id is checked directly as well as through the helper so that an
-- INSERT ... RETURNING can read the new row back: the helper runs on the
-- statement's snapshot, which does not include the row being inserted.
create policy "Users can read snapshots they can see"
  on public.snapshot for select to authenticated
  using (owner_id = (select auth.uid()) or private.can_view_snapshot(id));

create policy "Users can create their own snapshots"
  on public.snapshot for insert to authenticated
  with check (owner_id = (select auth.uid()) and creator_id = (select auth.uid()));

create policy "Owners and editors can edit snapshots"
  on public.snapshot for update to authenticated
  using (private.snapshot_role(id) >= 'editor')
  with check (private.snapshot_role(id) >= 'editor');

-- Published snapshots are deleted softly (deleted_at). Only a draft can be
-- removed outright, by its owner.
create policy "Owners can discard drafts"
  on public.snapshot for delete to authenticated
  using (owner_id = (select auth.uid()) and status = 'draft');

revoke insert, update on public.snapshot from anon, authenticated;
grant insert (
  status, title, description, starts_at, ends_at, date_precision, timezone,
  place_name, latitude, longitude, visibility
) on public.snapshot to authenticated;
grant update (
  status, title, description, starts_at, ends_at, date_precision, timezone,
  place_name, latitude, longitude, visibility, archived_at, deleted_at
) on public.snapshot to authenticated;

-- Policies: snapshot_participant --------------------------------------------

create policy "Users can read participants of snapshots they can see"
  on public.snapshot_participant for select to authenticated
  using (private.can_view_snapshot(snapshot_id));

-- The person must be one the adder can see (subquery under their RLS).
create policy "Owners and editors can add participants"
  on public.snapshot_participant for insert to authenticated
  with check (
    private.snapshot_role(snapshot_id) >= 'editor'
    and exists (select 1 from public.person p where p.id = person_id)
  );

-- Anyone can take themselves out of a memory they were tagged in.
create policy "Owners, editors or the person themselves can remove participants"
  on public.snapshot_participant for delete to authenticated
  using (
    private.snapshot_role(snapshot_id) >= 'editor'
    or exists (
      select 1 from public.person p
      where p.id = person_id and p.account_id = (select auth.uid())
    )
  );

revoke insert, update on public.snapshot_participant from anon, authenticated;
grant insert (snapshot_id, person_id) on public.snapshot_participant to authenticated;

-- Policies: snapshot_member -------------------------------------------------

create policy "Users can read members of snapshots they can see"
  on public.snapshot_member for select to authenticated
  using (private.can_view_snapshot(snapshot_id));

-- No insert policy: members arrive only through respond_to_invitation and
-- the owner trigger.

create policy "Owners can change member roles"
  on public.snapshot_member for update to authenticated
  using (role <> 'owner' and private.snapshot_role(snapshot_id) = 'owner')
  with check (role <> 'owner' and private.snapshot_role(snapshot_id) = 'owner');

-- Owners remove anyone but themselves, editors remove those below them, and
-- anyone can leave. The owner row never goes this way.
create policy "Members can be removed by owners, editors or themselves"
  on public.snapshot_member for delete to authenticated
  using (
    role <> 'owner'
    and (
      private.snapshot_role(snapshot_id) = 'owner'
      or (private.snapshot_role(snapshot_id) = 'editor' and role < 'editor')
      or account_id = (select auth.uid())
    )
  );

revoke insert, update on public.snapshot_member from anon, authenticated;
grant update (role) on public.snapshot_member to authenticated;

-- Policies: snapshot_invitation ---------------------------------------------

create policy "Invitees, inviters, owners and editors can read invitations"
  on public.snapshot_invitation for select to authenticated
  using (
    invitee_account_id = (select auth.uid())
    or invited_by = (select auth.uid())
    or private.snapshot_role(snapshot_id) >= 'editor'
  );

-- Owners invite at any role; editors invite contributors and viewers. Not
-- someone who is already a member, not across a block, and only to a
-- published snapshot.
create policy "Owners and editors can invite"
  on public.snapshot_invitation for insert to authenticated
  with check (
    invited_by = (select auth.uid())
    and status = 'pending'
    and (
      private.snapshot_role(snapshot_id) = 'owner'
      or (private.snapshot_role(snapshot_id) = 'editor' and role < 'editor')
    )
    and exists (
      select 1 from public.snapshot s
      where s.id = snapshot_id and s.status = 'published' and s.deleted_at is null
    )
    and not exists (
      select 1 from public.snapshot_member m
      where m.snapshot_id = snapshot_invitation.snapshot_id
        and m.account_id = invitee_account_id
    )
    and not private.is_blocked(invitee_account_id, (select auth.uid()))
  );

revoke insert, update, delete on public.snapshot_invitation from anon, authenticated;
grant insert (snapshot_id, invitee_account_id, role) on public.snapshot_invitation to authenticated;

-- Policies: snapshot_audience -----------------------------------------------

create policy "Users can read the audience of snapshots they can see"
  on public.snapshot_audience for select to authenticated
  using (private.can_view_snapshot(snapshot_id));

create policy "Owners can add to the audience"
  on public.snapshot_audience for insert to authenticated
  with check (private.snapshot_role(snapshot_id) = 'owner');

create policy "Owners can remove from the audience"
  on public.snapshot_audience for delete to authenticated
  using (private.snapshot_role(snapshot_id) = 'owner');

revoke insert, update on public.snapshot_audience from anon, authenticated;
grant insert (snapshot_id, account_id) on public.snapshot_audience to authenticated;

-- Policies: snapshot_audit_log ----------------------------------------------

create policy "Owners can read their snapshots' audit log"
  on public.snapshot_audit_log for select to authenticated
  using (private.snapshot_role(snapshot_id) = 'owner');

-- Invitation responses ------------------------------------------------------

-- Accept or decline an invitation addressed to you. Accepting makes you a
-- member with the invited role. Expired, revoked or answered invitations,
-- and ones for snapshots since deleted, are refused.
create function public.respond_to_invitation(p_invitation_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  inv public.snapshot_invitation;
begin
  select * into inv
  from public.snapshot_invitation
  where id = p_invitation_id
  for update;

  if inv.id is null or inv.invitee_account_id is distinct from (select auth.uid()) then
    raise exception 'Invitation not found' using errcode = 'P0002';
  end if;
  if inv.status <> 'pending' then
    raise exception 'This invitation has already been %', inv.status using errcode = '22023';
  end if;
  if inv.expires_at <= now() then
    raise exception 'This invitation has expired' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.snapshot where id = inv.snapshot_id and deleted_at is null
  ) then
    raise exception 'This memory is no longer available' using errcode = '22023';
  end if;

  update public.snapshot_invitation
  set status = case when p_accept then 'accepted' else 'declined' end::public.invitation_status,
      responded_at = now()
  where id = inv.id;

  if p_accept then
    insert into public.snapshot_member (snapshot_id, account_id, role, added_by)
    values (inv.snapshot_id, inv.invitee_account_id, inv.role, inv.invited_by)
    on conflict (snapshot_id, account_id) do nothing;
  end if;
end;
$$;

comment on function public.respond_to_invitation(uuid, boolean) is
  'Accept or decline an invitation addressed to the caller.';

-- Withdraw a pending invitation you sent, or any on a snapshot you own.
create function public.revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.snapshot_invitation
  set status = 'revoked', responded_at = now()
  where id = p_invitation_id
    and status = 'pending'
    and (
      invited_by = (select auth.uid())
      or private.snapshot_role(snapshot_id) = 'owner'
    );

  if not found then
    raise exception 'No pending invitation you can revoke' using errcode = 'P0002';
  end if;
end;
$$;

comment on function public.revoke_invitation(uuid) is
  'Withdraw a pending invitation the caller sent or owns.';

revoke execute on function public.respond_to_invitation(uuid, boolean) from public, anon;
revoke execute on function public.revoke_invitation(uuid) from public, anon;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;
grant execute on function public.revoke_invitation(uuid) to authenticated;

-- Owner deletes their account ---------------------------------------------

-- Before the account goes, each snapshot it owns passes to the longest-
-- standing editor, else contributor, else viewer. Snapshots with nobody to
-- inherit them are deleted with the account. Runs alongside BWX-9's
-- release_people trigger.
create function private.hand_over_snapshots()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s record;
  heir uuid;
begin
  for s in select id from public.snapshot where owner_id = old.id loop
    select m.account_id into heir
    from public.snapshot_member m
    where m.snapshot_id = s.id and m.account_id <> old.id
    order by m.role desc, m.created_at
    limit 1;

    if heir is null then
      delete from public.snapshot where id = s.id;
    else
      delete from public.snapshot_member
      where snapshot_id = s.id and account_id = old.id;
      update public.snapshot_member set role = 'owner'
      where snapshot_id = s.id and account_id = heir;
      update public.snapshot set owner_id = heir where id = s.id;
    end if;
  end loop;

  return old;
end;
$$;

comment on function private.hand_over_snapshots() is
  'Trigger function: passes a deleted account''s snapshots to their next member, or deletes them.';

create trigger hand_over_snapshots
  before delete on public.account
  for each row execute function private.hand_over_snapshots();
