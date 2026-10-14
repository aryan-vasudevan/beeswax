-- Waggle links: invitations anyone can receive, not just accounts you can
-- see (BWX-75). In-app invitations to an account are BWX-13.
--
--   snapshot_invite_link    a link that admits people to a snapshot
--   snapshot_join_request   someone who used an open link, waiting for a yes
--
-- Two kinds of link (docs/product.md, "Invite link forwarded"):
--
--   knock      An open link. Anyone signed in who has it can ask to join;
--              an owner or editor approves. Safe to drop in a group chat:
--              a forwarded link gets a stranger a knock, not a seat.
--   addressed  Made for one email or phone. Redeeming it joins at once, but
--              only for an account whose *verified* email or phone matches.
--
-- Links never store their token. The creator gets the token once, from
-- create_invite_link; the table keeps its SHA-256, so a leaked database
-- holds no working links. Everything about redeeming goes through security
-- definer functions -- clients never read or write link rows directly.
--
-- The preview a link shows before you join (preview_invite_link) names who
-- invited you and that it is a memory. Never the title, photos or people:
-- those are exactly what a forwarded link must not leak.
--
-- Rate limiting of link creation and redemption is BWX-86.

-- Types and tables ----------------------------------------------------------

create type public.invite_link_mode as enum ('knock', 'addressed');

create table public.snapshot_invite_link (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  created_by uuid references public.account (id) on delete set null,
  mode public.invite_link_mode not null,
  role public.snapshot_role not null default 'contributor'
    constraint not_owner check (role <> 'owner'),
  -- SHA-256 of the token. The token itself is never stored.
  token_hash bytea not null unique,
  -- For addressed links: who it is for. One of the two.
  addressed_email extensions.citext,
  addressed_phone text
    constraint addressed_phone_format check (addressed_phone ~ '^\+[1-9][0-9]{6,14}$'),
  -- Null means unlimited (knock links). Addressed links are single-use.
  max_uses integer constraint max_uses_positive check (max_uses > 0),
  use_count integer not null default 0,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint addressed_has_recipient check (
    mode = 'knock'
    or (addressed_email is not null) <> (addressed_phone is not null)
  ),
  constraint knock_has_no_recipient check (
    mode = 'addressed' or (addressed_email is null and addressed_phone is null)
  )
);

comment on table public.snapshot_invite_link is
  'Waggle links into a snapshot. Tokens are stored hashed; use the functions below.';

create index snapshot_invite_link_snapshot on public.snapshot_invite_link (snapshot_id);
create index snapshot_invite_link_created_by on public.snapshot_invite_link (created_by);

alter table public.snapshot_invite_link enable row level security;

create type public.join_request_status as enum ('pending', 'approved', 'denied');

create table public.snapshot_join_request (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  link_id uuid references public.snapshot_invite_link (id) on delete set null,
  account_id uuid not null references public.account (id) on delete cascade,
  -- Copied from the link when the request is made, so revoking the link
  -- later does not change what was asked for.
  role public.snapshot_role not null,
  status public.join_request_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  responded_by uuid references public.account (id) on delete set null
);

comment on table public.snapshot_join_request is
  'Knocks from open waggle links, waiting for an owner or editor.';

create unique index snapshot_join_request_one_pending
  on public.snapshot_join_request (snapshot_id, account_id) where status = 'pending';
create index snapshot_join_request_link_id on public.snapshot_join_request (link_id);
create index snapshot_join_request_account_id on public.snapshot_join_request (account_id);
create index snapshot_join_request_responded_by on public.snapshot_join_request (responded_by);

alter table public.snapshot_join_request enable row level security;

-- Clients read through policies but change nothing directly.
revoke insert, update, delete on public.snapshot_invite_link from anon, authenticated;
revoke insert, update, delete on public.snapshot_join_request from anon, authenticated;
-- The hash is useless to a client and should not leave the database.
revoke select on public.snapshot_invite_link from anon, authenticated;
grant select (
  id, snapshot_id, created_by, mode, role, addressed_email, addressed_phone,
  max_uses, use_count, expires_at, revoked_at, created_at
) on public.snapshot_invite_link to authenticated;

create policy "Owners and editors can see a snapshot's links"
  on public.snapshot_invite_link for select to authenticated
  using (private.snapshot_role(snapshot_id) >= 'editor');

create policy "Requesters, owners and editors can see join requests"
  on public.snapshot_join_request for select to authenticated
  using (
    account_id = (select auth.uid())
    or private.snapshot_role(snapshot_id) >= 'editor'
  );

-- Helpers -------------------------------------------------------------------

