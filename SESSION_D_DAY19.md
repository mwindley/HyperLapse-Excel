# Session D Day 19 — Plan Authoring deep design + Excel mockup

**Date:** 25 May 2026
**Continuation of:** Session C day 18 (24 May, Plan Authoring initial design)
**Status:** Architectural decisions locked, four .bas modules written and
dry-run verified, Excel mockup with live formulas built. Ready to pause.

---

## What this session was about

The operator surfaced `PLAN_AUTHORING.md` (Day 18 design doc) as a
starting point for discussion before building anything in Excel.
The session worked through the design end-to-end, simplified the
vocabulary significantly, then built the first 4 implementation
phases (P1, P2, P3, P4, P5) as concrete artifacts.

The aim was to reach a working Plan sheet mockup that the operator
could open and inspect, with macros ready to paste into
HyperLapse.xlsm when #49 (cart firmware gimbal-log enrichment) is
ready.

---

## Architectural decisions made this session

### 1. Gimbal action vocabulary collapsed: 7 types → 3

Old (UI_DESIGN_v2 + GIMBAL_VIZ §3): PF, Lock, Move, Track sun,
Sunrise, Sunset, MW, Hold — with sub-toggles for keyframe and R/C
frame.

New:

| Action | Behaviour |
|---|---|
| **Pan Follow** | Gimbal yaw = cart yaw + offset (cart frame) |
| **Approach** | Rate-paced move to target (static or moving); on arrival, hold or track |
| **Lock** | Freeze absolute real-world pose; counter-rotate as cart turns |

Move-then-hold collapses into Approach with static target.
Track-sun collapses into Approach with moving target.
Sunrise/Sunset/MW collapse into Approach with astro target + KF column.

### 2. Approach unifies Move-to and Track via pursuit curve

For a moving target (sun/moon/MW), one Approach row covers both
"slew to where target will be at slew-end" and "follow target
once converged." Excel pre-computes a pursuit curve (2-3 iterations
to converge on the moving target), samples it, emits a series of
cubic segments. Cart sees one continuous Catmull-Rom path with no
transition event — therefore no catch-up jolt.

### 3. Rate vocabulary — 5 named bands, Excel-side params

Operator picks rate from a fixed vocabulary:

| Rate | °/sec | Use |
|---|---|---|
| Imperceptible | 0.004 | Astro drift territory |
| Cinematic ease | 0.05 | Comfortable; default for most moves |
| Deliberate pan | 0.15 | Operator-pan feel |
| Fast | 0.30 | Punchy; approaches red on chart |
| Snap | (3s fixed) | Near-instant; regardless of distance |

Move time is a **derived column** = angular distance / rate.
Operator sees resulting duration; if not happy, edits cart plan
to absorb the gap (NOT the rate — keeps vocabulary consistent
across the night).

For non-rate-authored rows (Track, Pan Follow, Lock), Rate cell
shows literal text **"Computed"** so the column is never blank.

### 4. Rate column semantics for moving targets — Phase A only

For an Approach with moving target, the Rate governs only the
convergence phase. Once converged, gimbal moves at the target's
sky rate (Imperceptible band for astro). Execution chart paints
both phases distinctly so operator sees the transition.

Mental model: *"Rate = how I'm getting there; what happens once I
arrive depends on whether the target is static or moving."*

### 5. Recon-time captures simplified to two types

Old: 7-action vocabulary captured during recon with rich per-row
intent (UI_DESIGN_v2 Gimbal Recon spec).

New:

| Capture | Records | Used for |
|---|---|---|
| **Static marker** | (timestamp, Ry, pitch, label) | Approach static target |
| **Astro framing** | (timestamp, astro target, KF, Δyaw, Δpitch, label) | Approach astro target offset |

R/C toggle removed — all captures are real-world frame. Capture
happens with cart parked, so cart heading is stable (read from
CartLog at the timestamp range, not stored per gimbal row).

The composition work — picking action types, anchors, rates,
sequencing — does NOT happen in the field. Excel back at the
van, with coffee.

### 6. BNO correction applied at next Move-to (no snaps, ever)

Critical operator constraint: **smooth, no snaps** in the timelapse.

Cart maintains `pending_bno_correction` scalar updated as BNO
reads come in. The correction is NOT applied immediately. Instead,
the next Move-to / Approach segment dispatches with `target +
pending_bno_correction`. Gimbal slews smoothly to a slightly
adjusted endpoint; the correction is hidden inside an authored
motion.

