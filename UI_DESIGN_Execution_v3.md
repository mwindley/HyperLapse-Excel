# Execution Screen - Design v3 (Day 30, 05 Jun 2026)

Updates the Execution section of UI_DESIGN_v2.md. The v2 layout (chart +
3 waypoint cards + BNO anchor cluster + adjustment row) was designed for an
operator who SHAPES content during the shoot. That premise is gone. This v3
captures the spectator-first model agreed Day 30. Cart Recon and Gimbal Recon
screens in UI_DESIGN_v2.md are unchanged.

---

## 1. The operating premise (what changed)

The operator is a SPECTATOR during execution. Path, angles, timing are all
set-and-forget - decided at recon/bake, not adjusted live. The cart drives the
plan; the gimbal fires each GP on the cart's ACTUAL WP arrival (Phase 1-3,
proven Day 30). The UI's job is REASSURANCE - "what's happening, what's next" -
plus two narrow interventions:

- **Heading update** (optional refinement) - tell the cart where it ACTUALLY
  is before the next earth-frame GP, so the cart hands the gimbal a true
  heading to aim by. Forward-only. Never blocks the plan.
- **Nudge distance** (cart SAFETY only) - stop short of / extend past a hazard
  on the running leg. NOT for content.

Everything else is read-only.

### Why heading is only a refinement (FOV reality)
14mm on the full-frame R3 = ~104 deg horizontal / ~81 deg vertical / ~114 deg
diagonal FOV. A 5-10-15 deg heading error is a small fraction of that frame and
is EASY to fix in post (off-centre framing). What is NOT fixable in post is a
LATE or MIS-AIMED move (gimbal pointing the wrong place at the wrong moment).
So the design optimises for catching imminent moves, not for heading precision.
The operator is usually the source of error anyway; the UI lets them catch
their own setup mistakes before an un-undoable move.

---

## 2. Screen layout (top to bottom)

### a. Header
Unchanged from UI_DESIGN_v2 (two rows; Cart / Gimbal / Exec / Day|Night tabs).
Execution is the only screen that responds to the Day/Night toggle.

### b. Plan state row
One monospace line: running state, T+elapsed / total, photo count, CCAPI status.
(As v2.)

### c. Gimbal chart (kept - it has a real safety job)
I was wrong to think the spectator model retires the chart. It earns its place
as the CABLE / FAST-MOVE EARLY-WARNING picture:
- **Yaw axis: FIXED 450 deg span** - left = yaw_min, right = yaw_min + 450
  (yaw_min from Excel at bake time). Does NOT auto-fit the plan; even if the
  actual path only uses ~180 deg, the axis stays the full envelope so move size
  is constant and you can see cable headroom against the +/-450 cumulative limit.
- Pitch axis 20-80 deg; dashed reminder line at 80.
- Velocity-banded path (blue ease / green slow-or-astro / amber deliberate /
  red fast) + waypoint dots + Catmull-Rom path. (Bands as v2 / GIMBAL_VIZ.)
- Live camera icon at the current (yaw, pitch). The icon creeping toward a red
  band IS the cue: a fast pan is near -> glance, inspect the cable.

### d. Row list (the PRIMARY readout - this is the screen)
Time-ordered list of WP and GP rows interleaved, scrolling, the imminent event
kept in view. Each row, minimum content:
- Identity (WPnn, or GP type/intent e.g. "pan right", "track sun").
- Real-time ETA / "time to event", updating live.
- State: pending / now / done.
Intent is shown so the operator can confirm the plan matches what they expect
to see next, in case concerned.

### e. Nudge (persistent, small - NOT a row property)
Cart-safety distance only. Acts on the cart's currently-running leg, so it is a
small standing control, not buried in the list: ToGo readout, -100mm, +100mm.
(PAUSE/RESUME from v2 may sit here too; abort semantics unchanged.)

---

## 3. The ONE alert (agnostic)

