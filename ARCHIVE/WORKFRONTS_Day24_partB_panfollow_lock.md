# WORKFRONTS.md — Day 24 (part B) — Step 4 Pan Follow + LOCK design (discussion, not built)

**Append near the #5a executor notes / Step-4 entry. Design resolved
in discussion this session; NO code written for Pan Follow or LOCK.
Confirmed both are un-coded and un-pushed today.**

---

## Current state — what the executor + pusher actually do today

- **Cart executor** knows only `GTM_FULL` ('F') and `GTM_YAW` ('Y') —
  Track / Track-yaw. `GT_LOCK` ('L') exists ONLY as a gimbal-LOG enum
  stub; there is NO LOCK behaviour and NO Pan Follow state in the
  executor.
- **TrackPlanPush.bas** reads ONLY Track / Track-yaw rows and pushes
  mode F/Y. Pan Follow, Lock, Move, END rows are skipped — they never
  reach the cart. The gaps between Track intervals are undefined
  executor behaviour (it currently keeps commanding the last pose).
- Plan-sheet Action list (S6:S25): `Pan Follow, Lock, Move, Track,
  Track-yaw, END`. Pan Follow is a first-class authored GP (worked
  example row 6: `S=Pan Follow, Δyaw=-30, note "Pan follow -30 at
  start"`), NOT an implicit default.

## Command-layer taxonomy (the key framing)

The six actions split by whether the cart is actively commanding the
gimbal:
- **Commanding** (cart sends position; overrides the Ronin's native
  mode): Track, Track-yaw (per-tick cubic), Move (eased slew to an
  endpoint), LOCK (commanded fixed world bearing).
- **NOT commanding** (cart silent; Ronin's own mode takes over):
  Pan Follow.
- END terminates the plan.

LOCK and Pan Follow can both look "static" but are produced by OPPOSITE
cart behaviour — this is the crux of Step 4.

## Pan Follow — RESOLVED design (operator)

**The Ronin is left permanently in Pan Follow mode (operator sets it on
the gimbal). SDK position commands OVERRIDE that follow while they are
being issued; when the cart STOPS commanding, the gimbal reverts to its
native Pan Follow.** So follow is layered under our position control,
not a mode we switch over CAN — no CAN mode-switch needed (and the SDK
may not expose one anyway; moot).

Therefore each GP type is just "is the cart commanding?":
- **Track GP** → executor streams the cubic (overrides follow). Built.
- **Pan Follow GP** → cart issues ONE goto-yaw (the authored Δyaw, e.g.
  -30°), then GOES SILENT for the interval → Ronin follows cart heading
  mechanically. To build. **No BNO, no cart heading read** — matches the
  resolved #40 "pan-follow untouched, cart drives blind."

**Consequence for the executor:** it currently does a LOCK-like "keep
commanding last pose" between intervals. Pan Follow needs the OPPOSITE —
an explicit "release and stay quiet for this window" state — and we must
ensure no stray tick/LOCK/hold sneaks a position command in during a
Pan Follow window (any position command momentarily overrides follow).

**Pan Follow preview pose** (was an open question): collapses to "the
requested goto-yaw shown at the current heading." This also unblocks the
previewplan pusher.

**Wiring gap:** Pan Follow GPs are not pushed to the cart at all today.
TrackPlanPush only sends Track/Track-yaw. Pan Follow needs to reach the
cart as its own interval entry (a "go silent" window) — separable
pusher/protocol work.

## LOCK — model captured (NOT resolved; revisit, BNO-dependent)

**Operator model:** planned move to a target Ry, then HOLD that bearing
**independent of cart heading**. Crucially this is a WORLD-fixed bearing,
not a static cart-relative yaw: as the cart turns, the gimbal must
counter-rotate to keep the world bearing constant. (Inverse of Pan
Follow: Pan Follow = cart-frame fixed; LOCK = earth-frame fixed.) A
plain static commanded yaw only stays world-fixed if the cart never
turns.

**Two regimes:**
- **LOCK while parked (cart stopped):** heading isn't changing, so a
  plain static commanded yaw IS world-fixed. No counter-rotation, no
  heading source needed. Cheapest; build first if useful.
- **LOCK while the cart moves/turns:** needs
  `commanded_yaw = planned_Ry − (cart_heading_change since lock began)`
  → requires a live cart-heading-change source.

**Heading source for the moving case — the same fork as 3b:**
- **BNO** is the preferred truth source (operator: "LOCK is best enabled
  by BNO"). But BNO currently STALLS under motor power (see the
  motor-power note) — so LOCK-while-moving is blocked on that same
  electrical fix.
- **Bicycle-model dead-reckoning** (BicycleModel.bas, from cart wheel/
  steering data the cart already has) is the blind fallback, but it is
  known-imperfect (#20/#21: radius-only fit declined) → heading error
  accumulates over a long moving LOCK and the locked point drifts.
  Viable only as a SHORT-term hold, and only after real-world test.

**Decision:** LOCK is parked for now. Best enabled by BNO; revisit once
the BNO survives motors. If BNO can't be made reliable, evaluate
short-term bicycle-model maths with a real-world drift test before
trusting it.

## Step-4 status summary

- **Pan Follow execution:** designable + buildable NOW (BNO-independent).
  Cart-side = "go silent" window + one goto-yaw on entry. Plus push Pan
  Follow GPs to the cart (pusher/protocol change). Plus the executor's
  release-vs-keep-commanding distinction.
- **Pan Follow preview pose:** resolved (goto-yaw at current heading) →
  unblocks previewplan pusher.
- **LOCK:** parked, BNO-dependent for the moving case; parked-cart case
  is cheap but lower priority. Revisit after the BNO fix.

## Open handoff question raised, not yet decided

At a **Pan Follow → Track** boundary the cart goes from silent straight
to streaming position. Should the Phase-A ease (acquire_ms smoothstep,
already built) also apply at THAT handoff — easing from wherever the
Ronin's follow left the gimbal onto the track curve — or is that
transition allowed to snap? (Same question for LOCK → Track.) Decide
when building Pan Follow execution.
