# HyperLapse Cart — Plan Flow Review

_What works, what to fix, and where to probe. Written in Plan-sheet language.
The headline: the `.bas` and `.ino` do a lot, and do it well. The problem is
**plan flow** — the operator's authoring surface — not engine correctness._

---

## 1. The framing

The cart executes whatever lands on it; the push modules courier whatever they
read; the astro maths are sound. None of the issues below are "the engine is
wrong." They are all **plan flow**: the operator's intent doesn't always flow
forward, left-to-right and top-to-bottom, out to the cart through the fields
that actually carry it.

Direction of flow is fixed: **recon -> Plan -> push -> cart.** Author from what
the operator wants to express. The push is the courier. The cart is the
destination. Never reason backward from the wire to decide what the Plan should
be — that is how artefacts get left behind (see #3).

---

## 2. Current capability — heaps works

Verified by reading the code this session (`~16k` lines `.bas`, `8,616` lines
`.ino`, soak-v102):

- **Three-button orchestration** on Control: `PrepSession` (today's astro +
  map), `BuildPlan` (render plan + cable for review), `PushToCart` (six pushes
  behind a cable-span hard stop). Each chains the older single-step macros.
- **Full local astro** — sun / moon / GC ephemeris in `Astro.bas`. No internet
  dependency for any astronomical value.
- **Plan -> push -> cart** all live:
  - Cart Plan (LEFT) -> `CartPlanPush` -> `/plan/load` DRIVE/STOP segments.
  - Gimbal Plan (MIDDLE) -> `TrackPlanPush` -> `/settings/trackplan` intervals.
  - Cubics -> `PushTrackPathsToCart` -> `/settings/trackpath`.
  - Chart + Cable SVG (Excel authors the picture, the Giga moves the marker).
- **GP01 (Pan Follow, -30, For 60, WP01-anchored)** — traced push -> parse ->
  execute. Eases to -30 off the cart nose, then goes silent and the Ronin's
  native Pan Follow holds it. Works end to end.
- **GP02 (Move -> sunset, +offset to frame, hold)** — traced push -> execute.
  `EvalAstro` resolves sunset position, the framing offset (Δyaw/Δpitch) is
  added, the sketch eases to the absolute endpoint and holds it for the window.
  The sketch reaches and holds the sunset location.
- **Mode taxonomy is coherent.** Pan Follow = ease once, then release to the
  Ronin's native follow (cart-relative). Move / Track / Track-yaw = position
  continuously (world-absolute), because the Ronin is always physically in Pan
  Follow and silence would let it drift off the mark. Gimbal 0 deg = cart nose
  (RS4 pan is 360 deg continuous; the cable, not the gimbal, is the only yaw
  limit).
- **Exposure + cadence** — `FallbackFormula` ramps day `{Tv 1/5000, ISO 100}`
  to night `{Tv 20s, ISO 1600}`; cadence is derived `ceil(Tv + 1.5)` -> day 2s,
  night 22s. meter -> PUT -> fire cycle, three proven fire transports, exposure
  gate, near-zenith yaw cap, pano overlay.
- **Late start is a non-event.** Real-time anchor self-corrects the astro to
  "now"; WP-event firing slides every downstream GP off the cart's actual
  arrival.
- **Recon -> Plan flow.** Hand-move the gimbal, capture the real-world
  yaw/pitch, use Show astro + Snap var to record framing offsets; these land in
  the RIGHT zone as read-only reference; the operator copy-pastes into the
  MIDDLE as they see fit.
- **Exec UI heading entry is built, not a stub** (the state docs are stale on
  this). Earth-frame GPs show a `hdg` button -> `/track/heading` -> applies the
  drift correction.

---

## 3. The 60 fps frame (context for every motion decision)

Output is a 60 fps timelapse. Cadence is the real-time -> video-frame mapping:

| Phase | Tv | ISO | Cadence | Compression at 60 fps |
|-------|------|------|---------|-----------------------|
| Day   | 1/5000 | 100 | 2s | 120x (1 video-sec = 2 real-min) |
| Night | 20s | 1600 | 22s | 1320x (1 video-sec = 22 real-min) |

So night runs ~11x faster on screen than day (1320 / 120). Examples:
12 h night = ~33 s video; 4 h dusk at ~3 s cadence = ~80 s video; 60-min Slow
night swing = 2.7 s video.

**The punch line:** a get-there move plays back at the night compression
(~1300x). Covering 100-180 deg in 30 real-seconds = under one frame on screen =
a **whip**. Slowing it to look smooth burns minutes of a frame-starved night.
That squeeze is the whole reason #3 matters.

---

## 4. Issues to fix

### #1 Heading — earth-frame Track cubic was missing its baseline (FIXED)

The Track cubic is true earth-frame azimuth (sampled `yi = az`, no heading
subtracted). The live track path subtracted only `track_yaw_correction` (drift,
default 0) — **never the plan's expected heading**. So Track aimed correctly
only at col-H = 0, or via a workaround: col-H = 0 and the operator enters the
full real heading per GP via `hdg`, so the whole heading rides in as "drift."
That is how the +25 deg test passed. A cart at a real heading with col-H = that
heading and no entry would track off by the full heading, silently. Masked by
0-deg testing.

- **Operator model (intended, now wired):** author the expected real-world
  heading per WP in col-H (WP01 100, WP02 -60, ...), from recon. Execution
  relies on it. The operator MAY trim drift with `hdg` during the shoot, but is
  not required to — if not, the cart falls back on the plan's expected heading.
- **Fix (executed in `trackPlanTick`):**
  `gimbal = true_az + offY - exp_heading(baseline) - track_yaw_correction(drift)`.
  The plan's expected heading (col-H, delivered as the `eh` token per Track GP)
  is subtracted as the baseline, so the cart aims from the plan with no operator
  action; the `hdg` correction (`real - expected = drift`) is an optional trim.
  `exp_heading` NAN -> 0 (cart-at-0 fallback), so existing col-H = 0 plans are
  unchanged. Backward compatible.
- **Requires (plan/push side, to make the baseline real):** col-H populated per
  WP; every Track GP WP-anchored so the `eh` token is delivered. A TIME/ASTRO-
  anchored Track GP carries no `eh` -> baseline 0 -> tracks from 0. Confirm
  `TrackPlanPush` delivers `eh` for all intended Track GPs.
- **Note — `dataCartHeading` is a SEPARATE concern.** It is NOT in the Track
  path. It is still used by the Move-endpoint bake (`EvalAstro`, cart-frame
  `az - dataCartHeading`). So the workbook holds two frames: Track = earth-frame
  (true az, now re-based on the cart by col-H at runtime), Move = cart-frame
  (heading baked in via `dataCartHeading`). The Move path's heading handling is
  its own item and ties to #2 (Move is not drift-correctable).
- **Verify:** the SIGN is geometry-derived, flagged for confirmation in the
  daylight Sun Track run. The baseline uses the same CW+ subtraction convention
  as the existing drift term.

### #2 Drift-correction coverage gap

- **Operator sees:** "enter a real compass heading during the shoot to fix
  drift" (the `hdg` button).
- **Actually:** the button + correction appear only for **Track / Track-yaw**
  GPs (`earth = GTM_FULL || GTM_YAW`). Move, Pan Follow, Lock get neither.
- **Consequence:** a Move -> sunset aims at a real-world azimuth but cannot be
  drift-corrected. If the cart drifts during the hold, the framing drifts and
  there is no operator fix on that node.
- **Fix direction:** widen "earth-frame" to cover real-world-aimed Moves, or
  require real-world aims to be Track GPs. Decide later.

### #3 Pan Speed / Pan Time — the rate model is not built (BUILD FIRST)

- **Operator sees:** picks Pan Speed (Slow/Mid/Fast) to set the get-there speed;
  expects Pan Time to show how long it takes.
- **Actually:** the get-there duration on the wire is `acquire_ms = Ease-frames
  x cadence`. Pan Speed is **read only to validate it is non-blank** (value
  never used). Pan Time is a **display-only formula**, pushed nowhere, and it
  does not match what the cart actually does. Two overlapping "how fast"
  controls: Ease secretly sets the duration; Pan Speed was meant to.
- **GP02 illustrates it:** Pan Speed = Mid, Ease = blank -> `acquire = 0` ->
  the sketch falls back to its 3 s default -> the gimbal would whip to the
  sunset endpoint in ~3 s instead of an eased Mid-rate move.
- **The rate model (operator intent):** Pan Speed is an average rate
  (Slow 3 / Mid 6 / Fast 12 deg/min). `rate x swing` sets the duration; a fixed
  smoothstep S-curve shapes position within it (ease-in -> mid -> ease-out).
  Peak deg/step = `1.5 x rate x cadence`.
- **Night vs dusk:** at night (22 s cadence) only **Slow** stays under the
  cable-tangle cap; Mid/Fast would whip or be cap-stretched. In practice night
  = Slow only. At dusk (~2-3 s cadence) all bands are safe and Pan Speed is a
  real creative lever.
- **Build (forward, authored-side):**
  1. Get-there duration comes from **Pan Speed rate** (`swing / rate`), pushed,
     replacing Ease-frames as the source.
  2. **Pan Time = interactive worksheet formula** — recomputes live as the
     operator edits. Approximate is correct: one-shot astro endpoint at the
     node's Fires-at time, no moving-target cubic chase (sidereal drift over a
     get-there is a few degrees, negligible for an indication). Shown as a
     **fraction of For**, and **validated `Pan Time < For`** (a get-there that
     does not fit the window never settles -> flag, like the cable-span stop).
  3. **Rate colour** (green / amber / red from `1.5 x rate x cadence` vs cap),
     surfaced in the **plan-gimbal view, the cable-tangle chart, and the
     execution chart**. One computed quantity drives both the Pan Time fraction
     and the colour.
