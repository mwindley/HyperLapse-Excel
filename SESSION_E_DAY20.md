# Session E — Plan vocabulary refinement + P6 build + P7 design

**Date:** 26 May 2026
**Continuation of:** Session D Day 19 (25 May, P1–P5 Plan Authoring build)
**Status:** P6 anchor resolver built and verified. Plan middle-zone
vocabulary refined extensively. P7 design discussed end-to-end and
key decisions locked. No P7 code written yet.

---

## What this session was about

The operator surfaced the Day-19 Plan Authoring artefacts (mockup
xlsx + .bas modules) and asked to build P6 (anchor resolver).
After P6 landed, a long discussion walked the middle-zone columns
one-by-one looking for simplifications, drove vocabulary changes,
then moved on to P7 (Plan push) design at the architecture level.

Working preferences (no multi-choice, plain-text questions, one
question at a time, simple over clever, real-world use over
postponed perfection) carried through.

---

## P6 — Anchor resolver — BUILT

Live-formula in a new `Fires at` column (Q) on the Plan sheet
middle zone. Converts each gimbal row's `(Anchor type, Anchor ref,
Offset)` into an absolute wall-clock time.

### Changes vs P3 mockup

**New columns** (inserted after Anchor ref):
- P = Offset (min) — editable, blank=0
- Q = Fires at — derived formula

**Column shifts:**
- Middle zone old P..Y → new R..AA (shift +2)
- Right zone old AA..AJ → new AC..AL (shift +2) to avoid AA collision
- Gap at column AB between middle and right zones (visual gutter)
- Merged headers: `M3:Y3 → M3:AA3` and `AA3:AJ3 → AC3:AL3`

**WP # convention tightened:**
- Col H (Cart Plan WP #) now text "WP01", "WP02", ... (was integer)
- Anchor ref (col O) uses same WP01..WPNN convention
- String-to-string MATCH; no integer parsing

**Settings sheet times upgraded:**
- `dataShootStart`, `dataSunset/Sunrise/Moonrise/Moonset/MWRise/Transit/Set
  Time` converted from text strings to real Excel time values formatted
  `hh:mm:ss`. Pre-P6 worked by accidental coercion in arithmetic
  context but failed inside `IF(N="ASTRO",...)` branches.

### The formula (in Q for each row)

Nested IF, three branches on Anchor type (N), all add offset/1440:

```
=IF(N6="WP",
     INDEX($J$6:$J$20, MATCH(O6,$H$6:$H$20,0)) + IFERROR(P6,0)/1440,
   IF(N6="TIME",
     IFERROR(TIMEVALUE(O6),"") + IFERROR(P6,0)/1440,
   IF(N6="ASTRO",
     IF(O6="sunset",    dataSunsetTime,
     IF(O6="sunrise",   dataSunriseTime,
     IF(O6="moonrise",  dataMoonriseTime,
     IF(O6="moonset",   dataMoonsetTime,
     IF(O6="mwrise",    dataMWRiseTime,
     IF(O6="mwtransit", dataMWTransitTime,
     IF(O6="mwset",     dataMWSetTime, "")))))))
     + IFERROR(P6,0)/1440,
     "")))
