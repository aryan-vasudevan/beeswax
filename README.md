# Beeswax

Shared memories, as snapshots. One Expo app for iOS, Android and web, backed by
Supabase.

## Layout

```
apps/app/    Expo app (Expo Router, TypeScript)
packages/    shared code, as it appears
supabase/    migrations and local stack config -- see docs/database.md
```

npm workspaces. Run everything from the repo root.

## Getting started

```sh
npm install
cp .env.example .env    # fill in from `supabase status`
supabase start
npm start               # then press i, a or w
```

## Checks

```sh
npm run typecheck
npm run lint
npm run format:check    # npm run format to fix
```

Add dependencies to the app with `npx expo install <pkg>` from `apps/app`, so
versions match the Expo SDK.
