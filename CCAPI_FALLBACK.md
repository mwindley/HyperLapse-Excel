# CCAPI Fallback — Table-Driven Exposure Continuity

**Status:** Design document. No firmware or Excel code yet.
**Created:** 15 May 2026 (Session C day 9).
**Companion files:** REFERENCE_DATA.md (the table itself), WORKFRONTS.md (queued tasks), PROJECT_STATE.md (handoff).

This document captures a fallback design for exposure control when CCAPI
luminance fetches become unreliable or unavailable. Hand-off to future
sessions: read this end-to-end; don't assume the design transcript is
available.

---

## 1. Problem statement

### What CCAPI does today

The cart fetches a luminance value from the camera via CCAPI roughly
once per photo (or every Nth photo). The formula compares measured
luminance against a target and adjusts Tv / ISO to bring the next
photo closer to target. This is the only mechanism keeping exposure
correct across the steep light ramp of sunset and sunrise.

### Why this is fragile

Three independent failure modes:

1. **Single fetch blocks longer than the photo cadence allows.** Real
   measurement: 2.8s fetch on a photo cycle that should be ~2s costs
   a photo. REQ-PHASES instrumentation traced this to body-read
   time + connect time over WiFi — not the camera.
2. **Total CCAPI unreachability.** AP drops, cart out of range,
   camera WiFi flake. Cart's current behaviour is to keep retrying;
   meanwhile Tv stays frozen at last-known value while real-world
   light continues changing.
3. **WiFi/CCAPI contention competes with the camera's own attention.**
   Community wisdom (camerahacks/canon-ccapi-node) says don't drive
   CCAPI faster than ~3s between calls or the camera starts dropping
   shutter actuations. Confirmed locally: Tv=2 (interval=4s) with
   CCAPI fetch on every photo loses photos. The camera writes fast;
   the WiFi/CCAPI handler is the bottleneck.

### What this design solves

A fallback strategy that:

- **Reduces CCAPI cadence to safe levels** (≥30s between fetches)
  rather than every photo, dramatically reducing contention.
- **Continues operating with no CCAPI at all** for any duration from
  1 minute to a full shoot, with graceful exposure degradation that
  post-processing can recover.
- **Never drops a photo** because of CCAPI state — the photo cadence
  remains sacred, governed by the existing pin-8 + Tv+1.5s rule.

---

## 2. Foundational insights from investigation

These framings drive every architectural choice below. They emerged
through discussion and aren't obvious from the firmware code as it
stands.

### 2.1 Photos sacred; exposure error fixable in post

This principle (already in PREFERENCES.md) becomes the lens for
every tradeoff. A missed photo breaks the hyperlapse and cannot be
recovered. A 1-stop or even 2-stop exposure error is corrected by
LRTimelapse-class tools as part of normal post — they explicitly
perform per-frame antiflicker passes that handle exactly this kind
of drift.

Therefore: optimise the design to take the photo, even if exposure
is approximate. CCAPI is a refinement, not a hard dependency.

### 2.2 The table is local shape, not global trajectory

The Tv/ISO/Interval table in REFERENCE_DATA.md was hand-tuned by the
operator over many shoots. It is real-world data — but it is data
from *specific shoots* on *specific days* under *specific
conditions*. Treating it as "the curve sunset follows" is wrong.
Tonight's sunset will differ in start time, atmospheric clarity,
cloud cover, etc.

What is robust about the table is its **local shape**:

- Tv steps are roughly 1/3-stop apart.
- Through civil twilight, EV moves at roughly 1 step per minute.
- The Tv ceiling is 20s, after which ISO takes over.
- The asymmetry between daylight, civil-twilight, nautical-twilight,
  and astronomical-dark phases reflects atmospheric physics that
  *doesn't* change shoot-to-shoot.

So the useful artefact from the table is not (time → EV), it is
**(current EV → dEV/dt)**. Given where exposure currently sits, how
fast does it need to change?

### 2.3 Exposure formula is monotonic per phase

Sunset mode darkens only. Sunrise mode brightens only. The formula
never reverses direction within a phase, even when the scene
temporarily disagrees (cloud rolling in, cloud rolling out).

