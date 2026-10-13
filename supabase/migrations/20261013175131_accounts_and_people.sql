-- Accounts, people, friends and blocks (BWX-9).
--
-- The core of the model is `person`, not `account`. Memories involve people
-- who will never sign up -- grandparents, little siblings, people who have
-- died -- so snapshot participants (BWX-13) are people, and a person may or
-- may not have an account behind it. See docs/product.md, "Core model".
--
--   account          one per signed-up user, keyed by auth.users.id
--   person           anyone who can appear in a memory
--                      self person: account_id = created_by -- the user
--                      identity:    added by someone to stand for a human,
--                                   account_id null unless linked (BWX-46)
--   person_private   your private notes and contact details for a person;
--                    only you ever see them
--   relationship     your people list: label, and whether to suggest them
--   friendship       mutual friends between accounts, by request
--   block            accounts you have blocked
--   account_settings per-account preferences
--
-- Rules this schema holds (docs/product.md, sections 4 and 7):
--
-- * People are not browsable. You see yourself, people you created, your
--   people list, friends and pending requests, and (from BWX-13) people in
--   snapshots you can see. Everyone else is reachable only by exact username
--   through public.find_account, and only if they allow it.
-- * Identities are never merged. Two people adding "Grandpa" make two rows.
-- * Linking an identity to an account (BWX-46) never grants access to
--   anything. Access to snapshots is per account, not per person.
-- * Deleting an account never deletes people. The self person stays behind
--   as a name only, so other people's memories stay intact.
--
-- Sign-in methods are not modelled here. Supabase Auth already records each
-- linked provider (email, Apple, Google) in auth.identities; a public copy
-- would only drift from it.

-- Foundations fix -----------------------------------------------------------

-- Pin the search_path of the shared updated_at trigger (BWX-3), as the
-- Supabase advisors require for every function. It only calls now(), which
-- lives in pg_catalog and is always found.
alter function private.set_updated_at() set search_path = '';

-- account -------------------------------------------------------------------

