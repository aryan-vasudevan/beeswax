-- Media: photos, videos and voice memories in a snapshot (BWX-29), each
-- with its own audience set by whoever added it (BWX-90).
--
--   media_item       one contribution: who added it, what it is, when it was
--                    captured, who may see it
--   media_location   where it was captured -- only for insiders, never for
--                    people seeing a public snapshot through its link
--   storage bucket   `media`, private; every read is checked against
--                    media_item's row-level security
--
-- Rules (docs/product.md, sections 3, 6 and 7):
--
-- * Owning a snapshot never means owning its media. Each item belongs to its
--   contributor: they edit its caption, dates and audience, and delete it.
--   Owners and editors may hide an item (moderation) but cannot delete,
--   re-caption or republish it.
-- * Every item has an audience: 'members' (default) or 'public_ok'. A public
--   snapshot shows strangers only the public_ok items. Switching a snapshot
--   to public therefore never publishes anyone's media -- they opt in, item
--   by item.
-- * Precise location is personal data. It lives in media_location, readable
--   only by the snapshot's owner, members and custom audience.
-- * Items are authored by a person, not only an account, so relatives
--   without accounts can contribute through guest links later (BWX-63).
--
-- Upload flow (BWX-30):
--   1. The app inserts a media_item (status 'pending') with a client-made
--      idempotency key, so a retried request never creates a duplicate.
--   2. It uploads the file to media/<snapshot_id>/<item_id>/original.<ext>.
--      Storage only accepts that path from the item's uploader while the
--      item is pending.
--   3. It calls finish_media_upload(), which checks the file is there and
--      marks the item ready. Thumbnails and EXIF extraction (BWX-31) fill
--      in later. Pending items older than a day are cleaned up by a job.

-- Types -----------------------------------------------------------------------

create type public.media_kind as enum ('photo', 'video', 'audio');
create type public.media_status as enum ('pending', 'ready', 'failed');
create type public.media_audience as enum ('members', 'public_ok');

-- Optional hard cap on items per contributor. Off (null) by default: the
-- normal experience asks for your best moments, it does not count them.
alter table public.snapshot
  add column contribution_cap integer
    constraint contribution_cap_positive check (contribution_cap > 0);

grant update (contribution_cap) on public.snapshot to authenticated;

-- media_item ----------------------------------------------------------------

create table public.media_item (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.snapshot (id) on delete cascade,
  -- Who it is by. For an account, their self person; for a guest
  -- contribution (BWX-63), the identity the guest link was made for.
  contributor_person_id uuid not null references public.person (id),
  -- The account that uploaded it, if any. Null for guests, and once that
  -- account is deleted (BWX-69 decides whether the item stays).
  uploaded_by uuid default auth.uid() references public.account (id) on delete set null,
  kind public.media_kind not null,
  status public.media_status not null default 'pending',
  -- Set by the client per file; a retried insert with the same key is
  -- refused instead of duplicating the item.
  idempotency_key uuid not null,
  mime_type text not null
    constraint mime_type_matches_kind check (
      (kind = 'photo' and mime_type in ('image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp'))
      or (kind = 'video' and mime_type in ('video/mp4', 'video/quicktime'))
      or (kind = 'audio' and mime_type in ('audio/mp4', 'audio/m4a', 'audio/aac', 'audio/mpeg'))
    ),
  byte_size bigint constraint byte_size_positive check (byte_size > 0),
  original_filename text constraint original_filename_length check (char_length(original_filename) <= 255),
  caption text constraint caption_length check (char_length(caption) <= 2000),
  -- When it was captured. 'estimated' means it came from the snapshot's
  -- date or a guess, not the file -- shown as such and correctable (BWX-92).
  captured_at timestamptz,
  captured_at_estimated boolean not null default false,
  timezone text,
  width integer constraint width_positive check (width > 0),
  height integer constraint height_positive check (height > 0),
  duration_ms integer constraint duration_positive check (duration_ms > 0),
  audience public.media_audience not null default 'members',
  -- Moderation by an owner or editor. Hidden items are seen only by their
  -- contributor (and the moderators).
  hidden_at timestamptz,
  hidden_by uuid references public.account (id) on delete set null,
  -- Removed by the contributor. Gone for everyone at once; purged with its
  -- files after 30 days.
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (uploaded_by, idempotency_key)
);