**Implication:** Lock segments can run for a long time, drift
accumulates, and only gets folded in when the next Move-to fires.
Safety valve for "no Move-to for hours" case remains an open
question for #40 build.

### 7. Cart heading source — no cubic needed

Cart computes its own yaw rate via bicycle formula per photo
cadence; maintains three scalars:

| Scalar | Updated when | Used for |
|---|---|---|
| `gimbal_yaw_correction` | At BNO sync (margin-triggered) | Convert real-world poses to cart frame |
| `cart_yaw_accumulator` | Per cycle during Lock; reset at Lock entry | Counter-rotation for Lock |
| `pending_bno_correction` | Continuously, from BNO reads | Awaiting next Move-to to fold in |

No θ_cart cubic from Excel. BicycleModel.bas stays useful as
planning-time validator (operator can see "this Lock segment needs
X° of counter-rotation, fits in envelope").

### 8. Photo cycle timing (canonical, was inconsistent before)

```
T = 0       Shutter opens (gimbal still, at rest)
T = 0..20   20-sec exposure — gimbal MUST be perfectly still
T = 20      Shutter closes
T = 20..22  Service window (2 sec):
              - Card writes
              - CCAPI commands if any
              - Gimbal move request
              - Slew executes (1.0–1.5 sec)
              - Vibration damps
              - Gimbal at rest
T = 22      Cycle repeats
```

Total cycle = 22 sec. Exposure = 20 sec. Service gap = 2 sec.
One `setPosControl` per cycle. The 100 ms granularity of
`timeForAction` is plenty fine — slews are 10–15 increments.

---

## What was built (artifacts in chat outputs)

### Markdown updates (paste into HyperLapse-Excel repo)

| File | Status |
|---|---|
| `PLAN_AUTHORING.md` | Full Day-19 rewrite. New action vocabulary, rate bands, worked example, open questions extended. |
| `GIMBAL_VIZ.md` | New §9.5 added with photo cadence + cart-heading state model + BNO correction mechanism. |

### VBA modules (paste into HyperLapse.xlsm)

| File | Purpose | Status |
|---|---|---|
| `PlanBuilder.bas` | P2 — `BuildPlanFromCartLog` walks CartLog W events, seeds left zone of Plan sheet. | Dry-run verified against synthetic post-Day-16 data. Real CartLog in workbook has no W events, can't be tested until new recon. |
| `GimbalLogPuller.bas` | P4 — `PullGimbalLogToPlan` copies GimbalLog into right zone. | Detects 4-field (today) vs 7-field (post-#49) shape. Dry-run verified against both. |
| `PlanAuthoring.bas` | P5 — five middle-zone helpers (`AddPlanRowFromLog`, `AddBlankPlanRow`, `InsertPlanRowAbove`, `DeletePlanRow`, `RebuildAnchorDV`). | Includes Worksheet_SelectionChange snippet to paste into Plan sheet's code module for dynamic dropdowns. |

### Excel mockup (standalone)

| File | Purpose |
|---|---|
| `Plan_mockup_P3.xlsx` | Standalone .xlsx P1+P3 build. Settings sheet (15 named ranges incl. rate vocabulary). Plan sheet with three colour-coded zones, working formulas in derived columns (Step, Dist Σ, Arrives), demo data matching the worked example (Way01..Way06 + STOP, sunset shoot, 5 m/hr). Verified zero formula errors. Way06 arrives at 17:02 (T0−40 if sunset=17:42). |

---

## P-sequence status

From PLAN_AUTHORING.md "Implementation phases":

| P | Description | Status |
|---|---|---|
| P1 | Sheet design + layout | **DONE** — Plan_mockup_P3.xlsx |
| P2 | CartLog → Cart Plan macro | **DONE** — PlanBuilder.bas |
| P3 | Left-zone recompute formulae | **DONE** — built into mockup |
| P4 | GimbalLog → right zone copy | **DONE** — GimbalLogPuller.bas |
| P5 | Middle-zone authoring helpers | **DONE** — PlanAuthoring.bas |
| P6 | Anchor resolver (WP/TIME/ASTRO → wall-clock) | Not started |
| P7 | Plan push — gimbal stream (decompose Plan rows to cart segments) | Not started |
| P8 | Plan execute (StartCartReplay drives both streams) | Not started |
| P9 | Live-progress display | Not started |
| P10 | Plan validation | Not started |

Plus separate from P-sequence:
- **Gantt visualisation** — cell-grid two-lane Gantt for proofing.
  Discussed and design-locked (linear time axis, ~5 min/col default,
  empty cart lane after park, no chart — cell-grid). NOT BUILT.

---

## Open questions surfaced this session (in PLAN_AUTHORING.md)

Beyond the Day-18 inherited open items:

- **Approach-with-moving-target anchor mechanism.** Worked example
  used WP anchor; rule for TIME and ASTRO anchors needs documenting.
- **Astro tables pushed pre-recon.** Implies `PushAstroToCart`
  becomes a recon-prep step. Cart-side persistence across reboots
  may be needed.
- **Snap rate band duration parameter.** 3s? 5s? Per-row override?
- **Pano action.** Sits outside the three-action vocabulary; needs
  fourth slot or special-case.
- **#49 sequencing.** Cart firmware enrichment must land before
  Excel-side Plan macros can be tested end-to-end.
- **Astro target encoding in rich GimbalLog.** Surfaced during P4
  dry-run. Two options: compound Type values ("astro_sunset_mid")
  or separate AstroTarget column. Resolve before #49 cart-firmware
  build.
- **BNO drift safety valve.** If gimbal plan has no Move-to for
  hours, when does `pending_bno_correction` get forcibly applied?

---

## What a next session should do

**Probable next move: P6 — Anchor resolver.** Without it, Plan rows
have anchor type/ref strings ("WP3", "sunset", "23:30") but no way
to convert to absolute wall-clock at push time. P7 (push) can't
work without P6. P8 (execute) builds on P7.

**Alternative: build the Gantt visualisation.** Visual proofing
tool for the operator to scan the timeline before push. Doesn't
gate P6/P7/P8 but it's the operator-facing surface that gives
them confidence the plan is right.

**Another alternative: pause Excel work and focus on #49** — the
cart-firmware change needed to make the new rich GimbalLog real.
Without #49, P4 and P5 work in test-only mode against fabricated
log data.

Operator should pick based on shoot calendar / what's blocking.

---

## Files to load at start of next session

Per PROJECT_STATE.md bootstrap list:

- PROJECT_STATE.md (note: NOT updated for Day 19 — see below)
- WORKFRONTS.md (note: NOT updated for Day 19 — see below)
- PREFERENCES.md
- This file: SESSION_D_DAY19.md (fills the Day-19 gap)
- PLAN_AUTHORING.md (Day-19 version in outputs)
- GIMBAL_VIZ.md (Day-19 version in outputs, has new §9.5)

Plus on-demand:
- Plan_mockup_P3.xlsx — see what the layout looks like
- PlanBuilder.bas / GimbalLogPuller.bas / PlanAuthoring.bas —
  the three .bas modules ready to paste into HyperLapse.xlsm

**Important:** PROJECT_STATE.md and WORKFRONTS.md were NOT updated
this session. Future Claude reading them in isolation will think
Day 18 was the last session. This file covers the Day-19 gap; once
operator works through this material the canonical state docs
can be updated.

---

## Working preferences carried forward (unchanged)

- Windows cmd syntax
- Small steps, one question at a time, wait
- Plain-text questions (no multi-choice widgets — operator hates them)
- Code boxes for shell commands; bare URLs in chat
- Oscilloscope approach — instrument, don't guess
- No causal guesses without measurements
- Photos sacred, wrong exposure fixable in post
- Visualisation > Manipulation
- Cart Uno R4 retired; Giga R1 is current controller as of Day 18

---

## Side note — vocabulary differences future Claude should know

The cart firmware (v2 sketch) still has GT_PF/GT_LOCK/GT_MOVE/
GT_TRACK/GT_SUNRISE/GT_SUNSET/GT_MOONRISE/GT_MOONSET/GT_MW tags
defined for gimbalLog entries (sketch lines 1074-1083). These are
**capture-side tags** for the Recon UI; they do NOT correspond
to the Day-19 three-action vocabulary, which is **plan-side**.

Mapping for next session's understanding:
- Capture-side GT_PF / GT_MOVE / GT_LOCK → contribute to Plan-side
  Pan Follow / Approach / Lock authoring, but with operator
  re-composition in Excel.
- Capture-side GT_TRACK / GT_SUNRISE / GT_SUNSET / GT_MOONRISE /
  GT_MOONSET / GT_MW → contribute to Plan-side Approach with astro
  target. The Plan layer doesn't distinguish — it just sees "astro
  target X with offset Y."

The capture-side vocabulary is richer because it's the field
operator labelling intent. The Plan-side vocabulary is sparser
because Excel composes the intent into executable action.
