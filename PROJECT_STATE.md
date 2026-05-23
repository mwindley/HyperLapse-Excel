# HyperLapse Cart — Project State

**Last updated:** 23 May 2026 (Session C day 17 — **plan execution fully
characterised and verified end-to-end across all segment types and stop
styles**. The full day arc: started with a 3-segment plan that wouldn't
execute correctly; ended with a complete authoring vocabulary working as
designed and a clean production sketch.

Bugs found and fixed today, all via instrumentation-first diagnosis:

1. **Bogus rear-Tic delta negation** in `planTick`, `planStatusCSV`, and
   `/plan/nudge`. A `delta = -delta;` line, justified by a "rear Tic
   wired physically reversed" comment, made segment-complete check the
   wrong sign. Forward MOVE segments would never complete. Negations
   were not in the Day-15 v1prod branch point — added in uncommitted
   edits from a prior Claude session that crashed before testing.
   Verified empirically with `/debug/tic` after a manual forward drive:
   both Tics report positive position on cart-forward (~1% apart, the
   overdrive ratio). Removed; rear-Tic counts in the natural direction.

2. **I²C "cliff"** during plan execution. `planTick` was reading
   `ticRear.getCurrentPosition()` every main-loop iteration. After a
   variable run time (observed 7s, 17s, 128s across multiple tests),
   both Tics simultaneously NACK on the bus (Wire error code 2) and
   stop responding for the rest of the run. Cart kept moving on the
   last commanded velocity (Tic motors audibly unchanged). Throttled
   the read to 100ms cadence; cliff did not recur in any test
   thereafter. Mechanism not characterised — workfront #52, parked
   under avoidance.

3. **STOP-segment duration timer counted from segment entry, not
   from at-rest.** A 5-second STOP after a 30 m/hr cruise actually held
   only ~1.5 seconds at rest because the Tic STOP_DECEL ramp ate 3.5s
   of the window. Added an "at-rest gate" in `planTick` END_DURATION
   that polls both Tic velocities every 250ms; counts duration only
   from the moment both reach 0. Verified: 30 m/hr → SEG STOP(5s)
   takes 5.3s decel + 5s hold = 10.3s, cart genuinely still for the
   full 5s.

4. **Stop-style dispatcher (TR_S / TR_E / TR_D) pointless as written.**
   Each "stop" case did `cartStop()` THEN immediately
   `cartSetSpeed(speed_mhr)` — Tic got two velocity targets in
   microseconds and ignored the first. No actual stop happened.
   Rewrote dispatcher with revised semantics:
   - **M** (merge) — MOVE-only. Slam target speed; Tic accel/decel
     handles ramp. Default for MOVE.
   - **S** (decel) — STOP-only. `cartSetSpeed(0)`, Tic STOP_DECEL ramp
     to rest. Then hold via at-rest gate. Default for STOP.
   - **E** (emergency) — STOP-only. `cartDeadStop()` (Tic haltAndHold)
     for instant halt. Then hold.
   - **D** (decay) — STOP-only. `cartStartDecay()` arms linear ramp
     from current speed to 0 over `cart_decay_ms` (6 min production).
     Distance is derived, not specified. Then hold.

5. **Decay-loop wrap-around bug** that hid bug #4's true fix. When
   `cartStartDecay()` is called from inside `planTick` (which runs at
   the top of `cartLoop`), `cart_decay_start = millis()` is set AFTER
   `now = millis()` was captured at the top of cartLoop. The next
   line, `elapsed = now - cart_decay_start`, then underflows
   unsigned: tiny-negative becomes ~4 billion. `elapsed >=
   cart_decay_ms` becomes true on the same loop pass, triggering
   `cartStop()` — instant termination of the decay we just armed.
   Fixed with `if ((long)(now - cart_decay_start) < 0) elapsed = 0;`
   to handle the same-iteration decay-arm case. Verified: 60s decay
   ran linearly to zero, factor untouched until ramp complete.

Test-bank validation (all green):
- Bank A2 — STOP segment with END_DURATION (5s hold, true rest)
- Bank B-S — decelerated stop (~5.3s decel from 30 m/hr)
- Bank B-E — emergency stop (~30ms halt via haltAndHold)
- Bank B-D — decay stop (60s linear ramp from 30 m/hr to 0)
- Bank C1 — `/plan/stop` mid-MOVE (aborts plan, ramps cart down)
- Bank C2 — `/btn11` mid-MOVE (stops cart, plan stays RUNNING)
- Bank C3 — `/btn12` mid-MOVE (instant halt, plan stays RUNNING)
- Bank D1 — `/plan/nudge?d=100` extends current segment by 100mm
- Bank D2 — `/plan/nudge?d=-100` with plenty left, target shrinks
- Bank D3 — `/plan/nudge?d=-100` past zero, segment immediate complete
- Bank D4 — nudge on STOP segment rejected
- Bank E1 — multi-segment plan with steering (+5°, -5°, S-curve)

New sketch infrastructure (kept in production):
- `cart_decay_ms` (global, default 360000 / 6 min) replaces the prior
  `const CART_DECAY_MS`. Adjustable via `/debug/decaytime?ms=N`.
- `plantick_dist_last_ms` (100ms throttle for planTick END_DIST read).
- At-rest gate state in planTick END_DURATION (per-segment statics).
- `getLastError()` check after each Tic read in END_DIST — logs
  only on non-zero so a Tic comms collapse surfaces immediately
  without per-tick noise.

Diagnostic instrumentation removed from sketch at end of session:
- PTICK every-500ms probe block
- Post-stop PROBE every-100ms sampler
- DUR elapsed-since-rest 500ms probe
- TR_DECAY pre/post-startDecay diagnostic prints
- `stop_probe_until_ms`, `stop_probe_last_sample_ms`,
  `plantick_probe_last_ms` globals

Sketch 5140 → 5553 lines (+413 net, all production code, no diagnostics).

**Earlier Day 16 below.** Three-screen UI v2 foundation delivered.
Server-side routing on `?screen=cart|gimbal|exec`, shared header with
logo row + 4-tab bar, day palette baked in. **Cart Recon: full build**
— status line (voltage · motor state),
Last/Now waypoint rows, steering/speed/motor/action button rows,
turning-circle notes panel. New `'W'` CartLog event carries the
recon-session waypoint number; new `cart_motor_state` software flag
(DE-E/STOP/ENRG) wired through cartStop/cartDeadStop/cartSetSpeed/
cartEnergise/cartDeenergise; `/status` extended with v[10] motor
state, v[11] waypoint count, v[12] mm-since-last-waypoint; new btn22
Mark wpt handler with confirm. Operator verified end-to-end
(+5/+5/+5 cumulative steering, Last/Now roll-over, d-distance ticks,
Clear logs zeroes back to "—"). **Gimbal Recon: full build,
client-side state** — live readout `Ry · Cy · p` (Ry=Cy until BNO
integration); 4 prior slots + Current row block; type rows
PF/Lock/Move/Track sun + Sunrise/Sunset/MW; conditional sub-controls
(keyframe for astro, R/C frame for PF+Move, yaw Δ / pitch Δ for
astro, measured-variance line); label field; Show astro / Snap var
(TODO stubs pending Excel astro push) / Next action row. Per-type
pose handling: PF/Lock/Move capture pose AND write to cart gimbalLog
via /btn20; astro and Track sun are intent-only with no pose, no
gimbalLog write. Newest at slot c3 (just above Current), older
pushed up and off the top; Clear button on Current for mini-edit
without baking. iOS auto-zoom fixed (inputs at font-size:16px).
**JS escape-quote bug caught and fixed mid-build** — broken `\\'s`
inside an alert() string threw a syntax error and killed the entire
script (live readout stuck on dashes). New build lesson recorded
in PREFERENCES. **Execution screen: placeholder only** — header +
tabs work, body says "Coming next". Deferred until #5a segment
dispatcher + speed transition types + ±100mm nudge endpoint +
PAUSE/RESUME backend are built. Sketch 4843 → 5140 lines (+297 net);
SRAM globals +9 bytes. **Day 16 hygiene:** UI_DESIGN_SUMMARY.md
moved to ARCHIVE/ (superseded by UI_DESIGN_v2.md + Day 16 build);
GIMBAL_VIZ.md §3 / §9 / §10 annotated with superseded-by pointers.
**Earlier Day 15 below.** Day-15 part 7: #48 bus fault localised
via addr2line. Crash is in `WiFiClient::read` /
`Stream::readStringUntil` inside `ccapiStopLiveview()`'s
HTTP DELETE. Sometimes preempted by CAN RX ISR (3 of 4 dumps),
sometimes not (1 of 4). Stack measurement showed 1024/1024 used
in normal idle operation (stack is only 1 KB). Fix attempt 1
(char-buffer reads in ccapiRequest) ruled out — WiFi library
allocates Strings internally. Fix attempt 2 (`enablePush(false)`
+ delay before DELETE) removed CAN ISR from the crash stack but
crash persisted from a second mechanism. **Resolution: minimal
/stop handler.** The `ccapiStopLiveview()` call was housekeeping
(politely close camera liveview session); not required for
correctness because `ccapiStartLiveview()` already handles
"Already started" 503 from stale sessions. Removed from /stop
handler. /stop now does only local flag writes + serial log.
Verified across two full /start → photos → /stop cycles, both
clean, both started fresh liveview on next /start. #48 closed
for v1. v1 sketch current at /mnt/user-data/outputs/.)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

