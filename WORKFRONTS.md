# HyperLapse Cart — Open Workfronts

**As of:** Session C day 17, 23 May 2026

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
- **NEW #52 Investigate I²C cliff mechanism** — open. Avoidance
  fix (100ms throttle) sufficient; root cause not characterised.
  Park unless cliff recurs at lower read rates. If revisited:
  scope SDA/SCL signal integrity, check pull-up strength, consider
  external 10 kΩ pull-ups per Pololu's published troubleshooting.

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

---

## Day-17 plan-execution test bank — results recorded

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
stores ~9 yaw/pitch pairs (sunrise/sunset/MW × rise/mid/end
keyframes ≈ 50 bytes). On Show astro tap with type+keyframe context,
cart commands gimbal to stored position.

Path B (cart computes astro on-the-fly via ported `GetSunGimbalAngles`)
was considered and rejected — duplicates Excel logic, larger flash
hit, conflicts with day-8 architecture "astro pre-baked in Excel,
cart sees cubic coefficients only."

*Scope:*
- Excel side: button to "Push astro to cart" that calls
  `GetSunGimbalAngles` / `GetGCGimbalAngles` (Astro.bas, already
  built) at 9 (event, keyframe, time) combinations for today, posts
  to new cart endpoint `/settings/astropos?...`
- Cart side: settings struct gains the 9 yaw/pitch pairs; new
  endpoint receives and stores
- New endpoint `/gimbal/showastro?type=sunset&kf=mid` drives gimbal
  to stored position
- Snap var endpoint reads current Cy/p vs stored astro position and
  returns the delta; UI auto-fills the yaw Δ / pitch Δ fields

*Status:* design only, not built. Astro positions stale if shoot is
delayed past authoring time — acceptable artistic latitude per
GIMBAL_VIZ.md §1 principle.

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