This is already encoded in the firmware as `mode=darken` vs
`mode=skylight`. It is not a bug; it is a deliberate design that
prevents the formula from chasing its own tail. Costs: a cloud
event can leave ~10 minutes of frames over- or under-exposed.
Benefits: no oscillation, no glitchy behaviour, single-direction
exposure curve that post-processing handles trivially.

The fallback inherits this naturally: a table-driven advance is
monotonic by construction.

### 2.4 CCAPI cadence is independent of photo cadence

Historically the firmware fetched luminance roughly per photo (or
per N photos). This couples two unrelated concerns:

- **Photo cadence** is set by the Tv+1.5s rule. Sacred. Drives
  pin-8 timing. Can be as fast as 2s.
- **CCAPI fetch cadence** is set by what's safe over WiFi without
  blocking shutter actuations. ≥30s is safe.

Decoupling them is the single biggest reliability win. Photo cadence
keeps producing frames; CCAPI fetches happen on their own slower
schedule and nudge the exposure target when they arrive.

### 2.5 Luminance changes per minute, not per second

Even during the steepest part of civil twilight, real-world EV
changes ~1/3 stop per minute. A 30s CCAPI cadence is *more than
adequate* to track this — at worst we are 1/3 stop behind reality
for half a fetch cycle (~15s), which is well inside post-fix
territory.

---

## 3. Architecture

### 3.1 Two-mode operation

**Primary mode (CCAPI healthy):**
- CCAPI luminance fetch every ~30s
- Formula compares measured luminance vs target, adjusts Tv/ISO
- Cart tracks "current EV anchor" — updated by each successful fetch

**Fallback mode (CCAPI silent ≥ N seconds):**
- Cart continues from last known EV anchor
- Applies rate-of-change from on-cart rate table: dEV/dt at current EV
- Photo cadence and pin-8 unchanged

**Mode switching is automatic.** If CCAPI returns successfully, the
anchor updates and dEV/dt is recomputed from the new position. If
CCAPI stays silent past a threshold, the cart keeps walking the
rate table without complaint. No operator intervention needed.

### 3.2 The on-cart rate table

Not the full Tv/ISO/Interval table. A small derived table:

| Current EV | dEV/dt (stops per second) |
|------------|---------------------------|
| -12 (peak daylight) | very slow (~0.0001) |
| -8  (pre-sunset) | slow (~0.001) |
| -4  (low sun) | moderate (~0.005) |
| 0   (civil twilight) | fast (~0.018) |
| +4  (deep twilight) | slow (~0.005) |
| +8  (astronomical dark) | very slow (~0.0001) |

Exact values derived in Excel from the real-world table and
augmented by past-shoot analysis (§5). Probably ~20 rows; ~120 bytes
in PROGMEM. Linear interpolation between rows.

Cart has one operation: given current EV, look up dEV/dt, integrate
over elapsed time since last anchor.

**Why a rate table rather than a fitted curve:**
- Operator can edit by hand without rederiving coefficients
- No risk of polynomial over/undershoot at curve inflections
- Trivial to validate by inspection
- Storage cost negligible either way; simplicity wins

**Sign of dEV/dt is set by mode:** negative in sunset (darkening),
positive in sunrise (brightening). Magnitudes are symmetric.

### 3.3 Snap to real (Tv, ISO) pair

After computing target EV, snap to the nearest available
(Tv, ISO) pair on the camera's 1/3-stop grid. Two lookup tables on
cart:

- Tv standard values (~50 entries, 1/8000 → 30s + Bulb), sorted
- ISO standard values (~10 entries, 100 → 6400), sorted