```

Verified end-to-end:
- GP1 (WP01 +0) → 15:42 ✓
- GP2 (WP05 +0) → 16:30 ✓
- GP3 (ASTRO sunset +0) → 17:42 ✓
- Test rows: WP03+5min → 16:11; sunset−10min → 17:32; TIME 23:30 → 23:30. All ✓

### .bas modules updated for P6 (paste-ready, not runtime-tested)

| Module | Changes |
|---|---|
| `PlanBuilder_P6.bas` | Col H writes as text "WP" & Format(n,"00") (was integer). |
| `GimbalLogPuller_P6.bas` | Right-zone constants AA→AC, AJ→AL. All Cells(r,col) writes +2. CountRightZoneRows reads col 30 (AD). |
| `PlanAuthoring_P6.bas` | MID_COL_LAST Y→AA. Middle-zone writes 16..25 → 18..27. WriteMiddleRow skips cols 16 (P=Offset) and 17 (Q=Fires at). CopyMiddleRow preserves Q formula on row shift (was a latent bug — would have frozen Fires-at). BuildWPList reads strings. WP1 defaults → WP01. Right-zone log-row# read col 27→29. |

Other 14 .bas modules grep-checked — no Plan-sheet middle/right-zone refs. Not touched.

### Deliverables (in chat outputs)

| File | Status |
|---|---|
| `Plan_mockup_P6.xlsx` | Standalone mockup, verified |
| `PlanAuthoring_P6.bas` | Paste-ready |
| `GimbalLogPuller_P6.bas` | Paste-ready |
| `PlanBuilder_P6.bas` | Paste-ready |
| `P6_ANCHOR_RESOLVER.md` | Implementation note |

**Operator chose not to import the .bas yet** — preferred to eyeball
the layout in Excel first since HyperLapse.xlsm has no real cart data.

---

## Vocabulary refinement (post-P6, during P7 design lead-up)

The operator walked through middle-zone columns looking for
simplifications. Several material decisions:

### Action vocabulary collapsed differently (revising Day 19)

Day 19 collapsed Move-static and Track-astro into one "Approach"
action distinguished by target. **Session E unmade that collapse**
because Approach was carrying too much overloaded semantics:

| Old (Day 19) | New (Session E) | Reason |
|---|---|---|
| Approach + static target | **Move** | "Slew to a static target, hold on arrival" |
| Approach + moving target | **Track** | "Slew to moving astro target, then follow" — matches Ronin app vocabulary |
| Approach + moving target + yaw-only | **Track-yaw** | Pitch held at operator-typed value; yaw tracks |
| (no change) | **Pan Follow** | Yaw = cart yaw + offset |
| (no change) | **Lock** | Freeze absolute pose |

Five values in the Action dropdown. Plus an **END sentinel** row (see
end-of-plan, below) — strictly that's a sixth value used for one row.

Rationale recap from the discussion: "Approach is combination of get to
astro (moving) in a faster plan then track it" — that's the operator's
actual mental model and deserves its own word. Move is the natural
counterpart for static targets.

### Track-yaw + Ronin convention

Sketch firmware already has the field-side mode tag (`GTM_FULL='F'`
and `GTM_YAW='Y'`) and the convention that in YAW mode, `offP` carries
**absolute fixed pitch, not a delta** (sketch line 1104). Excel's
column V (Rp) maps directly to this. Decision aligns Plan layer with
existing firmware.

### Columns dropped

- **S (Target type)** — derivable from Target ref. If target is "Tree",
  it's a marker. If target is "sun", it's astro. P7 pattern-matches at
  push time.
- **U (KF — rise/mid/end)** — "sun mid" is not a real astro event,
  just sun at a time. Sunrise/sunset/moonrise etc. are themselves
  named events (instants), not keyframes of something else. They belong
  in the **Anchor ref** (when to fire), not the Target (where to point).
  Per-row KF column collapses entirely.
- **"sun@T0" compound references** — drop. Each column carries one
  piece of the story (N/O answer "when", T answers "what"). Composing
  "where with when" into the target ref breaks the left-to-right
  reading rhythm.

### Columns added

- **U (Ry), V (Rp)** — two new columns between Rate and Δyaw.
  - Auto-populated by formula when Target is a marker (lookup right-zone Ry/Pitch)
  - Operator types Rp directly for Track-yaw (held pitch absolute)
  - Blank/`—` for actions that don't have a target pose
  - Override-able: typing a value replaces the formula; small
    "Refresh marker poses" macro re-writes the formula
- **(new col) Ease** — named bands: `none` / `Just-perceptible` (~3 frames) /
  `Comfortable` (~10 frames) / `Cinematic` (~30 frames).
  Excel converts band → frames → real-world duration via the cadence
  active at the row's fire time (Tv from Appendix A drives cadence).
  Same ease in as ease out for now; expand to asymmetric later if needed.

### Rate semantics under ease (decision)

Rate band = **cruise (middle) speed**, exactly as authored. Total slew
duration = (slew distance / cruise rate) + ease_in + ease_out + hold tail.
If next row's Fires-at arrives before slew+eases complete, P7 validation
errors with the row number.

Velocity-band colour on the chart represents **cruise speed only** (drop
§7's "blue = ease segment marker" convention — too noisy). Ease presence
is implied by the Ease column value, not the chart colour.

### Cadence regime context (calibration of vocabulary)

The Rate vocabulary calibrates against night (22s cadence, 1320× video
speedup). At 2-second cadence (sunset/sunrise), the same authored real-world
rate plays back faster in video. Operator's typical post-edit speedup at
2s cadence is 4–8×, giving effective 480–960× — closer to the 1320×
night regime. Spread on "Cinematic ease" across regimes: roughly 2.7×.
Acceptable. Operator accepts that video appearance varies; the band name
indicates approximate cruise feel.

### Revised middle-zone column layout (post-Session E)

| Col | Field | Editable | Notes |
|---|---|---|---|
| M | Step | derived | GP01, GP02... (proposed change from numeric; deferred task) |
| N | Anchor type | yes | WP / TIME / ASTRO |
| O | Anchor ref | yes | WP01 / 23:30 / sunset / moonrise |
| P | Offset (min) | yes | blank = 0 |
| Q | Fires at | derived | formula (P6) |
| R | Action | yes | Pan Follow / Lock / Move / Track / Track-yaw / END |
| S | Target | yes | Tree / Harbour / sun / moon / mw / — |
| T | Rate | yes | named band or "Computed" |
| U | Ry | yes | formula for marker target; — otherwise |
| V | Rp | yes | formula for marker target; typed for Track-yaw; — otherwise |
| W | Δyaw | yes | offset from Ry, default 0 |
| X | Δpitch | yes | offset from Rp, default 0 |
| Y | Ease | yes | none / Just-perceptible / Comfortable / Cinematic |
| Z | Move t | derived | computed slew duration including ease |
| AA | Total dur | derived | next row's Fires-at − this row's Fires-at |
| AB | Note | yes | operator free text |

Net vs P6: dropped S (Target type) and U (KF) = −2 cols; added Ry, Rp,
Ease, Total dur = +4 cols. Net +2 cols. Middle zone ends at AB. Right
zone shifts further right by 1 (was at AC..AL, becomes AD..AM) to keep
the AB→ gap. (May reconsider — see open questions.)

Decision NOT made yet: where exactly the new columns sit (Ease and
Total dur could go elsewhere). Layout above is a best-fit pass.

---

## Deferred task (logged, not done)

**Collapse redundant WP # column.** Three changes:
1. Col B (Cart Plan Step) becomes `="WP" & TEXT(ROW()-5,"00")` text formula
2. Col M (Gimbal Plan Step) becomes `="GP" & TEXT(ROW()-5,"00")` text formula
3. Drop col H (WP #) entirely
4. Anchor resolver formula updates `MATCH(O6,$H...)` → `MATCH(O6,$B...)`
5. PlanBuilder.bas stops writing col H; PlanAuthoring.bas BuildWPList reads B

Trade: shrinks left zone width by one column, removes redundant
representation. Operator's preference at time of decision.

---

## P7 design discussion — decisions locked

P7 = "Push Gimbal Plan" macro. Walks middle-zone rows, decomposes
each into cart-side segments + TrackInterval pushes, sequential GETs
to existing cart endpoints.

### Architecture confirmed by sketch read

Two-table structure on cart:

1. **`track_sun` / `track_moon` / `track_mw`** — per-object Catmull-Rom
   cubic arrays. Up to 8 segments per object on Giga
   (`TRACK_SEGS_MAX=8`, sketch line 950). Pushed via `/settings/trackpath`
   ONCE per shoot by `PushTrackPathsToCart`. Independent of Plan.
2. **`track_plan[10]`** — Track intervals, one per Track Plan row.
   Carries `(ts_ms, te_ms, obj, mode, offY, offP)`. Pushed via
   `/trackplan/load?...`. `TRACK_PLAN_MAX=10` matches Ronin app's
   10 Track waypoints.

So **Track-row → cart is ~16 bytes**, not a cubic stream. The cubic
math (`track_<obj>` evaluation, residual checks, freeze-zenith logic)
lives once on Excel side via `FitAndPushTrackPath`/`CheckTrackFitResiduals`.

### Documented fit accuracy

WORKFRONTS #58 + AstroPush.bas instrumentation. Worst-case yaw error
× cos(pitch) projects to ~7 pixels at 14mm — below visible threshold.
On Giga (N=8 available) the accuracy ceiling is generous; segment-count
budget no longer the binding constraint.

### P7 phases

**Phase 1 — Validate.** Walk middle-zone rows. Check Anchor resolves
(Fires-at not blank), Action recognised, Target sensible for Action,
Rate set where required, Ry/Rp populated where required. Abort with
row-numbered error list. Last row must be Action=END.

**Phase 2 — Prerequisites.** If any Track row references an astro
object, ensure `track_<obj>` is loaded. Ensure astro event times on
Excel match what's been pushed.

**Phase 3 — Decompose rows.** Walk in order:

| Plan row | Cart side |
|---|---|
| Pan Follow | One PANFOLLOW segment for row duration |
| Lock | One HOLD at current real-world pose |
| Move (marker) | CUBIC slew (Ry+Δyaw, Rp+Δpitch as endpoint) + HOLD tail |
| Move (astro snapshot) | Excel evaluates `track_<obj>` at Fires-at → endpoint, then CUBIC slew + HOLD tail |
| Track full | One TrackInterval push (mode=F, offY=Δyaw, offP=Δpitch) |
| Track-yaw | One TrackInterval push (mode=Y, offY=Δyaw, offP=Rp absolute) |
| END | No segment emitted; provides Fires-at for previous row's hold-tail end |

**Phase 4 — POST.** Sequential GETs to existing endpoints:
- `/plan/load?seg=N&...` for HOLD/CUBIC/PANFOLLOW (cart Plan executor
  extends to gimbal segments — separate workfront)
- `/trackplan/load?idx=N&ts=&te=&obj=&mode=&oy=&op=` for TrackIntervals
- `/settings/trackpath?...` for cubics (only if not already pushed)

**Phase 5 — Summary.** Report segments + intervals pushed.

### Three P7 decisions closed

1. **Slew interpolation: always CUBIC** for Move slews. Excel computes
   coefficients to encode cruise rate + ease in + ease out. Cart side
   stays dumb — same `at³+bt²+ct+d` evaluator. LINEAR could be a
   special case for ease=none but the always-CUBIC simplification wins.

2. **End-of-plan: sentinel END row.** Last Plan row has Action=END,
   uses the same anchor type/ref/offset as any other row. Doesn't emit
   a cart segment but its Fires-at = the previous row's hold-tail end.
   Validation: last row must be END; no rows after END.

3. **Twice-called PushGimbalPlan: full reset + repush.** Predictable
   over fast. Operator can trigger as often as wanted while iterating.

### What P7 still needs (not decided)

- Endpoint URL/payload formats for any new POSTs (existing endpoints
  may need extension for the gimbal Plan executor)
- Cart-side gimbal Plan executor itself (separate workfront, the
  mirror of the existing cart Plan executor at sketch line 2513)
- How the gimbal stream's t_start_ms / t_end_ms interleave with the
  cart stream's segments (per GIMBAL_VIZ §9 "shared clock" model)
- Error handling on partial-push failure (cart-side rollback or just
  abort and ask operator to retry)

---

## Open questions surfaced this session

- **Total dur column placement.** Belongs to the row's overall
  timing — could sit next to Fires-at (cols Q+1) instead of further
  right. Layout pass needed.
- **End-anchor with Action=END is doing double duty.** END is both a
  vocabulary value and an implicit signal to the Plan. Worth confirming
  it doesn't paint the executor into a corner.
- **Gimbal Plan executor (cart-side).** Mirrors cart Plan executor at
  sketch line 2513 but doesn't exist yet. Needs a workfront entry.
- **Ease band default values.** "~3 / ~10 / ~30 frames" are §8
  guidelines; should be Settings-sheet named ranges (analogous to
  rate bands) so operator can adjust per-shoot.
- **Marker pose refresh macro.** "Refresh marker poses" was promised
  to reinstate the auto-populate formula in U/V after override. Not
  yet specified — when does it run, what does it look like?
- **Where do Premiere-Pro-style speed transitions land in the
  vocabulary?** The operator noted in-shot ease reduces the need for
  post-edit speed ramps. Confirmed the goal but didn't decide whether
  the planning vocabulary needs to acknowledge that path-of-least-
  surprise. (Probably no further work needed; ease in/out covers it.)

---

## P-sequence status (end of Session E)

| P | Description | Status |
|---|---|---|
| P1 | Sheet design + layout | DONE (Day 19); Session E mockup at Plan_mockup_P7.xlsx |
| P2 | CartLog → Cart Plan macro | DONE (Day 19); Session E update in PlanBuilder_P7.bas |
| P3 | Left-zone recompute formulae | DONE (Day 19) |
| P4 | GimbalLog → right zone copy | DONE (Day 19); Session E update in GimbalLogPuller_P7.bas |
| P5 | Middle-zone authoring helpers | DONE (Day 19); Session E update in PlanAuthoring_P7.bas |
| P6 | Anchor resolver | **DONE — Session E** |
| **P7** | **Plan push — gimbal stream** | **Design locked; not built** |
| P8 | Plan execute (both streams) | Not started — needs cart-side gimbal plan executor |
| P9 | Live-progress display | Not started |
| P10 | Plan validation | Phase 1 of P7 covers most; deferred |

Plus the doc/admin work completed this session:
- ✅ **PLAN_AUTHORING.md** updated to Session E vocabulary
- ✅ **Plan_mockup_P7.xlsx** built and verified
- ✅ **Deferred WP # collapse** applied to mockup
- ✅ **Three .bas modules** updated for Session E (paste-ready, untested)

---

## What a next session should do

Three plausible paths:

**A) Apply the vocabulary refinement to the mockup.**
Add the new Action vocabulary, swap KF/Target-type for Ry/Rp/Ease,
add END sentinel handling. Rebuild Plan_mockup_P6 → Plan_mockup_P7
or similar. No code; just the layout.

**B) Build P7 itself.**
Macro `PushGimbalPlan` per the five-phase architecture above. Needs
the new endpoints surveyed first (some may not exist yet on cart).

**C) Update PLAN_AUTHORING.md to reflect Session E.**
The doc still describes the Day-19 vocabulary. Future sessions
reading it will be confused. Bring it in line with: 4-action
vocabulary, dropped S/KF, added Ry/Rp/Ease, END sentinel row,
P7 push design.

**D) Address deferred WP # collapse task.**
Three-line change to mockup and one .bas helper. Quick win.

Operator should pick based on what's most useful next.

---

## Notes for future Claude (captured at end of session)

### State-of-repo gaps the next session will hit

1. **HyperLapse.xlsm in the project repo is at Day-19 state.**
   The mockup file (`Plan_mockup_P7.xlsx`) is ahead. If next-Claude
   reads only HyperLapse.xlsm, it'll see no Plan sheet at all (or
   the P5-era layout, not P7). The mockup is the design surface;
   HyperLapse.xlsm needs the P7 .bas modules pasted + the
   mockup-style layout applied to a fresh Plan sheet.

2. **The .bas P7 modules are paste-ready but untested.** I never
   ran any of them. Three things to watch on first paste:
   - Column-number arithmetic was changed in many places; one
     off-by-one would only surface at runtime.
   - `WriteMiddleRow` signature changed — any other caller in the
     workbook not in the three .bas files touched would break.
   - The "GP01" text formula uses `=""GP"" & TEXT(...)` with
     VBA-escaped double quotes; verify the formula appears
     correctly in Excel after macro run.

3. **PROJECT_STATE.md and WORKFRONTS.md were never updated for
   Day 19 or Session E.** Future Claude reading them in isolation
   will think Day 18 was the last session. Both SESSION_D_DAY19.md
   (Day 19's gap-filler) and SESSION_E_DAY20.md (this file) need
   to be folded into PROJECT_STATE.md eventually, or kept as
   compaction-aids alongside it.

### Design decisions left dangling

4. **Pano action.** Re-raised twice (Day 19 and Session E) without
   resolution. It doesn't fit the 4-action (+ END) vocabulary.
   Likely a separate action type with its own row shape since pano
   is a multi-cell state machine, not a single pose. Worth deciding
   before P7 builds, since P7's decomposition table needs to cover it.

5. **Refresh marker poses macro.** Documented as a follow-up but
   not designed or built. When operator overrides V/W cells, the
   formula link is lost. The macro restores the formula across all
   marker-targeting rows. Trigger TBD — could be a button, or run
   automatically when `PullGimbalLogToPlan` refreshes the right
   zone.

6. **Ease band → real-world duration formula.** The Settings sheet
   now has placeholder frame counts (`dataEaseJustPerceptible=3`,
   `dataEaseComfortable=10`, `dataEaseCinematic=30`) but the
   cadence-aware conversion isn't built. Needs Excel formula that
   reads Tv at the row's Fires-at to determine cadence, then
   computes `frames × cadence_sec`. Lives somewhere — probably the
   Move t derived column (col AA) — but not done.

7. **End-of-plan validation.** The doc says "last row must be END;
   no rows after END" but no code enforces this yet. Will be
   Phase 1 of P7 when built.

### Sketch-side things to know

8. **Sketch already has the firmware-side endpoints P7 will use.**
   `/settings/trackpath`, `/trackplan/load`, `/plan/load` exist on
   Giga (sketch lines ~4499, ~4607, ~2854 respectively). But the
   gimbal Plan executor (the cart-side runner that consumes the
   gimbal stream) is **not built** — sketch only has the cart Plan
   executor (at line 2513). P8 work; blocks end-to-end testing of P7.

9. **Sketch capture-side vocabulary is Day-16 era** (GT_PF / GT_MOVE
   / GT_TRACK + GTM_FULL / GTM_YAW at sketch lines 1075-1104).
   Plan layer is Session E. Mapping is straightforward — the sketch
   enum becomes the source for `AddPlanRowFromLog` to map recon
   captures onto Plan-side action vocabulary. #49 firmware
   enrichment is the bridge for the GimbalLog rich-row shape.

### Working-pattern observation

10. **The "let's discuss" + plain-text question discipline worked
    well this session.** Operator gave context I didn't have, and
    the simplifications (drop S, drop KF, move event names to
    anchor, etc.) all came from operator context rather than my
    pre-baked options. The PREFERENCES.md "no multi-choice" rule
    held throughout; future Claude should hold it equally firmly.

### Naming uncertainty

11. **I named this session `SESSION_E_DAY20`** based on alphabetical
    session-letter convention (C, D, E) and Day 19 being prior. If
    the project uses different naming (e.g. continues
    `SESSION_D_DAY20` because it's a continuation, or numerical
    days only), the file is easy to rename. Renaming is operator's
    call.

---

## Files in this session's outputs

- `Plan_mockup_P6.xlsx` — verified anchor resolver
- `PlanAuthoring_P6.bas` — paste-ready
- `GimbalLogPuller_P6.bas` — paste-ready
- `PlanBuilder_P6.bas` — paste-ready
- `P6_ANCHOR_RESOLVER.md` — implementation note
- `SESSION_E_DAY20.md` — this file
