# Beeswax — rough designs (BWX-7)

Low-fidelity designs for the four surfaces M1 builds: creation, the hive,
cell detail, and You. Companion to [product.md](product.md), which wins on
any disagreement about behaviour. This document only decides how it looks
and what the screens contain.

For the colours, type scale and components themselves, see
[design.md](design.md) — that is the design system BWX-6 builds and this
document consumes.

Scope is deliberately rough. Exact spacing, illustration and motion curves
are not settled here; screen inventory, hierarchy, states and the component
list are, because three people build these in parallel across iOS, Android
and web and need to agree before M1 starts.

---

## 1. Typeface

BWX-6 ships system fonts and defers the typeface here. The decision:

**Two faces, split at 19pt.**

| Role                            | Face                                      |
| ------------------------------- | ----------------------------------------- |
| Display, title, heading (≥19pt) | **Fraunces** — variable, OFL              |
| Body and below (<19pt)          | System stack: SF Pro, Roboto, `system-ui` |

Fraunces is a warm, slightly bookish variable serif. At `SOFT` dialled up a
little and `WONK` off, it reads contemporary and calm rather than cute,
which is what the visual direction asks for, and it makes a cell title look
like a keepsake instead of a post. One variable file, subset to Latin.

System fonts carry everything smaller. They cost no bundle, behave correctly
under Dynamic Type and TalkBack text scaling, never flash, and look right on
each platform — all of which matter more than brand at 13pt.

Numerals are tabular wherever counts, dates or honey percentages sit in a
column, so rows do not jitter as values change.

**Loading.** `useFonts` from `expo-font`, with the splash screen held via
`expo-splash-screen` until it resolves, so no screen renders in a fallback
face and reflows. If Fraunces ever costs more than it earns — bundle size,
a load stall on low-end Android — drop to system everywhere. The scale below
holds either way, which is why BWX-6 was right not to wait for this.

### Type scale

BWX-6's scale is correct and is adopted unchanged. This only assigns faces.

| Variant      | Size / line | Weight | Face     | Used for                              |
| ------------ | ----------- | ------ | -------- | ------------------------------------- |
| `display`    | 32 / 38     | 700    | Fraunces | Screen titles                         |
| `title`      | 24 / 30     | 700    | Fraunces | A cell's name on its own screen       |
| `heading`    | 19 / 25     | 600    | Fraunces | Section headings, moment headings     |
| `body`       | 16 / 23     | 400    | System   | Descriptions, written memories        |
| `bodyStrong` | 16 / 23     | 600    | System   | Emphasis inside body text             |
| `label`      | 14 / 19     | 600    | System   | Buttons, field labels, people's names |
| `caption`    | 13 / 18     | 400    | System   | Dates, counts, helper text            |
| `micro`      | 11 / 14     | 600    | System   | Tab labels, badges                    |

Sizes are points and scale with the OS text setting. Nothing in the app
pins a font size in a component.

---

## 2. Rules that apply to every screen

- **Five destinations**, per product.md decision 9: Hive, People, Create
  (centre), Buzz, You. Bottom tabs under 768px, side nav at or above it.
  The committed `tabs.ts` still has three and is BWX-5's to fix.
- **Honey is always visible, never nagging.** A cell's fill level is the
  only "you are missing something" signal on the hive. No badges counting
  gaps, no red dots on cells.
- **The fill level is drawn as a line, not as a colour change.** Honey
  (`honey400`) against empty wax (`cream300`) is 1.55:1 in light mode, so a
  flat fill makes the level — the actual information — invisible. The
  boundary is stroked in `honeyEdge`, which measures 3.99:1 against wax in
  light and 5.13:1 in dark, clearing the 3:1 that a meaningful graphic
  needs. `honeyEdge` is not required to contrast with the honey beneath it;
  it is read against the wax above. This is the whole reason BWX-6 carries
  `honeyEdge` as a separate token, and `check:contrast` should assert both
  of those pairs.
- **Bee words in what you see, plain words in what you press.** A screen may
  say "this comb"; a button says "Add people", a role says "Contributor".
- **Every hive interaction works from the comb list.** If a gesture on the
  canvas has no comb-list equivalent, it is not finished.
- **Reduced motion is a first-class state**, not a polish item. Honey fill,
  cell settle and the hive's placement animation all check
  `AccessibilityInfo.isReduceMotionEnabled()` and fall back to an instant
  state change.
- **Minimum touch target 44pt**, padded with `hitSlop` where the visual is
  smaller.
- **Four states per screen**: loading, empty, error, offline. Each is
  designed below; none is a spinner alone.

---

## 3. Creation

The highest-risk surface in the product. If this feels like filling in a
form, the hive stays empty and nothing else matters.

**One screen, not a wizard.** Exactly one thing is required: a title _or_
some media. Everything else is optional and progressively disclosed.

### Mobile

