# HyperLapse Cart — UI Design v2

**Captured:** 22 May 2026 (Session C day 15 part 10).
**Supersedes:** `UI_DESIGN_SUMMARY.md` (Day 10) where they conflict.
**Status:** Design locked at flavour-level. Ready for build, with
per-screen tweaks expected during operator-acceptance testing.

This document captures the second-pass design of the cart web UI,
worked through across day-15 part 10 in detail. The first-pass
design summary from Day 10 stands for context and history but is
superseded by this file's specifics.

---

## Hardware target

- **Phone**: iPhone SE 3rd generation (model MMXF3X/A), 375×667 CSS points
- All three screens designed to fit portrait without scroll
- No rotation to landscape required
- One URL, top-tab switcher

---

## Three screens (unchanged from Day 10)

1. **Cart Recon** — drive the cart, fill the Cart Log
2. **Gimbal Recon** — capture reference points before/after the route
3. **Execution** — monitor the running Plan, bounded operator interventions

---

## Global theme — day / night

- **Hard flip at nautical sunset / nautical sunrise** (auto)
- **Manual override button** on the header, label flips DAY ↔ NIGHT
- Cart Recon and Gimbal Recon are **daytime-only activities** —
  toggle visible for layout consistency but tapping is a no-op on
  those screens. Only Execution responds to the toggle.
- Palette decisions made by mockup, locked in:

**Day palette** (warm grey on warm grey, dark-photo-editing style):
- `#d8d8d4` background (warm light grey)
- `#eceae3` panel surfaces (slightly lighter)
- `#c8c5bc` notes/footer
- `#333` text
- `#7a8aa0` steering / nudge button (muted slate blue)
- `#a04848` action button (muted maroon: Cart log, Photo, Bake, DEAD)
- `#c89060` warm accent button (Mark wpt, Home)
- `#bcb9b0` header tab inactive
- Active tab indicated by `#a04848` 2px bottom-border accent

**Night palette** (red on black, dark-adapted vision):
- `#000` background (pure black, OLED-friendly)
- `#0a0202` panel surfaces (deep crimson-black)
- `#2a0808` panel borders
- `#7a1818` body text (dim red)
- `#a82020` brighter red (active text, important labels)
- `#d04040` brightest accent (critical action label)
- `#1a0606` button base / `#4a0c0c` button border
- `#3a0a0a` action button base / `#7a1818` action button border
- No white anywhere

---

## Shared header (all three screens)

Two rows, identical across screens:

**Row 1** — context icons + app name:
- RS4 gimbal SVG icon (left, ~32×38px) — from existing sketch
- "HyperLapse" centred (16px, weight 500)
- Canon R3 SVG icon (right, ~38×38px) — from existing sketch
- Night mode: both icons rendered in red palette at 50% opacity (de-emphasised)

**Row 2** — four equal-width tabs:
- `Cart` / `Gimbal` / `Exec` / `Day` (or `Night` in night mode)
- All same visual weight; active screen indicated by 2px bottom-border accent
- 4-column grid, full screen width minus padding

This header replaces the Day-10 design's single-row attempt at
fitting everything; that overflowed at 375px.

---

## Cart Recon — body

**Status row** (single line, monospace, centred):
- `12.4v · ENRG` (or similar)
- Voltage and motor state only — turn/speed/dist info moved into
  the Last/Now rows where it belongs

**Last / Now rows** (the waypoint pattern):
- Two rows displayed above the button area
- Format: `[Last/Now]  [turn°]  [speed m/hr · d distance]  [#N]`
- Last row = the most recently baked waypoint, read-only display
  of a CartLog entry, has `#N` on the right
- Now row = in-progress preview, no `#` until baked by Mark wpt

**Waypoint lifecycle** (worked out in detail this session):
- Operator taps turn/speed buttons in a flurry to set up the next
  leg. Now row updates live as each button is tapped.
- Operator taps **Mark wpt + confirm** to bake. Now row's values
  commit to CartLog as `#N`, `#N` appears on Now row.
- Distance ticks up as cart moves. Now row's turn/speed unchanged
  while baked.
- Next turn-or-speed tap = the **roll trigger**: Now row rolls to
  Last, fresh empty Now begins.
