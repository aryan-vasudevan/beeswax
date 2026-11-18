-- Suggested moments (BWX-96) and honey (BWX-44).
--
-- Both are deterministic: no models, just capture times and counts. AI can
-- refine later (docs/product.md, section 8: deterministic metadata first).

-- Suggested moments -----------------------------------------------------------

-- Groups a snapshot's unplaced photos and videos into suggested moments by
-- capture time: a gap longer than p_gap (90 minutes by default) starts a
-- new moment. Groups of fewer than two items stay unplaced -- one photo is
-- not yet a moment.
--
-- Suggestions are just that: status 'suggested', seen only by editors, and
-- their items read as unplaced to everyone else until an editor confirms.
-- Running again replaces earlier unconfirmed suggestions, and never
-- re-suggests a stretch of time an editor already dismissed.
--
-- Items with no capture time, or only an estimated one, are left out:
-- clustering a guess would present it as fact.
--
-- Returns how many moments were suggested. Owners and editors can run it;
-- so can server-side jobs (no user).
create function public.suggest_moments(p_snapshot_id uuid, p_gap interval default interval '90 minutes')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  grp record;
  new_moment uuid;
  made integer := 0;
begin
  if (select auth.uid()) is not null
    and coalesce(private.snapshot_role(p_snapshot_id) >= 'editor', false) is false
  then
    raise exception 'Only owners and editors can suggest moments' using errcode = '42501';
  end if;

  -- Replace earlier, unconfirmed suggestions. Their items fall back to
  -- unplaced through the foreign key.
  delete from public.snapshot_moment
  where snapshot_id = p_snapshot_id and status = 'suggested';

  for grp in
    with items as (
      select id, captured_at
      from public.media_item
      where snapshot_id = p_snapshot_id
        and status = 'ready'
        and deleted_at is null
        and moment_id is null
        and captured_at is not null
        and not captured_at_estimated
    ),
    marked as (
      select id, captured_at,
        case
          when lag(captured_at) over (order by captured_at, id) is null
            or captured_at - lag(captured_at) over (order by captured_at, id) > p_gap
          then 1 else 0
        end as starts_new
      from items
    ),
    grouped as (
      select id, captured_at,
        sum(starts_new) over (order by captured_at, id) as cluster_no
      from marked
    )
    select min(captured_at) as starts_at, max(captured_at) as ends_at, array_agg(id) as item_ids
    from grouped
    group by cluster_no
    having count(*) >= 2
    order by min(captured_at)
  loop
    continue when exists (
      select 1 from public.snapshot_moment
      where snapshot_id = p_snapshot_id
        and status = 'dismissed'
        and coalesce(starts_at, '-infinity') <= grp.ends_at
        and coalesce(ends_at, 'infinity') >= grp.starts_at
    );

    insert into public.snapshot_moment (snapshot_id, starts_at, ends_at, position, status, created_by)
    values (
      p_snapshot_id, grp.starts_at, grp.ends_at,
      extract(epoch from grp.starts_at), 'suggested', null
    )
    returning id into new_moment;

    update public.media_item set moment_id = new_moment where id = any(grp.item_ids);
    made := made + 1;
  end loop;

  return made;
end;
$$;

comment on function public.suggest_moments(uuid, interval) is
  'Suggest moments by clustering unplaced media on capture time. Suggestions need an editor''s confirmation.';

revoke execute on function public.suggest_moments(uuid, interval) from public, anon;
grant execute on function public.suggest_moments(uuid, interval) to authenticated;

-- Dismissing a moment unplaces what was in it. The moment row stays, as a
-- record that this stretch of time was looked at and rejected.
create function private.unplace_dismissed_moment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.media_item set moment_id = null where moment_id = new.id;
  update public.recollection set moment_id = null where moment_id = new.id;
  return new;
end;
$$;

comment on function private.unplace_dismissed_moment() is
  'Trigger function: when a moment is dismissed, its media and recollections become unplaced.';

create trigger unplace_dismissed_moment
  after update of status on public.snapshot_moment
  for each row when (new.status = 'dismissed' and old.status <> 'dismissed')
  execute function private.unplace_dismissed_moment();

-- Honey -----------------------------------------------------------------------

-- How full each cell is, for the hive. The people in a memory are its
-- participants plus its members; honey is the share of them who have added
-- something the caller can see. Counts never include what the caller is not
-- allowed to see, so honey can't be used to detect hidden contributions.
--
-- Takes many snapshots at once (up to 500) because the hive asks for a
-- screenful of cells in one go. Snapshots the caller can't see are skipped.
create function public.snapshot_honey(p_snapshot_ids uuid[])
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
      and private.can_view_contribution(
        mi.snapshot_id, mi.uploaded_by, true, mi.deleted_at, mi.hidden_at, mi.audience)
    union
    select r.snapshot_id, r.author_person_id
    from public.recollection r
    join wanted on wanted.id = r.snapshot_id
    where r.deleted_at is null
      and private.can_view_contribution(
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

comment on function public.snapshot_honey(uuid[]) is
  'Honey for hive cells: the share of a memory''s people who have added something the caller can see.';

revoke execute on function public.snapshot_honey(uuid[]) from public, anon;
grant execute on function public.snapshot_honey(uuid[]) to authenticated;
