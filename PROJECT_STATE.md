# HyperLapse Cart — Project State

**Last updated:** 13 May 2026 (end of Session C day 7 — Cart and Gimbal Log/Plan/Execution architecture discussion)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

Also upload `PREFERENCES.md` (sibling file) — that contains the working
agreement, the oscilloscope diagnostic approach, the standard test
sequence, and the WiFiS3 gotchas. Read both at session start.

---

## ⚠️ Top-of-file context — Session C day 7 outcomes

### What we did today

Pure design discussion. No code changes, no tests, no hardware swaps. Focus
shifted away from CCAPI/optocoupler for a day to architect the cart and
gimbal motion subsystems: how recon Log → Excel Plan → cart Execution
should work for both cart-position and gimbal-pointing.

### Cart Log / Plan / Execution — agreed architecture

**Position model (rear-axle reference, bicycle/Ackermann):**
- Wheelbase L = 490mm (centre-to-centre, measured)
- Velocity source: rear TIC step count × m_per_step
- Steering source: servo PWM × linear servo-to-wheel calibration
- Overdrive treated as known speed-dependent correction (0.95 at slow → 1.00
  at max), validated once by straight-line test, not measured per-event
- Front step count NOT logged (real-world says rear doesn't slip on the
  surfaces this cart sees; the differential absorbs overdrive mismatch
  internally; front-step logging adds no information until it does)
- TIC position-control safe ceiling ~130 m/hr; recon at 100, exec at 5 —
  both well inside

**Cart Log:**
- Event-driven (one row per UI change — speed, steering, stop)
- Add `rear_steps` (int32) to `CartLogEntry`, read via
  `ticRear.getCurrentPosition()` at the moment of each event
- Buffer ~64-128 entries in RAM (handful per minute, no SD, no streaming)
- Existing `/cartlog` poll-and-clear endpoint stays the retrieval path

**Cart Plan (built in Excel from Log):**
- 5-10 rows typical
- Movement segments: `(distance_m, steering_deg)` — distance = rear-axle
  arc length, matches rear step count directly
- Stops: `(duration_s)`
- Acceleration overhead measured once (drive a long straight at 5 m/hr,
  compare clock to distance÷speed); included in time estimates, not modelled
- Sun alignment via shoot start time

**Bicycle math placement: Excel only.**
- Forward integration: Log → (x, y, θ) trace, for the operator to see what
  they drove during recon
- Inverse fitting: trace → smooth Plan via single-arc geometry per
  smoothable section (chord length + heading change → radius → steering
  angle → arc length)
- Cart receives Plan in cart-native units (steps to travel, servo PWM to
  hold) — cart firmware stays dumb, calibration constants live in Excel

**Cart Execution:**
- Excel POSTs Plan to `/plan/load` at shoot start
- `/plan/start` begins the walker
- Per row: set steering, set speed, watch rear step count, advance when
  target reached (or duration elapsed for stops)
- No bicycle integration on cart — just step counting + servo control

### Gimbal Log / Plan / Execution — agreed architecture

**Gimbal Log already exists** — `gimbalLogCapture()` triggered by btn20,
records (ms, yaw, pitch) waypoints, 64-entry buffer, pulled by Excel via
`/gimballog`. Used during recon for operator-pointed framing snapshots.

**Three motion regimes during shoot, cleanly separated:**

1. **Driving — Pan Follow mode.** Gimbal hardware tracks cart heading.
   Cart commands yaw in cart-frame (0, ±90). No θ feed needed during
   motion. Operator-set yaw values pre-baked into Plan.

2. **Astro tracking at stops.** Cart computes target live from astro
   formulas + heading anchor + current time. Sun, galactic centre (and
   later: sunrise, moon if needed). Commands gimbal continuously.

3. **Creative manual pans between waypoints.** Operator-recorded waypoints
   from the Log are arranged in Plan as a sequence; cart interpolates with
   **Catmull-Rom cubic spline** between them — flows through every point,
   tangents inherited from neighbours, no operator-set handles.
   Bezier-family but with auto-tangents (good-enough flow-through).

**Heading anchor model:**
- Operator anchors cart heading via iPhone compass at shoot start
- Bicycle model integrates heading θ during drives (approximate)
- At every stop, UI shows cart's predicted heading; operator validates /
  corrects against iPhone compass before astro tracking starts
- Astro tracking always runs from a fresh anchor — never relies on
  integrated heading through a drive

**Yaw range is cumulative ±450°, NOT ±180°.** The RS4 Pro can do 720°+
mechanically; we limit to 900° total travel (−450° to +450°) for pin-8
cable safety. Operator pre-winds cables worst-case at setup. Plan and
Execution work in unwrapped cumulative yaw. Current `Gimbal.bas`
constants `GIMBAL_YAW_MIN/MAX = ±180°` are wrong for our purposes —
needs change to ±450°.

**Gimbal motion commands:**
- `setPosControl` does timed easing per call, up to 25.5 sec
  (uint8_t in 0.1s units) — good for waypoint-to-waypoint short moves