- **Pan Time's job:** indicate to the operator that some of the node window is
  spent getting there, so they decide OK / not-OK. It is an indication, not a
  cubic execution.

---

## 5. Parked actions (non-priority)

- **Right-zone reference (`GimbalLogPuller`)** — its documented column mapping
  (AD..AM, no Mode) lags the live RIGHT section (AE..AO, Mode inserted). It is
  read-only operator reference, does not reach the cart, so low stakes — but a
  misaligned paste source. Verify the actual code constants, realign. Tidy-up,
  not blocking.
- **Sun-current / sun-now recon option** — Show astro drives only to fixed
  events (sunrise/sunset/moon/GC keyframes). There is no "sun now" drive/snap
  for recording an offset against the live sun. Add if current-sun framing recon
  is wanted.

---

## 6. Scratch and sniff (measure before / while building)

- **Cubic push** (`PushTrackPathsToCart`) — the executor that consumes the cubic
  is read and trusted; the generator/fit has not been traced end-to-end this
  session. Close it before calling Track-sun fully end-to-end.
- **Cap is cable-tangle** — settled, easy to adjust, parked separately from the
  get-there/rate problem.
- **Pan Time inputs** — needs the swing (GP-start pose -> this node's endpoint)
  and the cadence at the Fires-at time. Both already computable (the dial
  resolver has poses; `CadenceSecAt` has cadence). Confirm the dial resolver
  poses are usable from the formula side.
- **Wire vs display split for the duration/cap** — decide at build whether Excel
  bakes the final duration and pushes it, or pushes rate + cap and the executor
  computes. That decides what crosses the wire.

---

## 7. How we work this project

- The `.ino` (8,616 lines) and the `.bas` modules describe current practice.
  Read them. Do not ask questions answerable by reading.
- Use Plan-sheet vocabulary — Pan Speed, Pan Time, Fires at, For, Anchor type,
  Move, Track, Pan Follow, Δyaw. Not invented terms.
- Simple and logical.
- Do not ask about obvious, 99%-certain decisions.
- Forward flow only: operator intent -> Plan -> push -> cart. Do not reason
  backward from the wire to invent Plan logic. Do not invent.
- Stop to discuss the operator's mistakes / issues, and genuine forks. Not for
  trivia.
