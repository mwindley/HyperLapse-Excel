# HANDOFF — Day 24 part A → next session (knock off gimbal steps 2, 3, 4)

Read this first, then the per-topic WORKFRONTS_Day24_partA_*.md notes
and the main WORKFRONTS.md. All deliverables in /mnt/user-data/outputs/.

## Where we are (end of Day 24 part A)

Cart-side execution engine is BUILT and HARDWARE-PROVEN for both halves.
Current sketch = **soak-v13b** (DJI_Ronin_Giga_v2.ino). Production
config unchanged: BNO live observe-only (stored DCD, no calibrateAll),
STUB_BNO undefined, BNO_CAL_CAPTURE off. **Ry=Cy holds throughout** (the
track path is separate from the deferred BNO gimbal-yaw correction).

Proven on hardware this session (gimbal powered, NO camera/cables —
keep that discipline for first-motion tests):
- Cart motion: Excel→push→execute (CartPlanPush.bas + /plan/advance).
- Gimbal track executor (#5a): walks track_plan[], evaluates cubic,
  drives gimbal. trackPlanTick @5Hz, /track/start /stop.
- Preview/step mode: /preview/step|goto|status + /settings/previewplan,
  bidirectional, 12°/s (PREVIEW_SLEW_DPS, one #define).
- Real-time anchor + Model B: /settings/realtime?ms= , cartRealTimeMs(),
  astro cubic evaluated at real time → late start self-corrects.
- Excel pushers DONE: TrackPlanPush.bas (intervals), AstroPush.bas (now
  sends rt0 on cubics). Both verified end-to-end with real shoot data.
- Load-disarm safety: trackplan idx=0 / trackpath seg=0 disarm the
  executor so loading a plan never moves the gimbal.

## LOCKED conventions / gotchas (do not relearn the hard way)
- **Epoch convention:** rt0 AND the /settings/realtime anchor MUST both
  be LOCAL-time-as-epoch-ms via DateToEpochMs(Now()) (serial×day-ms).
  NOT true UTC. Cart subtracts (real_now - rt0); offset cancels only if
  both match. Bench tests that fed true-UTC epoch-ms are NOT
  representative — re-test the anchor with local-as-UTC.
- **Arduino auto-prototype trap** (arduino-cli #2696/#1269): any sketch
  function taking/returning a custom struct type (e.g. TrackPath*) needs
  an EXPLICIT forward declaration right after the struct, or you get a
  bogus "'X' does not name a type". g++ compiles fine; only the Arduino
  preprocessor breaks. (Cost us 2 rounds.)
- **Const ordering:** define #defines/consts BEFORE the functions that
  use them; the executor cascade-failed when placed above GTM_/GTO_.
- **64-bit epoch:** epoch-ms is 13 digits → overflows Giga 32-bit long.
  Use strtoll + snprintf %lld, never atoll/(unsigned long) casts.
- **Time split:** interval WINDOW matching = arm-relative (cart runs
  whenever); CUBIC eval = real time (Model B). Don't conflate.

## NEXT STEPS — knock off 2, 3, 4 (1 is mostly done)

### Step 1 leftovers (Excel pushers — small)
- **previewplan pusher** in Excel: compute each GP's preview pose and
  push to /settings/previewplan (idx,yaw,pitch,label). Pan-follow's
  preview pose is the open question (it follows cart heading — what
  pose to show when stationary? likely the heading-relative angle at
  the GP's anchor). Move→endpoint; Track→astro keyframe/cubic pose at
  planned time; Lock/END→held.
- **Move-cubic Stage 4** in PlanPush.bas: PlanPush still only LOGS Move
  GPs (cubic coeffs deferred). Needs the ease-band→cubic computation
  then a POST. Ties into Step 2.

### Step 2 — Phase-A ease-onto-curve (executor) — RESOLVED design, build it
Requirement: every gimbal move must EASE (gentle accel/decel), not snap.
Ease bands = audience frames @60fps: Just-perceptible=3 (~50ms),
Comfortable=10 (~167ms), Cinematic=30 (~500ms). Move-t = total slew
time; Ease = the ramp at each end.
The test snap (10°→100° in ~0.5s) happened because trackPlanTick drives
each tick with a fixed 0.2s time-byte and NO ease on the initial
acquisition.
RESOLUTION (keeps cart dumb): Phase A = cart EASES from current pose
ONTO the real-time sun cubic it already holds (Model B), catching the
moving target, then blends into normal tracking. Cart does NO astronomy
— reads the sun cubic's present real-time value and ramps toward it over
a Move-t/Ease-band profile. Late-start recalc is automatic (cubic is
real-time-keyed).
BUILD: when a Track interval becomes active and the gimbal is off-curve,
ease onto the curve over the ease ramp (instead of snapping), then hand
to steady per-tick tracking. The slew-to-acquire is NOT operator-visible
and should not eat the track window (window = pure track; acquire is
overhead before it).

### Step 3 — BNO cart-yaw correction into gimbal yaw (real-world heading)
This is the convergence keystone that finally lets Ry≠Cy.
The gimbal now knows real TIME (Model B) so it can be at the correct
astro yaw. But correct WORLD yaw also needs the cart's real HEADING —
the gimbal is cart-mounted; if the cart isn't oriented as planned
(S-bend, terrain, off-line), gimbal-yaw-relative-to-cart ≠ relative-to-
world. #40 BNO has been observe-only all session (correction blocked on
plan-stream anchor fields + heading model).
WIRE: commanded_gimbal_yaw = astro_world_yaw − real_cart_heading(BNO).
Sign note (from Day-23): negate BNO yaw when folding in (BNO CW
negative, compass CW positive). Cart can't compute heading itself
(no bicycle model on cart — that's Excel BicycleModel.bas); the cart
reads BNO real cart yaw. Couples to the plan-stream anchor fields
(anchor flag, expected_cart_heading, frame tag) NOT yet in the
PlanSegment struct — that stream change is the prerequisite (#72-adj).

### Step 4 — Pan-follow execution
Not built on the cart at all. Pan-follow = gimbal follows cart heading
(cart frame). Needs an execution path (likely BNO-driven, ties to
Step 3's heading read). Define its preview pose too (Step 1).

## Suggested order next session
Step 2 (Phase-A ease) is self-contained and removes the only ugly
hardware behaviour seen (the snap). Step 3 (BNO correction) is the
biggest value but needs the plan-stream anchor fields first. Step 4
leans on Step 3. So: Step 2, then the plan-stream anchor fields, then
Step 3, then Step 4 + the leftover previewplan/Move-cubic pushers.

## Known issues parked (not chased)
- Recurring LOOP-LONG 1.6–2.6s stalls on empty/favicon WiFi requests
  (browser driving). Camera off = harmless now; needs a request-read
  timeout BEFORE a live shoot (frame-timing risk).
- /debug/trackeval uses cubic t0_ms clock vs executor real-time —
  cosmetic display mismatch only.
- Initial park→cubic-start move uses fast 0x02 time-byte (subsumed by
  Step 2's ease work).

## Operator preferences (STRICT — see PREFERENCES.md)
Plain-text questions, one at a time. NEVER suggest ending the session.
Bare URLs on their own line in chat. Windows cmd. Minimal preamble,
short replies, one suggestion at a time. Build lessons → PREFERENCES.md
(candidate new ones: Arduino auto-prototype trap; const ordering;
64-bit epoch parse; load-disarm-on-plan-load safety; epoch convention
must match across rt0 + anchor).
