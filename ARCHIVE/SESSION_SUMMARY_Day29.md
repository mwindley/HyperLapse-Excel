# HyperLapse Cart - Session Summary, Day 29 (04 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. Operator style
held hard this session: SHORT replies, ONE thing at a time, lead with the
answer, yes/no when asked, MEASURE/READ before theorising, NEVER guess,
NEVER jump to root cause, keep separate hardware separate, pure ASCII, no
fancy stuff. Repeated rebukes this session: "what a story", "too big a
story", "again a long story", "stop and think", "no discussion" - and
twice for jumping ahead of the evidence. When the operator says "wait, I
have more to share", STOP and let them finish before analysing.

The headline: the gimbal plan was authored, pushed, and executed
end-to-end; the Phase-A ease bug was fixed and proved; the CAN bus was
traced and restored; and the real design gap was named - gimbal execution
must be WP-event-anchored, not clock-anchored. A stepwise build plan for
that capability was written (WORKFRONT_gimbal_WP_coordination_Day29.md).

---

## WHAT LANDED THIS SESSION

### Gimbal plan authored + pushed + executed
- Built the gimbal block in the Plan sheet to a simple test: GP01 WP01
  straight (dyaw 0), GP02 WP02 right (dyaw -30), GP03 WP03 left (dyaw
  +30), GP04 WP04 straight (0), GP05 WP04 END. Action = Move; END bounds
  the last move's window (the push errors if a Move is the last row).
  Sign convention applied: right = negative yaw (cart CW-negative frame);
  flagged for operator confirmation, not measured on the Ronin.
- Push macro = `PushTrackPlanToCart` (gimbal). Dry run via
  `dataPlanPushDryRun = TRUE`, real push FALSE. (`PushGimbalPlan` is
  validate-only, NOT the push.) No AstroPush/cubics needed - all GPs are
  Move, obj=N.
- Documented "what can be typed" per gimbal column from the sheet's
  data-validation lists + PlanAuthoring.bas. Two stale-DV findings: col P
  (Offset) carries an old "Pan Follow,Approach,Lock" dropdown from a prior
  layout; "Approach" survives only there (live Action list dropped it).
- Col AA "Move t" = a vestigial DERIVED placeholder. PlanAuthoring writes
  the literal "(computed)" and paints it grey; PlanPush declares
  COL_MOVE_T=27 but never uses it; the real move time is computed at push
  from Ease x cadence. Nothing reads AA. Safe to ignore/clear.

### TrackPlanPush.bas - Phase-A ease / sunset fix (DELIVERED)
- Symptom: dry run logged "sunset/sunrise not set", cadence 0, ease
  forced to snap, even on a WP-only plan.
- Cause (measured): TrackPlanPush read the sun-time cells through
  SafeNum, whose IsNumeric() gate returns 0 for a DATE-typed cell. The
  sun cells (Settings F8/F18/F22) store full datetimes, so they read as 0
  -> cadence 0. Fires-at survived because it is time-of-day only.
- Second fault: sun times carry a date, plan Fires-at are time-of-day
  only - different bases for the cadence subtraction.
- Fix (read-time only, GetSunsetTime untouched): added `CellSerial`
  (IsDate-aware read) and `StampClock` (place fire + sun-event times on
  ONE dated timeline anchored at the shoot evening; sunrise rolled to the
  end-of-shoot morning so fireTime-sunriseT has the sign FormulaTv's
  sunrise branch wants). Confirmed FormulaTv expects negative t_rel
  before sunrise before writing.
- Proved: dry run then REAL push - cadence 22.0s, acquire_ms non-zero,
  4 intervals accepted. Build marker added: "(build: Day28
  dated-timeline ease fix)" prints on the start line.
- Ease band note: at 22s cadence, Comfortable (10 frames) = 220s ease,
  which overran the 2-min GP01/GP04 windows; switched those to
  Just-perceptible (3 frames) = ~66s, which fits.

### Giga_CAN_bus_test.ino - standalone CAN isolation sketch (DELIVERED)
- No WiFi/SDK/gimbal logic. 1 Mbit, TX id 0x223, sends a dummy frame
  every 50ms, reports TX OK/FAILING + any RX. Same write() pass/fail
  signal the main sketch logs as "TX errors". Used to clear gimbal,
  spare rig, and finally the cart Giga + Pal one variable at a time.

### WORKFRONT_gimbal_WP_coordination_Day29.md - build plan (DELIVERED)
- The stepwise plan for WP-event-anchored gimbal execution (see below).

---

## KEY UNDERSTANDINGS REACHED (operator-driven, measured)

### Gimbal execution must be WP-event-anchored (the big one)
- The plan binds GP to WP: Plan col Q (Fires-at) = the WP's Commence time
  (col J) + Offset (col P). There is NO independent gimbal timebase in the
  plan.
- The firmware does NOT honour that: TrackPlanPush flattens each GP to
  absolute ts/te ms, and trackPlanTick walks them against its own clock
  (`millis() - track_plan_anchor_ms`), anchored at `/track/start`. The
  executor never reads cart WP progress.
- So cart and gimbal run on TWO independent clocks. `/track/start` zeros
  the gimbal; `/plan/start` zeros the cart; `/plan/start` does NOT re-sync
  the gimbal (confirmed in sketch). Whatever gap is between the two
  start calls becomes permanent drift; cart slip or a `/plan/nudge`
  widens it. This is why the Day-28/29 runs were not coordinated.
- Design intent (operator, firm): GP is tied to WP - whenever the WP
  happens, the GP executes (arrival + offset), surviving slip/nudge.
- The clean hook: the cart already stamps the WP arrival in
  `planSegmentEnter` (`plan_seg_start_ms = millis()`), which IS that WP's
  Commence - the same instant col J represents. WP-event anchoring =
  hooking the gimbal onto an event the cart already produces.
