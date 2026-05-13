# HyperLapse Cart — Open Workfronts

**As of:** end of Session C day 7, 13 May 2026

This file lists work surfaced but not yet executed. Each item references
which session/day raised it. Prioritise per shoot calendar.

---

## Hardware (from day 6)

1. **Replace optocoupler + resistor.**
   Jaycar ZD1928 4N25/4N28 (×2 for spare) + 220Ω resistor pack.
   Stay in 4N25 family. ~$5 total.

2. **Buy USB logic analyser.**
   SparkFun TOL-18627 from Core Electronics, 24MHz / 8-channel, ~$30.
   Open-source PulseView/sigrok. Measure both sides of opto
   simultaneously BEFORE swapping, to confirm diagnosis.

3. **After opto swap:** re-run Tv=0.8"+2s test, target 100% delivery.

## Cart firmware (from day 7)

4. **Add `rear_steps` field to `CartLogEntry`.**
   Read `ticRear.getCurrentPosition()` inside `cartLogEvent()`.
   Grow `CART_LOG_MAX` to ~128 for headroom.

5. **Add Plan endpoints:** `/plan/load` (POST a 5-10 row plan),
   `/plan/start`, `/plan/stop`, `/plan/status`. Implement row-walker
   in main loop.

6. **Heading anchor:** new endpoint `/heading/anchor?deg=N` for operator
   iPhone-compass entry at each stop. Cart stores; astro tracking uses it.

7. **Integrate cart heading θ during drives.** Bicycle model live on
   cart, just for displaying predicted heading at next stop (validated
   by operator). Independent of position model that's Excel-side.

8. **Port astro maths from Astro.bas to C.** ~100-150 lines.
   `getSunPosition`, `getGCPosition`, `radecToAltAz`, `dateToJulian`.
   Constants: GC_RA_DEG = 266.4167, GC_DEC_DEG = -29.0078.
   Config endpoint `/astro/config?lat=&lng=&utc=` at shoot start.

9. **Replace ±180° yaw constants with ±450° cumulative** throughout
   sketch and Gimbal.bas. Track unwrapped cumulative yaw.

10. **Wire up `setSpeedControl` for slow continuous moves.**
    Currently unused — only `setPosControl` is called via `/move`.
    New endpoint `/gimbal/speed?yaw=&pitch=` for live tracking.

## Excel (from day 7)

11. **Bicycle integration: Log → (x, y, θ) trace.** Read CartLog CSV,
    apply m_per_step + overdrive correction + servo-to-degree
    calibration, integrate per-segment using rear-axle bicycle equations.

12. **Inverse fitting: trace → smooth Plan.** Operator selects wobbly
    sections; Excel proposes single-arc replacements (chord +
    heading-change → radius → steering angle → arc length).

13. **New Plan sheet schema** — interleaves cart movement/stop rows
    with gimbal pan-follow/astro-target/manual-waypoint rows.
    Push to cart via `/plan/load`.

14. **Catmull-Rom evaluator** for gimbal waypoint smoothing.
    Excel-side preview only; real evaluation happens on cart at
    execution. (Cart needs the spline math too, ~30 lines C.)

15. **Gimbal Plan XY chart:** yaw cumulative (X, −380° to +70° span)
    × pitch (Y, 0°-90°, dashed line at 80°). Operator sees the night's
    gimbal trajectory at a glance.

16. **Time-based luminance fetch** (from day 6, deferred).
    Replace "every 3 photos" with `LUM_FETCH_INTERVAL_MS = 30000`,
    decoupled from photo count.

## Calibration tests (from day 7)

17. **Straight-line test at 5 m/hr:** drive measured ~1m, count rear
    TIC steps. Derive m_per_step. Verify overdrive correction.

18. **Straight-line test at 100 m/hr:** same, verifies m_per_step is
    speed-independent and overdrive=1.00 holds.

19. **Acceleration overhead test:** time a longish 5 m/hr run from
    operator-start to operator-stop; compare clock time to
    (distance ÷ 5 m/hr × 3600). Difference = ramp overhead.

20. **Circle test:** set servo to known angle, drive a full circle,
    measure diameter. Derive servo-to-wheel-angle calibration.

21. **S-bend test:** only if straight + circle don't match bicycle
    model within ~2-3%.

## Open questions / decisions deferred

- "Stage 4" milestone definition: bundle hardware opto fix +
  time-based fetch + production-envelope soak test?
- Sunrise transition table (only sunset table reviewed to date).
- Moon tracking in scope or out of scope for the gimbal Plan?
- Logic-analyser-first vs opto-first ordering?