create table public.account (
  id uuid primary key references auth.users (id) on delete cascade,
  -- Null until chosen: Apple and Google sign-ups (BWX-11) arrive without one,
  -- and the app asks for it before anything else.
  username extensions.citext unique
    constraint username_format check (username::text ~ '^[a-z0-9_.]{3,30}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.account is
  'One row per signed-up user. Created by a trigger on auth.users.';

create trigger set_updated_at before update on public.account
  for each row execute function private.set_updated_at();

alter table public.account enable row level security;

revoke insert, update, delete on public.account from anon, authenticated;
grant update (username) on public.account to authenticated;

-- person --------------------------------------------------------------------

create table public.person (
  id uuid primary key default gen_random_uuid(),
  -- The account this person is, if any. Set for self people at sign-up and
  -- for identities once linked. Not unique: several identities, made by
  -- different people, can be linked to the same account.
  account_id uuid references public.account (id) on delete set null,
  -- Who added this person. For a self person, the account itself. Null once
  -- that account is deleted: the person outlives it as a name only.
  created_by uuid default auth.uid()
    references public.account (id) on delete set null,
  display_name text not null
    constraint display_name_length check (char_length(display_name) between 1 and 80),
  nickname text
    constraint nickname_length check (char_length(nickname) <= 40),
  -- Written by the user about themselves; identities have private notes in
  -- person_private instead.
  bio text
    constraint bio_length check (char_length(bio) <= 300),
  -- Path in the avatars storage bucket, once media lands (BWX-29).
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bio_only_on_self_person
    check (bio is null or account_id is not distinct from created_by)
);

comment on table public.person is
  'Anyone who can appear in a memory: a user themselves (self person) or an identity someone added.';

-- Exactly one self person per account.
create unique index person_one_self_per_account
  on public.person (account_id) where account_id = created_by;
create index person_created_by on public.person (created_by);
create index person_account_id on public.person (account_id);

create trigger set_updated_at before update on public.person
  for each row execute function private.set_updated_at();

alter table public.person enable row level security;

revoke insert, update on public.person from anon, authenticated;
grant insert (display_name, nickname, avatar_path) on public.person to authenticated;
grant update (display_name, nickname, bio, avatar_path) on public.person to authenticated;

-- person_private ------------------------------------------------------------

-- What you know about a person that nobody else should: notes ("met at
-- orientation", "allergic to cats"), and the email or phone you would use to
-- invite them (BWX-63) or to suggest a link when they sign up (BWX-46).
-- Keyed by (person, you), so everyone keeps their own.
create table public.person_private (
  person_id uuid not null references public.person (id) on delete cascade,
  account_id uuid not null default auth.uid()
    references public.account (id) on delete cascade,
  notes text
    constraint notes_length check (char_length(notes) <= 2000),
  email extensions.citext,
  phone text
    constraint phone_format check (phone ~ '^\+[1-9][0-9]{6,14}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (person_id, account_id)
);

comment on table public.person_private is
  'Your private notes and contact details for a person. Visible only to you.';

create index person_private_account_id on public.person_private (account_id);

create trigger set_updated_at before update on public.person_private
  for each row execute function private.set_updated_at();

alter table public.person_private enable row level security;

revoke insert, update on public.person_private from anon, authenticated;
grant insert (person_id, notes, email, phone) on public.person_private to authenticated;
grant update (notes, email, phone) on public.person_private to authenticated;

-- relationship --------------------------------------------------------------

-- Not "friend": the people in your memories are family, teammates, partners,
-- people you have lost touch with. Nothing in the snapshot model depends on
-- the label.
create type public.relationship_label as enum (
  'family',
  'friend',
  'partner',
  'classmate',
  'teammate',
  'coworker',
  'other'
);

create table public.relationship (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null default auth.uid()
    references public.account (id) on delete cascade,
  person_id uuid not null references public.person (id) on delete cascade,
  label public.relationship_label,
  -- False to stop suggesting someone (BWX-18) without removing them from
  -- your people or from any memory.
  suggest boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (account_id, person_id)
);

comment on table public.relationship is
  'Your people (BWX-17): who you remember things with, labelled.';

create index relationship_person_id on public.relationship (person_id);

create trigger set_updated_at before update on public.relationship
  for each row execute function private.set_updated_at();

alter table public.relationship enable row level security;

revoke insert, update on public.relationship from anon, authenticated;
grant insert (person_id, label, suggest) on public.relationship to authenticated;
grant update (label, suggest) on public.relationship to authenticated;

-- friendship ----------------------------------------------------------------

-- Mutual and by request. Friends power suggestions and the "friends"
-- audience; there are no counts and your list is visible only to you.
create type public.friendship_status as enum ('pending', 'accepted');

create table public.friendship (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null default auth.uid()
    references public.account (id) on delete cascade,
  addressee_id uuid not null references public.account (id) on delete cascade,
  status public.friendship_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint not_self check (requester_id <> addressee_id)
);

comment on table public.friendship is
  'Friend requests and friendships between accounts. One row per pair.';

-- One row per pair, whichever way round it was sent.
create unique index friendship_one_per_pair on public.friendship (
  least(requester_id, addressee_id), greatest(requester_id, addressee_id)
);
create index friendship_requester_id on public.friendship (requester_id);
create index friendship_addressee_id on public.friendship (addressee_id);

alter table public.friendship enable row level security;

revoke insert, update on public.friendship from anon, authenticated;
grant insert (addressee_id) on public.friendship to authenticated;
grant update (status) on public.friendship to authenticated;

-- block ---------------------------------------------------------------------

create table public.block (
  blocker_id uuid not null default auth.uid()
    references public.account (id) on delete cascade,
  blocked_id uuid not null references public.account (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint not_self check (blocker_id <> blocked_id)
);

comment on table public.block is
  'Accounts you have blocked. Only you can see your blocks.';

create index block_blocked_id on public.block (blocked_id);

alter table public.block enable row level security;

revoke insert, update on public.block from anon, authenticated;
grant insert (blocked_id) on public.block to authenticated;

-- account_settings ----------------------------------------------------------

create table public.account_settings (
  account_id uuid primary key references public.account (id) on delete cascade,
  -- Whether others can find you by exact username.
  discoverable boolean not null default true,
  push_notifications boolean not null default true,
  -- Fallback when push is off or undeliverable (BWX-42).
  email_notifications boolean not null default true,
  -- Local times, in `timezone`, between which nothing buzzes.
  quiet_hours_start time,
  quiet_hours_end time,
  -- IANA name, set by the app. Daily resurfacing (BWX-48) picks "today" in
  -- this zone.
  timezone text,
  -- Powers archive succession (BWX-66). Stored, never shown to anyone.
  last_active_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quiet_hours_together
    check ((quiet_hours_start is null) = (quiet_hours_end is null))
);

comment on table public.account_settings is
  'Per-account preferences (BWX-12). Created by the sign-up trigger.';

create trigger set_updated_at before update on public.account_settings
  for each row execute function private.set_updated_at();

alter table public.account_settings enable row level security;

revoke insert, update, delete on public.account_settings from anon, authenticated;
grant update (
  discoverable, push_notifications, email_notifications,
  quiet_hours_start, quiet_hours_end, timezone, last_active_at
) on public.account_settings to authenticated;

-- Access helpers ------------------------------------------------------------

-- Security definer, so they can look across rows the caller cannot see. They
-- live in `private`, which PostgREST does not expose; `authenticated` gets
-- usage and execute only so that policies can call them.

-- True if either account has blocked the other.
create function private.is_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.block
    where (blocker_id = p_a and blocked_id = p_b)
       or (blocker_id = p_b and blocked_id = p_a)
  );
$$;

-- True if the caller may see this person through BWX-9's rules: it is them,
-- they created it, it is on their people list, or it is a friend or a
-- pending friend request either way. BWX-13 adds people in shared snapshots.
create function private.can_view_person(p_person_id uuid)
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
      )
  );
$$;

-- True if this is the self person of an account that lets itself be found
-- and has no block with the caller. Lets you add someone you found through
-- public.find_account without making everyone visible.
create function private.is_discoverable_self_person(p_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.person p
    join public.account_settings s on s.account_id = p.account_id
    where p.id = p_person_id
      and p.account_id = p.created_by
      and s.discoverable
      and not private.is_blocked(p.account_id, (select auth.uid()))
  );
$$;

revoke execute on function private.is_blocked(uuid, uuid) from public;
revoke execute on function private.can_view_person(uuid) from public;
revoke execute on function private.is_discoverable_self_person(uuid) from public;

grant usage on schema private to authenticated;
grant execute on function private.is_blocked(uuid, uuid) to authenticated;
grant execute on function private.can_view_person(uuid) to authenticated;
grant execute on function private.is_discoverable_self_person(uuid) to authenticated;

-- Policies: person ----------------------------------------------------------

-- The direct checks come first so that INSERT ... RETURNING can read back a
-- new identity: the helper runs on the statement's snapshot, which does not
-- include the row being inserted.
create policy "Users can read people visible to them"
  on public.person for select to authenticated
  using (
    account_id = (select auth.uid())
    or created_by = (select auth.uid())
    or private.can_view_person(id)
  );

-- Clients only ever create identities. Self people come from the sign-up
-- trigger, and account_id is set only by the link flow (BWX-46).
create policy "Users can create identities"
  on public.person for insert to authenticated
  with check (created_by = (select auth.uid()) and account_id is null);

-- You edit your own self person (name, bio, photo) and the identities you
-- created. Nobody edits how someone else appears.
create policy "Users can edit people they created"
  on public.person for update to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

-- Your self person goes only when your account does.
create policy "Users can delete identities they created"
  on public.person for delete to authenticated
  using (created_by = (select auth.uid()) and account_id is distinct from created_by);

-- Policies: account ---------------------------------------------------------

-- An account is visible exactly when some person linked to it is. The
-- subquery runs under the caller's RLS on person.
create policy "Users can read accounts of people they can see"
  on public.account for select to authenticated
  using (
    id = (select auth.uid())
    or exists (select 1 from public.person p where p.account_id = account.id)
  );

create policy "Users can update their own account"
  on public.account for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Policies: person_private --------------------------------------------------

create policy "Users can read their own private notes"
  on public.person_private for select to authenticated
  using (account_id = (select auth.uid()));

create policy "Users can add private notes about people they can see"
  on public.person_private for insert to authenticated
  with check (
    account_id = (select auth.uid())
    and exists (select 1 from public.person p where p.id = person_id)
  );

create policy "Users can edit their own private notes"
  on public.person_private for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));

