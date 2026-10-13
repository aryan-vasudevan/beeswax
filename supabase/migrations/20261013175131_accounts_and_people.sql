-- Accounts, people and relationships (BWX-9).
--
-- The core of the model is `person`, not `account`. Memories involve people
-- who will never sign up -- grandparents, little siblings, people who have
-- died -- so snapshot members (BWX-13) point at a person, and a person may or
-- may not have an account behind it.
--
--   account   one per signed-up user, keyed by auth.users.id
--   person    anyone who can appear in a memory
--               self person: account_id = created_by -- the user themselves
--               identity:    created by someone else to stand for a human,
--                            account_id null until that human claims it
--   relationship   an account's list of people, with an optional label
--   account_settings   per-account preferences
--
-- Identities are private to whoever created them. If two people each add
-- "Grandpa", there are two identities; when he signs up and claims them
-- (BWX-46), both get his account_id and keep their own rows. Claiming links,
-- it never merges, so nothing anyone recorded is rewritten.
--
-- Deleting an account never deletes people. Someone who leaves Beeswax was
-- still at your Orientation Week, so their self person stays behind as a
-- name only -- no account, no avatar, no contact details -- and so do the
-- identities they created, which may sit in other people's snapshots. See
-- private.release_people_of_deleted_account below.
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

-- Usernames are how people find each other to add them, so any signed-in
-- user can read them. Only the username is editable, and only your own.
create policy "Signed-in users can read accounts"
  on public.account for select to authenticated
  using (true);

create policy "Users can update their own account"
  on public.account for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

revoke insert, update, delete on public.account from anon, authenticated;
grant update (username) on public.account to authenticated;

-- person --------------------------------------------------------------------

create table public.person (
  id uuid primary key default gen_random_uuid(),
  -- The account this person is, if any. Set for self people at sign-up and
  -- for identities once claimed. Not unique: several identities can be
  -- claimed by the same account.
  account_id uuid references public.account (id) on delete set null,
  -- Who added this person. For a self person, the account itself. Null once
  -- that account is deleted: the person outlives it as a name only.
  created_by uuid default auth.uid()
    references public.account (id) on delete set null,
  display_name text not null
    constraint display_name_length check (char_length(display_name) between 1 and 80),
  -- Path in the avatars storage bucket, once media lands (BWX-29).
  avatar_path text,
  -- Contact details the creator knows for an identity. Used to send the claim
  -- invite (BWX-46) and to suggest a match when someone signs up -- never to
  -- link automatically.
  email extensions.citext,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A self person is visible to every signed-in user, so it must not carry
  -- contact details; the account's own email and phone live in auth.users.
  constraint self_person_has_no_contact_details
    check (account_id is distinct from created_by or (email is null and phone is null))
);

comment on table public.person is
  'Anyone who can appear in a memory: a user themselves (self person) or an identity someone created.';

-- Exactly one self person per account.
create unique index person_one_self_per_account
  on public.person (account_id) where account_id = created_by;
create index person_created_by on public.person (created_by);
create index person_account_id on public.person (account_id);

create trigger set_updated_at before update on public.person
  for each row execute function private.set_updated_at();

alter table public.person enable row level security;

-- Visible: everyone's self person (so you can find and add people), plus the
-- identities you created, plus identities that have been claimed by you.
-- BWX-13 widens this to people who share a snapshot with you.
create policy "Signed-in users can read visible people"
  on public.person for select to authenticated
  using (
    account_id = created_by
    or created_by = (select auth.uid())
    or account_id = (select auth.uid())
  );

-- Clients only ever create identities. Self people come from the sign-up
-- trigger, and account_id is set only by the claim flow (BWX-46).
create policy "Users can create identities"
  on public.person for insert to authenticated
  with check (created_by = (select auth.uid()) and account_id is null);

create policy "Users can edit people they created"
  on public.person for update to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

-- Your self person goes only when your account does.
create policy "Users can delete identities they created"
  on public.person for delete to authenticated
  using (created_by = (select auth.uid()) and account_id is distinct from created_by);

revoke insert, update on public.person from anon, authenticated;
grant insert (display_name, avatar_path, email, phone) on public.person to authenticated;
grant update (display_name, avatar_path, email, phone) on public.person to authenticated;

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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (account_id, person_id)
);

comment on table public.relationship is
  'Your people (BWX-17). Removing one also drops them from member suggestions (BWX-18).';

create index relationship_person_id on public.relationship (person_id);

create trigger set_updated_at before update on public.relationship
  for each row execute function private.set_updated_at();

alter table public.relationship enable row level security;

create policy "Users can read their own relationships"
  on public.relationship for select to authenticated
  using (account_id = (select auth.uid()));

-- The person must be one you can see, and not you. The subquery runs under
-- the caller's RLS, so an invisible person reads as missing.
create policy "Users can add people they can see"
  on public.relationship for insert to authenticated
  with check (
    account_id = (select auth.uid())
    and exists (
      select 1 from public.person p
      where p.id = person_id
        and p.account_id is distinct from (select auth.uid())
    )
  );

create policy "Users can relabel their own relationships"
  on public.relationship for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));

create policy "Users can remove their own relationships"
  on public.relationship for delete to authenticated
  using (account_id = (select auth.uid()));

revoke insert, update on public.relationship from anon, authenticated;
grant insert (person_id, label) on public.relationship to authenticated;
grant update (label) on public.relationship to authenticated;

-- account_settings ----------------------------------------------------------

create table public.account_settings (
  account_id uuid primary key references public.account (id) on delete cascade,
  push_notifications boolean not null default true,
  -- Fallback when push is off or undeliverable (BWX-42).
  email_notifications boolean not null default true,
  -- IANA name, set by the app. Daily resurfacing (BWX-48) picks "today" in
  -- this zone.
  timezone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.account_settings is
  'Per-account preferences (BWX-12). Created by the sign-up trigger.';

create trigger set_updated_at before update on public.account_settings
  for each row execute function private.set_updated_at();

alter table public.account_settings enable row level security;

create policy "Users can read their own settings"
  on public.account_settings for select to authenticated
  using (account_id = (select auth.uid()));

create policy "Users can update their own settings"
  on public.account_settings for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));

revoke insert, update, delete on public.account_settings from anon, authenticated;
grant update (push_notifications, email_notifications, timezone)
  on public.account_settings to authenticated;

-- Sign-up -------------------------------------------------------------------

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

-- Account deletion ----------------------------------------------------------

-- Runs before the account row goes, so the foreign keys then null out
-- account_id and created_by instead of deleting anyone. What is removed is
-- everything that identifies or contacts a person: avatars, and the email and
-- phone the deleted user had recorded for their identities. Names stay,
-- because other people's memories refer to them.
--
-- A person left with neither account nor creator is visible to nobody until
-- BWX-13 shows people through the snapshots they appear in.
create function private.release_people_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.person
  set avatar_path = null, email = null, phone = null
  where created_by = old.id or account_id = old.id;

  return old;
end;
$$;

comment on function private.release_people_of_deleted_account() is
  'Trigger function: strips contact details and avatars from people tied to an account being deleted.';

create trigger release_people
  before delete on public.account
  for each row execute function private.release_people_of_deleted_account();
