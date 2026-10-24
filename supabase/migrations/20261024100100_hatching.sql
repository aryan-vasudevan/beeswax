-- Hatching (BWX-122): perspectives stay hidden until everyone's are in.
--
-- An owner can start a memory as brood: hatch_at is set, and until the cell
-- hatches each person sees only their own photos and stories. Honey still
-- fills -- people can see that others have added something, never what.
-- The cell hatches when every member who can contribute (contributor and
-- up, owner included) has added something, when the owner hatches it
-- early, or when hatch_at passes. Then everything appears at once, and
-- Buzz tells every member.
--
-- Why: whoever posts first shapes everyone else's memory. Hatching keeps
-- each account independent and makes the reveal a shared moment
-- (docs/product.md, "What only Beeswax does").
--
-- Rules:
-- * Start it before anyone else has added anything; hiding what people
--   have already seen would be strange and pointless.
-- * Owner only. hatch_at is at most 30 days out and can be moved while the
--   cell is unhatched; it cannot be cleared -- to end early, hatch it.
-- * Nothing un-hatches. A brood cell cannot be sealed.
-- * Visibility is decided by the clock (hatch_at <= now() counts as
--   hatched), so nothing stays hidden if the job is late. The job only
--   stamps hatched_at and sends the buzz.

alter table public.snapshot
  add column hatch_at timestamptz,
  add column hatched_at timestamptz,
  add constraint hatched_needs_hatch_at check (hatched_at is null or hatch_at is not null);

grant insert (hatch_at), update (hatch_at, hatched_at) on public.snapshot to authenticated;

create function private.is_brood(p_snapshot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select hatch_at is not null and hatched_at is null and hatch_at > now()
    from public.snapshot
    where id = p_snapshot_id
  ), false);
$$;

comment on function private.is_brood(uuid) is
  'True while a hatching memory has not hatched: contributions are visible only to their authors.';

revoke execute on function private.is_brood(uuid) from public, anon;
grant execute on function private.is_brood(uuid) to authenticated;

-- Visibility ----------------------------------------------------------------

