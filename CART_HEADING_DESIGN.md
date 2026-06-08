# Cart Heading — end-to-end design (recon → plan → execution → gimbal)

**Status: DESIGN DISCUSSION captured (Day 25). No code written.** This
is the agreed shape of how a cart heading flows from field capture to
gimbal aim, the trust ladder, and what's built vs blocked vs unproven.
Companion to the #40 BNO section in WORKFRONTS.md and to
GIMBAL_EXECUTION_CAPABILITIES.md. Read those for the gimbal-execution
mechanics; this is the heading-data spine specifically.

---

## 1. The system spine (context)

Recon collects → Excel composes → plan pushed once → cart executes
dumbly. Excel is the brain (all astronomy, cubics, bicycle integration,
exposure); the cart is dumb-but-clever (owns only the time-critical
loops — pin-8 cadence, per-tick cubic eval, motor ramps, Phase-A ease —
because those would jitter if driven live). Division of labour: **Excel
decides *what and where*; the cart decides *exactly when, smoothly*.**

The cart drives **blind** on an approximate path — deliberately. The
bicycle model is known-imperfect and the operator's eye + redrive covers
path error. The BNO exists for ONE job the dumb cart isn't good enough
for: at an anchor, give the gimbal the cart's *true* heading so an
earth-frame gimbal aim is correct against the real world even when the
cart isn't where the plan assumed. A mis-pointed gimbal is a ruined
frame, not a fixable-in-post one — that's the one place precision earns
its keep.

## 2. Why "wrong heading" is the real risk, not "imprecise heading"

The lens is a 14mm full-frame ultra-wide: ~104° horizontal, ~81°
vertical, ~114° diagonal angle of view (measured/confirmed Day 25).
Consequence for the heading design:

- **A few degrees of heading error is invisible.** A 5° offset shifts
  framing by <5% of the horizontal field; the subject stays well inside
  and post can recompose/crop/stabilise. Same logic as "wrong exposure
  fixable in post," applied to aim.
- **A gross heading error is categorical and fatal.** A stale / stalled
  / uncalibrated / sign-flipped read points the gimbal at genuinely the
  wrong sky; even a 104° field can't save a 40°-or-180° error. That is
  the unrecoverable outcome.

**Therefore 3b is primarily a *reject-bad-data* problem, not a precision
problem.** A correction within a few degrees is gravy; a correction that
is confidently wrong is worse than none (no correction = the bicycle
estimate, which is at least in the right ballpark). The cal-gate and
stall-detection are not polish — they are the core safety logic. Their
job is to reject bad heading and fall back, never to apply garbage.

## 3. The heading trust ladder (highest-trust first)

At each anchor the cart picks the best *available, trusted* source and
falls DOWN the ladder when a source fails its gate. It never applies a
source that is confidently wrong.

1. **Operator + iPhone (manual override).** The present, attentive
   operator supplies a manual true heading when the BNO is untrustworthy
   or just looks wrong on the UI. Human beats sensor.
2. **BNO / IMU (accepted, cal-ungated — decision Day 25).** At a
   stationary anchor the BNO's measured true heading replaces the planned
   estimate. The cal byte is NO LONGER a trust gate (see §6 — measured
   ±5° vs iPhone at cal 0). The only surviving reject-logic on this rung
   is **stall detection** (a frozen / climbing `last_poll_ms_ago` is
   categorically fatal and unrelated to cal — a stalled stream's heading
   is stale garbage). A non-stalled read is accepted regardless of byte;
   the operator override (rung 1) is the backstop that makes accepting it
   safe.
3. **Planned `expected_cart_heading` (the safe floor).** Always present
   in the pushed plan — Excel's bicycle-integrated θ for that waypoint.
   Used whenever 1 and 2 are unavailable. An estimate, but always in the
   right ballpark.

**No continuous cart-side heading.** The cart does NOT dead-reckon its
own heading tick-by-tick. It would be redundant (the planned θ already
encodes the same bicycle maths, computed better in Excel) and would be
the *same imperfect model* the BNO exists to correct. The cart only
needs a trusted heading at the **discrete anchor moments** before an
earth-frame gimbal move — between anchors the gimbal is either tracking
a cubic (cart-frame, heading-independent) or in pan-follow (cart-frame).
This is what makes "no live bicycle model on the cart" viable.

## 4. Where the heading lives at each stage

