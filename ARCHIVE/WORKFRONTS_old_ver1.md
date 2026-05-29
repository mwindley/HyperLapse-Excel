# HyperLapse Cart — Open Workfronts

**As of:** Session C day 13, 21 May 2026

This file lists work surfaced but not yet executed. Each item references
which session/day raised it. Prioritise per shoot calendar.

Day 13 update (added 21 May 2026):
- **#40 BNO085 integration architecture resolved across all six
  questions.** Pure design session, no code. See PROJECT_STATE
  day-13 entry for full design; summary below.
- **Anchor mechanism:** running scalar `gimbal_yaw_correction`
  applied additively to earth-frame-tagged gimbal cubics only.
  Pan-follow untouched. Cart drives its planned path blind — no
  cart position/heading correction. Plan stream gains per-row
  anchor flag + threshold + expected_cart_heading, and per-segment
  earth-frame vs chassis-frame tag.
- **Offset persistence (Q2):** Excel-pushed via Settings, NOT
  EEPROM. Fits the existing Appendix A / yaw envelope push
  pattern. Adelaide declination web-verified at +8.11°; bench
  offset +9.16° implies ~+1° BNO mount angle on bench, within
  ±3° BNO noise.
- **Acc dropout (Q3):** two-attempt retry per anchor row (500mm
  then 400mm before waypoint). If both fail, keep previous
  correction. Photos sacred throughout.
- **Cart→Excel feedback (Q5):** new CartLog event type `A` with
  subtypes A_OK / A_SKIP / A_FAIL. Pulled via existing /cartlog.
  Excel parser splits Type=A rows into a dedicated AnchorLog sheet
  on import.
- **Held over for build session:** stream format detail for the
  anchor flag/threshold/expected_heading fields; frame-tag bit
  position in Segment struct; ring buffer size + averaging window;
  whether A events overload columns or add a status column.

Day 12 update (added 21 May 2026):
- **Photo-drop root cause identified: 100ms shutter pulse width.**
  Day-11's "CCAPI stress" framing was wrong. The Canon R3 needs
  the shutter line held LOW for ~200ms to register reliably; 100ms
  sat at the edge of its debounce, and any camera slowdown (CCAPI
  or otherwise) tipped a fraction past it into drops. Built
  `DropTest.ino` as a minimal fork of production; 7 runs spanning
  zero-CCAPI to full Day-11 stress condition proved pulse width is
  the cause and CCAPI / opto are innocent.
- **Production fix applied + validated end-to-end.** `backupShutter()`
  micros window `100000` → `200000` in `DJI_Ronin_UnoR4_v3.ino`.
  Flashed to cart and ran the Day-11 stress condition: Tv=0.5",
  interval=2000ms, mode=darken, luminance fetch every 3rd photo,
  live view active. **38 fires, 38 photos on card. 100% delivery.**
  Same CCAPI load as Day-11 Run #1 (which delivered 70.4%).
  `fetch attempts/successes/errors=12/12/0`. PULSE log shows full
  200ms hold (`high=56820/56820`, `fire_us=203765`).
- **Hardware cluster (#1, #3) resolved without opto swap.** The
  opto path is innocent — Day-12 Run #4 (intervalometer 200ms
  through same opto) hit 100%. See updated Hardware section below.
- **Day-11 "Open question — recovery gap edge" superseded.** No edge
  exists in the 2s zone; the apparent edge was the pulse-width
  artefact. The Tv + 1.5s cadence rule still stands as a sensible
  minimum interval.
- **Resilience verified under stress.** Day-12 Run #7 included a
  real CCAPI fetch timeout mid-run; backoff applied for 2 cycles,
  recovery automatic, all 37 photos still landed. Architectural
  principle "photos sacred, never delayed" held under real stress.
- **Open design decisions closed:** "Stage 4 milestone — bundle
  hardware opto fix" reduces to a single item: production-envelope
  soak (multi-hour sunset+sunrise) to confirm the 200ms fix holds.
  "Logic-analyser-first vs opto-first ordering" answered:
  analyser-first revealed the real cause.
- **New PREFERENCES principle:** *When chasing software, compare
  against a known-good reference first.* A working intervalometer
  is the 100%-delivery reference. Measuring it alongside the
  Uno+opto trace on the same analyser would have surfaced the
  pulse-width gap on Day 11 if we had done it then.
- **New PREFERENCES build lesson:** USB cable quality can manifest
  as WiFi / HTTP latency on the Uno R4. Swap the cable before
  chasing sketch bugs.
- **DropTest.ino retained as parked diagnostic asset.** Analyser
  marker pins (D2-D5 for call-type codes), `/echo` endpoint, and
  `/debug/liveview_at_start` flag are useful for any future
  stress investigation. The 200ms pulse has been ported back to
  production already; no other changes need porting at this time.

Day 10 update (added 18 May 2026):
- **#44 Smooth Selection cluster REJECTED after build + test.**
  Built end-to-end (Smooth.bas, CartLog buttons, two-stage commit
  with chart overlay) and proved it works mathematically. Rejected
  because **smoothing rows i..j shifts the endpoint (x, y) of row j
  slightly, so all downstream rows integrate from that new endpoint
  and the entire trace shifts**. Operator's mental model "what I
  selected is what I changed" breaks; knock-on chain leads to
  chasing drift across the rest of the plan. <> simple.
  Geometric reason: single arc has 1 free parameter (R); matching
  end pose (Δx, Δy, Δθ) needs 3. Multi-arc or arc+straight fits
  work mathematically but explode cart-side and operator-facing
  complexity. **No execution benefit**: cart drives by
  distance+steering per segment; small wobbles invisible in 5 m/hr
  capture.
- **CartLog is the Plan.** The recon CartLog drives directly to
  `/plan/load` for execution. Wobbles preserved (faithful at 5 m/hr,
  invisible in photos). What operator edits is **S-event speed
  values** (5 m/hr photographable, 10 m/hr transitions, etc.) —
  in-place cell edits, no maths.
- **Chart's high-value job is gimbal integration.** Row-number
  labels at each T/X event (built day 10 in BicycleModel.bas) let
  operator reference cart waypoints when authoring gimbal plan rows.
- **#45 Speed editing in CartLog (NEW)** — operator edits S-row
  Value column to set per-segment execution speeds. Verify
  `/plan/load` accepts the resulting payload; may need per-segment
  speed override schema.
- **#46 Gimbal authoring against cart row labels (NEW)** — re-frame
  of the earlier #13 design. GimbalPlan rows reference CartLog row
  labels directly (W_start = CartLog row, W_end = CartLog row), no
  separate CartPlan sheet.
- **#43 Start New Log button** — promoted in importance. With no
  Smooth, the correction mechanism for bad recon is redrive.
- **Built and kept day 10:**
  - `WobblyRecon.bas` (`SimulateWobblyRecon`) — synthetic 16-row
    test fixture
  - `BicycleModel.bas` extension — Trace col H `CartLogRow`; chart
    shows row-number labels at T/X events via Excel linked data
    labels (`InsertChartField msoChartFieldRange`)
  - `SecToHms` made `Public`
- **Built and to-be-removed day 10:**
  - `Smooth.bas` module
  - CartLog `Worksheet_SelectionChange` + `_BeforeDoubleClick`
    handlers (or leave; harmless without buttons)
  - CartLog buttons G1:I1, named ranges, hidden cols Q:T