Also upload `PREFERENCES.md`, `GIMBAL_VIZ.md`, `WORKFRONTS.md`,
`EXPOSURE_FALLBACK.md`, and `UI_DESIGN_v2.md` — working agreement,
gimbal visualisation design (with Day-16 superseded-by annotations),
open task list, exposure fallback design (with reference table as
Appendix A), and the current authoritative UI spec. The Day-10
`UI_DESIGN_SUMMARY.md` is in ARCHIVE/ as of Day 16 — superseded by
UI_DESIGN_v2 + the Day-16 build.

Older session detail (days 5–11) lives in `PROJECT_STATE_old_ver1.md`.
This file keeps only what the next session needs to read to start work.

---

## Day-17 session — first successful plan execution (two bugs fixed)

Build + diagnostic session. The first attempt to run a multi-segment
plan end-to-end surfaced two faults. Both diagnosed via instrumentation
(oscilloscope approach — see PREFERENCES), then fixed. End-to-end
verification on the third clean test of the day.

### Bug 1 — bogus rear-Tic position negation

**Symptom.** Plan starts cleanly, SEG 1 dispatched, cart drives at
30 m/hr, but segment never completes. Cart drives past the planned
distance and continues until forcibly stopped.

**Diagnosis path.** Added PTICK probe to `planTick` printing `rear.pos`,
computed `delta`, and `target` every 500ms. Trace showed `rear.pos`
climbing positive (3 → 196 → 638 → ... → 628274) on cart-forward, but
the computed `delta` was negative the same magnitude (−628274), never
reaching the positive `target` (565000 steps = 1000mm). Cause: a
`delta = -delta;` line in `planTick`, mirrored in `planStatusCSV` and
`/plan/nudge`, with a comment claiming the rear Tic was "wired physically
reversed." Git blame against the Day-15 v1prod branch point showed
those negations were not in the original code; they had been added in
**uncommitted** edits before this session — from a prior Claude session
that crashed before testing the change.

**Verification before fix.** Ran a manual forward drive in Cart Recon
(no plan), then `/debug/tic`. Both Tics reported positive position
(rear=877,431; front=886,988; ~1% apart, the overdrive ratio). Confirmed
both motors count positive on cart-forward — no opposite-direction
quirk at the position-readback level. Whatever Tic-config inversion
gives the two motors their opposite physical rotation (to drive the
cart forward) is invisible at the library level; `getCurrentPosition`
returns positive numbers from both.

**Fix.** Removed the three `delta = -delta;` lines (planTick:2084,
planStatusCSV:2458, /plan/nudge:5049). Kept the legitimate
`if (speed_mhr < 0) delta = -delta;` lines below them — those handle
plan-authored reverse-direction MOVE segments and remain correct.
Updated comments to record the correct direction observation.

### Bug 2 — I²C "cliff" (Tic comms collapse) during plan execution

**Symptom.** During plan execution, after a variable run time, both
Tic controllers simultaneously stop ACKing on the I²C bus. From that
moment on every `getCurrentPosition()` / `getCurrentVelocity()` returns
0, every `getLastError()` returns 2 (Wire library: address-NACK), and
all subsequent stop commands (`/plan/stop`, `/btn11`, `/btn12`, etc.)
cannot reach the Tics. The Tics themselves continue executing the last
velocity command they received, so the cart runs at full commanded
speed until power-killed manually. Tic motors keep singing at the same
pitch through the cliff — confirms motor command unchanged, only Uno→Tic
comms dead.

**Diagnosis path.** PTICK probe extended with `getLastError()` after
each Tic read. Trace showed clean `(e0)` reads while cart accelerated
to commanded speed; reads then continued cleanly during cruise with
`rear.vel` and `front.vel` locked at the bit-exact commanded values
(`49913765` / `51724110`); at the cliff instant **all three reads
(rear.pos, rear.vel, front.vel) flipped from e0 to e2 simultaneously**.
Cliff timing across three runs: t+128s, t+7s, t+17s — highly
intermittent, not load-bound, not time-bound.

Read-rate inspection of the sketch showed `planTick()` calls
`ticRear.getCurrentPosition()` every main-loop iteration. With no
blocking work in the loop that's hundreds of I²C transactions per
second, all addressed at the rear Tic. Cart Recon (which works fine
indefinitely) only reads via `/status` every 3 seconds — orders of
magnitude lower.

**Hypothesis (not proven, but consistent).** Sustained high-rate I²C
polling against the Tic at the rates `planTick` was running it
eventually corrupts the bus or wedges the slave-side state machine,
producing the sudden simultaneous NACK on both addresses. No deeper
mechanism investigation done; the avoidance fix below proved sufficient.

**Fix.** Throttled `planTick`'s END_DIST read to 100ms cadence. At
30 m/hr the cart covers 8.3mm in 100ms; at 50 m/hr 13.9mm. Worst-case
segment-complete overshoot is ~14mm against multi-hundred-mm segments
— well within shoot tolerance and below the documented turning-circle
measurement noise. Other Tic reads (Cart Recon `/status`, cart log
captures, voltage poll every 2s, debug endpoints) were already
appropriately throttled.