comment on table public.media_item is
  'Photos, videos and voice memories. Each belongs to its contributor, not the snapshot owner.';

create index media_item_snapshot on public.media_item (snapshot_id, captured_at);
create index media_item_contributor on public.media_item (contributor_person_id);
create index media_item_uploaded_by on public.media_item (uploaded_by);
create index media_item_hidden_by on public.media_item (hidden_by);
create index media_item_pending on public.media_item (created_at) where status = 'pending';

create trigger set_updated_at before update on public.media_item
  for each row execute function private.set_updated_at();

alter table public.media_item enable row level security;

-- media_location ------------------------------------------------------------

create table public.media_location (
  media_id uuid primary key references public.media_item (id) on delete cascade,
  latitude double precision not null
    constraint latitude_range check (latitude between -90 and 90),
  longitude double precision not null
    constraint longitude_range check (longitude between -180 and 180),
  -- True if it came from the file's GPS rather than the contributor.
  from_exif boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.media_location is
  'Where a media item was captured. Readable only by the snapshot''s insiders.';

create trigger set_updated_at before update on public.media_location
  for each row execute function private.set_updated_at();

alter table public.media_location enable row level security;

-- Cover ---------------------------------------------------------------------

alter table public.snapshot
  add column cover_media_id uuid references public.media_item (id) on delete set null;

create index snapshot_cover_media_id on public.snapshot (cover_media_id);

grant update (cover_media_id) on public.snapshot to authenticated;

-- Helpers -------------------------------------------------------------------

-- True if the caller sees a snapshot as an insider -- owner, member, or
-- custom audience -- rather than as a stranger holding a public link.
create function private.is_snapshot_insider(p_snapshot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.snapshot_role(p_snapshot_id) is not null
    or exists (
      select 1
      from public.snapshot s
      join public.snapshot_audience a on a.snapshot_id = s.id
      where s.id = p_snapshot_id
        and s.visibility = 'custom'
        and s.deleted_at is null
        and a.account_id = (select auth.uid())
    );
$$;

-- True if the caller may see this media item: they can see its snapshot;
-- it is ready and not deleted (or it is theirs); it is not hidden (or they
-- added it, or they moderate the snapshot); and strangers on a public link
-- only get public_ok items.
create function private.can_view_media(p_media_id uuid)
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
        )
      )
  );
$$;

revoke execute on function private.is_snapshot_insider(uuid) from public;
revoke execute on function private.can_view_media(uuid) from public;
grant execute on function private.is_snapshot_insider(uuid) to authenticated;
grant execute on function private.can_view_media(uuid) to authenticated;

-- Triggers ------------------------------------------------------------------

-- On insert: the contributor is the uploader's self person, and the cap,
-- if the owner set one, holds.
create function private.prepare_media_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cap integer;
  used integer;
begin
  if new.uploaded_by is not null then
    select id into new.contributor_person_id
    from public.person
    where account_id = new.uploaded_by and created_by = new.uploaded_by;
  end if;

  select contribution_cap into cap from public.snapshot where id = new.snapshot_id;
  if cap is not null then
    select count(*) into used
    from public.media_item
    where snapshot_id = new.snapshot_id
      and contributor_person_id = new.contributor_person_id
      and deleted_at is null;
    if used >= cap then
      raise exception 'This memory is limited to % items per person', cap
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.prepare_media_item() is
  'Trigger function: sets the contributor from the uploader and enforces any contribution cap.';

create trigger prepare_media_item
  before insert on public.media_item
  for each row execute function private.prepare_media_item();

