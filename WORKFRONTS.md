# HyperLapse Cart — Open Workfronts

**As of:** end of Session C day 9, 15 May 2026

This file lists work surfaced but not yet executed. Each item references
which session/day raised it. Prioritise per shoot calendar.

Day 9 update:
- Workfront #5 (Plan endpoints) **DONE** — `/plan/load`, `/plan/start`,
  `/plan/stop`, `/plan/status` all working with CSV query format.
  Compile fix: PlanSegment struct moved to top of sketch.
- First end-to-end Plan execution test ran successfully.
- Servo-to-wheel calibration first estimate: **SERVO_TO_DEG ≈ 0.35**
  (servo +30° offset → ~10.6° wheel angle). Single quarter-turn test;
  needs full circle, symmetry, linearity validation.
- New issue: front_steps == rear_steps in every log row on the turn.
  Expected geometric divergence on arc. Listed below.
- New issue: UI polling saturates WiFi request queue. Listed below.

Day 8 update:
- Gimbal/cart-firmware section simplified significantly thanks to Excel
  pre-baking everything. See GIMBAL_VIZ.md for the design.
- Workfront #4 (rear_steps in CartLogEntry) **DONE** + front_steps added.
- Workfront #17 (straight-line calibration) **DONE** — m_per_step ≈ 1.77 µm/step
  speed-independent across 10× speed range. See PROJECT_STATE.md.
- New debug endpoints added: /debug/overdrive, /debug/tic, /debug/looplong, /debug/can
- CAN TX issue surfaced (gimbal wires OK per operator but errors climbing fast). New item below.
- **WiFi/RF link design session (afternoon).** New section added below.
  Wavlinks received, antennas confirmed non-detachable. Architectural
  decisions: wired backhaul + Giga R1 cart-side + AR3277 cart antenna.
  Shopping list: Jaycar AR3277, Phipps u.FL→RP-SMA pigtail ×2.

---

## Hardware (from day 6 — waiting on parts)

1. **Replace optocoupler + resistor.**
   Jaycar ZD1928 4N25/4N28 (×2 for spare) + 220Ω resistor pack.
   Stay in 4N25 family. ~$5 total. ON ORDER.

2. **Buy USB logic analyser.**
   SparkFun TOL-18627 from Core Electronics, 24MHz / 8-channel, ~$30.
   Open-source PulseView/sigrok. Measure both sides of opto
   simultaneously BEFORE swapping, to confirm diagnosis. ON ORDER.

3. **After opto swap:** re-run Tv=0.8"+2s test, target 100% delivery.

## WiFi / RF link (NEW day 8)

Architectural context: CCAPI fetches over WiFi are the only source of
photo drops in production. Field shoots place the cart 60-100m from
the van with a ~20m operating arc. WiFi reliability at that range
directly impacts pin-8 cadence stability.

### Hardware on hand
- 2× Wavlink WL-WN536AX6 AX6000 dual-band routers received. One for
  van, one for field deployment (battery-operable, mid-position).
- **Antennas are NOT detachable** — confirmed visually: plastic
  rotating hinge with coax feedline running up through the hinge,
  no RP-SMA connector. AP-side antenna upgrades not possible without
  replacing the AP.
- 1× Arduino Giga R1 WiFi available. Includes u.FL flex antenna in
  the box. Far better RF setup than Uno R4 (no onboard antenna, real
  external connector vs ESP32-S3 chip antenna).
- 60m Cat6 available for wired backhaul if needed.

### Van AP setup (DONE day 8)
- Van AX6000 configured. Admin UI at http://192.168.20.1 (default
  pwd `admin`, set new on first login).
