# Design

The hive's design system: the colours, type and spacing every screen reads
from, and the components built on them. The rule is that a screen never names
a colour or a font size. If something is missing from here, add it here.

## Layout

```
apps/app/
  scripts/check-contrast.mts     proves the palette meets WCAG AA
  src/theme/
    tokens.ts                    every hex value, the type scale, spacing
    provider.tsx                 ThemeProvider and useTheme
    index.ts                     what the rest of the app imports
  src/components/
    cell.tsx                     one snapshot, as a hexagon
    comb.tsx                     cells tiled the way wax is
    ui/                          text, button, text-field, chip, empty-state
```

`src/theme/tokens.ts` imports nothing at runtime, which is what lets the
contrast script load it in plain Node. Keep it that way: a platform-specific
font stack, if we ever need one, goes in its own module.

## Colour

Honey gold, warm amber, soft cream, charcoal and muted brown, with clay and
sage as the only other accents. Contemporary and calm; nothing cartoonish.

Honey is the only colour that acts. Cream, wax and charcoal describe. The
natural accents appear where meaning demands them -- a delete, a confirmation
-- and nowhere else.

| Token             | Light     | Dark      |
| ----------------- | --------- | --------- |
| `background`      | `#FBF6EC` | `#14110E` |
| `surface`         | `#FFFDF8` | `#1F1A15` |
| `surfaceSunken`   | `#F3EADA` | `#0D0B09` |
| `surfacePressed`  | `#F3EADA` | `#2A241D` |
| `surfaceSelected` | `#FDF3DC` | `#2E2213` |
| `border`          | `#E6D8C1` | `#362F27` |
| `borderStrong`    | `#8C7B63` | `#8C7B63` |
| `text`            | `#1F1A15` | `#FBF6EC` |
| `textMuted`       | `#6B5D4F` | `#B3A392` |
| `accent`          | `#E9A72C` | `#E9A72C` |
| `accentPressed`   | `#C8860E` | `#F2C45E` |
| `onAccent`        | `#1F1A15` | `#1F1A15` |
| `accentText`      | `#8A5B06` | `#F2C45E` |
| `focus`           | `#8A5B06` | `#F2C45E` |
| `wax`             | `#EADCC4` | `#2A241D` |
| `honey`           | `#E9A72C` | `#E9A72C` |
| `honeyEdge`       | `#7A4411` | `#C98740` |
| `amber`           | `#9C5A18` | `#C98740` |
| `danger`          | `#A32B1C` | `#E8705C` |
| `dangerPressed`   | `#86231A` | `#EE8470` |
| `onDanger`        | `#FFFFFF` | `#1F1A15` |
| `success`         | `#3C6B4A` | `#7FB58E` |
| `scrim`           | `#1F1A15` | `#0D0B09` |
| `onScrim`         | `#FFFDF8` | `#FFFDF8` |

Two pairs of tokens are easy to mix up:

- **`accent` vs `accentText`.** `accent` is honey as a surface, with `onAccent`
  on top of it. Honey as _ink_ on cream is `accentText`, which is darker,
  because honey gold on near-white is about 1.9:1 and unreadable.
- **`border` vs `borderStrong`.** `border` is a decorative hairline between
  rows. Anything that outlines a control or a cell uses `borderStrong`, which
  is held to 3:1.

A press darkens in the light hive and brightens in the dark one. That is the
only way both keep their contrast with the label on top.

### The contrast check

```sh
npm run check:contrast
```

Run it after touching `tokens.ts`. It walks every text, control and graphic
pair in both themes and fails the build below AA -- 4.5:1 for text, 3:1 for
controls and for graphics you have to see to understand the content. All 50
pairs pass today.

Two cases the script is deliberate about:

- **A title over a cover photo.** The scrim reaches 0.74 opacity where the
  words start, which clears 4.5:1 even over a white photo. `SCRIM_ALPHA_UNDER_TITLE`
  in the script and `SCRIM_STOPS` in `cell.tsx` have to stay in step.
- **How full a cell is.** Honey against pale wax is 1.55:1, and no honey gold
  worth the name will reach 3:1 against cream. So the _line_ where honey meets
  wax carries the contrast in the light hive (`honeyEdge`, 3.8:1 against both
  sides), while in the dark hive honey and wax already separate at 7.3:1 and
  the line is only a meniscus. The script accepts either route and fails if
  neither holds. The fill level is also never the only carrier of that
  information: it belongs in the cell's accessibility label too.

