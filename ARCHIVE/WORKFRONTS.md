# HyperLapse Cart — Open Workfronts

**As of:** Session C day 18 (second half), 24 May 2026

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

## Day 17 update (added 23 May 2026)

Diagnostic + build session. **Plan execution fully validated end-to-end
across all designed segment types and stop styles.** Five bugs found
and fixed via instrumentation; full diagnosis narrative in PROJECT_STATE
Day-17 entry.

**Headline.** All test banks green. The cart now executes any authored
plan correctly:

- MOVE segments at any speed, distance-ended, with steering
- MOVE-to-MOVE transitions (tr=M smooth merge)
- STOP segments (decel, emergency-halt, or 6-min decay) with operator-
  authored hold duration counting from genuine rest
- Operator-ended STOP segments
- `/plan/stop` mid-segment (clean abort)
- `/btn11` and `/btn12` mid-plan (stop cart without aborting plan)
- `/plan/nudge ±100mm` extending / shrinking / past-zero

**Bugs fixed (chronological):**

1. **Bogus rear-Tic delta negation** in `planTick`, `planStatusCSV`,
   `/plan/nudge`. Three `delta = -delta;` lines, justified by a stale
   "rear Tic wired physically reversed" comment, made segment-complete
   fire on the wrong sign. Forward MOVE segments would never complete.
   Inserted by an uncommitted edit from a prior Claude session that
   crashed before testing. Removed; verified empirically with
   `/debug/tic` that both Tics count positive on cart-forward.
2. **I²C "cliff"** — `planTick` was reading `ticRear.getCurrentPosition()`
   every main-loop iteration. Sustained high-rate I²C polling caused
   both Tics to simultaneously NACK on the bus (Wire err=2) after a
   variable run time (7s / 17s / 128s observed). Once cliffed, Tic
   comms dead for the rest of run; cart kept moving on last commanded
   velocity. Throttled `planTick` to 100ms cadence; cliff did not
   recur. Root cause not characterised — workfront #52.
3. **STOP-segment duration timer counted from segment entry.** A 5s
   STOP after 30 m/hr cruise actually held only ~1.5s at rest because
   the Tic STOP_DECEL ramp ate 3.5s of the window. Added an "at-rest
   gate" in `planTick` END_DURATION polling both Tic velocities every
   250ms; counts duration only from the moment both reach 0.
4. **Stop-style dispatcher (TR_S / TR_E / TR_D) pointless.** Each
   stop case did `cartStop()` then immediately
   `cartSetSpeed(speed_mhr)` — Tic accepted the latest target and
   ignored the first. No actual stop happened. Rewrote dispatcher
   with corrected M/S/E/D semantics: M for MOVE-to-MOVE, S/E/D for
   STOP segments. STOP variants only initiate deceleration; the
   at-rest gate handles the duration counting. All three converge
   to "wait at 0 then count" — they differ only in HOW the cart
   reaches 0.
5. **Decay-loop unsigned-subtraction underflow.** When
   `cartStartDecay()` is called from `planTick` (which runs at the
   top of `cartLoop`), `cart_decay_start` is set to a `millis()`
   later than `now` captured at the top of cartLoop. The next
   `elapsed = now - cart_decay_start` underflows, fires the
   decay-complete branch, calls `cartStop()` on the same iteration.
   Result: decay-style stop instantly turned into emergency-style
   stop. Fixed by guarding `elapsed` against negative-then-wrapped
   values.

**Authoring vocabulary, post-Day-17 (canonical):**

| Tag | Used on | What it does |
|---|---|---|
| **M** (merge) | MOVE | Slam target speed; Tic accel/decel handles ramp. Default for MOVE. |
| **S** (decel stop) | STOP | `cartSetSpeed(0)`; Tic STOP_DECEL ramps to rest (~5s from 30 m/hr). Then hold for `duration_ms`. Default for STOP. |
| **E** (emergency) | STOP | `cartDeadStop()`; Tic haltAndHold for instant lock (~30ms). Then hold. |
| **D** (decay) | STOP | `cartStartDecay()`; linear ramp from current speed to 0 over `cart_decay_ms` (6 min production). Then hold. |

Authoring format unchanged: `s,VAL,steer,speed,end[,tr]` where the
optional 6th field is the transition tag.

**New endpoints:**
- `/debug/decaytime` and `/debug/decaytime?ms=N` — get/set the global
  `cart_decay_ms` (default 360000 / 6 min, clamped 1s–10min)

**New globals (kept in production):**
- `cart_decay_ms` (replaces `const CART_DECAY_MS`)
- `plantick_dist_last_ms` (100ms read throttle)
- At-rest gate state in `planTick` END_DURATION (per-segment statics)

**Diagnostic instrumentation removed at end of session:**
- PTICK 500ms probe in `planTick` END_DIST
- PROBE 100ms sampler in `cartLoop` (post-stop)
- DUR elapsed-since-rest probe
- TR_DECAY pre/post-startDecay diagnostic prints
- `stop_probe_*`, `plantick_probe_last_ms` globals

Retained as production-grade defensive checks:
- `getLastError()` after Tic position read in `planTick`, logs only
  on non-zero error code — surfaces a cliff event immediately without
  per-tick noise

**Workfront status changes:**
- **#5a Segment dispatcher** — DONE. M for MOVE, S/E/D for STOP all
  verified end-to-end.
- **#5a-related: ±100mm nudge** — DONE. `/plan/nudge?d=±N` working,
  with past-zero segment-complete fallthrough.
- **#48 (was bus fault on shutter)** — unrelated to Day-17 bugs,
  not revisited.
- **NEW #51 Remove Day-17 diagnostics** — DONE this session.
- **NEW #52 I²C cliff** — partially resolved second-session.
  Original avoidance (100ms throttle on planTick) extended cliff
  onset from ~7s to ~3min but did not eliminate it; 1 Hz polling
  pushed cliff out to ~11min but still hit. Throttling alone never
  enough. Per Pololu docs (0J71/4.6): cause class is weak pull-ups
  + long wires + standard clock. Two interventions applied:
  (1) Architectural — MOVE segment completion is now time-based
  open-loop. Zero Tic reads during a MOVE segment. Cliff cause
  removed for the long-running case. STOP at-rest gate still polls
  velocity at 250ms but only during the bounded ~5s decel window
  (~20 reads per STOP, well below threshold).
  (2) Defensive — `Wire.setClock(50000)` added in setup (Pololu
  recommendation for marginal pull-ups).
  **Still open:** hardware fix (external 10 kΩ pull-ups on SDA/SCL
  per Pololu) — flagged as future work, no urgency now that the
  problem is sidestepped.
- **NEW #53 Calibration mismatch** — `CART_SPEED_SCALE = 58` (m/hr
  → Tic velocity) and `565 steps/mm` distance calibration are
  internally inconsistent by ~10%. Empirically chosen constants.
  Not a practical problem at hyperlapse pixel tolerances. Could be
  reconciled by remeasuring on a known-distance track.
- **NEW #54 Gimbal slew overshoot** (Day 17, second session). Observed
  during showastro tests: large-angle slews (e.g. home → 120° pan)
  with default `time_for_action = 0x14` (2s) physically overshoot
  target then correct. The DJI motor controller over-tunes for the
  load when forced to move fast. Fix options:
  (a) bump time_for_action to a slower fixed value (e.g. 0x40 = 6.4s)
  (b) compute slew time from angular distance like panoIssueSlew
      already does (line 2206 of sketch, `dur_ms = dmax / slew_dps × 1000`)
  Option (b) is consistent with existing code and the more durable
  fix. Apply to showastro / showastrooffset / /move endpoints.

