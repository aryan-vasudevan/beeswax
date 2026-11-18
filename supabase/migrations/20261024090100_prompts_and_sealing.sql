-- Prompts (BWX-38), and sealing with reflections over the years (BWX-60).
--
--   prompt              the questions the app may ask: "What made this day
--                       special?", "Looking back, what do you notice now?"
--   prompt_dismissal    "not this one" -- per person, per memory, forever
--   recollection        gains kind 'reflection' and the prompt it answers
--   snapshot            gains sealed_at: the capped cell
--
-- Prompts (docs/product.md, Decision 7): optional, varied, dismissible.
-- Each person gets a few at a time, stable per memory so they don't shuffle
-- on every open, never one they dismissed or already answered there.
--
-- Sealing: the owner caps a cell and what it holds is frozen as it was --
-- details, moments, people, photos and stories. What sealing never freezes
-- is anyone's control over their own things: contributors can still delete
-- their items or change who sees them, people can still take themselves
-- out, editors can still hide, and the owner can still change visibility,
-- archive or delete. A seal preserves a memory; it doesn't trap anyone in
-- it. Members (contributor and up) keep adding reflections, which stack in
-- layers by the year they were written. The owner can unseal; both are
-- audited.

-- Prompts -------------------------------------------------------------------

create type public.prompt_use as enum (
  'recollection',  -- while a memory is fresh: what happened
  'reflection'     -- once it is sealed or a year old: looking back
);

