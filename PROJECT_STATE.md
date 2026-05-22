# HyperLapse Cart — Project State

**Last updated:** 22 May 2026 (Session C day 15 — #36d Step D
built and verified end-to-end. Sketch then BRANCHED for v1/v2
production split: `DJI_Ronin_UnoR4_v1prod.ino` (v1, all-WiFi,
frozen except bug fix) and `DJI_Ronin_Giga_v2dev.ino` (v2,
Giga + wired Ethernet to camera, dev). v2 hardware chosen:
Giga R1 (on hand) + Arduino Ethernet Shield 2 (~$51 AUD).
v2 architecture: wired Ethernet point-to-point cart↔camera,
camera WiFi disabled, external WiFi for operator UI only.
v2 removes the only unacceptable failure mode (external AP
in camera comms path) and unlocks TABLE-mode camera
nudging that was impossible in v1. Excel + UI HTTP endpoint
surface shared across v1 and v2. #22 Giga migration
absorbed into v2 build. Step 4 of #36d permanently closed.
v1 sketch current at /mnt/user-data/outputs/.)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

Also upload `PREFERENCES.md`, `GIMBAL_VIZ.md`, `WORKFRONTS.md`, and
`EXPOSURE_FALLBACK.md` — working agreement, gimbal visualisation
design, open task list, exposure fallback design (with reference
table as Appendix A).

Older session detail (days 5–11) lives in `PROJECT_STATE_old_ver1.md`.
This file keeps only what the next session needs to read to start work.

---

### Day-15 part 2: v1/v2 architectural decision + sketch branch

After Step D verified, discussion widened to comms-outage
fallback architecture. Operator's risk assessment: external
WiFi failure is the only unacceptable risk; camera-side and
cart-side WiFi failures are accepted (rare, handled by
Fallback 1 + Step D).

Three options explored in research: camera-as-AP WiFi,
wired Ethernet point-to-point, USB+Pi+EDSDK. Wired Ethernet
chosen for v2 — structurally cleanest, removes the entire
camera WiFi path from the design, and (key insight) allows
TABLE-mode camera nudging that was impossible in v1.

v1 vs v2:

| | v1 (current) | v2 (future) |
|---|---|---|
| Board | Uno R4 WiFi | Giga R1 WiFi |
| Camera link | WiFi via external AP | Wired Ethernet direct |
| Camera WiFi | Used | Disabled |
| External WiFi | Cart + camera both use | Cart only (operator UI) |
| TABLE camera nudge | Impossible | Allowed |
| Excel/UI HTTP API | Shared | Shared (identical) |

v2 hardware: Giga R1 (on hand) + Arduino Ethernet Shield 2
($51 AUD). #22 Giga migration absorbed into v2 build.

Sketch branched:
- `DJI_Ronin_UnoR4_v1prod.ino` — v1 production, bug-fix only
- `DJI_Ronin_Giga_v2dev.ino` — v2 development starting point,
  same code, ported to Giga + W5500 Ethernet for camera

Both files include a header block stating which branch they
are, the architecture, and what TABLE mode does/doesn't do
in each version.

#36d Step 4 (TABLE actively pushing Tv/ISO to camera) is
permanently closed for v1 (logically impossible — CCAPI
unreachable when in TABLE). Re-opens as a build task in v2
because the wired link is independent of the WiFi outage
that caused entry to TABLE.

---

## Day-15 session — #36d Step D (TABLE → LIVE recovery)

Build session. Extends the Day-14 comms-recovery state machine
with a recovery path so TABLE is no longer a one-way trip per
shoot. Three rounds of test exposed two real bugs in the
adjacent Day-14 code that didn't surface in the Day-14 outage
test because that test cut WiFi mid-cycle in a different phase.

### What was built

**Step D scheduler + merged probe block.** Constants:
`TABLE_PROBE_INTERVAL_MS = 60000`. State: `last_table_probe_ms`.
Scheduler block inside the photo-fire branch arms `probe_pending`
once the wall-clock interval elapses while in TABLE+NORMAL. The
existing PROBING probe-fire block was merged into a two-source
form with explicit `from_table` classification (set when the
predicate matches, not derived after the fact), so a probe is
unambiguously one or the other.

**Recovery branch.** On TABLE-source ping success:
`exposure_mode → LIVE`, `exp_delta_t_rel = 0`, log discard,
invalidate liveview (see Bug 3 below). Standard
`adjustExposureByLuminance()` then nudges Tv/ISO back into the
dead zone via the one-step-per-fetch walk on the next fetch
cycle. No special recovery PUT needed — the dead zone is the
natural arbiter (if TABLE under-nudged, walk pulls it back; if
TABLE over-nudged, in-deadzone says wait).