- `/plan/nudge?d=+-N` exists (Day-15/16): live +-mm trim of the running
  MOVE segment. Cart-only - it does NOT touch the gimbal plan, so under
  the current firmware a nudge desyncs cart vs gimbal further.

### Cubic astro tracking is already in the sketch
- `TrackPath` holds per-object cubic coeffs (sun/moon/mw), pushed via
  `/settings/trackpath`; `trackEvalAt` evaluates a0+a1t+a2t^2+a3t^3 each
  tick; the executor drives FULL (yaw+pitch) and YAW (yaw + fixed pitch)
  modes from it. Sun Track hardware-proven. Model B already anchors the
  cubic to REAL time (`real_t0_ms`/`cartRealTimeMs`), so once a WP event
  sets WHEN the interval opens, the cubic gives WHERE the object is at
  that real moment. The tracking math is done; only the WHEN needs to be
  WP-anchored.

### Heading model with BNO stubbed (future work)
- BNO is now stubbed (Day-28). Heading source moves to the iPhone -
  rung 1 of the CART_HEADING_DESIGN trust ladder - with planned
  `expected_cart_heading` as the floor.
- New Day-29 refinement: Cart Recon now captures a compass reading per
  WP. That recon compass becomes `expected_cart_heading` (pushed per WP),
  so the planned heading is measured, not pure bicycle integration. At
  execution, an iPhone request on approach to an astro GP = compare /
  override / offset against it, propagated forward to stop cumulative
  drift. Feeds the existing 3b correction on earth-frame GPs only.
  All future work.

---

## CAN BUS (traced + restored; factual, root cause of trans 2 unconfirmed)
- Gimbal CAN was dead at session start - TX errors climbing, no ACK.
  Established: 1 Mbit both ends; the gimbal accessory link is point-to-
  point and the external node IS an end, so it must terminate. Gimbal
  presented 120 (one terminator); switching the Pal's 120 on gave ~66
  ohm (both ends). Wiring continuity + H/L verified.
- Still TX errors after termination. Isolation via the test sketch:
  spare Giga + spare Pal -> gimbal STREAMS 0x530, two-way good (gimbal +
  spare rig + Ronin all cleared). Cart Giga + production Pal -> TX
  FAILING, rx=0 (the controller accepts ~3 frames into the mailbox then
  collapses when nothing ACKs).
- Parts now: trans 1 dead (reverse polarity, known, operator error);
  trans 2 = production/suspect, REMOVED, cause UNCONFIRMED; trans 3 +
  spare Giga now in the rig and WORKING (0x530 streaming, `/home` good,
  TIC on).
- CORRECTION for the record: I called the S (silent-mode) pin as the
  production fault. That was PREMATURE and wrong - the production Pal had
  S tied to GND (normal mode), the spare had S unconnected (also normal);
  both are normal-mode wiring. Do NOT attribute trans 2's failure to the
  S pin. Cause unconfirmed.

---

## NEXT STEPS (when operator returns)
1. Build WP-event-anchored gimbal execution per
   WORKFRONT_gimbal_WP_coordination_Day29.md: Phase 1 (carry anchor WP +
   offset through the push; record `wp_arrival_ms[]` in planSegmentEnter)
   -> Phase 2 (fire intervals off arrival + offset; retire the gimbal
   clock; this SUPERSEDES the parked /plan/start re-stamp idea) -> Phase 3
   (validate, incl. a nudge test) -> Phase 4 (astro + heading, future).
2. Two decisions deferred to build time: fire-late-vs-skip when an
   offset window is still open at the next WP; Pan-Follow -> Track
   handoff ease.
3. Interim, to SEE coordinated motion before the build: fire
   `/track/start` and `/plan/start` back-to-back (within ~1s). Note GP01
   is a real move now (Move eases from the gimbal's actual non-zero yaw
   to 0), not a no-op.
4. Housekeeping so the standing docs are not misleading: fold the Day-29
   workfront into WORKFRONTS.md (or note it at the top); fix
   PROJECT_STATE "State of the system" which still says gimbal execution
   is "design only" (superseded by Day-24 proofs + the Day-28/29 runs).
5. Future: iPhone heading 3b + recon-compass `expected_cart_heading`
   propagation.

## DELIVERABLES IN /mnt/user-data/outputs/
- TrackPlanPush.bas                         - Phase-A ease/sunset dated-
                                              timeline fix (re-import)
- Giga_CAN_bus_test.ino                     - standalone CAN isolation
- WORKFRONT_gimbal_WP_coordination_Day29.md - stepwise build plan
- SESSION_SUMMARY_Day29.md                  - this file

## MISTAKES OWNED THIS SESSION (carry the discipline forward)
- "GP01 will not move" - WRONG. Move eases from the ACTUAL current pose
  to the absolute endpoint; current yaw was non-zero, so GP01 (yaw 0)
  moves. Read the executor, do not assume a zero-target is a no-op.
- "Cart and gimbal hang off the same start clock" - WRONG. Independent
  clocks; only the plan numbers are shared.
- S-pin called as the CAN fault - PREMATURE, wrong (see CAN section).
- Conflated the spare bench rig with the cart hardware - the operator
  corrected it. Keep separate hardware separate when reasoning.

## PROCESS NOTE (reinforced hard)
Answer the exact question, lead with the answer, stop. Yes/no first when
asked yes/no. Measure/read before theorising; do NOT jump to root cause -
state findings, not stories. When the operator says to wait, wait. Keep
pure ASCII / simple. Several rebukes for length and for getting ahead of
the evidence; the discipline that worked was: one finding, one or two
lines, stop.