-- On update: the contributor decides what the item says and who sees it;
-- moderators decide only whether it is hidden. Server-side jobs (no user)
-- are not restricted.
create function private.check_media_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    return new;
  end if;

  if new.uploaded_by is distinct from me and (
    new.caption is distinct from old.caption
    or new.captured_at is distinct from old.captured_at
    or new.captured_at_estimated is distinct from old.captured_at_estimated
    or new.timezone is distinct from old.timezone
    or new.audience is distinct from old.audience
    or new.deleted_at is distinct from old.deleted_at
  ) then
    raise exception 'Only the person who added this can change it' using errcode = '42501';
  end if;

  if new.hidden_at is distinct from old.hidden_at then
    if coalesce(private.snapshot_role(new.snapshot_id) >= 'editor', false) is false then
      raise exception 'Only owners and editors can hide items' using errcode = '42501';
    end if;
    new.hidden_by = case when new.hidden_at is null then null else me end;
  end if;

  return new;
end;
$$;

comment on function private.check_media_change() is
  'Trigger function: contributor-only fields stay with the contributor; hiding stays with moderators.';

create trigger check_media_change
  before update on public.media_item
  for each row execute function private.check_media_change();

-- The cover must be a ready, visible item from the same snapshot that
-- anyone who can see the snapshot can see. A members-only item would be a
-- blank cell for strangers on a public link, so a public snapshot's cover
-- must be public_ok. Choosing an unsuitable cover is refused; making a
-- snapshot public quietly drops a cover that no longer qualifies.
create function private.check_snapshot_cover()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  suitable boolean;
begin
  if new.cover_media_id is null then
    return new;
  end if;

  select exists (
    select 1 from public.media_item m
    where m.id = new.cover_media_id
      and m.snapshot_id = new.id
      and m.status = 'ready'
      and m.deleted_at is null
      and m.hidden_at is null
      and (new.visibility <> 'public' or m.audience = 'public_ok')
  ) into suitable;

  if suitable then
    return new;
  end if;

  if tg_op = 'INSERT' or new.cover_media_id is distinct from old.cover_media_id then
    raise exception 'The cover must be a visible item from this memory' using errcode = '23514';
  end if;

  new.cover_media_id = null;
  return new;
end;
$$;

comment on function private.check_snapshot_cover() is
  'Trigger function: keeps the cover to a ready, visible item of the same snapshot.';

create trigger check_snapshot_cover
  before update of cover_media_id, visibility on public.snapshot
  for each row execute function private.check_snapshot_cover();

-- An item that stops being suitable stops being the cover.
create function private.release_cover()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.snapshot s
  set cover_media_id = null
  where s.cover_media_id = new.id
    and (
      new.deleted_at is not null
      or new.hidden_at is not null
      or new.status <> 'ready'
      or (new.audience = 'members' and s.visibility = 'public')
    );
  return new;
end;
$$;

comment on function private.release_cover() is
  'Trigger function: clears a snapshot cover when its item is deleted, hidden or no longer public.';

create trigger release_cover
  after update on public.media_item
  for each row execute function private.release_cover();

-- Policies: media_item ------------------------------------------------------

create policy "Users can read media they may see"
  on public.media_item for select to authenticated
  using (uploaded_by = (select auth.uid()) or private.can_view_media(id));

-- Contributors and up add their own items.
create policy "Contributors can add media"
  on public.media_item for insert to authenticated
  with check (
    uploaded_by = (select auth.uid())
    and status = 'pending'
    and private.snapshot_role(snapshot_id) >= 'contributor'
  );

-- Contributors edit their own items; moderators may update (to hide). The
-- trigger above decides which columns each may touch.
create policy "Contributors and moderators can update media"
  on public.media_item for update to authenticated
  using (
    uploaded_by = (select auth.uid())
    or private.snapshot_role(snapshot_id) >= 'editor'
  )
  with check (
    uploaded_by = (select auth.uid())
    or private.snapshot_role(snapshot_id) >= 'editor'
  );

revoke insert, update, delete on public.media_item from anon, authenticated;
grant insert (
  snapshot_id, kind, idempotency_key, mime_type, byte_size, original_filename,
  caption, captured_at, captured_at_estimated, timezone, width, height,
  duration_ms, audience
) on public.media_item to authenticated;
grant update (
  caption, captured_at, captured_at_estimated, timezone, audience, deleted_at, hidden_at
) on public.media_item to authenticated;