**Recovery fail path:** stay in TABLE, scheduler re-arms after
another 60s. No fail counter (TABLE is already the failure
state).

### Bugs found and fixed mid-build

**Bug 1 — stale fetch firing after FLIP.** First Step-D test run
showed only ONE TABLE probe and no recovery despite WiFi
returning. Root cause: at the moment of FLIP, `lum_fetch_pending`
had already been set 3 photos earlier by the every-Nth scheduler.
After FLIP the code reset `comms_mode = NORMAL`, which opened the
fetch-service gate. The stale fetch then fired, hit a 10s
connect-fail, and re-entered PROBING — which suppressed Step-D
probes (their predicates require `comms_mode == NORMAL`). Fix:
gate both `lum_fetch_pending = true` assignment AND fetch
service on `exposure_mode != EXP_MODE_TABLE`. Belt-and-braces
on both arm and service sites.

**Bug 2 — re-entering PROBING from TABLE.** Even with fetches
gated, any other CCAPI call from inside TABLE could trip the
PROBING entry block (`comms_mode = PROBING`, `probe_pending =
true`). That would mask Step-D probes the same way. Fix: gate
PROBING entry on `exposure_mode != EXP_MODE_TABLE`. Once in
TABLE, no CCAPI failure can disturb state; only Step D's 60s
ping can move us out.

**Bug 3 — stale liveview session after recovery.** Second test
run got TABLE → LIVE flip cleanly but fetches afterwards
returned 503 forever (~250-700ms each, not the 10s connect-fail
pattern). Camera CCAPI was responding fine — but the
`/shooting/liveview` session expired during the outage. The
existing dead-liveview detector requires 3 *connection-level*
fails to invalidate `lum_liveview_started`; 503 is
application-level, doesn't increment. Result: cart kept asking
for a luminance histogram from a dead session and accepting the
503. Fix: on TABLE → LIVE recovery, set `lum_liveview_started
= false` and `lum_last_liveview_attempt_ms = 0`.
`tryStartLiveviewIfNeeded` then POSTs a fresh /liveview on the
next loop iteration. Single small addition to the recovery
branch.

### Verified end-to-end

WiFi-off-then-on test, single full cycle:

| Photo | Gap | Cause |
|---|---|---|
| #16 | ~10000ms | initial CCAPI discovery (10s connect-fail) |
| #18 | ~3020ms | PROBING probe attempt 1 |
| #21 | ~3019ms | PROBING probe attempt 2 |
| #24 | ~3035ms | PROBING probe attempt 3 → FLIP to TABLE |
| #25 onwards | 2000-2004ms | clean TABLE cadence, zero CCAPI |
| ~#55 | ~3023ms | Step-D probe → ping success → LIVE recovery |
| #56 onwards | 2000-2004ms | post-recovery, liveview restarted, fetches ok=Y |

**Photos delivered: 64/64. Zero dropped.** WiFi happened to come
back within the first 60s window, so only one TABLE probe fired
this test. Multi-probe TABLE cycle (longer outage) not
specifically exercised but mechanism is symmetric and tested
in pieces.

### Setup gotchas (re-discovered)

- `/exposure/init` must succeed before `/shutter/start` — it
  populates `current_tv`, which is a precondition for
  `tryFlipToTableMode`. Without it, FLIP returns "blocked:
  current_tv=(empty)" and the cart stays in LIVE forever
  through repeated CCAPI failures. Day-14 had this set up via
  the test harness; first Day-15 test ran with camera WiFi
  already off at init time, exposed the brittleness.
- Standard sequence reinforced: CCAPI alive check → init
  (verify Tv/ISO in response) → Push Formula to Cart (Excel) →
  exposure/target → shutter/start. Skipping any one of these
  produces a quiet failure mode later.

### Files modified this session

- `DJI_Ronin_UnoR4_v3.ino` — Step D scheduler + merged probe
  block + recovery branch with liveview invalidation; three
  TABLE-mode gates (fetch arm, fetch service, PROBING entry);
  comment header updated for Step D-built status.

### Mental model corrections recorded

- **Once in TABLE, no CCAPI call should originate from the
  cart.** Step-D's 60s ping is the sole permitted outbound
  CCAPI activity. Any other CCAPI call — stale fetch, anchor
  retry, liveview-restart, ISO PUT — risks the 10s connect-fail
  block and (worse) re-entry to PROBING that suppresses Step D.
  Gates on `exposure_mode != EXP_MODE_TABLE` apply at every
  CCAPI-call origination site, not at the request layer.
