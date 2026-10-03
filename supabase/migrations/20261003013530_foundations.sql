-- Foundations for the beeswax database (BWX-3).
--
-- This migration deliberately creates no application tables. Those land in
-- the tickets that own them: BWX-9 (account, person, auth_provider,
-- friendship, settings), BWX-13 (snapshot, members, viewers), BWX-21 (links
-- and nesting), BWX-29 (media and collaborators), BWX-38 (prompts and
-- reflections), BWX-47 (resurfacing log and mutes).
--
-- What lives here is what all of those assume exists: extensions, a schema
-- for helper functions the API must never expose, and the shared updated_at
-- trigger.

-- Extensions ----------------------------------------------------------------

-- Case-insensitive text for usernames and emails (BWX-10). Supabase keeps
-- extensions out of `public` so they are not reachable over the API; refer to
-- the type as `extensions.citext`.
create extension if not exists citext with schema extensions;

-- Helper schema -------------------------------------------------------------

-- PostgREST only exposes `public` and `graphql_public`, so anything in
-- `private` is callable from triggers and from security-definer functions but
-- never from a client. Helpers that bypass RLS belong here, not in `public`.
create schema if not exists private;

revoke all on schema private from anon, authenticated;
grant usage on schema private to postgres, service_role;

-- updated_at ----------------------------------------------------------------

-- Tables with an `updated_at` column attach this trigger so the value comes
-- from the database rather than being trusted from the client:
--
--   create trigger set_updated_at before update on public.<table>
--     for each row execute function private.set_updated_at();
create or replace function private.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function private.set_updated_at() is
  'Trigger function: stamps updated_at = now() on UPDATE.';

-- Conventions for the migrations that follow ---------------------------------
--
--   * Primary keys are uuid, defaulting to gen_random_uuid().
--   * Timestamps are timestamptz. Snapshots also carry their own timezone
--     (BWX-14), because a memory's local time is part of the memory.
--   * Every table in `public` runs `alter table ... enable row level
--     security` in the same migration that creates it. A table with RLS on
--     and no policies denies everything, which is the safe way to land.