- **WAN = USB Tethering to iPhone.** Working topology:
  iPhone(tether) → USB → AX6000 → WiFi → clients (laptop, iPhone #2).
- **USB tethering quirks observed:**
  - Despite Wavlink docs page for router-mode WAN listing only
    DHCP/PPPoE/Static, USB Tethering DOES appear as a 4th option
    in the actual UI for this model. Docs out of date.
  - iPhone-side state is fragile: Trust prompt appears
    inconsistently. Some iPhones connect first try, others sit at
    "trusted but no data". Recovery: try the other iPhone, or
    fully cycle Personal Hotspot off→on while plugged in.
  - "1 Connection" indicator on iPhone Personal Hotspot screen is
    the canonical test for whether tether is actually active.
    Trust+plugged ≠ tethered. Watch this counter.
  - Cable must be a data cable; charge-only cables draw power but
    don't expose USB data lines. Test by plugging to a laptop —
    Trust prompt + photos prompt = data cable confirmed.
- **Recommended: back up working config** via More → Backup and
  Restore → Backup. Recovering the trust dance from scratch is
  painful; the file restores the WAN config in one click. NOT YET
  CONFIRMED DONE.

### Architectural decision (day 8, by principle, not yet tested)
- **Field-AP backhaul: WIRED.** Mesh backhaul on dual-band AP shares
  airtime between backhaul and clients on same radio. At 50-100m
  backhaul MCS will degrade, inflating fetch latency variance. Same
  class of problem REQ-PHASES was chasing. Wired backhaul = full
  5 GHz radio dedicated to cart.
- **Cart-side board: GIGA R1.** Stronger radio (Murata 1DX / Cypress
  CYW4343W vs ESP32-S3-MINI), external antenna out of the box, u.FL
  for swapping in better antennas. Trade-off: WiFi library port from
  WiFiS3 (mbed-based) — non-trivial.
- **Single-AP option (van only) rejected.** Phone signal meter shows
  700 Mbps → 20 Mbps drop at 100m. Cart chip antenna would be worse.
  Bandwidth fine for JSON; latency variance is the killer.

### Open work
22. **Port cart firmware from Uno R4 to Giga R1.** WiFi layer is the
    main change (WiFiS3 → mbed WiFi). Pin-8, CCAPI, exposure, plan
    endpoints, CAN — all need verification on new board. Scope this
    carefully before committing.

23. **Cart antenna upgrade.**
    - Jaycar AR3277 — 11dBi 2.4GHz dipole RP-SMA, 1.5m lead,
      magnetic base. $49.95.
    - Phipps Electronics u.FL to RP-SMA female pigtail ×2
      (one spare; u.FL is fragile, rated ~30 mating cycles).
    - Connects Giga J14 → pigtail → AR3277.
    - Note: AR3277 is 2.4GHz only. Giga's WiFi is 2.4GHz-only anyway
      (802.11b/g/n, 65 Mbps max) so dual-band antenna unnecessary.

24. **Cart antenna placement.** Current Uno R4 sits in same plane as
    Ronin base (150mm off ground) and steppers (200mm). Bad RF
    neighbours — steppers absorb and radiate noise, Ronin base
    reshapes pattern. Plan: short non-metallic mast (300-500mm),
    fibreglass / PVC / tent pole. Position becomes a test variable.
    Log WiFi.RSSI() alongside fetch timing for each position tested.

25. **Wired backhaul setup.** Lay 60m Cat6 van AP → field AP. Confirm
    Wavlink firmware allows wired backhaul in mesh mode (some
    treat wired vs wireless backhaul as config-time, not runtime).
    Decision: probably configure field AP as plain AP (not mesh node)
    with wired uplink. Simpler than fighting mesh firmware.

26. **WiFi diagnostic instrumentation (oscilloscope philosophy).**
    Per-fetch logging from cart:
    - RSSI before fetch
    - Time to connect (if reconnect needed)
    - REQ-PHASES timing (already exists)
    - Disassociation events
    Feeds the test plan below.

### Test plan (deferred — depends on hardware arriving)
- Variable 1: cart antenna position (current plane / +150mm mast / +300mm mast)
- Variable 2: AP backhaul (mesh / wired)
- Variable 3: cart-to-AP distance (10m / 50m / 100m)
- Fixed: same AP location, same Tv setting, same fetch cadence
- Measure: fetch latency mean + variance, RSSI, photo delivery %

### Worst-case escalations (don't buy yet)
- Replacement field AP with detachable antennas (e.g. Wavlink AERIAL
  HD6 outdoor with RP-SMA, or similar). Only if cart-side upgrade
  + wired backhaul insufficient.
- Outdoor PtP bridge (Ubiquiti NanoStation or similar) for van↔field
  link, treating Wavlink AP purely as cart-side serving.

### Rejected during day 8 design
- ~~Single AP only (van)~~ — 100m too far for cart chip antenna
- ~~AP-side directional (Alfa APA-M25)~~ — Wavlink antennas not
  detachable
- ~~Modify Uno R4 ESP32-S3-MINI-1 → MINI-1U for u.FL~~ — SMD rework
  fiddly; Giga is the better lever
- ~~Mesh backhaul as primary~~ — principle rejects shared-airtime
  backhaul for latency-sensitive workload

## Cart firmware

~~4. Add `rear_steps` field to `CartLogEntry`.~~ **DONE day 8.** Plus
    `front_steps` added for front-vs-rear diagnostic. CART_LOG_MAX
    reverted to 64 (RAM overflow at 128). Grow later if needed using
    a different strategy (SD card, streaming, or move to Giga).

5. **Add Plan endpoints:** `/plan/load` (POST a stream of segments),
   `/plan/start`, `/plan/stop`, `/plan/status`. Implement clock-driven
   segment dispatcher in main loop.
   **DONE day 9.** Implemented as GET with CSV query string
   (`?n=N&s1=TYPE,VAL,STEER,SPEED,END&s2=...`). Compile fix needed:
   PlanSegment struct moved to top of sketch (before forward
   declarations the Arduino preprocessor generates). Tested
   end-to-end with 4-segment plan (straight + hold + servo ramp +
   90° turn). Operator-stop via `/btn12` (dead stop). All segment
   transitions logged with rear_steps / front_steps for Excel
   bicycle model analysis.

5a. **Segment dispatcher + cubic evaluator (NEW day 8).** ~50 lines C.
    Segment types: HOLD, LINEAR, CUBIC (Catmull-Rom as standard
    cubic coefficients), PANFOLLOW. Per tick: eval at (now - t_start),
    quantise to 0.1°, accumulator-driven setPosControl.

9. **Replace ±180° yaw constants with ±450° cumulative** throughout
   sketch and Gimbal.bas. Track unwrapped cumulative yaw.

### REMOVED (day 8 — Excel pre-bakes everything)

- ~~#6 Heading anchor endpoint at runtime~~
- ~~#7 Cart-θ integration during drives~~
- ~~#8 Port astro maths to C~~
- ~~#10 setSpeedControl wiring~~

## Cart UI (new — from day 8)

10a. **Gimbal UI page on cart web server.** Separate URL (suggestion
     `/gimbal`), parallel to existing `/` cart UI. Field-side Plan-row
     editor. See GIMBAL_VIZ.md §3 for layout.
     Per-row inputs: Way# dropdown (1..N from cart log), Type dropdown
     (pan-follow / hold / track sun / track milky / manual), Duration
     in seconds, two reserved fields, capture button (active only when
     type=manual). Plus yaw/pitch nudge controls for pointing the
     gimbal when authoring manual rows.

## CAN bus investigation (PARKED day 8)

10b. **CAN "TX errors" climbing — RESOLVED as misnomer.** During cart
     calibration, [CAN] TX errors counter incrementing ~6/sec with
     LOOP-LONG firing at ~120ms intervals. Investigated and found:
     - Termination correct: WCMCU breakout has 120Ω + Ronin has 140Ω
       → parallel ~64Ω (within CAN spec)
     - VCC = 3.3V steady, not 5V
     - 1 Mbps baud rate confirmed (standard for DJI R SDK)
     - **`/home` command worked correctly** while errors were climbing
     - Conclusion: counter was actually mailbox-full count, not failed
       transmissions. Frames were getting through; counter only tracked
       moments when CAN.write returned ≤0 because all 3 TX mailboxes
       were still holding pre-ACK frames.
     - **Renamed `txErrCount` → `mailboxBusyCount`** throughout firmware
       (variable, serial log, /status, UI). Day-8.
     - UI now shows green "CAN: OK" steady state; amber "busy (N)" only
       above 20 sustained.
     - Spare WCMCU board on hand if a genuine fault emerges later.

     **Not closed entirely:** transceiver does warm up under heavy
     polling traffic (`getPosData` every REQUEST_INTERVAL_MS plus
     keep-alive every 30s). Currently cosmetic — but if poll cadence
     increases in future (e.g. Plan execution dispatching gimbal
     commands every 2s), worth re-examining whether the 3-mailbox
     queue + delay(2) yield approach scales. Not blocking work.

## Excel (from day 7, expanded day 8)

~~11. Bicycle integration: Log → (x, y, θ) trace.~~ **DONE day 8.**
    `BicycleModel.bas` module created with `IntegrateBicycle` sub.
    Reads 6-column CartLog, applies rear-axle Ackermann maths
    (straight + arc segments), writes Trace sheet, renders XY chart
    on CartLog. Subdivides arcs into 0.1m sub-steps for smooth chart.
    Verified via `SimulateCartLog` synthetic test (5m straight +
    R=2m quarter-circle → end (7, 2) heading +90°). Real-world
    Cart Logs await tomorrow's SERVO_TO_DEG calibration.

11a. **Control-sheet handler row for IntegrateBicycle (NEW day 8).**
     The `Worksheet_BeforeDoubleClick` handler in the Control sheet's
     code module needs a row added for `btnIntegrateBicycle`. Done
     manually in-session day 8 but not captured in any .bas (handler
     lives in sheet code, not module). Worth adding to the README
     workflow note so it isn't lost on workbook rebuild.

12. **Inverse fitting: trace → smooth Plan.** Operator selects wobbly
    sections; Excel proposes single-arc replacements (chord +
    heading-change → radius → steering angle → arc length).

13. **New Plan sheet schema** — interleaves cart movement/stop rows
    with gimbal pan-follow/astro-target/manual-waypoint rows.
    Single shared timeline. Push to cart via `/plan/load`.

14. **Catmull-Rom evaluator (Excel-side, full evaluation now — NOT
    preview-only).** Excel evaluates the spline densely, packs cubic
    coefficients per segment, and POSTs those to cart. Cart no longer
    needs spline math. See GIMBAL_VIZ.md §8.

14a. **Astro endpoint computation (NEW day 8).** For each "track sun /
     moon / milky" Plan row, evaluate astro formulas (existing
     Astro.bas) at row_start_time and row_end_time. These computed
     (yaw, pitch) become spline waypoints alongside operator-placed
     manual waypoints.