| Stage | What carries the heading | Notes |
|---|---|---|
| **Recon** | CartLog: distance + turn per waypoint, cart parked at each mark | Today: turns are *relative steering inputs*, NOT absolute headings. Proposed (this discussion): also record BNO heading + cal byte at each marked waypoint — record-only. See §5. |
| **Excel / plan** | Bicycle integration of (θ₀ + turn/distance sequence) → absolute true-bearing θ per waypoint | θ is currently *implied/computable* but NOT stored as a column and NOT pushed. Materialising it is the 3b prerequisite. `expected_cart_heading` = this θ made explicit. Source = BicycleModel.bas (built). |
| **Push** | Plan stream: `expected_cart_heading` (one float per anchored waypoint) + per-segment earth/chassis frame tag | NOT in the stream today — confirmed by grep: PlanSegment has 8 fields (…, anchor), neither present. Append at the TAIL per build-lesson 12. |
| **Cart use** | Per-segment scalar, dormant until the cart parks at that anchor | Not a live signal. The frame tag decides which gimbal cubics get the correction (earth-frame) vs which don't (chassis-frame / pan-follow). |
| **Cart check** | At the anchor: BNO read vs the planned scalar, gated | The trust ladder (§3) resolves to a single heading the correction consumes. |
| **Gimbal handoff** | `gimbal_yaw_correction = (−true_yaw) − expected_cart_heading`, applied additively to earth-frame cubics only | Sign: BNO yaw negated (BNO CW = negative, compass CW = positive). Both terms must be compass-CW-positive true bearings or a silent sign error hides here. Excel `bnoOffsetDeg` (Adelaide declination +8.11° + ~+1° mount) folds in at this same line. |

## 5. Two BNO heading capabilities — same mechanism, two roles

Both share the **"capture heading + cal byte, record-only"** pattern (the
3a anchor instrumentation already does this at execution anchors):

- **Recon-time heading at waypoints (NEW, proposed).** When the operator
  marks a waypoint (cart parked), also log the BNO heading + cal byte.
  Role: gives Excel measured ground-truth to **correct or sanity-check**
  the open-loop bicycle integration, which otherwise drifts further from
  θ₀ the longer the path. Anchors the planned `expected_cart_heading` to
  reality at each waypoint instead of pure dead-reckoning.
- **Execution-time heading at anchors (3b).** At the stationary "duck
  off" before an earth-frame gimbal move, read the BNO and feed the
  correction. Role: the live gimbal-aim correction.

**Open design intent to settle:** does the recon heading *replace* the
integrated θ, or *correct/sanity-check* it (Excel reconciles
measured-vs-integrated, operator sees disagreements)? Leaning
sanity-check + operator-visible, trust deferred — see §6.

## 6. The (now-answered) cal question — cal 0 ACCEPTED for production

**Was: is a byte-0–1 heading on a saved DCD trustworthy? — ANSWERED Day 25: yes (±5° vs iPhone at cal 0).**

Key fact (methodproven, Day 24): the **cal byte ≠ the stored
calibration.** The byte reports *current confidence*, not whether a valid
DCD is loaded. On a mounted, flat-moving cart the byte reads **0–1 even
though the stored DCD is valid and the heading is good** — it only climbs
to 2–3 with off-plane motion the bolted cart can't easily produce. The
unit is calibrated ONCE off-cart (figure-8 → cal 3 → `/savecal`; DCD
persists across power cycles), and production boots on that stored DCD.

So a low byte at a waypoint is a *shake-state artifact*, NOT a bad-heading
signal — a pre-calibrated unit *should* give good headings at byte 0–1.
BUT this is **reasoned, not yet proven** — the methodproven note marks
"is cal 1 actually usable?" as an explicit open item, to be settled by
real-world use, not more bench.

**Increment-0 measurement (Day 25, on the assembled cart, saved DCD):**
full 360° rotations, BNO `true_yaw` vs iPhone compass agreed within
**±5°, at cal byte = 0.** The reasoning held — the byte is a shake-state
artifact, not a validity signal; the DCD does its job. ±5° against the
14mm's ~104° field is <5% framing shift — invisible, post-fixable.

**Production decision (Day 25): cal byte = 0 is ACCEPTED as production-
valid heading. The old "reject ≤1 / keep-previous" cal-gate is RETIRED.**
The byte may still be logged for the record, but it no longer blocks or
downgrades a reading. This removes the cal-gate branching and the
byte-tied keep-previous fallback from 3b.

**What makes accepting cal-0 safe:** the **operator + iPhone override is
now a REQUIRED capability**, not optional. With the cal byte no longer
guarding against a bad read, the guard becomes the present, attentive
operator, who can override any BNO reading that looks wrong on the
Execution UI. The removed sensor-confidence heuristic is replaced by a
human override that can actually be trusted.