**Build lessons added to PREFERENCES (Day 17):**
- A prior crashed Claude session can leave uncommitted edits in the
  working tree. `git diff` against the latest commit before treating
  local sketch as authoritative.
- A code comment that explains a counterintuitive behaviour is
  high-risk signal, not high-trust signal. Verify empirically before
  reasoning from it.
- I²C cliffs are quiet — no exception, no watchdog. Standardise
  `getLastError()` checks for any code touching Tic comms.
- `millis()` captured at the top of a cartLoop iteration is stale by
  the time inner code completes. Sub-blocks may set their own
  timestamps later in the same iteration; guard subtraction.
- A "stop" command followed by an immediate "set speed" is identical
  to "set speed" alone — the Tic accepts the latest target. To
  actually stop and hold, there must be an in-between gate that
  waits for rest.
- **If the slave is reliable in doing what you commanded, don't keep
  asking what it's doing.** The cliff symptom was caused by polling
  the Tic for its position 10× per second — asking something the Tic
  already knows and will execute faithfully. Replacing the poll with
  a time-based estimate (commanded velocity × elapsed time) was
  enough to remove the cliff cause entirely. Bigger lesson: when a
  measurement-based feedback loop hits a hardware-bus problem, first
  ask whether the measurement is necessary at all.
- **Position-poll != real-world feedback.** Asking the Tic where the
  cart is doesn't measure the cart — it measures the Tic's internal
  step counter, which equals reality only when nothing slips. Open-
  loop estimation makes the same assumption. No accuracy is lost by
  removing the poll.

---

## Day 18 update (added 24 May 2026)

Giga capability validation (Steps 1, 2, 4, 5 of GIGA_MIGRATION_STRATEGY)
PLUS Step 7 v2 sketch port complete. Step 3 (CAN) paused on cooked
transceiver. Sketch went from 0 → 5667 lines in DJI_Ronin_Giga_v2.ino,
section-by-section verbatim port from v1prod with Giga deltas applied.

**Capability tests passed (Day 18 first half):**
- **Step 1** Blink + Serial on Giga (COM12, 115200, LED + Serial.println).
- **Step 2** WiFi on Rosedale at 192.168.1.116 after one-time
  WiFiFirmwareUpdater run.
- **Step 4** I²C Tic 14+15 at default speed on Wire (D20/D21) with
  external 4.7 kΩ pull-ups. Pololu Tic library compiles + runs
  unchanged.
