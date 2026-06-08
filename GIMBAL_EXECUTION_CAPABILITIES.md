# HyperLapse Cart — Gimbal Execution Capabilities

Reference for the gimbal-plan execution system: the GP (gimbal point)
types, how each is authored in the Plan sheet and executed on the cart,
their status, and the design decisions behind them. Captured Day 24
(part B). Companion to the chronological WORKFRONTS notes — this is the
"what it does" reference, not the decision log.

---

## The model: Excel plans, the cart executes

Excel (HyperLapse.xlsm) is the planning brain. The cart (Arduino Giga R1)
is a dumb executor — Excel supplies every value at plan-upload time; the
cart is **not** driven live during a shoot. The DJI Ronin sits permanently
in **Pan Follow** mode (operator-set on the gimbal). SDK position commands
from the cart override that follow while they are being issued; when the
cart stops commanding, the gimbal reverts to its native Pan Follow.

A consequence that shapes several behaviours below: **silence = the Ronin
follows.** So a GP that must hold a fixed pose has to keep commanding it;
a GP that wants the gimbal to follow simply goes quiet.

Current limitation: **Ry = Cy holds** — the cart applies no gimbal-yaw
correction for its own heading yet (that is the BNO-blocked item; see
Status). Everything below operates without a live cart-heading source
except where noted.

---

## GP types (Plan col S "Action")

Authored values: `Pan Follow, Lock, Move, Track, Track-yaw, END`.
Cart interval modes are single chars: `F` (full track), `Y` (track-yaw),
`P` (pan follow), `M` (move).

### Move  — cart mode `M`
One-shot eased slew from the gimbal's current pose to an **absolute
endpoint**, then **hold** the endpoint.

- Endpoint: a **marker** (Ry + Δyaw, Rp + Δpitch from cols V/W/X/Y) or an
  **astro** point (the object's position at the GP fire time, via
  `EvalAstro`, plus Δyaw/Δpitch). Move-to-astro means "slew to where the
  sun/moon/GC will be at this time, plus my framing offset."
- Motion: a single **ease-in/ease-out S-curve** (smoothstep) — no cubic.
  Duration = ease band (col Z) × cadence; default 3 s if no ease set.
- After the slew it **holds** the endpoint every tick (it must — silence
  would let the Ronin follow the gimbal off the mark).
- Status: **hardware-proven** for the eased slew + cart-relative hold
  (the normal static-base case). Holding world-fixed against a *moving*
  cart base needs the BNO (same dependency as Lock).

### Track  — cart mode `F`
Yaw **and** pitch follow a moving astro object continuously, via a cubic
path the object traces across the sky.

- Object: col T target (`sun`/`moon`/`gc`). Excel fits a cubic over the
  object's window and pushes it; the cart evaluates it each tick.
- Framing offset: Δyaw/Δpitch (cols X/Y) added to the object's position.
- Entry: **Phase-A ease** (see Shared behaviours) — smoothly eases onto
  the moving curve, no snap.
- Status: **hardware-proven** (sun). Moon added this session; GC works.

### Track-yaw  — cart mode `Y`
Yaw follows the astro object; **pitch is held fixed**.

- Yaw = object yaw + Δyaw (col X). Pitch = **Rp, the ref pitch in col W**
  (a fixed elevation, not a delta). Confirmed correct Day 24 pt B.
- Use: lock the camera at a chosen elevation and let it pan with the
  object — e.g. follow an object's azimuth at a fixed tilt.
- Status: built; shares the proven Track cubic path.

### Pan Follow  — cart mode `P`
Eases **once** to a goto-yaw, then goes **silent** so the Ronin's own Pan
Follow takes over from that offset.

- Goto-yaw = Δyaw (col X); pitch = Δpitch (col Y). Eased entry (same
  smoothstep as Phase-A), duration from acquire/ease or 3 s default.
- After the ease the cart commands nothing → the Ronin follows the cart's
  heading, holding that pan offset, for the rest of the window.
- BNO-independent (no cart-heading read needed).
- Status: **hardware-proven** — eased to offset, then tracked a hand
  rotation of the cart in native follow.

