# Exposure Fallback — Table-Driven Exposure Continuity

**Status:** Design document — NOW BUILT (Day 32). The table-driven exposure
formula is implemented: Excel `Formula.FallbackFormula` ramps Tv/ISO sunset->
sunrise, `Formula.PushFormulaToCart` POSTs it to the cart `/exposure/load`, and
PushFormulaToCart is folded into the `PushToCart` prep chain. The cart's LUM walk
runs table-driven when CCAPI luminance is unavailable. This doc remains the design
+ rate-table + validation reference; the original "no code yet" status is retired.
**Created:** 15 May 2026 (Session C day 9).
**Supersedes:** `CCAPI_FALLBACK.md`, `WORKFRONT_36.md`, `OLD_SUN_TABLE.md` (all folded in here).
**Companion files:** `WORKFRONTS.md` (queued tasks under "Exposure fallback + validation"), `PROJECT_STATE.md` (handoff).

This document captures a fallback design for exposure control when CCAPI
luminance fetches become unreliable or unavailable, together with the
validation method for refining the underlying rate table from real-shoot
exposure exports. Hand-off to future sessions: read this end-to-end;
don't assume the design transcript is available.

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

### The learning loop in one sentence

**Every successful CCAPI-driven shoot improves the fallback table
used the next time CCAPI fails.** CCAPI in production is the
measurement instrument; the rate table is the predictor that runs
when the instrument is unavailable. Each CCAPI shoot's EXIF Tv/ISO
is a real-world (EV, t_rel) sample. Aggregating these refines the
predictor. Fallback episodes get shorter and more graceful over
time as a direct consequence of normal production use. See §5 for
the curation and shoot-type discipline that protects this loop
from self-referential corruption.

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

The Tv/ISO/Interval reference table (Appendix A) was hand-tuned by
the operator over many shoots. It is real-world data — but it is
data from *specific shoots* on *specific days* under *specific
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

Exact values derived in Excel from the real-world reference table
(Appendix A) and augmented by past-shoot analysis (§5). Probably
~20 rows; ~120 bytes in PROGMEM. Linear interpolation between rows.

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
- Holds the real-world Tv/ISO/Interval reference table (Appendix A)
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

## 5. The learning loop — validation method and worked examples

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

**Sky-condition needs operator log.** Weather isn't in EXIF — needs
operator-tagged metadata at shoot start, or post-hoc weather-API
lookup per shoot date.

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

**Don't fight individual-shoot accuracy.** Per architectural
principle #2 ("wrong exposure fixable in post"), individual shoots
with operator-nudge or weather variance are not worth rescuing
data-wise. Treat all clean exports as input to the soup; accept
noise; trust median across N≥3-4 shoots before table changes.

### 5.4a Shoot-type discipline — only CCAPI-driven shoots refine the table

**Critical methodological finding (day 9 evening, Jan 22-23 2026
shoot review).** A shoot's EXIF Tv/ISO record tells you what the
camera DID, not what reality WAS. Two distinct shoot regimes
produce that EXIF data, and only one of them is usable for
refining the recipe table:

1. **CCAPI-driven shoots (refinement-eligible).** Cart reads
   luminance from camera in real time and adjusts Tv/ISO to
   match. EXIF Tv/ISO therefore tracks *reality*. Comparing this
   EXIF curve against the reference table is a legitimate
   **table-vs-reality** measurement.

2. **Table-driven shoots (NOT refinement-eligible).** Cart applies
   a pre-baked recipe (possibly an older version of the same
   table, possibly with shoot-time operator nudges). EXIF Tv/ISO
   tracks the *recipe*, not reality. Comparing this EXIF curve
   against the reference table is a **table-vs-table** diff — it
   tells you whether two recipe versions agree, not whether
   either matches reality.

Both regimes have valid uses, but they're not interchangeable as
refinement input. Confusing them silently corrupts the aggregate
dataset with self-referential bias: feeding "table-driven" exports
back as ground truth would lock in the original table's errors and
amplify operator nudges.

