# HyperLapse Cart — Session Summary, Day 25 (31 May 2026)

For future Claude. Read this first, then the consolidated docs. The
operator's working style is strict — see PREFERENCES_CONSOLIDATED.md.
Key points that bit this session: simple SEQUENTIAL one-step-at-a-time
instructions; NO menus of options/"maybe"s; NEVER suggest pausing or
ending the session; MEASURE/READ before theorising, do NOT stack
hypotheses or guess; raw URLs on their own line (not in code boxes).

---

## WHAT LANDED THIS SESSION (all validated end-to-end)

### 1. Recon IMU heading -> Excel (the core objective — DONE)
BNO heading now flows recon -> cart log -> Excel -> bicycle model.
- Cart: Mark-wpt (btn22) logs a 'W' then an 'A' row; 'A' value =
  true_yaw x10, plus cal. (Already in sketch from prior session.)
- Excel Cart.bas GetCartLog: 'A' rows land heading in col 12 (L,
  value/10) and cal in col 13 (M). These tail cols survive
  ProcessCartLog (which only clears E:K).
- BicycleModel.bas seeds theta0 from the first 'A' heading (negated:
  BNO is CW-negative). Measured -154.5 -> integrated +154.5. Validated.
- SIGN STILL TO CONFIRM against iPhone on a clean driven trace (the
  negate may need flipping if mirrored). Not yet done.

### 2. BNO motor-power stall — FIXED (categorical)
Stream froze under motor power. Root cause = I2C bus CONTENTION from
Tic clock-stretching (Pololu docs: Tic holds SCL low while busy),
NOT conducted noise. Prior "2.2k pull-up" fix was premature.
FIX: BNO moved to its OWN bus Wire2 (D8 SDA / D9 SCL), isolated from
Tics on Wire (D20/D21). 2.2k pull-ups on D8/D9 mandatory (mbed adds
none). Use the core's built-in Wire2 — do NOT declare your own
TwoWire (causes "multiple definition" linker error). Validated:
soak motors driving, /debug/imu last_poll_ms_ago 30-96ms, no stall.

### 3. /cartlog NON-CLEARING — FIXED
Was retrieve-and-clear; a stray browser read emptied the buffer
before GetCartLog, losing recon data.
- Sketch: /cartlog no longer clears. Added /cartlog/clearcart
  (clears ONLY the cart buffer; leaves gimbal log, recording,
  waypoint counter). Contrast /cartlog/clear = abandon EVERYTHING.
- Excel GetCartLog: calls /cartlog/clearcart only after a confirmed
  import (newRows>0). EMPTY check fixed to strip CR/LF on a COPY
  (Trim doesn't strip CRLF; don't strip the real response — Split
  needs the Chr(10) separators). Validated: browser re-read returns
  same rows.

### 4. Three pre-existing Excel bugs — FIXED
- TimestampDiff used CDate("00:00:00 " & t) -> type mismatch ->
  caught -> returned 0 -> ALL durations/distances were 0. Now
  TimeValue(t). (Verified in Immediate window: 105s correct.)
- ProcessCartLog distance was speed x time — operator says NEVER
  intended. Now (rearArr(i)-rearArr(i-1)) x M_PER_STEP (actual rear
  steps, same source as bicycle model). Snapshots RearSteps BEFORE
  the E:K clear wipes col 5. Added M_PER_STEP=0.00000178 + SafeDouble.
  GenerateReplayPlan unaffected (reads distance magnitude only).
- BicycleModel ApplyEvent 'T' used raw servo code as wheel angle;
  now evtValue - 98 (98 = straight, operator-confirmed).

### 5. btn3 (CTR) recenter logging — FIXED (sketch v22, NOT yet flashed)
btn3 set steering target to 98 but logged nothing; only the
ramp-arrival 't,98' appeared. BuildPlanFromCartLog ignores lowercase
't' (treats as informational), so the cart plan never saw the return
to centre and left Turn stuck at +32. The bicycle model DID catch it
(it UCases event type, so 't' hits Case "T"). FIX: btn3 now logs an
authoritative 'T,98' like cartAdjustSteering does. Banner soak-v22.
FORWARD-ONLY: existing recon logs predate this and still show held
+32 on post-recenter legs.

