# WORKFRONTS.md — Day 24 (part B) — Move execution built (soak-v18)

**Append to the build record. Move-cubic "Stage 4" resolved — and it
needed no cubic. Build: soak-v18. Ry=Cy holds.**

---

## Step (Move) execution: BUILT (Day 24 pt B) — the "Move cubic" turned out unnecessary

The prior plan assumed a Move needed a fitted cubic (AstroPush.FitCubic
lifted to Public, a generic cubic push path, a new executor branch).
Resolving the design with the operator collapsed that:

- A Move goes from the previous GP's pose to a FIXED endpoint (static),
  unlike Track which follows a moving object. A single ease-in/ease-out
  slew to a fixed target is exactly what the cart's Phase-A smoothstep
  already does.
- Operator's guidance: "simple guides me; in video editing with speed
  changes I use handles to make an S often." Handles making an S = a
  smoothstep. So a Move is one S-curve, no cruise, no cubic.
- Therefore: no FitCubic, no generic cubic slot, no new push path. Just
  a new interval mode reusing the proven Phase-A code.

### Cart (soak-v18): mode 'M' = GTM_MOVE
- On entering an 'M' interval: capture actual pose, ease (smoothstep)
  from it to the ABSOLUTE endpoint (offY/offP) over acquire_ms (or
  PANFOLLOW_EASE_MS_DEFAULT=3000 if none pushed).
- **After the slew: HOLD the endpoint (keep commanding it), do NOT go
  silent.** Critical subtlety: the Ronin is permanently in Pan Follow,
  so silence would let it follow the gimbal off the mark. Move must
  actively hold to override follow until the next GP. (This is the one
  thing that distinguishes Move 'M' from Pan Follow 'P' — same eased
  entry, opposite ending: 'P' releases to silence, 'M' holds.)
- No cubic, no slot. offY/offP are absolute (like 'P'), not offsets.

### Excel (TrackPlanPush.bas): Move is an INTERVAL, not a cubic
- Relocation: because a Move is now a plain execution interval, it
  belongs in the interval pusher (TrackPlanPush), NOT a cubic builder in
  PlanPush. TrackPlanPush now matches action "MOVE":
  - mode='M', obj='N' (unused by cart for M).
  - offY/offP = ABSOLUTE endpoint: astro -> PlanPush.EvalAstro(target,
    fire-time, cartHeading)+d; marker -> Ry(V)/Rp(W)+d.
  - acquire = ease_frames x cadence (the S duration), same as Track.
- **PlanPush.EvalAstro and PlanPush.IsAstroTarget lifted Private->Public**
  so TrackPlanPush can compute astro Move endpoints (operator confirmed
  Move-to-astro is possible, though Track is the more likely use). Added
  COL_RY=22 and a dataCartHeading read to TrackPlanPush.
- **Re-import BOTH .bas** (PlanPush too — TrackPlanPush won't compile
  against the old Private signatures).

### Flags (consistent with earlier choices, tunable)
- Move duration = ease band x cadence, NOT distance-aware. A 90-degree
  move and a 5-degree move with the same ease band take the same time
  (big one slews faster). Distance-aware Move-t (col AA, still unbuilt)
  is the later refinement — same flag as Track acquire.
- Marker Move needs Ry/Rp filled; astro Move needs dataCartHeading + a
  valid fire time. Below-horizon astro logs a note, still emits the
  extrapolated endpoint (as preview does).

### Bench test (cart side, standalone)
/settings/trackplan?idx=0&ts=0&te=600000&obj=N&mode=M&offy=45&offp=-10&acquire=4000
then /track/start -> eases to 45/-10 and HOLDS against a hand-rotation
(unlike Pan Follow, which would follow). Not yet run on hardware.

## Execution status across 2/3/4 after tonight
- Phase-A ease (Step 2): DONE both sides, hardware-proven (v14).
- 3a anchor instrumentation: DONE + verified (v15).
- Pan Follow (Step 4, mode P): DONE + hardware-proven (v16).
- Preview GP-start/continuation tag + previewplan pusher: DONE,
  dry-run verified (v17 + PlanPush.PushPreviewPlanToCart).
- Move (mode M): DONE both sides (v18) — cart bench test pending.
- 3b (correction into earth-frame cubics): BLOCKED on BNO motor-power
  electrical fix (not code).
- LOCK: parked — moving-cart case best enabled by BNO.

## Terminology locked this session
- Preview buttons: PREV / NEXT (not FWD/RWD/rewind).
- Preview pose tag: GP-start (PREV/NEXT lands here) / continuation
  (stepped through, skipped by GP-level PREV/NEXT). Track GP = GP-start
  (object at ts) + continuation (object at te), label "<GP>e".

## Open / next
- BNO conducted-vs-radiated proximity test on the spare GIGA
  (instrumented bench sketch ready), then Tier-1 fix. Unblocks 3b + LOCK.
- Move bench test (cart 'M' hold vs hand-rotation).
- Distance-aware Move-t refinement (col AA).
- Stray text in Plan S6 ("CLOSE STEP 2 THEN PAN FOLLOW PLS") to clear
  when next authoring the plan (preview skips it as a non-action).