**Worked example — the Jan 22-23 2026 shoot:**
- 6,176 photos across full sunset → astro → sunrise
- Recipe was table-driven (no CCAPI luminance loop active)
- Validated against canonical Appendix A reference table
- Sunset block: 74% within ±0.5 stop, mean EV_diff -0.23
- Pre-sunset bins (-80 to -30min): std 0.07-0.11 — recipes agree
  to ~1/8 stop. Tight match between this shoot's recipe and the
  canonical table.
- t=0 to +30min: -0.5 to -1.0 stop divergence. Two recipe
  versions disagreeing about the rapid-twilight slope.
- t=+60 to +70min: +2 to +3 stop wild divergence — the §5.6.3
  manual-time-nudge signature (large offset at astro-lock
  boundary while mid-curve still matches well).

Verdict: this shoot is **not** refinement input. It is, however,
informative about:
- Recipe-version consistency at the start of the sunset ramp
- Where this shoot's recipe diverged from canonical (could be
  intentional refinement applied earlier or operator nudge)
- The day-9 manual-time-nudge gotcha replicating in a new shoot

**Going forward:** every shoot must be tagged at capture time with
the regime that produced it (CCAPI-driven / table-driven). Without
this tag, EXIF analysis is ambiguous. Add to shoot-log workflow.

**Toolchain status (day 9 evening):** `exif_ingest.py` and
`validate_exposure.py` are working end-to-end. The pipeline is
correct; the input needs to be the right shoot type. Once a
CCAPI-driven shoot is in hand, the same toolchain will produce a
genuine table-vs-reality measurement.

### 5.5 Validation method — proven day 9 with two exports

Step-by-step process for processing a new exposure export:

1. Load exposure export (columns: SourceFile, ExposureTime, ISO,
   DateTimeOriginal).
2. **Check Tv column for Excel date-mangling** (see §5.6.1).
3. **Check camera clock for DST offset** (see §5.6.2).
4. Detect shoot blocks via inter-photo gap > 600s. Some shoots
   run continuous through astro window, others split at
   operator break. If no gap, split at midpoint between
   sunset and sunrise.
5. For each block, compute t_rel = photo_time - sun_event_time.
   Sun event from ephemeris (use timeanddate.com Adelaide page
   for accuracy).
6. Compute EV per photo: `EV = -log2(Tv_s) - log2(ISO/100)`.
   Linear-interpolate old table EV at each photo's t_rel.
7. Filter Tv_s == 0 garbage rows (sub-second photos truncated
   to int 0 in some export formats).
8. Compare: mean/median/std EV_diff, % within ±0.5/±1.0/±2.0
   stop. Bucket by 10-min time bins.

### 5.6 Method gotchas — three to remember

#### 5.6.1 Excel date-mangling of Tv column

If the export came through a workbook column without text
formatting, Excel interprets fractional Tv values as dates:

- `1/4` → "1-Apr-current-year" → Excel serial like 46113
- `1/80` → "1-Jan-1980" → serial 29221
- `1/2000` → "1-Jan-2000" → serial 36526
- `1/13` → "1-Jan-2013" → serial 41275

Decoder rules:
- Year 1950-1999 with day=1 month=1 → Tv = 1/(year-1900)
- Year 2026 with day=1, month varies → Tv = 1/month
- Year 2000-2099 with day=1 month=1, year-2000 in
  {13,15,20,25,30,40,50,60,80} → Tv = 1/(year-2000); else 1/year
- Year >= 2100 with day=1 month=1 → Tv = 1/year (genuine fast)

Prevention: format Tv column as TEXT in Excel before export.

#### 5.6.2 Camera-clock DST

Camera may be on ACDT while shoot is in ACST window — Adelaide DST
runs Oct→Apr (ended 5 April 2026). Symptom: implied sunset/sunrise
from Tv inflection points lands ~1 hour later than ephemeris.
Subtract 1 hour from timestamps if so. A 1-hour offset masquerades
as ~10-stop formula failure if uncaught.

#### 5.6.3 Manual time-nudge artefact

The old Excel could shift the entire ramp earlier/later by 10-15
min (operator action, not visible in EXIF). Symptom in EV_diff:
large systematic offset (>±1 stop) concentrated in the
rapid-changing zones either side of astro-lock entry/exit, with
mid-curve fast-Tv region still matching well. Don't update table
from a shoot showing that pattern; flag it as "operator-nudged"
in shoot log instead.

