# Beeswax

Shared memories, as snapshots. One Expo app for iOS, Android and web, backed by
Supabase.

## Layout

```
apps/app/    Expo app (Expo Router, TypeScript) -- design system in docs/design.md
packages/    shared code, as it appears
supabase/    migrations and local stack config -- see docs/database.md
```

npm workspaces. Run everything from the repo root.

## Getting started

```sh
npm install
cp apps/app/.env.example apps/app/.env    # fill in from `supabase status`
supabase start          # then sign in as alice@beeswax.test / password123
npm start               # then press i, a or w
```

## Checks

```sh
npm run typecheck
npm run lint
npm run check:contrast  # the palette against WCAG AA
npm run test            # jest, via jest-expo
npm run format:check    # npm run format to fix
```

Add dependencies to the app with `npx expo install <pkg>` from `apps/app`, so
versions match the Expo SDK.

The root `package.json` pins `react` through `overrides`. Without it, adding a
package that accepts `react@^19` lets npm hoist a newer React beside the one the
SDK pins, and two copies of React in one bundle break hooks. Update the override
and `apps/app`'s `react` together when the SDK moves.

### Tests

Jest with the `jest-expo` preset. Tests live in `apps/app/src/__tests__/`,
outside `src/app/` because every file in there is a route. Note that `render`
from `@testing-library/react-native` is async:

```tsx
const { getByText } = await render(<Home />);
```

## CI

Two workflows run on every PR and on pushes to `main`:

- **ci** — `typecheck`, `lint`, `format:check` and `test` as four parallel jobs,
  plus a `web build` job that exports the static web bundle. On PRs it then
  deploys that bundle to EAS Hosting and comments the URL.
- **supabase** — applies every migration to an empty database in order, then
  lints the result. This is the only thing between a broken migration and the
  live database, so keep it green.

Both are worth marking as required checks on `main`, which is not protected yet.

### Enabling web previews

The `web preview` job no-ops with a notice until two things exist:

1. An EAS project linked to this repo — run `npx eas-cli@latest init` from
   `apps/app`, which writes `extra.eas.projectId` into `app.json`.
2. An `EXPO_TOKEN` repository secret — create a token under
   [Expo access tokens](https://expo.dev/settings/access-tokens) and add it at
   Settings → Secrets and variables → Actions.

Each PR then gets a `pr-<number>` alias, redeployed on every push.