### Validation run

Third end-to-end test of the day after both fixes applied:

```
/plan/load?n=3&s1=m,1000,0,30,d&s2=m,500,0,50,d&s3=s,0,0,0,o
/plan/start
```

Observed:
- SEG 1 (MOVE 1000mm @ 30 m/hr) dispatched, cart accelerated to commanded
  speed via Tic ramp, delta climbed cleanly toward 565000 steps target
- SEG 1 complete at t+115.3s (theory: 120s, actual is slightly under
  due to the initial accel ramp covering part of the distance)
- SEG 2 (MOVE 500mm @ 50 m/hr) entered, `plan_seg_start_rear=565349`
  (captured correctly from SEG 1 end). Velocity ramped 30 → 50 m/hr
  smoothly via `tr=M`. Delta climbed to target 282500
- SEG 2 complete at t+34.2s after SEG 2 entry (theory 36s)
- SEG 3 (STOP, end=operator) entered. Cart halted as part of plan
  execution

No cliff (e2) anywhere in the run. Plan ran to STOP as authored.

### Files modified this session

- `DJI_Ronin_UnoR4_v1prod.ino`:
  - Removed three `delta = -delta;` lines (Bug 1)
  - Added 100ms throttle to `planTick` END_DIST (Bug 2 avoidance)
  - Replaced `CART_DECAY_MS` constant with mutable `cart_decay_ms`
    (default 360000 / 6 min for production); added
    `/debug/decaytime?ms=N` for testing
  - Rewrote `planSegmentEnter` dispatcher with corrected M/S/E/D
    semantics (Bug 4)
  - Added at-rest gate in `planTick` END_DURATION (Bug 3)
  - Fixed decay-loop unsigned-subtraction underflow (Bug 5)
  - Added `getLastError()` check after rear-pos read in END_DIST —
    logs only on non-zero error code
  - Added probe instrumentation for diagnosis, then removed all of
    it at end of session (PTICK probe, PROBE in cartLoop, DUR probe,
    TR_DECAY probe)

### Test-bank validation results

| Bank | Test | Result |
|---|---|---|
| A2 | STOP segment with END_DURATION (5s) | ✓ at-rest gate working |
| B-S | Decelerated stop (Tic STOP_DECEL ramp) | ✓ ~5.3s decel + hold |
| B-E | Emergency stop (cartDeadStop) | ✓ ~30ms halt + hold |
| B-D | Decay stop (linear ramp over cart_decay_ms) | ✓ 60s linear ramp |
| C1 | `/plan/stop` mid-MOVE | ✓ abort + ramp |
| C2 | `/btn11` mid-MOVE | ✓ stop, plan stays RUNNING |
| C3 | `/btn12` mid-MOVE | ✓ instant halt, plan stays RUNNING |
| D1 | `/plan/nudge?d=100` | ✓ target extends |
| D2 | `/plan/nudge?d=-100` (left in seg) | ✓ target shrinks |
| D3 | `/plan/nudge?d=-100` past zero | ✓ immediate segment complete |
| D4 | nudge on STOP segment | ✓ rejected cleanly |
| E1 | Multi-segment with steering | ✓ steering per-segment works |

### Mental model corrections recorded

- **A prior crashed Claude session can leave uncommitted edits in the
  working tree.** Today's Bug 1 came in via the prior-Claude
  edits. The protective practice is to verify a planTick-style change
  by checking against the latest committed version with `git diff` (or
  recent-commit `git show`) before treating the local file as
  authoritative.
- **A "comment that explains a counterintuitive thing" is high-risk
  signal, not high-trust signal.** The "rear Tic wired physically
  reversed" comment was the rationalisation, not the truth. Verifying
  comment claims empirically (manual drive + `/debug/tic`) was a
  one-minute test that should have happened earlier.
- **I²C cliffs are quiet.** No exception, no Serial diagnostic, no
  watchdog reset — just a flip from e0 to e2 and 28+ seconds of
  successful zero-returns from the library that look like "Tic is
  fine, at rest." Without `getLastError()` instrumentation the
  failure mode is invisible. The new on-error-only print in
  `planTick` END_DIST is the standardised check going forward.
- **`millis()` captured at the top of a loop iteration is stale by
  the time inner code completes.** Bug 5 (decay underflow) is the
  worked example. When passing `now` down to sub-blocks that may
  themselves call `millis()`, guard against the timestamp ordering
  not matching code-execution order.
- **A "stop" command followed by an immediate "set speed" is
  identical to "set speed" alone** — the Tic accepts the latest
  target and discards the earlier one. Apparently "stop then go"
  needs an in-between gate (the at-rest check) for any actual stop
  to happen. Bug 4 is the worked example.

### Path back into this work

Plan execution is now production-quality. Outstanding work in this area:

- **Workfront #52 — I²C cliff root cause.** Avoidance fix (100ms
  throttle) is sufficient for now. If the cliff recurs at lower read
  rates, scope the SDA/SCL lines and check pull-up strength.
- **Workfront #51 — was "remove Day-17 diagnostics."** Done this
  session at end. Close.
- Execution screen UI (the placeholder from Day 16) now has a working
  backend; can be wired up when ready. Subscreen design needs the
  Plan state, segment-progress readout, ±100mm buttons, and PAUSE
  semantics decisions captured in WORKFRONTS Day-15 Part 8.

---





Build session. Server-side three-screen UI delivered, two screens
real (Cart Recon, Gimbal Recon), one placeholder (Execution). The
authoritative spec is `UI_DESIGN_v2.md` (Day 15 part 10).

### What was built

**Routing.** Single `else` block in path dispatcher parses
`?screen=cart|gimbal|exec` (default `cart`). Three HTML bodies
between a shared head + header + tab bar.

**Shared header.** Logo row (RS4 + R3 SVG icons reused from old UI)
+ 4-tab grid (Cart / Gimbal / Exec / Day). Active tab marked with
2px maroon bottom border. Day palette baked in CSS — warm grey on
warm grey, muted slate-blue buttons, maroon action, warm tan warn.
Night palette deferred to Execution screen build.

**Cart Recon screen.**

- Status line (monospace, centred): voltage · motor state
- Last row: most-recent waypoint display, empty "—" until first bake
- Now row: live preview, ticks distance from cart-log-start or last
  waypoint
- Steering row: L5 / L1 / CTR / R1 / R5 (existing btn1–5)
- Speed row: −10 / −1 / DEC / +1 / +10 (existing btn6–10)
- Motor row: STOP / DE-E (confirm) / ENRG. DEAD removed from this
  screen per v2 spec (no longer needed when only Cart-Recon work is
  happening; the Execution screen will get its own quick-stop).