### 5.7 Day-9 results across two shoots

*April 17-18 2026, DST-corrected:*
- Sunset side: mean EV_diff +0.02, 73% within ±0.5 stop,
  95% within ±1 stop. Old table ~0.5 stop darker than reality
  at +10 to +30 min.
- Sunrise side: could not validate (operator skipped ISO ramp).

*Feb 20-21 2026, sunset 20:04 / sunrise 06:54 ACDT:*
- Sunset mid-curve (-30 to +10 min): 82% within ±1 stop.
  Old ~0.5 stop darker than reality at t=0 — matches April.
- Sunset astro-lock zone (+20 to +50 min): consistent -2.5
  stop offset. **LIKELY ARTEFACT** — operator confirmed the
  old Excel had a manual time-nudge to hurry/slow the ramp
  relative to sun event, and believes it was used on this
  shoot. Cannot attribute this offset to the table itself.
- Sunrise pre-ramp (-100 to -70 min): ~2 stops darker than
  recipe. Same possible nudge artefact.

**Signal vs noise:**
- Repeated across shoots (likely table refinement): post-sunset
  rapid twilight ~0.5 stop too dark.
- Single shoot, plausibly nudge-driven: large astro-lock
  offsets. Don't over-correct from these.

### 5.8 Caveat: clock drift in old EXIF

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

**BrightnessValue is not available on Canon R3 (verified day 9
evening).** EXIF tag `BrightnessValue` (0x9203) was speculated as a
free source of camera-metered luminance independent of the exposure
decision. The R3 does not populate this tag — confirmed by running
`exif_ingest.py` over a 6,176-image CR3 shoot from Jan 22-23 2026:
column was blank for every row. No further attempt; this avenue is
closed. The `BrightnessValue` column in `exif.csv` is kept (cheap
to produce, may populate on a future camera) but treated as
permanently empty in the current pipeline.

Therefore: scene luminance signal must come from the EV computed
from Tv & ISO (i.e. what the camera actually used), with curation
discipline (§5.4) doing the work of separating "exposure used"
from "scene luminance." No free metered-EV channel.

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

## 7. Summary in one paragraph

CCAPI is a refinement, not a dependency. The cart's exposure target
advances through sunset/sunrise by integrating a small on-cart rate
table that says how fast brightness is changing at any given EV.
Successful CCAPI fetches every ~30s anchor this integration against
reality; missed fetches leave the cart walking the table on its
own, drifting by at most ~1/3 stop per minute in the steepest
regions — well within post-fix range. The rate table is derived in
Excel from the operator's hand-tuned real-world Tv/ISO/Interval
table (Appendix A) plus a growing aggregate of EXIF data from past
shoots, curated by operator review and tagged by atmospheric
condition. Cart stays dumb; Excel does the brains; every shoot
makes the system smarter; photos are never delayed.

---

## Appendix A — Reference data: hand-built sun table

Source: hand-built reference table from prior shoots, used to derive
the Tv+1.5s cadence rule and ISO ramp behaviour. Captured here as
the canonical reference asset for ongoing comparison against
real-shoot exports.

### Properties

- **Sunset:** 64 rows, t = -80 min (1/5000, ISO 100) → +74 min (20s, ISO 1600)
- **Sunrise:** 63 rows, t = -99 min (20s, ISO 1600) → +1 min (1/5000, ISO 100)
- **Tv steps:** ~1/3 stop spacing, 52 distinct Tv values across both curves
- **ISO ramp:** 100 throughout daylight; 100 ↔ 1600 only when Tv pinned at 20s ceiling
- **Interval column:** matches Tv+1.5s rule (`max(2, ceil(Tv+1.5))`) for 60/64 sunset
  and 61/63 sunrise rows.

### Columns

`SunLabel | Timelabel | Time | T | ISO | Interval`

- `Time` = seconds relative to sun event (negative = before, positive = after)
- `Timelabel` = wall-clock label for that t_rel (sunset@17:46 reference)
- `T` = Tv value (e.g. `1/500`, `0.8`, `20`)
- `ISO` = ISO setting
- `Interval` = photo interval in seconds

### Data