- Only ever 2 rows visible on screen. Prior entries (#1..#N-2)
  live in the CartLog file but aren't shown.

**Button rows** (preserved from existing UI, less the items the
Day-10 design said to drop):
- L5 / L1 / CTR / R1 / R5 (steering presets)
- −10 / −1 / DEC / +1 / +10 (speed adjust)
- STOP / DE-E / ENRG (motor state)
- ● Cart log / Mark wpt (the two main action buttons)
- DEAD removed from Cart Recon (was in old layout; belongs on
  Execution and renamed to PAUSE — see Execution below)
- Home, Photo, PAUSE, BKUP, Gimbal log, btn13, btn21 removed
  (not relevant to recon)

**Notes panel** at the bottom (turn-circle table content, from #10b).

---

## Gimbal Recon — body

**Live readout** (one line, monospace, small):
- `live · Ry 118.7° · Cy 273° · p 34.2°`
- Ry = real-world yaw (gimbal frame + BNO cart yaw)
- Cy = cart-frame yaw (gimbal readback)
- p = pitch
- Operator sees both yaws at all times so they know what they're
  about to bake

**Captured rows display** (open-ended list, 5 visible):
- 3 priors + Last above + Current at row 5 (just above buttons)
- Current's stable slot is just above the button cluster — operator's
  eye is on the buttons when about to act, Current sits right there
- Each baked row shows event type, label, and key value with `Ry` or
  `Cy` prefix carrying the frame decision (e.g. `Ry 361 p38`)

**Current row block** (highlighted with maroon border in day mode):
- 4-button type row (operator-authored): PF / Lock / Move / Track sun
- 3-button astro row: Sunrise / Sunset / MW
- Two-row layout because 7 buttons don't fit one row at 375px
- Visually groups operator-authored vs astro

- **Keyframe sub-toggle** (rise / mid / end) appears when astro
  type is selected. Doesn't appear for PF/Lock/Move/Track sun.

- **R/C toggle** appears for PF and Move only (Real-frame yaw
  vs Cart-frame yaw stored)

- **Yaw Δ and pitch Δ offset fields** for astro events:
  - Pre-fillable from measured variance via the Snap var assist
  - Operator can edit before bake

- **Measured variance display** below offset fields when relevant
  (monospace, small, e.g. `measured -11.2° / +0.8°`)

- **Label field** (free text) — operator types whatever conveys
  intent to Excel later (tree / "replace tree" / "del6 use 7" etc.)

**Action row** (three equal buttons):
- `Show astro` — drives gimbal to computed astro position
- `Snap var` — copies measured variance into offset fields
- `Next` — bake the Current row (with confirm)

**Notes panel** at the bottom (tip text: "Push gimbal by hand,
type label, tap Next").

**Event types** (final set, after consulting Excel VBA and
original Day-8 design):
1. **PF** — Pan follow (gimbal yaw tracks cart yaw)
2. **Lock** — Hold position
3. **Move-to** — Manual pose capture
4. **Track sun** — Live sun tracking (different from Move-to
   sunset which is a one-shot position)
5. **Sunrise** — Astro target with rise/mid/end keyframes
6. **Sunset** — Astro target with rise/mid/end keyframes
7. **MW** — Milky Way astro target with rise/mid/end keyframes

Reserved fields from the Day-8 design (Extra 1, Extra 2) dropped
this session.

---

## Execution — body

**Plan state row** under the header tabs:
- One line, monospace, centred
- `Running · T+02:14 / 04:18 · photos 487 · CCAPI live`

**Gimbal chart** (wide and shallow, immediately under plan state):
- The operator's main reassurance picture
- Yaw axis: `[yaw_min, yaw_min + 450°]` — Excel computes yaw_min
  at plan-bake time, cart receives it
- Pitch axis: 20°–80° (narrowed from Day-10's 0°-90°; matches
  usable range)
- Dashed line at 80° (mechanical limit reminder)
- Waypoint dots on the path
- Catmull-Rom path connecting dots
- Path coloured by velocity band:
  - Blue = ease segment (transition)
  - Green = <0.05°/sec (slow / astro track)
  - Amber = 0.05–0.3°/sec (deliberate manual pan)
  - Red = >0.3°/sec (fast move, may need cable check)
- Live camera icon (small filled rectangle) at the Plan's current
  (yaw, pitch). Orientation fixed (no rotation by yaw).
- Chart purpose: at-a-glance show "where we are now", "where fast
  moves are coming", "why we're not on sunset yet", whole shape
  of the night in one image

**Three waypoint cards** (Last / Now / Next):
- Compact, one row of three equal cells
- Now visually emphasised (different background colour)
- Each card shows name + time/progress info

**Anchor cluster** (one line):
- BNO anchor info only — iPhone-anchor mechanism dropped this
  session (operator unable to improve on BNO accuracy at night)
- E.g. `Anchor: last Δ +0.8° at T+01:39 · next anchor row in 22m`

**Adjustment row** (4 equal cells at the bottom):
- `ToGo 280 mm` (read-only readout, in-palette panel, NOT a
  button — same visual as the notes panel surface, monospace)
- `−100mm` (nudge button)
- `+100mm` (nudge button)
- `PAUSE` (toggles to `RESUME` when active)

**Now message** (small notes-panel-style line at the bottom):
- E.g. `Now · ease toward sunset, no fast moves for 14m`
- In-flow prompt; can become a checkpoint prompt when a Plan
  anchor row is due

**Removed from Execution** (vs Day-10 design):
- iPhone-anchor checkpoints (out — see anchor cluster above)
- Pre-start heading-validation checklist with iPhone cross-check
  (out for same reason)
- Scheduled mid-execution iPhone prompts (out)
- DEAD STOP renamed to PAUSE (out, the abort function entirely;
  no quick-abort exists on this screen)

---

## Cross-cutting usability decisions

**Confirmations** (worked out this session):
- DEAD, DE-E, Mark wpt (Cart Recon), Capture/Next (Gimbal Recon)
  all require operator confirm-tap
- ENRG does NOT confirm (energising is recoverable)
- PAUSE does NOT confirm (pause is reversible)
- Tab switching does NOT confirm (recons each happen once,
  current row persists across switches, nothing is ever lost)

**Polling**: stay at 3s (cart is slow-motion, 4mm per 3s at 5 m/hr).
Workfront #27 resolution remains correct; no WebSocket needed.

**Mark wpt / Capture feedback**: button shade shift on confirm-tap,
in-palette. No flash, no popup. Persistent counter in status row
not needed — Last row's `#N` is the count.

**Connection loss indicator**: row-1 (HyperLapse title row)
background flips to a warm/amber colour as the alarm. Other rows
stay in cool/grey/red palette. Threshold not finalised (3s / 6s /
10s).

**Tap targets** at iPhone SE 3 size: OK at design-time, will
verify in operator acceptance testing. Tap precision at night
similar.

**Two-hand use**: assumed available. Operator's hands free for the
phone (cart is autonomous during shoot; gimbal is push-mode during
recon).

---

## What's NOT in this design

- iPhone compass anchor mechanism (out — BNO-only)
- Per-segment skip / advance button on Execution (use PAUSE +
  −100mm-past-zero combo instead)
- Reset button anywhere (TBD what it would reset)
- Brightness control in app (operator handles via OS brightness)
- Haptic feedback (Vibration API support uneven on iOS)
- Per-screen notes content differences (use same panel content
  across screens, can be refined later)

---

## Open / deferred

- **Connection-loss threshold** — 3s / 6s / 10s / configurable
- **Layout under crowded conditions** — what wins above-the-fold
  if Execution gets more content
- **Pre-start checklist** — what does it actually contain now
  that iPhone-anchor is out?
- **Logging actual gimbal readback** alongside Plan position for
  post-shoot review — not designed
- **Pre-start preview animation** of Plan path — not designed

---

## References

- Day-15 Part 8 + 9 in WORKFRONTS — gimbal execution model and
  PAUSE / ±100mm semantics (the cart firmware behaviour that
  underlies this UI's Execution screen)
- Day-10 `UI_DESIGN_SUMMARY.md` — first-pass design, three-screen
  decision, heading-architecture history
- GIMBAL_VIZ.md — chart velocity bands and original Day-8 event
  vocabulary
- Existing sketch SVG icons at lines 4760+4763 (RS4 + R3) — reused
  in the new header