- Action row: ● Cart log / Mark wpt (new, with confirm) / Clear logs
- Notes panel: turning-circle table (#10b) preserved

**Sketch additions for Cart Recon:**

- `cart_motor_state` (1 byte): software flag with values
  MOTOR_DEENERGISED / MOTOR_STOPPED / MOTOR_RUNNING. Hooks into
  cartStop, cartDeadStop, cartSetSpeed, cartEnergise, cartDeenergise.
  Decay completion already calls cartStop() so it's covered.
- `cart_waypoint_count` (4 bytes): increments per Mark wpt bake;
  reset by btn19 log-start / btn21 Clear logs / /cartlog/clear.
- `cart_last_waypoint_steps` (4 bytes): `ticRear.getCurrentPosition()`
  at last bake; reset paths same as above. The Now-row distance
  reads `(cur_steps − cart_last_waypoint_steps) / 565` mm
  (565 steps/mm from planMmToSteps calibration).
- New `'W'` event in CartLog, value = `cart_waypoint_count`. Other
  event types unchanged.
- New btn22 (Mark wpt) handler with confirm dialog in the UI.
- `/status` payload extended:
  - v[10] = motor state (0=DE-E, 1=STOP, 2=ENRG)
  - v[11] = waypoint count (recon-session local)
  - v[12] = mm since last waypoint (or cart-log-start if no W yet)

**Operator verification end-to-end.**

- ENRG → −10 m/hr → drive → STOP → status row showed "21.8v · STOP"
- L5 / L5 / L5 → Now row showed cumulative +15° steering correctly
- Mark wpt → confirm → Last rolled to #1, Now reset
- Three more bakes → Last showed #3 with d 8 (real mm covered
  between bake and stop, not noise)
- Clear logs → Last back to "—"

**Gimbal Recon screen.**

- Live readout line: `live · Ry · Cy · p` (monospace, centred).
  Ry = Cy until BNO085 integration lands (architecture: when BNO
  arrives, Ry will add cart_heading to gimbal yaw).
- Four prior slots (c0…c3) showing the four most recent baked rows.
  Newest sits in slot c3 (just above Current row), older pushed up
  toward c0 and off the top. Empty rows show grey.
- Current row block (highlighted maroon border, 5th row visually)
  with Clear button for mini-edit without baking.
- Type rows:
  - Operator-authored: PF / Lock / Move / Track sun
  - Astro: Sunrise / Sunset / MW
- Conditional sub-controls per type:
  - Keyframe (rise/mid/end): astro types only
  - R/C frame toggle (Ry/Cy): PF + Move only
  - Yaw Δ / pitch Δ offset inputs (numeric): astro types only
  - Measured-variance display line: astro types only
- Label field: free-text single-line input, 24-char limit.
- Action row: Show astro (TODO stub) / Snap var (TODO stub) /
  Next (with confirm).

**Per-type pose handling:**

| Type | Captures pose? | Writes to cart gimbalLog? |
|---|---|---|
| PF | yes | yes (via existing /btn20 path) |
| Lock | yes | yes |
| Move | yes | yes |
| Track sun | no | no (intent-only) |
| Sunrise | no | no |
| Sunset | no | no |
| MW | no | no |

Astro and Track sun rows carry intent (type + keyframe + offsets +
label) but no pose — actual pointing is computed at execution time
from astro maths.

**Client-side state.** Captured row list lives in browser memory only.
Reload kills type/label/keyframe/offset data. The cart gimbalLog
buffer still records yaw+pitch for pose-types via /btn20 so Excel
still receives those raw entries via /gimballog. Logged as #49
follow-up: persist the rich list to cart RAM before relying on this
in production.

**Show astro / Snap var.** Both pop a "not yet implemented" alert.
Mechanism is Path A from Day-16 design discussion: Excel pushes
today's astro yaw/pitch positions (sunrise/sunset/MW × rise/mid/end =
9 yaw/pitch pairs, ~50 bytes) to cart in a new settings field.
Cart commands gimbal to stored position when Show astro tapped.
Logged as #50.

**JS escape-quote bug caught and fixed mid-build.** First Gimbal
Recon flash showed dashes in the live readout and never updated.
Operator pulled the served HTML; inspection found
`'... today\\'s ...'` in an alert() string — the `\\'` produced a
literal backslash followed by a string-closing apostrophe, which
threw a syntax error and killed the entire script (live polling
included). Fix: rewrote without the apostrophe. **Build lesson
recorded in PREFERENCES** about C++ string literals containing JS
strings: each level of escaping multiplies, easy to over-escape into
broken JS. The fact that the bug surfaced in a stub-alert function
(showAstro), not in any real logic, made the symptom (no live
readout) look completely unrelated to the bug location.

**Execution screen.** Header + tabs work, body is "Coming next"
placeholder. Deferred because its prerequisites aren't built:

