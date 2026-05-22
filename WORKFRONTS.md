# HyperLapse Cart — Open Workfronts

**As of:** Session C day 15, 22 May 2026

This file lists work surfaced but not yet executed. Each item
references which session/day raised it. Prioritise per shoot
calendar.

Older session detail (days 6–11 workfront narratives) lives in
`WORKFRONTS_old_ver1.md`. This file keeps only open items, plus
one-line stubs for resolved/rejected ones to preserve traceability.

---

## Comms-outage fallback architecture (Day 15 — resolved)

Step 4 of #36d originally said "TABLE walks the table actively
pushing Tv/ISO PUTs at row boundaries." Day-15 discussion
identified this as a logical impossibility — if CCAPI is
unreachable (which is why we're in TABLE), the cart cannot push
Tv/ISO changes to the camera.

Reframed as a layered fallback problem, then narrowed by
operator's risk assessment.

**Risks classified:**
- Camera-side WiFi failure: accepted (Step D handles)
- Cart-side WiFi failure: accepted (rare; pin-8 keeps firing)
- External AP failure: accepted (pin-8 + TABLE keep photos
  delivered; only operator UI capability is lost)

**Architecture as it stands:**

**Production v1 (current, sufficient for now).** External WiFi
(Rosedale / field router) is the working comms path. When it
fails — for any of the three reasons above — pin-8 keeps
photos firing (Fallback 1), Step D detects the outage, and
TABLE mode runs cart-side exposure walk. Camera stays frozen
at flip-time Tv/ISO; photos are over/underexposed during
outage; LRTimelapse fixes drift in post. The full shoot is
delivered. Architecture is robust. Some risk is accepted by
design.

**Production v2 (future improvement, not blocking).** Move
the camera link to wired Ethernet point-to-point. Camera WiFi
disabled, external WiFi never reaches the camera. Cart still
uses external WiFi for operator UI / Excel only. Tracked as
#47. Optionally drops pin-8 in favour of CCAPI HTTP shutter
over the wire (architectural principle #12 would retire).
Camera-as-AP and USB+Pi+EDSDK options are no longer in the
running — wired Ethernet is structurally cleaner.

#36d Step 4 is closed by this framing. v1 already handles the
outage cases acceptably; v2 explores improvements.

---

## Day 15 update (added 22 May 2026)

Build session. #36d Step D (TABLE → LIVE recovery) delivered and
end-to-end verified. Three Day-14-era bugs surfaced and fixed
during the build (see PROJECT_STATE day-15 entry for detail).

**Headline:** TABLE is no longer one-way per shoot. WiFi outage
mid-shoot now triggers FLIP to TABLE, photos continue on
step-function exposure, every 60s a 1s ping checks if comms are
back; on success the cart returns to LIVE and the standard
luminance walk nudges Tv/ISO back into the dead zone. 64/64
photos delivered across a full WiFi-off-then-on cycle.

**New principle reinforced:** once in TABLE, no CCAPI call should
originate from the cart except the Step-D ping. Gates applied at
every origination site (fetch arm, fetch service, PROBING entry).
Architectural rule, not a defensive patch.

---

## Day 14 update (added 21 May 2026)

Build session. #36d Table Mode + comms-recovery state machine
delivered and end-to-end verified. See PROJECT_STATE day-14 entry
for full detail.

**Headline:** photos sacred verified through CCAPI outage. 14/14
delivered. 1 photo delayed 12s on discovery, 3 photos delayed 1s
during probe phase, post-TABLE-flip cadence clean.

**Day-15 part 2 (architectural):** v1 (current Uno R4 + all-WiFi)
declared production; sketch branched to `DJI_Ronin_UnoR4_v1prod.ino`
(bug-fix only) and `DJI_Ronin_Giga_v2dev.ino` (v2 dev starting
point). v2 = Giga R1 + Arduino Ethernet Shield 2, wired Ethernet
point-to-point to camera, camera WiFi disabled. v2 build absorbs
#22 Giga migration. Excel/UI shared across v1 and v2.

**New follow-ups added** (see #36d entries below):
- TABLE → LIVE recovery within a shoot (Step D, not yet built)
- TABLE per-cycle PUT logic (Step 4 of original Day-13 plan,
  design question added)
- Dead-state cleanup from removed Day-12 logic (low priority)

**Mental model retired:** "CCAPI activity stresses the camera" was
Day-11 thinking, traced to 100ms pulse width (fixed Day 12). The
constants built around being polite (`LUM_LIVEVIEW_RETRY_MS`,
`FETCH_FAIL_BACKOFF_CYCLES`, `LUM_FAIL_THRESHOLD`) were solving a
phantom; now gated or zeroed.

---

## Day 13 update (added 21 May 2026)

Two design resolutions in one session, both pure design (no code).

### #40 BNO085 integration architecture resolved (all six questions)

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

### #36d remaining subtasks resolved (Table Mode + Δt_rel offset)

- **Outage detection:** 3 consecutive fetch fails → TABLE mode;
  3 consecutive fetch successes → back to LIVE. Symmetric
  threshold. Grounded in Appendix A data (peak rate 1/3 stop
  per 60s, 3-miss-window ~18s well inside tolerance).
- **Recovery smoothing — eliminated.** Monotonic per-phase walk
  + post-fix in LRTimelapse makes smoothing both unnecessary and
  counter-productive (delays return to truth). Not deferred —
  removed entirely.
- **Tv-format Canon translation — stale.** Cart already has
  `TV_LADDER[]` (line 414, 60 Canon-format strings); Excel
  pushes Appendix A in Canon format; verified Day 12. No work.
- **Photo-loop integration:** new `exposure_mode` flag
  (LIVE / TABLE). Photo loop untouched. "Formula" in the cart
  is actually a step-function lookup table → renamed concept
  to **Table Mode**.
- **Δt_rel offset** (the key insight): at LIVE → TABLE handoff,
  find table row matching `current_tv`; from then on, lookups
  use `t_rel_now + Δt_rel`. Preserves the CCAPI loop's
  accumulated wisdom about today's specific sky (e.g. an extra
  stop slow because afternoon was overcast). Zero jolt at
  handoff by construction.
- **TABLE → LIVE return:** discard Δt_rel, existing
  `adjustExposureByLuminance()` does one-step-per-fetch
  catch-up walk. That walk IS the smoothing.
- **Edge cases — closed without separate design pass.**
  Candidates are implementation details, not design questions;
  handle at build time per PREFERENCES discipline.
- **Held over for build session:** exact `current_tv` →
  table-row matching when no exact string match; whether ISO
  shares Tv's Δt_rel; where wild-CCAPI rejection
  (EXPOSURE_FALLBACK §6.6) sits.

See PROJECT_STATE day-13 entry for full detail on both designs.

---

## Open workfronts — cart firmware

**#5a Segment dispatcher + cubic evaluator.** ~50 lines C. Segment
types: HOLD, LINEAR, CUBIC (Catmull-Rom as standard cubic
coefficients), PANFOLLOW. Per tick: eval at (now - t_start),
quantise to 0.1°, accumulator-driven setPosControl. Day 8 design;
not yet built.

**#36d Table Mode + comms-recovery (DAY-15 STEP D COMPLETE).**
Architecture from Day 13. Build delivered Day 14. Step D recovery
delivered Day 15. End-to-end verified across two test cycles
(Day 14: LIVE → TABLE; Day 15: full LIVE → TABLE → LIVE).

Built:
- `exposure_mode` (LIVE/TABLE), `comms_mode` (NORMAL/PROBING)
- `findTableRowForTv()` with seconds-based comparison + 0.5% epsilon
  (handles Excel decimal vs Canon-format Tv strings)
- LIVE → TABLE handoff with `Δt_rel` capture, `last_table_tv/iso`
  seeding
- Comms-recovery state machine: any CCAPI connect-fail → PROBING;
  ping (1s, `WiFi.ping()`) every 3rd photo BEFORE pin-8 fires;
  3 ping fails → TABLE; ping success → NORMAL
- `tryStartLiveviewIfNeeded` gated on NORMAL + LIVE; ANCHOR call
  gated on NORMAL
- TABLE-mode gates at every CCAPI origination site
  (`lum_fetch_pending` arm, fetch service block, PROBING entry
  in ccapiRequest) — once in TABLE, only Step D's ping can move
  the cart out
- **Step D (Day 15):** 60s wall-clock TABLE-side ping probe;
  merged probe-fire block with explicit `from_table`
  classification; on success → `exposure_mode = LIVE`, discard
  `Δt_rel`, invalidate `lum_liveview_started` so a fresh
  `/liveview` POST restarts the histogram session
- `/debug/match`, `/debug/ping` endpoints for diagnostics
- `/exposure/state` returns full mode + probe + comms state

Not yet built (and acceptable for production):
- **TABLE per-cycle PUT logic (Step 4 of original Day-13 plan).**
  Cart enters TABLE and reports the mode + offset, but doesn't yet
  walk the table actively pushing Tv/ISO PUTs at row boundaries.
  Currently camera stays at whatever Tv/ISO it had at the moment of
  flip. For brief outages this is fine; for sustained outages
  exposure will drift unfixed. Build: per-cycle compute
  `formulaTv(t_rel + Δt_rel)`, `formulaIso(...)`, compare to
  `last_table_tv/iso`, PUT only when changed (i.e. table row
  crossed). The PUT needs to happen via CCAPI which is unreachable
  in TABLE state — this is the contradiction that needs design.
  Day-15 added rule "no CCAPI call from TABLE except Step-D ping"
  sharpens this: Step 4 may now be re-scoped or rejected entirely,
  since LRTimelapse can fix the smoothed exposure walk in post.

**#36d cleanup (low-priority).** Dead state vars from removed Day-12
logic: `consecutive_fetch_fails`, `consecutive_fetch_successes`,
`lum_consecutive_conn_fails`, `lum_in_outage`,
`lum_fetch_skip_remaining`, `LUM_FAIL_THRESHOLD`,
`FETCH_FAIL_BACKOFF_CYCLES`. All sitting at 0 / dead-branch. Remove
when convenient. Also `MODE_FLIP_THRESHOLD` and `PROBE_COUNT` are
semantically the same (3) — consolidate or document.

**#36d follow-up: TABLE-during-comms-dead semantic question
(CLOSED Day 15).** Question was: in TABLE, should we PUT Tv/ISO
to the camera over CCAPI (which we can't reach), or just walk
the table cart-side and let the camera stay frozen? Resolved
by the camera-as-AP decision (see fallback architecture
section above): with the external AP removed, the only outage
mode is camera-side WiFi failure (accepted risk, rare). When
that happens, TABLE walks cart-side state only; camera stays
frozen; LRTimelapse fixes drift in post. (a) accepted.

**#47 Production v2 — wired Ethernet to camera (FUTURE,
not blocking).** v1 (current all-WiFi via external AP) is
sufficient. v2 reduces comms risk fundamentally by moving
the camera link to a wired Ethernet point-to-point.

**Hardware (chosen Day 15):**
- Arduino Giga R1 WiFi (already on hand — was held in
  reserve per #22)
- Arduino Ethernet Shield 2 (W5500, $51.15 AUD from Core
  Electronics) — to buy
- Short Cat5e/Cat6 cable cart→camera RJ-45

**Board choice rationale.** Both Uno R4 + Shield 2 and Giga
R1 + Shield 2 work technically. v2 picks the Giga because:
- Giga is already on hand
- v2 is the natural trigger for #22 (Giga migration). Per
  architectural principle #14, Giga activates only when a
  specific design need outgrows the Uno; v2's Ethernet
  stack + simultaneous WiFi STA for operator UI is the
  first design that materially benefits from Giga's headroom
  (1 MB SRAM, dual-core, more SPI ports, more flash)
- Going to Giga now avoids doing a board migration *after*
  v2 ships when something else outgrows the Uno

**#22 Giga migration is now part of v2.** No longer a
separate workfront — it's the migration step inside the v2
build. Port production sketch from Uno R4 (50% flash, 68%
globals) to Giga's STM32H747. Code is mostly portable;
attention needed on WiFi library, SPI assignment, pin
numbering, timer-based code (PIN8 PULSE timing, fetch
timing), and any AVR-specific bits if present.

**Topology:**
- Cart ↔ camera: Ethernet cable, CCAPI over the wire
- Camera WiFi: disabled, never used
- Cart WiFi: STA mode joining external AP, for operator UI /
  Excel only
- External WiFi never reaches the camera

**What this eliminates:**
- Camera-WiFi-off failure mode (no WiFi to fail)
- External-AP-to-camera failure path (doesn't exist —
  external AP only touches cart, not camera)
- Whole comms-outage architecture (TABLE mode, Step D) becomes
  irrelevant for normal operation. Could be retained as a
  belt-and-braces fallback for Ethernet-cable-fault, but the
  failure rate would be near-zero.

**What survives unchanged:**
- External WiFi for operator UI / Excel plan push. If
  external AP fails, operator loses visibility but photos and
  exposure tracking continue unaffected.
- Continuous power cable to camera (already in place).
- Day-15 reliability claims for CCAPI hold over Ethernet —
  same HTTP, same endpoints, same protocol.

**Additional simplification (operator's call):** drop pin-8
firing entirely, fire shutters via CCAPI HTTP over the wire.
- Removes the pin-8 cable from cart to camera N3 port
- Single comms path for both shutter and exposure control
- Photos-sacred guarantee transfers from pin-8 hardware to
  Ethernet+CCAPI reliability — acceptable because wired link
  is more reliable than WiFi by a wide margin
- Permanent / keep-alive HTTP connection avoids per-photo
  connect overhead and detects link loss immediately on
  write failure
- Latency variability vs pin-8: not a concern at 1320×
  audience speed; sub-frame jitter doesn't show
- Architectural principle "Pin-8 must work when CCAPI is
  unreachable" (PREFERENCES #12) becomes obsolete and would
  be retired

**What needs to be checked / built:**
- Hardware: W5500 SPI Ethernet shield or module on the Uno
  R4. Cat5e/Cat6 short cable to camera RJ-45.
- Coexistence: WiFiS3 (uses SPI) + W5500 (uses SPI) on
  different chip-selects — should be fine, verify
- CCAPI over Ethernet: confirm Canon CCAPI behaviour
  identical to WiFi (expected per Canon docs, R3 spec lists
  Ethernet as supported CCAPI transport)
- CCAPI shutter timing: measure cadence variance via HTTP
  shutter call, compare to pin-8 baseline (Day-12-style
  oscilloscope approach)
- Keep-alive strategy: persistent TCP connection across the
  shoot, write-fail detection as immediate outage signal
- Camera config: disable WiFi, enable Ethernet network mode,
  configure static IP on the camera-cart subnet

**Decision deferred to when v2 is actually wanted.** Real-world
v1 experience will tell us how often external AP issues
actually bite. If they're rare, v1 stays. If they're common,
v2 (wired Ethernet) is the chosen path. Camera-as-AP and
USB+Pi+EDSDK options from earlier Day-15 research are no
longer in the running — wired Ethernet is structurally
cleaner than either.

**#40 BNO085 integration (build phase).** Architecture resolved
Day 13 (see above). Build work pending:
- UART-RVC wiring on production cart (Serial1, 3.3V, GND, TX, RX)
- Ring buffer + sample averaging
- Plan stream extension: anchor flag, threshold,
  expected_cart_heading, per-segment frame tag
- `gimbal_yaw_correction` scalar + cubic-eval application
- Two-attempt retry logic at 500mm / 400mm before waypoint
- CartLog event type `A` (A_OK / A_SKIP / A_FAIL)
- `/debug/imu` endpoint (offset, acc, raw_yaw, true_yaw)
- Excel-pushed offset via Settings (named range `bnoOffsetDeg`)

**#43 Cart UI "Start New Log" button.** New endpoint
`/cartlog/clear` (or similar). Cart UI button POSTs to it,
clearing in-RAM cart log without requiring Excel-side retrieve
first. Existing `/cartlog` retrieve-and-clear stays; this is for
abandon-without-save. Promoted in importance Day 10 (with
Smooth Selection rejection, redrive is the correction mechanism).

**#45 Speed editing in CartLog — firmware side check.** Operator
edits S-row Value column to set per-segment execution speeds (5
m/hr photographable, 10 m/hr transitions). Open question: does
today's `/plan/load` segment format (`TYPE,VAL,STEER,SPEED,END`)
accept per-segment SPEED overrides cleanly, or does cart firmware
need an update? Verify before extending Excel side.

---

## Open workfronts — cart UI

**#10a Gimbal UI page.** Separate URL on cart web server
(suggestion `/gimbal`), parallel to existing `/` cart UI.
Field-side Plan-row editor. See GIMBAL_VIZ.md §3 for layout.

---

## Open workfronts — WiFi / RF link

**#22 Port cart firmware from Uno R4 to Giga R1.** ABSORBED
INTO #47 v2 BUILD (Day 15). Uno is not the blocker yet, but
v2's Ethernet+WiFi simultaneous use is the first design that
materially benefits from Giga's headroom, and doing the
migration as part of v2 avoids a separate later migration.
See #47 for details. Current Uno at 50% flash, 68% globals.

**#23 Cart antenna upgrade.** Hardware on hand; mast work
pending. Day-12 added constraint: mast fold mechanism needs
repeatable hard-stop in shoot-up position so BNO085 hard-iron
calibration survives transport/deploy cycles.

**#24 Cart antenna placement.** Mast specs refined Day 12:
350mm useful length from cart deck to IMU mount, plus enough
above the IMU for the antenna. Stiffness: rod-style ≥10mm
fibreglass, or PVC pipe with wall thick enough to not sway
visibly on cart start/stop. Non-metallic throughout.

**#25 Wired backhaul setup.** Lay 60m Cat6 van AP → field AP.
Confirm cable on hand. Field-test deferred until antenna work
above is done.

**#26 WiFi diagnostic instrumentation.** Oscilloscope philosophy
applied to RF link — log RSSI, retry counts, link quality per
fetch. Design ready, not built.

---

## Open workfronts — Excel

**#13 New Plan sheet schema.** Interleaves cart movement/stop
rows with gimbal pan-follow/astro-target/manual-waypoint rows.
Single shared timeline. Push to cart via `/plan/load`.

**#14 Catmull-Rom evaluator (Excel-side).** Excel evaluates the
spline densely, packs cubic coefficients per segment, POSTs to
cart. See GIMBAL_VIZ.md §8.

**#14a Astro endpoint computation.** For each "track sun / moon
/ milky" Plan row, evaluate astro formulas (existing Astro.bas)
at row_start_time and row_end_time. Computed (yaw, pitch) become
spline waypoints alongside manual waypoints.

**#14b Spline waypoint sequence assembly.** Build ordered
waypoint list from: operator-placed manual, computed astro track
endpoints, hold positions (repeated waypoints), phantom
waypoints for explicit transition rows.

**#14c Cubic-coefficient packing.** Each spline segment becomes
a parameter block for cart: `(type, t_start_ms, t_end_ms,
coefficients...)`. Compact binary or JSON for /plan/load POST.

**#15 Gimbal Plan XY chart with velocity bands.** yaw cumulative
(X, −380° to +70° span) × pitch (Y, 0°-90°, dashed at 80°).
Catmull-Rom spline through waypoints. Colour bands per
GIMBAL_VIZ.md §7. Plus execution-feasibility warning when
utilisation exceeds 0.5.

**#15a Audience-frame display for ease durations.** When
operator sets an ease duration, Excel shows audience-frame count
at 60fps × 1320× speedup.

**#46 Gimbal authoring against cart row labels.** GimbalPlan
rows reference CartLog row labels directly (W_start = CartLog
row, W_end = CartLog row), no separate CartPlan sheet. Operator
looks at chart, sees row-number label on the curve, references
in GimbalPlan. Visualisation-driven authoring. Depends on pano
master config (#33 resolved), Astro.bas (#14a).

---

## Open workfronts — Excel exposure / validation

**#37 Post-timelapse import workflow.** Single-pass workflow
that ingests EXIF data, validates against branch, saves CSV.
See EXPOSURE_FALLBACK.md.

**#38 Refit session.** DEFERRED until CCAPI shoots exist (weeks
to months away). Aggregate has zero CCAPI-driven data today;
nothing to refit yet. CSVs are forward-compatible.

**#39 EXPOSURE_FALLBACK.md upkeep.** "Shoots reviewed" log
within the doc, updated after each post-timelapse import.

---

## Open workfronts — calibration

**#18 Straight-line test at slow speed (2-3 m/hr).** Verifies
behaviour at slowest operating speed (production exec is 5 m/hr).

**#19 Acceleration overhead test.** Time a longish 5 m/hr run
from cold start, compare clock to distance ÷ speed. Result
folded into Plan time estimates as a constant overhead.

**#20 Circle test.** Set servo to known angle, drive a full
circle, measure radius vs prediction. Cross-validates m_per_step
(slip vs deflection vs diff-ratio distinguishing factor) AND
servo-to-wheel calibration AND cart yaw rate. Also feeds #29.

**#21 S-bend test.** Only if straight + circle don't match
bicycle model.

**#29 Refine servo-to-wheel calibration.** Day-9 quarter-turn
gave first numbers; full circle + linearity + symmetry tests
needed before COMMITTING executed Plans. Coarse calibration OK
for visualisation/smoothing structure.

**#29a Operator-facing turn advice.** Draws from same #29
measurement table; "for a tight turn, set servo to N".

**#30 Cart log buffer size.** Day-9 Test 3 hit CART_LOG_MAX=64
during a long recon. Need a bigger buffer or streaming. Options:
SD card, streaming to Excel, or Giga migration (#22).

**#31 Plan nudge endpoint + UI.** Design ready, not built.
Operator nudges a running plan: adjust timing, skip a row, etc.

**#32 't' event integration into BicycleModel.bas.** Day-9
firmware addition lands a `t` (steering ramp) event in CartLog;
BicycleModel.bas needs to integrate it properly.

---

## Open workfronts — gimbal Plan additions

**#33 Panorama row type — Plan and Execution.** Day-9 evening
design + bench build. Pano firmware finalised. Master config
resolved. Master config defines pano cell yaws/pitches; per-row
choose which cells fire.

**#34 Gimbal settle time measurement.** Pano design assumes 1s
settle between cells; measure actual settle for confidence.

**#35 Operator "PANO NOW" trigger during execute.** Unplanned
pano injection from cart UI during plan execution. Design only.

---

## Open workfronts — heading + gimbal stream

**#40 BNO085 integration.** See "Cart firmware" section above
for the full build-phase task list. Architecture resolved
Day 13 (see top of file).

**#41 iPhone compass heading anchors at waypoints.** Storage in
plan: new column on Sequence sheet, `Compass Heading (°N true)`,
blank = no anchor. Workflow modes: pre-planned (operator scouts,
reads iPhone, types values) and in-field (operator captures at
each waypoint during recon). Complementary to #40 BNO anchors —
operator-in-the-loop absolute reference vs IMU-driven.

**#42 Gimbal CAN command stream update rate sizing.** Cart
streams pose updates to gimbal via CAN. Sizing study: how often
is fast enough for smooth motion? Defer until first prototype
running.

---

## Open design decisions

- Sunrise transition table (only sunset table reviewed to date).
- Moon tracking in scope or out of scope for the gimbal Plan?
- Two reserved per-row inputs in Gimbal UI — TBD.
- Velocity-band thresholds (0.05 / 0.3°/s) — confirm in practice;
  adjustable if first shoots suggest otherwise.
- Stream size for /plan/load — JSON or binary? Uno R4 SRAM tight
  after recent additions; consider chunked POST.
- m_per_step canonical value: 1.77 µm/step or wait for
  circle-test cross-validation before committing?
- Front_steps logging: keep on by default, or only enable for
  calibration runs (small SRAM cost)?

---

## Stage 4 milestone

Reduced to a single item Day 12: **production-envelope soak**
(multi-hour sunset+sunrise) to confirm the 200ms pulse-width fix
holds across a real shoot.

---

## Closed items — one-line stubs

Full detail in `WORKFRONTS_old_ver1.md`.

- **#1 Replace optocoupler** — Day 12 resolved; opto innocent,
  not needed.
- **#2 Buy USB logic analyser** — Day 12 done.
- **#3 Post-opto Tv=0.8"+2s re-test** — Day 12 superseded by
  Tv=0.5"+2s at 100% delivery.
- **#4 rear_steps in CartLogEntry** — Day 8 done (front_steps
  also added for diagnostic).
- **#5 Plan endpoints** — Day 9 done (`/plan/load`,
  `/plan/start`, `/plan/stop`, `/plan/status`).
- **#6 Heading anchor endpoint at runtime** — Day 8 removed
  (Excel pre-bakes).
- **#7 Cart-θ integration during drives** — Day 8 removed.
- **#8 Port astro maths to C** — Day 8 removed.
- **#9 ±450° cumulative yaw** — Day 12 done via Settings
  envelope (`gimbalYawEnvelopeMin` / `gimbalYawEnvelopeMax`,
  default ±225°).
- **#10 setSpeedControl wiring** — Day 8 removed.
- **#11 Bicycle integration: Log → (x, y, θ) trace** — Day 8
  done via `BicycleModel.bas`.
- **#11a Control-sheet handler row for IntegrateBicycle** —
  Day 8 done in-session, note in README.
- **#12 Inverse fitting: trace → smooth Plan** — Day 10
  rejected with #44 cluster.
- **#16 Time-based luminance fetch** — Day 12 deleted (current
  every-Nth cadence + skip-2-on-fail resilience is enough).
- **#17 Straight-line test at 5 m/hr** — Day 8 done.
- **#27 WiFi unresponsiveness under UI polling** — Day 9
  resolved via avoidance.
- **#28 Front step counting on arcs diagnostic** — Day 9
  characterised.
- **#36 / #36a Simple fallback formula (Excel side)** — Day 9
  late evening done.
- **#36b Formula evaluator on cart** — Day 12 done; Excel
  pushes Appendix A via GET query (~1.3 KB inside 1.5 KB
  envelope).
- **#36c Time-based fetch (cart side)** — Day 12 deleted with
  #16.
- **#36d subtask 1 Time anchor on cart** — Day 12 done; cart
  advances sunset+sunrise trel in lockstep from millis base.
- **#36d Step D TABLE → LIVE recovery within a shoot** —
  Day 15 done; 60s ping probe in TABLE, on success → LIVE,
  liveview invalidated for restart, standard luminance walk
  nudges back into deadzone.
- **#44 Smooth Selection (Excel)** — Day 10 built end-to-end
  then REJECTED on operator-workflow grounds. Original
  Smooth.bas archived. New principle "Visualisation >
  Manipulation" added to PREFERENCES.
- **#44a Deviation calculation helper** — Day 10 rejected
  with #44.
- **#44b Plan sheet for smoothed segments** — Day 10 resolved
  differently: CartLog *is* the Plan.
- **#44c Chart wobbly trace + smooth overlay** — Day 10
  rejected with #44.
- **"Stage 4 milestone bundle"** — Day 12 reduced to soak only.
- **"Logic-analyser-first vs opto-first ordering"** — Day 12
  resolved (analyser-first was correct).