create table public.prompt (
  -- A stable slug, so the app can translate it.
  id text primary key constraint id_format check (id ~ '^[a-z0-9_]{2,40}$'),
  use public.prompt_use not null,
  body text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.prompt is
  'Questions the app may ask about a memory (BWX-38). Managed by migrations.';

alter table public.prompt enable row level security;

create policy "Signed-in users can read prompts"
  on public.prompt for select to authenticated
  using (true);

revoke insert, update, delete on public.prompt from anon, authenticated;

insert into public.prompt (id, use, body) values
  ('special',          'recollection', 'What made this day special?'),
  ('funniest',         'recollection', 'What was the funniest thing that happened?'),
  ('unphotographed',   'recollection', 'What happened that nobody photographed?'),
  ('overheard',        'recollection', 'What did someone say that you still remember?'),
  ('almost_went_wrong','recollection', 'What almost went wrong?'),
  ('taste_sound',      'recollection', 'What did it sound, smell or taste like?'),
  ('first_noticed',    'recollection', 'What was the first thing you noticed when you got there?'),
  ('who_made_it',      'recollection', 'Who made it what it was?'),
  ('notice_now',       'reflection',   'Looking back, what do you notice now that you didn''t then?'),
  ('still_true',       'reflection',   'What from that day is still true?'),
  ('tell_them',        'reflection',   'What would you tell yourself from back then?'),
  ('who_since',        'reflection',   'Who from this memory do you still think about?'),
  ('changed',          'reflection',   'What has changed since?'),
  ('do_again',         'reflection',   'If you could go back for one hour of it, which hour?');

create table public.prompt_dismissal (
  account_id uuid not null default auth.uid() references public.account (id) on delete cascade,
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  prompt_id text not null references public.prompt (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (account_id, snapshot_id, prompt_id)
);

comment on table public.prompt_dismissal is
  'Prompts someone said "not this one" to, per memory. Visible only to them.';

create index prompt_dismissal_snapshot_id on public.prompt_dismissal (snapshot_id);
create index prompt_dismissal_prompt_id on public.prompt_dismissal (prompt_id);

alter table public.prompt_dismissal enable row level security;

create policy "Users can read their own dismissals"
  on public.prompt_dismissal for select to authenticated
  using (account_id = (select auth.uid()));

create policy "Users can dismiss prompts on memories they can see"
  on public.prompt_dismissal for insert to authenticated
  with check (account_id = (select auth.uid()) and private.can_view_snapshot(snapshot_id));

create policy "Users can undo their own dismissals"
  on public.prompt_dismissal for delete to authenticated
  using (account_id = (select auth.uid()));

revoke insert, update on public.prompt_dismissal from anon, authenticated;
grant insert (snapshot_id, prompt_id) on public.prompt_dismissal to authenticated;

-- What a recollection was answering, if anything.
alter table public.recollection
  add column prompt_id text references public.prompt (id) on delete set null;

create index recollection_prompt_id on public.recollection (prompt_id);

-- A reflection is about the whole memory from later on, not a moment in it.
alter table public.recollection
  add constraint reflection_not_in_moment check (kind <> 'reflection' or moment_id is null);

grant insert (prompt_id) on public.recollection to authenticated;

-- Sealing -------------------------------------------------------------------

alter table public.snapshot
  add column sealed_at timestamptz,
  add column sealed_by uuid references public.account (id) on delete set null;

create index snapshot_sealed_by on public.snapshot (sealed_by);

grant update (sealed_at) on public.snapshot to authenticated;

create function private.is_sealed(p_snapshot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select sealed_at is not null from public.snapshot where id = p_snapshot_id), false);
$$;

revoke execute on function private.is_sealed(uuid) from public, anon;
grant execute on function private.is_sealed(uuid) to authenticated;

-- Up to p_limit prompts for the caller on a memory: reflection prompts once
-- it is sealed or more than a year old, otherwise recollection prompts.
-- Never one they dismissed or already answered there. Ordered by a hash of
-- memory, person and prompt, so each person sees a different, stable set.
-- Only people who can write (contributor and up) are asked anything.
create function public.snapshot_prompts(p_snapshot_id uuid, p_limit integer default 3)
returns table (id text, use public.prompt_use, body text)
language sql
stable
security definer
set search_path = ''
as $$
  with s as (
    select
      case
        when sealed_at is not null
          or coalesce(starts_at, created_at) < now() - interval '1 year'
        then 'reflection'::public.prompt_use
        else 'recollection'::public.prompt_use
      end as use
    from public.snapshot
    where id = p_snapshot_id
      and coalesce(private.snapshot_role(p_snapshot_id) >= 'contributor', false)
  )
  select p.id, p.use, p.body
  from public.prompt p
  join s on s.use = p.use
  where p.active
    and not exists (
      select 1 from public.prompt_dismissal d
      where d.account_id = (select auth.uid())
        and d.snapshot_id = p_snapshot_id
        and d.prompt_id = p.id
    )
    and not exists (
      select 1 from public.recollection r
      where r.written_by = (select auth.uid())
        and r.snapshot_id = p_snapshot_id
        and r.prompt_id = p.id
        and r.deleted_at is null
    )
  order by md5(p_snapshot_id::text || (select auth.uid())::text || p.id)
  limit least(greatest(coalesce(p_limit, 3), 1), 5);
$$;

comment on function public.snapshot_prompts(uuid, integer) is
  'A few prompts for the caller on a memory: varied, stable, never dismissed or already answered.';

revoke execute on function public.snapshot_prompts(uuid, integer) from public, anon;
grant execute on function public.snapshot_prompts(uuid, integer) to authenticated;

-- Sealing and unsealing: owner only, published only, stamped and audited.
-- While sealed, what the memory says is frozen; who sees it, whether it is
-- archived or deleted, where it nests and who owns it are not. A cover can
-- still be cleared (it must, when its item stops being suitable) but not
-- changed. Server-side changes (no user) are not restricted.
create function private.check_snapshot_seal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if new.sealed_at is distinct from old.sealed_at then
    if me is not null and private.snapshot_role(old.id) is distinct from 'owner' then
      raise exception 'Only the owner can seal or unseal a memory' using errcode = '42501';
    end if;
    if new.sealed_at is not null then
      if new.status <> 'published' then
        raise exception 'Publish the memory before sealing it' using errcode = '22023';
      end if;
      if old.sealed_at is null then
        new.sealed_at = now();
        new.sealed_by = me;
      end if;
    else
      new.sealed_by = null;
    end if;
  end if;

  if me is not null
    and old.sealed_at is not null
    and new.sealed_at is not null
    and (
      new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.starts_at is distinct from old.starts_at
      or new.ends_at is distinct from old.ends_at
      or new.date_precision is distinct from old.date_precision
      or new.timezone is distinct from old.timezone
      or new.place_name is distinct from old.place_name
      or new.latitude is distinct from old.latitude
      or new.longitude is distinct from old.longitude
      or new.contribution_cap is distinct from old.contribution_cap
      or (new.cover_media_id is not null and new.cover_media_id is distinct from old.cover_media_id)
    )
  then
    raise exception 'This memory is sealed' using errcode = '55000';
  end if;

  return new;
end;
$$;

comment on function private.check_snapshot_seal() is
  'Trigger function: only owners seal; a sealed memory''s details are frozen.';

create trigger check_snapshot_seal
  before update on public.snapshot
  for each row execute function private.check_snapshot_seal();

create function private.audit_snapshot_seal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.snapshot_audit_log (snapshot_id, actor_id, action)
  values (new.id, (select auth.uid()),
    case when new.sealed_at is null then 'unsealed' else 'sealed' end);
  return null;
end;
$$;

comment on function private.audit_snapshot_seal() is
  'Trigger function: logs sealing and unsealing.';

create trigger audit_snapshot_seal
  after update of sealed_at on public.snapshot
  for each row when (new.sealed_at is distinct from old.sealed_at)
  execute function private.audit_snapshot_seal();

-- What a sealed memory holds stays as it was. Shared by the tables inside a
-- cell; columns are compared through jsonb so one function serves all.
--
--   media_item           no new items; existing ones may only change who
--                        sees them, be hidden, or be deleted (and a pending
--                        upload may finish)
--   recollection         only reflections may be added; other recollections
--                        may only change audience, be hidden or deleted;
--                        reflections stay their author's to edit
--   snapshot_moment      no changes at all
--   snapshot_participant no one added; anyone may still take themselves out
--
-- Clients cannot write the *_by columns; they are free here only so that
-- deleting an account can null them out on a sealed memory.
create function private.check_sealed_contents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  free_keys text[];
begin
  if (select auth.uid()) is null
    or not private.is_sealed((coalesce(row_new, row_old) ->> 'snapshot_id')::uuid)
  then
    return coalesce(new, old);
  end if;

  if tg_table_name = 'snapshot_participant' then
    if tg_op = 'DELETE' then
      return old;
    end if;
  elsif tg_table_name = 'recollection' then
    if row_new ->> 'kind' = 'reflection'
      and (tg_op = 'INSERT' or row_old ->> 'kind' = 'reflection')
    then
      return new;
    end if;
    free_keys := array['audience', 'hidden_at', 'hidden_by', 'deleted_at', 'updated_at', 'written_by'];
  elsif tg_table_name = 'media_item' then
    free_keys := array['audience', 'hidden_at', 'hidden_by', 'deleted_at', 'updated_at', 'status', 'uploaded_by'];
  elsif tg_table_name = 'snapshot_moment' then
    free_keys := array['created_by', 'updated_at'];
  end if;

  if tg_op = 'UPDATE'
    and free_keys is not null
    and (row_new - free_keys) = (row_old - free_keys)
  then
    return new;
  end if;

  raise exception 'This memory is sealed' using errcode = '55000';
end;
$$;

comment on function private.check_sealed_contents() is
  'Trigger function: freezes what a sealed memory holds, leaving people control of their own things.';

create trigger check_sealed_contents
  before insert or update on public.media_item
  for each row execute function private.check_sealed_contents();

create trigger check_sealed_contents
  before insert or update on public.recollection
  for each row execute function private.check_sealed_contents();

create trigger check_sealed_contents
  before insert or update or delete on public.snapshot_moment
  for each row execute function private.check_sealed_contents();

create trigger check_sealed_contents
  before insert or delete on public.snapshot_participant
  for each row execute function private.check_sealed_contents();

-- Buzz: reflections are counted as reflections ------------------------------

create or replace function private.buzz_contribution()
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
    what := case when item ->> 'kind' = 'reflection' then 'reflection' else 'recollection' end;
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