-- Policies: media_location --------------------------------------------------

create policy "Insiders can read where media was captured"
  on public.media_location for select to authenticated
  using (
    exists (
      select 1 from public.media_item m
      where m.id = media_id
        and (
          m.uploaded_by = (select auth.uid())
          or (private.is_snapshot_insider(m.snapshot_id) and private.can_view_media(m.id))
        )
    )
  );

create policy "Contributors can set where their media was captured"
  on public.media_location for insert to authenticated
  with check (
    exists (
      select 1 from public.media_item m
      where m.id = media_id and m.uploaded_by = (select auth.uid())
    )
  );

create policy "Contributors can correct where their media was captured"
  on public.media_location for update to authenticated
  using (exists (
    select 1 from public.media_item m
    where m.id = media_id and m.uploaded_by = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.media_item m
    where m.id = media_id and m.uploaded_by = (select auth.uid())
  ));

create policy "Contributors can remove where their media was captured"
  on public.media_location for delete to authenticated
  using (exists (
    select 1 from public.media_item m
    where m.id = media_id and m.uploaded_by = (select auth.uid())
  ));

revoke insert, update on public.media_location from anon, authenticated;
grant insert (media_id, latitude, longitude, from_exif) on public.media_location to authenticated;
grant update (latitude, longitude) on public.media_location to authenticated;

-- Finishing an upload -------------------------------------------------------

-- Called by the uploader after the file is in storage. Marks the item ready
-- if its original is there; otherwise refuses, so a half-finished upload
-- never shows as a broken cell.
create function public.finish_media_upload(p_media_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  item public.media_item;
begin
  select * into item from public.media_item where id = p_media_id for update;

  if item.id is null or item.uploaded_by is distinct from (select auth.uid()) then
    raise exception 'Upload not found' using errcode = 'P0002';
  end if;
  if item.status <> 'pending' then
    return;
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'media'
      and o.name like item.snapshot_id::text || '/' || item.id::text || '/original.%'
  ) then
    raise exception 'The file has not finished uploading' using errcode = '22023';
  end if;

  update public.media_item set status = 'ready' where id = item.id;
end;
$$;

comment on function public.finish_media_upload(uuid) is
  'Mark a pending media item ready once its original file is in storage.';

revoke execute on function public.finish_media_upload(uuid) from public, anon;
grant execute on function public.finish_media_upload(uuid) to authenticated;

-- Storage -------------------------------------------------------------------

-- Private bucket. Declared here so local, CI and the hosted project all get
-- it from the same migration. 50 MiB is the Free plan's per-file ceiling;
-- longer videos need Pro (BWX-116).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'media', 'media', false, 52428800,
  array[
    'image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp',
    'video/mp4', 'video/quicktime',
    'audio/mp4', 'audio/m4a', 'audio/aac', 'audio/mpeg'
  ]
)
on conflict (id) do nothing;

-- Object names are <snapshot_id>/<media_id>/<file>. The id in the second
-- segment ties every object to a media_item row, and the row's policies
-- decide who may touch the file.
create function private.media_id_from_path(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when split_part(p_name, '/', 2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(p_name, '/', 2)::uuid
  end;
$$;

grant execute on function private.media_id_from_path(text) to authenticated;

create policy "Media files are readable when their item is"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'media'
    and exists (
      select 1 from public.media_item m
      where m.id = private.media_id_from_path(name)
    )
  );

-- Only the uploader, only while the item is pending, only its original.
-- Thumbnails and previews are written by the processing job (BWX-31).
create policy "Uploaders can store their pending original"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'media'
    and exists (
      select 1 from public.media_item m
      where m.id = private.media_id_from_path(name)
        and m.uploaded_by = (select auth.uid())
        and m.status = 'pending'
        and name like m.snapshot_id::text || '/' || m.id::text || '/original.%'
    )
  );