### Lock
Hold a world-fixed bearing.

- Parked-cart case is cheap (hold the pose). The **moving-cart** case
  needs the gimbal to counter-rotate against the cart's heading change,
  which requires a live heading source (BNO).
- Status: **parked** — best enabled by the BNO fix (moving case).

### END
Bookend GP. Holds the previous pose; its purpose is to bound the plan and
enable end-time calculation for the preceding GP's interval. No new motion.

---

## Astro objects (Plan col T "Target")

`sun`, `moon`, `gc` — all three are full astro objects with position maths
in Astro.bas (az/alt → gimbal yaw/pitch, above-horizon flags, rise/set/
transit root-finders). Blank target = a marker Move/Lock using Ry/Rp.

- **gc = the Milky Way galactic centre.** Renamed from "mw" this session;
  the cart wire token and all object-identity code are now `gc`. (A
  separate "Movewatch" feature in the firmware also uses the letters
  `MW` — unrelated, deliberately untouched.)
- **moon** became a first-class object this session (#55 closed): its
  cubic is fitted over the **dark window** (astroDusk → darkEnd), the
  same window as GC. No horizon gating — if the moon is below the horizon
  for part of the window the cubic simply asks for a steep-down pitch the
  gimbal's pitch limit clamps, and preview shows it. The operator owns
  plan shootability.

Track windows: sun = sunset → sunrise; GC and moon = the dark window
(astroDusk → darkEnd).

---

## Shared behaviours

### Phase-A ease (acquire)
On entering a Track interval, the cart captures its actual current pose
and **smoothsteps onto the live (moving) cubic value** over `acquire_ms`,
re-reading the target each tick so it converges velocity-matched onto the
curve — no cruise, no snap. `acquire_ms` = ease frames (col Z band →
Settings `dataEase*`: Just-perceptible 3 / Comfortable 10 / Cinematic 30)
× the photo cadence at that GP's fire time (from the exposure model,
`FormulaTv` → `CalcInterval`). No event times set → acquire 0 → legacy
snap (with a warning, never a fabricated value).
Status: **hardware-proven.**

### Yaw-rate cap near zenith — DECIDED, not yet built
Problem: an astro object's **azimuth** swings fastest at transit, forcing
a fast gimbal pan ("whip"). From this latitude the **GC transits near
overhead (~84° alt)**, so GC hits this every night near culmination (sun
and moon never get that high here). The fast yaw is driven by azimuth
rate, **not** by the gimbal's pitch — so clamping pitch would not fix it.

Decision: replace the current blunt **freeze-yaw** (the cubic fit zeroes
yaw motion for a whole segment when pitch > 80°, which can freeze for
hours) with a **per-tick yaw-rate cap** in the cart executor. The gimbal
pans at up to a comfortable max rate; when the object outruns it, the
gimbal keeps panning at the cap, lags, and re-converges as the azimuth
rate drops — smooth throughout. Trade accepted: brief framing drift
through the capped window in exchange for smooth motion. To build: the
rate value (deg/s, tuned on real GC footage) and confirm it applies
uniformly to all objects (likely yes — a comfortable-pan cap is
object-independent; sun/moon just never reach it here).

### Hold vs. silent
Because the Ronin is always in Pan Follow: GPs that hold a pose (Move,
Lock) must keep commanding it every tick; GPs that want the follow (Pan
Follow) go silent. This is why Move "holds" rather than easing then
releasing like Pan Follow does.

---

## The push pipeline (Excel → cart)

A shoot's gimbal side is assembled from several pushes (separate from the
cart/dolly motion push, `CartPlanPush`):

