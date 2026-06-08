# HyperLapse Cart - Session Summary, Day 30 (05 Jun 2026) [FULL]

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. This supersedes the
earlier Day-30 summary (which stopped after the heading unification) - the
session continued into the Execution UI, chart, and pano.

Operator style held all session: SHORT replies, lead with the answer, ONE
thing at a time, MEASURE/READ before theorising, NEVER guess, NEVER change
design limits/parameters/methods on a whim (got pulled up for proposing a
180deg/20-60 axis change - reverted; the operator does not change on a whim).
Pure ASCII (got pulled up for an em-dash literal in ChartPush - fixed).
FORMATTING (reinforced, hold it): macros in CODE BOXES, test URLs as BARE URLs
on their own line. Do NOT suggest ending/pausing the session (got pulled up).
When the operator says "stop", stop. When testing, hold issues/questions until
the operator calls the test done ("talk issues at end of test not during").

---

## HEADLINE
Three big things landed and are HARDWARE-PROVEN:
1. WP-event gimbal coordination (Phases 1-3) - GPs fire on the cart's ACTUAL
   WP arrival, survive nudge/slip. (covered in the earlier Day-30 summary.)
2. Heading convention UNIFIED on the Ronin/standard CW-positive frame
   (E=+90). BicycleModel boundary flip; HEADING_CONVENTION.md is the source of
   truth. (earlier summary.)
3. The Execution screen is BUILT and live on the cart: reassurance ribbon,
   Excel-authored chart with live camera icon, time-ordered WP/GP row list,
   and controls (Start, E-stop, nudge, heading-update stub, Pano).

---

## EXECUTION UI - DESIGN (captured in UI_DESIGN_Execution_v3.md)
Premise: operator is a SPECTATOR. Path/angles/timing are set-and-forget. The
UI is REASSURANCE + two narrow interventions (heading refine; cart-safety
nudge). FOV reality (14mm on full-frame R3 = ~104H x 81V) means a 5-15deg
heading error is post-fixable; a LATE/mis-aimed move is not - so the UI
optimises for catching imminent moves, not heading precision. Time context:
recon -> van (build+push plan) -> long WAIT -> "lights action" Start much
later. So Start lives on the Exec screen, NOT bundled with the push. The cart
stays powered through the wait (plan kept in RAM); Tics de-energise to save
power. One agnostic alert (red row + optional beep) fires for either an astro
GP approaching OR a fast pan approaching (~2min ETA, time-based). Heading
update = button prepopulated with expected (recon floor), operator overrides,
cart computes delta, REPLACES the running offset (not additive - prevents
cumulative drift), forward-only, non-blocking. iOS audio: tap-to-Start unlocks
it; ringer must be ON (checklist); red row is the real signal, beep best-effort.

## EXECUTION UI - BUILD (all on the cart, soak-v44)
- /exec/feed (v38-v44): JSON the screen polls @3s - plan state, live gimbal
  yaw/pitch, time-ordered WP/GP rows with SIMPLE planned-time ETA (reached
  events use the real wp_arrival stamp), ribbon fields (batt/photos/rssi/can,
  cam='?' placeholder), ymin (chart axis), pano phase+pidx. GP state is HONEST
  ('idle' when track unarmed, never a guessed 'done').
- Screen served at /?screen=exec (the exec branch of the shared 3-screen page;
  day palette - NIGHT PALETTE DEFERRED). Ribbon (2 lines: batt/photos/age/rssi
  + cam/CAN), plan-state line, chart, WP/GP row list (earth badge, fast NNdeg
  badge, hdg button on earth GPs), controls.
- Controls wired to real endpoints: START = /btn15 (energise) -> /track/start
  -> /plan/start (confirm; the tap also unlocks iOS audio). E-STOP = /plan/stop
  -> /btn14 (de-energise), instant no-confirm. nudge = /plan/nudge?d=+-100.
  hdg = prompt STUB (real endpoint is the next build). PANO = /gimbal/pano.
- Build-lesson 16 (JS-in-client.println escaping) handled: validated the
  emitted JS bracket/quote balance statically before flashing; survived.

## CHART (Excel authors, Giga moves the icon) - PROVEN
- Architecture (operator's): Excel computes the faithful path at bake and
  authors an inner SVG; the cart stores+serves it and only moves the live
  camera icon. CONTRACT (locked, do not change on a whim): viewBox 0 0 355 90;
  x=(yaw-yaw_min)/450*355; y=90-(pitch-20)/60*90 (pitch 20 bottom..80 top);
  dashed 80deg limit line. 450deg yaw span, 20-80 pitch are the DESIGN.
- Cart (v43): /settings/chartsvg?idx&last&yawmin&d= reassembles + URL-decodes
  (getStr does NOT decode - urlDecode added) chunked SVG into chart_svg; serves
  it; ymin in feed; JS positions #xcam from yaw/pitch/ymin. PROVEN with a
  hand-made SVG.
- Excel (ChartPush.bas, NEW module): PushChartToCart reads Move/Pan-Follow GP
  rows (point = Ry+dyaw, Rp+dpitch), authors blue polyline + dots + gridlines +
  dashed 80, computes yaw_min, chunk-pushes (150 raw chars/chunk, percent-
  encoded; chunk RAW then encode so no %XX split). PROVEN: test plan points
  (0,20)(-100,30)(-180,60)(0,0), yaw_min=-180, 503-char SVG, 4 chunks, rendered
  correctly on the phone. Track/Track-yaw rows skipped (astro charting deferred
  - the extension uses col-H planned heading + AstroPush az/alt samplers).

## PANO - it was JUST a button
Previous Claude had already built the whole pano firmware (state machine
PANO_IDLE..DONE, panoStart/panoTick/panoIssueSlew, /gimbal/pano +
/gimbal/panostatus, plan skipped during pano, offsets {-78,-26,26,78} = 4 shots
centred on current gimbal yaw). Tonight = add a PANO button on the Exec screen
-> /gimbal/pano, + pano phase/pidx in the feed -> now-line 'PANO shot N/4 (plan
paused)'. PROVEN: tapped, swept -77.8/-25.9/+26.2/+78.2, shutter fired each,
logged 4, resumed to trigger pose. NB the gimbal SLEEPS - if /home or pano does
nothing, wake the gimbal first.