### 6. Cart-plan waypoint granularity — FIXED (PlanBuilder.bas)
Plan numbered every stop as a waypoint -> 5 marks became 13 rows.
This recon had ACCIDENTAL starts/stops (operator). FIX: only 'W'
marks number a leg; 'X' stops emit an un-numbered "—" STOP row and
legDistance CARRIES FORWARD to the next 'W' (not reset). Also fixed
WritePlanRow label: was derived from ROW INDEX (so STOPs stole
numbers regardless) — now from the passed wpNum. Bug found en route:
Chr(8212) throws "Invalid procedure call" (Chr is 0-255); use
ChrW(8212) for the em-dash. Validated: 5 marks -> WP01-WP05 + "—"
stops, distances carried (WP02=0.454m survived 3 stops before it).

---

## OPEN / NOT DECIDED

### Bicycle-model steering calibration (operator THINKING, not deciding)
Cart physically turned ~90° (operator ground truth) and BNO measured
~85° (WP1 +6.1 -> WP5 -79.0). Bicycle model integrated ~130-147°
(overshoot). Investigated by measurement, NOT guess:
- Ramp is NOT the cause: instant-on/off simplification gave the same
  overshoot (130-137°). Ruled out.
- Overdrive is NOT the cause: range only 0.95-1.00. Ruled out.
- Distance is NOT the over-rotation cause: log reads 6.15m total vs
  operator-measured 7-8m, i.e. log UNDER-reads — would make overshoot
  worse, not better. So the error is on the STEERING side.
- Circle test (17 May, 8-pt Kasa fit, +30 PWM, grass) gave
  SERVO_TO_DEG=0.504, R=1693mm — internally consistent.
- This recon's main leg implies SERVO_TO_DEG ~0.33-0.35 (matches the
  old day-9 quarter-turn estimate). Two clean measurements disagree;
  no known material difference.
- KEY INSIGHT (operator): protractor shows 30 servo units = 28° wheel,
  linkage near 1:1 at low angles -> geometric SERVO_TO_DEG ~0.93. BUT
  pure geometry (490mm wheelbase, 28° wheel) -> R=921mm, yet cart
  orbited 1693mm. Cart turns WIDER than the wheel angle implies = SLIP.
  So the driven SERVO_TO_DEG values (0.504, 0.33) are slip-corrected
  EFFECTIVE-steering factors, not linkage ratios.
- EMERGING STRUCTURE (agreed, not finalised): bicycle model is a
  planning VISUALISATION the operator edits the plan against — it is
  NOT fed to cart execution (BNO gives real heading at anchors). So
  the right structure is PURE GEOMETRY (honest 28°/wheelbase) x a SLIP
  FACTOR for on-ground path. To make THIS recon read 90°: slip = 0.376
  (eff wheel 11.3°). Circle test implies slip ~0.54. They BRACKET the
  real value. NOT decided which.
- CURRENT CODE STATE: BicycleModel.bas has SERVO_TO_DEG=0.504 and the
  -98 fix. The slip-factor restructure is NOT yet implemented — would
  be pure-geometry-wheel-angle x slip, replacing the single conflated
  constant.
- PROPER RESOLUTION needs a CONTROLLED re-test (linearity +5/+15,
  symmetry -30), not this single wobbly hand-driven recon. Operator
  flagged bicycle model is "at risk to provide [unreliable] repeated
  visualisation" until then — caveat any planning done off the trace.