- `setSpeedControl` does continuous angular velocity, 0.5s valid window,
  re-issue continuously — best for slow tracking (sun, milky way, slow
  creative pans). Currently unused from Excel side — Gimbal.bas only
  calls `setPosControl` via `/move`.
- Long moves (>25.5s) handled by cart subdividing into segments along
  the Catmull-Rom curve, OR by using speed control mode

**Astro maths port to cart:**
- Current Astro.bas is well-factored: ~60 lines of dense maths
  (sun position, GC position fixed at RA=266.4167°, Dec=−29.0078°,
  RADecToAltAz, Julian day, GMST/LST). Galactic centre is a constant pair.
- ~100-150 lines of C on the cart. Uno R4 has hardware FPU, fine.
- **14mm f/1.8 lens (Sigma 14mm f/1.8 Art-class) is very wide** —
  104° HFoV. Current ~1° accuracy is plenty; no need for Meeus-grade
  algorithms. Refraction correction nice-to-have but not required.

**Gimbal Plan visualisation:** XY chart, yaw on X (cumulative −380° to
+70° span, fits 450° window), pitch on Y (0° to 90°, with hard-zone
dashed line at 80°). Waypoints as dots, Catmull-Rom spline drawn through
them. Operator authors / inspects the night's gimbal trajectory at a glance.

### Uno R4 vs production — verdict: stays fine, but watch loop budget

The cart firmware additions are modest in memory (a few KB) and
computation (Catmull-Rom eval, astro recompute every N seconds, plan-row
walker). None strain the Uno R4 hardware.

The real concern is **loop time** — sacred rule says photos never delayed.
Current `max_loop_us` instrumentation already exists in the PIN8 log,
so we measure rather than guess as features land. **Not a reason to
switch to Giga preemptively.**

### Workfronts created today (see "Open workfronts" section below)

Architecture decisions only — implementation deferred. The following work
is queued:

1. Cart firmware: add `rear_steps` to `CartLogEntry`, grow buffer,
   add `/plan/load` and `/plan/start` endpoints, write plan-row walker
2. Cart firmware: port astro maths from Astro.bas to C (~100-150 lines)
3. Cart firmware: replace ±180° yaw constants with ±450° cumulative
4. Cart firmware: wire up `setSpeedControl` for slow continuous gimbal moves
5. Cart firmware: heading-anchor endpoint, integrate cart-θ during drives
6. Excel: bicycle integration (Log → trace), arc-fitting (trace → Plan),
   new Plan sheet schema with cart + gimbal rows interleaved
7. Excel: Catmull-Rom evaluator for gimbal smoothing (preview only;
   real evaluation happens on cart at execution)
8. Excel: Gimbal Plan XY chart (yaw cumulative × pitch with 80° hard zone)
9. Calibration tests: straight-line (m_per_step + overdrive),
   circle (servo-to-wheel-angle), S-bend (only if needed)
10. Acceleration overhead measurement at 5 m/hr

### Files modified today

None. Discussion / design session only.

---



### What we learned today

**Production edge case identified.** From Excel table, the tightest
production margin is sunset 18:15-18:24: Tv=0.2"-1.6", interval 2-4s,
Tv changing every minute. **The most stressed combination is Tv=0.8" +
interval=2s** — only 1.2s gap between exposure end and next pin-8.
Luminance fetch needs to be every 30s during this window. Outside this
10-minute peak luminance window, intervals are generous and drops have
never been an issue in real-world overnight runs.

**Cart-side electrical signal is pristine.** Added heavy instrumentation:
- D9 jumpered to D8 for readback (INPUT mode)
- `[PULSE rise=Xus fall=Yus high=N/M]` per fire — microsecond edge timing
- PIN8 log enriched with `loops=N max_loop_us=X fire_us=Y` for loop context