- **Cubic track paths** — `AstroPush.PushTrackPathsToCart` ("Push Track
  Paths to Cart"). Fits and pushes the sun / GC / moon cubics. This is
  what actually tracks.
- **Interval table** — `TrackPlanPush.PushTrackPlanToCart`. Which object /
  mode / when (ts–te windows), plus `acquire_ms` (Phase-A ease) and the
  Δyaw/Δpitch offsets; also emits Pan Follow and Move intervals.
- **Preview poses** — `PlanPush.PushPreviewPlanToCart`. One pose per GP
  for on-cart preview (PREV/NEXT by GP). A **Track** GP emits two: a
  **GP-start** pose (object at ts) and a **continuation** pose (object at
  te) so the full sweep is visible for cable management. Continuations are
  tagged so GP-level stepping skips them.
- **Discrete keypoints** — `AstroPush.PushAstroToCart` ("Push Astro to
  Cart"). Sun rise/set + GC rise/mid/end positions, consumed by
  `/gimbal/showastrooffset`. This is a **recon / setup helper** (swing the
  gimbal to where an astro event will be, to check framing and
  obstructions during a scout) — not the tracking path.
- **Exposure model** — `Formula.PushFormulaToCart`. Tv/ISO crossover
  table; doubles as the WiFi-loss fallback the cart can run table-driven.

### Recon → plan capture loop
The recon UI is the intended authoring path for astro GPs. During a
scout: request an astro keyframe (gimbal swings there), nudge a framing
offset, record it as a GP. It lands in the cart's gimbal log with the
astro type + keyframe + offset; `GimbalLogPuller` / `AddPlanRowFromLog`
pull it into the Plan sheet as a **Move** row with `target=gc`/sun/moon
and the offset as Δyaw/Δpitch. So col T's target value is normally
*written by the pull*, not typed — the dropdown is a manual-edit aid.

---

## Authoring column map (Plan sheet, gimbal middle zone)

| Col | Field | Notes |
|-----|-------|-------|
| M | Step | GP label (GP01…) |
| N | Anchor type | WP / TIME / ASTRO |
| O | Anchor ref | event name when ASTRO (sunset, gcrise…) |
| P | Offset | timing offset |
| Q | Fires-at | **computed** (no dropdown) |
| R | Total dur | |
| S | Action | Pan Follow / Lock / Move / Track / Track-yaw / END |
| T | Target | sun / moon / gc, or blank for a marker |
| U | Rate | |
| V | Ry | ref yaw |
| W | Rp | ref pitch (Track-yaw's fixed pitch) |
| X | Δyaw | framing yaw offset / goto-yaw |
| Y | Δpitch | framing pitch offset |
| Z | Ease | band → Phase-A ease frames |
| AA | Move-t | (distance-aware move duration — not yet built) |
| AB | Note | |

---

## Status summary

Hardware-proven: Phase-A ease (Track entry), Pan Follow, Move (eased slew
+ cart-relative hold), sun Track. Built/verified: moon as full object,
GC rename, the interval / preview / acquire pushers (dry-run verified).

Decided, not yet built: the yaw-rate cap (replaces freeze-yaw);
distance-aware Move-t (col AA).

Blocked on the BNO motor-power electrical fix (a hardware/wiring issue,
not code): folding cart-heading correction into earth-frame cubics (3b);
Lock's moving-cart case; Move's world-fixed hold against a moving base.
All three share one mechanism — the gimbal subtracting the cart's measured
heading — and unblock together once the BNO streams reliably under motor
power.

---

## Cart endpoint cheat-sheet (raw-URL bench tests; cart = 192.168.1.97)

- `/settings/trackpath?obj=sun|moon|gc&seg=N&ts=&te=&ay0..3=&ap0..3=[&rt0=]`
  — push a cubic PATH segment (obj is the full word).
- `/settings/trackplan?idx=N&ts=&te=&obj=S|M|W|N&mode=F|Y|P|M&offy=&offp=[&acquire=]`
  — push one interval (obj single char; mode: F full, Y yaw, P pan-follow,
  M move).
- `/settings/previewplan?idx=N&yaw=&pitch=&label=[&start=1|0]`
  — one preview pose (start=0 marks a continuation).
- `/track/start`  `/track/stop`
- `/gimbal/showastrooffset?type=sun|moon|gc&kf=rise|mid|end` — recon helper.
- `/debug/imu` (+ `/capture` `/savecal`) — BNO state.
