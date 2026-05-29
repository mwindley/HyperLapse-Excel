# Plan Authoring — Architecture

**Status:** P1–P6 built; P7 designed; P8–P10 not started.

**Last updated:** 26 May 2026 (Session E day 20 — vocabulary
refined, P6 anchor resolver built, P7 design locked)

This file is the single source of truth for the cart + gimbal
Plan-authoring surface. Future Claude sessions: read this BEFORE
writing any code for the operator's Plan sheet. The architecture
was decided across multiple sessions and is hard-won; please don't
re-invent it from a partial reading of the .bas modules.

**Session E changes** (in summary; details below):
- Gimbal action vocabulary refined to **Pan Follow / Lock / Move /
  Track / Track-yaw / END**. Day-19's "Approach" word is dropped;
  Move handles static targets, Track handles moving (astro) targets.
  Track-yaw is the yaw-only variant (matches firmware GTM_YAW='Y'
  in the sketch).
- Dropped middle-zone columns: Target type (derivable from Target),
  KF (sunrise/sunset/etc. are themselves astro events, not keyframes
  of something else).
- Added middle-zone columns: **Ry** and **Rp** (auto-populate from
  recon for marker targets, typed for Track-yaw, blank otherwise);
  **Ease** (named bands: none / Just-perceptible / Comfortable /
  Cinematic); **Total dur** (derived).
- Replaced End anchor column with a sentinel **END row** at the
  end of the plan. END uses the same anchor mechanic as any other
  row; defines when the plan stops.