```
┌──────────────────────────────┐
│ Cancel          New   Save   │   Save enabled as soon as there is a
├──────────────────────────────┤   title or one photo
│  ┌────────────────────────┐  │
│  │  Add photos            │  │   Tapping opens the picker. Picking
│  │  or start with a title │  │   photos suggests title, date, place
│  └────────────────────────┘  │   from EXIF — each labelled as a
│                              │   suggestion and editable
│  Title                       │
│  [________________________]  │
│                              │
│  When                        │
│  [ Summer 2008          ▾ ]  │   precision: day/month/season/year/decade
│                              │
│  Who was there               │
│  ( + ) (AV) (YE) (SK)        │   avatars; + opens people picker
│                              │
│  Where                       │
│  [ Add a place            ]  │
│                              │
│  More ▾                      │   description, visibility, nest under,
└──────────────────────────────┘   connections, contribution settings
```

### Web

Same fields, two columns at ≥768px: the photo drop zone takes the left
column at full height (drag and drop a folder), fields stack on the right.
Save sits top-right, not at the bottom of a long scroll.

### Behaviour

- **Autosave to brood from the first keystroke.** Leaving never loses work,
  and there is no "are you sure" dialog.
- **Suggestions are labelled.** A date read from EXIF shows as
  "Summer 2008 · from your photos" with one tap to accept or edit. Per
  product.md §8, AI and inference never silently fill a field.
- **On save, always land in the hive** with the new cell placed and
  highlighted as its honey fills. One rule, everywhere.

### States

| State   | Design                                                                                     |
| ------- | ------------------------------------------------------------------------------------------ |
| Loading | Fields skeleton in wax; the photo zone is usable immediately                               |
| Empty   | This _is_ the empty state — the photo zone is the primary call                             |
| Error   | Inline under the field. Save failure keeps the draft and retries                           |
| Offline | "Saved on this device. Photos will upload when you're back." Draft is local, uploads queue |

---

## 4. Hive

Home. Two co-equal views of the same data behind one toggle: the **canvas**
and the **comb list**. The comb list is not a lesser fallback — it is what
VoiceOver and TalkBack users get by default, and it is likely what many
sighted users prefer day to day.

### Canvas (mobile and web)

```
        ⬡   ⬡   ⬡           Newest at the edge, oldest at the core.
      ⬡   ⬡   ⬡   ⬡         Rings mark years; the ring label floats
    ⬡   ⬡  ███  ⬡   ⬡       at the ring's edge as you pan.
      ⬡   ███   ⬡   ⬡
        ⬡   ⬡   ⬡           ███ = honey fill rising from the bottom
                            of the cell. Older cells deepen to amber.
```

- A cell shows its cover photo, clipped to the hexagon. Title appears on
  tap (mobile) or hover (web); it is always in the accessibility label.
- **Pan and pinch** on mobile; scroll, drag and keyboard arrows on web.
- **Scrubbing a ring** jumps through time — the only time control, since
  there is no calendar.
- Tapping a comb (a parent and its children) zooms into it rather than
  opening the parent directly.
- A **pollen trail** lights the path through every cell touching a selected
  person, place or tradition.

### Comb list

Chronological, grouped by year ring, one row per cell: cover thumbnail,
title, date, place, honey as a labelled meter, participant avatars. Every
canvas action has a row equivalent — open, filter, follow a trail.

The toggle lives in the header and its state persists per user. Turning on
a screen reader selects the comb list without changing the stored setting.

### Search and filters

One field, filters behind it: title, date range, person, place, text,
parent, visibility (BWX-59). Search covers "find the thing from March",
which is the job a calendar would otherwise do.

### States

| State   | Design                                                                                                               |
| ------- | -------------------------------------------------------------------------------------------------------------------- |
| Loading | Wax-coloured hexagon skeletons in ring formation; no spinner                                                         |
| Empty   | A single empty cell outline, "Your hive starts with one memory", and a Create button. Never a marketing illustration |
| Error   | The hive keeps whatever is cached and shows an inline retry strip                                                    |
| Offline | Cached cells stay interactive, dimmed strip: "Showing what's on this device"                                         |

---

## 5. Cell detail

What a snapshot looks like when opened. The densest screen in the product,
and the one where the two separations in product.md §3 have to be legible:
being in a memory is not access to it, and owning a snapshot is not owning
its media.

### Layout

```
┌────────────────────────────────────┐
│ ‹ Japan 2024 › Day 3               │  breadcrumbs when nested
├────────────────────────────────────┤
│ [          cover photo           ] │
│                                    │
│ Kyoto, day three          ▓▓▓▓░░   │  title + honey meter
│ 14 March 2024 · Kyoto              │
│ (AV) (YE) (SK) +2                  │  participants, not members
├────────────────────────────────────┤
│ [ Everyone | Mine | Yahia | Sara ] │  perspectives (BWX-45)
├────────────────────────────────────┤
│ ▸ Arrival            09:20         │  moments, in time order
│   [img] [img] [img]                │
│ ▸ Lunch              12:40         │
│   [img]  "nobody photographed      │  written memories sit inside
│          the rain" — Yahia         │  the moment they belong to
│ ▸ The drive home     19:05         │
├────────────────────────────────────┤
│ Connects to: Japan 2024 (trip)     │
│ Inside: Day 3 → Nishiki Market     │
└────────────────────────────────────┘
```