**What is NOT yet proven (deferred to user-acceptance, post-production
build):** the ±5° result is single-environment, cart hand-rotated. Whether
it HOLDS with motors running, on the move, across a full night and across
different magnetic sites is settled in **UAT during real shoots** — not on
the bench, not before shipping the capability. Stall-detection stays
regardless (a stalled stream is fatal independent of cal).

**Still record-first for the OTHER variables:** keep logging heading +
cal byte at recon waypoints and execution anchors — not to gate trust
(that's settled) but to generate the measured-vs-integrated and
across-night data that UAT needs. Safe whether or not it all proves out.
**We designed the capability; real-world UAT confirms it holds — maybe
OK, maybe not, but cal-0 is accepted to ship.**

## 7. Error budget — bounded to operator error, by design

The operator is the human anchor at the one categorically-unrecoverable
point:
- **Recon:** operator records cart heading-at-start (θ₀) in the Cart
  Recon UI — the true-north reference (cart edge to north per iPhone).
- **Plan:** operator owns every Cart Plan edit; θ integration starts
  from that θ₀, in true bearings consistent with the gimbal plan's astro
  azimuths.
- **Execution start:** operator physically positions the cart to the
  start heading at t=0; the Execution UI informs (shows target vs live
  IMU/iPhone) so they match it before arming.
- **In-shoot:** operator present and active all night, iPhone in hand,
  IMU on the Execution UI; can override any anchor read.

Autonomous-failure modes are removed (the cart never guesses its own
absolute heading — set and checked by a present human at both ends). The
residual risk collapses to **operator error**, bounded by attention and
forgiven by the wide FOV. The architecture's goal is not to beat the
operator — it's to **never be confidently wrong without the operator
seeing it.**

---

## 8. The plan (sequenced, no code yet)

Dependency order. Each step is small and most reuse proven patterns.

**A. Recon-time heading capture (record-only).**
   - Cart: on Mark-Waypoint, sample BNO `true_yaw` + cal byte into the
     CartLog waypoint (`W`) event. Same record-only pattern as the 3a
     `A`-events; append fields at the tail (build-lesson 12) so existing
     CartLog parsers stay intact.
   - Excel: `BuildPlanFromCartLog` reads the new heading + cal columns.
   - Value: starts generating the real-world measured-vs-integrated data
     that settles §6 — and is safe whether or not it proves out.

**B. Excel materialises `expected_cart_heading` per waypoint.**
   - Run BicycleModel.bas integration over the Cart Plan (θ₀ + turn/
     distance sequence) to an absolute true-bearing θ at each anchored
     waypoint. Maths exists; the "write θ per waypoint" wiring doesn't.
   - Decide (from A's data + §5 open intent) whether a recon BNO heading
     replaces or sanity-checks the integrated θ. Show measured-vs-
     integrated to the operator either way.

**C. Plan-stream change — push the heading.**
   - Add `expected_cart_heading` (float) + earth/chassis frame tag to
     PlanSegment, the s-string parser, and the Excel pusher
     (TrackPlanPush / PlanPush). Tail tokens, order-independent, per
     build-lesson 12 (the `anchor` flag set this precedent).
   - Cart receives + stores the per-segment scalar; dormant until anchor.

**D. Build 3b — the correction.**
   - At the stationary anchor: resolve the trust ladder (§3) to one
     heading — operator/iPhone override, else gated BNO, else the pushed
     `expected_cart_heading`.
   - Apply `gimbal_yaw_correction = (−true_yaw) − expected_cart_heading`
     to earth-frame cubics only (frame tag decides). **No cal-gate** (cal
     0 accepted, §6). Surviving reject-logic = **stall-detect**
     (last_poll_ms_ago not climbing → else keep-previous). This is the
     reject-bad-data logic of §2 narrowed to stalls only, not a precision
     tuner.
   - **Operator/iPhone override is a required part of 3b**, not a later
     nicety — it's the safety mechanism that replaced the cal-gate (§6).
     The Execution UI must let the operator supply/confirm a manual
     heading at an anchor.

**Sequencing note (next-session call):** A (recon capture) and C (stream
change) are both small and somewhat independent; A starts producing the
trust-settling data immediately and is the cheapest first move. C is the
hard 3b prerequisite. B sits between. Likely order A → B → C → D, but
confirm at build time.

**Still decided/known and NOT re-opened:** read model = stationary "duck
off" averaged window (not the old 500/400 mm crawl); ~3 anchors per
12 h night; pan-follow + cart path stay BNO-independent (cart drives
blind); LOCK moving-case shares the same heading mechanism and unblocks
with 3b; the BNO motor-power stall is RESOLVED (Day 25, 2.2k pull-ups).
