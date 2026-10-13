-- Seed data for local development and preview branches.
--
-- Test users for signing in locally. All use the password `password123`.
--
--   alice@beeswax.test   username alice
--   bob@beeswax.test     username bob
--   carol@beeswax.test   username carol
--
-- Seed rows for a feature belong with the migration that creates its tables;
-- add them here when that migration lands. Keep this file idempotent -- it is
-- re-run on every `supabase db reset`.

-- Users ---------------------------------------------------------------------

-- The sign-up trigger creates each account, self person and settings row.
-- GoTrue needs the empty-string token columns and an auth.identities row to
-- let these users sign in with a password.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
  u.email, extensions.crypt('password123', extensions.gen_salt('bf')), now(),
  '{"provider": "email", "providers": ["email"]}',
  jsonb_build_object('username', u.username, 'display_name', u.display_name),
  now(), now(), '', '', '', ''
from (values
  ('a1111111-1111-1111-1111-111111111111'::uuid, 'alice@beeswax.test', 'alice', 'Alice Seed'),
  ('b2222222-2222-2222-2222-222222222222'::uuid, 'bob@beeswax.test', 'bob', 'Bob Seed'),
  ('c3333333-3333-3333-3333-333333333333'::uuid, 'carol@beeswax.test', 'carol', 'Carol Seed')
) as u (id, email, username, display_name)
on conflict (id) do nothing;

insert into auth.identities (
  id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(), u.id, u.id::text, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  now(), now(), now()
from auth.users u
where u.email like '%@beeswax.test'
on conflict (provider_id, provider) do nothing;

-- People --------------------------------------------------------------------

-- Alice's people: Bob and Carol, plus two family members without accounts.
insert into public.person (id, created_by, display_name) values
  ('d4444444-4444-4444-4444-444444444444', 'a1111111-1111-1111-1111-111111111111', 'Grandma Noor'),
  ('e5555555-5555-5555-5555-555555555555', 'a1111111-1111-1111-1111-111111111111', 'Uncle Sami')
on conflict (id) do nothing;

insert into public.relationship (account_id, person_id, label)
select 'a1111111-1111-1111-1111-111111111111'::uuid, p.id, r.label::public.relationship_label
from (values
  ('bob', 'friend'),
  ('carol', 'classmate')
) as r (username, label)
join public.account a on a.username = r.username
join public.person p on p.account_id = a.id and p.created_by = a.id
union all
select 'a1111111-1111-1111-1111-111111111111'::uuid, id, 'family'::public.relationship_label
from public.person
where id in ('d4444444-4444-4444-4444-444444444444', 'e5555555-5555-5555-5555-555555555555')
on conflict (account_id, person_id) do nothing;
