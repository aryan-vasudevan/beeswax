# Beeswax — product specification

**Every memory, a little sweeter.**

Snapchat captures moments. Photo libraries store them. Beeswax reconstructs
the experiences behind them.

This is the reference for what Beeswax is and how it behaves. It adapts the
master product prompt (October 2026) to the decisions the team has made since,
chief among them: **the hive replaces calendars, timelines and profile pages.**
Where this document disagrees with the prompt, this document wins, and the
reason is written down in [Decisions](#decisions-where-we-depart-from-the-prompt).

Every feature is tested against one question: _does this help reconstruct,
preserve, or revisit a shared experience?_ If not, it does not ship.

---

## 1. Principles

1. Experiences, not posts, are the organizing unit.
2. Memories belong to people's lives, not to their accounts. People who never
   sign up -- grandparents, people who have died -- are first-class.
3. A shared event has many legitimate perspectives. None is "the truth".
4. Memories get richer over time; nothing silently rewrites the original.
5. Capturing should take seconds. Organizing can happen later.
6. Reminiscence, not scrolling. No feeds, follower counts, likes, streaks or
   popularity of any kind.
7. Private by default. Consent is in the data model, not bolted on.
8. Your history is yours: exportable, recoverable, deletable.
9. AI assists, never invents. Inferences are labelled and confirmable.
10. Complexity lives underneath. The surface stays simple.

---

## 2. The hive: design language

The whole product is a hive. The theme carries meaning -- every bee concept
maps to a real mechanic -- and it stops at the controls: buttons, permissions
and settings use plain words, because "Make Forager" helps nobody.

| Hive concept     | What it is in Beeswax                                                                                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Hive**         | Your archive. Home screen. Every snapshot you can see is a cell.                                                                                                                           |
| **Cell**         | One snapshot. Hexagonal. Cover photo inside, title on hover/tap.                                                                                                                           |
| **Comb**         | A cluster of related cells: a parent snapshot and its children, a trip, a chapter of life. Zooming into a comb opens it.                                                                   |
| **Year rings**   | The hive grows outward like comb: oldest memories at the core, newest at the edge. Rings of cells mark years, so time is readable without a calendar. Scrubbing a ring jumps through time. |
| **Honey**        | How complete a memory is: the share of participants who have added something, weighted by media, stories and reflections. A cell fills from the bottom as people contribute.               |
| **Empty wax**    | The memory gap. A half-full cell shows missing perspectives without a nagging notification.                                                                                                |
| **Amber**        | Age. Cells deepen toward amber over the years.                                                                                                                                             |
| **Warm honey**   | A resurfaced memory. Old crystallized cells glow and turn liquid when someone revisits or reflects.                                                                                        |
| **Moments**      | Inside a cell: the reconstructed event, as a small comb of moments in time order (arrival, dinner, the drive home).                                                                        |
| **Capped cell**  | A time capsule. Wax cap shows the unlock date; nothing inside is readable until then.                                                                                                      |
| **Sealed cell**  | A snapshot frozen as it was (BWX-60). Reflections can still be layered on.                                                                                                                 |
| **Nectar**       | Unsorted media: imports and camera-roll batches waiting to become snapshots. Turning nectar into honey is the organizing step.                                                             |
| **Brood**        | Drafts. Cells still being built.                                                                                                                                                           |
| **Swarm**        | A group of people who keep sharing memories (BWX-62). A family is a swarm with a long life (M7).                                                                                           |
| **Waggle**       | An invitation. The waggle card shows only what is safe to show: who invited you, not what the memory contains.                                                                             |
| **Pollen trail** | Selecting a person, place or tradition lights the path through every cell it touches.                                                                                                      |
| **Person hive**  | Opening a person shows the comb you share with them (BWX-58). Replaces profile pages.                                                                                                      |
| **Buzz**         | Notifications. Calm, batched, never manipulative.                                                                                                                                          |

### Navigation

Five destinations, bottom tabs on phones, side nav on wide web:

1. **Hive** -- home.
2. **People** -- your people as a hive of faces: friends, identities, swarms. Requests and invitations live here.
3. **Create** (centre) -- start a snapshot from anywhere.
4. **Buzz** -- invitations, contributions, resurfacing, requests.
5. **You** -- your own person hive, settings, privacy, storage, export, account.

**After saving a snapshot**, you always land in the hive with the new cell
placed and highlighted as its honey fills. One rule, everywhere.

### Accessibility is not optional

A canvas of hexagons is invisible to a screen reader and hard on motor
control. The hive therefore has a **comb list**: the same cells as a
chronological, fully accessible list grouped by year ring. It is a view of
the hive, not a separate timeline product, and it is what VoiceOver/TalkBack
users get by default. Every hive interaction (open, filter, follow a trail)
must work from the comb list. Motion respects reduced-motion settings.

### Visual direction

Honey gold, warm amber, soft cream, charcoal, muted brown; restrained natural
accents. Contemporary and calm, never cartoonish. Contrast meets WCAG AA.
Motion is soft and short (honey pours, cells settle) and never blocks input.

---

## 3. Core model

```
Experience
  └─ Snapshot (cell)
       ├─ Participants      people who were there (accounts or identities)
       ├─ Members           accounts with access, each with a role
       ├─ Contributions     media, written memories, reflections -- each owned by its contributor
       ├─ Moments           the reconstructed event, in time order
       ├─ Children          nested snapshots (combs)
       └─ Connections       continuation, same trip, tradition, same people, same place
```

Two separations hold everywhere:

- **Being in a memory never grants access to it.** A participant is someone
  who was there. A member is an account allowed in. Tagging Grandma does not
  let anyone who later claims "Grandma" read anything.
- **Owning a snapshot never means owning its media.** Each contribution
  belongs to whoever added it. The owner arranges and moderates; the
  contributor decides who may see their item beyond the members.

---

## 4. Decisions where we depart from the prompt

Argue with these -- but argue with the reason, not the outcome.

1. **No calendar or timeline view.** The prompt calls them essential for MVP.
   They make Beeswax look like every other photo app. The hive carries time
   through year rings and amber, search covers "find the thing from March",
   and the comb list covers accessibility. If testing shows people cannot
   find memories, we fix the hive, not add a calendar.
2. **"Public" means _anyone with the link_, never discoverable.** There is no
   public profile, no browse, no search of other people's public memories.
   A discovery surface is how a memory app becomes a feed, and it invites
   scraping. Public snapshots are unlisted links that require sign-in.
3. **No "duplicate snapshot".** Copying a memory copies other people's media
   and permissions into a place they never agreed to. Instead: **Start from
   this** -- a new snapshot pre-filled with the title pattern, place and
   people, which is what duplication is really for (traditions, repeat trips).
4. **Contribution limits stay, hidden.** Off by default, in advanced
   settings. The normal experience invites more, never "you've used 12/12".
5. **Friends exist, but quietly.** Mutual, request-based, used for
   suggestions and the "friends" audience. No counts, no friends-of-friends
   browsing, your list is visible only to you.
6. **Last activity is stored, never shown.** It powers archive succession
   (BWX-66). "Last seen" creates social pressure we do not want.
7. **Memory-gap prompts are visual first.** Empty wax does the asking. At
   most one gentle push per snapshot per week, and never to someone who
   dismissed it.
8. **Face recognition is blocked on legal review** (BWX-67). Biometric data
   of people who cannot consent is the single biggest legal risk in the
   product.
9. **Five tabs, not three.** The prompt is right that People and Buzz need
   their own place; BWX-5 is updated.
10. **Bee names stay out of the controls.** Roles are Owner, Editor,
    Contributor, Viewer. The theme is in what you see, not what you press.

---

## 5. Features

Status key: ✅ built (in review) · 🔨 in progress · 📋 ticketed · — not started.
Ticket numbers are in Linear (BWX workspace).

### Phase 1 — MVP (must work together end to end)

**Accounts** -- email/password, Apple, Google (BWX-10, BWX-11); username,
display name, optional phone, photo and bio; email verification (on in
config), password reset, email change, recovery; sessions and refresh
tokens (Supabase Auth); linking several sign-in methods to one account;
account deletion and data export; notification and privacy settings
(BWX-12). Schema: BWX-9 ✅.

**People** -- search users (exact username or contact match only, no
browsing); friend requests, accept, reject, remove; block; identities for
people without accounts with name, nickname, photo and private notes; your
people list with relationship labels and "hide from suggestions" (BWX-17);
smart suggestions (BWX-18); discoverability control.

**Identity claiming** (BWX-46) -- an identity is linked to an account only
when the identity's creator and the account holder both agree. Never by name.
Linking grants no access; owners of snapshots that include the identity are
asked whether to invite the new account. Either side can dispute and unlink.
Multiple creators' records for the same person are never merged.

**Snapshots** -- create with only a title or only media; approximate dates
("summer 2008", "the 90s"); optional time, end, timezone, place and
coordinates; cover; drafts and autosave (brood); archive, soft delete with
30-day restore; "start from this"; share by waggle link; export. Schema:
BWX-13 ✅ (being reworked to the model above), UI BWX-14, BWX-20.

**Nested snapshots** (BWX-21, BWX-22) -- combs to any reasonable depth
(cap at 6); children inherit place, participants, date range and visibility
as editable defaults; a parent never widens a child's audience; no cycles;
breadcrumbs.

**Connections** (BWX-21, BWX-23, BWX-24) -- continuation, same trip,
tradition, same people, same place, related. Manual first; suggestions
(BWX-52) need approval.

**Permissions** -- see [section 6](#6-permissions). Server-enforced (RLS),
audited.

**Invitations** -- invite an account (in-app) or anyone (waggle link).
Expiring, revocable, single-use or knock-to-join, role assigned up front,
no duplicate pending invites, preview reveals nothing sensitive.

**Media** (M3) -- photos, videos, audio; resumable multi-upload with
progress and retry; originals kept, thumbnails and previews generated in the
background; EXIF capture time, timezone, GPS, dimensions, duration,
filename; correctable dates and places; location stripped from anything
shared publicly; reorder; cover selection; per-item visibility owned by
the contributor; delete and removal requests.

**Contribution settings** -- who can upload, allowed types, approval
before items appear, soft limits, notify on add. All off/permissive by
default, tucked away.

**Event reconstruction** -- inside a cell, contributions arrange into
moments by capture time and place; suggested moments from time gaps;
manual moments, drag to reorder, fix wrong timestamps; multi-day; play the
event back moment by moment. Inferred moments are labelled as suggestions.

**Perspectives** (BWX-45) -- Everyone / Mine / each contributor; compare
accounts of the same moment side by side; conflicting recollections coexist.

**Written memories** (BWX-40) -- separate from captions: stories, quotes,
inside jokes, "nobody photographed this". Each is one person's account and
says so. Optional, varied, dismissible prompts (BWX-38, BWX-39).

**Hive** -- BWX-19 (v0), BWX-25, BWX-26; comb list; year rings; honey
(BWX-44); search and combined filters by title, date range, person, place,
text, parent, visibility (BWX-59).

**Resurfacing** (M5) -- on this day, N years ago, forgotten combs, places,
people, traditions; hide a memory, mark sensitive, mute people and periods
(BWX-51), turn off, set frequency.

**Buzz** -- in-app inbox plus push with email fallback (BWX-42); granular
preferences; quiet hours; batched.

**Trust and safety** -- report content, owner moderation (hide), block,
rate limits on auth and invites, age gate (13+, no minors' public links),
audit log of permission changes.

### Phase 2 — what makes it Beeswax

Smart moment grouping and duplicate detection; memory gaps (BWX-44, BWX-43);
living reflections and sealing (BWX-60); revision history; time capsules
(BWX-61); person hives (BWX-58); traditions (BWX-54, BWX-57); life chapters;
swarms (BWX-62); suggested links (BWX-52, BWX-53); nectar tray and imports
(BWX-55, BWX-56); voice memories; advanced hive (zoom, trails).

### Phase 3 — expansion

AI memory search and Q&A with citations; recaps and year in review; family
hives, family tree, succession (M7); memory books, digital and printed;
cloud and archive imports; subscriptions (Free, Plus, Family); recognition
(BWX-67, pending legal).

---

## 6. Permissions

Server-enforced by row-level security. The client's idea of your role is
decoration.

|                                         | Owner |        Editor         | Contributor | Viewer | Participant only |
| --------------------------------------- | :---: | :-------------------: | :---------: | :----: | :--------------: |
| See the snapshot                        |   ✓   |           ✓           |      ✓      |   ✓    |        —         |
| Edit title, dates, place, description   |   ✓   |           ✓           |      —      |   —    |        —         |
| Add / remove participants               |   ✓   |           ✓           |      —      |   —    |        —         |
| Invite members                          |   ✓   | contributors, viewers |      —      |   —    |        —         |
| Change roles                            |   ✓   |           —           |      —      |   —    |        —         |
| Change visibility                       |   ✓   |           —           |      —      |   —    |        —         |
| Add own media, memories, reflections    |   ✓   |           ✓           |      ✓      |   —    |        —         |
| Edit / delete own contributions         |   ✓   |           ✓           |      ✓      |   —    |        —         |
| Hide others' contributions (moderation) |   ✓   |           ✓           |      —      |   —    |        —         |
| Delete others' contributions            |   —   |           —           |      —      |   —    |        —         |
| Arrange moments, set cover              |   ✓   |           ✓           |      —      |   —    |        —         |
| Nest under / link to other snapshots    |   ✓   |           ✓           |      —      |   —    |        —         |
| Archive, delete, transfer ownership     |   ✓   |           —           |      —      |   —    |        —         |
| Leave                                   |   —   |           ✓           |      ✓      |   ✓    |        —         |

Notes:

- The owner can hide anyone's item from the snapshot but cannot delete,
  download or republish it; the contributor keeps it.
- Every contribution has its own audience: **members** (default) or
  **public-ok**. A public snapshot shows only public-ok items.
- Visibility modes: **private** (members only), **custom** (members plus
  chosen people or swarms as viewers), **public** (anyone signed in with the
  link; never listed).

---

## 7. Edge cases and defined behaviour

Each of these has, or will have, a database or end-to-end test.

| Scenario                                      | Behaviour                                                                                                                                                                                                                |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Owner deletes their account                   | Ownership passes to their named successor (BWX-66), else the longest-standing editor, else contributor. With no members left, the snapshot is deleted with the account.                                                  |
| Any user deletes their account                | They choose: remove their contributions, or leave them attributed to their name. Default is remove. Their self person stays as a name-only participant so other people's memories stay intact. 30-day grace, then purge. |
| Collaborator leaves                           | Access ends. They remain a participant (they were there). Their contributions stay unless they remove them.                                                                                                              |
| Owner removes a contributor                   | Access ends. Their contributions stay but the owner may hide them. The contributor keeps their items and can delete them.                                                                                                |
| Contributor revokes their media               | Removed from the snapshot for everyone, soft-deleted for 30 days, then purged with all derivatives.                                                                                                                      |
| Private snapshot made public                  | Only items marked public-ok appear. Contributors are asked, once, whether to allow their items. Nobody's media becomes public by someone else's switch.                                                                  |
| Parent snapshot deleted                       | Children are kept and move up to the parent's parent (or top level). The owner sees how many children are affected before confirming.                                                                                    |
| Child stricter than parent                    | The child's own visibility always applies. Access to a parent never implies access to a child.                                                                                                                           |
| Identity linked to the wrong account          | Either the identity's creator or the account can dispute; unlinking is immediate. Linking never granted access, so nothing leaked. Logged.                                                                               |
| Two users create the same person              | Two records. Each creator approves linking separately. Never merged.                                                                                                                                                     |
| Friend removed                                | Nothing in shared snapshots changes. They leave suggestions and the friends audience.                                                                                                                                    |
| User blocks someone they share snapshots with | Neither can invite or add the other again, see the other's person hive, or see the other's new contributions in shared snapshots. Existing shared snapshots remain.                                                      |
| Simultaneous edits                            | Contributions are separate rows and never conflict. Snapshot details use optimistic concurrency: a stale save is rejected and the client merges field by field.                                                          |
| Upload fails halfway                          | Resumable upload with an idempotency key; the item shows as pending and resumes or is cleaned up after 24h.                                                                                                              |
| Video with no timestamp                       | Takes the snapshot's date, marked "estimated", and is correctable.                                                                                                                                                       |
| Approximate date                              | Stored with a precision (day, month, season, year, decade). The hive places it within its ring; it reads "Summer 2008".                                                                                                  |
| Participants disagree                         | Both accounts stand, attributed. Nothing marks one as correct.                                                                                                                                                           |
| Inappropriate content                         | Owner or editor hides it; anyone can report it. Hidden items are visible only to their contributor. Reports go to a moderation queue.                                                                                    |
| Time capsule recipient deletes their account  | They are removed as a recipient; the capsule still opens for the rest, or only for its creator if none remain.                                                                                                           |
| Subscription downgrade                        | Nothing is deleted. Over quota means no new uploads until under it. Everything stays viewable and exportable.                                                                                                            |
| Complete data deletion                        | As account deletion, with contributions removed, then purged from storage; backups age out within 30 days.                                                                                                               |
| Offline during creation                       | Draft is saved on the device; uploads queue and sync when back online.                                                                                                                                                   |
| Invite link forwarded                         | The preview shows only who invited and that it is a memory. Opening it needs sign-in; a link addressed to someone verifies their email or phone, and an open link only lets people knock -- the owner approves.          |
| Snapshot with mixed media permissions         | Each viewer sees exactly the items their access allows; counts and honey reflect only what they can see.                                                                                                                 |

---

## 8. Privacy and AI rules

- Private by default. Nothing is published by a third party's action.
- Identity notes and contact details are visible only to their creator.
- No sale of content or behavioural profiles. No advertising on memories.
- No training of general models on private memories.
- AI only sees what the asking user may see, labels its suggestions, cites
  the snapshots it used, and can be corrected or turned off.
- Deterministic metadata first (capture time, place, clustering); models
  only where rules cannot do the job.
- Minors: 13+ only; under-18 accounts cannot create public links.

---

## 9. Measuring whether it works

Privacy-conscious, aggregated: time to first snapshot; share of snapshots
with more than one contributor; invitation acceptance; invitees who
contribute; contributors per shared snapshot; repeat creation; weekly
revisits; resurfacing opened; cohort retention; storage cost per active
user; conversion and paid retention. Not optimized: session length,
notification taps.

---

## 10. Definition of done for the MVP

The prompt's end-to-end journey must pass as an automated test before MVP:
create an account → "Waterloo Orientation" with a date range → two people
without accounts → ten photos → invite a friend as contributor → their
photos arrive → both in moment order → switch perspectives → written
memory → nested sub-event → back to parent → find it in the hive → search
by person or date → change privacy safely → anniversary resurfaces it →
add a reflection → export → archive or delete per the ownership rules.

No placeholder buttons that do nothing. A feature is done when its UI,
database, authorization, persistence and error handling all work.