Snap rule:
- If EV ≤ EV_ceiling (where Tv=20"/ISO=100): adjust Tv only, ISO=100
- If EV > EV_ceiling: lock Tv=20", adjust ISO

Total on-cart storage: rate table + Tv grid + ISO grid ≈ ~400 bytes
in PROGMEM. Invisible on 256 KB Uno R4 flash; even smaller fraction
on Giga R1.

### 3.4 Cart stays dumb; Excel does the brains

Consistent with day-7/8 architectural decisions throughout the
project.

**Excel (pre-shoot):**
- Holds the real-world Tv/ISO/Interval table (REFERENCE_DATA.md)
- Holds the aggregate dataset from past shoots (§5)
- Computes the (EV → dEV/dt) rate table by combining table-derived
  shape with past-shoot statistics
- Computes EV anchor at shoot start from current sun altitude (via
  Astro.bas)
- POSTs to cart: `(rate_table, Tv_grid, ISO_grid, initial_EV_anchor,
  mode, fallback_threshold_seconds)`

**Cart (runtime):**
- Receives the package from Excel at shoot start
- Per-photo cycle: compute current EV via integration since last
  anchor; snap to (Tv, ISO); apply via CCAPI set command (cheap,
  non-blocking compared to luminance fetch)
- Per CCAPI-fetch-interval (~30s): attempt luminance fetch; on
  success, update anchor and timestamp
- Per pin-8 cycle: fire shutter on Tv+1.5s schedule, unchanged

### 3.5 Sacred boundaries

The fallback design must NOT:

- Block or delay pin-8.
- Block the main loop waiting on CCAPI (existing backoff handles
  this; fallback inherits it).
- Bidirectionally chase brightness within a phase (no oscillation).
- Require new astro maths on cart (Excel pre-bakes everything).

The fallback design MUST:

- Continue producing exposure changes when CCAPI is silent.
- Resync cleanly when CCAPI returns (no jolts).
- Be inspectable — operator can see "I'm in fallback mode, anchored
  at EV=X, advancing at dEV/dt=Y."

---

## 4. Data flow

### 4.1 Shoot-time (forward use)

```
Operator opens Excel workbook on shoot day
  │
  ▼
Enter shoot date + location + start time
  │
  ▼
Excel uses Astro.bas to compute sun altitude trajectory
  │
  ▼
Excel picks rate-table variant (clear / overcast / smoke — §5.3)
  │
  ▼
Excel computes initial EV anchor for shoot start
  │
  ▼
Excel POSTs to cart: /exposure/load
  { rate_table, Tv_grid, ISO_grid, initial_EV,
    mode, fallback_threshold_seconds }
  │
  ▼
Cart confirms load, idle
  │
  ▼
Operator triggers /shutter/start
  │
  ▼
Cart begins photo cadence + opportunistic CCAPI + fallback integration
```

### 4.2 Review-time (retrospective use, learning loop)

```
Past shoot completes, photos saved to laptop folder
  │
  ▼
Python script walks folder, reads EXIF per image:
  - Timestamp
  - Tv, ISO
  - BrightnessValue (camera's own metered EV — free luminance data)
  - GPS if present
  │
  ▼
For each image, compute sun altitude at timestamp via Astro
  (review-mode call: timestamp → alt, az)
  │
  ▼
Compute actual EV per image = log2(Tv) + log2(ISO/100)
  │
  ▼
Excel imports CSV, plots:
  - Actual EV vs sun altitude
  - Delta (actual − current_table_prediction) vs sun altitude
  - Estimated dEV/dt vs EV (finite differences between frames)
  │
  ▼
Operator reviews plot, marks ranges:
  ✓ valid (smooth conditions, table fits)
  ✗ reject (cloud event, foreground lit by car, lens fog)
  │
  ▼
Operator tags shoot with conditions:
  - clear / thin cirrus / overcast / smoke
  │
  ▼
Excel appends ✓ ranges to aggregate dataset, tagged
  │
  ▼
Aggregate dataset regenerates rate-table(s) — median dEV/dt per EV bin,
  per condition tag
```

The cart never sees any of this directly; it only sees the latest
rate-table variant Excel hands it at shoot start.

---

## 5. Future evolution: the learning loop

### 5.1 Why this design improves over time

Every past shoot is a measurement of the (EV, dEV/dt) function we
care about. The data already exists in EXIF on every photo from
every previous luminance-controlled timelapse. The system gets
better not by writing new code, but by **reviewing more shoots and
appending their valid ranges to the aggregate**.

This compounds quietly:
- 5 shoots: rate table is a rough median of one operator's data
- 20 shoots: confidence intervals tight enough to flag anomalies
- 50 shoots: variants by atmospheric condition are well-supported

### 5.2 What we learn that single shoots cannot show

- **Confidence bounds** on dEV/dt at each EV — variance, not just
  median.
- **Sunrise/sunset asymmetry** if it exists in real measurement
  (operator's hand-coded table assumes symmetry; real data may
  disagree).
- **Edge-case discovery** — EV regions where the formula struggles,
  or where the table runs systematically hot or cold.
- **Calibration drift** over hardware lifetime — does the same
  atmospheric brightness map to the same CCAPI luminance reading
  after a year of use?

### 5.3 Variants by atmospheric condition

The operator tags each reviewed shoot with conditions: clear, thin
cirrus, overcast, smoke, etc. Each tag accumulates its own scatter
plot of (EV, dEV/dt) points. Excel ends up with a small library:

- `rate_table_clear.csv`
- `rate_table_overcast.csv`
- `rate_table_smoke.csv`
- `rate_table_default.csv` (all valid data, condition-agnostic)

At shoot time, operator looks at the actual sky and picks which
variant Excel ships to the cart. The cart doesn't know variants
exist; it just receives the right table for the night.

### 5.4 Curation discipline

The operator's eye on post-processed shoots remains the ground truth.
The aggregate learns the **shape** of the EV curve, not its
**correctness**. If a past shoot was 1/3 stop under throughout, the
rate-derived table replicates that mistake — only operator review
catches it.

This is fine because shape is all we need. The rate table's job is
"how fast is brightness changing right now?" not "what is the
correct exposure?" That second question is answered live by CCAPI
when CCAPI works, and approximated by integration when it doesn't.

### 5.5 Caveat: clock drift in old EXIF

Image timestamps depend on the camera's clock being correct at
capture. R3 clock drift is usually small but not zero. For very old
shoots, astro-derived sun altitude could be slightly off →
mislabeled review data.

Mitigations:
- Cross-check old shoots against published sunset/sunrise for the
  location/date; apply clock offset before astro.
- Going forward, cart logs "camera clock at shoot start = X" for
  later audit.
- Curve is smooth enough that 30s clock error is well below
  atmospheric noise floor — not blocking.

---

## 6. Open questions and decisions deferred

### 6.1 Primary vs fallback role for the table

**Option A**: Table is the primary driver. Cart walks the rate
table; CCAPI fetches anchor-correct the cart's notion of "where am
I on the curve." One code path; CCAPI is purely additive refinement.

**Option B**: Table is fallback only. CCAPI drives normally during
healthy operation; table only kicks in after CCAPI has been silent
past threshold. Existing behaviour unchanged when CCAPI works.

A is more elegant but a bigger firmware change. B is more
conservative and incremental. Both end up at similar runtime
behaviour; the difference is "what happens first." Decision
deferred until first prototype.

### 6.2 CCAPI fetch cadence — fixed or adaptive?

**Fixed 30s** is the simplest rule and matches the analysis above.

**Adaptive** could fetch more often during steep ramp regions
(civil twilight) and less often during flat regions (peak day,
deep night) — but the cost of fetching when not needed is small,
and the analysis already shows 30s is safe everywhere. Probably
not worth the complexity unless evidence demands it.

### 6.3 Fallback threshold

How long must CCAPI be silent before cart switches to integration
mode? Candidates:

- **One missed fetch** (~30s) — aggressive, responsive
- **Three missed fetches** (~90s) — conservative, avoids transient WiFi blips
- **Threshold from Excel** — operator-tunable per shoot

Probably configurable, default = three missed fetches.

### 6.4 Re-sync behaviour when CCAPI returns

When CCAPI comes back after fallback, two values exist:
- Integrated EV from rate table
- Freshly-measured EV from CCAPI

These may disagree. Snap directly to measured? Smooth toward it
over a few frames to avoid an exposure jolt visible in the
timelapse? LRTimelapse will smooth small jolts but big ones leak
through.

Probably: if disagreement ≤ 1/3 stop, snap. If > 1/3 stop, smooth
over next 3 frames. To be tested.

### 6.5 EXIF-vs-CCAPI luminance equivalence

Past shoots give us Tv/ISO from EXIF, which gives EV — but that's
the *exposure the camera used*, not the *scene luminance the camera
measured*. These are the same only if the exposure was correct.

For shoots reviewed as ✓ valid, this is fine — operator validated
that exposure was correct, so EV = scene luminance up to a small
offset. For ✗ ranges, the discrepancy is the whole reason they were
rejected. So curation handles this naturally — but worth naming.

EXIF `BrightnessValue` tag *might* give us the camera's own metered
luminance independent of exposure decision. To be confirmed with
sample R3 files.

### 6.6 What happens if CCAPI returns wrong/wild values

A CCAPI fetch that succeeds but returns a clearly-wrong luminance
(transient camera state, lens cap, etc.) would jolt the anchor and
ruin the next ~30s of exposure decisions. Sanity check on each
returned value: discard if it disagrees with integrated prediction
by more than ~2 stops; keep walking the table. Logged for review.

### 6.7 Operator visibility

Operator needs to see, at a glance, which mode the cart is in:
- Cart UI status bar showing "CCAPI: live" / "CCAPI: fallback (Ns)"
- Current EV anchor + integrated EV + last fetch delta
- Per-shoot summary at /stop: how much time in fallback vs live

---

## 7. Proposed workfront entries

To be added to WORKFRONTS.md when this design is ready to act on.

### Firmware
27. **Rate-table evaluator on cart.** Receive (rate_table, Tv_grid,
    ISO_grid, initial_EV, mode, threshold) from Excel via new
    `/exposure/load` endpoint. Integrate dEV/dt over elapsed time
    since last anchor. Snap result to nearest (Tv, ISO) pair. ~80
    lines C. Storage cost ~400 bytes PROGMEM.

28. **Decouple CCAPI fetch cadence from photo cadence.** Replace
    "every Nth photo" with wall-clock interval (default 30s,
    configurable). Photo cadence remains pin-8 + Tv+1.5s.

29. **Fallback mode switching + anchor management.** Track last
    successful fetch timestamp. After threshold of silence, switch
    to integration mode silently. On successful fetch, update
    anchor; if delta > 1/3 stop, smooth over 3 frames.

30. **Cart UI exposure status.** New status bar showing mode (live
    / fallback / seconds-since-fetch), current EV anchor, integrated
    EV, last fetch delta. Parallel to existing CAN status bar.

### Excel
31. **Rate-table derivation.** Compute (EV → dEV/dt) lookup from
    real-world table (REFERENCE_DATA.md §1) using finite differences.
    ~20 rows. Export to cart-compatible binary or JSON.

32. **EXIF ingestion pipeline.** Python script: image folder → CSV
    with (timestamp, Tv, ISO, BrightnessValue, GPS). Tested on past
    shoot data.

33. **Astro retrospective mode.** Confirm Astro.bas accepts past
    timestamps and returns (alt, az). Wire into review pipeline.

34. **Review sheet.** Excel sheet that imports a past-shoot CSV,
    computes EV per image, plots EV-vs-sun-altitude and delta-from-
    table. Operator marks ✓/✗ ranges and tags atmospheric condition.

35. **Aggregate dataset + rate-table variants.** Append ✓ ranges
    across shoots, tagged by condition. Regenerate per-condition
    rate tables (clear / overcast / smoke / default).

36. **Pre-shoot Excel handoff.** Operator picks variant, Excel POSTs
    to cart `/exposure/load` at shoot start.

### Reference data
37. **REFERENCE_DATA.md upkeep.** Each curated shoot's contribution
    summarised in a "shoots reviewed" log within REFERENCE_DATA.md.
    Tracks which data informs the current rate tables. Lightweight
    version control by hand.

---

## 8. Summary in one paragraph

CCAPI is a refinement, not a dependency. The cart's exposure target
advances through sunset/sunrise by integrating a small on-cart rate
table that says how fast brightness is changing at any given EV.
Successful CCAPI fetches every ~30s anchor this integration against
reality; missed fetches leave the cart walking the table on its
own, drifting by at most ~1/3 stop per minute in the steepest
regions — well within post-fix range. The rate table is derived in
Excel from the operator's hand-tuned real-world Tv/ISO/Interval
table plus a growing aggregate of EXIF data from past shoots,
curated by operator review and tagged by atmospheric condition.
Cart stays dumb; Excel does the brains; every shoot makes the
system smarter; photos are never delayed.