SunLabel	Timelabel	Time	T	ISO	Interval
Sunset	Sunset_16:25	-4800	1/5000	100	2
Sunset	Sunset_16:38	-4020	1/4000	100	2
Sunset	Sunset_16:51	-3240	1/3200	100	2
Sunset	Sunset_17:03	-2520	1/2500	100	2
Sunset	Sunset_17:13	-1920	1/2000	100	2
Sunset	Sunset_17:21	-1440	1/1600	100	2
Sunset	Sunset_17:28	-1020	1/1250	100	2
Sunset	Sunset_17:31	-840	1/1000	100	2
Sunset	Sunset_17:34	-660	1/800	100	2
Sunset	Sunset_17:37	-480	1/640	100	2
Sunset	Sunset_17:40	-300	1/500	100	2
Sunset	Sunset_17:43	-120	1/400	100	2
Sunset	Sunset_17:46	60	1/320	100	2
Sunset	Sunset_17:49	240	1/250	100	2
Sunset	Sunset_17:51	360	1/200	100	2
Sunset	Sunset_17:54	540	1/160	100	2
Sunset	Sunset_17:56	660	1/125	100	2
Sunset	Sunset_17:57	720	1/100	100	2
Sunset	Sunset_17:58	780	1/80	100	2
Sunset	Sunset_18:00	900	1/60	100	2
Sunset	Sunset_18:02	1020	1/50	100	2
Sunset	Sunset_18:03	1080	1/40	100	2
Sunset	Sunset_18:04	1140	1/30	100	2
Sunset	Sunset_18:06	1260	1/25	100	2
Sunset	Sunset_18:08	1380	1/20	100	2
Sunset	Sunset_18:09	1440	1/15	100	2
Sunset	Sunset_18:10	1500	1/13	100	2
Sunset	Sunset_18:11	1560	1/10	100	2
Sunset	Sunset_18:12	1620	1/8	100	2
Sunset	Sunset_18:13	1680	1/6	100	2
Sunset	Sunset_18:15	1800	1/5	100	2
Sunset	Sunset_18:16	1860	1/4	100	2
Sunset	Sunset_18:17	1920	0.3	100	2
Sunset	Sunset_18:18	1980	0.4	100	2
Sunset	Sunset_18:19	2040	0.5	100	2
Sunset	Sunset_18:20	2100	0.6	100	2
Sunset	Sunset_18:21	2160	0.8	100	2
Sunset	Sunset_18:22	2220	1	100	3
Sunset	Sunset_18:23	2280	1.3	100	3
Sunset	Sunset_18:24	2340	1.6	100	4
Sunset	Sunset_18:26	2460	2	100	4
Sunset	Sunset_18:27	2520	2.5	100	5
Sunset	Sunset_18:28	2580	3.2	100	5
Sunset	Sunset_18:29	2640	4	100	5
Sunset	Sunset_18:31	2760	5	100	7
Sunset	Sunset_18:32	2820	6	100	8
Sunset	Sunset_18:34	2940	8	100	10
Sunset	Sunset_18:35	3000	10	100	12
Sunset	Sunset_18:37	3120	13	100	15
Sunset	Sunset_18:38	3180	15	100	17
Sunset	Sunset_18:40	3300	20	100	22
Sunset	Sunset_18:41	3360	20	125	22
Sunset	Sunset_18:42	3420	20	160	22
Sunset	Sunset_18:43	3480	20	200	22
Sunset	Sunset_18:44	3540	20	250	22
Sunset	Sunset_18:45	3600	20	320	22
Sunset	Sunset_18:46	3660	20	400	22
Sunset	Sunset_18:47	3720	20	500	22
Sunset	Sunset_18:49	3840	20	640	22
Sunset	Sunset_18:51	3960	20	800	22
Sunset	Sunset_18:53	4080	20	1000	22
Sunset	Sunset_18:56	4260	20	1250	22
Sunset	Sunset_18:59	4440	20	1600	22
Sunrise	Sunrise_05:06	-5940	20	1600	22
Sunrise	Sunrise_05:09	-5760	20	1250	22
Sunrise	Sunrise_05:12	-5580	20	1000	22
Sunrise	Sunrise_05:14	-5460	20	800	22
Sunrise	Sunrise_05:16	-5340	20	640	22
Sunrise	Sunrise_05:18	-5220	20	500	22
Sunrise	Sunrise_05:19	-5160	20	400	22
Sunrise	Sunrise_05:20	-5100	20	300	22
Sunrise	Sunrise_05:21	-5040	20	250	22
Sunrise	Sunrise_05:22	-4980	20	200	22
Sunrise	Sunrise_05:23	-4920	20	160	22
Sunrise	Sunrise_05:24	-4860	20	125	22
Sunrise	Sunrise_05:25	-4800	20	100	22
Sunrise	Sunrise_05:31	-4440	20	100	22
Sunrise	Sunrise_05:32	-4380	15	100	17
Sunrise	Sunrise_05:33	-4320	13	100	15
Sunrise	Sunrise_05:34	-4260	10	100	12
Sunrise	Sunrise_05:36	-4140	8	100	10
Sunrise	Sunrise_05:38	-4020	6	100	8
Sunrise	Sunrise_05:39	-3960	5	100	7
Sunrise	Sunrise_05:41	-3840	4	100	6
Sunrise	Sunrise_05:42	-3780	3	100	5
Sunrise	Sunrise_05:43	-3720	2.5	100	5
Sunrise	Sunrise_05:45	-3600	2	100	4
Sunrise	Sunrise_05:46	-3540	1.6	100	4
Sunrise	Sunrise_05:47	-3480	1.3	100	4
Sunrise	Sunrise_05:48	-3420	1	100	3
Sunrise	Sunrise_05:50	-3300	0.8	100	3
Sunrise	Sunrise_05:52	-3180	0.6	100	3
Sunrise	Sunrise_05:54	-3060	0.5	100	2
Sunrise	Sunrise_05:55	-3000	0.3	100	2
Sunrise	Sunrise_05:57	-2880	1/4	100	2
Sunrise	Sunrise_05:58	-2820	1/5	100	2
Sunrise	Sunrise_06:00	-2700	1/6	100	2
Sunrise	Sunrise_06:01	-2640	1/8	100	2
Sunrise	Sunrise_06:03	-2520	1/10	100	2
Sunrise	Sunrise_06:04	-2460	1/13	100	2
Sunrise	Sunrise_06:05	-2400	1/15	100	2
Sunrise	Sunrise_06:06	-2340	1/20	100	2
Sunrise	Sunrise_06:07	-2280	1/25	100	2
Sunrise	Sunrise_06:08	-2220	1/30	100	2
Sunrise	Sunrise_06:09	-2160	1/40	100	2
Sunrise	Sunrise_06:10	-2100	1/50	100	2
Sunrise	Sunrise_06:11	-2040	1/60	100	2
Sunrise	Sunrise_06:12	-1980	1/80	100	2
Sunrise	Sunrise_06:14	-1860	1/100	100	2
Sunrise	Sunrise_06:15	-1800	1/125	100	2
Sunrise	Sunrise_06:16	-1740	1/160	100	2
Sunrise	Sunrise_06:18	-1620	1/200	100	2
Sunrise	Sunrise_06:19	-1560	1/250	100	2
Sunrise	Sunrise_06:21	-1440	1/320	100	2
Sunrise	Sunrise_06:23	-1320	1/400	100	2
Sunrise	Sunrise_06:25	-1200	1/500	100	2
Sunrise	Sunrise_06:27	-1080	1/640	100	2
Sunrise	Sunrise_06:29	-960	1/800	100	2
Sunrise	Sunrise_06:32	-780	1/1000	100	2
Sunrise	Sunrise_06:34	-660	1/1250	100	2
Sunrise	Sunrise_06:36	-540	1/1600	100	2
Sunrise	Sunrise_06:38	-420	1/2000	100	2
Sunrise	Sunrise_06:40	-300	1/2500	100	2
Sunrise	Sunrise_06:42	-180	1/3200	100	2
Sunrise	Sunrise_06:44	-60	1/4000	100	2
Sunrise	Sunrise_06:46	60	1/5000	100	2

---

## Appendix B — Session assets cross-reference

- `exposure_feb_decoded.csv` — Feb 2026 shoot with Tv values decoded
  from Excel date-mangling. Retained for cross-session reuse and as
  a worked example of §5.5 method applied.