Web at ≥768px puts moments in the main column and lifts participants,
connections and children into a right rail, so the cell can open beside the
hive without losing the hive.

### Things this screen must get right

- **Perspectives are a filter, not a verdict.** Switching to "Yahia" shows
  what Yahia added. Two accounts of the same moment sit side by side with
  no marker of which is correct.
- **Attribution is always on the item**, never only in a detail sheet. Every
  photo and written memory carries whose it is.
- **Empty wax asks the question.** A half-full honey meter with "3 of 5
  people have added something" is the whole memory-gap mechanic on this
  screen. At most one gentle push per snapshot per week.
- **Role changes what is visible, not what is greyed out.** A Viewer does
  not see a disabled "Add photos" button; they see no button.

### Special cell states

| State        | Design                                                                                                                              |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Capped**   | Wax cap over the cover with the unlock date. Nothing inside is rendered — not blurred, not fetched                                  |
| **Sealed**   | A thin wax rule under the header, "Sealed 12 March 2026". Reflections can still be added below                                      |
| **Hatching** | Contributions hidden behind a count: "4 people have added theirs". Everything appears at once when the last person does             |
| **Hum**      | A small speaker control by the title; ten seconds, plays softly on open, off under reduced motion and silent by default on cellular |

### States

| State   | Design                                                                                       |
| ------- | -------------------------------------------------------------------------------------------- |
| Loading | Header renders from hive data immediately; moments skeleton below                            |
| Empty   | Cover placeholder in wax, "Nothing here yet" and the contribute action if the role allows it |
| Error   | Header stays, moments area shows retry                                                       |
| Offline | Cached contributions shown, upload queue visible at the bottom                               |

---

## 6. You

Your own person hive on top, settings below. Replaces a profile page —
per product.md there is no public profile and nothing here is visible to
anyone else.

```
┌──────────────────────────────┐
│ (avatar)  Aryan              │
│           @aryan             │
│           Edit profile       │
├──────────────────────────────┤
│   ⬡  ⬡  ⬡     your cells     │  a small comb: the memories you are in
│ ⬡  ⬡  ⬡  ⬡                   │
├──────────────────────────────┤
│ Buzz                      ›  │  notification types, quiet hours
│ Privacy                   ›  │  discoverability, who can find you
│ People                    ›  │  friends, identities, blocked
│ Storage                   ›  │  usage, quality, downloads
│ Export your memories      ›  │
│ Account                   ›  │  sign-in methods, email, delete
└──────────────────────────────┘
```

Plain words throughout, per decision 10. "Export your memories" is a
top-level row rather than buried in Account, because product.md principle 8
makes it a promise rather than a feature.

Account deletion shows the choice product.md §7 requires — remove your
contributions, or leave them attributed — with the default on remove, and
says plainly what happens to snapshots you own.

---

## 7. What BWX-6 needs to build

Components these four screens require, beyond what BWX-6 already has:

| Component         | Used by                | Notes                                                     |
| ----------------- | ---------------------- | --------------------------------------------------------- |
| `HoneyMeter`      | Hive list, cell detail | Labelled, not decorative. Text alternative always present |
| `ParticipantRow`  | Creation, cell detail  | Overlapping avatars, +N overflow, opens people picker     |
| `ApproximateDate` | Creation, cell detail  | Renders a date with its precision: "Summer 2008"          |
| `SuggestionChip`  | Creation               | A labelled inference with accept / edit                   |
| `Perspectives`    | Cell detail            | Segmented; Everyone / Mine / per contributor              |
| `MomentGroup`     | Cell detail            | Time-stamped heading plus its contributions               |
| `Breadcrumbs`     | Cell detail            | Nesting path, depth capped at 6                           |
| `EmptyState`      | Every screen           | Illustration-free; a sentence and one action              |
| `SettingsRow`     | You                    | Label, value, chevron, optional description               |
| `ViewToggle`      | Hive                   | Canvas ↔ comb list, persists per user                     |

`Cell` and `Comb` are BWX-6's. This document does not redesign them; it only
assumes a cell can render cover, honey level, amber age, and the capped,
sealed and hatching states above.

---

## 8. Open questions for the team

1. **Does the hive canvas ship in M1 at all**, or does M1 ship the comb list
   and search, with the canvas following in M2? The canvas is the product's
   signature and also its biggest build risk (BWX-8 is the Skia spike).
   Shipping the list first is not a downgrade — it is the accessible view
   either way.
2. **Fraunces or system only.** A real bundle and load-time cost against a
   real piece of identity. Measure on low-end Android before committing.
3. **Where do connections get made?** This document shows them on cell
   detail. The creation flow's "More" could also ask "does this continue
   something?" — cheaper to answer at creation, more context later.
4. **How much of cell detail is M1?** Moments, perspectives and written
   memories are three separate tickets. The header, honey and contributions
   list are the minimum that makes the screen worth opening.