- **PREFERENCES candidate principle:** *Visualisation > Manipulation*.
  Clear visualisation of what the operator did is more valuable than
  a tool to mathematically clean it up. Operator's eye + redrive is
  simpler than algorithmic smoothing.

Day 9 late evening update (added 15 May 2026):
- **Exposure cluster restructured around three-session model.**
  Shoot session = pick branch + push + execute. Post-timelapse
  session = extract + tag + save CSV (always). Refit session =
  optional cold-winter-night divergence check; expected normal
  outcome is no refit. Branching is operator opt-in; default
  branch always exists. CSVs are the storage shape, not Aggregate
  sheet. See EXPOSURE_FALLBACK.md for full architecture.
- **Simple formula built and verified (#36 + #36a DONE).** Excel
  side ready. FallbackFormula sheet has sunset + sunrise blocks
  from Appendix A. UDFs `FormulaTv(t_rel, branch, sunEvent)` and
  `FormulaISO(t_rel, branch, sunEvent)`. Live evaluator on sheet.
  Push to cart verified end-to-end (HTTP 0 with cart off, as
  expected). Cart firmware #36b will receive payload when built.
- **exif_ingest.py and validate_exposure.py both DONE.** Tested on
  6,176-image Jan 22-23 2026 shoot. BrightnessValue confirmed
  absent on R3 — closed in EXPOSURE_FALLBACK.md §6.5.
- **Jan 22-23 2026 shoot reviewed.** Table-driven (not CCAPI),
  therefore NOT refinement input. Used as worked example of
  shoot-type discipline + manual-time-nudge recurrence.
- **Architectural principle #14 added to PREFERENCES**: Uno R4 is
  current; Giga R1 is held in reserve. Don't migrate proactively;
  migrate when a specific workfront demonstrates Uno is the
  blocker. WORKFRONT #22 (Giga port) marked HELD IN RESERVE.
- **New cluster: Cart Plan smoothing (#43 + #44 cluster).**
  Recon drives at 100 m/hr (survey); execution at 5 m/hr (shoot).
  Operator may catastrophically fail a turn (new "Start New Log"
  cart button to wipe and redo) or drive a wobbly turn that should
  have been one arc (new Excel "Smooth Selection" button proposes
  a single arc + deviation warning + chart overlay). Architectural
  decision: "a straight line is a series of curves" — no special
  case for straight, everything is an arc.

Day 9 evening update (added 15 May 2026):
- New section **"Exposure fallback + validation (#36-39)"** added below,
  absorbing CCAPI_FALLBACK design doc and WORKFRONT_36 validation draft.
  Full design lives in `EXPOSURE_FALLBACK.md` (single canonical source).
- New section **"Heading + gimbal stream (#40-42)"** added below,
  absorbing WORKFRONT_COMPASS_ANCHOR and WORKFRONT_GIMBAL_RATE drafts.
- Original draft files `WORKFRONT_36.md`, `WORKFRONT_COMPASS_ANCHOR.md`,
  `WORKFRONT_GIMBAL_RATE.md`, `CCAPI_FALLBACK.md`, `OLD_SUN_TABLE.md`
  retired — content merged into `EXPOSURE_FALLBACK.md` + this file.

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

## Hardware (from day 6 — RESOLVED Day 12 via pulse-width fix)

**Status:** the chronic photo-drop problem this cluster was opened to
fix turned out NOT to be opto-related. Day 12 identified the 100ms
shutter pulse width as the cause; 200ms restored delivery to 96-100%
on the bench (7 runs) and 100% in production (Day-12 end-to-end
test: 38/38 at Tv=0.5"/2s + luminance every 3rd). The opto path is
innocent — Day-12 Run #4 (intervalometer 200ms through the same
opto) hit 100%. The logic analyser purchase (#2) paid for itself by
revealing the pulse-width difference against the intervalometer
reference. Items below kept for record.

1. ~~**Replace optocoupler + resistor.**~~ **NOT NEEDED Day 12.**
   Jaycar ZD1928 4N25/4N28 (×2 for spare) + 220Ω resistor pack.
   Opto path verified innocent (intervalometer through same opto =
   100%). Spare 4N25s + 220Ω still useful as inventory if a future
   genuine opto fault appears.

2. ~~**Buy USB logic analyser.**~~ **DONE Day 12.**
   SparkFun TOL-18627 from Core Electronics, 24MHz / 8-channel, ~$30.
   PulseView/sigrok. Comparing the intervalometer trace (200ms LOW)
   against the Uno+opto trace (100ms LOW) on the same instrument
   identified the pulse-width gap. Worth the $30.

3. ~~**After opto swap:** re-run Tv=0.8"+2s test, target 100% delivery.~~
   **SUPERSEDED Day 12.** No opto swap happened. Tonight's
   end-to-end production validation at Tv=0.5"/2s + luminance every
   3rd photo + live view = 38/38 = 100% delivery, a stricter
   condition than the Tv=0.8"+2s target. The chronic drop issue is
   resolved.

## WiFi / RF link (NEW day 8 — REFRAMED Day 12)

**Day-8 framing was wrong** (now corrected): "CCAPI fetches over WiFi
are the only source of photo drops in production". That sentence was
written before Day-12 identified the 100ms shutter pulse width as the
real cause of chronic drops. Post-Day-12, CCAPI fetches do NOT cause
drops — Day-12 Run #7 (full CCAPI load + 200ms pulse) delivered 37/37
in the Day-11 stress condition. Pin-8 cadence is independent of fetch
latency; the PULSE log confirms electrically pristine output across
all conditions.

**Post-Day-12 architectural context:** WiFi reliability at 60-100m
distance still matters, but for **exposure quality degradation under
extended outage**, not for photo delivery. The scenarios:

1. **Transient fetch failures (seconds)** — handled by existing
   `lum_fetch_skip_remaining` backoff (skip 2 cycles on fail).
   Cart retains `lum_last_value`, photos keep firing at correct
   cadence, exposure stays at the most recent reading. This works
   today and was verified Day-12.

2. **Extended outage (minutes-to-hours)** — cart at distance, link
   drops while sky continues to change. Current code holds the
   stale `lum_last_value` indefinitely. After 10-30 minutes that
   value becomes wildly wrong; every subsequent photo's exposure
   is wrong. This is the gap the formula-fallback architecture
   (#36b + #36d) was designed to fill: when fresh luminance has
   been unavailable for N seconds, evaluate the time-of-day
   formula (Old World Table approximation) to produce a
   less-wrong (Tv, ISO) until live luminance returns.

3. **Total outage entire shoot** — operator picks branch + pushes
   formula to cart before shoot (#36 DONE Day-9 late evening).
   Formula-only mode runs without CCAPI. Already implementable on
   the Excel side; just needs #36b to evaluate on cart.

Per architectural principle #2 ("wrong exposure fixable in post") the
formula fallback isn't pursuit of perfection — it's keeping degradation
*bounded* during outages. A 30-minute-stale CCAPI reading drifts
unboundedly; a formula evaluation tracks the sun and stays close.

Field shoots place the cart 60-100m from the van with a ~20m
operating arc. WiFi reliability at that range directly impacts how
long the cart spends in fallback mode, which is now an
**exposure-quality** concern, not a delivery one.

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
22. **Port cart firmware from Uno R4 to Giga R1.**
    **HELD IN RESERVE — see architectural principle #14 in PREFERENCES.**
    Don't execute proactively. Uno R4 is current and sufficient for
    everything built so far. Migrate only when a specific workfront
    demonstrates Uno is the blocker (SRAM exhaustion, WiFi capacity,
    computational load, or feature requiring more I/O). At design
    time on any new workfront, ask: *does this break the Uno?* If
    yes, migration becomes part of that workfront. If no, stay on
    Uno.
    Scope when activated: WiFi layer is the main change (WiFiS3 →
    mbed WiFi). Pin-8, CCAPI, exposure, plan endpoints, CAN — all
    need verification on new board.

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

~~9. **Replace ±180° yaw constants with ±450° cumulative** throughout
   sketch and Gimbal.bas. Track unwrapped cumulative yaw.~~
   **DONE Day 12.** Implemented differently from the original
   wording: instead of widening hardcoded constants to ±450°, the
   cart now has no yaw clamp at all (cart is dumb on yaw), and
   Excel's `Gimbal.GimbalPosition` enforces a per-shoot envelope
   from Settings named ranges `gimbalYawEnvelopeMin` /
   `gimbalYawEnvelopeMax` (default ±225°, 450° span). Out-of-
   envelope commands return False and log to BTN; no HTTP is sent.
   Verified end-to-end Day 12: cumulative yaw past ±180° honoured
   by the SDK (tested +170° → +190° → 0° unwound honestly); refuse
   path works (yaw=300 outside default ±225 refused, then accepted
   after operator widened envelope to 310).

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

12. **Inverse fitting: trace → smooth Plan.** **REJECTED day 10** —
    superseded by #44 cluster which was itself rejected. See day-10
    update above. CartLog *is* the Plan; no inverse fitting needed.

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

    **Test program (day 9 late-late evening update):**
    - Full 360° circle at servo +30° (averages out ramp + measurement
      noise; 4× the data of the day-9 quarter test)
    - Half circle at servo +15° (linearity: does +15° give 2× the
      radius of +30°?)
    - Full circle at servo -30° (symmetry: left vs right turn radius)
    - Push servo offset upward until steering binds or radius stops
      decreasing — find max usable steering
    - Optionally +45° if linkage allows
    - Method: drive at 100 m/hr (speed-independence confirmed
      day-8), CCAPI + CANbus off (isolate cart-only behaviour),
      mark **8 rear-axle (x, y) positions** at approx 0°/45°/90°/
      135°/180°/225°/270°/315° around an imaginary peg-marked
      centre. Operator angle-by-eye between marks (operator self-
      assessed as good at this; the circle-fit doesn't require
      angles to be exact).
    - At each ground mark, operator presses a cart-UI "Mark
      Waypoint" button (workfront #29b) producing a distinct log
      event so Excel can pair ground (x, y) to log timestamp.

    **Outputs feed two downstream consumers:**

    1. **Operator turn-advice document** (new sub-workfront 29a) —
       turn-by-eye rules of thumb the operator can keep in their
       head or on a card: "want 2m orbit? servo ≈ 30°", "want 5m
       orbit? servo ≈ 15°", "minimum orbit radius is X m at max
       servo", "left vs right differ by N% — choose orbit direction
       accordingly". Pre-recon knowledge to frame what's possible
       before pressing record.

    2. **Excel smoothing maths** (workfront #44) — if servo-to-wheel
       turns out non-linear, the maths uses a lookup table or
       piecewise fit instead of a single SERVO_TO_DEG constant.
       If asymmetric, signed-steering branches differ. #44's
       visualisation/structure can be built without #29; #44's
       **execution accuracy** depends on #29.

    Then commit calibration (constant or table) to BicycleModel.bas.

29a. **Operator turn-advice document.** Plain-language guide produced
     from #29 results. Lives alongside PROJECT_STATE.md. Updated
     when #29 is re-run (e.g. after physical changes to the cart,
     new wheels, new steering linkage). Operator's eyeball
     reference during recon planning.

29b. **Cart UI "Mark Waypoint" button + log event (firmware).** New
     button on the cart logging UI page. POSTs to a new endpoint
     `/cartlog/waypoint`. Endpoint appends a log event of distinct
     type `"W"` to the in-RAM cart log buffer. Value = sequential
     waypoint number (1..N) or zero. ~8 events per calibration
     test; no impact on CART_LOG_MAX=64. Update Cart.bas's
     `EventDescription` to recognise `"W"` and render as
     "Waypoint N". Pre-req for the log-comparison block on the
     Calibration sheet.

29c. **Excel log-comparison block on Calibration sheet.** Below
     the ground-truth 8 (x, y) input block: a second block of 8
     rows that, after the cart log is pulled, auto-finds the 8
     "W" events and pulls (x_log, y_log) from the integrated
     Trace sheet at each. Side-by-side comparison reports delta_x,
     delta_y, distance per point, plus max delta and RMS delta
     summary. Tests bicycle-model integration fidelity independent
     of the steady-state circle-fit calibration.

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

## Exposure fallback + validation (UPDATED day 9 late evening — session model)

Full design rationale in `EXPOSURE_FALLBACK.md`. These workfronts
implement that design.

**Architecture (refined day 9 late evening):**

Three layers:

1. **Old World Table** — operator's hand-tuned t_rel → (Tv, ISO)
   recipe (Appendix A of EXPOSURE_FALLBACK.md). Single curve, no
   variants. Authoritative until superseded by data.
2. **Simple formula** — parameterized approximation of the Old
   World Table. Parameters fit such that formula reproduces
   Appendix A at default settings. Runs on cart in fallback mode
   (CCAPI silent). Storage cost much smaller than the table;
   behaviour identical for default inputs.
3. **Saved CSVs** — every post-timelapse session saves a CSV
   capturing that shoot's (t_rel, Tv, ISO) rows + operator tags +
   operator comments. Stored as files in a folder, not in the
   workbook. Refit sessions load them on demand.

**Working data shape: (t_rel, Tv, ISO).** EV is derived only when
needed for plots; never stored. f=1.8 is a fixed project constraint.

**Three operator sessions, distinct activities, no coupling:**

| Session | When | Activities | Build status |
|---------|------|------------|--------------|
| **Shoot** | Evening, at cart | Pick branch, push formula to cart, execute | **BUILD NOW** (#36 + #36a-e) |
| **Post-timelapse** | Daytime after shoot, at laptop | Import CR3s, extract, tag, comment, save CSV | **BUILD NOW** (#37 + #37a-c) |
| **Refit** | Optional, cold winter night | Load CSVs, inspect divergence, decide branch refits | **DEFERRED** until CCAPI shoots exist (#38 + #38a-d) |

**Formula structure is locked, only values change.** The simple
formula's parameter shape (Tv-step crossover t_rel values + ISO
ramp anchors + ceilings) is general enough to express any realistic
variation across seasons, locations, sky conditions. Future CCAPI
refits will produce **new parameter values for the same structure**
— drop-in replacements via `/exposure/load`. This is why #36 and
#37 can be built now with full confidence: the storage shape (CSV)
and the runtime shape (formula parameters) are forward-compatible
with future refits.

**Core operator workflow is sessions 1 + 2 only.** Many operators
will never refit, never branch — they just shoot, save data, and
fix variance in post per architectural principle #2.

**Branching is operator opt-in.** Default branch always exists.
Operator may create branches when post-timelapse comments reveal
a basis (bright sky / dull sky / smoke / etc) — but is never
required to. System works correctly for an operator who only ever
uses "default."

**Refit threshold is HIGH, not optimisation.** When refit is
eventually built, Excel during refit is a divergence detector, not
a refinement engine. It surfaces big differences (~1+ stop in a
specific t_rel zone). Operator inspects, typically attributes to
an in-shoot nudge or noise, and ignores. Refit commits are rare
and exceptional — they mean something genuinely changed in the
real world (lens / location / season range / hardware), not data
accumulation. The expected normal outcome of a refit session is
**no refit committed.**

---

### Done (day 9 late evening)

~~38a. **EXIF ingestion pipeline (Python).**~~ **DONE.**
`exif_ingest.py` extracts (filename, DateTimeOriginal,
ExposureTime, ISO, BrightnessValue, GPS, Status) from a folder
of CR3 files via exiftool. Tested on 6,176-image Jan 22-23 2026
shoot, 100% clean parse. BrightnessValue confirmed absent on R3
(see EXPOSURE_FALLBACK.md §6.5). Lives in project root.

~~validation toolchain.~~ **DONE.** `validate_exposure.py`
compares an exif.csv against Old World Table, bins differences
by t_rel, writes per-photo validation.csv. Useful for spot-checks;
not part of the production session model. Rename candidate
("compare_to_reference") deferred.

---

### Shoot session — pre-shoot infrastructure

~~36. **Branch picker + cart push (Excel).**~~ **DONE day 9
late evening.** Implemented in `Formula.bas` module + new
buttons on Control sheet. `dataActiveBranch` named range on
Settings holds current branch. `PushFormulaToCart` POSTs the
active branch's parameters to cart `/exposure/load` as JSON.
Verified end-to-end against cart-off (HTTP 0 = no server,
expected) — payload constructed correctly at 937 bytes for
default branch. Re-test against running cart firmware will
yield 404 until #36b implements the endpoint.

~~36a. **Simple formula definition (Excel).**~~ **DONE day 9
late evening.** `FallbackFormula` sheet built by
`InitFallbackFormula`. Default column seeded from Appendix A
(51 sunset Tv crossovers + 12 ISO ramp anchors + 3 policy
ceilings). Two UDFs (`FormulaTv`, `FormulaISO`) walk the
crossover rows and return snapped (Tv, ISO) for any t_rel.
Live evaluator at bottom of sheet lets operator scrub t_rel
and watch the result update.

Verified the formula reproduces Appendix A at seven test
points spanning all phases:
- t=-4800 → 1/5000, ISO 100  ✓
- t=-300  → 1/500,  ISO 100  ✓
- t=1500  → 1/15,   ISO 100  ✓
- t=2220  → 1,      ISO 100  ✓
- t=3300  → 20,     ISO 100  ✓
- t=3600  → 20,     ISO 320  ✓
- t=4440  → 20,     ISO 1600 ✓

Branching infrastructure works via `AddBranch newName,
copyFromName` — copies an existing branch column to a new
column at the right. Untested at runtime; deferred until
operator has a reason to branch.

**Sunrise side not yet stored.** Formula returns sensible
sunset-side values only. Sunrise as time-mirror is the design
assumption (EXPOSURE_FALLBACK.md §3.2). Implementation is a
small later enhancement — sign-flip in the UDF or a second
column block. Not blocking for first CCAPI shoot since shoots
typically start near sunset.

**Lessons captured during build (worth a note in PREFERENCES
when next updated):**
- VBA: line continuations capped at ~24 per logical line.
  Use row-by-row assignment for long literal arrays.
- Excel: cell value strings starting with `==` are parsed as
  formulas → raise 1004. Use `--` or prefix with apostrophe.
- VBA `With Range.Cells(r,c)` can fail with 1004 after
  recent operations on adjacent cells; direct
  `range.Cells(r,c).property = ...` is more reliable.

~~36b. **Formula evaluator on cart (firmware).** Receive parameter
     set from Excel via `/exposure/load`. Evaluate at current t_rel
     each photo cycle. Snap to R3's Tv/ISO grid. Storage:
     parameters (~100 bytes) + Tv grid + ISO grid ≈ ~400 bytes
     PROGMEM.~~
     **DONE Day 12.** Implemented via GET query string (not POST/
     JSON) — avoids POST body handling and JSON parser on RAM-tight
     Uno R4. URL-size validated via /debug/urlsize before build (1.5
     KB envelope confirmed; real Appendix A payload = 1323 bytes).
     Cart stores ~1.4 KB RAM in struct arrays (60 Tv entries × 2
     sides + 20 ISO entries × 2 sides + 4 ceilings/branch). Parser
     and walkers (`formulaTv`, `formulaIso`) implement the same
     algorithm as Excel's FormulaTv/FormulaISO UDFs. Verified end-
     to-end Day 12: 9 evaluation points across sunset+sunrise all
     match expected values; real Appendix A push gives sstv=51,
     ssiso=12, srtv=49, sriso=14 with correct Tv/ISO at known
     waypoints (t=2220 → 1s/ISO100, t=3600 → ceiling/ISO320).
     Diagnostic endpoint `/debug/formula?t=N&event=sunset|sunrise`
     retained for future verification. Tv-format translation
     (Excel "0.5" → Canon "0\"5") deferred to #36d.
     Sketch size: 130324 bytes flash (49%), 22556 bytes globals
     (68%), 10212 bytes stack headroom — healthy.

36d. **Fallback mode switching + anchor management (firmware).**
     Track last successful fetch timestamp. After threshold of
     silence, switch to formula mode silently. On successful
     fetch, snap to live luminance; if delta > 1/3 stop, smooth
     over 3 frames.

     **Subtask 1 (DONE Day 12): Time anchor.** Wire format extended
     with three params: `&t0ss=NNNN` (sunset trel at receipt),
     `&t0sr=MMMM` (sunrise trel at receipt), `&cross=PPPP` (sunset
     trel threshold for event flip). Cart stamps millis() at receipt
     and advances both anchors together. Active event picked by
     comparing current sunset-trel against cross threshold (cross =
     time gap between civil sunset and astronomical sunset, ~5400s
     for Adelaide May). One push at session setup covers whole
     sunset-through-sunrise shoot, no re-push mid-shoot. Excel reads
     cached event times from Settings (dataSunsetTime, dataSunriseTime,
     dataAstroDusk — operator refreshes via Get Sunset Time button
     before push). Verified end-to-end Day 12: both anchors advance
     in lockstep, crossover flips at threshold both directions,
     restoration works. `/debug/trel` diagnostic endpoint reports
     full state. Sketch size: 131996 bytes flash (50%), 22568 bytes
     globals (68%), 10200 bytes stack headroom — healthy.

     **Remaining subtasks:**
     - **Subtask 2: Outage detection.** Wire `lum_last_success_ms` to
       a threshold (~5min? size by field-test experience). When
       silence exceeds threshold, set `exposure_mode = fallback`.
     - **Subtask 3: Tv-format translation.** Excel sends "0.5" / "1/500" /
       "20"; camera wants "0\"5" / "1/500" / "20\"". Add `excelTvToCanonTv()`
       lookup on cart, applied before `ccapiPutTv()`. Maps via TV_LADDER
       index or hand-rolled string-rewriting.
     - **Subtask 4: Photo-loop integration.** Each photo cycle: read
       mode. If `live`, current path. If `fallback`, evaluate formula
       at getCurrentTrel(), translate Tv, push Tv+ISO via ccapiPut*.
     - **Subtask 5: Recovery.** On first successful fetch after outage:
       if delta > 1/3 stop from live, smooth over 3 frames. Otherwise
       snap. Switch mode back to `live`.
     - **Subtask 6: Outage-edge cases.** Stale cached times in Excel,
       API failure (HTTP 521 seen Day 12), sunrise rollover when
       today's sunrise has already passed — operator workflow to
       refresh before pushing.

36e. **Cart UI exposure status (firmware).** Status bar showing
     mode (live / fallback / seconds-since-fetch), current branch
     in use, last fetch delta. Parallel to existing CAN status bar.

---

### Post-timelapse session — extraction and save

37. **Post-timelapse import workflow (Excel).** Single-pass workflow
    from CR3 folder to saved CSV. Steps:
    1. Operator clicks "Import new shoot"
    2. Prompted for CR3 folder path
    3. Excel shells out to `exif_ingest.py`, waits, loads result
    4. Excel computes t_rel per row (needs shoot date, location,
       sunset/sunrise from Astro.bas — see #37a)
    5. Operator fills in tags on a single form:
       - Shoot date (auto-detected from EXIF, operator confirms)
       - Sky condition (clear / partial / overcast / smoke / other)
       - Type: **CCAPI-driven** or **table-driven** (defaults
         table-driven; CCAPI presence detected if possible from
         shoot metadata, else operator confirms)
       - Branch label (default unless operator chose otherwise)
       - Free-text comments (anything the operator noticed —
         later guides refit-session decisions)
    6. Operator clicks "Save shoot CSV"
    7. Excel writes CSV with all rows + tag metadata in header to
       configured shoot-archive folder
    No formula comparison, no charts, no accept/reject decisions.
    Pure capture-and-park.

37a. **Astro retrospective mode (Excel).** Confirm Astro.bas accepts
     past timestamps and returns sunset/sunrise for the shoot date
     + location. Drives t_rel computation in #37. Mostly a review
     of existing module — may already work.

37b. **Shoot-archive CSV schema.** One file per shoot. Header rows
     hold tags (ShootID, Date, Type, Branch, SkyCondition, Comments,
     SunsetUTC, SunriseUTC, Location). Body rows hold
     (Filename, DateTimeOriginal, t_rel_sec, Tv, ISO). Tag metadata
     in header keeps each CSV self-describing for the refit session
     loader. Folder convention: project-folder/shoots/YYYY-MM-DD/

37c. **Table-driven shoots saved but flagged.** Table-driven shoots
     go through the same import + save flow; the Type tag carries
     forward to the refit session, which excludes them from
     divergence analysis (per EXPOSURE_FALLBACK.md §5.4a). Stored
     for record but not refinement input.

---

### Refit session — DEFERRED until CCAPI shoots exist

**Status: DO NOT BUILD YET.** The workfronts below are documented
for future implementation. They are explicitly deferred until
multiple CCAPI-driven shoots exist to design against.

**Why deferred (captured day 9 late evening discussion):**

1. **Nothing to refit yet.** The aggregate has zero CCAPI-driven
   shoots. There is no data to drive any refit decision today.
   Until the cart's CCAPI luminance loop reaches production, the
   simple formula (#36a) seeded from Old World Table is both
   the runtime fallback AND the only formula. No alternatives
   to compare against.

2. **First CCAPI shoots are weeks/months away.** Production CCAPI
   depends on the opto fix (#1), logic-analyser confirmation (#2),
   WiFi reliability work (#22-26), and operator field time.

3. **Specifications would be guesses.** Today's discussion has
   the *shape* of the refit session (load CSVs, show divergence,
   operator yes/no, log decisions) but not the empirical details
   (what "divergence" means numerically, what charts illuminate
   the decision, what comment patterns matter). Those answers
   come from looking at 3-5 real CCAPI CSVs side-by-side, not
   from imagining what they might contain.

4. **CSVs are forward-compatible — refit can be built later
   without data loss.** As long as the post-timelapse CSV schema
   (#37b) captures everything that might matter — raw rows, all
   tags, free-text comments — refit-session UI can be designed
   against real archived shoots whenever that future session
   happens. CSVs accumulate; the workbook that loads them
   waits.

5. **Most operators will never refit anyway.** Branching and
   refitting are opt-in infrastructure. Per architectural
   principle #2 ("wrong exposure fixable in post") and the
   day-9 framing ("variance easy fixed in post; simple current
   formula is good enough"), the core operator workflow is
   sessions 1 + 2 only. Refit is enrichment, not foundation.

6. **The formula structure is locked, only values change.** The
   simple formula's parameter shape (Tv-step crossover t_rel
   values + ISO ramp anchors + ceilings) is general enough to
   express any realistic variation in atmospheric ramp shape
   across seasons, locations, sky conditions. CCAPI refits
   produce **new parameter values for the same structure** —
   they are drop-in replacements via `/exposure/load`. The
   formula module (#36a) and the cart firmware evaluator (#36b)
   never need to change to absorb refit results. This is the
   key justification for building the formula NOW with full
   confidence.

**What unlocks "build now" status:**
- ≥3 CCAPI-driven shoots saved as CSVs in the archive folder
- Operator wanting to inspect them side-by-side
- Patterns visible in the data that suggest divergence-display
  thresholds and chart shapes

**Captured shape (for the future builder):**

38 [DEFERRED]. **CSV loader for refit session (Excel).** Load all
    shoot CSVs from archive folder (operator may filter by date
    range, branch, type). Comments visible alongside each loaded
    shoot — they guide branch / refit decisions. Display:
    per-shoot row list with tag summary + scrollable comments
    column.

38a [DEFERRED]. **Per-branch divergence display (Excel).** For a
     selected branch:
     - Filter loaded shoots to that branch's contributors
     - Overlay all (t_rel → Tv) curves from CCAPI-driven shoots
     - Overlay current branch formula
     - Highlight zones where ≥N shoots diverge from formula by
       ≥M stops (threshold-driven; defaults set HIGH per
       architectural principle "easy fix in post")
     - Surface verdict: "no refit needed" (default) or "candidate
       divergence at t_rel=X" with brief stats
     Thresholds (N and M) to be calibrated empirically from
     real CCAPI data, not guessed.

38b [DEFERRED]. **Operator refit Yes/No (Excel).** For each
     candidate divergence:
     - Operator inspects, attributes to nudge / noise / real shift
     - Default disposition: ignore (consistent with "simple
       formula good enough")
     - If operator selects "refit": Excel re-fits the branch's
       formula parameters against the selected subset; shows
       per-parameter delta + residual std before/after; operator
       Yes/No to commit
     - All decisions logged regardless of outcome
     - Expected normal outcome: NO refit committed. Refit is
       exceptional, not routine.

38c [DEFERRED]. **Refit log (Excel).** One row per refit-session
     decision: date, branch reviewed, loaded shoots count,
     divergence flagged y/n, refit committed y/n, parameter
     deltas if committed, operator notes. Builds confidence over
     time without committing to changes. Operator can re-read
     the log later.

38d [DEFERRED]. **Branch CRUD (Excel).** Operator creates new
     branch by:
     - Picking a basis (e.g. "bright clear skies")
     - Selecting shoots from loaded set that match the basis
     - Naming the branch
     - Excel runs a fresh fit against the selected shoots,
       initialising the new branch's parameters
     - New branch becomes available in #36 pre-shoot picker
     Branches can be deleted (with log entry); never auto-created.

---

### Reference data and shoot tagging

39. **EXPOSURE_FALLBACK.md upkeep.** "Shoots reviewed" log within
    EXPOSURE_FALLBACK.md (new section, TBD) tracking which shoots
    have informed which branches. Lightweight version control by
    hand. First entry: Jan 22-23 2026 shoot — flagged
    **table-driven, not refinement input** (see §5.4a worked
    example).

39a. **Shoot-type tagging at capture.** Cart should log whether
     CCAPI luminance loop was active during the shoot, and write
     this to a sidecar file at shoot start/end. Lets the
     post-timelapse session auto-detect Type rather than relying
     on operator memory. Minor firmware addition.

## Heading + gimbal stream (NEW day 9 evening)

Coupled cluster: heading source (IMU + operator anchors) feeds gimbal
CAN target stream. Originally drafted as three separate notes
(BNO085 install, iPhone compass anchors, gimbal CAN rate sizing).
Merged here because they form one data-flow chain.

40. **BNO085 IMU install + UART-RVC integration.** Single Adafruit
    BNO085 9-DOF breakout (~AU$40, Core Electronics; SparkFun BNO086
    is drop-in alternative). UART-RVC mode at 100Hz over 4-wire
    cable (3.3V, GND, TX, RX) to Uno R4 Serial1 (or Giga R1 post-#22
    migration). No level shifter needed (3.3V native both sides).
    No I²C — avoids cable-length and stepper-noise concerns at 350mm.
    Re-uses on-hand Cat6 offcuts; no new cable purchase.

    **Mounting:** top of the non-metallic mast (#23/#24 cluster).
    Small 3D-printed / non-metallic enclosure. Orient
    **X_imu=cart_forward, Y_imu=cart_left, Z_imu=cart_up** so
    BNO085 outputs directly in cart body frame (no rotation matrix
    in firmware). Reference marks on PCB and mount so re-installs
    preserve orientation.

    **Mast mechanical requirement (new constraint on #24):** mast
    fold mechanism needs a **repeatable hard-stop in the shoot-up
    position** (pin, latch, or bolt-locked hinge). This guarantees
    the antenna's ferrous mass returns to the same location relative
    to the IMU each time, so the BNO085's hard-iron calibration done
    once in shoot config remains valid across power cycles and
    transport/deploy cycles. Also good for RF repeatability.

    **Mast specs (refined):** 350mm useful length from cart deck to
    IMU mount, plus enough above the IMU for the antenna. Stiffness:
    rod-style ≥10mm fibreglass, or PVC pipe with wall thick enough
    to not sway visibly on cart start/stop. Non-metallic throughout.

    **Failure mode is graceful** — fall back to bicycle-model
    dead-reckoning + iPhone compass anchors (#41). Architectural
    principle #12 holds: IMU path is WiFi-independent.

    **Day 12 first-light bench test (DONE):** Adafruit BNO085 4754
    on Uno R4 WiFi via I2C at 0x4A. Wiring: VIN/GND/SCL/SDA/INT(D7),
    no RST needed. SparkFun_BNO080_Arduino_Library handles it.
    Rotation vector @ 10Hz. Standard figure-8 motion brings the
    magnetometer to acc=3. Once calibrated, captured a `c`-command
    offset against iPhone compass in True-North mode (offset =
    +9.16° for tonight's bench setup, which folds together magnetic
    declination + BNO mounting angle into one number). Verified
    against iPhone at N, E, S, W — true_yaw tracks to within ±3°
    of iPhone reading. **For the 14mm shooting lens this is
    negligible** (~3% of frame width, invisible in result).
    Standalone sketch `BNO085_BenchTest.ino` retained as parked
    diagnostic asset alongside DropTest.ino. NOT yet integrated
    into the production sketch.

    **Architectural questions — RESOLVED day 13 (see PROJECT_STATE
    day-13 entry for full design):**
    1. **Continuous vs session-start heading?** Neither. Excel
       pre-bakes gimbal cubics; operator-placed anchor rows
       inject a running scalar `gimbal_yaw_correction` applied
       additively to earth-frame-tagged segments only.
    2. **Offset persistence:** Excel-pushed via Settings, NOT
       EEPROM. Fits existing Appendix A / yaw envelope push
       pattern. Operator captures via `c`, reads from /debug/imu,
       types into Excel named range, next push carries it.
       Adelaide declination web-verified +8.11°.
    3. **Mid-shoot acc dropout:** two-attempt retry per anchor
       row (500mm, then 400mm before waypoint). If both fail,
       keep previous `gimbal_yaw_correction`. Log A_OK / A_SKIP /
       A_FAIL to CartLog. Photos sacred throughout.
    4. **Chassis heading vs steering angle:** chassis only, BNO
       only. Cart does NOT run bicycle-model θ integration.
       Anchors compare BNO chassis yaw to Excel's pre-baked
       expected heading at that row.
    5. **Cart-to-Excel feedback rate:** anchor-cadence, not
       photo-cadence. New CartLog event type `A` pulled via
       existing /cartlog endpoint. Excel splits to dedicated
       AnchorLog sheet on import.
    6. **Frame convention bridge:** Excel does the bridge at
       authoring (bakes earth-frame astro into cart-frame cubics
       using assumed cart heading). Cart applies a scalar offset
       at cubic eval time to earth-frame-tagged segments only.

    **Original (now superseded) question text retained below for
    reference / archaeology:**
    1. **Continuous vs session-start heading?** Cart moves during
       hyperlapse execution. Does the gimbal-plan walker (#14)
       compute astro→cart-relative yaw every photo using current
       BNO heading (Shape A), or does Excel bake fixed cart heading
       into the plan at authoring time (Shape B)? Shape A is more
       flexible; Shape B keeps the cart dumber. Tracking astro
       while the cart traverses (the typical hyperlapse pattern)
       strongly suggests Shape A.
    2. **Offset persistence.** Where does the `c`-capture offset
       live across power cycles? EEPROM on cart? Pushed from Excel
       like the formula? Recaptured every session? Each has
       different operator-workflow consequences.
    3. **Mid-shoot acc dropout.** If the magnetometer's acc drops
       below 2 mid-shoot (RF interference, ferrous transient, etc.),
       cart should: pin to last good yaw? Trust gyro extrapolation?
       Log and continue, photos sacred?
    4. **Chassis heading vs steering angle.** For astro tracking we
       want the chassis's instantaneous heading (where the body is
       pointing), not steering angle. BNO mounted to the chassis
       gives chassis heading directly. Bicycle-model `theta` is
       different (kinematic integration of steering + speed).
       Cart needs to distinguish.
    5. **Cart-to-Excel heading feedback rate.** Excel's Trace chart
       (and gimbal-plan viz) wants cart heading at photo cadence
       or better for live display. New endpoint or piggyback on
       existing telemetry? CartLog row format extension?
    6. **Frame convention bridge.** Excel's BicycleModel uses
       cart-local theta (start = +X axis). Astro tables use earth
       true-azimuth. BNO085 provides the bridge. Where the
       bridging math lives (cart firmware vs gimbal-plan UDF vs
       Trace UDF) is a design choice.

    **Calibration on a 16kg cart (operational reality):**
    The lab figure-8 motion that achieves acc=3 in seconds is
    impossible once the BNO is bolted to a 16kg cart. Practical
    calibration workflow at shoot setup:

    - **Drive the cart in 2-3 full circles** (yaw coverage) with
      motors active. Motors-active matters because stepper DC
      currents are part of the cart's local magnetic environment;
      calibrating with motors off then driving with them on
      invalidates the calibration.
    - **Cross any available slope/incline** during setup for pitch
      and roll variation (acc=3 needs all 3 axes; acc=2 is yaw-
      dominant and sufficient for 14mm lens).
    - **Watch acc value live** while driving. The BNO supports
      saving calibration state to its own NV memory (library:
      saveCalibration), which survives power cycles BUT is tied to
      the local magnetic environment at calibration time. Move
      cart to a new location → re-calibrate.

    Implications:
    - **Per-shoot setup time:** 3-5 minutes of "drive a few circles
      with motors running" pattern. Operator workflow needs to plan
      for this; not a quick start.
    - **Per-location, not per-session:** if same site re-shot in
      consecutive evenings, saved calibration may still be valid.
      Different town/region → re-calibrate.
    - **Cart's own field must be stable.** Mast antenna in
      repeatable position (already a #24 constraint). Anything
      else ferrous that moves between calibration and shoot
      (battery, cables, deck-mounted gear) invalidates calibration.
    - **Live operator feedback during calibration drive.**
      Recommended: `/debug/imu` endpoint streaming current acc +
      raw_yaw + true_yaw, viewable on operator's phone/browser
      while driving the circles. Changes the workflow from "drive
      blind hoping acc climbs" to "drive while watching number
      climb to 2 or 3, hold true-north for capture". Cheap to add
      (mirrors `/debug/trel` shape).
    - **The `c`-capture true-north step** still happens AFTER
      acc≥2 is achieved. Order: calibrate-by-driving → confirm acc
      stable → point cart at iPhone true-north reading → press
      capture. Capture stamps that one moment as "yaw=0 = true
      north for this shoot".

41. **iPhone compass heading anchors at waypoints.** Cart heading
    estimate (bicycle-model dead-reckoning + IMU when present) drifts
    over time. iPhone compass provides operator-in-the-loop absolute
    reference at chosen waypoints. Fits the avoidance-vs-solve
    discipline: bound the drift problem with operator anchors rather
    than chasing autonomous absolute heading on a stepper-noisy cart.

    **Storage in plan:** new column on **Sequence** sheet —
    `Compass Heading (°N true)`, blank by default. Blank = no anchor,
    drift continues uncorrected. Filled = anchor against this value
    when waypoint is reached.

    **Workflow modes:** pre-planned (operator scouts site, points
    cart down each intended pose, reads iPhone compass, types values
    before shoot) OR live (operator reaches waypoint, points cart,
    reads phone, types value, triggers waypoint). Same field
    supports both.

    **Correction logic (cart side):** on reaching a waypoint with
    non-blank compass value:
    `heading_correction = compass_value - current_estimated_heading`
    Apply as snap (immediate) for lock-mode tracking shots — gimbal
    re-aims, GC moves to correct position in frame, no visual
    artefact since the lock target is recomputed anyway. Fade-in
    option deferred — anchors land at segment boundaries, not
    mid-segment.

    **True north vs magnetic north:** AstroTable uses true north
    (astronomical convention). iPhone compass defaults to true
    north on modern iOS; verify Settings → Compass → Use True
    North = ON. Plan template should include a checkbox / note on
    Settings sheet. Adelaide magnetic declination currently ~+6.5° E;
    only relevant if iPhone is on magnetic.

    **iPhone reading hygiene:** re-do figure-8 calibration when
    iPhone prompts. Take readings **away from the cart** (steppers,
    batteries, steel) — the very interference the on-cart IMU mast
    was raised to escape. Stand 2m back, point phone along intended
    cart heading, read.

    **UI surface:** minimum viable = extra column on Sequence sheet,
    manually filled. Nicer (deferred) = "Capture Heading" button on
    Control sheet that prompts operator and writes into active
    waypoint row.

    **Open question:** does operator need to see cart's current
    heading estimate alongside iPhone reading, to spot gross errors
    before committing the anchor? (Suggests adding
    `Current heading (°N)` to Monitor sheet next to existing cart
    state block.)

    **Depends on:** #40 (IMU path) for precision between anchors,
    but useful even with dead-reckoning only. Touches #32 't' event
    integration — heading correction is a state event the bicycle
    model needs to consume cleanly.

42. **Gimbal CAN command stream update rate sizing.** Cart streams
    (target_yaw, target_pitch) to Ronin RS2/RS3 over CAN using DJI
    R SDK position-control command (CmdSet 0x0E, CmdID per 2.3.4.1).
    While the command stream is active, gimbal operates earth-frame
    regardless of M-button mode (per ArduPilot driver empirical
    note). This overrides pan-follow as long as commands are
    streaming.

    **Design point to size:** at what rate should cart push
    (target_yaw, target_pitch) updates, and what `time_ms` field
    value per command?

    **Inputs to the sizing:**
    - GC angular motion rate (from AstroTable): steepest near
      zenith transit ~50°/15min (e.g. 02:15→02:30 = 47.4°→26.4° Az).
      Most of night slower.
    - Cart yaw rate during driving: bicycle model
      `dθ/dt = v·tan(δ)/L`. At 100 m/hr, +30° servo
      (δ_wheel ≈ 10.6° per current SERVO_TO_DEG=0.35), L=0.49 →
      ~1°/sec. Drops by speed ratio at lower speed.
    - Exposure duration: at night, Tv up to 20s. Gimbal must hold
      attitude steady within blur tolerance for full exposure.
    - SDK command floor: `time_ms` min 100ms per docs.
    - Smoothness vs latency: too-fast may chatter gimbal motors;
      too-slow lags GC arc and lags cart yaw compensation.

    **Open questions:**
    - Does gimbal's own IMU handle cart-yaw compensation between
      CAN updates? (Earth-frame interpretation suggests yes —
      gimbal holds attitude on its own gyros; our command just sets
      target in earth frame.)
    - Gimbal step response to new target — test with `time_ms` =
      100, 500, 1000 and observe.
    - Streaming faster than `time_ms` (e.g. new command every 200ms
      with time_ms=1000): does gimbal abort in-flight motion and
      restart, or blend?

    **Suggested first test:** bench-stream sinusoidal target_yaw
    at 1 / 2 / 5 Hz with varying time_ms. Observe motion smoothness
    via phone camera or get_current_position read-back. Establish
    sensible default before designing AstroTable-driven path.

    **Depends on:** #40 + #41 (heading source) for cart-frame to
    earth-frame mapping. Sits alongside #32 ('t' event integration)
    and #29 (circle test — cart yaw rate calibration). Independent
    of #36-39 (exposure cluster).

## Cart Plan smoothing (NEW day 9 late evening)

Cart is hard to drive cleanly. The Cart Log captures whatever the
operator actually managed during recon — including 3-segment turns
that should have been single arcs, mid-turn corrections, false
starts. Smoothing is the planning-stage operation that proposes
clean cart-native segments (single arcs, including effectively-
straight large-radius arcs) for selected ranges of the wobbly log.

**Reality of recon (day 9 late evening discussion):**
- Cart drives at 100 m/hr for recon (survey speed, fast enough to
  scout without taking an hour, slow enough for operator to steer
  and react).
- Execution drives at ~5 m/hr (production speed, gives camera time
  between photos).
- Same geometry, different speeds, only possible because bicycle
  model is speed-independent (day-8 finding).

**Two operator interventions:**

1. **Catastrophic recon mistakes → start over.** New cart UI button
   ("Start New Log") wipes the entire log. Simple but tough: if the
   operator botched a turn, they drive the whole path again. No
   partial delete on cart side. Pull the log to Excel BEFORE
   pressing if you want to keep the wobbly run for any reason.

2. **Wobbly turns that should have been one arc → smooth.** Operator
   highlights rows in CartLog sheet, clicks Smooth. Excel proposes a
   single arc fitting the selection's start (x, y, θ) and end
   (x, y, θ). Operator accepts or rejects.

**Architectural notes (day 9 late evening):**

- *"A straight line is a series of curves"* — no special case for
  straight. Everything is an arc. Δθ ≈ 0 → large radius → near-zero
  steering → effectively straight. Same maths handles both.
- Operator does NOT override end point. Smooth accepts what was
  driven, just cleaner. If the operator wanted to end somewhere
  else, they should have driven there.
- Deviation threshold defaults to HIGH per architectural principle
  #2 ("variance easy fixed in post"). Operator only worries when
  arc proposal genuinely misses the path.
- Depends on SERVO_TO_DEG calibration (workfront #29) being
  accurate enough that proposed steering δ_servo actually produces
  the predicted arc when executed. Coarse calibration is fine for
  the visualisation/smoothing structure (build #44 today). Tight
  calibration (from #29's full circle / linearity / symmetry tests)
  needed before COMMITTING executed Plans. Operator-facing turn
  advice (#29a) and #44's maths both draw from the same #29
  measurement table — consistent story.

**Workfronts:**

43. **Cart UI "Start New Log" button (firmware).** New endpoint
    `/cartlog/clear` or similar. Cart UI page gets a button that
    POSTs to it, clearing the in-RAM cart log buffer. Same effect
    as the existing `/cartlog` retrieve-and-clear, but without
    requiring an Excel-side retrieve first — useful when operator
    wants to abandon recon without saving.
    Confirm: the existing `/cartlog` retrieve already clears the
    buffer (per Cart.bas comment header). New button is for
    abandon-without-save case.

44. **Smooth Selection in CartLog (Excel).** **REJECTED day 10
    after build + test.** See day-10 update at top of file.
    Built end-to-end (`Smooth.bas`, two-stage commit, chart
    overlay) and proved working: rows 5-8 fumbled bend gave
    R=9.3m, deviation 544mm; rows 8-11 wobbly straight gave
    R=97.9m near-straight (correctly identifying intent). Commit
    deleted in-between rows, re-integrated cleanly. Rejection
    reason is not a bug — it's that smoothing rows i..j shifts
    downstream rows' (x, y) positions by the (x_end, y_end)
    mismatch from the single-arc fit, and operator's mental
    model "what I selected is what I changed" breaks. Knock-on
    drift would propagate across plan. Original code archived;
    can be revived if multi-arc fitting becomes desirable later
    (no immediate driver).

44a. **Deviation calculation helper (Excel).** **REJECTED day 10**
     with #44. Was built in `Smooth.bas` as `EstimateDeviation`.

44b. **Plan sheet for smoothed segments (Excel).** **RESOLVED
     differently day 10**: CartLog *is* the Plan. No separate
     sheet. Operator edits S-event speed values in-place; cart
     POSTs the (lightly-edited) CartLog directly to `/plan/load`.

44c. **Chart: wobbly trace + smooth proposal overlay (Excel).**
     **REJECTED day 10** with #44. Was built as overlay series in
     `Smooth.RefreshChartWithOverlay`.

45. **Speed editing in CartLog (NEW day 10).** Operator edits the
    Value column of S events in CartLog to set per-segment
    execution speeds (typical: 5 m/hr for photographable sections,
    10 m/hr for transitions, slower for tight turns). In-place
    cell edits, no maths. Then POST the lightly-edited CartLog to
    `/plan/load`. Open question: does today's `/plan/load` segment
    format (`TYPE,VAL,STEER,SPEED,END`) accept per-segment SPEED
    overrides cleanly, or does the cart firmware need an update
    to honour the values? Check Cart firmware side before assuming.

46. **Gimbal authoring against cart row labels (NEW day 10).**
    Re-frame of the earlier #13 GimbalPlan schema discussion (day
    10 morning, before #44 rejected). GimbalPlan rows reference
    CartLog row labels directly:
    - `W_start` = CartLog Excel row number (matches the chart's
      row-number label)
    - `W_end` = CartLog Excel row number
    - Other columns per #13 morning sketch (Type, Yaw_in/out,
      Pitch_in/out, Duration_s, Ease_style, computed t_start_ms /
      t_end_ms / Audience_frames, Notes)
    No separate CartPlan sheet — CartLog is the cart spine.
    Operator looks at chart, sees label "8" on the curve, references
    W_start=8 in GimbalPlan. Visualisation-driven authoring.
    Depends on: pano master config from Settings (workfront #33
    pre-resolved this), Astro.bas for track-row endpoints (#14a).

## Open design decisions

- ~~"Stage 4" milestone definition: bundle hardware opto fix +
  time-based fetch + production-envelope soak test?~~ **RESOLVED
  Day 12.** Opto piece falls away (pulse-width fix made it
  unnecessary). Time-based fetch (#16 / #36c) deleted — current
  every-Nth-photo cadence delivers 100% and the resilience
  behaviour (skip-2-on-fail) is intentional. Stage 4 reduces to a
  single item: production-envelope soak (multi-hour
  sunset+sunrise) to confirm the 200ms fix holds across a real
  shoot.
- Sunrise transition table (only sunset table reviewed to date).
- Moon tracking in scope or out of scope for the gimbal Plan?
- ~~Logic-analyser-first vs opto-first ordering?~~ **RESOLVED
  Day 12.** Analyser-first was correct — comparing the
  intervalometer trace against the Uno+opto trace surfaced the
  pulse-width gap. The opto was never the problem.
- Two reserved per-row inputs in Gimbal UI — TBD.
- Velocity-band thresholds (0.05 / 0.3°/s) — confirm in practice;
  adjustable if first shoots suggest otherwise.
- Stream size for /plan/load — JSON or binary? Uno R4 SRAM tight
  after recent additions; consider chunked POST.
- m_per_step canonical value: 1.77 µm/step or wait for circle-test
  cross-validation before committing?
- Front_steps logging: keep on by default, or only enable for
  calibration runs (small SRAM cost)?
