# HyperLapse Cart — Gimbal Visualisation & Plan Architecture

**Created:** 14 May 2026 (Session C day 8)
**Status:** Design complete, no code yet

This document covers the end-to-end design for authoring, visualising,
and executing the gimbal Plan. Reference document for the workfronts
that follow.

Read alongside:
- `PREFERENCES.md` — working agreement
- `PROJECT_STATE.md` — overall state
- `WORKFRONTS.md` — concrete tasks (#13–#15 expand here)

---

## 1. End-to-end workflow

```
RECON (in field)
  │
  ├── Cart UI       → operator drives cart, btn19 captures cart waypoints
  │                   → Cart Log fills (event-driven, rear_steps included)
  │
  └── Gimbal UI     → separate page on same Arduino (different URL)
                      operator selects cart waypoint number,
                      sets row type / duration / params,
                      btn captures gimbal yaw+pitch if type=manual
                      → Gimbal Log fills as a draft Plan

BACK AT VAN — EXCEL AUTHORING
  │
  ├── Pull Cart Log via /cartlog
  ├── Pull Gimbal Log via /gimballog (now a Plan draft)
  ├── Operator cuts/pastes/reorders rows into final Plan table (10–15 rows)
  ├── Excel computes astro endpoints for "track" rows
  ├── Excel builds spline waypoint sequence (manual + astro endpoints + holds)
  ├── Excel runs Catmull-Rom smoothing across the sequence
  ├── Excel visualises Plan as XY chart (yaw × pitch), colour-coded for velocity
  ├── Operator inspects, iterates, edits, re-visualises
  │
  └── COMMIT → bake to execution stream → POST to cart /plan/load

CART EXECUTION
  │
  ├── /plan/start begins clock-driven dispatcher
  ├── For each segment at its scheduled t: evaluate formula, quantise,
  │   command setPosControl
  └── Operator supervises; emergency stop available
```

**Key principle:** astro is an input to authoring, NOT a runtime master.
The cart executes the trajectory the operator committed; it is not
slaved to real-time astronomical computation. Astro drift between
Plan time and shoot time is acceptable artistic latitude.

---

## 2. Plan vs Execution separation (sacred)

| Concept    | Where it lives | What it contains                        |
|------------|----------------|-----------------------------------------|
| **Plan**   | Excel          | Smooth, continuous, ideal yaw(t),       |
|            |                | pitch(t) trajectory. Author-friendly    |
|            |                | row table. Catmull-Rom curves. No       |
|            |                | quantisation, no hardware limits.       |
| **Stream** | POSTed to cart | Pre-computed parameter blocks per       |
|            |                | segment. Cubic coefficients, hold       |
|            |                | positions, etc. Dumb-to-execute.        |

The chart visualises the **Plan** (smooth/ideal).
The warnings reflect **Execution stress** (steps per gap).
Two views of the same data.

---

## 3. Gimbal UI on cart (new — to be implemented)

Served at a different URL from the existing cart UI (suggestion: `/gimbal`).
Shares Arduino backend, separate page.

### Per-row controls

| Field         | Type       | Notes                                       |
|---------------|------------|---------------------------------------------|
| Way #         | Dropdown   | 1..N from cart log. Simple numeric list.    |
| Type          | Dropdown   | pan-follow / hold / track sun /             |
|               |            | track milky way / manual                    |
| Duration      | Seconds    | This row's length. Cumulative time falls    |
|               |            | out by summing.                             |
| Extra 1       | Reserved   | TBD                                         |
| Extra 2       | Reserved   | TBD                                         |
| Capture btn   | Button     | Only active when type=manual. Grabs         |
|               |            | current gimbal yaw+pitch into the row.      |

### Manual gimbal pointing

When type=manual the operator needs to point the gimbal before capturing.
The Gimbal UI must include yaw/pitch nudge controls:
- Yaw: −10° / −1° / −0.1° / +0.1° / +1° / +10°
- Pitch: same set
- Status bar showing current yaw/pitch readout
- Optional: shutter trigger to preview framing on R3

### Existing cart UI button mapping (for reference)

Current layout in `DJI_Ronin_UnoR4_v2.ino`:

| Row     | Buttons                              | Endpoints  |
|---------|--------------------------------------|------------|
| Top     | Home / Photo                         | /home /shutter |
| Steering | L5 / L1 / CTR / R1 / R5             | btn1–5     |
| Speed   | −10 / −1 / DEC / +1 / +10            | btn6–10    |
| Motors  | STOP / DEAD / -- / DE-E / ENRG       | btn11–15   |
| Camera  | PAUSE / [interval] / BKUP            | btn16, /interval, btn18 |
| Log     | ● Cart / ● Gimbal / --               | btn19, btn20, btn21 |

btn20 ("● Gimbal") already captures gimbal waypoints into the log.
For the new workflow we keep btn20 for raw-waypoint logging during
cart-UI mode, and add a parallel Gimbal UI for structured Plan-row entry.

---

## 4. Cart-side execution model (sacred — keep dumb)

Cart receives a **stream of parameterised formula segments** from Excel.
One segment per Plan row. Each segment is a small fixed-size parameter
block. Cart dispatches on segment type, evaluates `f(t, params)` each
tick, quantises to 0.1°, commands gimbal.

### Segment types

```c
enum SegType { HOLD, LINEAR, CUBIC, PANFOLLOW };

struct Segment {
    uint8_t type;
    uint32_t t_start_ms;   // ms from /plan/start
    uint32_t t_end_ms;
    union {
        struct { int16_t yaw_dec; int16_t pitch_dec; } hold;
        struct { int16_t y0,p0,y1,p1; } linear;
        struct { float ay[4]; float ap[4]; } cubic; // Catmull-Rom as standard cubic
        struct { int16_t yaw_cart_frame; int16_t pitch; } panfollow;
    };
};
```

All complex maths (astro positions, Catmull-Rom tangents, ease curves,
transition shapes) are pre-computed in Excel/Python and reduced to
these parameter blocks. **Cart does NOT compute:**

- Astro formulas (no port of Astro.bas to C)
- Catmull-Rom tangents or spline math beyond `at^3 + bt^2 + ct + d`
- Heading integration during drives (Plan is in cart-frame at authoring)
- Transition shapes or easing curves (baked into cubic coefficients)
- Blur thresholds or warning logic

### Execution loop (per tick, aligned to photo gap)

```
target_deg = eval_segment(current_seg, now - seg_t_start)
target_dec = round(target_deg * 10)              // quantise
delta_dec  = target_dec - last_commanded_dec
if delta_dec != 0:
    setPosControl(target_dec, time_ms = gap_ms - safety_margin)
    last_commanded_dec = target_dec
```

The accumulator pattern: track `target_dec - last_commanded_dec` continuously.
Most ticks send 1 step (0.1°). Some send 0 (target hasn't crossed boundary).
Some send 2-8 (transit / fast pan). "0.2° catch-up" after a missed tick
falls out naturally.

### What this implies for workfronts

The day-7 workfronts list shrinks dramatically:

- ~~#6 Heading anchor endpoint~~ — not needed at runtime
- ~~#7 Cart-θ integration during drives~~ — not needed (no astro slave)
- ~~#8 Port astro maths to C~~ — Excel pre-bakes
- ~~#10 setSpeedControl for slow continuous moves~~ — pre-quantised setPosControl fine
- ~~Catmull-Rom on cart~~ — Excel pre-samples as cubic coefficients

What remains on cart:
- #4 rear_steps in CartLogEntry
- #5 Plan endpoints `/plan/load`, `/plan/start`, `/plan/stop`, `/plan/status`
- #9 ±450° cumulative yaw constants
- New: segment dispatcher + cubic evaluator (~50 lines C)
- New: Gimbal UI page (separate URL)

---

## 5. SDK constraints (cross-reference)

From DJI R SDK v2.2 (the protocol Gimbal.bas uses):

- **`setPosControl`:** yaw/roll/pitch in **0.1° units**, range ±1800 (±180° native — we extend to ±450° cumulative)
- **Minimum execution time: 100ms**
- Protocol field is `int16_t` — host-side rounding required, no sub-resolution accumulation in SDK

`setSpeedControl` exists for continuous tracking but with our pre-baked
stream approach we don't need it — `setPosControl` with eased time_ms
covers all cases.

---

## 6. Real-world tracking maths (Adelaide, lat −34.93°)

All numbers computed for the Milky Way regime: **Tv=20s, interval=22s,
gap=2s, fixed** (from production exposure table, only happens at night).

### Milky Way (GC at RA=266.4167°, Dec=−29.0078°)

GC at transit from Adelaide passes near zenith (peak altitude ~84°).
Three regimes within a single night:

| Regime         | Per-22s motion       | During 2s gap   | Steps per gap |
|----------------|----------------------|-----------------|---------------|
| GC at transit  | 0.35 – 0.78° (avg 0.60°) | 0.18 – 0.39°/s | **3.5 – 7.8** |
| GC rising      | ~0.09°               | ~0.05°/s        | ~1            |
| GC setting     | ~0.085°              | ~0.04°/s        | ~1            |

Worst case 7.8 steps in 2s → **257 ms per step**, well above 100ms SDK floor.

### Sun (year-round, Adelaide)

| Regime              | Per-22s motion | During 2s gap | Steps per gap |
|---------------------|----------------|---------------|---------------|
| Winter, any time    | ~0.09°         | ~0.045°/s     | ~1            |
| Summer mid-afternoon| ~0.09°         | ~0.046°/s     | ~1            |
| Summer solar noon   | **0.32 – 0.41°** | **0.20°/s**  | **~4**        |
| Sunset/sunrise      | ~0.085°        | ~0.042°/s     | ~1            |

Sun tracking is trivial everywhere except summer solar noon (sun near
zenith at 78°). Even that worst case is 490 ms/step — 5× SDK headroom.

### Star trail during 20s exposure (14mm lens, R3 6000px wide)

Sky moves 0.084° in 20s at sidereal rate. With perfect tracking: zero
trail. Without tracking: **4.8 pixels of trail**. With one missed
gimbal step (0.1° error): ~6 pixels worst case. Tolerable for hyperlapse
output where individual frames are not pixel-peeped.

---

## 7. Velocity bands (chart colour coding)

The chart shows the **Plan trajectory** (smooth/ideal). Colour conveys
velocity in **real-time °/sec** along the path. Operator already knows
the activity from the Plan row types; colour is a sanity check.

| Colour       | Range                    | What it represents                       |
|--------------|--------------------------|------------------------------------------|
| **Blue**     | row-type marker          | Ease-in / ease-out transition segments   |
| **Green**    | < 0.05°/sec              | Astro tracking, slow drift               |
| **Amber**    | 0.05 – 0.3°/sec          | Deliberate manual pan (e.g. 90°/30min)   |
| **Red**      | > 0.3°/sec               | Aggressive pan (e.g. 90°/5min)           |

Blue is a **row-type label**, not a velocity band — marks any segment
whose Plan-row type is "ease into/out of hold", regardless of speed.
Slow eases and fast eases both show blue, distinguishing transitions
visually from astro (green) and pans (amber/red).

### Calibration reference points

- MW rise/set: 0.004°/sec → **green** (barely visible drift in video)
- MW transit worst: 0.035°/sec → **green**, near amber boundary
- Sun summer noon: 0.019°/sec → **green**
- 90°/30min manual pan: 0.05°/sec → **green/amber boundary**
- 90°/5min manual pan: 0.30°/sec → **amber/red boundary**

### Video-speedup translation (60fps output, 22s real → 1 frame = 1320×)

| Real °/sec | °/frame at 60fps | Perceived in video      |
|------------|------------------|-------------------------|
| 0.004      | 0.09°/frame      | Imperceptible drift     |
| 0.035      | 0.77°/frame      | Smooth, slow            |
| 0.05       | 1.1°/frame       | Smooth, perceptible     |
| 0.30       | 6.6°/frame       | Punchy pan              |
| 1.0        | 22°/frame        | Jerky, motion-blurred   |

### Execution-feasibility warning (separate from cinematic bands above)

A second dimension: can the cart actually execute it?

```
steps_needed  = combined_deg_per_gap / 0.1
time_required = steps_needed × 100 ms
utilisation   = time_required / gap_ms

< 0.25  green  (easy)
0.25–0.50  amber  (active tracking)
0.50–0.80  red    (near hardware limit)
≥ 0.80  HARD VIOLATION (Plan exceeds hardware)
```

For the production envelope (gap=2s always at night), GC transit
worst case sits at utilisation = 7.8 × 100 / 2000 = 0.39 → **amber**.
Sun summer noon = 4 × 100 / 2000 = 0.20 → **green**.

The chart shows cinematic velocity as colour. The feasibility warning
fires as a separate visual indicator (red border on offending segments,
text warning in the row).

---

## 8. Catmull-Rom smoothing

Used for all Plan segments where smooth motion is required:

- Manual-pan sequences (operator-logged waypoints)
- Track-row endpoints (computed astro positions become waypoints)
- Hold-row stationary points (repeated waypoints to enforce zero motion)
- Transitions between row types (track → hold, hold → manual, etc.)

### Why Catmull-Rom

- Interpolates (passes through every waypoint, not approximates)
- Auto-tangents from neighbouring points — operator places dots only
- Bezier family — cheap polynomial eval on cart (`at³+bt²+ct+d`)
- Excel-side smoothing: ~30 lines of VBA / Python
- Cart-side: 0 lines — Excel pre-bakes coefficients

### Transition handling — operator drives, defaults available

At the boundary between a long track (constant slow motion) and a long
hold (zero motion), naive Catmull-Rom overshoots. Two approaches:

1. **Operator authors explicit transition rows.** "MW track 3hr →
   manual ease-out 60s → hold". Excel auto-inserts phantom waypoints
   to enforce zero velocity at the ease end. Reserved buttons in the
   gimbal UI offer ease-style presets.

2. **Auto-smooth in Excel.** Detect type transitions, synthesise
   phantom waypoints automatically. Friendlier but harder to author
   intent.

**Decision:** approach 1 — operator drives transitions explicitly with
sensible defaults available. The operator is a video editor and
understands end conditions; we don't try to be cleverer than them.

### Cart-still-moving vs cart-parked

- **Cart moving:** transition duration falls out of cart Plan timing —
  next cart waypoint has known arrival time, gimbal eases over that
  interval.
- **Cart parked overnight:** gimbal Plan row carries its own duration
  explicitly — "ease to sunrise hold over 15 min, then hold for 3 hr".

Same Catmull-Rom evaluator handles both. Difference is only in where
the timing data comes from.

### Audience-frame guide for ease durations

At 1320× speedup, ease durations are governed by **video frames**, not
real seconds:

| Audience perception | Frames | Real-time     |
|---------------------|--------|---------------|
| Hard cut            | 0      | 0 sec         |
| Just-perceptible    | ~3     | 66 sec        |
| Comfortable         | ~10    | 220 sec (3.7 min) |
| Cinematic           | ~30    | 660 sec (11 min) |

Excel should display the audience-frame count when the operator selects
an ease style. "Ease 60s = 2.7 frames, abrupt halt" or "Ease 5min =
13.6 frames, comfortable" — informed choice.

---

## 9. Cart Plan / Gimbal Plan coupling

Cart Plan and Gimbal Plan are conceptually parallel but technically
interleaved. The execution stream POSTed to cart contains both types
of segments on a single timeline.

- Cart segments: speed/steering changes, stops, durations
- Gimbal segments: pose changes, tracks, holds, transitions
- Shared clock — both reference `t_ms` from /plan/start

Cart-side row-walker dispatches each segment to its destination
(steering subsystem, gimbal subsystem) at its scheduled t.

Timing inheritance: if a gimbal-Plan row's duration is unspecified, it
inherits from the surrounding cart-Plan rows (e.g. "ease until next
cart waypoint arrives").

---

## 10. Open design questions

These were raised today and deferred:

1. **Chart sampling strategy** — fixed Δt, per-segment, or adaptive
   by curvature? Probably per-segment (each row chooses based on type).
2. **Velocity → colour gradient curve** — linear, log, or banded?
   Banded matches the green/amber/red proposal cleanly.
3. **Exposure-table coupling** — Plan-time → Tv lookup → Tv-dependent
   blur threshold. Implementation detail of the warning logic.
4. **Two reserved per-row inputs** in the gimbal UI — TBD.
5. **Heading anchor mechanics** — defer until Plan authoring is
   working; one-shot anchor at shoot start may be enough.
6. **Re-bake on shoot delay** — if shoot starts later than authored,
   astro tracks shift. Mitigation: re-author or re-bake. Manual for now.
7. **Stream size on Uno R4** — ~50 segments per night × ~32 bytes each
   = 1.6 KB, fits comfortably in SRAM. Larger plans → flash or chunked.

---

## 11. Today's findings (one-line summary each)

- Plan vs Execution separation is sacred — chart shows Plan, cart runs Execution
- Astro is authoring input, not runtime master — cart not slaved to sky
- Cart UI already has btn20 gimbal capture; new Gimbal UI page parallels it
- Gimbal UI is field-side Plan-row editor (way#/type/duration/params)
- Catmull-Rom smooths everything — manual, astro endpoints, transitions
- Operator authors transitions explicitly with default presets (reserved buttons)
- 1320× video speedup makes ease duration a video-frame budget, not seconds
- Production gap = 2s always at night; GC transit needs 7.8 steps per gap, 257ms each
- Sun tracking trivial except summer noon (4 steps per gap, 490 ms each)
- Velocity bands: blue=ease, green<0.05°/s, amber 0.05–0.3, red>0.3
- Cart receives pre-baked cubic coefficients per segment; ~50 lines C total
- SDK quantises to 0.1°/100ms; host-side accumulator handles rounding correctly