create policy "Users can delete their own private notes"
  on public.person_private for delete to authenticated
  using (account_id = (select auth.uid()));

-- Policies: relationship ----------------------------------------------------

create policy "Users can read their own relationships"
  on public.relationship for select to authenticated
  using (account_id = (select auth.uid()));

-- The person must be one you can see, or someone you found by username; and
-- not yourself.
create policy "Users can add people they can see or found"
  on public.relationship for insert to authenticated
  with check (
    account_id = (select auth.uid())
    and (
      exists (
        select 1 from public.person p
        where p.id = person_id
          and p.account_id is distinct from (select auth.uid())
      )
      or private.is_discoverable_self_person(person_id)
    )
  );

create policy "Users can edit their own relationships"
  on public.relationship for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));

create policy "Users can remove their own relationships"
  on public.relationship for delete to authenticated
  using (account_id = (select auth.uid()));

-- Policies: friendship ------------------------------------------------------

create policy "Users can read their own friendships and requests"
  on public.friendship for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

create policy "Users can send friend requests"
  on public.friendship for insert to authenticated
  with check (
    requester_id = (select auth.uid())
    and status = 'pending'
    and not private.is_blocked(requester_id, addressee_id)
  );

-- Only the person asked can accept, and only a pending request.
create policy "Users can accept requests sent to them"
  on public.friendship for update to authenticated
  using (addressee_id = (select auth.uid()) and status = 'pending')
  with check (addressee_id = (select auth.uid()) and status = 'accepted');

