# HyperLapse Cart — Project State

**Last updated:** 15 May 2026 (end of Session C day 9 — Plan endpoints working + first 90° turn calibration)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

Also upload `PREFERENCES.md`, `GIMBAL_VIZ.md`, and `WORKFRONTS.md` —
that contains the working agreement, the gimbal visualisation design,
and the open task list.

---

### Straight performance — sufficient for production, no further testing needed

Discussion outcome from day 9: straight calibration is well-characterised
for the production envelope. **No further straight testing planned.**

**Production envelope:** 5–30 m/hr, typically 2 stops + holds per shoot.

**Why this is covered:**
- Day-8 measured speed-independence across 10× range (10–100 m/hr).
  Production 5 m/hr is one factor of 2 below the lower test point —
  same regime, no reason to expect departure.
- Day-9 re-confirmed at 100 m/hr to 0.01%.
- Production 5–30 m/hr is in the **linear / short-ramp regime**.
  Operator reports: 100 m/hr → stop is 6+ seconds of slowing;
  10 m/hr → stop is near-linear and short; DEAD STOP = 0s.
  So ramp overhead negligible at production speeds.
- Tic holds well during stops — position stable, no drift.
- Day-9 Seg 1 anomaly explained: 28s for 600mm at 100 m/hr vs
  21.6s pure travel = ~6s ramp-down, matches operator's observation.

**Workfront #19 (acceleration overhead) demoted** from "needed before
production" to "optional — confirmed negligible at production speeds
by operator observation."

**Workfront #18 (5 m/hr straight test) demoted** from "elevated" to
"deferred — extrapolation from 10 m/hr is safe given speed-independence
across 10× range already measured."