- **Liveview session state is camera-side, not cart-side.**
  `lum_liveview_started` is the cart's belief about the camera's
  session; it can go stale during outage even though
  WiFi-reachability looks fine afterwards. Recovery from outage
  must invalidate the cart-side belief. The existing
  connection-fail-counter doesn't catch 503-after-recovery
  because 503 isn't a connection fail.
- **Dead zone is the natural recovery arbiter.** Step D doesn't
  need to compute a "what should Tv/ISO be now" PUT at recovery
  — the next luminance fetch tells us whether TABLE under- or
  over-nudged, and the standard walk pulls back into deadzone
  either way. Symmetric with LIVE→TABLE: handoff is jolt-free
  by construction.

---


Build session. The Day-13 designs for #36d became code; the comms
failure handling around them was rebuilt from scratch when the
existing "be polite to recovering camera" approach proved fatal to
photo cadence during a real outage.

### What was built

**Step 1 — state vars + `/exposure/state` extension.** New: `exposure_mode`
(LIVE/TABLE), `consecutive_fetch_fails/successes`, `exp_delta_t_rel`,
`last_table_tv/iso`, `last_mode_change_ms`. No behaviour change.

**Step 2 — `findTableRowForTv()` + `/debug/match` endpoint.** Match
returns t_rel of the table row whose Tv value matches `current_tv`.
Comparison is by **seconds, not string identity**, with 0.5% relative
epsilon — handles Excel's decimal format ("0.5", "1.3", "20") matching
Canon's format ("0\"5", "1/250"). `tvStringToSeconds()` extended to
parse plain decimals and plain integers (previously only fractions and
quote-notation). Verified across all 5 Tv formats including realistic
miss case.

**Step 3 (built then rebuilt) — comms-recovery state machine.**
Originally wired `consecutive_fetch_fails` counter with 3-fail
threshold. Real-world test exposed the flaw: every failing CCAPI call
blocks the cart loop for 10s (library-level `client.connect()`
timeout, can't be shortened per PREFERENCES known quirk). At
`LUM_LIVEVIEW_RETRY_MS = 30000` the cart blocked 10s out of every 30s
during outage — visibly broken cadence. Dropping retry to 10s made it
worse (continuous blocking). The fundamental issue: we shouldn't be
calling CCAPI at all once we know it's down.

**Step 4 onward — comms-recovery redesign.** New state machine:

- `comms_mode` = NORMAL | PROBING
- On ANY CCAPI connect failure → enter PROBING
- During PROBING, replace the every-3rd-photo fetch with a 1s
  `WiFi.ping()` — runs BEFORE pin-8 fires, so camera is idle during
  the ping (verified per PREFERENCES: photo recovery window is for
  camera, not free cart time)
- On ping success → back to NORMAL
- On 3 consecutive ping fails → flip to TABLE mode

**Step 5 — old logic gated/removed.** `tryStartLiveviewIfNeeded`
now gated on `comms_mode == NORMAL` AND `exposure_mode != TABLE`. The
ANCHOR CCAPI call in `/shutter/start` skipped when comms_mode already
PROBING (saves one 10s block on initial discovery). Step-3 inline
fail counters in `ccapiRequest` and `ccapiStartLiveview` removed —
PROBING is single source of truth. `FETCH_FAIL_BACKOFF_CYCLES` dropped
from 2 to 0 (the "give camera recovery time" rationale was Day-11
era thinking).

### Verified end-to-end

Camera WiFi off mid-test, 14 photos through the full failure cycle:

| Photo | Gap | Cause |
|---|---|---|
| #1 | 12089ms | initial discovery, single 10s CCAPI block |
| #2-#8 | 2000-2004ms | normal cadence |
| #3, #6, #9 | ~3020ms | probe-delayed photos (+1s for ping) |
| #9 | — | TABLE flip captured `delta_t_rel=26865`, `last_table_tv="0\"5"`, `last_table_iso=200` |
| #10-#14 | 2000-2004ms | post-flip steady state, no CCAPI activity |

**Photos delivered: 14/14. Zero dropped.** Cart count and card count
match. The cost model from design (1×12s on discovery + 3×1s on
probes + 0 dropped) verified in real-world test.

### Key measurements taken this session

- `WiFi.ping()` cost: **~1015ms regardless of outcome** (live host
  1005ms with 219ms RTT; dead host 1015ms, never-existed IP 1015ms).
  The 1s flat cost is the design's foundation.
- `client.connect()` to dead CCAPI host: **10001-10009ms** (confirmed
  for fetch path and liveview-start path).

### Files modified this session

- `DJI_Ronin_UnoR4_v3.ino` — substantial: state machine, ping helper,
  match function, gates, debug endpoints. Compiles cleanly. Flash
  usage well within Uno R4 limits.

### Step D (future) — TABLE → LIVE recovery during a shoot

Not built. Currently TABLE is a one-way trip within a shoot: cart
stays in TABLE until `/shutter/stop` (or reset). Acceptable for
production because:
- Post-shoot, LRTimelapse fixes the smoothed exposure walk
- Most outages last longer than the remaining shoot anyway
- Recovery probe in TABLE would re-introduce periodic blocking risk

When/if needed: periodic ping in TABLE at low rate (e.g. every 30s),
on 3 consecutive ping successes re-enable LIVE. Lives in WORKFRONTS
as a follow-up.

### Loose ends to clean up later

- `consecutive_fetch_fails`, `consecutive_fetch_successes`,
  `lum_consecutive_conn_fails`, `lum_in_outage`,
  `lum_fetch_skip_remaining` — dead state vars, sitting at 0 doing
  nothing. Remove when convenient.
- `LUM_FAIL_THRESHOLD` constant — also dead.
- `FETCH_FAIL_BACKOFF_CYCLES` — set to 0, branch still in code, can
  be removed.
- `MODE_FLIP_THRESHOLD` comment still references "fetch fails";
  meaning has shifted to "ping fails" (now equivalent to
  `PROBE_COUNT`). Either consolidate to one constant or document.

### Files added/modified this session

- `DJI_Ronin_UnoR4_v3.ino` (cart sketch)

### Mental model corrections recorded

- **"Camera stress" from CCAPI activity is not real.** Day-11 "78%
  delivery under CCAPI load" was the 100ms pulse-width issue (fixed
  Day 12). CCAPI itself is reliable when WiFi is up. The constants
  built around "be polite to stressed camera" were solving a phantom.