A single alert mechanism, fired for either reason - the row says which:
- An **astro / earth-frame GP** is approaching (a real-world heading would
  refine it), OR
- A **fast pan** is approaching (cable-check).

The alert does not care which - it is just "attention, something's coming on
this row." Visual is primary: the row cell goes RED. Sound is secondary
(see section 5). For a spectator, one thing to react to; the row text explains.

Timing: the window opens when the cart's ETA to the relevant WP is ~2 min out
(time-based, not distance - the operator asked for 2 min notice). It closes
when the GP fires. ETA is an estimate (slip/nudge/stop move it), so "2 min"
wobbles - fine for a heads-up, not treated as exact.

---

## 4. Heading update (decoupled from the alert)

A plain, ALWAYS-available button - not gated to the alert (the alert just draws
the eye to a row where updating is worthwhile).
- Prepopulated with the EXPECTED heading (recon floor / `expected_cart_heading`
  for that WP). Common case: glance, it's about right, don't touch it.
- Operator overrides with the real value, taps. Cart computes the delta
  ("oops, -10 deg offset").

Semantics (settled Day 30):
- It is the operator telling the cart "I did NOT arrive where planned - here is
  where I ACTUALLY am." The cart relays this to the gimbal for the NEXT
  earth-frame GP so the gimbal can cope.
- **Forward-only.** Applies to the next GP the cart informs the gimbal about;
  does NOT retro-correct the current point.
- **Replaces** the running offset (does NOT accumulate). Each update is a fresh
  absolute truth, preventing cumulative drift - a prior left error must not be
  "cancelled" by a later right error.
- **Non-blocking.** No response -> cart hands the gimbal the planned floor and
  gets on with it. Photos/plan never wait on the operator.
- Earth-frame GPs ONLY. Relative pans and the cart path are heading-independent
  - no prompt, no wait.
- Sign: cart heading and gimbal yaw are now ONE convention (CW-positive,
  Day-30 unification), so the operator's heading feeds the correction with NO
  sign flip.

---

## 5. Alert sound (iOS constraints - verified Day 30)

Sound is a SECONDARY layer on top of the red cell; the red cell always works.
- iOS Web Audio needs a user-gesture unlock before any sound. The "tap to start
  execution" gesture unlocks audio for the whole session (unlock persists
  across the domain), so later timed beeps can fire without another tap.
- Create ONE AudioContext at start and REUSE it (Safari caps ~4 per page).
- Hard limit we cannot override: if the phone's RINGER/MUTE switch is set to
  silent/vibrate, iOS plays NO Web Audio. So "ringer ON" is a pre-start
  CHECKLIST item, and the prompt must never be sound-only - the red cell is the
  real signal, the beep is best-effort.

---

## 6. Carried over / unchanged from v2

- Palette (day warm-grey / night red-on-black), confirmations model, 3s polling,
  connection-loss header-row colour flip.
- Removed-from-Execution list (no quick-abort beyond PAUSE, etc.).

## 7. Superseded from v2

- BNO "anchor cluster" line - BNO is stubbed; heading is iPhone/recon-floor now.
  Replaced by the heading-update model (section 4). Any BNO-delta readout is
  gone.
- "Three waypoint cards (Last/Now/Next)" as the centrepiece - replaced by the
  full time-ordered row list (section 2d); Last/Now/Next is just the in-view
  slice of that list.
- Chart framed as content-shaping aid - re-scoped to cable/fast-move warning.

## 8. Still open

- Exact ETA model for the 2-min window (speed x distance-to-go; how to display
  while paused / between legs).
- Fast-pan alert threshold: red band only, or red+amber; key off deg/sec or off
  total swing (big slew = the real cable risk). Leaning: total swing.
- Connection-loss threshold (3 / 6 / 10 s) - still open from v2.
- Pre-start checklist contents - now has at least: ringer ON; tap-to-start
  (audio unlock); cart heading seed entered.