-- Rejecting, cancelling and unfriending are all a delete, by either side.
create policy "Either side can end a friendship or request"
  on public.friendship for delete to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

-- Policies: block -----------------------------------------------------------

create policy "Users can read their own blocks"
  on public.block for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy "Users can block others"
  on public.block for insert to authenticated
  with check (blocker_id = (select auth.uid()));

create policy "Users can unblock"
  on public.block for delete to authenticated
  using (blocker_id = (select auth.uid()));

-- Policies: account_settings ------------------------------------------------

create policy "Users can read their own settings"
  on public.account_settings for select to authenticated
  using (account_id = (select auth.uid()));

create policy "Users can update their own settings"
  on public.account_settings for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));

-- Finding people ------------------------------------------------------------

-- The only way to reach someone you have no connection to: their exact
-- username. Returns nothing for undiscoverable accounts, blocks either way,
-- or yourself. There is deliberately no partial-match search -- that is a
-- directory, and a directory is what gets scraped.
create function public.find_account(p_username text)
returns table (
  account_id uuid,
  person_id uuid,
  username text,
  display_name text,
  avatar_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id, p.id, a.username::text, p.display_name, p.avatar_path
  from public.account a
  join public.account_settings s on s.account_id = a.id
  join public.person p on p.account_id = a.id and p.created_by = a.id
  where a.username = lower(trim(p_username))::extensions.citext
    and s.discoverable
    and a.id <> (select auth.uid())
    and not private.is_blocked(a.id, (select auth.uid()));
$$;

comment on function public.find_account(text) is
  'Exact-username lookup for adding someone. No partial matches, by design.';

revoke execute on function public.find_account(text) from public, anon;
grant execute on function public.find_account(text) to authenticated;

-- Triggers ------------------------------------------------------------------

-- Every new auth user gets an account, a self person and settings, in the
-- same transaction as the sign-up. Email sign-up (BWX-10) passes `username`
-- and `display_name` in the user metadata; Apple and Google (BWX-11) supply
-- `full_name` or `name` and no username.
--
-- An invalid or taken username fails the whole sign-up, so the app checks
-- availability first.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_username text := nullif(lower(trim(meta ->> 'username')), '');
begin
  insert into public.account (id, username)
  values (new.id, v_username);

  insert into public.person (account_id, created_by, display_name)
  values (
    new.id,
    new.id,
    -- Trimmed to fit display_name_length; a long name from a provider should
    -- not fail the sign-up.
    left(coalesce(
      nullif(trim(meta ->> 'display_name'), ''),
      nullif(trim(meta ->> 'full_name'), ''),
      nullif(trim(meta ->> 'name'), ''),
      v_username,
      nullif(split_part(new.email, '@', 1), ''),
      'New bee'
    ), 80)
  );

  insert into public.account_settings (account_id)
  values (new.id);

  return new;
end;
$$;

comment on function private.handle_new_user() is
  'Trigger function: creates account, self person and settings for a new auth user.';

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Stamp responded_at when a request is accepted.
create function private.stamp_friendship_response()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    new.responded_at = now();
  end if;
  return new;
end;
$$;

comment on function private.stamp_friendship_response() is
  'Trigger function: records when a friend request was answered.';

create trigger stamp_response before update on public.friendship
  for each row execute function private.stamp_friendship_response();

-- Blocking someone ends any friendship or pending request with them.
create function private.end_friendship_on_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.friendship
  where (requester_id = new.blocker_id and addressee_id = new.blocked_id)
     or (requester_id = new.blocked_id and addressee_id = new.blocker_id);
  return new;
end;
$$;

comment on function private.end_friendship_on_block() is
  'Trigger function: removes any friendship or request between two accounts when one blocks the other.';

create trigger end_friendship after insert on public.block
  for each row execute function private.end_friendship_on_block();

-- Deleting an account never deletes people. Before the account row goes,
-- strip what identifies them -- photo and bio -- from their self person and
-- any identities linked to them; the foreign keys then null out account_id
-- and created_by. Names stay, because other people's memories refer to them.
-- Their private notes about others are deleted by cascade.
create function private.release_people_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.person
  set avatar_path = null, bio = null
  where account_id = old.id;

  return old;
end;
$$;

comment on function private.release_people_of_deleted_account() is
  'Trigger function: strips photos and bios from people tied to an account being deleted.';

create trigger release_people
  before delete on public.account
  for each row execute function private.release_people_of_deleted_account();