## Type

System faces: SF on iOS, Roboto on Android, the system stack on web. A
typeface is a decision for the designs in BWX-7. The scale is not, and holds
either way.

| Variant      | Size / line height | Weight | For                                 |
| ------------ | ------------------ | ------ | ----------------------------------- |
| `display`    | 32 / 38            | 700    | Screen titles                       |
| `title`      | 24 / 30            | 700    | Section titles, a cell's own screen |
| `heading`    | 19 / 25            | 600    | Group headings                      |
| `body`       | 16 / 23            | 400    | Everything someone reads            |
| `bodyStrong` | 16 / 23            | 600    | A line of body text that matters    |
| `label`      | 14 / 19            | 600    | Buttons, field labels, names        |
| `caption`    | 13 / 18            | 400    | Helper text, dates, counts          |
| `micro`      | 11 / 14            | 600    | Tab labels, badges                  |

Text scales with the OS text size. Do not turn that off.

## Space, radius, touch

`space` is a 4pt scale: `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32,
`xxxl` 48. Padding and gaps come from it rather than from loose numbers.

`radius` is `sm` 6, `md` 10, `lg` 16, `pill` 999.

`minTouchTarget` is 44. Nothing tappable is smaller, and a control that looks
smaller makes up the difference with `hitSlop`.

## Components

| Component    | What it is                                                             |
| ------------ | ---------------------------------------------------------------------- |
| `Text`       | Every string the user reads. Takes a type `variant` and an `ink`.      |
| `Button`     | `primary` (honey, one per screen), `secondary`, `ghost`, `danger`.     |
| `TextField`  | A labelled input, with helper text and an error state.                 |
| `Chip`       | A participant. Photo or initials, name, and a note when one is needed. |
| `EmptyState` | Nothing here yet, said calmly.                                         |
| `FocusRing`  | The keyboard focus ring, drawn outside a control so nothing moves.     |
| `Cell`       | One snapshot, as a hexagon with a cover photo clipped into it.         |
| `Comb`       | A small cluster of cells, tiled.                                       |

Still to come, with the ticket that owns each: the pannable hive and its
accessible comb list (BWX-19); honey, amber, capped and sealed cells, and all
motion including the reduced-motion alternative (BWX-83); identity
suggestions, perspective and privacy selectors, approximate dates, places,
reflection cards, buzz rows and upload progress, each with the feature it
belongs to.

## The hexagon

A cell is a pointy-top hexagon: flat sides left and right, a point top and
bottom. Its `width` is the distance across the flats, and everything else
follows -- height is `width * 2 / sqrt(3)`, which is `CELL_HEIGHT_RATIO`.

It is drawn with `react-native-svg`, which gets the same shape on iOS,
Android and web. Three things to know if you touch `cell.tsx`:

- **A stroke straddles its line.** The outline polygon is inset by half its
  width, or the outer half falls off the canvas and the edge looks thin.
- **Clip-path ids share one namespace per document on web.** Each cell
  generates its own from `useId()`, or every cell in a comb ends up wearing
  the first one's clip.
- **The title is a real `Text` over the SVG**, not SVG text, so it stays
  crisp and can ellipsize. It sits on the bottom edge of the hexagon's
  full-width band, so one line or two both stay inside the slanted edges.

Drawing a few hundred cells on one pannable canvas is a different problem.
BWX-8 is the spike that decides whether Skia is the answer; this component is
for the handful a screen shows at a time.

## Accessibility

Not optional, and cheaper to keep than to retrofit:

- Every colour pair meets AA, enforced by the script above.
- Every control is at least 44pt to the finger and shows a focus ring to the
  keyboard. The web app is a first-class target, and tabbing through a form is
  how plenty of people will use it.
- A hexagon on a canvas is invisible to a screen reader, so a `Cell` carries
  an `accessibilityLabel` that says what the cell is -- "Japan, day 3, 48
  photos from 4 people" -- not just its title. The fully accessible view of
  the hive is the comb list in BWX-19.
- Decorative art is hidden from assistive technology. `EmptyState` does that
  for its illustration, so never put anything there that the title and body
  do not already say.
- Motion must respect reduced-motion settings. There is no motion in this
  system yet; BWX-83 adds it, and owns that alternative.