create function private.hash_invite_token(p_token text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select extensions.digest(convert_to(p_token, 'UTF8'), 'sha256');
$$;

-- The link a token refers to, if it is still usable: not revoked, expired,
-- used up, or pointing at a snapshot that is deleted or unpublished.
create function private.usable_invite_link(p_token text)
returns public.snapshot_invite_link
language sql
stable
security definer
set search_path = ''
as $$
  select l.*
  from public.snapshot_invite_link l
  join public.snapshot s on s.id = l.snapshot_id
  where l.token_hash = private.hash_invite_token(p_token)
    and l.revoked_at is null
    and l.expires_at > now()
    and (l.max_uses is null or l.use_count < l.max_uses)
    and s.status = 'published'
    and s.deleted_at is null;
$$;

revoke execute on function private.hash_invite_token(text) from public;
revoke execute on function private.usable_invite_link(text) from public;

-- Making a link ---------------------------------------------------------------

-- Returns the token -- the only time anyone sees it. The app turns it into
-- a URL. Owners can hand out any role but owner; editors only contributor
-- or viewer, as with in-app invitations.
create function public.create_invite_link(
  p_snapshot_id uuid,
  p_mode public.invite_link_mode,
  p_role public.snapshot_role default 'contributor',
  p_email text default null,
  p_phone text default null,
  p_valid_for interval default interval '14 days'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.snapshot_role := private.snapshot_role(p_snapshot_id);
  v_token text;
begin
  if v_role is null or v_role < 'editor' then
    raise exception 'Only owners and editors can invite' using errcode = '42501';
  end if;
  if p_role = 'owner' or (v_role = 'editor' and p_role >= 'editor') then
    raise exception 'You cannot invite at that role' using errcode = '42501';
  end if;
  if p_valid_for <= interval '0' or p_valid_for > interval '90 days' then
    raise exception 'Links last between a moment and 90 days' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.snapshot
    where id = p_snapshot_id and status = 'published' and deleted_at is null
  ) then
    raise exception 'Publish the memory before inviting people' using errcode = '22023';
  end if;

  -- 24 random bytes, URL-safe base64: 32 characters, 192 bits.
  v_token := rtrim(
    translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_'),
    '='
  );

  insert into public.snapshot_invite_link (
    snapshot_id, created_by, mode, role, token_hash,
    addressed_email, addressed_phone, max_uses, expires_at
  ) values (
    p_snapshot_id, (select auth.uid()), p_mode, p_role, private.hash_invite_token(v_token),
    nullif(lower(trim(p_email)), '')::extensions.citext, nullif(trim(p_phone), ''),
    case when p_mode = 'addressed' then 1 end,
    now() + p_valid_for
  );

  return v_token;
end;
$$;

comment on function public.create_invite_link(uuid, public.invite_link_mode, public.snapshot_role, text, text, interval) is
  'Create a waggle link and return its token. The token is not stored and cannot be retrieved later.';

create function public.revoke_invite_link(p_link_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.snapshot_invite_link
  set revoked_at = now()
  where id = p_link_id
    and revoked_at is null
    and (
      created_by = (select auth.uid())
      or private.snapshot_role(snapshot_id) = 'owner'
    );

  if not found then
    raise exception 'No active link you can revoke' using errcode = 'P0002';
  end if;
end;
$$;

comment on function public.revoke_invite_link(uuid) is
  'Revoke a waggle link the caller made, or any link on a snapshot they own.';

-- Opening a link ------------------------------------------------------------

-- What the landing page may show before anyone joins. Callable signed out.
-- An unusable token returns no row; the page says "this link no longer
-- works" without saying why.
create function public.preview_invite_link(p_token text)
returns table (
  inviter_name text,
  inviter_avatar_path text,
  mode public.invite_link_mode,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.display_name, p.avatar_path, l.mode, l.expires_at
  from private.usable_invite_link(p_token) l
  left join public.person p
    on p.account_id = l.created_by and p.created_by = l.created_by
  where l.id is not null;
$$;

comment on function public.preview_invite_link(text) is
  'Who invited you and how the link works. Never the memory''s title, people or media.';

-- Use a link. Returns what happened:
--   'joined'          you are now a member (addressed links)
--   'requested'       your knock is waiting for approval (knock links)
--   'already_member'  nothing to do
-- An addressed link for someone else, a block either way, or an unusable
-- link all raise the same "not valid" error, so a stranger learns nothing.
create function public.redeem_invite_link(p_token text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  v_link public.snapshot_invite_link;
  v_owner uuid;
  verified boolean;
begin
  if me is null then
    raise exception 'Sign in to use an invitation' using errcode = '42501';
  end if;

  select * into v_link from private.usable_invite_link(p_token);
  select owner_id into v_owner from public.snapshot where id = v_link.snapshot_id;

  if v_link.id is null
    or private.is_blocked(me, v_link.created_by)
    or private.is_blocked(me, v_owner)
  then
    raise exception 'This invitation is not valid' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.snapshot_member
    where snapshot_id = v_link.snapshot_id and account_id = me
  ) then
    return 'already_member';
  end if;

  if v_link.mode = 'addressed' then
    select
      (v_link.addressed_email is not null
        and u.email_confirmed_at is not null
        and lower(u.email) = lower(v_link.addressed_email::text))
      or (v_link.addressed_phone is not null
        and u.phone_confirmed_at is not null
        and '+' || ltrim(u.phone, '+') = v_link.addressed_phone)
    into verified
    from auth.users u
    where u.id = me;

    if not coalesce(verified, false) then
      raise exception 'This invitation is not valid' using errcode = '22023';
    end if;

    update public.snapshot_invite_link set use_count = use_count + 1 where id = v_link.id;
    insert into public.snapshot_member (snapshot_id, account_id, role, added_by)
    values (v_link.snapshot_id, me, v_link.role, v_link.created_by);
    return 'joined';
  end if;

  insert into public.snapshot_join_request (snapshot_id, link_id, account_id, role)
  values (v_link.snapshot_id, v_link.id, me, v_link.role)
  on conflict (snapshot_id, account_id) where status = 'pending' do nothing;
  return 'requested';
end;
$$;

comment on function public.redeem_invite_link(text) is
  'Use a waggle link: join (addressed, verified match) or knock (open link).';

-- Answer a knock. Owners answer any; editors answer requests for roles
-- below editor.
create function public.respond_to_join_request(p_request_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  req public.snapshot_join_request;
  v_role public.snapshot_role;
begin
  select * into req from public.snapshot_join_request where id = p_request_id for update;
  v_role := private.snapshot_role(req.snapshot_id);

  if req.id is null
    or v_role is null
    or not (v_role = 'owner' or (v_role = 'editor' and req.role < 'editor'))
  then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if req.status <> 'pending' then
    raise exception 'This request has already been answered' using errcode = '22023';
  end if;

  update public.snapshot_join_request
  set status = case when p_approve then 'approved' else 'denied' end::public.join_request_status,
      responded_at = now(),
      responded_by = (select auth.uid())
  where id = req.id;

  if p_approve then
    insert into public.snapshot_member (snapshot_id, account_id, role, added_by)
    values (req.snapshot_id, req.account_id, req.role, (select auth.uid()))
    on conflict (snapshot_id, account_id) do nothing;
  end if;
end;
$$;

comment on function public.respond_to_join_request(uuid, boolean) is
  'Approve or deny someone who knocked through an open waggle link.';

revoke execute on function public.create_invite_link(uuid, public.invite_link_mode, public.snapshot_role, text, text, interval) from public, anon;
revoke execute on function public.revoke_invite_link(uuid) from public, anon;
revoke execute on function public.redeem_invite_link(text) from public, anon;
revoke execute on function public.respond_to_join_request(uuid, boolean) from public, anon;
revoke execute on function public.preview_invite_link(text) from public;

grant execute on function public.create_invite_link(uuid, public.invite_link_mode, public.snapshot_role, text, text, interval) to authenticated;
grant execute on function public.revoke_invite_link(uuid) to authenticated;
grant execute on function public.redeem_invite_link(text) to authenticated;
grant execute on function public.respond_to_join_request(uuid, boolean) to authenticated;
grant execute on function public.preview_invite_link(text) to anon, authenticated;

-- Audit ---------------------------------------------------------------------

create function private.audit_invite_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.snapshot_audit_log (snapshot_id, actor_id, action, details)
    values (new.snapshot_id, (select auth.uid()), 'link_created',
      jsonb_build_object('mode', new.mode, 'role', new.role, 'link_id', new.id));
  elsif new.revoked_at is not null and old.revoked_at is null then
    insert into public.snapshot_audit_log (snapshot_id, actor_id, action, details)
    values (new.snapshot_id, (select auth.uid()), 'link_revoked',
      jsonb_build_object('link_id', new.id));
  end if;
  return new;
end;
$$;

comment on function private.audit_invite_link() is
  'Trigger function: logs waggle links being created and revoked.';

create trigger audit_invite_link
  after insert or update of revoked_at on public.snapshot_invite_link
  for each row execute function private.audit_invite_link();

-- Declining leaves no trace -------------------------------------------------

-- An in-app invitation someone declined disappears for the person who sent
-- it, and the audit log does not record the decline. Nobody should be able
-- to see "X said no to your memory". The inviter can invite again; a block
-- is the answer to repeated invitations.
drop policy "Invitees, inviters, owners and editors can read invitations"
  on public.snapshot_invitation;

create policy "Invitees, inviters, owners and editors can read invitations"
  on public.snapshot_invitation for select to authenticated
  using (
    invitee_account_id = (select auth.uid())
    or (
      status <> 'declined'
      and (
        invited_by = (select auth.uid())
        or private.snapshot_role(snapshot_id) >= 'editor'
      )
    )
  );

drop trigger audit_invitation_status on public.snapshot_invitation;

create trigger audit_invitation_status
  after update of status on public.snapshot_invitation
  for each row
  when (old.status is distinct from new.status and new.status <> 'declined')
  execute function private.audit_invitation_change();