- Gimbal plan plumbing (segments aren't pushed yet)
- Segment dispatcher + speed transition types (Day-15 Part 9 — design
  only)
- ±100mm nudge endpoint (Day-15 Part 9 — design only)
- PAUSE/RESUME endpoint (Day-15 Part 8 — design only)
- BNO085 (#40 build phase) for anchor cluster
- Excel astro push (#50) for full chart

Building Execution tonight would have been ~70% stubs. Better to
build the firmware backend first, then the screen has real things
to show.

### Day-16 hygiene actions

- `UI_DESIGN_SUMMARY.md` (Day 10) moved to `ARCHIVE/`. It's
  superseded by `UI_DESIGN_v2.md` plus the Day-16 build, and already
  self-flagged its heading-architecture section as superseded by
  Day-13 #40.
- `GIMBAL_VIZ.md` §3 (Gimbal UI on cart), §9 (Cart/Gimbal Plan
  coupling), §10 (Open design questions) annotated with
  superseded-by callouts. §3 → UI_DESIGN_v2 Gimbal Recon. §9 →
  WORKFRONTS Day-15 Part 8 + Part 9. §10 → per-question status
  notes inline (most resolved by Day-13 #40 and Day-15 Part 8/9).
- Sections 1, 2, 4, 5, 6, 7, 8 of GIMBAL_VIZ.md remain authoritative
  reference (workflow, Plan/Execution split, segment types, SDK
  constraints, astro maths, velocity bands, Catmull-Rom).

### Memory snapshot (post-build, awaiting Verify confirmation)

- SRAM globals: +9 bytes from new state vars (1 + 4 + 4)
- Flash: +~3 KB estimated from new HTML strings (verify post-flash)
- Sketch 4843 → 5140 lines (+297 net)

### Files modified this session

- `DJI_Ronin_UnoR4_v1prod.ino` — three-screen UI replacement of
  the `else` block, new state vars, new btn22 handler, /status
  payload extension
- `GIMBAL_VIZ.md` — superseded-by annotations on §3 / §9 / §10
- `UI_DESIGN_SUMMARY.md` — moved to ARCHIVE/ (no content change)

### Mental model corrections recorded

- **Cart-side state is the source of truth for production data.**
  Cart Recon waypoint tracking (counter + steps anchor + W events)
  is cart-side and survives page reloads / tab switches via /status.
  Gimbal Recon rich-row state is client-side only and does NOT
  survive reload. Acceptable for this build (recon is a continuous
  session, operator doesn't reload mid-recon), but a real gap for
  production — #49 closes it.
- **Per-type behaviour matters in UI design.** The first Gimbal
  Recon build wrote /btn20 (gimbalLogCapture) on every Next-bake
  including astro types. Realised mid-session that astro rows have
  no meaningful pose to capture; gated /btn20 on `poseT[cur.type]`.
  Same pattern likely repeats in #50 Excel-side: astro rows
  shouldn't carry pose, just type + keyframe + offset + label.
- **Tab switching = full page reload, by design.** Server-side
  routing means each tab tap is a fresh HTTP fetch. Cart state
  reconstructs from /status; client state does not. This is
  acceptable because nothing important on Cart or Gimbal Recon
  lives only in client state — Cart Recon all server-side, Gimbal
  Recon known-ephemeral with the #49 follow-up.

### Path back into this work

A future session can re-enter the UI build by:
1. Reading UI_DESIGN_v2.md + this Day-16 entry alongside the sketch
2. Picking up at #49 (Gimbal rich-row persistence) — smallest path
   to make Gimbal Recon production-usable
3. OR picking up at #5a (segment dispatcher + transition types) —
   unlocks the Execution screen build

---



### Day-15 part 7: #48 bus fault localised via addr2line

Measured the actual crash, drilled to the cause. Did NOT speculate.

**Method:** captured fresh crash dump from current build, ran
`arm-none-eabi-addr2line` on the PC + LR + stack values against the
sketch's `.elf` file.

Build paths used:
- elf: `C:\Users\mauri\AppData\Local\arduino\sketches\
  F4FFB483BA32955ACC96AEEBF10EBF23\DJI_Ronin_UnoR4_v1prod.ino.elf`
- addr2line: `C:\Users\mauri\AppData\Local\Arduino15\packages\
  arduino\tools\arm-none-eabi-gcc\7-2017q4\bin\
  arm-none-eabi-addr2line.exe`

**Resolved call stack at crash (top-down, partial):**

```
PC = 0x0000f21a → WiFiClient::read(uint8_t*, uint32_t)
                  FifoBuffer.h:82
LR = 0x0000ed7a → FifoBuffer::available()
       0x0000ec7e → WiFiClient::read()
       0x00016742 → Stream::timedRead()
       0x00016770 → Stream::readStringUntil('\n')
       0x00005c10 → ccapiRequest    line 2341 (status-line read)
       0x0001684e → arduino::String constructor
       0x0000623a → ccapiStopLiveview  line 2489
       0x00008abe → loop, /shutter/stop handler  line 4003
       ...
       0x000131c8 → can_rx_isr                  ← CAN interrupt!
       0x00012c14 → r_can_call_callback
       0x0000c88a → R7FA4M1_CAN::onCanCallback
       0x00015efe → CanMsgRingbuffer::enqueue    line 54
```

**Concrete mechanism (measured, not guessed):**

A CAN RX interrupt fires while the WiFi blocking-read path is
constructing a `String` object on the heap (allocating memory for
the status-line buffer). The ISR calls into `CanMsgRingbuffer::enqueue`,
which executes `_buf[_head] = msg;` — a struct copy into an array
slot indexed by `_head`.

**The bus fault address `0x200259d2` is OUTSIDE Uno R4 SRAM.**
Uno R4 SRAM range is `0x20000000` to `0x20007FFF` (32 KB).
`0x200259d2` is ~150 KB above the start of SRAM, in unmapped memory.
The previous crash address `0x20025961` is in the same out-of-range
region.

**SRAM layout from `.map` file (measured, not estimated):**

```
0x20000000  __data_start__       (start of SRAM, initialised globals)
0x200002c8  __bss_start__        (uninitialised globals)
0x20005854  __bss_end__          (end of globals; 0x5854 = 22,612 bytes)
0x20005858  __HeapBase           (heap start, 4-byte aligned)
0x20007b00  __HeapLimit          (heap top / stack low limit)
0x20007b00  __StackLimit         (stack grows down from above)
0x20007f00  __StackTop           (top of usable SRAM)
                                 (vector table above)
```

- Globals: 22.5 KB (matches 68.9% of 32 KB from Verify output)
- Heap region: 0x20005858–0x20007b00 = **8,872 bytes**
- Stack region: 0x20007b00–0x20007f00 = **1,024 bytes** (only 1 KB!)
- Total usable: 31.75 KB

**Bit-flip observation (specific finding):**

Compare the fault addresses to nearby valid heap addresses:
- Fault 1: `0x20025961` vs valid heap `0x20005961` → **differ only in bit 17**
- Fault 2: `0x200259d2` vs valid heap `0x200059d2` → **differ only in bit 17**

Both faults land at structured offsets — a valid heap pointer with one
specific bit flipped (bit 17 = +0x20000). This is NOT random garbage;
it's a specific corruption pattern. The valid-region addresses
(`0x20005961`, `0x200059d2`) sit just inside the **heap region**
(0x20005858+).

So either:
- A heap pointer is having bit 17 corrupted somewhere (cosmic ray
  unlikely; more probably a structured bug — a memcpy with wrong
  offset, an array index overflow, a register clobber in an ISR
  prologue/epilogue, or a hardware bus glitch)
- Two heap accesses are racing and OR-ing together (CAN ISR + main
  thread both touching the same memory)
- Some address-arithmetic path adds 0x20000 spuriously

So either:
- `_buf` (the ringbuffer's internal array pointer) is corrupted
- `_head` (the ringbuffer's index) is corrupted to a huge value
- The ringbuffer instance itself is in a memory region the linker
  didn't allocate

Either way, **the CAN ringbuffer's instance variables have been
overwritten** by the time the ISR fires. The fault is a heap/state
corruption symptom, not a bug in the `/stop` handler itself.

**Plausible mechanism (NOT yet proven, requires further drilling):**
- SRAM globals at 68.9% leaves only ~10 KB for heap + stack
- Only **1 KB of stack** — deep call chains (WiFi → Stream → String
  ctor + ISR preempt onto same stack) are tight
- WiFi `readStringUntil` allocates dynamic Strings continuously
  during reads; heap growth + fragmentation over a long shoot
- Heap grows toward stack; if either overruns the other, or grows
  into the CAN ringbuffer's static allocation region, the
  ringbuffer's `_head` or `_buf` gets trampled
- Day-7's failed `CART_LOG_MAX = 128` bump (.stack_dummy overlapped
  .heap) is documented evidence that the SRAM ceiling is already
  uncomfortably close

**What we KNOW (evidence):**
- Crash is in CAN ISR enqueue, reading via WiFi when it fires
- Crash address is outside valid SRAM
- Two separate crashes hit nearly identical out-of-range addresses
- The /stop handler path is identical to fetch path; difference
  must be cumulative state, not handler logic
- 62-photo run vs 87-photo run vs 104-photo run (which DIDN'T crash)
  suggests probabilistic exposure to the corruption window — but
  this is observation, not proof of a memory-pressure mechanism

**What we DON'T know (requires further work):**
- Whether the heap is actually growing without bound
- Where the CAN ringbuffer lives in SRAM (map file would tell us)
- Whether disabling CAN push-subscribe before /stop would mask
  the bug (it would, but doesn't fix the underlying corruption)

**Fix candidates (none chosen yet):**
1. Stop CAN push-subscribe before /stop; gimbal stops sending; ISR
   stops firing during teardown. Doesn't fix the corruption, just
   avoids the trigger.
2. Disable CAN RX interrupts around blocking WiFi reads. Same.
3. Drive `client.readStringUntil` and friends with explicit char-at-
   a-time reads to avoid heap allocations. Investigate.
4. Migrate to Giga R1 (v2 / #47). 1 MB SRAM removes the memory
   pressure entirely.

Updated #48 in WORKFRONTS with this evidence.

**Update — fix attempt 1 (char-buffer reads) failed.** Replaced
`String statusLine = client.readStringUntil('\n')` and the header
read loop in `ccapiRequest()` with a 48-byte stack-local buffer + char-
at-a-time reads. Goal: remove our code's contribution to heap
allocation in the WiFi read path. **Crashed again. Same crash
signature.** addr2line on the new dump showed the String
constructor is STILL in the stack — but inside the WiFiS3 library's
`ModemClass::buf_read`, not our code. The WiFi driver allocates
Strings internally on every `client.read()`. Removing String use in
ccapiRequest didn't help because the library does the same allocation
one frame deeper. We can't avoid this without rewriting WiFiS3.

**Update — regression test against pre-cleanup version.**
Operator uploaded a much older v3 sketch (~Day-14 era, pre-part-3 —
still had `findTableRowForTv`, `lum_fetch_skip_remaining`, the old
String-based reads, all the things later sessions retired). Flashed
and tested /stop. **Did NOT crash on that run.** 31 photos delivered,
clean `[lum] live view stopped status=503` log. Initially suggested
today's changes destabilised /stop.

**Update — back-out + retest revealed it's NOT a code-state issue.**
Reverted today's part-7 work (stack instrumentation removed,
char-buffer change reverted) — restored end-of-part-6 sketch (4843
lines). Re-ran the /stop test. **Crashed again** with same signature.
So the v3 "clean" run was just lucky timing; the bug is **intermittent
across runs of identical code**.

**Revised understanding (end of part 7):**

- /stop crash is a **race condition** between CAN RX ISR and WiFi
  blocking-read path. Whether it manifests depends on millisecond-
  level timing of when /stop arrives relative to CAN message bursts.
- The String-in-WiFi-library finding from fix-attempt-1 means heap
  pressure isn't the only mechanism — even without our String use,
  the library still allocates inside the read path.
- The stack-overflow hypothesis from the painted-stack measurement
  (1024/1024 used at idle) is real and concerning, but doesn't
  fully explain the crash by itself either — v3 with even more
  String use should crash MORE often if stack overflow were the
  sole cause, but didn't crash on the one test we did.
- Honest position: **mechanism partially understood, root cause
  not isolated. Multiple possible contributors. Intermittent.**

**Restated fix candidate ranking after evidence:**
1. **Stop CAN push-subscribe before /stop** — best masking option.
   Closes the race window completely by silencing the ISR during
   teardown. Doesn't require understanding root cause.
2. **Disable CAN RX interrupts around the DELETE** — same idea, even
   narrower window.
3. **Avoid /stop entirely** — current workaround. Power-cycle to end
   shoots. Production-safe but operator-friction.
4. **Giga R1 (v2 / #47)** — different platform, removes the SRAM
   constraint and likely the race timing too. Long-term.
5. ~~Char-buffer reads in ccapiRequest~~ — **ruled out by experiment**.
   Doesn't fix the underlying race; library still allocates Strings.

WORKFRONTS #48 entry updated with revised understanding.

**Fix attempt 2 — `enablePush(false)` + delay before /stop teardown.**
Added 2 lines before `ccapiStopLiveview()`: disable CAN push subscribe
to silence the gimbal, then 50ms delay to let the bus quiet. Goal: close
the ISR-vs-WiFi-read race window by removing the ISR side.
**Result: still crashed**, but with a different stack signature. addr2line
showed the CAN ISR was NO LONGER in the crash stack — `can_rx_isr`,
`r_can_call_callback`, `CanMsgRingbuffer::enqueue` all gone. Crash was
still in `WiFiClient::read` / `Stream::readStringUntil` during the DELETE,
but without the CAN ISR overlay. Fault address `0x810076c3` — high bit
set, no longer the heap-pointer + bit-flip pattern seen earlier.
**Useful diagnostic finding:** at least two distinct corruption mechanisms
contribute to the /stop crash. Silencing CAN closes one. Something else
remains. Reverted (we can re-add if we have a reason).

**Final resolution: minimal /stop handler.** Operator observation:
"/stop never crashed in 14 days of operation, only today" combined with
"1 crash in 5 stops is 1 too many" reframed the problem. We had been
trying to fix the crashing code. The simpler path: **don't call it.**

Audited what /stop actually does. Five steps:
1. Set `shutter_mode = 0` (stop PIN8 firing) — local, can't fail
2. Set `shutter_paused = false` — local, can't fail
3. `enablePush(false)` — single CAN frame, non-blocking
4. `ccapiStopLiveview()` — HTTP DELETE to camera, **the crashing call**
5. Serial summary print — can't fail

Step 4 is housekeeping. Camera times out liveview sessions on its own;
`ccapiStartLiveview()` already handles "Already started" 503 for stale
sessions. So step 4 was never required for correctness.

Minimal /stop applied — only steps 1, 2, 5 retained. Tested through
two full cycles:
- Cycle 1: /start → 29 photos → /stop → clean exit, no crash
- Cycle 2: /start → camera POST /liveview returned 200 ("[lum] live
  view started" — fresh session, camera had timed out the old one
  during the ~20s gap) → 7 photos → /stop → clean exit

**#48 closed for v1.** Crashing code removed from hot path. The
underlying bug in WiFiS3 / Stream / String / CAN ISR interaction is
still there, but cart no longer touches it. v2 (Giga + Ethernet) will
revisit, since that platform may resolve the root cause incidentally.

Trade-off documented inline in the /stop handler: skipped DELETE
means the camera session lingers a few seconds longer; no operational
impact observed.

---

### Day-15 part 6: more dead-var cleanup + canFlip removal + memory snapshot

Two more sketch trims following the part-5 pattern:

**1. #36d cleanup completed.** Traced the original WORKFRONTS
"dead state vars" list var-by-var:
- `lum_fetch_skip_remaining` — dead (branch unreachable, nothing ever
  set it non-zero). Removed, plus its check block in the fetch-service
  loop and two stale comments.
- `lum_consecutive_conn_fails` + `LUM_FAIL_THRESHOLD` — NOT dead. They
  are the liveview-died detector; 3 connection-level fails invalidates
  `lum_liveview_started` for fresh re-POST. Also exposed in
  `/exposure/state`. KEEP.
- `lum_in_outage` — NOT dead. Log-spam suppression flag. KEEP.
- WORKFRONTS line "all sitting at 0 / dead-branch" was wrong about these;
  cleanup item rewritten with verified status of each candidate.

**2. canFlip preconditions removed.** `tryFlipToTableMode` previously
required `exp_anchor_set && exp_tv_ceiling_sec != 0 && current_tv != ""`.
These existed to feed the retired `findTableRowForTv()` call. Decision
basis: the execute UI (planned, separate workfront) prevents
uninitialised cart starts upstream, so the gates protected against a
case that can't happen at runtime. Also aligns with photos-sacred +
autonomous-cart framing: if CCAPI fails, reaching TABLE is the right
move regardless of init state. Removed. Sketch 4862 → 4843 lines after
both trims.

**Verification:** ran the standard sequence end-to-end. 62 photos
delivered cleanly through the LIVE phase before operator hit
`/shutter/stop` and the known #48 bus fault recurred (same crash
signature, photos #1–#62 all delivered). canFlip change unaffected
during the LIVE phase. FLIP path itself not exercised this run (no
WiFi outage), but the only code change touched the LIVE→TABLE entry
function and the rest of LIVE behaviour was unchanged.

**Memory snapshot (post all Day-15 trims):**
- Flash: 135,316 / 262,144 bytes = **51.6%** (Day-15 baseline 50%,
  ~+1.5% net for the session)
- SRAM globals: 22,588 / 32,768 bytes = **68.9%** (Day-15 baseline 68%,
  essentially unchanged)
- Local-variable headroom: 10,180 bytes

Flash has plenty of room. SRAM globals at 69% is the binding constraint
for new features. Day-7's failed `CART_LOG_MAX = 128` bump (.stack_dummy
overlapped .heap) is the historical evidence that the SRAM ceiling
is real, not theoretical. Future features that touch this budget:
#30 (cart log buffer size), #40 (BNO085 ring buffer), `/plan/load`
JSON parsing at scale. Giga R1 (1 MB SRAM) absorbs this via #47.

**Open observation — /shutter/stop bus fault reproduced.** Same crash
as part 5, same stack-region address. Hardware damage previously
attributed to the bus fault is itself unmeasured (see Day-15 part 5
notes — cause of transceiver death is "unknown" per the PREFERENCES
no-guessing rule). The fault itself however is reproducible, occurs
exclusively in the `/stop` handler, and is the basis for the #48
workaround (avoid the endpoint, power-cycle to end shoots).

---

### Day-15 part 5: dead-var cleanup + /shutter/stop bus fault

Two small dead identifiers removed from v1 sketch: `FETCH_FAIL_BACKOFF_CYCLES`
(constant, no reads) and `MODE_FLIP_THRESHOLD` (define, never referenced
— `PROBE_COUNT` is the live equivalent). Sketch −15 lines. Re-test ran
clean through full cycle: 87 photos delivered across LIVE → PROBING →
TABLE → Step D → LIVE. Same shape as part-3 verification.

**Open observation — bus fault on `/shutter/stop` after #87.** Photo
fetch succeeded normally (#87, fetch ok=Y, lum=0, in_deadzone), then
operator hit `/shutter/stop` → cart entered the stop handler →
firmware bus fault, address `0x20025961` (SRAM region), PC `0x0000f1ca`.
Stack dump in transcript. Crash is in the stop path, photos #1–#87
were all clean.

- Previous test (Day-15 part 3) reached `/stop` fine and reported
  `photos_taken=104`. Same code path, different outcome.
- The dead-var edit removed only a `static const = 0` and a `#define`
  that was never referenced. Neither could plausibly change runtime
  behaviour. Edit is not suspected.
- Most likely: stochastic memory-state issue (heap fragmentation,
  stack growth into something, WiFi-stack interaction). Not
  investigated this session — operator's call to move on; photos
  were delivered.

**Crash has real cost (discovered later this session).** Subsequent
bench work showed the CAN transceiver was fried by this crash. CAN
TX errors climbing in bursts of 6, bus impedance measurements
ruled out wiring (terminators sane, 65Ω in parallel as expected).
Swapping the SN65HVD230 transceiver fixed the gimbal comms. So the
`/shutter/stop` bus fault is not just a cosmetic end-of-shoot annoyance
— it can damage hardware downstream. Promotes this from "note it
and move on" to a real workfront. New entry in WORKFRONTS as
**#48 /shutter/stop bus fault**: reproduce, localise (add Serial
checkpoints inside the stop handler), fix.

If this recurs, the investigation order would be: reproduce → check
whether `/stop`-specific or any-shutdown → look at `0x20025961`
relative to known heap/static layout → add `Serial.print` checkpoints
inside the stop handler to localise.

---

### Day-15 part 4: Turning-circle measurements (#20 / #29)

Real-world measurement of cart turning diameter at six servo
offsets. SCX6 chassis on actual ground, walked through full circles
and tape-measured. Standalone calibration drive (no plan execution
yet).

| Servo offset (°) | Diameter (m) | Radius (m) |
|---|---|---|
| 5  | 18.0 | 9.00 |
| 10 | 10.0 | 5.00 |
| 15 |  7.5 | 3.75 |
| 20 |  5.6 | 2.80 |
| 25 |  4.8 | 2.40 |
| 30 |  4.2 | 2.10 |

**Bicycle-model fit attempted, declined.** Pure bicycle model
`R = L/tan(δ_wheel)` with linear servo→wheel linkage doesn't fit:
the "Ackermann constant" `R × δ_servo_rad` climbs from 0.785 at 5°
to 1.100 at 30° (40% increase). Possible causes: non-linear linkage
at extremes, rear-wheel scrub on tight turns, suspension geometry
shift under load. The model also has structural ambiguity from
radius-only measurements — wheelbase L and servo-ratio k can't be
separated without an independent measurement (e.g. static ruler or
front-wheel goniometer).

**Decision per principle #15 (Visualisation > Manipulation):** the
table above IS the calibration. Use it directly as a lookup for
operator turn advice (#29a) — "want a 5m diameter turn? set servo
to ~25°". No fitted physical model needed for that. BicycleModel.bas
still earns its keep for CartLog→(x,y) trace integration; cm-accuracy
isn't the goal there either, eyeball-correct is enough.

**Measurement tolerances:** SCX6 has long-travel suspension; chassis
pitches and rolls under turn loads, tyres scrub on tight turns,
outdoor measurements honestly ±0.5m. The 40% climb in the Ackermann
constant is partly real non-linearity and partly noise; we cannot
separate them from this data alone, and don't need to.

**Tightest achievable turn: ~4.2m diameter at max servo (30°).**
Useful for shoot-planning sanity (any waypoint pair requiring tighter
than 4m radius needs the operator to drive a multi-leg manoeuvre).

---

### Day-15 part 3: v1 TABLE-mode simplification

Follow-on from the Part 2 v1/v2 split. With Step 4 (per-cycle
PUTs from TABLE) permanently closed for v1, the table-row
lookup that produced `exp_delta_t_rel` at flip had no consumer
— and neither did the `last_table_tv` / `last_table_iso`
snapshots, which only existed to support change-detection for
the never-built per-cycle PUT. Retired the lot, plus the
function and endpoint that fed them.

**Code removed from v1 sketch:**
- State vars: `exp_delta_t_rel`, `last_table_tv[8]`, `last_table_iso`
- Function: `findTableRowForTv()` (~30 lines + comment block)
- Endpoint: `/debug/match` (~60 lines)
- Block inside `tryFlipToTableMode`: matchedTrel/matchedIdx
  locals, the call to `findTableRowForTv`, the Δt_rel
  assignment, the `last_table_*` snapshot writes, and the
  matched/no-match Serial logs
- Δt_rel discard line + reset in the Step D recovery branch
- 3 fields from `/exposure/state` JSON response
- Header + state-block comments rewritten to describe v1's
  actual capability (no table lookups, no Δt_rel) rather
  than the original Day-13 design

**Preserved (still earning their keep):**
- `exposure_mode` flag and EXP_MODE_LIVE / EXP_MODE_TABLE
- `tryFlipToTableMode()` (now simpler — just flips and logs)
- All three TABLE-mode CCAPI gates (fetch arm, fetch service,
  PROBING entry) — Day-15 rule still applies
- Step D scheduler, recovery branch, liveview invalidation
- `last_mode_change_ms` (for `/exposure/state` reporting)

**Held back (separate decision needed):** the `canFlip`
precondition in `tryFlipToTableMode` still requires
`exp_anchor_set && exp_tv_ceiling_sec != 0 && current_tv != ""`.
With table lookups gone, those preconditions are arguably
stale — removing them would let TABLE engage on a cold-start
cart that never completed `/exposure/init`. Behaviour change,
not pure cleanup. Flagged but not actioned.

**End-to-end verification (this session, 22 May):**

| Phase | Photos | Behaviour |
|---|---|---|
| LIVE start | #1–#9 | clean 2s cadence, fetches ok=Y |
| Discovery | #10 | 10s CCAPI connect-fail → PROBING |
| PROBING probes | #11–#17 | 3 ping fails, ~1s each |
| FLIP | between #17/#18 | clean log, no Δt_rel or match output |
| TABLE | #18–#77 | ~60 photos clean 2s cadence, zero CCAPI |
| Step D probe | between #77/#78 | ping ok, recovery → LIVE |
| LIVE post-recovery | #78–#104 | liveview restart, fetches ok=Y, in_deadzone |

**Photos delivered: 104/104.** FLIP log line confirmed clean
at the wire: `[#36d] FLIP LIVE -> TABLE (via probe) event=sunset
trel_now=-11703 current_tv=1/5000 current_iso=100` — no orphan
fields. `/exposure/state` JSON confirmed clean (no `delta_t_rel`,
`last_table_tv`, `last_table_iso`).

**Files modified this session:**
- `DJI_Ronin_UnoR4_v1prod.ino` — −143 lines (4986 → 4843)

**Mental model:** with Step 4 closed, TABLE mode is now
exactly what it operationally needed to be all along: a
"don't talk to the camera, just keep photos firing, ping
every 60s" state. The Day-13 design carried Δt_rel and table
lookups in anticipation of Step 4; closing Step 4 lets us
collapse the state to match the actual behaviour. Less code,
same delivery, same robustness.

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
- Plan endpoints `/plan/load`, `/plan/start`, `/plan/stop`,
  `/plan/status` (Day 9)
- ±450° cumulative yaw via Settings envelope (Day 12)
- Formula evaluator + Appendix A push (Day 12)
- Time anchor on cart for sunset+sunrise (Day 12)
- TABLE → LIVE recovery within a shoot via 60s ping probe
  (Day 15) — Step D complete; TABLE no longer one-way per shoot
- **Three-screen UI v2 foundation (Day 16):**
  - Cart Recon screen — full production build, operator-verified
    end-to-end. Status line, Last/Now waypoint rows, all button
    rows, Mark wpt + W event in CartLog, /status v[10]/v[11]/v[12].
  - Gimbal Recon screen — full UI build with client-side state.
    Live readout, 4 prior slots + Current row, type/keyframe/frame/
    offset/label authoring, pose-vs-intent type handling,
    /btn20 gated on pose types only. NOT production-ready until
    #49 (rich-row persistence) lands.

### What's tested

- Tv=0.5" + 2s + CCAPI + mode=darken + live view: 100% delivery
  (Day 12 end-to-end)
- LIVE → TABLE on CCAPI outage: 14/14 delivery (Day 14)
- LIVE → TABLE → LIVE full cycle with WiFi off/on: 64/64
  delivery (Day 15)
- /shutter/stop minimal handler: 2/2 clean cycles (Day 15 part 7)
- Cart Recon waypoint workflow: ENRG → drive → multiple +5 steers
  → Mark wpt #1/#2/#3 → Last rolls correctly → Clear logs zeroes
  (Day 16 operator-verified)
- Sketch utilisation: ~51.6% flash, ~68.9% globals on Uno R4 WiFi
  (Day 15 part 6; Day 16 adds +9 bytes globals, verify post-flash)
- URL payload size envelope: 1.5 KB (verified via /debug/urlsize)
- BNO085 first-light: tracks within ±3° of iPhone compass across
  all four quadrants (Day 12 bench, not yet on production sketch)

### What's NOT tested

- Multi-hour production-envelope soak across sunset+sunrise
  (Stage 4 milestone)
- ANY of the cart Plan/Execution architecture under real load
  (endpoints exist, not exercised against a real plan)
- ANY gimbal Plan execution (design only, see GIMBAL_VIZ.md §§4–8
  and UI_DESIGN_v2.md Execution screen)
- BNO085 integration in production sketch (#40 design resolved
  Day 13; build phase pending)
- Gimbal Recon rich-row persistence across page reloads (#49)
- Show astro / Snap var on Gimbal Recon (#50 — Excel astro push)
- Execution screen — placeholder only, build deferred until
  backend (segment dispatcher, ±100mm nudge, PAUSE/RESUME, BNO,
  Excel astro push) lands

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

## Git repository structure

Two separate repos on the operator's local machine, each pushed
to its own GitHub remote. Captured Day 15 part 10 for future
session reference — Claude should know which files live where
before suggesting commit commands.

**Repo 1 — sketch (firmware):**
- Local path: `C:\Users\mauri\OneDrive\Documents\Github\DJI-Ronin-RS4-Arduino`
- Remote: `https://github.com/mwindley/DJI-Ronin-RS4-Arduino.git`
- Branch: `session-c-uno-luminance` (long-lived working branch
  carrying Day-12 onward). Master not yet caught up.
- Contains: all Arduino sketches (`DJI_Ronin_UnoR4_v1prod.ino`,
  `DJI_Ronin_UnoR4_v3.ino`, plus bench-test sketches like
  `BNO085_BenchTest`, `DropTest`, `I2C_Scanner`).
- The production v1 sketch path inside the repo:
  `DJI_Ronin_UnoR4_v1prod\DJI_Ronin_UnoR4_v1prod.ino`

**Repo 2 — Excel + docs:**
- Local path: `C:\Users\mauri\OneDrive\Documents\Github\HyperLapse-Excel`
- Remote: `https://github.com/mwindley/HyperLapse-Excel.git`
- Branch: `master`
- Contains: `HyperLapse.xlsm`, VBA modules (`Modules/*.bas`),
  Python scripts (`Python/*.py`), all design/state docs
  (`PROJECT_STATE.md`, `WORKFRONTS.md`, `PREFERENCES.md`,
  `UI_DESIGN_v2.md`, `UI_DESIGN_SUMMARY.md`, `GIMBAL_VIZ.md`,
  `EXPOSURE_FALLBACK.md`, `SHOPPING.md`, `TURN_TEST_RESULTS.md`,
  etc.), CSV reference data, ARCHIVE folder.

**Workflow:** Claude generates outputs to `/mnt/user-data/outputs/`
in the chat session. Operator downloads each file, then cuts from
`Downloads` and pastes into the relevant local repo folder before
running git commands. Sketch files go to repo 1, all .md / docs go
to repo 2.

**Implication for commit suggestions:** a single session often
produces changes to both repos (a sketch change AND a doc update).
That means **two separate commits**, one per repo. Cannot combine
into one. Future sessions: always check which repo a file belongs
to before suggesting `git add` paths.

**Other workfronts in the operator's local sketch repo** (not
ours to commit unless we worked on them): bench-test sketches,
v3 sketch (the pre-branch-point reference), other accumulated
work. When committing, stage only the files actually touched this
session — leave the rest as the operator's WIP.

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