- **Step 5** CCAPI alive check + shutter trigger. Required two fixes
  vs v1prod (see workfront #61 below): explicit `\r\n` on outbound
  headers + Wire pin selection.
- **Step 5b** Full CCAPI dynamic-range validation. Tv GET (522 bytes,
  current `0\"3`, 60 abilities), ISO GET (253 bytes), liveview start,
  luminance flipdetail. 5162-byte response parsed via FF 00 01 +
  size:4 BE + JSON + FF FF framing. Mean luminance 144→247 (bright)
  →16 (dark). Full headroom confirmed; 8 KB LUM_RESP_BUF_SIZE on
  Giga handles the live histogram cleanly.

**Step 3 paused.** SN65HVD230 transceiver killed by reversed
3.3V/GND wiring. CAN-only test sketch (DJI_Giga_Step3_CAN.ino)
ready to flash once new transceiver arrives (~5 days).

**Step 7 sketch port (Day 18 second half) — DJI_Ronin_Giga_v2.ino.**

Five open design questions resolved up-front via GIGA_DESIGN.md:

1. **IP addressing during parallel.** Giga 192.168.1.95 on Rosedale
   (DHCP-reserved by MAC). Uno stays on .97 until retirement.
   Excel `dataArduinoIP` flips at cutover.
2. **UI vs camera traffic.** Operator UI + Excel polling on WiFi
   STA port 80. W5500 wired Ethernet (when arrives) for CCAPI only.
3. **Shutter pin.** Pin-8 → D7 on Giga. 200ms HIGH pulse discipline
   verbatim. Sacred; fires on shutter_mode==3 regardless of CCAPI.
4. **Buffer sizes.** CartLog 64→128, GimbalLog 24→128. Operator's
   20-50m recon × ~50 events leaves comfortable headroom.
5. **String allocation.** snprintf for hot paths (/status,
   /heartbeat, /cameramsg); String OK for cold paths.

Port structure: 8 sections, 5667 lines total. Compiles + runs with
STUB_CAN defined. All 57 v1prod endpoints ported. Full 3-screen
browser UI verbatim. Path ordering verified for every startsWith
chain (showastrooffset before showastro, movewatchdump before
movewatch, /shutter/* before /shutter, /cartlog/clear before
/cartlog, etc.).

Section breakdown with Giga deltas:
- §1 (~370): WiFi.h not WiFiS3.h; STUB_CAN/BNO/W5500 stubs;
  LUM_HTTP_TIMEOUT_MS 10000→2000; buffer 4096→8192.
- §2 (~510): Appendix A formula plumbing — no Giga changes.
- §3 (~460): Buffer sizes bumped per resolved Q4 above.
- §4 (~500): drainCANRx + sendFrame wrapped in `#ifndef STUB_CAN`.
  All commands callable; frames built and silently dropped at the
  sendFrame stub. Pano state machine + movewatch sampler.
- §5 (~655): ccapiRequest with `\r\n` on outbound headers (Q1
  resolved via build lesson #1). Binary-frame luminance parse.
- §6 (~935): Plan executor with #52 time-based completion, at-rest
  gate, pano helpers, pin-D7 backupShutter.
- §7 (~200): setup + loop. `Wire.setClock` REMOVED (blocks Giga
  per Day-18 finding). CAN.begin wrapped. **delay(1) at bottom of
  loop()** per discipline #2.
- §8 (~1860): handleHttpRequest body split 8a-8h:
  - 8a skeleton + status/heartbeat/cameramsg/interval
  - 8b move/home/gimbal pano/shutter/btn1-22
  - 8c exposure/* + settings/astropos/trackpath/trackplan
  - 8d cartlog/gimballog (+ /clear, /push variants)
  - 8e plan/load/start/stop/status/nudge
  - 8f gimbal/showastro/snapvar/showastrooffset
  - 8g 17 debug endpoints (4 early-return + 13 chain)
  - 8h browser UI catch-all (3 screens, all SVG icons, polling JS)

**Workfront state changes:**

- **#47 (Giga R1 migration) — Step 7 port complete.** Sketch ready
  to flash. Smoke test against Excel still pending. Real-gimbal
  validation pending CAN transceiver arrival.
- **NEW #60 Step 3 transceiver hardware** — bench setup blocked by
  cooked SN65HVD230. New transceiver in transit (~5 days). DJI_Giga_
  Step3_CAN.ino sketch ready to flash on arrival. Compiles cleanly;
  only hardware blocks the test.
- **NEW #61 v2 build discipline (mbed-os failure modes)** — design
  doc. Seven risks identified from v1prod patterns that may break
  on Giga: long blocking calls, String allocation in hot paths,
  ISR/network collision, no-yield loops, PROGMEM no-op, millis
  rollover (already handled), no EEPROM. Six defensive disciplines
  applied during Step 7 port: bounded timeouts ≤2s, delay(1)
  bottom-of-loop, snprintf for hot paths, CAN RX in ring buffer
  never network code, document F() no-op, multi-hour soak test
  before declaring done. Most folded into the sketch; multi-hour
  soak test still pending (see #63).
- **NEW #62 Excel Camera.bas dead-code cleanup** — design doc.
  Cart firmware has owned the per-photo exposure walk since #36b
  (Day 12). Excel's Camera.bas luminance pipeline + per-photo CCAPI
  walk is vestigial. Low risk, not blocking. Defer to Giga Excel
  port pass when every HTTP endpoint is being repointed anyway.
- **NEW #63 Multi-hour soak test of Giga v2 sketch** — close-out
  test for #61 build discipline. Run a representative shoot
  envelope (sunset → sunrise) against the flashed sketch with
  Excel driving plan execution. Watch for blocking-call stalls,
  heap fragmentation, mbed-os scheduler starvation, silent
  WiFi disconnects. Pass criterion: photo cadence within tolerance
  for the full duration with no LOOP-LONG spam and no
  reconnects. Blocks on flash + smoke test landing first.
- **NEW #64 Phase-time terminology cleanup.**
  `dataPhase2aStart` / `2bStart` / `3Start` / `4aStart` / `4bStart`
  / `5Start` are jargon from a prior session — not real astronomical
  terms. They approximate real events (golden hour, civil dusk,
  nautical dusk, astronomical dawn, civil dawn, sunrise) but the
  offsets drift seasonally and don't match the standard
  astrophotography vocabulary. Astro.bas can compute the real
  events directly via `FindSunCrossing` at the appropriate
  altitudes (-6° civil, -12° nautical, -18° astronomical). Replace
  named ranges with real-event names, retire `CalculatePhaseTimes`.
  Defer to Giga Excel port pass (same window as #62) — every
  consumer of `dataPhaseXStart` will be reviewed anyway. Not
  blocking.
- **NEW #65 mbed WiFi accept() semantics — sketch fix landed.**
  Day-18 smoke test exposed that Giga's mbed WiFi
  `wifiServer.available()` is semantically `accept()` — returns
  the client object as soon as the TCP three-way handshake
  completes, BEFORE the HTTP request body arrives. v1prod's
  Uno-WiFiS3 pattern (single-shot `if (client.available())`)
  saw `req_len=0` always, fell through every if/else, landed in
  the UI catch-all. Root-caused via ArduinoCore-mbed issue #766
  (JAndrassy: "available() here works like Ethernet library's
  accept()"). Fix: replaced single check with a
  `while (client.connected()) { if (client.available()) ... else
  delay(1); }` bounded at 2 seconds. Confirmed working: /status,
  /heartbeat, /settings/astropos, /exposure/load all round-trip
  cleanly. Documented as Day-18 build lesson #5. CLOSED.
- **NEW #66 Empty-connection diagnostic cost.** Side-effect of
  the #65 fix: any TCP socket that lands but never sends a
  request (browser speculative pre-connect, port scan, stale
  Excel WinHttp socket) costs ~3000ms wall-clock (2s wait + 1s
  client.stop tear-down). Cosmetic only — real Excel polling
  is unaffected and pin-D7 cadence is still guaranteed by the
  sacred-pin discipline. Long-term: investigate non-blocking
  accept + pending-client state machine (per ArduinoCore-mbed
  #76 / #281 idiom — `sock->set_blocking(false)` + persistent
  client state). Not blocking #63 soak test; revisit if
  empty-connection rate becomes significant.

**Build lessons from Day 18 (also in PREFERENCES):**

1. **Giga mbed WiFi needs `\r\n` on outbound HTTP headers.** Canon
   CCAPI rejects bare-LF with 400 + empty body. WiFiS3 was lenient;
   mbed is strict per RFC. Use `print("...\r\n")` not `println`
   for headers.
2. **Giga has three I²C buses.** Pins near AREF are Wire1
   (silkscreen reads SDA1/SCL1); default Wire is on D20/D21 at the
   other end of the digital header. Wire1 instance vs Wire: read
   the pin diagram.
3. **External pull-ups on Wire are MANDATORY.** Giga doesn't apply
   internal pull-ups for Wire. 4.7 kΩ to 3V3 — confirmed working.
4. **`Wire.setClock()` blocks on Giga.** Don't call it. Default
   100 kHz works fine with proper pull-ups.
5. **mbed `wifiServer.available()` is `accept()`, not data-ready.**
   Returns the client object as soon as TCP handshake completes,
   BEFORE the HTTP request body arrives. v1prod's single-shot
   `if (client.available())` check saw `req_len=0` always.
   Canonical mbed pattern is a `while (client.connected())` loop
   that waits for `client.available()` with `delay(1)` between
   checks, bounded at 2 seconds. v1prod's Uno-WiFiS3 pattern is
   NOT portable to mbed. Documented in #65.

Sketch line count after port: 5667 (vs v1prod 6275). Denser, same
features. All v1prod functionality reachable; CAN/BNO/W5500 paths
covered by stubs until hardware arrives.

---



Below is a record of what was tested and verified. Future regression
tests should re-run these.

### Test bank A — segment end conditions

A1 (MOVE with END_DURATION) skipped — parser puts MOVE val into
dist_mm, not duration_ms. Combination not designed for. The valid
end conditions per type are MOVE→END_DIST, STOP→END_DURATION or
END_OPERATOR.

**A2 (STOP with END_DURATION).** ✓ Verified.
- Plan: `n=4&s1=m,200,0,20,d&s2=s,5000,0,0,t&s3=m,200,0,20,d&s4=s,0,0,0,o`
- Result: SEG 2 entered at 20 m/hr cruise, at-rest reached t+3545ms,
  5s hold counted from rest, SEG 3 entered, cart re-accelerated to
  20 m/hr cleanly. Total SEG 2 wall-clock: ~8.5s for "5-second STOP".

**A3 (STOP with END_OPERATOR).** ✓ Verified as part of every other
test (the trailing `s,0,0,0,o` segment).

### Test bank B — STOP segment transition tags

5-segment plan: MOVE 250mm @ 30 m/hr → STOP 5s (variant) → MOVE
250mm @ 30 m/hr → STOP 5s (variant) → STOP operator-end.

**B-S (default decel stop).** ✓ At-rest at t+5408ms / t+5306ms.
Cart re-accelerated from full rest, drove SEG 3 cleanly. Re-stopped
in SEG 4.

**B-E (emergency stop, cartDeadStop).** ✓ At-rest at t+31ms / t+32ms.
Cart re-accelerated from dead halt without issue.

**B-D (decay stop).** ✓ With `cart_decay_ms=60000` (1 min) for
test convenience. Cart maintained 30 m/hr at SEG 2 entry, then
linearly decayed over 60s to 0. At-rest at t+60144ms. 5s hold then
SEG 2 complete. Production default 360000ms (6 min) restored at
end of session.

### Test bank C — stop primitives mid-plan

**C1 (`/plan/stop`).** ✓ Abort fires planAbort → cartStop. Cart
decelerates via Tic STOP_DECEL ramp. Plan state → IDLE.

**C2 (`/btn11` cartStop mid-MOVE).** ✓ Cart decelerates and stops
(~5.4s). Plan state stays RUNNING — segment-complete via END_DIST
will not fire because cart isn't moving. Operator must follow with
`/plan/stop` to clean up. UX implication recorded for Execution
screen design.

**C3 (`/btn12` cartDeadStop mid-MOVE).** ✓ Sharp halt within ~50ms.
Plan stays RUNNING (same as C2). Cart locked at last position
(Tic haltAndHold prevents drift).

### Test bank D — `/plan/nudge`

**D1 (`+100mm`).** ✓ Plan: `m,250,0,30,d`. During cruise, nudged
+100mm at delta=68499. `[Plan] NUDGE seg=1 delta_mm=100
new_dist_mm=350 steps=70299/197750`. Target updated to 197750,
cart continued, SEG 1 completed at delta=197824.

**D2 (`-100mm` with plenty left).** ✓ Plan: `m,250,0,30,d`.
Nudged -100mm at delta=50099. Target shrank to 84750. SEG 1
completed at delta≥84750. Cart drove ~150mm total.

**D3 (`-100mm` past zero).** ✓ Plan: `m,250,0,30,d`. Waited until
delta=106849 (~189mm covered). Nudged -100mm. Handler logged:
`NUDGE past zero — segment complete`. SEG 2 entered immediately.

**D4 (nudge on STOP segment).** ✓ Plan with STOP+duration. Nudge
request returned `ERROR: nudge only valid mid-MOVE`. Rejected
cleanly.

### Test bank E — multi-segment with steering

**E1 (S-curve plan).** ✓ Plan: `m,300,-5,20,d` → `m,300,5,20,d`
→ STOP. SEG 1 with steer=-5, SEG 2 with steer=+5, all completed.
Steering ramps at 1°/sec (existing behaviour) so the -5 → +5
transition takes ~10s.

---

## Day 16 update (added 23 May 2026)

Build session — three-screen UI v2 foundation delivered. Two screens
real (Cart Recon, Gimbal Recon), one placeholder (Execution). See
PROJECT_STATE Day-16 entry for full detail.

**Headline:** UI_DESIGN_v2.md spec moved from design to running
firmware. Cart Recon operator-verified end-to-end. Gimbal Recon UI
fully laid out but captured rows are client-side only — production
gap closed by new follow-up #49.

**Sketch additions (v1prod):**
- Server-side `?screen=cart|gimbal|exec` routing in the catch-all
  HTML `else` block. Shared header (logo row + 4-tab bar) on every
  screen. Day palette baked in CSS.
- New state vars: `cart_motor_state` (1B), `cart_waypoint_count` (4B),
  `cart_last_waypoint_steps` (4B). +9 bytes SRAM globals.
- Hooks added: cartStop/cartDeadStop/cartSetSpeed/cartEnergise/
  cartDeenergise all set `cart_motor_state` correctly. Decay completion
  already calls cartStop() so covered.
- New `'W'` event in CartLog (value = waypoint number).
- New btn22 (Mark wpt) handler with confirm.
- `/status` extended: v[10] motor state (0=DE-E, 1=STOP, 2=ENRG),
  v[11] waypoint count, v[12] mm-since-last-waypoint.
- Reset paths: btn19 log-start, btn21 Clear logs, /cartlog/clear all
  zero the waypoint counter and reseat the rear_steps anchor.

**New follow-ups:**
- **#49** Gimbal Recon rich-row persistence (cart-side struct
  extension + /gimballog/push endpoint). Smallest path to make
  Gimbal Recon production-usable.
- **#50** Excel astro position push to cart. Unlocks Show astro
  and Snap var on Gimbal Recon.

**JS escape-quote build lesson** added to PREFERENCES. Broken
`\\'s` in a stub-alert string killed the entire script (live readout
stuck on dashes). Each level of C++ → HTML → JS escape multiplies;
easy to over-escape into a parser error far from the affected feature.

**Hygiene:**
- `UI_DESIGN_SUMMARY.md` (Day 10) moved to `ARCHIVE/` — superseded
  by UI_DESIGN_v2 + Day-16 build.
- `GIMBAL_VIZ.md` §3 / §9 / §10 annotated with superseded-by
  callouts. Sections 1, 2, 4, 5, 6, 7, 8 remain authoritative
  reference.

**Closed / promoted this session:**
- #10a Gimbal UI page — DELIVERED as Gimbal Recon screen (one URL
  with ?screen= routing, not a separate URL as Day-8 had proposed).
  Production-readiness pending #49.
- #29 Mark Waypoint button — DELIVERED (btn22 + `'W'` CartLog event).
- Old design assumptions in GIMBAL_VIZ.md §3 (Way# dropdown, yaw/pitch
  nudge buttons, Extra 1/2 reserved fields) — formally retired.

**Not changed this session:**
- All execution-related workfronts (#5a dispatcher, ±100mm nudge,
  PAUSE/RESUME, #40 BNO build) remain open. Execution screen
  remains a placeholder pending these.

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

**Part 3 — v1 simplification (same day).** With Step 4 closed
for v1, the per-flip table-row lookup that produced `exp_delta_t_rel`
+ `last_table_tv` / `last_table_iso` had no consumer. Retired
those state vars, `findTableRowForTv()`, `/debug/match` endpoint,
and associated Serial logs / JSON fields. Sketch −143 lines
(4986 → 4843). End-to-end verified 104/104 photos across full
LIVE → PROBING → TABLE → Step D recovery → LIVE cycle. FLIP log
and `/exposure/state` JSON clean at the wire. TABLE mode in v1
is now operationally exactly what it needed to be: "don't talk
to the camera, keep photos firing, ping every 60s."

**Part 8 — Gimbal execution model + PAUSE semantics (design).**
UI design session (Day-15 part 8) resolved how the gimbal half of
the plan executes alongside the cart, and what the proposed
PAUSE button does to both. This is design only — no firmware
written yet. Builds on Day-8 GIMBAL_VIZ design and Day-9
"operator-in-the-loop" architecture.

*Cart execution semantics (from existing v1 sketch).* MOVE
segments are **distance-driven** — cart drives until rear_steps
delta covers the segment's `dist_mm`, at the segment's
`speed_mhr`. Wall-clock time falls out. STOP segments are
**duration-driven** — cart sits for `duration_ms`. No clock-driven
MOVEs exist.

*Gimbal plan linking.* Gimbal events are anchored to cart
**waypoints** (cart distance), not wall-clock time. Example
authoring: "pan-follow from cart way 2 to cart way 5" or "move
from Ry 250° to Ry 110° between way 2 and way 5 (600mm)". The
gimbal events that DON'T link to cart distance: astro targets
(sunrise / sunset / MW) — those still fire on wall-clock astro
time because the sky doesn't wait for the cart.

*Move-to execution math.* For a "move yaw X° over Y mm" event:
- DJI R SDK protocol resolution: 0.1° yaw, 100ms time
  (`int16_t * 0.1f` per the sketch line 1381 etc.)
- Plan provides: total yaw delta, total distance, start yaw
- Execution computes the next nudge from
  `target_yaw - last_commanded_yaw` against accumulated distance
  from segment start — NOT from accumulated micro-increments.
  Rounding errors don't drift across thousands of nudges.
- Slow pan (5° / 600mm = 0.0083°/mm): one 0.1° nudge per ~12mm.
  Distance accumulates with no nudge fire for many cart loops.
- Fast pan (140° / 600mm = 0.233°/mm): one 0.1° nudge per ~0.43mm.
  Tighter nudge cadence.
- The combined plan tells execution the total distance and total
  yaw; execution decides when each 0.1° fires.

*Accuracy budget is loose.* Timelapse is post-processed for
luminance, flicker, and stabilisation. Wind blows the rig left
and right a bit anyway. The 0.1° yaw quantisation will look like
microscopic stair-steps in raw output; post-stabilisation
smooths them out completely. We don't need sub-0.1° resolution,
ms-accurate timing, or fancy interpolation.

*PAUSE semantics.* DEAD STOP button on Execution UI re-framed
as PAUSE (toggle PAUSE ↔ RESUME). Use case: hazard ahead, 2 min
freeze, then continue. Shoot continues throughout — photos keep
firing on Tv cadence, no abort.

- **PAUSE during a MOVE segment**: Tic ramps cart down via
  STOP_DECEL_SETTING (smooth, photogenic). Cart sits at the
  current rear_steps position with X mm still to go. Distance-
  driven gimbal moves also pause (no distance progress = no
  new yaw nudges fired). RESUME: Tic ramps back up via
  ACCEL_SETTING, rear_steps continues from where it stopped,
  segment end condition (delta ≥ target) is met when cart has
  actually covered the remaining distance. Distance preserved.
  Gimbal yaw resumes from its paused intermediate value.
  Total wall-clock extends by however long the pause was.
- **PAUSE during a STOP segment**: cart already at rest. The
  STOP duration counter is frozen — segment won't auto-advance
  until RESUME. Effective use: extend the hold past its
  scheduled end. Subsequent segments still cover their full
  distances, so cart still arrives at the right places.
- **Astro events during pause**: sunrise / sunset / MW are
  wall-clock-fired, independent of pause state. A pause that
  pushes the cart through an astro window means the gimbal
  goes to the astro position on schedule, regardless of where
  the cart is. Acceptable: astro is what audience expects to
  see on time; cart position is flexible.
- **Pause during a hold-at-waypoint (gimbal hold)**: zero
  effect on gimbal. Gimbal was already not moving. Photos keep
  firing on identical-frame which at 1320× speedup = ~1 second
  of audience-visual extra hold per 2-min pause. Indistinguishable
  from planned hold being slightly longer.
- **Pause during pan-follow**: zero effect. Pan-follow points
  gimbal yaw to track cart heading; cart heading isn't changing
  during pause; gimbal stays still.
- **Pause during track-point** (move-to a fixed earth-frame
  object): zero effect. Gimbal already pointed at object; cart
  paused means parallax doesn't change; object stays in frame.
- **Pause during move-to (distance-driven gimbal segment)**:
  the interesting case. Gimbal yaw pauses at intermediate
  value, audience sees a brief hold mid-move. Resumes when
  cart resumes, completes the remaining yaw delta over the
  remaining distance. Yaw will complete "on cart distance",
  not "on time".

*Real-but-not-often consequence.* Astro events are wall-clock-
fired. A long pause near a scheduled astro event can push the
cart into the astro window with a still-incomplete gimbal
move-to. The gimbal will then need to jump from its
mid-move intermediate yaw to the astro target. Whether this
manifests as a jolt or is smoothed by the planner is a
question for the gimbal-plan dispatcher (#5a) and the linking
logic (Excel-side #46).

*Status of this design.* Not built. Inputs to:
- #5a Segment dispatcher + cubic evaluator (firmware)
- #13 New Plan sheet schema (Excel — combined cart+gimbal plan)
- #46 Gimbal authoring against cart row labels (Excel)
- Execution UI (DEAD STOP renamed to PAUSE, toggles to RESUME)

**Part 9 — Speed transition types + ±100mm nudge semantics (design).**
Continuation of Day-15 Part 8. Adds the Excel-side speed-change
authoring vocabulary and the cart-execution behaviour for the
operator's ±100mm distance nudge during a running plan.

*Four speed transition types per segment-to-segment boundary.*
Excel emits the type per segment; cart dispatches in
`planSegmentEnter()`. All four target functions already exist in
the sketch — only the dispatcher and per-segment field are new.

1. **Dead** — `cartDeadStop()` — Tic `haltAndHold`, motor locks at
   current position, sharp stop. Used only when precision matters
   more than smoothness.
2. **Stop** — `cartStop()` — velocity factor → 0 immediately; Tic
   uses its current deceleration setting (STOP_DECEL_SETTING) to
   ramp down. Real-world acceptable for timelapse.
3. **Decay** — distance-driven linear-decay-to-zero. Plan
   specifies the decay distance; cart computes nudge factor
   `current_speed ÷ remaining_distance` and drops speed at each
   rear_steps increment. Recomputed if remaining distance changes
   (see ±100mm below). NOT the existing 6-minute global
   `cartStartDecay()` — that's manual-DEC-button behaviour.
   The plan-side decay is distance-bounded and adaptive.
4. **Smooth** — set the new target speed and let Tic's
   ACCEL_SETTING / STOP_DECEL_SETTING handle the ramp inside the
   next segment. "Slam it in and Tic will sort it out." This is
   the default — most segment-to-segment transitions will be
   smooth.

*±100mm nudge buttons on Execution UI.* Operator can adjust the
current MOVE segment's target distance by ±100mm. The Execution
UI shows the ToGo readout (current `target - delta` in mm) and
two buttons.

- **Within-segment**: target shifts by ±100mm. Cart continues at
  current segment speed. ToGo updates.
- **−100mm past zero**: segment completes immediately
  (`planSegmentComplete()` fires). Cart advances to next segment.
  Behaviour at the boundary depends on the **next** segment's
  speed transition type (above). Overshoot is small at slow
  segment speeds (the use case for −100mm); at higher speeds it
  could be larger but tap is less likely.
- **+100mm with distance left**: target extends 100mm. Cart
  continues; ToGo grows. No special handling.

*Decay segments interact with ±100mm via recompute.* If the
operator nudges a decay segment, the nudge factor is recomputed
each time the remaining distance changes:
- `−100mm during decay (plenty left)`: nudge factor recomputed,
  decay drops to zero faster (steeper). Audience-perceived: cart
  arrives at rest earlier than originally planned.
- `+100mm during decay`: nudge factor recomputed, decay drops
  more gently. Cart arrives at rest later.
- `−100mm during decay past zero`: emergency `cartStop()`
  fallback. Cart was already slow due to decay; overshoot
  negligible (sub-mm).

*Gimbal coupling on ±100mm.* Distance-driven gimbal segments
(move-to with yaw delta) recompute their yaw-per-mm nudge factor
the same way decay does:
- New nudge factor = `(target_yaw − current_yaw) ÷ new_remaining_distance`
- −100mm: yaw nudges accelerate to cover remaining delta in less
  distance. +100mm: yaw nudges slow.
- All other gimbal event types (PF, Lock, sun-track, astro
  targets) are independent of cart distance and need no
  recompute.

*Excel prevents gimbal moves spanning cart STOP segments.*
Distance-driven gimbal nudges only progress while cart distance
progresses — so a gimbal Move-to cannot span a cart STOP (the
gimbal would freeze mid-move during the stop, then resume,
producing an unintended audience-visible hold). Authoring rule:
each gimbal Move-to row may only cover consecutive cart MOVE
segments. Excel detects a Move-to that crosses any STOP and
errors at plan-bake time; operator splits the gimbal row into
before/after pieces. This keeps cart-side execution simple — no
"freeze during STOP / resume after STOP" logic needed.

*Stranded gimbal on −100mm past zero.* Different problem.
Operator-initiated cart shorten can end a MOVE segment while a
distance-driven gimbal move-to is still in progress. Excel
didn't anticipate this; the cart handles it locally with one
simple rule: **gimbal carries on at its current yaw/sec rate.**

- At the moment of strand, gimbal converts its last
  `yaw/mm × cart_speed_at_strand` into a constant `yaw/sec` rate.
- Gimbal continues nudging at that rate until it reaches the
  intended end yaw of the abandoned move-to.
- Then sits at end yaw (gimbal effectively becomes a hold).
- Cart is doing whatever its next segment says, independently.
- No snap. No reach into the next gimbal segment. No coupling
  back to cart distance.

Rare event. Not anticipated in Excel plan. Cart-side rule is
self-contained.

*Status.* Design only, not built. Same downstream consumers as
Part 8: firmware #5a, Excel #13 and #46, UI execution screen.
Additional cart-side need: Excel emits speed transition type in
the segment string, sketch parses it, dispatcher in
`planSegmentEnter()` selects between Dead / Stop / Decay /
Smooth handlers.

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
- `/debug/ping` endpoint for diagnostics (`/debug/match` retired
  Day-15 part 3 with `findTableRowForTv`)
- `/exposure/state` returns full mode + probe + comms state

Not yet built (and acceptable for production):
- **TABLE per-cycle PUT logic (Step 4 of original Day-13 plan).**
  CLOSED for v1 (Day-15 part 2): logically impossible, CCAPI
  unreachable in TABLE by definition. Re-opens as a v2 build task
  (wired Ethernet link is independent of the WiFi outage that
  caused entry to TABLE). Day-15 part 3 follow-up retired the v1
  scaffolding that anticipated Step 4 (`exp_delta_t_rel`,
  `last_table_tv`, `last_table_iso`, `findTableRowForTv`,
  `/debug/match`). Rebuilt from scratch in v2 if/when needed.

**#36d cleanup (CLOSED Day 15 part 6).** Traced through the
original "dead state vars" list. Verified status of each:
- `FETCH_FAIL_BACKOFF_CYCLES` — dead, removed Day 15 part 5.
- `MODE_FLIP_THRESHOLD` — dead, removed Day 15 part 5
  (`PROBE_COUNT` is the live equivalent).
- `lum_fetch_skip_remaining` — dead, removed Day 15 part 6
  (branch was unreachable; nothing ever set it non-zero).
- `lum_consecutive_conn_fails` + `LUM_FAIL_THRESHOLD` — NOT dead.
  Still load-bearing as the liveview-died detector (3 connection-
  level fails invalidates `lum_liveview_started` for fresh re-POST).
  Also exposed in `/exposure/state` JSON. KEEP.
- `lum_in_outage` — NOT dead. Load-bearing for log-spam
  suppression (first fail logs verbose, subsequent fails throttle
  to every Nth attempt). Also exposed in `/exposure/state` JSON.
  KEEP.
- `consecutive_fetch_fails`, `consecutive_fetch_successes` — already
  kept in earlier passes, still consumed by `/exposure/state`.

Original WORKFRONTS line "all sitting at 0 / dead-branch" was
wrong about the lum_* vars; corrected by tracing.

**#36d follow-up: canFlip preconditions stale (CLOSED Day-15 part 6).**
`tryFlipToTableMode` originally required `exp_anchor_set &&
exp_tv_ceiling_sec != 0 && current_tv.length() > 0`. These existed
to feed `findTableRowForTv`, retired Day-15 part 3. Decision: the
execute UI (planned, separate workfront) prevents uninitialised
cart starts upstream, so the gates protected against a case that
can't happen at runtime. Removed. Also aligns with photos-sacred
+ autonomous-cart framing: if CCAPI fails, reaching TABLE is the
right move regardless of init state.

**#36d follow-up: TABLE-during-comms-dead semantic question
(CLOSED Day 15).** Question was: in TABLE, should we PUT Tv/ISO
to the camera over CCAPI (which we can't reach), or just walk
the table cart-side and let the camera stay frozen? Resolved
by the camera-as-AP decision (see fallback architecture
section above): with the external AP removed, the only outage
mode is camera-side WiFi failure (accepted risk, rare). When
that happens, TABLE walks cart-side state only; camera stays
frozen; LRTimelapse fixes drift in post. (a) accepted.

**#48 /shutter/stop bus fault — CLOSED Day-15 part 7.**
Resolution: minimal /stop handler. `ccapiStopLiveview()` removed
from the /stop path; that DELETE was housekeeping (the camera
times out its own liveview session and `ccapiStartLiveview()`
already handles "Already started" 503 from leftover sessions).
/stop now only sets `shutter_mode = 0`, clears pause, prints
summary. Cannot crash because no blocking network or CAN call.
Verified across two full /start → photos → /stop cycles, both
clean.

**Investigation summary (kept here for v2 reference):**

The crash was intermittent, in `WiFiClient::read` /
`Stream::readStringUntil` inside the DELETE call. addr2line on
crash dumps showed two distinct mechanisms:
- Mechanism A (3 of 4 dumps): CAN RX ISR preempted into the
  WiFi read at the wrong moment. `CanMsgRingbuffer::enqueue`
  wrote to a corrupted address — measured addresses were valid
  heap pointers with bit 16 or 17 flipped (0x20025961, 0x200259d2,
  0x2002ba5a — all OUTSIDE the 32 KB SRAM region).
- Mechanism B (1 of 4 dumps): crash in same WiFi read, but no
  CAN ISR in the stack. Fault address 0x810076c3 — different
  pattern, high bit set. Some other corruption source.

Stack measurement showed 1024/1024 bytes used in normal idle
operation (Uno R4 stack region is only 1 KB). Strongly suggestive
that ISR preempt has nowhere safe to push registers, but didn't
fully explain mechanism B.

**Things tried that didn't fix it:**
- Char-buffer reads in ccapiRequest (Day-15 part 7 fix attempt 1):
  removed our String allocations, but WiFiS3 library allocates
  Strings inside `client.read()` itself. Reverted.
- `enablePush(false)` + delay before DELETE (fix attempt 2):
  silenced CAN traffic during the vulnerable window. Removed CAN
  ISR from the crash stack but mechanism B still crashed. Reverted.
- v3 regression test: pre-cleanup sketch ran clean once but crashed
  on second test. Bug is intermittent on identical code.

**Why the bug appeared only on Day 15:** unclear. /stop call path
(`ccapiStopLiveview` → `ccapiRequest`) is unchanged from Day 14
era. Possibilities not investigated: heap fragmentation pattern
from accumulated WiFi traffic over longer test sessions; transceiver
replacement timing (some crashes happened with original transceiver,
some with replacement, so not a clean dividing line); or simply
more /stop tests today than ever in one session (statistical
exposure).

**Note on "hardware-damaging" claim from Day-15 part 5:** the
in-RAM corruption mechanism has no obvious path to damaging the
external transceiver chip. Transceiver death may be unrelated to
the bus fault; cause genuinely unknown. The Day-15 part 5
assertion is unsupported by evidence.

**For v2 (#47, Giga + Ethernet):** the WiFi-blocking-read +
CAN-ISR combination doesn't exist on v2 (camera over wired
Ethernet, different stack, much more SRAM). Whether to restore
the polite DELETE on /stop in v2 is a decision for that build —
measure first if the crash mechanism still surfaces.

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

**#10a Gimbal UI page — DELIVERED Day 16.** Implemented as Gimbal
Recon screen on the unified UI (one URL, server-side
`?screen=cart|gimbal|exec` routing, not a separate URL as Day-8
proposed). Spec: UI_DESIGN_v2.md (Day-15 Part 10). GIMBAL_VIZ.md §3
annotated as superseded by this delivery.

Built:
- Live readout `Ry · Cy · p` (Ry=Cy until BNO integration)
- 4 prior captured-row slots + Current row block (newest at slot
  closest to buttons)
- Type rows: PF / Lock / Move / Track sun (operator-authored);
  Sunrise / Sunset / MW (astro)
- Conditional sub-controls: keyframe (rise/mid/end) for astro,
  R/C frame toggle for PF+Move, yaw Δ / pitch Δ for astro,
  measured-variance line for astro
- Label field, Clear button on Current row
- Action row: Show astro / Snap var (TODO stubs — see #50) / Next
- Per-type pose handling: PF/Lock/Move capture pose AND write to
  cart gimbalLog via /btn20; astro and Track sun are intent-only
  with no pose, no gimbalLog write

Production-readiness pending #49 (rich-row persistence).

**#10b Notes / hints panel on cart UI (CLOSED Day-15 part 7).**
Built — multi-line text panel rendered below the action buttons
on Cart Recon screen. Day-16 build preserved the content (turning-
circle table) and moved it under the new Cart Recon screen.

Current content:
- Turning-circle table (servo 5°/10°/15°/20°/25°/30° → diameter
  18.0/10.0/7.5/5.6/4.8/4.2 m, tightest = 30°). Absorbed from
  retired #29a workfront.

The /stop warning that was planned for this panel is no longer
needed — #48 was resolved separately in Day-15 part 7 by making
/stop a no-op for housekeeping.

Add further tips by inserting `client.println` lines inside the
notes `<div>` block (Cart Recon body in v1prod sketch).

**#49 Gimbal Recon rich-row persistence (NEW Day 16).** Gimbal Recon
captured rows live client-side only as built; reload kills type/
label/keyframe/offset data. Cart-side struct extension + push
endpoint required before Gimbal Recon is production-usable.

*Scope:*
- Extend `GimbalLogEntry` struct with: type (1B enum), kf (1B enum),
  fr (1B enum), offY (float), offP (float), label (12-char fixed
  array — avoids heap fragmentation, #48 contributor)
- New endpoint `/gimballog/push?rows=...` accepting query-encoded
  rich rows; clears existing gimbalLog and replaces
- Gimbal Recon JS calls /gimballog/push on every Next-bake (or on
  a new explicit "Push to cart" button) instead of /btn20
- /gimballog Excel-pull endpoint returns the rich CSV; Excel parser
  updates for new columns

*Costs:* ~+600 bytes SRAM globals (struct grows, ~30B × ~20 slots).
68.9% → ~70.7% — still well clear of the ceiling that bit Day 7's
CART_LOG_MAX bump.

*Risks:* heap fragmentation from String labels — fixed-size char
array mitigates. Excel parser change requires coordinated update.

*Verification path:* author 5 mixed-type rows, reload page, captured
list reconstructs from /gimballog; pull from separate tab confirms
all rich fields; pose-types still write yaw/pitch, intent-types
carry zero pose.

**#50 Excel astro position push to cart (NEW Day 16).** Unlocks the
Show astro and Snap var buttons on Gimbal Recon.

*Architecture (Path A chosen Day 16):* Excel pre-computes today's
astro positions and pushes to cart in a new settings field. Cart
stores 7 yaw/pitch pairs (sun rise/set, moon rise/set, MW rise/
mid/end ≈ 56 bytes + 1 mask byte). On Show astro tap with
type+keyframe context, cart commands gimbal to stored position.

Path B (cart computes astro on-the-fly via ported `GetSunGimbalAngles`)
was considered and rejected — duplicates Excel logic, larger flash
hit, conflicts with day-8 architecture "astro pre-baked in Excel,
cart sees cubic coefficients only."

*Scope (final after Day 17 build):*
- Excel side: button to "Push astro to cart" that calls
  `GetSunGimbalAngles` / `GetGCGimbalAngles` for sun + MW (already
  built in Astro.bas), and new moon astro maths (see #55), posts
  to cart endpoint `/settings/astropos?...`
- Cart side ✅ BUILT Day 17 (second session). 10 globals + mask,
  `/settings/astropos` GET/POST, `/gimbal/showastro?type=...&kf=...`,
  `/gimbal/snapvar?type=...&kf=...`, `/gimbal/showastrooffset?...`
  (workflow B for typed-offset verification, not in UI)
- UI side ✅ BUILT Day 17 (second session). Show astro / Snap var
  buttons wired; Sunrise/Sunset/Moonrise/Moonset/MW type buttons;
  keyframe sub-row appears for MW only.

*Cart vocabulary:*
- types: sun, moon, mw
- keyframes: sun/moon → rise|set; mw → rise|mid|end
- URL params: sry/srp (sun rise), ssy/ssp (sun set),
  mnry/mnrp (moon rise), mnsy/mnsp (moon set),
  mry/mrp (mw rise), mmy/mmp (mw mid), mey/mep (mw end)

*Dispatch-order bug found and fixed Day 17:* original
`path.startsWith("/gimbal/showastro")` matched both showastro AND
showastrooffset (prefix collision). Changed to
`path == "/gimbal/showastro" || path.startsWith("/gimbal/showastro?")`.

*Status:* cart side ✅ done. Excel side pending — see #55 for
moon maths, #50-Excel for push button.

**#55 Moon astronomy maths in Excel — CLOSED Day 18.** Full
sun-equivalent treatment delivered: local Schlyter low-precision
ephemeris in Astro.bas (GetMoonPosition + public wrappers),
FindMoonCrossing/BisectMoonAltitude root finder, AstroPush.bas
populates mnry/mnrp/mnsy/mnsp on /settings/astropos and adds
moon as third object to /settings/trackpath. Window selection
handles all four cases: rise+set in envelope, rise-only,
set-only (moon up at sunset), neither. Validated against
timeanddate.com for Adelaide 25-May-2026: local moonset 01:07
vs timeanddate 01:09 — 2-minute agreement (~0.5° at moon's
apparent motion), well inside 14mm FOV tolerance.

**Note on data source:** initially planned to use api.sunrisesunset.io
for moon rise/set times. Cross-check vs timeanddate.com Day 18
revealed the API was 64 minutes off (reported 02:11 vs
correct 01:09). Local maths in Astro.bas was 2 min off.
Local wins on both accuracy and offline operation — API path
dropped from the design entirely. Zero internet dependency
for any astronomical computation now (closes part of #57).

End-to-end test (Day 18): PushAstroToCart returned mask=11
(sun_rise + sun_set + moon_set) with moon_set yaw 274.90° /
pitch -0.50° — matches timeanddate's 275° azimuth within 0.1°.
PushTrackPathsToCart pushed sun (4 segs) + moon (4 segs) + MW
(4 segs) successfully.

**#56 Morning astronomical dawn missing in Excel — PARTIAL Day 18.**
Sun computation moved fully local Day 18. Astro.bas
FindSunCrossing(date, targetAlt, dir) computes all 8 sun
crossings — sunrise/sunset/civil dawn/civil dusk/nautical
dawn/nautical dusk/astro dawn/astro dusk. GetSunsetTime now
populates dataSunsetTime/SunriseTime/CivilDawn/CivilDusk/
NauticalDusk/AstroDusk. Still missing on Settings sheet:
dataNauticalDawn, dataAstroDawn (need named ranges added).
Tonight (Day 18) MW push worked using the existing
sunrise-90min proxy via the +24h workaround. Real fix wants
the morning twilight ranges populated AND the dark-window
end-of-dark logic to use dataAstroDawn (tomorrow's) instead
of dataPhase4aStart. Defer to next pass.

Note: the existing "phase 1-5" scheme in CalculatePhaseTimes is
internal scaffolding (sunset-anchored offsets, not astronomy);
don't treat it as authoritative twilight data. See #64.

**#57 Shoot-date anchor for Excel astro (NEW Day 17).** Today
Excel computes everything from `Now()` / today's calendar date.
That's wrong for the operator's actual workflow:
- Shoots typically run dusk-to-dawn crossing midnight. The
  "dawn" of the shoot is the NEXT calendar day's sunrise.
  CalculatePhaseTimes uses today's sunrise instead, which is
  morning-already-past â€” useless.
- Operator often prepares the shoot earlier (different date),
  potentially without internet. Today's flow requires running
  Get Sunset Time on the day of the shoot.

Fix: add `dataShootDate` named range (defaults to today, operator
can edit). All astro reads/computes anchor on that date. API
calls (when available) cache values per-date. Local astro
(Astro.bas) already takes atTime parameter so works correctly
once given the right date.

This was uncovered during Day-17 push-astro testing: Push Astro
to Cart found MW core never above horizon in tonight's dark
window because dataPhase4aStart was computed from today's
sunrise (this morning), making the For-loop window go
backwards (dusk 18:44 â†’ "dawn" 05:37 same calendar day).

Workaround for early Day-17 testing: in PushAstroToCart, detect
when sunrise < dusk and add 24h locally. Real fix is #57.

**#58 Track-path cubic segments stuck at N=2 by SRAM (NEW Day 17).**
Cart's TRACK_SEGS_MAX is 2 due to RAM pressure on Uno R4. With
N=2 the MW core fit has 20Â° yaw / 2.75Â° pitch worst-case error
near zenith. With N=4 the error drops to ~9Â° yaw / 0.85Â° pitch
(zenith-segment only; other segments <0.5Â°). N=4 doesn't link
because the toolchain reserves an 8 KB heap region that pins
the global ceiling.

Same SRAM ceiling also blocks: the `/debug/trackplan?idx=N`
read-back endpoint (removed); the Track runtime block (1 Hz
plan-runner check, cubic eval, setPosControl) â€” a self-contained
~80 lines in `loop()` that won't link.

Excel side has freeze logic implemented (in FitAndPushTrackPath,
samples with pitch > 80Â° use constant yaw rather than fitting
through nonsense). Push pipeline + cubic storage + /debug/trackeval
all working at N=2.

Path forward (any of):
- Halve lum_resp_buf (4096 â†’ 2048) to free 2 KB. Risk: luminance
  HTTP responses can hit 4.5 KB; truncation may break the
  "histogram":[[ scan. Verify with sample R3 responses first.
- Use slice-by-16 CRC32 (64-byte table) instead of slice-by-8
  (1024-byte table). Saves 960 bytes. Touches CRC code path.
- Shrink other globals (CartLogEntry, GimbalLogEntry buffers).
- Migrate to Giga R1 (#47) which has 1 MB SRAM â€” no contention.

Acceptance at N=2: yaw error projects to ~7 pixels at 14mm in
worst case (yaw error Ã— cos(pitch)). Below visible threshold
for current shoots. Real fix needed before Track runtime block
can be added.

**#59 Track runtime integration in cart plan-runner (NEW Day 17).**
Blocked on #58 (SRAM). When SRAM cleanup lands, add a 1 Hz block
in `loop()` that:
- Computes shoot_time = millis() - track_plan_anchor_ms
- Linear-scans track_plan[0..count-1] for the active interval
  (one where ts_ms <= shoot_time < te_ms)
- If active: picks that interval's object cubic from track_<obj>,
  evaluates at t=(now - tp->t0_ms)/1000, applies offY/offP, calls
  setPosControl with the result
- Mode FULL: yaw = cubic + offY, pitch = cubic + offP
- Mode YAW:  yaw = cubic + offY, pitch = offP (fixed)
- Today setPosControl is called with world-frame yaw direct (Ry=Cy
  shortcut). When #40 BNO lands the conversion becomes
  `cart_yaw = world_yaw - cart_real_heading`.

Code drafted Day 17 but reverted after failing to link. See
git history (or this WORKFRONTS entry) for the block.

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

**#20 Circle test.** DONE Day 15 part 4. Six diameters measured
at servo offsets 5°/10°/15°/20°/25°/30°: 18.0/10.0/7.5/5.6/4.8/4.2 m.
Table in PROJECT_STATE Day-15 part 4. Bicycle-model fit declined
(40% climb in Ackermann constant = R×δ across the range; pure
bicycle with linear linkage doesn't fit; radius-only data has
L/k ambiguity anyway). Table used directly as operator lookup.

**#21 S-bend test.** Per #20 trigger condition ("only if straight
+ circle don't match bicycle model"): #20 showed mismatch, so #21
is technically triggered. But — per principle #15 + measurement
tolerances on SCX6 (long-travel suspension, tyre scrub, ±0.5m
honest), refining the physical model further isn't earning its
keep right now. Park unless a specific shoot needs sub-meter trace
accuracy. If revisited: also measure wheelbase static and one
front-wheel angle, to break the L/k ambiguity.

**#29 Refine servo-to-wheel calibration.** PARTIALLY DONE Day-15
part 4. The six-row turning-diameter table is the calibration. Full
"servo-to-wheel angle" decomposition not derivable from radius data
alone (needs independent measurement); not pursued. The table is
sufficient for visualisation/smoothing structure and for #29a
operator advice. Whether it's sufficient for COMMITTING executed
Plans depends on shoot tolerances — revisit if a shoot demands
sub-meter trace fidelity.

**#29a Operator-facing turn advice.** MOVED to cart-UI section
below (#10b notes/hints panel). Data table from Day-15 part 4
becomes one of the hints in that panel.

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
- **#36d Step 4 (per-cycle PUTs from TABLE)** — Day 15
  part 2 CLOSED for v1 (logically impossible — CCAPI
  unreachable in TABLE). Re-opens as a v2 build task.
- **#36d v1 TABLE simplification** — Day 15 part 3 done;
  retired `exp_delta_t_rel`, `last_table_tv/iso`,
  `findTableRowForTv()`, `/debug/match` and associated
  Serial logs / JSON fields. v1 sketch −143 lines.
  End-to-end verified 104/104 photos.
- **#20 Circle test** — Day 15 part 4 done; 6-row diameter
  table at 5°/10°/15°/20°/25°/30° servo. Bicycle fit declined
  (model mismatch + radius-only ambiguity). Table used directly
  as operator lookup. See PROJECT_STATE Day-15 part 4.
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
- **#10a Gimbal UI page** — Day 16 DELIVERED as Gimbal Recon
  screen on unified UI (one URL with ?screen= routing). Spec
  UI_DESIGN_v2.md. GIMBAL_VIZ.md §3 superseded. Production-
  readiness pending #49.
- **#29 Mark Waypoint button** — Day 16 DELIVERED as btn22 on
  Cart Recon screen. Writes new `'W'` event into CartLog with
  recon-session waypoint number as value. Operator-verified
  end-to-end.