- **WiFi outage is the failure mode that matters.** Camera down, AP
  reboot, signal drop. Camera-busy-vs-idle complications don't enter
  the picture because the failure is binary (packet gets through or
  doesn't).
- **The 1.5s photo recovery window is NOT free cart time.** Pings
  there assume camera doesn't mind concurrent network activity during
  card write. Untested. Probe placement moved to BEFORE pin-8 fire,
  guaranteeing camera idle during the ping. Costs +1s on probe photos,
  buys deterministic camera state.

---

## Day-13 session — two designs resolved (#40 BNO + #36d Table Mode)

Pure design session. No code changes. Two unrelated workfronts
moved from "architectural questions open" to "design complete,
ready for build."

### Part 1: #40 BNO085 integration architecture resolved

All six architectural questions raised in WORKFRONTS #40 are now
resolved.

### Anchor design (resolved Q1, Q4, Q6)

**Purpose.** Keep the gimbal's earth-frame output honest against
cart-heading drift. Nothing else. Cart position and cart path are
NOT corrected. The cart drives its pre-baked path blind, believing
it is heading where Excel assumed at authoring time. The gimbal —
which has real earth-frame work to do during astro-track and
earth-frame pan-to-point segments — gets the correction.

**Mechanism.**
- BNO085 samples continuously into a small ring buffer on cart
  (cheap, runs in background, no impact on photo loop)
- Plan rows can carry an `anchor` flag with a per-row threshold,
  authored in Excel
- When cart reaches an anchor-flagged row, it pulls a clean
  averaged BNO yaw from the buffer
- Compares to Excel's pre-baked `expected_cart_heading` for that
  row
- If `|delta| > threshold`, updates a running scalar
  `gimbal_yaw_correction`
- All subsequent earth-frame-tagged gimbal cubics evaluate as
  `at³+bt²+ct+d + gimbal_yaw_correction`
- Pan-follow segments untouched (chassis-frame, no correction
  applies)
- Correction never snaps — only affects computation of the *next*
  gimbal move, never any move in progress
- WiFi-independent during execution

**Plan stream changes required for #40 to land.**
- Per-row `anchor` flag + threshold value in plan
- Per-segment frame tag (`earth_frame` vs `chassis_frame`) on
  CUBIC and HOLD segment types in the existing Segment struct
- Per anchor-flagged row, Excel bakes `expected_cart_heading` so
  cart can compute delta

**Cart-side footprint.**
- Continuous BNO sampling into ring buffer (~tens of samples)
- One float `gimbal_yaw_correction` (updated only at anchor rows)
- Frame-tag check at cubic eval time, one branch
- No bicycle-model integration, no per-photo BNO reads, no astro
  math on cart — all consistent with day-7 / day-8 architectural
  rules

### Offset persistence (resolved Q2)

The `c`-capture true-north offset folds magnetic declination +
BNO mounting angle into one number. Bench test gave +9.16° for
Adelaide; expected declination is +8.11° (web-verified), implying
~+1° BNO mounting angle on the bench setup.

**Storage: Excel-pushed via Settings**, NOT cart EEPROM.
- Operator captures via cart `c` command after
  calibration-by-driving achieves acc≥2
- Reads value from `/debug/imu` endpoint
- Types into Excel named range (suggested: `bnoOffsetDeg`)
- Excel includes it in next Settings/plan push (alongside
  Appendix A, yaw envelope, etc.)
- Cart receives, stores in SRAM, applies to every BNO read
- Re-capture only when something physical changed (mount tweak,
  new location, BNO replacement)

**Rationale.** Cost analysis: EEPROM (8 bytes used of 8KB, ~10
lines C) and Excel-push (1 float in settings struct, 1 named
range) are about equal in machine cost. Excel-push wins on
**architectural consistency** — fits the existing Settings
envelope pattern (#9 yaw envelope, #36b Appendix A, etc.). The
"more steps per shoot" cost is small because the value rarely
changes — operator types it once, every plan push carries it.

**Sanity check (optional).** Excel can display
`expected = declination(lat,lng) + recorded_mount_angle` next to
the typed value. Operator sees if drift looks wrong before
pushing.

### Acc dropout handling (resolved Q3)

Cart may approach an anchor-flagged row with BNO acc<2 (RF
interference, ferrous transient, calibration degradation).

**Two-attempt retry inside one anchor row.**
- **Attempt 1:** 500mm before waypoint. Pull averaged yaw, check
  acc.
  - acc≥2 → use it. Update `gimbal_yaw_correction`. Log
    `ANCHOR_OK, row=N, attempt=1, acc=X, delta=+Y°`.
  - acc<2 → log `ANCHOR_SKIP, row=N, attempt=1, acc=X`. Wait for
    attempt 2.
- **Attempt 2:** 400mm before waypoint. Same logic.
  - acc≥2 → use it. Log `ANCHOR_OK, row=N, attempt=2, acc=X,
    delta=+Y°`.
  - acc<2 → log `ANCHOR_FAIL, row=N, both_attempts_acc_low,
    kept_correction=+Y°`. Carry on with previous correction.

Photos sacred throughout — neither attempt blocks the shutter
loop, both run from the background BNO sampler.

500mm/400mm are sensible starting values, tunable in firmware
later if real-world data suggests otherwise. The two attempts
give one short window for any transient interference to pass.

**Rationale.** Stale correction beats bad correction. The drift
error missed for one anchor cycle is the same magnitude already
tolerated between anchors.

### Cart→Excel feedback (resolved Q5)

Anchor results logged to CartLog as new event type `A`.
- Subtypes: `A_OK`, `A_SKIP`, `A_FAIL` (or single Type=A with
  status column — detail for build time)
- Fields: row#, attempt#, acc value, delta_deg, applied_correction
- Pulled via existing `/cartlog` endpoint — no new infrastructure
- Excel-side: parser splits Type=A rows into a dedicated
  AnchorLog sheet on import, keeping CartLog itself clean
- Trace chart can optionally mark anchor points (small icon at
  the row's (x, y) — green for OK, amber for SKIP, red for FAIL)

**Rationale.** Anchors are cart events. CartLog is the cart event
log. Existing pull mechanism handles them. Excel-side sheet split
keeps the visual clean for non-anchor analysis.

### What was NOT decided

- Stream format detail for per-row anchor flag + threshold +
  expected_heading — design at build time when /plan/load schema
  is touched anyway
- Frame-tag bit position in Segment struct — design at build time
- BNO ring buffer size and sample averaging window — sensible
  default ~3 sec, tune from real-world data
- Whether `A` events overload existing CartLog columns or add a
  status column — Excel-side detail, decide when building the
  parser

### Part 2: #36d remaining subtasks resolved (Table Mode + Δt_rel offset)

The four remaining #36d subtasks (after subtask 1 Time anchor was
done Day 12) all closed in this session. Two were stale or
eliminated; two were designed.

**Outage detection — resolved.**
- Cart counts consecutive luminance fetch outcomes
- **3 consecutive fetch failures** → LIVE → TABLE mode
- **3 consecutive fetch successes (while in TABLE)** → TABLE → LIVE
- Same fetch cadence both modes (every Nth photo, no separate
  probe schedule)
- Threshold grounded in Appendix A data: peak rate of change is
  1/3 stop per 60s in civil twilight; 3 missed fetches at ~6s
  cadence = ~18s gap = well inside the 60s tolerance window
- "3 fail, 3 success" symmetric thresholds — same number both
  directions, easy to reason about

**Recovery smoothing — eliminated, not just deferred.**
- The exposure curve is monotonic in one direction per phase
  (sunset darkens, sunrise brightens — `mode=darken` /
  `mode=skylight` set once at shoot start)
- LIVE mode walks one step per fetch in the configured direction
  via existing `adjustExposureByLuminance()` + `nextTv()` /
  `nextIso()`
- TABLE mode walks the table's own step-function in t_rel
- When TABLE → LIVE handoff occurs, the existing one-step-per-fetch
  walk IS the smoothing — no extra logic needed
- Smoothing the already-shot image is also pointless: exposure
  error is baked into the SD card the moment the photo fires;
  smoothing only delays return to truth
- Removed from subtask list; will not be built

**Tv-format Canon translation — stale subtask.**
- Cart already has a hard-coded `TV_LADDER[]` (line 414 of
  production sketch) with all 60 Canon-format Tv strings
  (`0"5`, `2"5`, `1/5000` etc.)
- Excel pushes Appendix A in Canon-format strings already
  (Day 12 verified end-to-end: 51/12/49/14 entries landed
  correctly)
- `ccapiPutTv()` handles JSON-escape of embedded `"` at send time
- No new translation work needed; subtask removed from list

**Photo-loop integration — resolved as Table Mode + Δt_rel
offset.** The hardest of the four; multi-step design.

*Mode shape:*
- `exposure_mode` flag: `LIVE` (default) or `TABLE`
- Photo loop untouched, fires shutter every interval_ms (sacred)
- Fetch path branches on mode but produces same output shape
  (a PUT, or no PUT)

*"Formula" is a misnomer.* Inspection of cart sketch lines 714
and 756 confirmed: `formulaTv()` and `formulaIso()` are
**step-function lookup tables**, not formulas. Walk ascending
t_rel array, first row where `arr[i].t_rel >= t` gives the Tv.
No interpolation. Renamed concept to **Table Mode** for clarity;
C identifiers (`formulaTv` etc.) left unchanged (working code,
not worth touching for a cosmetic rename).

*The Δt_rel offset (key insight):*
- CCAPI loop in LIVE mode walks Tv/ISO based on actual scene
  luminance. On a dull/dark afternoon, CCAPI might walk the
  cart to Tv=1/100 by the time t_rel says it "should" be at
  Tv=1/200 (one stop ahead of the clock-driven canonical curve)
- Blindly switching to `formulaTv(t_rel_now)` at handoff would
  undo that accumulated wisdom and jolt the exposure
- **Solution:** at LIVE → TABLE handoff, find the table row
  whose Tv matches `current_tv`. The t_rel of that row is the
  "effective t_rel" the CCAPI loop had walked the cart to.
  Compute `Δt_rel = matched_row_t_rel - t_rel_now`. From here,
  table lookups use `t_rel_now + Δt_rel`
- Properties: no jolt at handoff (first PUT matches `current_tv`
  by construction), preserves CCAPI loop's accumulated
  weather-correction, subsequent nudges follow the table's
  natural step intervals

*Per-cycle behaviour in TABLE mode:*
- Compute `target_tv = formulaTv(t_rel_now + Δt_rel)` and
  same for ISO
- Compare to `last_table_tv` (recorded at the previous TABLE-mode
  PUT, or at handoff)
- PUT only when the table actually crosses to a new value
  at the current offset-adjusted t_rel (i.e. only on row
  boundaries). Otherwise hold.
- This naturally paces nudges by the table's own intervals
  (60s in steep zones, hundreds of seconds in flat zones) —
  not by photo cadence
- Probe attempts (CCAPI fetches) continue at the existing every-3rd
  cadence; on the 3rd consecutive success, flip back to LIVE

*TABLE → LIVE handoff:*
- Δt_rel is discarded
- Next fetch reading drives one nudge in the configured direction
  via existing `adjustExposureByLuminance()`
- Subsequent fetches keep nudging until the reading lands in
  deadzone — may take several fetches if reality drifted
  while cart was in TABLE mode; that catch-up walk IS the
  smoothing

**Edge cases — closed without separate design pass.**
- "Edge cases" was Day-12 era language from the opto / pulse-width
  investigation, where electrical/timing edges under load were the
  thing to find. #36d has no analogous continuous parameter near a
  hardware limit — it's a discrete state machine with mode flips
  and a Δt_rel offset.
- Candidate edge cases (boot timing, t_rel boundaries, current_tv
  not in table, Tv-pinned-at-ceiling zone with ISO ramp, sustained
  outage, wild CCAPI reading, operator manual override) all have
  obvious handling paths and are implementation details for the
  build, not design questions.
- Per PREFERENCES discipline: address them at build time when each
  branch of the state machine is exercised against actual behaviour.
- Removed from subtask list.

### What was NOT decided (#36d)

- Exact `current_tv` → table-row matching logic when no exact
  string match exists (closest-by-EV is the obvious choice but
  not coded yet; decide when building)
- Whether ISO gets its own offset or shares Tv's `Δt_rel` (in
  the active Tv-walk zone, ISO is pinned at 100; only at the
  20s ceiling does ISO ramp; sharing the offset is likely fine
  but verify when building)
- Whether wild-CCAPI-reading rejection (>2 stops from prediction
  per EXPOSURE_FALLBACK §6.6) lives inside the LIVE mode loop or
  as a sanity gate at handoff time — build decision

### Files modified today

None. Design session only. Resolution captured in PROJECT_STATE
and WORKFRONTS.

---

## Day-12 session — Pulse width identified as root cause

The Day 11 hypothesis that "CCAPI activity stresses the camera and
causes drops" is overturned. The Canon R3 needs the shutter line
held LOW for ~200ms to register reliably; production's 100ms pulse
was at the edge, and any CCAPI-induced camera slowdown pushed a
fraction of triggers past the edge into drops.

Built `DropTest.ino` — a minimal fork of the production sketch on a
spare Uno R4 WiFi — to sweep variables independently. Key changes:
analyser marker pins on 2/3/5/6, /echo verification endpoint,
/debug/liveview_at_start?on=N flag for true zero-CCAPI baseline,
and pulse width raised to 200ms.

Results across 7 test runs proved:
- Pulse width is the cause (100ms → 53.8-70.4%, 200ms → 96-100%)
- CCAPI load is not the cause (200ms holds up under full Day-11
  stress condition: 37/37 = 100%)
- The opto path is innocent (200ms with intervalometer = 100%,
  200ms with Uno+opto = 96-98%)
- Production resilience verified: a real fetch timeout mid-run was
  handled cleanly, backoff applied, recovery automatic, and all
  photos still landed

See `DAY12_SUMMARY.md` for full data table, traces, and reasoning.

**Production fix applied and validated end-to-end:**
- `backupShutter()` micros window raised from `100000` to `200000`.
  One-line change to the production sketch (`DJI_Ronin_UnoR4_v3.ino`),
  with an 8-line rationale comment above the loop.
- Flashed to cart, ran the Day-11 stress condition end-to-end:
  Tv=0.5", interval=2000ms, mode=darken, luminance fetch every 3rd
  photo, live view active. 38 fires, 38 photos on card. **100%
  delivery.**
- PULSE log confirms full 200ms hold (`high=56820/56820`,
  `fire_us=203765`) — every readback sample HIGH across the window.
- `fetch attempts/successes/errors=12/12/0` — same CCAPI load as
  Day-11 Run #1 (which delivered 70.4%), now 100%.

The chronic 70-74% delivery issue in the 2-second zone is resolved.

**Workfronts resolved this session (key items):**
- #1 / #3 (opto swap, post-opto re-test) — innocent, not needed
- "Stage 4 milestone" reduces to production-envelope soak only
- "Logic-analyser-first vs opto-first" — analyser-first answered it
- #16 / #36c (time-based luminance fetch) — deleted
- #9 (±180° yaw → cumulative) — done via Settings envelope
  (`gimbalYawEnvelopeMin` / `gimbalYawEnvelopeMax`, default ±225°,
  450° span). GimbalPosition refuses out-of-envelope commands.
- #36b (Formula evaluator on cart) — Excel pushes Appendix A
  parameters via GET query (~1.3 KB URL inside the 1.5 KB envelope
  verified via /debug/urlsize). Cart stores ~1.4 KB RAM, walks
  parser matching Excel's UDF logic. Verified end-to-end with 9
  evaluation points + real Appendix A push (51/12/49/14 entries
  landed correctly). `/debug/formula` diagnostic endpoint retained.
- #36d subtask 1 (Time anchor on cart) — Excel sends both sunset
  and sunrise trel anchors plus astronomical-sunset crossover
  threshold (`t0ss`, `t0sr`, `cross`). Cart advances both in
  lockstep from millis base, picks active event by sunset-trel vs
  cross. One push covers a full sunset-through-sunrise shoot.
  Verified end-to-end. `/debug/trel` reports full state. Sketch
  now at 50% flash, 68% globals.
- #40 BNO085 first-light — Adafruit 4754 on Uno R4 over I2C,
  alive at 0x4A. Standalone `BNO085_BenchTest.ino` calibrates via
  figure-8 motion (acc=3 achievable), captures true-north offset
  against iPhone compass with single `c` command, tracks to
  within ±3° of iPhone across all four quadrants. Negligible
  error for 14mm lens (~3% of frame). NOT yet integrated into
  production sketch.

---

## Older sessions (archived)

Days 5–11 detail moved to `PROJECT_STATE_old_ver1.md`. One-line
stubs for reference:

- **Day 5** — Stage 3 Tv-driven cadence, body-read 30× speedup,
  fetch backoff, REQ-PHASES instrumentation committed.
- **Day 6** — PIN8 + PULSE instrumentation, cart-vs-camera
  cross-reference (uncommitted at end of day).
- **Day 7** — Cart Log/Plan/Execution architecture (pure design,
  no code).
- **Day 8** — Gimbal architecture overhaul; astro pre-baked in
  Excel, Catmull-Rom evaluated in Excel, cart sees cubic
  coefficients only. See GIMBAL_VIZ.md for the canonical version.
- **Day 9** — Servo-to-wheel calibration done; plan endpoints
  `/plan/load`, `/plan/start`, `/plan/stop`, `/plan/status`
  built and tested; UI polling fault resolved via avoidance;
  pano firmware built. Late evening: exposure cluster
  restructured around three-session model, FallbackFormula
  built + verified, exif_ingest.py + validate_exposure.py done.
- **Day 10** — Smooth Selection (#44 cluster) built end-to-end
  then REJECTED on operator-workflow grounds; CartLog became
  the Plan; new principle "Visualisation > Manipulation"
  (now in PREFERENCES). Kept: WobblyRecon.bas, BicycleModel
  Trace col H CartLogRow + chart row-number labels, SecToHms
  promoted Public.
- **Day 11** — Photo-drop investigation (later overturned by
  Day 12). Original CCAPI-stress hypothesis now obsolete.

---

## State of the system (current)

### What works (production)

- Stage 3 Tv-driven cadence
- 200ms shutter pulse — 100% delivery validated end-to-end (Day 12)
- Body-read 30× speedup, fetch backoff, REQ-PHASES instrumentation
- PIN8 + PULSE instrumentation
- Cart-vs-camera cross-reference workflow
- Intervalometer fallback (always reliable)
- Existing cart UI (btn1–21, /cartlog, /gimballog)
- Plan endpoints `/plan/load`, `/plan/start`, `/plan/stop`,
  `/plan/status` (Day 9)
- ±450° cumulative yaw via Settings envelope (Day 12)
- Formula evaluator + Appendix A push (Day 12)
- Time anchor on cart for sunset+sunrise (Day 12)
- TABLE → LIVE recovery within a shoot via 60s ping probe
  (Day 15) — Step D complete; TABLE no longer one-way per shoot

### What's tested

- Tv=0.5" + 2s + CCAPI + mode=darken + live view: 100% delivery
  (Day 12 end-to-end)
- LIVE → TABLE on CCAPI outage: 14/14 delivery (Day 14)
- LIVE → TABLE → LIVE full cycle with WiFi off/on: 64/64
  delivery (Day 15)
- Sketch utilisation: 50% flash, 68% globals on Uno R4 WiFi
- URL payload size envelope: 1.5 KB (verified via /debug/urlsize)
- BNO085 first-light: tracks within ±3° of iPhone compass across
  all four quadrants (Day 12 bench, not yet on production sketch)

### What's NOT tested

- Multi-hour production-envelope soak across sunset+sunrise
  (Stage 4 milestone)
- ANY of the cart Plan/Execution architecture under real load
  (endpoints exist, not exercised against a real plan)
- ANY gimbal Plan execution (design only, see GIMBAL_VIZ.md)
- BNO085 integration in production sketch (#40 design just
  resolved this session)

### Hardware notes

- Mast (#23/#24): mechanical work pending. New constraint added
  Day 12: needs repeatable hard-stop in shoot-up position so
  BNO085 hard-iron calibration survives transport/deploy cycles.
- Opto path: confirmed innocent on Day 12. Spare 4N25s remain as
  inventory; no swap planned.
- Cart: Arduino Uno R4 WiFi at 192.168.1.97. Adequate for
  everything built so far (Architectural principle #14: Giga
  migration only when Uno is the specific blocker).

---

## Working preferences

See PREFERENCES.md for the full agreement. Key reminders:
- Windows cmd syntax
- Small steps, one question at a time, wait for confirmation
- Code boxes for shell commands; bare URLs on own line in chat
- Oscilloscope approach — instrument, don't guess
- Photos sacred; wrong exposure fixable in post
- Pin-8 must work when CCAPI is down
- Tv+1.5s cadence rule
- Visualisation > Manipulation (Day 10)
- Compare against known-good reference first (Day 12)
