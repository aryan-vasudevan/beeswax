# Database

Supabase, with every schema change checked into this repo as a migration.
Nothing is changed by clicking around in the dashboard: if it is not in
`supabase/migrations/`, it does not exist.

## Layout

```
supabase/
  config.toml                  project + local stack config, and auth settings
  seed.sql                     seed data for local and preview branches
  migrations/
    <timestamp>_<name>.sql     applied in filename order, exactly once
```

The Supabase GitHub integration reads this directory. Its **working directory**
setting must be `.`, since `supabase/` sits at the repo root. If the Expo app
later moves `supabase/` under a workspace, that setting has to move with it.

## Environments

| Where | Database | How it gets migrations |
| --- | --- | --- |
| Local | Postgres in Docker, `supabase start` | `supabase db reset` |
| Shared | `beeswax` — ref `xpsztpxzfgwrbrwvtjks` | Supabase GitHub integration, on push to `main` |

There is deliberately no separate dev project. The Free plan allows two active
projects in total, and preview branches are Pro-only ($0.01344 per branch-hour),
so the per-PR database does not exist for us either. Until there are real users,
the one project is both dev and prod, and the thing that keeps it safe is the
CI check below rather than a second environment.

Day-to-day work happens against local Docker, which each of us runs
independently. The shared project is for testing the things local cannot show
you -- several people contributing to the same snapshot, auth against real
providers, a build running on an actual phone.

**When this needs to change:** the day the project holds data someone would be
upset to lose. At that point, create a *fresh* project, point the GitHub
integration at it, and let it become prod -- the current one is demoted to dev.
That swap is cheap precisely because the whole schema is in `migrations/`: the
new project gets it by replaying the folder. Do not promote a project that has
already been used as dev; its migration history will not match.

Two things are worth knowing about the integration, because they are easy to
assume wrong:

- **It only deploys to prod if "Deploy to production" is turned on.** Without
  it, pushes to the production branch do nothing and you only get PR preview
  branches.
- **On the production branch it applies migrations, Edge Functions declared in
  `config.toml`, and Storage buckets declared in `config.toml` — and nothing
  else.** The `[api]` and `[auth]` sections of `config.toml` and the seed file
  are ignored there. So the auth settings in `config.toml` shape local and
  preview only; the hosted projects keep whatever is set in their dashboards
  unless you opt them in with a `[remotes]` block (there is a commented
  template at the bottom of `config.toml`). If you do opt in, override the
  local-only values in the same block — a bare `[remotes.main]` inherits
  `site_url = "http://127.0.0.1:8081"` from the root config and breaks auth
  redirects in the hosted app.

Deploying from GitHub works on any plan; branching does not. Each commit runs
only the migrations that have not been applied yet.

## Local setup

Prerequisites:

- Docker (Docker Desktop, OrbStack, or Colima) — the local stack is containers.
- The Supabase CLI. `brew install supabase/tap/supabase`, or use
  `npx supabase@latest <command>` with no install.

```bash
supabase start          # first run pulls several GB of images
supabase db reset       # apply every migration from scratch, then seed.sql
supabase status         # prints the local URL and keys
```

Useful local endpoints: API on `http://127.0.0.1:54321`, Postgres on `54322`,
Studio on `http://127.0.0.1:54323`, and the mail viewer on
`http://127.0.0.1:54324` — signup confirmation emails land there rather than
being sent, which is what makes email verification testable locally.

Copy the `anon` key and API URL from `supabase status` into the app's `.env`
(see `.env.example`). The local keys are fixed and not secret.

## Making a schema change

```bash
supabase migration new add_snapshot_tables   # creates an empty timestamped file
# write the SQL by hand
supabase db reset                            # replay everything, including yours
git add supabase/migrations/<timestamp>_add_snapshot_tables.sql
```

Write migrations by hand rather than generating them from a database you edited
in Studio. `supabase db diff` is there if you need it, but a generated diff
tends to carry noise and loses the ordering you actually meant.

Two rules that keep the history replayable:

- **Never edit a migration that has been pushed.** The remote records which
  files it has applied; changing one after the fact means local and remote
  silently disagree. Fix it forward with a new migration.
- **Every migration must work on an empty database.** That is what CI checks.

## Deploying

Open a PR, let the `verify` job pass, merge to `main`. The Supabase integration
applies the new migrations to the project.

To do it by hand:

```bash
supabase link --project-ref <project-ref>
supabase db push --dry-run    # list what would be applied
supabase db push
```

### What has to be configured once

No GitHub secrets are needed -- the integration authenticates itself, and the
`verify` job only ever touches a throwaway database inside the runner.

In the Supabase dashboard, on the project connected to GitHub:

- Working directory: `.`
- Production branch: `main`
- Deploy to production: on

In GitHub → Settings → Branches, protect `main` and make **`verify`** a
required check. Note that this is the GitHub Actions job, not a Supabase check:
without branching there are no preview branches and so no Supabase status check
on PRs.

Confirm `major_version` in `config.toml` matches the hosted project. It is
currently `17`; check with `SHOW server_version;`, because `supabase db diff`
and the local stack both assume they agree.

## Conventions

The first migration, `*_foundations.sql`, sets up what the rest assume:

- `citext` for case-insensitive usernames and emails. It lives in the
  `extensions` schema, so the type is `extensions.citext`.
- A `private` schema for helper functions. PostgREST only exposes `public` and
  `graphql_public`, so anything in `private` is unreachable from a client.
  Functions that bypass RLS belong there.
- `private.set_updated_at()`, attached as a trigger to any table with an
  `updated_at` column, so the timestamp comes from the database rather than
  being trusted from the client.

For the migrations that follow:

- uuid primary keys, `default gen_random_uuid()`.
- `timestamptz` everywhere. Snapshots additionally store their own timezone,
  because the local time of a memory is part of the memory.
- `alter table ... enable row level security` in the same migration that
  creates the table. RLS on with no policies denies everything, which is the
  safe state to land in; the policies then open it deliberately.

`config.toml` leaves `auto_expose_new_tables` at the cloud default rather than
requiring explicit grants. Turning it off would be stricter, but it is an
`[api]` setting, and `[api]` is ignored on the production branch — so local
would be strict while prod stayed permissive. RLS is the control that actually
applies in both places.

## Deferred

These are real decisions that belong to later tickets, not oversights:

- **PostGIS.** Not enabled. Place search and EXIF location can start as
  plain lat/lng columns; revisit if proximity queries need it.
- **Scheduling.** The daily resurfacing pick, the suggested-links job, and
  batched nudges all need a scheduler. `pg_cron` versus scheduled Edge
  Functions is open.
- **Storage buckets.** Buckets declared in `config.toml` are deployed by the
  integration, so media buckets should be declared there when that schema
  lands, not created by hand in the dashboard.
- **A separate prod project.** See "When this needs to change" above. Not
  needed before launch; needed the moment there is data worth protecting.