### Other open threads
- Cart-plan Arrives column: still raw recon elapsed HH:MM:SS; the P3
  clock-time derivation is still a placeholder ("seed with raw
  timestamp for now" in WritePlanRow).
- M_PER_STEP / total-distance gap: log 6.15m vs measured 7-8m
  (~15-25% under). Entangled with slip; day-8 noted a similar ~10%
  theoretical-vs-measured gap (tyre deflection/slip). Needs the same
  controlled test.
- theta0 negate SIGN: verify against iPhone on a clean driven trace;
  flip if mirrored.

---

## NEXT STEPS (when operator returns to testing)
1. Flash sketch v22 to the cart (btn3 -> T,98). Watch the banner;
   if it shows old, clear Arduino IDE build cache
   (AppData\Local\arduino\sketches\) — a v19 flash this project
   previously refused to take due to a STALE BUILD CACHE despite
   dfu-util reporting success.
2. Controlled steering re-test to settle slip factor: repeat circle
   protocol at +5, +15 (linearity) and -30 (symmetry). Then decide
   pure-geometry x slip structure + the value (0.376 vs 0.54 bracket).
3. Confirm theta0 sign vs iPhone on a clean driven trace.
4. (Deferred, separate) plan-stream change: expected_cart_heading +
   earth/chassis frame tag into PlanSegment, then build 3b gimbal-yaw
   correction (-true_yaw) - expected_cart_heading; operator/iPhone
   override is a REQUIRED part of 3b.

## PENDING DOC WORK (not yet written into the masters)
Capture in the consolidated docs next session:
- The slip-factor analysis + the "geometry x slip" structure decision
  when finalised.
- The three Excel fixes (TimestampDiff, step-based distance, -98) and
  the btn3 logging fix, as build lessons.
- Build-lesson candidate: Chr() is 0-255, use ChrW() for Unicode in
  VBA cell writes.
- Build-lesson candidate: stale Arduino IDE build cache can make a
  dfu-util "success" boot the OLD banner — clear the cache.
  (Shared-bus / Wire2 lesson already captured in PREFERENCES build
  lesson 18 + GIGA_PIN_PLAN.)

## DELIVERABLES IN /mnt/user-data/outputs/
- DJI_Ronin_Giga_v2.ino    — soak-v22 (all cart edits; NOT yet flashed)
- Cart.bas                 — GetCartLog A-rows + clearcart + EMPTY fix
                             + TimestampDiff fix + step-based distance
- BicycleModel.bas         — -98 offset + SERVO_TO_DEG 0.504 + theta0 anchor
- PlanBuilder.bas          — stops un-numbered + label-from-wpNum + ChrW
- BNO085_BenchTest_Giga_Wire2.ino — Wire2 bench test
- CartLog_driven_recon.xlsx        — the real driven recon (RearSteps in E)
- CartLog_simplified_instant_turn.xlsx — instant-on/off test variant
- Cart_DIAG.bas            — diagnostic build (SUPERSEDED, can archive)
- CART_HEADING_DESIGN.md, BUILD_SPEC_recon_heading.md,
  IMPL_recon_heading.md  — heading design/spec/impl
- WORKFRONTS.md / WORKFRONTS_CONSOLIDATED.md, GIGA_PIN_PLAN.md,
  PREFERENCES_CONSOLIDATED.md, PROJECT_STATE_CONSOLIDATED.md,
  UI_DESIGN_v2.md        — master docs

## VERIFIED FACTS WORTH KEEPING
- Cart IP 192.168.1.97, WiFi "Rosedale". Operator on Windows/cmd.
- 98 = steering straight; servo range 60-130 on D5.
- Steering ramps 1°/sec (CART_STEERING_STEP_MS=1000). 't' logged only
  on ARRIVAL at target, not during the ramp. btn3 ramp-down from +32
  takes 32s; this recon's recenter t,98 at 00:04:05 means CTR pressed
  ~00:03:33 (cart still turning through the ramp, unlogged).
- M_PER_STEP=0.00000178 (1.77um/step, day-8). WHEELBASE_M=0.49.
- Bicycle model writes Trace sheet; reads RearSteps from CartLog col 5,
  steering as raw servo code (now -98 in ApplyEvent). UCases event type
  (so it catches lowercase 't'). Cart plan does NOT UCase (so it needed
  the btn3 T,98 fix).