Move on to circle / symmetry / linearity testing for bicycle model
(workfronts #20, #29).

---

## ⚠️ Top-of-file context — Session C day 9 outcomes

### What we did today

Built and ran the first end-to-end Plan execution test on the cart,
collecting calibration data for the bicycle model. Plan: straight 600mm
+ 5s hold + 60s servo ramp to +30° + 90° right turn at +30° steering.

### Key results — servo-to-wheel calibration

**First estimate: SERVO_TO_DEG ≈ 0.35 deg_wheel per deg_servo**

| Metric | Bicycle model (δ=30°) | Measured |
|--------|-----------------------|----------|
| Turn radius | 849 mm | 2614 mm (arc) / 2915 mm (position) |
| Arc length for 90° | 1333 mm | 4107 mm |
| End position | (849, 849) | (3170, 2660) ±100mm |

Servo +30° offset produces ~10.6° actual wheel angle, not 30°.
Single test; need full circle test and ±15° / ±30° symmetry checks
before locking in the constant.

### Straight calibration re-confirmed

Seg 1 (600mm @ steer 0°): rear_steps = 339,025. Expected
(600 × 565) = 339,000. **0.01% off** — day-8 m_per_step = 1.77 µm/step
holds at 100 m/hr.

### Plan endpoint implementation completed and tested

Plan endpoints working end-to-end:
- `/plan/load?n=N&s1=...&s2=...` — CSV query-string format
- `/plan/start` — begins execution from segment 0
- `/plan/stop` — operator abort
- `/plan/status` — current state CSV

Segment format: `TYPE,VAL,STEER,SPEED,END`
- TYPE: m=move, s=stop
- VAL: dist_mm (move) or duration_ms (stop)
- STEER: degrees offset from centre (98)
- SPEED: m/hr
- END: d=distance, t=duration, o=operator

Compile fix: PlanSegment struct moved to top of sketch (after RxEntry)
because Arduino preprocessor generates forward declarations before
struct definition in original location.

### New issue surfaced — front == rear step counts on arc

Every single log row shows `front_steps == rear_steps` (or off by 1).
Bicycle model predicts inner/outer wheel divergence proportional to
wheelbase track and arc curvature. Either:
- ticFront.getCurrentPosition() not reading correctly
- Overdrive equalising the two
- Differential geometry not producing expected divergence

Worth investigating in next test. Affects day-7 architecture
assumption that "rear is sufficient on straights" — needs verification
that front actually diverges on arcs at all.

### Critical fault — WiFi unresponsiveness under UI polling

**Discovered today:** Phone/browser UI tabs polling `/status` and
`/cameramsg` every ~1 second saturate the Uno R4 WiFi request queue.
After ~15 min the cart becomes unreachable; power cycle required.

**Workaround:** All UI tabs closed during plan execution. Test from
laptop terminal only (curl / PowerShell). UI for monitoring; raw URLs
for execution.

**Fix needed:** Rate-limit UI polling or switch to on-demand refresh.
See WORKFRONTS #27.

### Tic power state lesson

Operator hit emergency power switch on Tic supply during overrun, but
left Arduino USB-powered for serial. Result: Tics lost all state
(positions = 0, step_mode = 0, no I2C response). When power restored,
must re-energise (btn15) and Tic position counts restart from 0. No
position recovery possible — log every test from a fresh power-on.

### Operator workflow notes

PowerShell with `Invoke-WebRequest -UseBasicParsing` is the reliable
way to send `&` query strings. cmd.exe curl with quoted URL still got
truncated on `&` characters. Click-through bare URLs in chat work for
single-param endpoints, but multi-param need PowerShell.

### Debug additions today

- `[WiFi] path=[...]` log added to every request — invaluable for
  diagnosing path matching. Stays in v3_debug.ino.

### Files modified today

- `DJI_Ronin_UnoR4_v3.ino` → `DJI_Ronin_UnoR4_v3_debug.ino`:
  - PlanSegment struct + enums moved to top of sketch (before forward
    declarations) to fix compile error
  - WiFi path debug logging added at request handler entry

### Next steps for next session

1. **Investigate front vs rear step count** — should diverge on arc,
   currently identical. Either reading bug or genuine equality (which
   would change architecture assumptions).
2. **Full circle test** at +30° — gives a better servo-to-wheel
   calibration than a single quarter turn.
3. **Symmetry test** — repeat with -30° (left turn). Check if servo
   centre (98) is geometric centre or biased.
4. **Linearity check** at +15° — is SERVO_TO_DEG constant across
   wheel angles, or does it change?
5. **Fix UI polling** — rate-limit `/status` and `/cameramsg` to
   minimum needed for live display. Currently saturates WiFi.
6. **Update BicycleModel.bas** with SERVO_TO_DEG = 0.35 (provisional)
   and run integrator on today's log to verify the trace matches the
   measured end position.

### Design context discussion (rainy afternoon, no testing)

After the turn test, talked through the architectural implications.
Captured here so it's not lost.

**Cart is dumb by design — Excel does all maths.** Bicycle integration
(viewer), inverse fitting (predictor), astro pre-baking, Catmull-Rom
all live in Excel. Cart receives Plans in cart-native units (steps,
servo PWM). Cart never knows what a "wheel angle" or "turn radius" is.

**Bicycle model has two roles:**
- **Viewer:** log → trace render. Useful for operator to see the path.
  Speed/colour bands easy.
- **Predictor:** operator selects rows 3-7 of recon, asks Excel to
  smooth into one arc that ends at same point with same heading.
  Excel computes radius/steering/length and commits as a Plan row.
  This requires the calibration (SERVO_TO_DEG) to be accurate enough
  that the predicted arc actually lands where Excel claims.

**Production tolerance is asymmetric.**
- Distance: large tolerance. Sun is far; ±100mm on a 60m drive is
  invisible in the final video.
- Turn-at-spot and stop-before-hazard: hard limits. Wrong turn
  location may miss the path; stop overrun may meet a cliff.
- Gimbal pointing: precise (sun position is precise).

**Two paths to handling hard limits:**
- Path A — pre-calibrate everything (lookup tables, multi-session
  measurement, lots of maths).
- Path B — operator in the loop (DEAD STOP + nudges during execute).

**Decision: Path B + minimal Path A.** Operator built the rig to be
there during shoots (2pm–11pm, then 4am–sunrise). Watches with
attention; supervision is the activity, not a burden. Hard limits
handled by operator observation + intervention.

**Critical actions where operator must supervise:**
1. Approach to known hazard (cliff, ditch, fence)
2. Tight turn at a path constraint
3. First execution of a new Plan — whole-run validation
4. Surface transition (gravel to grass, slope change)
6. Camera issues mid-shoot (operator diagnoses)

Not critical: wind (no concern); battery (huge main battery);
sun-target divergence (operator can't tell from ground).

**Operator intervention model — distance only, not angles.**
- DEAD STOP — emergency (existing, works)
- Nudge ±100mm on current segment — shorten or extend
- No angle nudge. Operator can't judge "5° more left" by eye.
- No hold-duration nudge. Same family as angles — too hard to judge.
- Past-zero shorten = immediate segment complete (no overflow).
- Adjust counter clears at segment boundary.

**UI implications — two distinct screens.**
- **Cart Position Logging UI (recon mode):** manual drive, live state,
  no segments. Light, infrequent updates.
- **Cart Position Execution UI (shoot mode):** segment-aware,
  remaining distance (100mm resolution), nudge buttons, DEAD STOP.
  Push updates per 100mm change — event-driven, not polled. Solves
  WiFi polling fault by design.

**Gimbal alignment with cart Plan.**
- Cart segments are distance-anchored; gimbal Plan rows are
  time-anchored. Excel builds both Plans together so durations match
  at segment boundaries.
- **Gimbal time is sacred; cart position is flexible.** When operator
  nudges cart distance, gimbal continues on its pre-baked time
  schedule. Sun position is fixed in time, not in cart position.
- Gimbal does NOT get nudge buttons. Operator can't judge gimbal
  angles from observation, and gimbal motion only needs to align with
  cart heading or sun (both pre-baked).
- Small boundary mismatches (cart finishes Seg 3 a few seconds late,
  gimbal already moved to next mode) are invisible — sun moves
  ~0.25°/min at horizon; 5s delay = 0.02° sun shift, below gimbal's
  0.1° quantisation.

**Confirmed: cart-position nudging exists because of critical-action
faults, NOT to track gimbal. Gimbal Plan runs independently.**

### 't' event implementation + validation (day 9 late afternoon)

After the context discussion, added servo ramp-complete logging and
validated it across three tests.

**Code change:**
- Inside the 1°/sec servo ramp logic in `cartLoop()`, added
  `cartLogEvent('t', cart_steering)` when `cart_steering ==
  cart_steering_target`.
- Updated CartLogEntry comment to document 't' as "servo reached
  target (ramp complete)".
- Original 'T' event (target SET) preserved — fires from
  `cartAdjustSteering()` at button press.

**So:** every steering button click now produces 1 'T' (instantaneous,
at click) + 1 't' (delayed, when servo settles N seconds later, where
N = degrees of change × 1°/sec). Each event captures rear_steps and
front_steps. Excel can interpolate steering linearly during the ramp.

**Test 1 — Bench, no driving.** PASS.
- L1, CTR, L5 clicked in sequence
- 'T' + 't' pairs appeared as designed
- rear_steps and front_steps stayed at 0 (cart stationary)
- 1° ramps (L1, CTR) produce same-second 'T'+'t' (sub-1s ramp)
- 5° ramp (L5) produced 'T' at click, 't' 5 seconds later ✓

**Test 2 — Driving at 100 m/hr, single L5 click.** PASS.
- 'T' at 00:00:40, rear=205,306
- 't' at 00:00:45, rear=288,913
- Ramp window: 5 sec, ~148mm of arc travel during steering change
- Front step count tracks rear within ~1% (small offset)
- Tic position tracking works correctly during driving

**Test 3 — Recon-style mixed inputs over 2.5 min.** PASS-with-finding.
- 31 events recorded for ~2.5 min driving with 10 steering changes
- Buffer 64 entries half-used; clean log
- **Finding: extrapolation = 60 min recon → ~750 events.
  CART_LOG_MAX=64 is too small for production recon.**
- Not a Uno-break — current setup ran clean. But for the production
  flow ("operator drives at 100 m/hr to collect log for Excel")
  the buffer is undersized by 10×.

**Buffer options surveyed (not chosen — design decision deferred):**
1. Bump CART_LOG_MAX to 96 or 128 (128 caused stack/heap overlap day-8)
2. Drop front_steps (saves 4 bytes/entry, gives ~80 entries — but
   loses front-vs-rear diagnostic)
3. Stream log to Excel during run (new endpoint, polling load)
4. Compact log format (drop ms field, etc — marginal gain)
5. Move to Giga R1 (workfront #22 — problem disappears with 1MB SRAM)

**Recommendation:** parked for buffer + UI polling redesign together.
Both speak to the same architectural question: cart RAM and WiFi are
both Uno R4 limits. Giga R1 migration is the upstream answer; until
then, restrain usage by design (short recon runs, careful polling).

### Cart position model — break point for the day

Discussed and confirmed the full flow:

**1. Cart collects.** Operator drives manually, every command + servo
   ramp logged with rear_steps + front_steps. Validated today.
**2. Excel views.** `BicycleModel.bas` integrator → (x, y, θ) trace.
   Curves smoothed by 't' interpolation (pending Excel update).
**3. Excel predicts (when asked).** Operator selects rows, asks for
   single-arc smoothing. Requires accurate SERVO_TO_DEG (work TBD).
**4. Excel sends small and dumb back to cart.** Plan in cart-native
   units (steps, servo PWM). Cart executes, no maths.

Architecture sound, confirmed by today's testing. Remaining work is
calibration depth (more turn tests, different angles) and operator-UX
(nudge buttons, buffer redesign, polling fault).

**Next workstream after this break: investigate UI polling fault
(workfront #27).**

### UI polling fault investigation (day 9 evening) — RESOLVED via avoidance

Followed the measure-drill-simplify-avoid discipline.

**Measure (request-level timing instrumentation):**
Added `/debug/reqlog?on=0|1` toggle to v3.ino. When enabled, every
request prints `[REQ] path=X t01=Nms t12=Nms send=Nms close=Nms
total=Nms` to serial, breaking the request into sub-phases:
- t01 = client accept → request line parsed
- t12 = parse → response built (the actual handler work)
- send = response written to client
- close = client.stop()

**Findings — first measurement pass:**
| Phase | Time | Notes |
|-------|------|-------|
| t01 | ~60ms | WiFiS3 stack accepting + reading request line |
| t12 | 3-6ms | Endpoint handler (status/cameramsg) |
| send | 50ms | WiFiS3 stack writing response |
| close | 6ms | client.stop() |
| **/status total** | **~110ms** | per request |
| **/favicon.ico** | **~1300ms** | falling through to UI HTML catch-all |

LOOP-LONG fires at ~140ms per request — confirms WiFi handling
blocks the main loop for that long.

**Drill — root causes identified:**
1. `t01=60ms` per request: WiFiS3 stack overhead, not our code. Fixed
   cost of accepting + reading a single HTTP request line. Can't
   easily fix without library work or migrating to Giga R1.
2. `/favicon.ico` falls through to catch-all → serves entire UI HTML
   page (1.3s) just so the browser can display a tab icon. Wasteful.
3. At 1 Hz UI polling + 110ms per request: 11% CPU sustained on WiFi,
   plus socket churn (new TCP connection per request). Over 15
   minutes that's likely TCP socket pool exhaustion or memory
   fragmentation — but neither was directly observed.

**Simplify + Avoid — three changes:**

1. **Favicon handler** — added early-exit in v3.ino:
   ```cpp
   if (path == "/favicon.ico") {
       client.println("HTTP/1.1 204 No Content");
       client.println("Connection: close");
       client.println();
       client.stop();
       return;
   }
   ```
   Result: 1301ms → 89ms (~14× faster).

2. **UI polling rate 1s → 3s** — `setInterval(upd, 1000)` →
   `setInterval(upd, 3000)`. Cameramsg 5s → 10s. Status update is
   slightly less live but still fine for visual feedback at 5-30
   m/hr operating speeds.

3. **Pause polling on button press** — new `pollPaused` JS variable.
   Every button function (home, shutter, btn, btn19, btn20)
   sets `pollPaused = Date.now() + 5000`. The `upd()` and `updCam()`
   functions check `if (Date.now() < pollPaused) return`. So clicking
   a button stops polling for 5 seconds, preventing collision between
   operator commands and background polling.

**Result — sustained run:**
5 minutes of continuous UI polling at 3s rate. Numbers stayed flat:
- /status: total=109-112ms (no drift)
- /cameramsg: total=105-108ms (no drift)
- LOOP-LONG: 118-125ms (no drift)

**CPU load now:** ~5% (down from ~15%). Cart remains responsive to
button clicks throughout.

**Conclusion — avoidance was the right move.** The deeper fix
(WiFiS3 stack optimisation, async TCP handling, or Giga R1 migration)
is still available as workfront #22 if a future workload re-exposes
the saturation. For current operator workflow (recon @ 100 m/hr in
2-3 min bursts, execute @ 5-30 m/hr with occasional button presses)
the avoidance is sufficient.

**Cost of avoidance:** UI shows slightly slower updates (3s status
refresh instead of 1s). Acceptable — operator at the van isn't
watching for sub-second changes, just confirming cart state.

**Workfront #27 RESOLVED via avoidance.** Not closed — if production
shoots reveal saturation under longer / heavier patterns, return to
the deeper fix.

### Gimbal panorama feature — design context (day 9 evening)

Discussion: panorama as a Gimbal Plan capability. Pure design, no code.

**Trigger:** Planned (Plan row) or operator-nudged/interrupted at any
time during a HOLD or astro-track segment.

**Constraint: pano only when cart stopped.** This simplifies catch-up
maths considerably (no cart-heading drift to chase).

**Geometry decided (master parameters in Excel):**

- Range: **±120° relative to current yaw** at trigger time
- 14mm lens FOV = ~104° horizontal on full-frame
- Overlap: **50%** (internet consensus for 14mm — wide lens has heavy
  edge distortion; 30% is floor, 50% recommended; standard sources)
- Step between photo centres = 52° (50% of 104° FOV)

**N = 4 photos** for edge-to-edge ±120° coverage at 50% overlap.

Frame centres: **−78°, −26°, +26°, +78°** (symmetric around current).

Total gimbal yaw rotation during pano: −78° → +78° = 156°.

Edge coverage: leftmost photo edge at −130°, rightmost at +130°
(10° margin past requested ±120° — clean and symmetric).

**Pitch:** held at current pitch (same as gimbal's current pose).

**Camera settings:** same Tv / ISO / interval as current shoot. No
exposure changes for pano.

**Motion phases per photo cycle:**

1. Slew to next centre (~52° step at controlled ~100°/s → 0.5-0.8s)
2. Settle (assume **1 second** — pending real measurement)
3. Exposure (Tv from production table)

Plus initial slew from current to −78°, plus final slew back to
underlying track target.

**Pano duration vs Tv (using authoritative production table):**

| Tv | Per-photo cycle | Pano duration (4 photos + slews) |
|----|----------------|----------------------------------|
| 2s | 3.8s | ~17s |
| 8s | 9.8s | ~41s |
| 20s | 21.8s | **~90s (worst case)** |

**Catch-up analysis:**

Astro drift (sun at horizon / sidereal): 0.25°/min.

Worst-case drift during 90s pano = **0.37°**. Negligible.

**Conclusion: no special catch-up phase needed.** The pano is so much
shorter than any meaningful track motion that resume is just "slew
back to current target, settle, resume tracking" — handled by the
existing gimbal where-am-I-vs-target logic. No new state machine.

**Recovery by interrupted state:**

1. **HOLD** — gimbal slews from +78° back to held pose. Standard slew.
2. **TRACK SUN / MILKY WAY** — gimbal slews from +78° to *current*
   astro target (not original target — sun moved ~0.37° max during
   pano, absorbed in the slew). Standard re-targeting.
3. **PAN-FOLLOW** — N/A. Pano only when cart stopped, so no pan-follow
   active.

**Architecture stays clean:**

- Cart still dumb (cart doesn't know anything about pano; gimbal-only)
- Excel-side complexity: Plan row type for pano, master parameters
  (N, overlap%, range), pano sub-step yaw generation
- Gimbal execution: pano is a sequence of (slew, settle, photo)
  sub-segments interleaved with normal Plan execution
- No new "catch-up easing" math — re-uses existing slew-to-target

**Master parameters in Excel:**
- `PANO_OVERLAP_PERCENT = 50` (for 14mm)
- `PANO_RANGE_DEG = 120` (±120° from current)
- `PANO_N_PHOTOS = 4` (derived from FOV + overlap + range, recorded
  explicitly for clarity)
- `GIMBAL_SETTLE_MS = 1000` (assumed, pending measurement)

**Open question:** how does operator trigger an unplanned pano during
execute? Probably a button on the Execution UI ("PANO NOW") that
sends `/plan/pano` or similar to the cart, which inserts a pano
sub-segment at the current Plan position. Defer until UI design pass.

### Pano bench test — decision and plan (day 9 evening continued)

**Question raised:** can we test pano firmware on a rainy bench day,
and will it help with the broader gimbal Plan workfront, or be wasted?

**Decision: Option A — pano interrupt only, against a simple
stub of HOLD/TRANSITION segments. Not Option B (full Catmull-Rom
dispatcher first).**

**Reasoning:**
- The pano interrupt logic is **independent** of the underlying
  motion's smoothing. Pano queries "what's the target right now"
  from whatever's running underneath.
- Whether the underneath is linear interpolation or Catmull-Rom,
  the pano handler talks to the same interface.
- So a simple linear-interpolation stub now is sufficient. Pano
  built against it will work unchanged when Catmull-Rom dispatcher
  (workfront #5a / GIMBAL_VIZ §) arrives later.
- Cost: ~1 day Option A vs 3-5 days Option B.
- No effort wasted: pano implementation lives at a higher layer
  than the motion smoothing.

**What Option A bench test teaches:**
- Real gimbal settle time (#34)
- Gimbal yaw/pitch pose precision (does −78° actually land at −78°?)
- 4-photo stitching at 50% overlap on 14mm
- Pano sub-segment generation in Excel
- Cart-side pano handler
- Resume-after-detour model validated against stubbed transition

**What it does NOT teach (deferred to later workfront):**
- Catmull-Rom evaluator on cart
- Excel spline → cubic coefficient packing
- Multi-segment dispatcher
- Real smooth-motion behaviour for the audience-frame aesthetic

**Bench test plan structure (cart on bench, stationary, R3 on gimbal):**

Test Plan:
- **Seq 1:** HOLD at (yaw=0°, pitch=0°), 2 min
- **Seq 2:** TRANSITION to (yaw=−90°, pitch=10°), 10 min linear
  interpolation
- **Seq 3:** TRANSITION back to (yaw=0°, pitch=0°), 10 min
- **Seq 4:** STOP

Fixed camera: **Tv=5s** (mid-table value, 8s photo cycle including
settle + slew).

**At any time during execution, operator triggers pano:**
- During Seq 1 (HOLD) — verifies static recovery
- During Seq 2 (mid-transition) — verifies time-anchored recovery
  against linear stub
- During Seq 3 (return transition) — same

Multiple panos per run possible.

**What pano does:**
- 4 photos at yaw centres relative to current pose at trigger
  (−78°, −26°, +26°, +78°)
- Pitch held at current pitch
- Each photo: slew → 1s settle (assumed) → Tv exposure (5s) → next
- After 4th photo, query underlying segment "what should pose be NOW
  by clock time" → slew to that → resume normally

**Trigger mechanism:** raw URL `/gimbal/pano` (or similar) — operator
sends from laptop terminal during the run.

**Instrumentation needed:**
- Gimbal Log records waypoints at each photo (existing capture mechanism)
- Add timestamp + commanded yaw + commanded pitch at each photo position
- Optional: serial print at slew-start, slew-end, settle-end, photo-fire

**Open question for implementation phase:** does the Plan execution
this needs already exist (Gimbal Log endpoint, CAN setPosControl, etc.)
or are we building from scratch? Need to check code first.

### Pano firmware build + keep-alive finding (day 9 evening continued)

Built `/gimbal/pano` endpoint and state machine. End-to-end works.

**Pano state machine:** SLEW → SETTLE → PHOTO → repeat 4× → RESUME → IDLE.
Each phase has timed transitions in main loop. Tunable parameters:
- `?tv=N` — Tv exposure in ms (wait between shutter and next slew)
- `?speed=N` — slew speed in deg/sec (for edge-finding)
Photo positions logged via existing `gimbalLogCapture()`.

**Critical finding — keep-alive interferes with long motions:**

Existing code has a 30-second keep-alive that fires
`setPosControl(g_yaw, g_roll, g_pitch)` to prevent motor sleep. This
tells the gimbal "stay where you currently are." Hit it during pano
testing: the resume slew (~4s back to centre) was interrupted by
keep-alive firing at T+30s, freezing the gimbal mid-slew at whatever
yaw it happened to be at (+20-40°).

**Fix applied for pano:** added `PANO_RESUME` state; keep-alive
suppressed while `pano_phase != PANO_IDLE`.

**Broader implication — affects EVERY workfront with gimbal motion
longer than 30 seconds:**

- **TRANSITION segments** (e.g. 0° → -90° over 10 min): would freeze
  mid-way after 30s.
- **TRACK_SUN / TRACK_MILKY tracking:** slow drift over minutes/hours
  hits the same problem.
- **PAN_FOLLOW during long cart movements:** same.
- **Catmull-Rom evaluator running splines:** if no command for 30s,
  frozen at last position.

**Pattern of fix for all of them:** any "gimbal is in motion" code
must either (a) suppress keep-alive during its execution, or (b)
re-issue position commands at a rate ≥ 1 per 30 seconds (naturally
true for high-rate dispatchers like Catmull-Rom).

**Cleanest design:** a global `gimbal_busy` flag (or richer state)
that gates keep-alive. Each motion subsystem sets/clears it. Pano
already does this implicitly via `pano_phase`. Catmull-Rom dispatcher
and TRANSITION/TRACK execution will need equivalent gating when
implemented.

This is a **structural property of any future gimbal Plan execution
code**, not pano-specific. Captured as workfront #36.

### Pano firmware — final config + edge-finding (day 9 evening continued)

**Production config decided:** `speed=70°/s, tv=auto (Tv-driven by camera)`.
Total pano time ≈ 15 seconds at tv=1ms (4 photos plus initial + resume slews).
At Tv=20s production max: ~22s × 4 photos plus slews ≈ 95 seconds.

**Edge-finding tested on bench (cart suspension partly loaded):**
- 20°/s: very stable, baseline
- 30°/s: stable
- 70°/s: stable, chosen for production
- 100°/s: past the edge

**Caveat:** bench mount didn't have suspension in full play. Real-world
edge needs cart on its own wheels on shoot-similar surface. Production
70°/s is conservative.

**Asymmetric overshoot noted:** Photo 4 (yaw +78°) tends to overshoot
slightly more than Photo 1 (yaw −78°). Logged positions still within
0.5° of target. Possibly direction-dependent gimbal motor behaviour
or camera/lens CG offset. Not problematic at current tolerance.

**Critical findings — must carry forward to all gimbal execution work:**

1. **DJI `time_for_action` byte is 0.1-second units in a single byte**
   (per DJI R SDK Protocol v2.3, §2.3.4.1). Max value 0xFF = 25.5s.
   ConstantRobotics SDK header comment says "time_ms" — **misleading**.
   Always reference the actual DJI protocol PDF (saved in chat history;
   need to capture URL).

2. **Gimbal has ~700ms startup latency** before motion begins after
   `setPosControl`. Move characterisation testing must account for this.

3. **Back-to-back setPosControl commands can be silently ignored.**
   Inter-command gap of ~200ms required between consecutive commands.
   `PANO_INTER_CMD_MS = 200` in code. Without it, photo 2 sometimes
   stayed at photo 1's yaw position.

4. **Keep-alive (30s `setPosControl(g_yaw, g_roll, g_pitch)`) freezes
   the gimbal mid-motion.** Suppressed during pano via state check.
   This pattern affects ALL gimbal motion subsystems with motion >30s
   (TRANSITION, TRACK_*, PAN_FOLLOW, Catmull-Rom dispatcher). See
   workfront #36.

5. **Slew completion must be polled by g_yaw arrival, not by timer.**
   Commanded duration is motion-time-only, doesn't include the
   ~700ms latency. If we advance state on timer, gimbal is still
   mid-slew when next command arrives. Polling g_yaw to within
   tolerance (PANO_ARRIVAL_TOL_DEG = 0.8°) plus a timeout floor
   (commanded dur + 2s) is robust.

6. **Post-shutter visual confirmation matters to operator.** Even
   for fast Tv (1/5000s = 0.2ms exposure), the camera red LED is
   visible for hundreds of ms. Moving the gimbal too soon makes the
   operator think the photo didn't take. Floored post-shutter wait
   at PANO_POST_SHUTTER_MIN_MS = 500ms. Slow Tv (e.g. 20s) waits
   full Tv naturally.

**Final pano constants in v3.ino:**
- PANO_N_PHOTOS = 4
- PANO_SETTLE_MS = 800 (post-slew mechanical settle)
- PANO_POST_SHUTTER_MIN_MS = 500 (visual confirmation floor)
- PANO_INTER_CMD_MS = 200 (DJI command gap)
- PANO_ARRIVAL_TOL_DEG = 0.8 (slew arrival tolerance)
- PANO_SLEW_TIMEOUT_MS = 2000 (slew timeout past commanded dur)
- pano_offsets[4] = {−78, −26, +26, +78} (50% overlap, ±120° on 14mm)
- Default tv_ms = 800, default speed_dps = 20

---

## ⚠️ Top-of-file context — Session C day 8 outcomes

### What we did today

Two distinct streams of work:

**Morning: pure design.** Built the full design for the gimbal Plan
(authoring workflow, visualisation chart, velocity warnings, execution
stream, cart-side simplification). See `GIMBAL_VIZ.md` for the
complete design document.

**Afternoon: first cart calibration measurements.** Started workfront
#4 (rear_steps logging) and #17 (straight-line test). Discovered
firmware/drivetrain reality differed from assumptions; iterated through
several runs of investigation; landed on a clean speed-independent
calibration constant.

### Cart calibration findings (day 8)

**m_per_step = ~1.77 µm/step** (rear-axle motor microstep → cart ground travel)

Three clean runs at locked overdrive 1.00:

| Speed | µm/step |
|-------|---------|
| 10 m/hr | 1.780 |
| 50 m/hr | 1.744 |
| 100 m/hr (OD=0.97) | 1.779 |

Spread ~2% across 10× speed range — **m_per_step is speed-independent**.

### Drivetrain reality

| Component | Spec | Notes |
|-----------|------|-------|
| Stepper | NEMA17 17HS13-0404S-PG27 | 200 full steps/rev (1.8°) |
| Planetary | 26.85:1 (datasheet: 26 + 103/121) | Integrated with motor |
| Tic 36v4 | step_mode = 4 (= **1/16 microstepping**) | Not 256 as initially assumed. Confirmed by `getStepMode()` via new `/debug/tic` endpoint. |
| Diff (SCX6 AR90 axle) | 3.3:1 ring & pinion | Manufacturer spec |
| Tyre | Falken Wildpeak M/T, 7" (177.8mm) | Loaded radius slightly less than nominal |

**Theoretical:** 200 × 16 × 26.85 × 3.3 = 283,360 microsteps per wheel rev → 1.97 µm/step
**Measured:** 1.77 µm/step (~10% less)

10% gap attributed to combination of tyre deflection under load, real
diff ratio slightly different from spec, possible constant slip — NOT
distinguishable from a straight-line test. **Defer to circle test (#20)
to separate these effects.**

### Front vs rear Tic behaviour

With overdrive locked at 1.00, front and rear step counts track within
~0.01% on straight runs. Confirms PROJECT_STATE day-7 assumption that
rear is sufficient for the bicycle model **on straights**. Open question
for circle test: does front/rear divergence match geometrically-expected
arc-length difference, or does slip / tyre stretch cause anomalies?

### Tic findings of note

- `step_mode` enum value: 0=full, 1=1/2, 2=1/4, 3=1/8, **4=1/16**, 5=1/32, 6=1/64, 7=1/128, 8=1/256
- Velocity units: microsteps per 10,000 seconds
- Rear `max_speed` setting = 200,000,000 (20,000 µsteps/sec) — clamped 2.5× lower than front (500,000,000). Not a current operational limit but worth knowing.
- `position_uncertain` flag stays false during normal velocity-mode operation. Set after `haltAndHold`, `deenergize`, or limit-switch trip.
- Tic counts step pulses **commanded** — physical slip would not be detected by the Tic.

### Debug endpoints added today

| Endpoint | Purpose |
|----------|---------|
| `/cartlog` (5-col) | Now includes rear_steps + front_steps per event |
| `/debug/tic` | Live snapshot of both Tic controllers (step mode, max speed, position, velocity, uncertain flag) |
| `/debug/overdrive?val=N` | Lock overdrive to fixed value (N=auto to revert). Used to isolate speed-dependent overdrive from calibration measurements. |
| `/debug/looplong?on=0\|1` | Silence/enable LOOP-LONG serial prints |
| `/debug/can?on=0\|1` | Disable CAN TX (sendFrame becomes no-op). Used during calibration when gimbal not connected. |
| `/status` (12 fields) | Now returns mailboxBusyCount (v[10]) and can_tx_enabled (v[11]) for UI |

### Cart UI additions today

- New status bar between Gimbal and Excel rows showing CAN state:
  - Green "CAN: OK" steady state
  - Amber "CAN: busy (N)" when mailboxBusyCount > 20
  - Amber "CAN: DISABLED" when can_tx_enabled is false
- `mailboxBusyCount` (was `txErrCount`) — counter renamed throughout
  (variable, serial log "[CAN] mailbox busy: N", JSON, UI). Original
  name caused misdiagnosis as a fault. Day-8.

### Excel modules added/updated today

- **BicycleModel.bas (NEW)** — bicycle/Ackermann integration of Cart
  Log into (x, y, θ) trace. Public subs:
  - `IntegrateBicycle` — walks CartLog events, integrates per-segment
    straight + arc maths, subdivides arcs into ~0.1m sub-steps for
    smooth chart rendering, writes Trace sheet, renders XY chart on
    CartLog.
  - `SimulateCartLog` — writes synthetic 5-row test log (5m straight
    + R=2m quarter-circle arc) so the integrator can be tested
    without driving the cart.
  - `btnIntegrateBicycle` — Control-sheet button callback.
  Calibration constants exposed as `M_PER_STEP = 1.78e-6`,
  `WHEELBASE_M = 0.49`, `SERVO_TO_DEG = 1.0` (placeholder pending
  circle test). Verified end-to-end via simulator: end position
  (7, 2) heading +90° matches expected to 0.01%.
- **Cart.bas (UPDATED)** — `GetCartLog` now writes 6 columns
  (timestamp, type, value, description, rear_steps, front_steps)
  to match the new 5-column cart firmware CSV.
- **Buttons.bas (UPDATED)** — `BuildControlSheet` adds "Integrate
  Bicycle" button. **Note: operator must manually add the handler
  row** to the Control sheet's `Worksheet_BeforeDoubleClick` code
  (which lives in the sheet's code module, not a .bas file, so the
  ImportModules workflow doesn't cover it).

### CAN bus issue (parked)

During cart calibration, gimbal CAN TX errors climbing rapidly with
LOOP-LONG firing at ~120ms intervals (CAN.write blocking). User reports
gimbal powered and wires OK. Deferred — disabled via /debug/can?on=0
to keep cart calibration unaffected. Investigate separately.

### Memory situation (Uno R4 watch-list)

CART_LOG_MAX bumped to 128 then reverted to 64 due to RAM
overflow (.stack_dummy overlaps .heap). Day-7 plan to bump buffer
size needs reconsidering when we add Plan endpoints. Not at imminent
risk but new globals consume the budget; prefer locals, prefer
`F("string")` for serial prints. Giga R1 (1 MB SRAM) remains the
contingency.

### Files modified today

- `DJI_Ronin_UnoR4_v2.ino` — sketch (in /mnt/user-data/outputs/):
  - CartLogEntry: +rear_steps, +front_steps (int32_t each)
  - cartLogEvent: reads both Tic positions at event time
  - cartLogGetCSV: 5-column output
  - cartUpdateOverdrive: honours runtime override
  - sendFrame: honours can_tx_enabled flag
  - End-of-loop LOOP-LONG print: honours loop_long_enabled flag
  - `txErrCount` renamed to `mailboxBusyCount` throughout (variable,
    serial log, /status field, UI). Threshold for "amber busy"
    indicator set to 20 sustained counts.
  - /status response extended from 10 to 12 fields
  - Cart UI: new status bar between Gimbal and Excel rows for CAN
  - New endpoints: /debug/overdrive, /debug/tic, /debug/looplong, /debug/can
- `BicycleModel.bas` (NEW) — bicycle integration module, see above.
- `Cart.bas` (UPDATED) — 6-column CartLog parsing.
- `Buttons.bas` (UPDATED) — new Integrate Bicycle button definition.
- `PREFERENCES.md` — URL formatting rule changed (bare URLs on own lines, clickable, no code box). Code boxes still used for shell commands.

### Next steps for next session

1. **Circle test (#20) — priority.** First real-world test that
   distinguishes slip from tyre deflection AND derives the
   SERVO_TO_DEG calibration constant. Needs bigger area than
   today's space; user moving cart tomorrow. Bring front_steps
   into the analysis. Once we have the constant, plug it into
   BicycleModel.bas and rerun integrator on real Cart Logs.
2. Investigate the CAN TX issue if symptoms return (parked at
   end-of-day-8; transceiver cools fine, /home command works,
   mailbox-busy counter is congestion not failure).
3. Continue toward Plan endpoints + segment dispatcher (#5, #5a)
   per GIMBAL_VIZ.md cart-side execution model.
4. Add `btnIntegrateBicycle` row to Control sheet's
   `Worksheet_BeforeDoubleClick` handler — done in-session by
   operator but not via ImportModules (handler lives in sheet
   code module, not .bas).

---

## Full details

See **`GIMBAL_VIZ.md`** for the complete design document covering:
- End-to-end workflow (recon → Plan → visualise → commit → execute)
- Plan vs Execution separation
- Gimbal UI on cart (new page, parallel to existing cart UI)
- Cart-side execution model (segment dispatcher + cubic evaluator)
- SDK constraints and accumulator pattern
- Real-world tracking maths (Adelaide, GC, sun, year-round)
- Velocity band colour coding (blue/green/amber/red)
- Catmull-Rom smoothing and transition handling
- Video-speedup (1320×) implications for ease durations

### Workfronts changes

Day-7 firmware items that **vanish** thanks to Excel-side pre-baking:
- ~~#6 Heading anchor endpoint at runtime~~
- ~~#7 Cart-θ integration during drives~~
- ~~#8 Port astro maths to C (~100-150 lines)~~
- ~~#10 setSpeedControl wiring~~
- ~~Catmull-Rom evaluator on cart~~

Day-7 firmware items that **remain**:
- #4 rear_steps in CartLogEntry
- #5 Plan endpoints (/plan/load, /plan/start, /plan/stop, /plan/status)
- #9 ±450° cumulative yaw constants

Day-8 firmware items **added**:
- Gimbal UI page (separate URL, parallel to existing cart UI)
- Segment dispatcher + cubic evaluator (~50 lines C)

Day-8 Excel items **added**:
- Astro endpoint computation for "track" rows
- Spline waypoint sequence assembly (manual + astro + holds)
- Catmull-Rom smoothing
- Cubic-coefficient packing for cart stream
- Velocity-band colour coding on chart
- Cinematic + execution-feasibility warnings
- Audience-frame display for ease durations

### Files modified today

None. Design session only.

### Cross-reference workflow

Unchanged. See day 7 entry below for the test-correlation pipeline.

---

## ⚠️ Hardware status (carried forward from day 6)

- **Opto and analyser:** on order, not yet arrived
- **Hardware reliability fix:** parked until parts arrive
- **Production edge case:** Tv=0.8"+2s currently at 76% delivery with
  CCAPI active; awaits opto swap + true 30s fetch interval test

---

## ⚠️ Day-7 outcomes (Cart Log/Plan/Execution architecture)

Pure design session. No code. Architected Cart and Gimbal Log → Plan →
Execution flow. See WORKFRONTS.md for the queued tasks.

Day-7 details preserved below for reference:

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
- Forward integration: Log → (x, y, θ) trace
- Inverse fitting: trace → smooth Plan via single-arc geometry
- Cart receives Plan in cart-native units (steps, servo PWM); cart firmware
  stays dumb, calibration constants live in Excel

**Cart Execution:**
- Excel POSTs Plan to `/plan/load` at shoot start
- `/plan/start` begins the walker
- Per row: set steering, set speed, watch rear step count, advance when
  target reached (or duration elapsed for stops)
- No bicycle integration on cart — just step counting + servo control

### Gimbal Log / Plan / Execution — UPDATED on day 8

See GIMBAL_VIZ.md for the current design. Day-7 architecture is
superseded where it conflicts; key changes:

- Astro pre-baked in Excel, not computed on cart
- Catmull-Rom evaluated in Excel, cart sees cubic coefficients only
- Heading anchored once at authoring, not integrated through drives
- Gimbal UI is field-side Plan-row editor, not just waypoint capture
- Speed control unused — pre-quantised position commands handle all cases

---

## State of the system

### What works

- Stage 3 Tv-driven cadence (committed day 5)
- Body-read 30× speedup (committed day 5)
- Fetch backoff (committed day 5)
- REQ-PHASES instrumentation (committed day 5)
- PIN8 + PULSE instrumentation (day 6, uncommitted)
- Cart-vs-camera cross-reference (day 6, uncommitted)
- Intervalometer fallback (always worked, never modified)
- Existing cart UI (btn1–21, /cartlog, /gimballog)

### What's tested at production edge

- Photo cadence at Tv=0.8" + 2s: 94% no-CCAPI, 76% with-CCAPI-at-6s
- Pin-8 electrical output: pristine on every fire
- Camera + cable + intervalometer: 100% reliable

### What's NOT tested

- Fetch interval at true production 30s cadence
- Tv=0.8" + 2s with new opto + 30s fetch
- Anything beyond 5-20 minute soaks
- Sunrise transition (only sunset table reviewed)
- ANY of the Plan/Execution architecture (design only, no firmware)
- ANY of the Gimbal UI / visualisation (design only, no code)

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

## Open questions for next session

1. Order priority once parts arrive: analyser first (measure before fix)
   or opto first (fix and verify)?
2. Which workfront to start on? Several are now independent of hardware:
   - Cart firmware: rear_steps + Plan endpoints (#4, #5)
   - Cart firmware: ±450° cumulative yaw (#9)
   - Excel: time-based luminance fetch (#16)
   - Excel: bicycle integration of cart Log (#11)
3. Two reserved per-row inputs in Gimbal UI — defer until first prototype?
4. Should we sketch the Gimbal UI HTML and segment dispatcher in
   parallel, or build them in sequence?