- WP # collapse: col B (Cart Plan Step) and col M (Gimbal Plan Step)
  are now `WP01`/`GP01` text labels. Col H (separate WP # column)
  dropped. Anchor resolver formula MATCHes against col B.
- Photo cadence calibration: rate vocabulary describes cruise
  speed in real-world °/sec. Video appearance varies across cadence
  regimes (22s/1320× vs 2s/120× pre-post-speedup). Operator's
  typical post-speedup at 2s cadence is 4–8×, narrowing the spread.
- Ease semantics: rate band = cruise (middle) speed exactly as
  authored. Total slew duration includes ease in + cruise + ease out.
  If next-row Fires-at arrives before slew + eases complete,
  validation errors.
- Velocity-band colour on the chart represents cruise speed only
  (drop §7's "blue = ease segment marker" convention).

---

## Context — where this fits

After a recon drive (manual ~100 m/hr ~20-50 m scout with handful
of waypoints):

- **CartLog sheet** is populated by `Cart.GetCartLog` — every cart
  event (S start, T turn, +5 steering, W waypoint mark, etc.)
  with timestamps + Tic positions. **Raw recon data.**
- **GimbalLog sheet** is populated by `Cart.GetGimbalLogToSheet`
  / `Gimbal.GetGimbalLog` — every operator-authored gimbal row
  from the Gimbal Recon screen (type, kf, frame, measured offset,
  label, position). **Raw recon intent.**

Today these flow forward into:

- **Sequence sheet** via `Cart.GenerateReplayPlan` — timed cart
  action stream executed at shoot time by
  `Sequence.StartCartReplay` / `RunCartReplayStep`. **Works.**
- Astro pushes (Day 18) via `AstroPush.PushAstroToCart` and
  `AstroPush.PushTrackPathsToCart`. **Works.**

What does NOT exist yet:

- A **gimbal plan executor** equivalent to `RunCartReplayStep`
  for gimbal actions (P8 territory; cart-side firmware mirror of
  the existing cart plan executor at sketch line 2513).

What DOES exist (built across Day 19 + Session E):

- **Plan sheet** with three zones — left (Cart Plan, editable),
  middle (Gimbal Plan, editable), right (Gimbal Log reference,
  read-only).
- **`BuildPlanFromCartLog`** macro (P2) seeds left zone from
  CartLog.
- **`PullGimbalLogToPlan`** macro (P4) populates right zone from
  GimbalLog.
- **P5 middle-zone helpers** (`AddPlanRowFromLog`, `AddBlankPlanRow`,
  `InsertPlanRowAbove`, `DeletePlanRow`, `RebuildAnchorDV`).
- **P6 anchor resolver** — live formula in middle-zone col Q
  ("Fires at") converts (Anchor type, Anchor ref, Offset) to
  absolute wall-clock.
- **P7 design** — `PushGimbalPlan` macro architecture is locked
  (decomposition rules, validation phases, endpoint surface).
  Not built yet.

---

## The Plan sheet — three-zone layout

A single sheet, named **`Plan`**, with three vertical zones:

```
┌──────────────────────┬──────────────────────┬──────────────────────┐
│  LEFT — Cart Plan    │  MIDDLE — Gimbal     │  RIGHT — Gimbal Log  │
│  (B..K)              │  Plan (M..AB)        │  (AD..AM)            │
│                      │                      │                      │
│  Editable.           │  Editable.           │  Read-only           │
│  Populated from      │  Authored by         │  reference.          │
│  CartLog via Build   │  operator using      │  Populated from      │
│  Plan macro.         │  rows from RIGHT     │  GimbalLog.          │
│                      │  as building blocks. │                      │
│  Cart waypoints,     │  Each row: Pan       │  Two row types:      │
│  speeds, turns,      │  Follow / Lock /     │  static marker (Ry/  │
│  durations, arrival  │  Move / Track /      │  pitch + label) and  │
│  time-of-day per     │  Track-yaw / END,    │  astro framing       │
│  step.               │  anchored to WP /    │  (Δyaw/Δpitch + KF + │
│                      │  TIME / ASTRO event. │  label).             │
│  Excel recomputes    │                      │                      │
│  downstream timings  │  Carries target,     │  Operator references │
│  when operator       │  rate, Ry/Rp,        │  these when authoring│
│  edits.              │  offsets, ease;      │  middle zone.        │
│                      │  Excel computes      │                      │
│                      │  Fires-at + Total    │                      │
│                      │  dur per row.        │                      │
└──────────────────────┴──────────────────────┴──────────────────────┘
```

Visual gutter at column AC between middle and right zones.

The Plan sheet is the operator's working surface for the **night's
shoot**. CartLog and GimbalLog remain as the raw recon audit trail.

---

## Left zone — Cart Plan (cols B..K)

### Columns

| Col | Field             | Editable | Notes                                       |
|-----|-------------------|----------|---------------------------------------------|
| B   | Step              | derived  | `WP01`, `WP02`, ... text formula. Every row is a waypoint (STOP rows included — once a row is in the plan it is a position). |
| C   | Action            | yes      | DRIVE, STOP                                 |
| D   | Distance (mm)     | yes      | for DRIVE; derived from CartLog initially   |
| E   | Speed (m/hr)      | yes      | for DRIVE; recon's actual speed is the seed |
| F   | Turn (deg)        | yes      | for TURN; +5, -10, etc.                     |
| G   | Hold (sec)        | yes      | for STOP                                    |
| H   | (unused — gutter) | —        | Was WP # in P6 layout; collapsed into col B in Session E.  |
| I   | Distance from t=0 | derived  | running total                                |
| J   | Arrives           | derived  | wall-clock when cart arrives at this step   |
| K   | Note              | yes      | operator free text                          |

### Operator's job, left zone

Cart fix-up. The recon data is approximate — the operator scouted
at 100 m/hr; the shoot may run at 20 m/hr. The +5° turn during
recon may want to be +10° at shoot speed. The "drive 2 m" segment
between waypoints may be too short or too long because operator
slipped past the mark.

Operator works **top-to-bottom** through the Cart Plan, editing
speeds/distances/turns. Excel recomputes the **time-of-day** for
each waypoint based on shoot start anchor (`dataShootStart`
named range on Settings) + cumulative durations.

Critical mechanic: **waypoint numbers stay stable** across edits.
If the operator changes "drive 2 m" to "drive 3 m" on step 4, the
waypoint marker WP03 doesn't change identity, just moves later in
wall-clock time.

### Generated by

**`BuildPlanFromCartLog`** (built Day 19) — reads CartLog, writes
left zone with recon-time values as seeds, leaves operator to fix-up.

Session E update: writes col B as `WP` & 2-digit format (e.g.
`WP01`). Does NOT write col H (which is now unused).

### Pushed to cart by

`PushCartPlan` (not built yet; analogous to current
`GenerateReplayPlan` + `StartCartReplay`). Generates the same
/btn, /move, /home stream the existing code produces.

---

## Right zone — Gimbal Log reference (cols AD..AM)

### Recon capture model

The Gimbal Recon screen captures only two kinds of row, both taken
with the cart **parked** (so cart heading is stable and unambiguous
— read from CartLog at the timestamp range of captures, not stored
per row):

1. **Static marker.** Operator pushes the gimbal to a scene point
   (Tree, Harbour, Hill), types a label, presses "Mark scene".
   Row records (timestamp, type=marker, Ry, pitch, label).
2. **Astro framing.** Operator picks an astro target (sun / moon /
   MW / sunrise / sunset / moonrise / moonset / mwrise / mwtransit /
   mwset) and a keyframe (rise / mid / end where applicable).
   Presses "Show astro" — Excel-pushed astro tables (must be on
   cart at recon time, not just at execution) drive the gimbal to
   the predicted astro position. Operator pushes gimbal to adjust
   framing through the camera, types a label, presses "Snap framing".
   Row records (timestamp, type=astro+keyframe, Δyaw, Δpitch from
   predicted, label).

All captures real-world frame; cart-frame interpretation only arises
in the Plan sheet when authoring a Pan Follow row (which is
cart-frame by construction).

The composition work — picking action types, anchors, rates,
sequencing — does NOT happen in the field. That happens in Excel
back at the van. Matches the "Visualisation > Manipulation"
principle: recon is observation, planning is composition.

### Columns (Session E layout — right zone shifted to AD..AM)

| Col | Field            | Recon type          | Notes                            |
|-----|------------------|---------------------|----------------------------------|
| AD  | Log row #        | both                | row number on GimbalLog sheet    |
| AE  | Timestamp        | both                | HH:MM:SS                         |
| AF  | Type             | both                | "marker" / "astro"               |
| AG  | Astro target     | astro only          | sun / moon / mw / sunset / etc.  |
| AH  | Keyframe         | astro only          | rise / mid / end                 |
| AI  | Ry (yaw)         | marker only         | gimbal yaw at capture            |
| AJ  | Pitch            | marker only         | gimbal pitch at capture          |
| AK  | Δyaw             | astro only          | offset from predicted astro yaw  |
| AL  | Δpitch           | astro only          | offset from predicted astro pitch|
| AM  | Label            | both                | operator's free text             |

Marker rows leave AG/AH/AK/AL blank; astro rows leave AI/AJ blank.

### Behaviour

Read-only. Refreshed by **`PullGimbalLogToPlan`** (built Day 19,
updated Session E for the right-zone shift). Refreshes the reference
from current GimbalLog sheet contents.

This zone informs the operator what gimbal-plan rows are available
to build from. Each right-zone row is a building block:

- **Marker row** (Tree, Harbour, Hill) → **Move** with the marker
  label as Target in the Plan sheet. Ry/Rp auto-populate via formula
  from this right-zone row's AI/AJ.
- **Astro framing row** (sunset+mid, moonrise+rise, etc.) → typically
  becomes a **Move** with the astro object as Target plus the
  captured Δyaw/Δpitch. The KF distinction (rise/mid/end) becomes
  part of the anchor (Anchor ref = sunrise / sunset / moonrise etc.),
  not a target descriptor.

### #49 — GimbalLog enrichment status

Today's GimbalLog has (Timestamp, Yaw, Pitch, Notes) — 4 fields,
no type/label/keyframe/offset. Per-row rich capture is a cart
firmware change tracked as workfront #49. The 7-field shape above
is the target.

Cart firmware-side already has the rich enum in the sketch
(GT_PF / GT_LOCK / GT_MOVE / GT_TRACK / GT_SUNRISE / etc., plus
GTM_FULL/GTM_YAW track-mode tag — see sketch lines 1075–1104).
That's the field-side capture vocabulary, separate from this Plan
layer's action vocabulary.

Mapping: the capture-side Day-16 vocabulary feeds the right-zone
reference table; operator composes Session E vocabulary (4 actions +
yaw-only variant + END) in the middle zone.

---

## Middle zone — Gimbal Plan (cols M..AB)

### Action vocabulary (Session E — six values including END)

| Action          | What it does                                                    |
|-----------------|-----------------------------------------------------------------|
| **Pan Follow**  | Gimbal yaw = cart yaw + offset (cart-frame). Pitch holds.       |
| **Lock**        | Freeze the current absolute (real-world) pose. Counter-rotates  |
|                 | as cart turns.                                                  |
| **Move**        | Slew to a static target at chosen rate, hold on arrival. Target |
|                 | may be a marker (Tree/Harbour) or a snapshot pose (sun at the   |
|                 | row's Fires-at time).                                           |
| **Track**       | Slew to a moving astro target at chosen rate, then follow at    |
|                 | sky rate. Two-phase, one row. Excel pre-computes Phase A        |
|                 | (convergence) via pursuit-curve iteration; Phase B (tracking)   |
|                 | reuses the per-shoot per-object cubic on the cart.              |
| **Track-yaw**   | As Track but pitch held fixed at operator-typed Rp. Yaw         |
|                 | follows the astro object. Matches firmware GTM_YAW='Y'.         |
| **END**         | Sentinel row. Defines when the plan ends. No segment emitted    |
|                 | to cart; previous row's hold-tail extends to END's Fires-at.    |

That's it. Six values, one of which (END) appears exactly once
per plan (the last row).

### Rate vocabulary

Operator picks a rate from a named set (Excel-side parameters on
the Settings sheet, editable per shoot):

| Rate            | °/sec  | Use                                            |
|-----------------|--------|------------------------------------------------|
| Imperceptible   | 0.004  | Astro drift territory                          |
| Cinematic ease  | 0.05   | Comfortable, default for most moves            |
| Deliberate pan  | 0.15   | Operator-pan feel, more energy                 |
| Fast            | 0.30   | Punchy. Approaches red on velocity-band chart  |
| Snap            | (fixed | Near-instant. 2–5s slew regardless of distance |
|                 | dur)   |                                                |

The rate band describes the **cruise (middle) speed in real-world
°/sec**, exactly as authored. Total slew duration =
(slew_distance / cruise_rate) + ease_in + ease_out, plus hold tail.

For rows where the operator doesn't pick the rate (Track — rate is
the object's sky rate; Pan Follow — rate is cart's yaw rate;
Lock — rate is 0; END — no rate), the rate cell displays the literal
text **"Computed"** or `—` so the column is never blank.

### Cadence regime calibration

The rate vocabulary is calibrated against **night (22s cadence,
1320× video speedup)**. During 2-second-cadence transition periods
(sunset/sunrise/twilight), the same authored real-world rate plays
back faster in video. Operator's typical post-edit speedup at 2s
cadence is 4–8×, giving 480–960× effective video speedup — closer
to night's 1320×.

Spread on the same rate band across regimes is roughly 2.7×. Band
names still convey approximately the right intent. Operator accepts
the variation; post-edit speed control finishes the job.

### Ease vocabulary (Session E)

Operator picks an ease from a named set on the Settings sheet:

| Ease band         | Frames at 60fps | Audience perception          |
|-------------------|-----------------|-------------------------------|
| none              | 0               | Hard start/stop               |
| Just-perceptible  | ~3              | Abrupt but noticed            |
| Comfortable       | ~10             | Cinematic feel                |
| Cinematic         | ~30             | Slow, deliberate              |

Same ease in as ease out (single column). Excel converts band →
frames → real-world duration via the cadence active at the row's
fire time (Tv from Appendix A drives cadence).

Ease applies meaningfully to **Move** and **Track-Phase-A**. Pan
Follow, Lock, Track-Phase-B, and END have no ease boundaries.

### Hold-vs-fill — hold is the default

After a Move to a static target, the gimbal holds at that pose
until the next gimbal row fires. The gap (between "arrived" and
"next row starts") is dead-still hold time.

The operator absorbs gaps by editing the **cart plan** (slow a
leg, extend a distance, move the action to a later waypoint) — NOT
by stretching the gimbal rate. This keeps the rate vocabulary
consistent and the visual feel of pans uniform across the night.

### Columns (Session E layout — middle zone M..AB, 16 cols)

| Col | Field         | Editable | Notes                                                                                          |
|-----|---------------|----------|------------------------------------------------------------------------------------------------|
| M   | Step          | derived  | `GP01`, `GP02`, ... text formula                                                               |
| N   | Anchor type   | yes      | WP / TIME / ASTRO                                                                              |
| O   | Anchor ref    | yes      | "WP05" / "23:30" / "sunset" / "sunrise" / "moonrise" / "moonset" / "mwrise" / "mwtransit" / "mwset" |
| P   | Offset (min)  | yes      | Plain number, positive or negative. Blank = 0.                                                 |
| Q   | Fires at      | derived  | Anchor resolver formula (P6). Wall-clock time.                                                 |
| R   | Total dur     | derived  | Next row's Fires-at − this row's Fires-at. Operator sees row duration at a glance.             |
| S   | Action        | yes      | Pan Follow / Lock / Move / Track / Track-yaw / END                                             |
| T   | Target        | yes      | Marker label ("Tree") / astro object ("sun", "moon", "mw") / `—`                               |
| U   | Rate          | yes      | Named band, or "Computed", or `—`                                                              |
| V   | Ry            | yes      | Auto-populate formula for marker target; `—` otherwise. Operator may override.                 |
| W   | Rp            | yes      | Auto-populate formula for marker target; **typed for Track-yaw** (absolute held pitch); `—` otherwise. |
| X   | Δyaw          | yes      | Offset from Ry, default 0                                                                      |
| Y   | Δpitch        | yes      | Offset from Rp, default 0                                                                      |
| Z   | Ease          | yes      | none / Just-perceptible / Comfortable / Cinematic                                              |
| AA  | Move t        | derived  | Excel-computed slew duration including ease                                                    |
| AB  | Note          | yes      | Operator free text                                                                             |

### Ry/Rp semantics

`V (Ry)` and `W (Rp)` carry the **real-world target pose** the
gimbal aims at. Three populating modes:

1. **Marker target (Tree/Harbour/etc.):** Formula looks up the
   target label in the right-zone Label column (AM) and returns
   the matching Ry (AI) / Pitch (AJ). Operator sees the values
   inline; can override by typing.
2. **Track-yaw row:** Operator types Rp directly as the held pitch.
   Ry shows `—` (yaw is following the astro object). To record a
   "framed" pitch from the field, operator captures a marker during
   recon and types that marker's pitch into the Track-yaw row's W
   cell. **The Plan does NOT auto-resolve a marker name back into
   Rp for Track-yaw** — that would make Track-yaw rows depend on
   marker existence, breaking the simple model.
3. **Other rows (astro Move, Pan Follow, Lock, END):** Both `—`.

A **"Refresh marker poses"** helper macro (TBD) rewrites the
formula into V/W cells across all marker-targeting rows; restores
the auto-link after override.

### Authoring workflow

1. Operator reviews right zone — sees the recon-captured static
   markers (Tree, Harbour, Hill — type=marker rows) and astro
   framings (sunset/moonrise/etc. with captured Δyaw/Δpitch —
   type=astro rows).
2. Operator picks a row from right zone (or starts from scratch).
3. Copies into middle zone with a building-block macro, or types
   from scratch.
4. Picks Action (Pan Follow / Lock / Move / Track / Track-yaw),
   Target, etc.
5. Decides the anchor:
   - **WP** anchor: action fires when cart reaches waypoint.
   - **TIME** anchor: action fires at wall-clock time.
   - **ASTRO** anchor: action fires at named astro event time.
   - Optional Offset (minutes, + or −).
6. Picks Rate.
7. Edits Δyaw/Δpitch if framing needs offset from raw target.
8. Picks Ease (default `none`).
9. Last row is **END** with anchor/ref/offset defining plan end.

### Anchor semantics (P6 built)

- **WP anchor is sticky.** If operator nudges cart waypoint
  (left zone) — say, extends a drive leg by 500mm — gimbal plan
  rows anchored to that waypoint inherit the new arrival time.
  Operator does NOT edit middle zone in response.
- **TIME anchor is absolute.** Wall-clock time. Independent of
  cart progress.
- **ASTRO anchor is computed.** Excel reads the astro event time
  from named ranges (`dataSunsetTime`, `dataMoonriseTime`, etc.)
  at formula-time and converts to absolute wall-clock.

Anchor resolver formula in col Q (Fires at) handles all three
branches plus the offset. Lives in every middle-zone data row;
recomputes live as operator edits.

### Track — the two-phase pursuit

A Track row covers both the convergence slew and the subsequent
tracking. The maths:

- **Phase A — Convergence.** Gimbal slews from current pose at the
  chosen rate toward the *predicted future position* of the target.
  Excel iterates: estimate slew duration → look up target position
  at slew-end time → recompute distance → re-derive duration →
  converge (2–3 iterations is usually enough; the sun moves slowly
  vs the slew rate).
- **Phase B — Tracking.** Once gimbal has converged with target,
  path = target's path. Cart-side, the gimbal evaluates the
  pre-pushed `track_<obj>` cubic each photo cycle.

No transition between phases — continuous Catmull-Rom path.

**Rate column semantics for Track:**
The Rate cell governs **Phase A only** — it's the convergence
rate the operator chose. Once Phase B begins, the gimbal moves at
the *target's* rate (typically Imperceptible band for astro
objects). So a single row like "Track sun, Cinematic ease"
executes as Cinematic ease followed by Imperceptible, back to back,
continuously.

Operator's mental model: *"Rate = how I'm getting there; what
happens once I arrive is the object's sky rate."*

### Track-yaw

As Track for the yaw axis. Pitch holds at the operator-typed Rp
value (col W). Matches firmware GTM_YAW='Y' mode where `offP` is
absolute fixed pitch (not a Δ).

Use case: lock horizon at rule-of-thirds line, let the sun/moon/MW
yaw drift across the frame while foreground composition stays
fixed.

### Spanning actions

A Move/Track row spans from its anchor (Fires-at) to the start of
the next row, which is the usual case. Examples:

- "Move Harbour, Cinematic ease, at WP3" — slews toward Harbour
  starting at WP3 arrival, holds at Harbour from arrival to start
  of next row.
- "Track sun, Cinematic ease, at WP5" — slews toward sun starting
  at WP5, converges via pursuit curve, then tracks sun until next
  row starts.
- "Move sun at sunset, Δyaw +30, Δpitch +20, Cinematic ease" —
  anchor ASTRO sunset, target=sun. At sunset, sun's position is
  evaluated, +30/+20 added → endpoint pose. Slews to that, holds
  until next row.

### END row semantics

Last row of every plan. Anchor type / ref / offset defines when
the plan ends. Action = END. No target, no rate, no ease — those
columns blank or `—`.

Validation rule: the last row must be END. No rows after END.
END's Fires-at = the plan's hard stop time.

---

## Output to cart — three streams

When operator presses "Push Plan" (P7):

### Stream 1 — Cart action stream (existing)
Read left zone, emit /btn, /move, /home calls via
`RunCartReplayStep`-style macro. No change to existing cart side.

### Stream 2 — Astro pushes (existing, Day 18)
`PushAstroToCart` + `PushTrackPathsToCart` populate
/settings/astropos + /settings/trackpath. Done as part of plan
push, not per-row. Also needs to be pushed pre-recon so "Show
astro" framing capture has data on cart.

### Stream 3 — Gimbal action stream (P7 — designed, not built)

Read middle zone. Each Plan row decomposes:

| Plan row | Cart stream |
|---|---|
| Pan Follow | One PANFOLLOW segment for row duration |
| Lock | One HOLD segment at current real-world pose |
| Move (marker target) | One CUBIC slew (current pose → V+X, W+Y) + HOLD tail |
| Move (astro snapshot, e.g. sun at sunset) | Excel evaluates `track_<obj>` at Fires-at → endpoint, then CUBIC slew + HOLD tail |
| Track full | One **TrackInterval** push (mode=F, offY=Δyaw, offP=Δpitch) |
| Track-yaw | One **TrackInterval** push (mode=Y, offY=Δyaw, offP=W absolute) |
| END | No segment emitted; provides Fires-at for previous row's hold-tail end |

**Slew interpolation: always CUBIC** (Session E decision). Excel
computes coefficients encoding cruise rate + ease in + ease out.
Cart-side `at³+bt²+ct+d` evaluator stays unchanged.

**Track decomposition is NOT a cubic stream.** Track rows push a
single ~16-byte TrackInterval to the cart's `track_plan[]`. The
per-object cubic data (`track_sun`, `track_moon`, `track_mw`) is
pushed separately by `PushTrackPathsToCart` once per shoot via
`/settings/trackpath`. Cart evaluates which interval is active at
each cycle and reads the appropriate `track_<obj>` cubic.

Sketch reference: TrackInterval at line 979, TrackPath at line 959,
`/trackplan/load` endpoint, TRACK_SEGS_MAX=8 (Giga), TRACK_PLAN_MAX=10.

### Time anchoring

Cart's `track_plan_anchor_ms` is set at plan start (`millis()`).
All segment ts/te values are relative to that anchor (in ms).
Excel converts wall-clock author times to ms-from-anchor at push
time. WP-anchored rows have their absolute time resolved at push
time from the cart plan's computed waypoint-arrival times.

---

## P7 macro design — five phases

`PushGimbalPlan` operator-pressed button.

### Phase 1 — Validate

Walk middle-zone rows top-to-bottom. Check:
- Anchor type ∈ {WP, TIME, ASTRO}; Anchor ref resolves (Fires-at
  not blank)
- Action ∈ {Pan Follow, Lock, Move, Track, Track-yaw, END}
- Target sensible for Action (Move needs marker or astro;
  Track/Track-yaw need astro)
- Rate set where required
- Ry/Rp populated where required (Move-to-marker uses formula;
  Track-yaw needs operator-typed Rp)
- Ease ∈ valid bands
- Last row is END; no rows after END
- For each Move/Track row: total duration ≥ slew + ease in + ease out

If anything fails, abort with row-numbered error list. Don't push
anything.

### Phase 2 — Prerequisites

- If any Track/Track-yaw row references sun/moon/MW, ensure
  `track_<obj>` is loaded on cart. If not, call `PushTrackPathsToCart`.
- If any ASTRO anchor is used, ensure astro event times pushed
  via `PushAstroToCart` match what Excel has.

### Phase 3 — Decompose rows

Walk rows in order, build the segment + interval lists per the
mapping table above.

### Phase 4 — POST to cart

Sequential GETs, retry on failure, log per-segment.
- `/plan/load?seg=N&...` — HOLD/CUBIC/PANFOLLOW
- `/trackplan/load?idx=N&...` — TrackIntervals
- `/settings/trackpath?...` — cubics (only if not already pushed)

**Twice-called PushGimbalPlan does a full reset + repush** (Session E
decision). Predictable over fast.

### Phase 5 — Summary

Report segments + intervals pushed. Ready to execute via /plan/start
(P8).

---

## Implementation phases — workfront cluster

These are sub-workfronts; not individual roadmap entries until
operator picks priority order.

**P1. Sheet design + layout.** Build the Plan sheet in
HyperLapse.xlsm. Three zones, column headers, conditional formatting
for action types, drop-down validation. **DONE (Day 19,
refreshed Session E).**

**P2. CartLog → Cart Plan macro.** `BuildPlanFromCartLog` —
reads CartLog, writes left zone with recon-time values as seeds.
**DONE (Day 19); Session E update pending in repo** (col B
text format, col H dropped).

**P3. Left-zone recompute formulae.** When operator edits
speed/distance/turn, time-of-day downstream updates. **DONE (Day 19)
as cell formulas.**

**P4. GimbalLog → right zone copy.** `PullGimbalLogToPlan` —
copies GimbalLog rows into right zone. **DONE (Day 19); Session E
right-zone shift applied in `GimbalLogPuller_P6.bas`.**

**P5. Middle-zone authoring helpers.** Buttons to copy a
right-zone row into middle zone with sensible defaults. **DONE (Day
19); Session E vocabulary update pending in repo** (new actions,
dropped S/U, new V/W/Z/AA).

**P6. Anchor resolver.** Live formula in col Q converts
(Anchor type, Anchor ref, Offset) to wall-clock. **DONE (Session E).**

**P7. Plan push — gimbal stream.** `PushGimbalPlan` —
five-phase macro per the design above. **DESIGN LOCKED (Session E);
not built.**

**P8. Plan execute — both streams.** Modify existing
`StartCartReplay` / `RunCartReplayStep` to also drive the gimbal
stream. Requires cart-side gimbal plan executor (firmware mirror of
the existing cart plan executor at sketch line 2513).

**P9. Live-progress display.** During execution, show operator
which row is firing now, which is next, time-to-next. Required for
any reasonable operator UX during the 8-hour shoot.

**P10. Plan validation.** Pre-flight check before pushing.
Phase 1 of P7 covers most of this; P10 adds cinematic checks (no
"Fast" Track during astro tracking spans, etc.).

---

## Open questions

These weren't resolved in the design conversations; future Claude
should re-raise before building.

**Inherited from Day 18:**
- **Does the Cart Plan need a "shoot start" anchor cell** explicitly,
  or is it taken from `dataShootStart`? Today, recon happens at
  ~3pm, shoot starts at ~4pm or sunset. Operator might want to test
  different start times during authoring.
- **Pano master config storage.** Pano cells (yaw/pitch grid) are
  master-config today per WORKFRONT #33. Plan rows would just say
  "fire pano". Confirm Plan doesn't need to author the pano cells
  per-row; only the trigger. **Re-raised:** where does Pano sit in
  the Session E vocabulary? Likely a seventh action (Pano) with its
  own row shape, since pano is a multi-cell state machine not a
  single pose.
- **Operator interruption during shoot** — pause / skip / nudge.
  How does Plan reflect a paused/aborted/nudged execution?
  Workfront #5 territory; out of scope for first cut.
- **Multi-night shoots.** Plan is single-night today. If operator
  wants two consecutive nights, two Plan sheets or one with a
  break? Out of scope first cut.

**Raised Session E:**
- **Marker pose refresh macro.** "Refresh marker poses" reinstates
  the V/W formula after operator override. Not yet specified —
  what trigger, what does it look like?
- **Ease band defaults on Settings sheet.** Placeholders added
  (`dataEaseJustPerceptible` = 3, `dataEaseComfortable` = 10,
  `dataEaseCinematic` = 30 frames). Cadence-aware conversion not
  built; needs Excel formula that reads Tv at the row's Fires-at
  to compute real-world ease duration.
- **Pano action.** As above — re-raise from Day 19, still unresolved
  in Session E.
- **#49 sequencing.** Cart firmware enrichment must land before
  Excel-side Plan macros can be tested end-to-end. The capture-side
  vocabulary (in the sketch) is Day-16 era; the GimbalLog rich
  shape arrives with #49. Plan layer (this doc) is Session E
  vocabulary; mapping layer between the two is light but needs to
  be exercised end-to-end.
- **Cart-side gimbal plan executor.** P8 territory. Mirrors existing
  cart plan executor at sketch line 2513. Doesn't exist yet.
- **Endpoint URL/payload formats for P7 push.** `/plan/load`
  exists for cart; needs extension or parallel `/gimbalplan/load`
  for gimbal segments. `/trackplan/load` already exists for Track
  intervals. Survey before building P7 Phase 4.

---

## Decision log

| When        | Decision                                                                  |
|-------------|---------------------------------------------------------------------------|
| Day 8       | Catmull-Rom astro pre-baked in Excel, cart sees cubic coefficients only.  |
| Day 12      | Cart owns per-photo exposure walk (#36b). Excel doesn't loop per photo.   |
| Day 18 eve  | Single Plan sheet, three zones (cart / gimbal plan / gimbal log).         |
| Day 18 eve  | WP binding is sticky — nudging cart WP moves bound gimbal rows.           |
| Day 18 eve  | TIME and ASTRO bindings supported for after-cart-parks-for-night gimbal.  |
| Day 18 eve  | Cart is dumb on gimbal plan — cart just stops at right position.          |
| Day 18 eve  | Recon-time gimbal offsets seed Middle-zone rows; operator can override.   |
| Day 19      | (Superseded Session E) Vocabulary: Pan Follow / Approach / Lock.          |
| Day 19      | (Superseded Session E) "Approach" unifies Move-to and Track.              |
| Day 19      | Rate vocabulary: 5 named bands as Excel-side parameters.                  |
| Day 19      | "Computed" literal in Rate cell where operator doesn't author the rate.   |
| Day 19      | Hold-until-next is default. Operator absorbs gaps via cart plan edits.    |
| Day 19      | Recon captures simplified: static marker + astro framing. R/C dropped.    |
| Day 19      | Gimbal plan composition happens at Excel, not in field.                   |
| Day 19      | Astro tables pushed pre-recon (for "Show astro" framing).                 |
| Day 19      | Sunset/sunrise are useful T0 anchors; any astro event works.              |
| Session E   | **Vocabulary refined: Pan Follow / Lock / Move / Track / Track-yaw / END**. |
|             | Approach split into Move (static target) + Track (moving target).         |
| Session E   | Track-yaw is yaw-only variant; aligns with firmware GTM_YAW='Y'.          |
|             | offP carries absolute fixed pitch (not Δ) for Track-yaw.                  |
| Session E   | Dropped middle-zone S (Target type — derivable from Target) and          |
|             | U (KF — astro events aren't keyframes of something else).                 |
| Session E   | Added middle-zone Ry, Rp (auto-pop for markers, typed for Track-yaw),    |
|             | Ease (named bands), Total dur (derived).                                  |
| Session E   | Dropped middle-zone End anchor column. Plans end with sentinel END row.   |
| Session E   | Col B (Cart Step) and M (Gimbal Step) are text formulas — `WP01`/`GP01`.  |
|             | Col H (WP #) dropped from left zone; anchor resolver MATCHes col B.       |
| Session E   | STOP is a waypoint — once it's in the plan, it's a position the operator |
|             | can reference like any other.                                             |
| Session E   | Ease semantics: rate band = cruise speed; total slew = ease in + cruise + |
|             | ease out + hold tail. Validation errors if next row arrives too soon.     |
| Session E   | Velocity-band chart colour = cruise speed only. Drop §7 blue-as-ease.     |
| Session E   | Cadence regime: rate vocab calibrated to 22s/1320×. 2s cadence + 4–8×    |
|             | post-speedup keeps spread at ~2.7×. Operator accepts.                     |
| Session E   | Slew interpolation: always CUBIC (encodes cruise + ease).                 |
| Session E   | PushGimbalPlan = full reset + repush every call. Predictable.             |

---

## Worked example — S-bend, 5 m/hr, sunset shoot (Session E vocabulary)

A concrete plan, worked end-to-end. The point is to show **which
fields the operator authors, which Excel computes, and which
sources each field comes from.**

### Anchors

T0 = sunset (any astro event works; sunset is dominant for this
shoot). All times below are offsets from T0.

| Event                       | Time      |
|-----------------------------|-----------|
| Cart start (WP01)           | T0 − 120  |
| WP02 reached                | T0 − 108  |
| WP03 reached                | T0 − 96   |
| WP04 reached                | T0 − 84   |
| WP05 reached (GP02 fires)   | T0 − 72   |
| WP06 reached, cart parked   | T0 − 40   |
| WP07 (STOP — a waypoint)    | T0 − 40   |
| Sunset (GP03 fires)         | T0        |
| Framed sunset pose reached  | T0 + 12   |
| Plan end (GP04 / END)       | T0 + 120  |

### Operator-authored Cart Plan (left zone)

| Step | Action | Distance | Speed   | Turn  |
|------|--------|----------|---------|-------|
| WP01 | DRIVE  | 1.00 m   | 5 m/hr  | 0°    |
| WP02 | DRIVE  | 1.00 m   | 5 m/hr  | +20°  |
| WP03 | DRIVE  | 1.00 m   | 5 m/hr  | 0°    |
| WP04 | DRIVE  | 1.00 m   | 5 m/hr  | −20°  |
| WP05 | DRIVE  | 1.00 m   | 5 m/hr  | 0°    |
| WP06 | DRIVE  | 2.67 m   | 5 m/hr  | 0°    |
| WP07 | STOP   | —        | 0       | —     |

Excel-derived columns (not shown): distance-from-zero, time-of-day
per step. Seed values come from CartLog recon; operator edits speed
from 100 m/hr (recon) down to 5 m/hr (shoot).

### Operator-authored Gimbal Plan (middle zone, Session E)

Four rows. That's the whole gimbal plan.

| GP   | Anchor    | Offset | Action  | Target | Rate           | Ry  | Rp | Δyaw | Δpitch | Ease       |
|------|-----------|--------|---------|--------|----------------|-----|----|------|--------|------------|
| GP01 | WP01      | 0      | Pan Follow | —     | Computed       | —   | —  | 0    | 0      | none       |
| GP02 | WP05      | 0      | Track   | sun    | Cinematic ease | —   | —  | 0    | 0      | Comfortable|
| GP03 | sunset    | 0      | Move    | sun    | Cinematic ease | —   | —  | +30  | +20    | Comfortable|
| GP04 | sunset    | +120   | END     | —      | —              | —   | —  | —    | —      | —          |

Implicit end-times via Total dur column:
- GP01 Total dur = GP02.Fires - GP01.Fires
- GP02 Total dur = GP03.Fires - GP02.Fires
- GP03 Total dur = GP04.Fires - GP03.Fires
- GP04 Total dur = blank (END is the stop)

### Excel-computed (operator may see, doesn't author)

**For GP01 Pan Follow:**
- No computation needed; cart-side PANFOLLOW segment from T0−120
  to T0−72 (= GP02's Fires-at).

**For GP02 Track sun:**
- Starting pose: gimbal at cart-frame Cy=0 / cart heading at WP05.
- Sun position at GP02 fire time (T0−72): from astro table, say
  Ry = 252°, pitch = +16°.
- Angular distance (yaw-dominant): 63° from gimbal current to sun.
- Phase A pursuit iteration:
  - Iteration 1: distance 63° / Cinematic ease 0.05°/sec = 21 min
    slew. Sun moves ~5° in 21 min → target shifts to Ry ~257°.
  - Iteration 2: distance 58° → 19 min slew. Sun moves ~4.7° →
    target Ry ~256.7°.
  - Converges around 19 min / 58° / Ry ~256.7°.
- Phase B: T0−53, gimbal on sun, follows astro path until GP03
  fires at T0.
- Cart side: one CUBIC segment for Phase A slew + one TrackInterval
  for Phase B.

**For GP03 Move sun + Δ:**
- Target pose: sun's position at T0 + (Δyaw +30°, Δpitch +20°).
  - Sun at T0 from astro table: say Ry = 285°, pitch = 0°.
  - Target: Ry = 315°, pitch = +20°.
- Starting pose: where GP02 ended, i.e. sun-at-T0 = (285°, 0°).
- Angular distance: √(30² + 20²) ≈ 36° combined.
- Cinematic ease 0.05°/sec → 720 sec cruise + ease in + ease out.
  Comfortable ease at 22s cadence: ~10 frames × 22s = 220s each end.
  Total slew time ≈ 720 + 220 + 220 = 1160 sec ≈ 19.3 min.
- Cart side: one CUBIC segment (cruise + ease coefficients) + HOLD
  tail until GP04 fires at T0+120.

**For GP04 END:**
- Fires at T0+120 = 19:42. No cart segment; previous row's HOLD
  tail ends here.

### Field sources for each datum

| Datum                          | Source                                          |
|--------------------------------|-------------------------------------------------|
| WP01..7 distances, turns       | CartLog W events + S/T events (recon seed)      |
| Cart speed (5 m/hr)            | Operator edit on Cart Plan (override of recon)  |
| Cart heading at WP05/6         | CartLog (integrated from S/T sequence, or BNO)  |
| Sun Ry/pitch at any time       | Astro table (pushed at plan time + recon time)  |
| Gimbal starting pose at GP01   | Last known gimbal pose (cart-frame yaw = 0)     |
| Δyaw/Δpitch on GP03            | Operator typed in Plan sheet                    |
| Pursuit-curve convergence      | Excel iteration                                 |
| Cubic coefficients per segment | Excel (Catmull-Rom on sampled path)             |
| Wall-clock arrival times       | Operator's `dataShootStart` + cumulative durs   |

### What this reveals

1. **Plan sheet rows are very compact** — 4 gimbal rows (one is
   the END sentinel) cover a 4-hour shoot.
2. **Astro tables carry most of the runtime gimbal data** — sun
   position is looked up at many timestamps during pursuit and
   tracking. They MUST be on cart at recon time (for Show astro)
   AND on cart at execution time (for the plan executor).
3. **The pursuit-curve maths is Excel's job, not the cart's.**
   Cart sees a flat stream of cubic segments and TrackInterval
   pushes. All cleverness is pre-baked.

---

## Cross-references

- `Cart.bas` `GetCartLog` / `ProcessCartLog` / `GenerateReplayPlan`
  / `GetGimbalLogToSheet` / `StartCartReplay` — existing recon →
  plan → execute pipeline for cart side
- `Gimbal.bas` `GetGimbalLog` / `UpdateGimbalDisplay_FUTURE` — the
  current gimbal-side equivalent (incomplete; will be revised under
  #49 to read 7-field rich GimbalLog)
- `Sequence.bas` `StartCartReplay` / `RunCartReplayStep` — current
  cart-execute machinery; gimbal stream should follow the same
  OnTime pattern
- `AstroPush.bas` `PushAstroToCart` / `PushTrackPathsToCart` —
  astro inputs to cart, pushed once per shoot at plan-push time
  (Session E: also needs to be pushed pre-recon)
- `PlanBuilder.bas` (P2), `PlanAuthoring.bas` (P5),
  `GimbalLogPuller.bas` (P4) — the existing Plan macros
- Sketch (`DJI_Ronin_Giga_v2.ino`):
  - HOLD / LINEAR / CUBIC / PANFOLLOW segment types — line 144+
  - TrackPath struct + per-object cubic storage — line 950+
  - TrackInterval struct + track_plan[] — line 977+
  - Gimbal log enum (capture-side vocabulary) — line 1075+
  - GTM_FULL / GTM_YAW track mode tags — line 1102+
  - Cart plan executor (mirror for gimbal-side P8) — line 2513+
  - `/settings/trackpath`, `/trackplan/load`, `/plan/load` endpoints
- GIMBAL_VIZ.md — velocity bands, Catmull-Rom smoothing,
  ease-duration audience-frame budget
- UI_DESIGN_v2.md Gimbal Recon screen — field-side recon UI
- WORKFRONT #46 "Gimbal authoring against cart row labels"
- WORKFRONT #13 "New Plan sheet schema"
- WORKFRONT #49 "GimbalLog rich-row persistence" — cart firmware
  change to enable per-row type/label/offset capture (7 fields)
- WORKFRONT #58 — Track-path fit accuracy (worst yaw × cos pitch
  ≈ 7 pixels at 14mm; acceptable below visible threshold)