14b. **Spline waypoint sequence assembly (NEW day 8).** Build the
     ordered list of waypoints for Catmull-Rom from:
     - Operator-placed manual waypoints
     - Computed astro track endpoints
     - Hold positions (repeated waypoints for stationary segments)
     - Phantom waypoints for explicit transition rows
     (operator-authored ease-in/ease-out, see GIMBAL_VIZ.md §8)

14c. **Cubic-coefficient packing (NEW day 8).** Each spline segment
     becomes a parameter block for cart: `(type, t_start_ms, t_end_ms,
     coefficients...)`. Compact binary or JSON for /plan/load POST.

15. **Gimbal Plan XY chart with velocity bands (UPDATED day 8):**
    yaw cumulative (X, −380° to +70° span) × pitch (Y, 0°-90°,
    dashed line at 80°). Catmull-Rom spline drawn through waypoints.
    Colour bands:
    - Blue = ease-in/ease-out transition row
    - Green < 0.05°/sec (astro, slow drift)
    - Amber 0.05–0.3°/sec (deliberate manual pan)
    - Red > 0.3°/sec (aggressive pan)
    Plus execution-feasibility warning (red border / text) when
    utilisation = (steps × 100ms) / gap_ms exceeds 0.5.
    See GIMBAL_VIZ.md §7.

