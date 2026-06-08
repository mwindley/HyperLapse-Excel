# WORKFRONTS — PANO: manual interrupt + Excel-configured geometry (design)

Status: **DESIGN AGREED, not yet built.** Day 24 (part B) discussion.
No BNO dependency. Splits into two independent builds (see end).

---

## What exists today (standalone pano)

A 4-photo horizontal panorama state machine on the cart, centred on the
gimbal's current pose at trigger:
- `pano_offsets[PANO_N_PHOTOS] = {-78,-26,26,78}` (HARDCODED, ~156° span,
  single row, pitch held at centre).
- States: IDLE -> SLEW -> SETTLE (800ms) -> PHOTO -> WAIT, per photo, then
  RESUME (slews back to the centre pose) -> IDLE.
- Triggered by `/gimbal/pano?tv=&speed=` (+ a button). Params: per-photo
  exposure tv_ms, slew speed dps.
- Returns to the pose it started from.

**The catch:** it was built for a STATIC pose. `panoTick()` and
`trackPlanTick()` both run every loop and neither yields — so firing a
pano during an active Track interval would make the two executors FIGHT
(both command the gimbal each tick). And `PANO_RESUME` returns to the
frozen snapshot pose and goes IDLE; it does not re-engage tracking. So
"duck off mid-plan, pano, resume" is NOT built today.

---

## Agreed design

### Trigger: MANUAL interrupt (not planned)
The operator fires the pano in the moment, when the sky earns it (a dash
of sunset colour, the first blue or a lit cloud near astro-sunrise).
Rationale: a pano needs exciting content, and you can't schedule when the
sky gets interesting — a planned pano would mostly fire on boring skies.
So: operator-initiated interrupt during the shoot. No new GP type, no
plan-authoring for the trigger.

(Pano SHAPE is still pre-configured in Excel; only the FIRING is manual.
"Pre-configured shape, manually fired.")

### Interrupt / suspend / resume (the mechanism, cart side)
1. Pano start suspends the active GP — the track executor yields (stops
   commanding) and remembers which interval it was in.
2. Pano runs its shots.
3. Resume re-engages — but NOT to the frozen snapshot pose. The tracked
   object MOVED during the pano, so resume must re-acquire the object's
   CURRENT position. This is exactly Phase-A ease: capture actual pose,
   smoothstep onto the live moving cubic. **Reuse Phase-A** — no new
   easing code. (The standalone pano's "return to centre" RESUME becomes
   irrelevant for the tracking case.)

### Geometry: Excel-configured, pushed as an array
- Excel computes the offset array and pushes `{count, offsets[]}`; the
  cart just slews to each and shoots. Cart stays dumb — no span/n math on
  the cart, no geometry knowledge.
- Even distribution rule (operator's table, confirmed): **step = span / n**,
  shots centred in each slice, symmetric about 0.
    span 180, n=5 -> -72,-36,0,36,72   (step 36)
    span 180, n=4 -> -67.5,-22.5,22.5,67.5  (step 45)
    span 180, n=6 -> -75,-45,-15,15,45,75   (step 30)
  Outer shots are inset half a step from the ends (centres span (n-1)/n of
  the span) — correct for tiling: each shot owns the middle of its slice.
- Centred on the **current gimbal heading** at trigger; **single row**
  (pitch held at centre pose).
- Cart array ceiling: **`PANO_MAX = 12`** (replaces hardcoded 4). Covers a
  6-shot pano with generous room for edge-oversampling. Pano offsets are a
  small float array — NOT cubic segments, so they do NOT share the
  `TRACK_SEGS_MAX = 4` cubic-SRAM limit. URL length to push up to 12 is
  trivial (other pushes already send longer query strings).

**Why push the array (not span+n for the cart to divide):** even spacing
is trivial, but later edge-oversampling (denser shots at the pano ends so
wide-angle distortion doesn't put stitch seams in the worst part of each
frame) is a NON-UNIFORM array. Push-the-array makes that a future
Excel-only change — the cart never changes. Push-span-and-n would box us
into even spacing without new firmware. So the variable-length array
costs nothing now and unlocks edge-oversample for free.

---

## Accepted trade-offs

- **Design case is cart-STOPPED** at the twilight bookends (late sunset;
  pre-astro-sunrise) — stars at the edges, earliest blue/cloud on the
  foreground. Cart stopped => no heading drift, the BNO worry evaporates
  for the primary use.
- **Cart-moving panos tolerated, not precisely solved** — before late
  sunset, TV is fast and the photo interval is often <4s, so cart motion
  during a pano has low impact. Resume logic is identical regardless of
  cart motion (re-ease onto the live object). Real-world experience will
  judge whether the moving case is good enough; don't over-engineer it.
- **Lost frames accepted** — design case is TV=20s / interval=22s, span
  180+, so a wide pano costs several main-sequence frames. With the
  sequence's frame density and post-stabilization frame-dropping, expected
  impact is low-to-none. Accepted cost.

---

## Deferred to real-world tuning

- **Overlap / edge-oversample model.** "span" as configured is the
  shot-spacing field (n x step), NOT the final stitched coverage — each
  shot's lens FOV must exceed the step to overlap, so the outer shots
  reach beyond +/-span/2 by half the overlap. The exact overlap %, the
  edge-density distribution, and how overlap maps to the real lens FOV are
  a geometry conversation with actual lens numbers. The array model
  already supports whatever non-uniform distribution this lands on.
- Pano-config Excel surface evolves with experience (shot count, span,
  later overlap/edge-oversample factor).

---

## Build split (when ready; either part can go first)

1. **Cart interrupt/suspend/resume plumbing** — manual trigger; track
   executor yields while pano active (the panoTick vs trackPlanTick
   fight must be resolved — one suppresses the other); on pano end,
   re-arm Phase-A onto the live object. This is what makes "duck off and
   resume" real. Independent of geometry.
2. **Configurable pano geometry** — Excel pano config -> computed offset
   array -> push `{count, offsets[]}`; widen the cart pano machine from
   the hardcoded 4 to the pushed array (`PANO_MAX = 12`). This is what
   makes the pano itself good. Replaces `pano_offsets[]`.

Neither is BNO-blocked.