Across all tests (Tv=0.8"/2s, 49 fires, 3 drops): every PULSE line shows
rise=6-9µs, fall=6-9µs, all 28000+ samples HIGH (zero glitches), fire_us
always 103.76ms. **Dropped fires are statistically indistinguishable from
captured ones at the Arduino pin.**

**Intervalometer test (200+ fires, 14 min): 100% delivery.** The
intervalometer plugs in at the cable mid-join, BYPASSING the optocoupler.
The cart goes through the opto. Cart drops to 75-94% in the same window.

**Conclusion:** The Arduino pin-8 signal is fine. The drops happen
downstream of the Arduino — most likely in the optocoupler. Without an
oscilloscope or logic analyser we cannot see the opto's output to confirm.

### Delivery results by test

| Test condition | Result |
|---|---|
| Tv=2" + interval=4s, no CCAPI (5 min) | 90% (63/70) |
| Tv=2" + interval=4s, no CCAPI (20 min) | 75% (242/321) |
| Tv=0.8" + interval=2s, no CCAPI (~1.6 min, 36 fires) | 78% (28/36) |
| **Tv=0.8" + interval=2s, no CCAPI** (5 min, 49 fires) | **94% (46/49)** |
| **Tv=0.8" + interval=2s, WITH CCAPI** (5 min, 165 fires) | **76% (125/165)** |
| Intervalometer at 4s (14 min) | **100% (214/214)** |

Note: CCAPI test used current "fetch every 3 photos" rule, which at 2s
interval = fetch every 6s. **5× more frequent than the 30s production
target.** True production fetch cadence has not been tested yet.

### Key insight — drops are NOT correlated with cart-side anomalies

For each dropped fire, the cart-side log entries show:
- Same gap (2000-2004ms)
- Same loops count (~320)
- Same max_loop_us (~122k)
- Same fire_us (103.76ms)
- Same PULSE rise/fall (6-9µs)
- Same samples (no glitches)

As captured fires. The Arduino is doing the right thing every time.

### Tomorrow priorities

1. **Hardware: replace optocoupler and resistor.**
   Recommended from Jaycar Australia:
   - ZD1928 4N25/4N28 optocoupler ×2 ($1.75 each, one as spare)
   - 220Ω 1/4W resistor pack (or 330Ω for safer LED current)
   Total: ~$5
   Stay in the 4N25 family (6N138 needs Vcc on output side — not available).
   
2. **Measurement: buy USB logic analyser BEFORE swapping opto.**
   Recommended: SparkFun TOL-18627 USB Logic Analyzer (24MHz, 8-channel)
   from Core Electronics, ~$30. Uses open-source PulseView/sigrok.
   With this we can measure both sides of the opto simultaneously and
   PROVE the diagnosis before guessing-and-swapping.

3. **Test true production fetch cadence (time-based 30s).**
   Current code does "every 3 photos" — must add time-based fetch
   interval. New code: `LUM_FETCH_INTERVAL_MS = 30000` time-gated, decoupled from photo count.

4. **After opto swap: re-run Tv=0.8"+2s test, target 100% delivery.**

### Files modified today (in /mnt/user-data/outputs/)

- `DJI_Ronin_UnoR4_v2.ino` — heavy PIN8 instrumentation
  - CART_SHUTTER_READBACK = D9
  - backupShutter() rewritten with PULSE diagnostic
  - PIN8 log line enriched with loops/max_loop_us/fire_us
  - diag_loop_count tracking in loop()
  - T1b live view suppression (one-shot log + silent return)
  - ANCHOR call at /shutter/start
  - /debug/poll_camera?on=1 endpoint
- `photo_delta_check.py` — pagination fixed (page=2,3,4… not 1,2,3)

### Cross-reference workflow

After each test:
1. Cart serial captures every PIN8 fire with millis timestamp
2. Camera CCAPI provides per-file `lastmodifieddate` (second precision)
3. `photo_delta_check.py` walks all pages of /contents/cfex/102EOSR3
4. Manual correlation: anchor PIN8 #1 to first captured photo, infer
   each subsequent fire's expected camera time, find nearest capture
   within ±1.5s = OK, else DROPPED.

This gives definitive per-fire labels, which let us check whether
cart-side instrumentation differs between OK and DROPPED fires.
(Result: it doesn't.)

---

## State of the system

### What works

- Stage 3 Tv-driven cadence (committed day 5)
- Body-read 30× speedup (committed day 5)
- Fetch backoff (committed day 5)
- REQ-PHASES instrumentation (committed day 5)
- PIN8 + PULSE instrumentation (today, uncommitted)
- Cart-vs-camera cross-reference (today, uncommitted)
- Intervalometer fallback (always worked, never modified)

### What's tested at production edge

- Photo cadence at Tv=0.8" + 2s: 94% no-CCAPI, 76% with-CCAPI-at-6s
- Pin-8 electrical output: pristine on every fire
- Camera + cable + intervalometer: 100% reliable

### What's NOT tested

- Fetch interval at true production 30s cadence
- Tv=0.8" + 2s with new opto + 30s fetch
- Anything beyond 5-20 minute soaks
- Sunrise transition (only sunset table reviewed)

### Hardware uncertainty

- Existing opto is sealed/wrapped — cannot inspect resistor value or model
- Cart-side signal verified perfect via D9 readback
- Intervalometer bypasses opto and gets 100% — opto strongly suspected
- No measurement of opto OUTPUT signal yet (needs scope or logic analyser)

---

## Working preferences (carry forward)

- Windows cmd syntax (not bash)
- Small steps, ask ONE question at a time, wait for confirmation
- Code boxes for commands and URLs (copy button matters)
- Oscilloscope approach — instrument, don't guess
- Photos are sacred; wrong exposure is fixable in post
- Pin-8 must work when CCAPI is down
- Tv+1.5s cadence rule
- Real-world Excel table is authoritative for production scenarios
- See PREFERENCES.md for full agreement

---

## Open questions for tomorrow

1. Should we order opto + analyser before next session? (User intends to.)
2. Order priority: analyser first (measure before fix) or opto first (fix and verify)?
3. After opto swap, should luminance fetch interval be made time-based
   (30s) and decoupled from photo count?
4. Do we want a "stage 4" milestone covering hardware reliability fix,
   time-based fetch interval, and production-envelope soak test?