-- The old rule, unchanged, under a new name: what the caller could see if
-- the memory were hatched. Honey uses it, so brood cells still fill.
create function private.can_view_contribution_when_hatched(
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

revoke execute on function private.can_view_contribution_when_hatched(uuid, uuid, boolean, timestamptz, timestamptz, public.media_audience) from public, anon;
grant execute on function private.can_view_contribution_when_hatched(uuid, uuid, boolean, timestamptz, timestamptz, public.media_audience) to authenticated;

-- In a brood cell, only your own.
create or replace function private.can_view_contribution(
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
  select private.can_view_contribution_when_hatched(
      p_snapshot_id, p_author_account, p_ready, p_deleted_at, p_hidden_at, p_audience)
    and (p_author_account = (select auth.uid()) or not private.is_brood(p_snapshot_id));
$$;

-- Media rows, their files and their locations all go through this.
create or replace function private.can_view_media(p_media_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.media_item m
    where m.id = p_media_id
      and private.can_view_snapshot(m.snapshot_id)
      and (
        m.uploaded_by = (select auth.uid())
        or (
          m.status = 'ready'
          and m.deleted_at is null
          and (m.hidden_at is null or private.snapshot_role(m.snapshot_id) >= 'editor')
          and (m.audience = 'public_ok' or private.is_snapshot_insider(m.snapshot_id))
          and not private.is_brood(m.snapshot_id)
        )
      )
  );
$$;

-- Honey counts what would be visible once hatched: a brood cell fills as
-- people add things, without showing any of it.
create or replace function public.snapshot_honey(p_snapshot_ids uuid[])
returns table (snapshot_id uuid, people integer, contributed integer, honey numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if cardinality(p_snapshot_ids) > 500 then
    raise exception 'Ask for at most 500 snapshots at a time' using errcode = '22023';
  end if;

  return query
  with wanted as (
    select distinct w.id
    from unnest(p_snapshot_ids) as w (id)
    where private.can_view_snapshot(w.id)
  ),
  people as (
    select sp.snapshot_id, sp.person_id
    from public.snapshot_participant sp
    join wanted on wanted.id = sp.snapshot_id
    union
    select m.snapshot_id, p.id
    from public.snapshot_member m
    join wanted on wanted.id = m.snapshot_id
    join public.person p on p.account_id = m.account_id and p.created_by = m.account_id
  ),
  contributions as (
    select mi.snapshot_id, mi.contributor_person_id as person_id
    from public.media_item mi
    join wanted on wanted.id = mi.snapshot_id
    where mi.status = 'ready'
      and mi.deleted_at is null
      and private.can_view_contribution_when_hatched(
        mi.snapshot_id, mi.uploaded_by, true, mi.deleted_at, mi.hidden_at, mi.audience)
    union
    select r.snapshot_id, r.author_person_id
    from public.recollection r
    join wanted on wanted.id = r.snapshot_id
    where r.deleted_at is null
      and private.can_view_contribution_when_hatched(
        r.snapshot_id, r.written_by, true, r.deleted_at, r.hidden_at, r.audience)
  ),
  counted as (
    select
      wanted.id,
      (select count(*) from people pe where pe.snapshot_id = wanted.id)::integer as people,
      (select count(*) from people pe
        where pe.snapshot_id = wanted.id
          and exists (
            select 1 from contributions c
            where c.snapshot_id = wanted.id and c.person_id = pe.person_id
          ))::integer as contributed
    from wanted
  )
  select
    counted.id,
    counted.people,
    counted.contributed,
    case when counted.people = 0 then 0
      else round(counted.contributed::numeric / counted.people, 2)
    end
  from counted;
end;
$$;

-- Rules on the snapshot -----------------------------------------------------

create function private.check_snapshot_hatch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  by_job boolean := coalesce(current_setting('beeswax.hatching', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    if me is not null and new.hatch_at is not null
      and (new.hatch_at <= now() or new.hatch_at > now() + interval '30 days')
    then
      raise exception 'A memory hatches between now and 30 days from now' using errcode = '22023';
    end if;
    return new;
  end if;

  if new.hatch_at is distinct from old.hatch_at and me is not null then
    if private.snapshot_role(old.id) is distinct from 'owner' then
      raise exception 'Only the owner can decide when a memory hatches' using errcode = '42501';
    end if;
    if new.hatch_at is null then
      raise exception 'Hatching cannot be turned off; hatch it now instead' using errcode = '22023';
    end if;
    if old.hatched_at is not null or old.hatch_at <= now() then
      raise exception 'This memory has already hatched' using errcode = '22023';
    end if;
    if new.hatch_at <= now() or new.hatch_at > now() + interval '30 days' then
      raise exception 'A memory hatches between now and 30 days from now' using errcode = '22023';
    end if;
    if old.hatch_at is null and (
      exists (
        select 1 from public.media_item
        where snapshot_id = old.id and uploaded_by is distinct from me and deleted_at is null
      )
      or exists (
        select 1 from public.recollection
        where snapshot_id = old.id and written_by is distinct from me and deleted_at is null
      )
    ) then
      raise exception 'Hatching has to start before anyone else adds something' using errcode = '22023';
    end if;
  end if;

  if new.hatched_at is distinct from old.hatched_at then
    if old.hatched_at is not null then
      raise exception 'A hatched memory stays hatched' using errcode = '22023';
    end if;
    if new.hatch_at is null then
      raise exception 'This memory is not hatching' using errcode = '22023';
    end if;
    if me is not null and not by_job and private.snapshot_role(old.id) is distinct from 'owner' then
      raise exception 'Only the owner can hatch a memory early' using errcode = '42501';
    end if;
    new.hatched_at = now();
  end if;

  if new.sealed_at is not null and old.sealed_at is null
    and new.hatch_at is not null and new.hatched_at is null and new.hatch_at > now()
  then
    raise exception 'Let the memory hatch before sealing it' using errcode = '22023';
  end if;

  return new;
end;
$$;

comment on function private.check_snapshot_hatch() is
  'Trigger function: owner-only hatching rules; nothing un-hatches, brood cannot be sealed.';

create trigger check_snapshot_hatch
  before insert or update on public.snapshot
  for each row execute function private.check_snapshot_hatch();

-- Hatching buzzes every member once.
create function private.buzz_hatched()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.buzz(m.account_id, 'hatched', new.id, (select auth.uid()))
  from public.snapshot_member m
  where m.snapshot_id = new.id;
  return null;
end;
$$;

comment on function private.buzz_hatched() is
  'Trigger function: tells every member a memory has hatched.';

create trigger buzz_hatched
  after update of hatched_at on public.snapshot
  for each row when (old.hatched_at is null and new.hatched_at is not null)
  execute function private.buzz_hatched();

-- Hatching when everyone is in ----------------------------------------------

-- After each new contribution to a brood cell: if every member who can
-- contribute has now added something, it hatches.
create function private.hatch_when_complete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sid uuid := (to_jsonb(new) ->> 'snapshot_id')::uuid;
begin
  if tg_table_name = 'media_item' and to_jsonb(new) ->> 'status' <> 'ready' then
    return null;
  end if;
  if not private.is_brood(sid) then
    return null;
  end if;

  if not exists (
    select 1 from public.snapshot_member m
    where m.snapshot_id = sid
      and m.role >= 'contributor'
      and not exists (
        select 1 from public.media_item i
        where i.snapshot_id = sid and i.uploaded_by = m.account_id
          and i.status = 'ready' and i.deleted_at is null
      )
      and not exists (
        select 1 from public.recollection r
        where r.snapshot_id = sid and r.written_by = m.account_id and r.deleted_at is null
      )
  ) then
    perform set_config('beeswax.hatching', 'on', true);
    update public.snapshot set hatched_at = now() where id = sid;
    perform set_config('beeswax.hatching', 'off', true);
  end if;

  return null;
end;
$$;

comment on function private.hatch_when_complete() is
  'Trigger function: hatches a brood memory once every contributor has added something.';

create trigger hatch_when_complete
  after insert or update of status on public.media_item
  for each row execute function private.hatch_when_complete();

create trigger hatch_when_complete
  after insert on public.recollection
  for each row execute function private.hatch_when_complete();

-- Hatching on time ----------------------------------------------------------

-- Stamps memories whose hatch_at has passed, which sends their buzz. They
-- are already visible -- this only makes it official. Runs every five
-- minutes under pg_cron; returns how many hatched.
create function private.hatch_due_snapshots()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  perform set_config('beeswax.hatching', 'on', true);
  update public.snapshot
  set hatched_at = now()
  where hatch_at <= now() and hatched_at is null and deleted_at is null;
  get diagnostics n = row_count;
  perform set_config('beeswax.hatching', 'off', true);
  return n;
end;
$$;

comment on function private.hatch_due_snapshots() is
  'Job: stamps memories whose hatch time has passed and buzzes their members.';

revoke execute on function private.hatch_due_snapshots() from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule('hatch-due-snapshots', '*/5 * * * *', 'select private.hatch_due_snapshots()');
