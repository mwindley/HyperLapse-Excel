# WORKFRONTS.md — Day 24 (part A) — Real-time anchor (Model B) PROVEN + Phase-A design

**Append after the preview note. Relates to #57 (shoot anchor), #5a,
gimbal execution. Sketch reached build soak-v13.**

---

## Real-time anchor / Model B — built + proven on hardware (Day 24)

**The principle (operator):** Cart waypoints execute on the cart's own
relative clock — start early/late, no matter. The gimbal also runs on
relative time EXCEPT when it must track an astro object — sun/moon/mw
are at a real-world position at a real moment, regardless of when the
operator pressed go. The gimbal can't control actual start time, so
the cart must LEARN real start time and use it for astro tracking.

**Time-model decision — Model B chosen.** Test question: "what if I
start 30 min late?"
- Model A (cubics repinned to a shared shoot-start t=0): late start →
  gimbal points where the sun WAS at planned start (30 min stale),
  needs a re-fit. Simple clock, NOT flexible.
- Model B (astro cubics keyed to REAL time; cart maps via a learned
  offset): late start → cart evaluates cubic at actual-now → gimbal
  points where the sun ACTUALLY is → self-corrects, joining the arc
  30 min in. Flexible; matches the operator principle. CHOSEN.

**Built (soak-v12 → v12a → v13):**
- Real-time anchor: `/settings/realtime?ms=<epoch_ms>` — Execution UI
  hands the cart real wall-clock at ACTUAL start. Cart (no RTC) retains
  `rt_offset_ms = epoch_ms - millis()`; `cartRealTimeMs()` returns real
  epoch-ms from millis() thereafter.
  - BUG fixed (v12a): epoch-ms is 13 digits, overflows the Giga's
    32-bit long; `atoll` + `(unsigned long)` Serial cast truncated to
    low-32 (showed 2002966303 = 1780119426847 & 0xFFFFFFFF). Fix:
    `strtoll` (64-bit parse) + `snprintf %lld` print. %lld renders fine
    on the mbed_giga core.
- TrackPath gains `real_t0_ms` (real epoch-ms of the cubic's t=0).
- `/settings/trackpath` accepts optional `rt0=` (AstroPush will send
  the real Now() it fitted against). Absent → real_t0_ms=0 → relative
  fallback (keeps the proven hand-pushed test working).
- `trackPlanTick`: interval WINDOW matching stays arm-relative (windows
  authored relative to shoot start, cart runs whenever); CUBIC EVAL
  uses real time when anchor set AND cubic has rt0:
  `eval_s = (cartRealTimeMs() - real_t0_ms)/1000`. Else relative.

**Hardware test (gimbal powered, no camera/cables):** set anchor, pushed
sun cubic 0.1°/s with rt0 = 100s in the PAST, pushed interval, armed.
Gimbal slewed to ~10° immediately (= 100s of real elapsed time, not
0), then crept up (status read 19.6° a bit later, pitch flat 0). **Model
B proven: gimbal joins the sun's real-time arc at the correct current
point — late-start self-correction works.**

## Phase-A acquire — design resolved (NOT yet built)

**Problem surfaced by the test:** the move ONTO the curve snapped (~10°
in ~0.5s). The executor drives each tick with a fixed 0.2s time-byte
and NO ease, so initial acquisition has no acceleration profile.

**Plan requirement:** every gimbal move must EASE — gentle accel at
start, gentle decel at end. Ease bands are audience frame counts @60fps:
Just-perceptible=3 (~50ms), Comfortable=10 (~167ms), Cinematic=30
(~500ms). Ease = the ramp at each end; Move-t (e.g. "~12 min") = total
slew time.

**The curve-ball:** Phase A (slew to sun) must account for the sun
moving DURING the slew (already solved historically) — but a late cart
start means this must be recomputed ON THE CART, since Excel doesn't
know actual start time. That breaks a purely pre-baked Excel cubic for
the acquire destination.

**Resolution (keeps cart dumb-ish):** Phase A = the cart EASES from its
current pose ONTO the real-time sun cubic it already holds (Model B),
catching the moving target, then blends into normal tracking. The cart
does NO astronomy — it reads the sun cubic's present real-time value
and ramps toward it over a Move-t/Ease-band profile. Late-start recalc
is automatic because the cubic is real-time-keyed.

**To build next:** executor behaviour — when a Track interval becomes
active and the gimbal is off-curve, ease onto the curve over the
ease/Move-t ramp (instead of snapping), then hand to steady tracking.
Plus Excel side: AstroPush to send `rt0=`; trackplan pusher; the
ease-band → cubic/ramp parameters reach the cart.

**Status:** Cart-side execution engine proven on hardware for: cart
motion push+execute, track executor, preview/step, real-time anchor +
Model B astro eval. Remaining: Phase-A ease-onto-curve (executor),
Excel gimbal pushers (trackplan, previewplan, rt0 on trackpath,
Move-cubic Stage 4), pan-follow execution. Ry=Cy holds throughout
(track path separate from deferred BNO correction).

**Also flagged (not chased):** recurring LOOP-LONG ~1.6–2.6s stalls on
empty/favicon WiFi requests (browser driving). Camera off so harmless
now; needs a request-read timeout before a live shoot (frame risk).

---

## Convergence point — real-world-correct gimbal yaw (next steps)

The journey from Excel gimbal plan → executable has built the cart-side
engine and proven it on hardware. The remaining steps converge on
making the gimbal point at the TRUE world target, which needs two
real-world inputs:

1. **Real time** → where the sun actually is. DONE (Model B, proven).
   The gimbal now knows real time and can be at the correct astro yaw.

2. **Real cart yaw** → how the cart is actually oriented in the world.
   The gimbal is mounted on the cart; if the cart isn't pointing where
   the plan assumed (drove an S-bend, terrain, late/off-line), the
   gimbal's yaw-relative-to-cart no longer equals yaw-relative-to-world.
   To point at the real sun, the gimbal yaw must be corrected for the
   cart's actual heading.

This is the #40 BNO work, observe-only all session (`Ry=Cy` holds, no
correction applied — was blocked on plan-stream anchor fields + heading
model). With Model B providing the time half, the heading half is the
unblocking piece: gimbal_world_yaw = astro_real_time_yaw, and
commanded gimbal yaw = world_yaw − real_cart_heading (BNO).

So real-world correctness = Model B (time, done) + BNO cart-yaw
correction (heading, to wire). Folding real cart yaw into the gimbal
yaw is what finally lets Ry≠Cy.

**Full remaining next-steps list:**
- Phase-A ease-onto-curve (executor eases onto real-time sun cubic).
- BNO cart-yaw correction folded into gimbal yaw (real-world heading).
- Excel gimbal pushers: trackplan, previewplan, rt0 on trackpath,
  Move-cubic Stage 4.
- Pan-follow execution.