---

## DELIVERABLES IN /mnt/user-data/outputs/ (this session, full)
- DJI_Ronin_Giga_v2.ino   - soak-v44 (Phase1-2 WP-event firing, wp_arrival
                            stamp, /exec/feed, Exec screen, chart receiver,
                            idle auto-de-energise, PANO button)
- TrackPlanPush.bas       - Phase-1 awp/offms tail tokens
- BicycleModel.bas        - heading boundary flip to CW-positive
- ChartPush.bas           - NEW: Execution chart author (Move/relative scope)
- HEADING_CONVENTION.md   - single source of truth (unified CW-positive frame)
- UI_DESIGN_Execution_v3.md - Execution screen design (spectator model)
- SESSION_SUMMARY_Day30.md  - the earlier (pre-UI) summary
- SESSION_SUMMARY_Day30_FULL.md - this file

## FIRMWARE STATE
soak-v44 on the cart. New since v34: v35 awp/offms stored on TrackInterval;
v36 wp_arrival_ms stamp in planSegmentEnter; v37 Phase-2 live WP-event interval
selection (trackIntervalOpenAbs); v38 /exec/feed; v39 honest GP feed state;
v40 idle auto-de-energise (energised+vel0+outside-plan, 2min, reset on ENRG/
Start); v41 feed ribbon fields; v42 Exec screen served; v43 chart receiver;
v44 PANO button + feed pano fields.

## NEXT STEPS (operator's order: heading, then the list)
1. HEADING - operator confirmed: build BOTH halves, ENDPOINT FIRST (it is the
   logical foundation; the executor correction has nothing to apply/test until
   the endpoint feeds it a value). Two halves:
   1a. ENDPOINT half (make the hdg button real, self-contained, testable
       alone): push per-WP expected_cart_heading (PlanBuilder ALREADY writes it
       to Plan col H - just send it to the cart); store it cart-side; the Exec
       hdg button posts the operator's REAL heading; cart computes delta and
       stores it as the running offset - REPLACE (not additive), FORWARD-only,
       non-blocking (no input -> planned floor). Test: post a heading, read the
       stored offset/delta back in /exec/feed. NO sign flip (cart+gimbal both
       CW-positive now). NEXT ACTION when resuming: read how col H /
       expected_cart_heading currently flows (PlanBuilder + any push) before
       wiring - do not guess.
   1b. EXECUTOR half (Phase 4 / 3b): trackPlanTick astro path applies
       gimbal_yaw_correction = real_heading - expected_cart_heading to the
       commanded gimbal yaw, EARTH-FRAME GPs ONLY (relative pans + cart path
       stay heading-independent). Testable once 1a exists, ideally in the
       daylight Sun Track run.
2. Then the parked list:
   - Astro chart curves (extend ChartPush: col-H heading + AstroPush az/alt
     samplers; daylight verify).
   - Gimbal UNWIND / cumulative-yaw: a Move takes the SHORTEST path now (can
     wind toward cable tangle). Decide operator-in-plan control (a per-Move
     unwind/direction hint - simple, not auto cable-modelling). MEASURE the
     executor first: does it command cumulative +-450 or wrapped +-180?
   - Live daylight Sun Track WP-anchored run (Phase 4 piece A) - mind the UTC
     epoch consistency (rt0 and /settings/realtime both UTC epoch-ms).
   - SERVO_TO_DEG slip calibration (model over-rotates; controlled test).
   - Pano "same Tv" (uses default 800ms now; wire the live plan Tv).
   - cam CCAPI-alive flag (feed shows '?'; photos-climbing is the alive proxy).
   - Reconcile remaining docs to HEADING_CONVENTION.md (CART_HEADING_DESIGN,
     GIMBAL_EXECUTION_CAPABILITIES, WORKFRONTS, GIMBAL_VIZ, the Day-29
     workfront sec 4, PROJECT_STATE 'design only' line).
   - Night palette for the Exec screen (deferred; standalone shell proves it).
   - LOOP-LONG stalls (1.4-3.0s) around gimbal commands - partly the gimbal
     SLEEPING (wake it). Worth instrumenting if it persists when awake.

## MISTAKES OWNED
- Proposed changing the chart axes (450->180, 20-80->20-60) - the operator does
  NOT change design limits on a whim; reverted to 450/20-80.
- "No code to change" for the convention unification - was true only for the
  gimbal path; the cart BicycleModel needed the flip. (earlier summary.)
- Em-dash literal in ChartPush broke VBA (non-ASCII) - fixed to ASCII content
  test.
- Suggested ending the session / handed macros as bare text - both against
  standing preferences; corrected.

## PROCESS NOTE
Measure the actual code/sheet/datasheet before stating anything; lead with the
answer; one finding at a time; stop when told. Sign conventions and the chart
size were settled by MEASUREMENT, not assertion. The pano was a reminder to
CHECK what previous Claude already built before designing - the whole state
machine existed; the task was one button.