15a. **Audience-frame display for ease durations (NEW day 8).**
     When operator sets an ease duration, Excel shows the
     audience-frame count at 60fps × 1320× speedup. "Ease 60s =
     2.7 frames, abrupt halt" or "Ease 5min = 13.6 frames,
     comfortable". See GIMBAL_VIZ.md §8.

16. **Time-based luminance fetch** (from day 6, deferred).
    Replace "every 3 photos" with `LUM_FETCH_INTERVAL_MS = 30000`,
    decoupled from photo count.

## Calibration tests (from day 7, day 8 progress)

~~17. Straight-line test at 5 m/hr~~ **DONE day 8.** Tested at 10/50/100 m/hr
    (not 5; tested across wider speed range). m_per_step = 1.77 µm/step,
    speed-independent across 10× range. Theoretical 1.97 µm/step;
    measured 10% lower attributed to tyre deflection + real diff ratio
    + possible constant slip. Distinguishing factor: circle test (#20).

18. **Straight-line test at constant slow speed (e.g. 2-3 m/hr).**
    Verifies behaviour at slowest operating speed (production exec is
    5 m/hr). Optional — already speed-independent across 10× range.

19. **Acceleration overhead test:** time a longish 5 m/hr run from
    operator-start to operator-stop; compare clock time to
    (distance ÷ 5 m/hr × 3600). Difference = ramp overhead.

20. **Circle test:** set servo to known angle, drive a full circle,
    measure diameter. Derive servo-to-wheel-angle calibration.
    **Day-8 addition:** also analyse front vs rear step counts.
    Front (outer arc) should advance more than rear (inner arc) by
    a geometrically predictable ratio. Divergence from prediction
    will tell us about real slip vs tyre deflection vs diff ratio
    error — issues we couldn't distinguish in straight-line testing.

21. **S-bend test:** only if straight + circle don't match bicycle
    model within ~2-3%.

## Cart firmware / WiFi (NEW day 9)

27. **WiFi unresponsiveness under UI polling — RESOLVED via avoidance
    (day 9 evening).** Web UI on phone/browser was polling `/status`
    and `/cameramsg` every ~1 second. After ~15 min of execution +
    polling, Uno R4 WiFi request queue saturated; cart unreachable;
    power cycle required.

    **Investigation (day 9 evening, REQ timing instrumentation):**
    - WiFiS3 fixed cost per request: ~60ms accept + ~50ms send = ~110ms
    - `/favicon.ico` was falling through to UI HTML catch-all (1.3s
      per browser visit)
    - At 1Hz polling: 11% CPU on WiFi sustained; socket churn likely
      cause of eventual saturation

    **Avoidance applied:**
    - Added `/favicon.ico` → 204 No Content handler (1301ms → 89ms)
    - UI polling 1s → 3s, cameramsg 5s → 10s
    - JS `pollPaused` pauses polling 5s after every button press

    **Result:** 5-min sustained polling test — flat 109-112ms per
    request, no drift, no saturation. CPU load ~5%.

    **Status:** Resolved for current operator workflow. NOT closed —
    if production shoots (longer / heavier UI use) re-expose
    saturation, return to deeper fix:
    - Rate-limit polling server-side
    - Investigate WiFiS3 accept/close cycle, TCP backlog queue
    - Migrate to Giga R1 (workfront #22)

28. **Front step counting on arcs — diagnostic.** Day-9 morning turn
    test log showed `front_steps == rear_steps` exactly. Day-9
    afternoon recon test showed **front and rear differ by a small
    constant offset (~3000 steps) that does NOT grow with distance**,
    even on the arc segments. Either:
    - The differential really does equalise both wheels (would
      change architecture — front_steps then redundant for cart
      position model).
    - Front Tic counts a different mechanical thing than expected.
    - Real arc geometry produces a small fraction of expected divergence.
    Day-9 afternoon: both Tics confirmed alive in /debug/tic
    (step_mode=4 on both, both responding). The "front == rear"
    pattern is real, not a comms fault. Investigate before circle
    test (#20) to know what the test should measure.

## Calibration tests — day 9 progress

29. **Refine servo-to-wheel calibration.** Day-9 quarter-turn at
    +30° servo gave first estimate SERVO_TO_DEG ≈ 0.35 (i.e. servo
    +30° produces ~10.6° actual wheel angle). Single test, ±100mm
    position measurement, servo ramped during start of turn.
    Need: full 360° circle test, ±15° linearity check, ±30° symmetry
    check (left turn). Then commit constant to BicycleModel.bas.

30. **Cart log buffer too small for production recon.** Day-9 Test 3
    measured 31 events / 2.5 min recon-style driving. Production
    recon ~60 min → ~750 events needed; CART_LOG_MAX=64 covers ~5 min.
    Options (none chosen — parked):
    - Bump to 96 or 128 (128 caused stack/heap overlap day-8)
    - Drop front_steps (saves 4 bytes/entry → ~80 entries; loses
      diagnostic — but if #28 confirms front==rear, drop becomes free)
    - Stream log to Excel mid-run (new endpoint, polling overhead)
    - Compact format (marginal)
    - Migrate to Giga R1 (#22 — best answer, biggest commit)
    Solve alongside #27 (UI polling fault) — both are Uno R4
    capacity limits.

31. **Plan nudge endpoint and UI — design ready, not built.**
    Day-9 design discussion:
    - `/plan/nudge?mm=N` modifies `plan_segments[plan_current].dist_mm`
      by signed N. Past-zero = immediate segment complete.
    - Adjust counter resets at segment entry.
    - MOVE segments only — no nudge on STOP (operator can't judge
      hold-duration changes by eye).
    - UI shows: current segment, remaining distance (100mm
      resolution), cumulative adjustment, [+100mm] and [-100mm]
      buttons, plus DEAD STOP.
    - Updates pushed per 100mm of progress (event-driven, not polled
      — solves WiFi load by design).
    - Two distinct cart UI screens: Logging UI (recon) vs
      Execution UI (shoot mode). Different layouts, different
      update rhythms.

32. **'t' event integration into BicycleModel.bas.** Day-9 firmware
    change logs 't' (servo ramp complete) alongside 'T' (target set).
    Excel integrator currently treats 'T' as instantaneous steering
    change. Update needed:
    - Read 'T' as start-of-ramp (steering still at previous value)
    - Read 't' as end-of-ramp (steering now at target)
    - Interpolate steering linearly across the ramp window
    - Each 1°-step slice is a separate mini-arc for the integrator
    Without this update, viewer trace will look stepped, predictor
    arcs will inherit small but systematic error from ignored ramps.

## Gimbal Plan additions (NEW day 9 evening)

33. **Panorama row type — Plan and Execution.** Day-9 evening design.
    Pano allowed only when cart stopped (HOLD or astro-track segment).
    Geometry: ±120° from current yaw, 50% overlap on 14mm (104° FOV),
    N=4 photos at centres −78°, −26°, +26°, +78°. Worst-case duration
    ~90s at Tv=20s. No catch-up special-case — existing where-am-I
    slew handles resume.
    Excel work:
    - Pano Plan row type (renders as a marker / shaded zone in chart)
    - Master parameters: PANO_OVERLAP_PERCENT=50, PANO_RANGE_DEG=120,
      PANO_N_PHOTOS=4, GIMBAL_SETTLE_MS=1000
    - Sub-segment generation from pano row → (slew, settle, photo)
      sequence
    Cart-gimbal firmware work:
    - Gimbal-side handler for "pano now" command (planned or operator
      triggered)
    - Slew-settle-photo cycle implementation
    - Coordination with shutter (pin-8) to fire at each photo position

34. **Gimbal settle time measurement.** Pano design assumes 1s settle
    time after each slew (4 settles per pano + 2 boundary slews).
    Affects pano duration calc and possibly photo blur. Worth a one-off
    bench test with the actual cart + Ronin + camera + lens setup:
    slew, photo, repeat with various settle times (0.3s, 0.5s, 1.0s,
    1.5s), inspect for motion blur. Find minimum reliable settle.

35. **Operator "PANO NOW" trigger during execute.** Unplanned pano
    capability. UI button on Execution UI that sends pano command;
    cart inserts pano at current Plan position; existing slew-back
    handles resume. Defer until Execution UI design pass.

## Open design decisions

- "Stage 4" milestone definition: bundle hardware opto fix +
  time-based fetch + production-envelope soak test?
- Sunrise transition table (only sunset table reviewed to date).
- Moon tracking in scope or out of scope for the gimbal Plan?
- Logic-analyser-first vs opto-first ordering?
- Two reserved per-row inputs in Gimbal UI — TBD.
- Velocity-band thresholds (0.05 / 0.3°/s) — confirm in practice;
  adjustable if first shoots suggest otherwise.
- Stream size for /plan/load — JSON or binary? Uno R4 SRAM tight
  after recent additions; consider chunked POST.
- m_per_step canonical value: 1.77 µm/step or wait for circle-test
  cross-validation before committing?
- Front_steps logging: keep on by default, or only enable for
  calibration runs (small SRAM cost)?
