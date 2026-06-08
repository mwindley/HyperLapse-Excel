# Gimbal Plan View (#2) — Remaining Steps

**As of:** 07 Jun 2026, end of session. The render loop is LIVE end-to-end
(Excel button -> sweep-dir fill -> Python render -> opens PNG, hardware-
confirmed on the operator's machine: Python 3.14, openpyxl 3.1.5,
matplotlib 3.10.9). This file lists what's left. Companion to
GIMBAL_PLANVIEW_BUILD.md (the fuller spec) and the #11 entry in WORKFRONTS.

---

## What is DONE and working

- `Python/gimbal_planview_v2.py` — renderer. Non-cumulative reference
  model (base = Ry when present else WP heading; pitch = Rp else 0; Δ
  additive; NO accumulation). Pitch-as-length glyphs, earth/chassis
  styling, world-sweep legs (1→2→3→4) with CW/CCW obeyed from col AC,
  near-180° ambiguity flag when AC blank, PREV/NEXT (`--gp N`),
  map-underlay hook (`--map`), park-and-wait marker for below-horizon.
- `Modules/GimbalSweepDir.bas` — fills Plan col AC with shortest
  cart-frame CW/CCW per leg; blanks-only (operator overrides preserved);
  `FillSweepDirections True` forces a full recompute.
- `Modules/GimbalPlanViewButton.bas` — Render Plan View button. Fills
  sweep dirs, saves, shells Python (outer-quoted `cmd /c` to beat the
  quote-strip bug), logs to `Python/render_log.txt`, opens the PNG.

---

## Remaining steps (priority order)

1. **Update the docs to today's model.** GIMBAL_PLANVIEW_BUILD.md predates
   the two big corrections made this session:
   - yaw/pitch are **NOT cumulative** — per-GP references (Ry/Rp = world
     anchor; blank Ry = cart-nose offset; Δ additive).
   - sweep direction is **col AC CW/CCW**, auto-filled by GimbalSweepDir,
     operator overrides to send a leg the long way to unwind cable; the
     renderer READS col AC and never recomputes.
   Fold both in; the build doc's resolver pseudocode still shows the old
   inference-from-Action and any accumulation language must go.

2. **FIX workfront #11 validation chart (real bug, not viz polish).**
   The yaw×pitch validation chart (`GimbalPlanViz_v3.bas`) accumulates
   Move rows — same stale cumulative model we just removed from the plan
   view. Its trajectory, max-|cum yaw|, and ±450 cable numbers are
   therefore WRONG. Re-base it on the non-cumulative reference model
   (base = Ry else heading; pitch = Rp else 0; Δ additive) and compute
   cable as the running cart-frame angle honouring col AC, exactly as the
   renderer now does. Until fixed, do not trust #11's cable headroom.

3. **Wire the cable strip (view #3) to col AC.** The cable wind-up is
   already computed in the renderer (`cable` field, honours CW/CCW). View
   #3 is the linear −450…+450 strip that shows it directly. The plan view
   deliberately does NOT show cable (gimbal-pointing only, by decision);
   #3 is where the operator reads wind-up and decides which leg to flip.
   This is the natural consumer of the col-AC direction work.

4. **Map underlay v1 → v2.** v1 works (`--map tile.png`, manual north-up
   screenshot; Tapanappa is the reference image). v2 = auto-fetch a
   static tile from Settings lat/lon (Google Static Maps, north-up, needs
   API key). NOTE: tile fetch needs outbound network — runs on the
   operator machine, not the build sandbox.

5. **Earth-frame exercise + frame tag.** The current plan is all chassis
   Move, so earth-frame styling and park-and-wait are unexercised on real
   data (proven only in the scenario storyboard). When an astro GP is
   added, verify. Longer term: add the per-segment earth/chassis frame
   tag to the plan stream (#40-adjacent) so the renderer reads it instead
   of inferring from Ry presence.

---

## Watch-outs captured (so they aren't rediscovered)

- **openpyxl re-save nukes cached formula values** — never write back to
  the .xlsm with openpyxl to test; the plan cells are formulas and read
  back blank. Test overrides in-memory or in real Excel.
- **`cmd /c` quote strip** — multi-quoted path lists must be wrapped in
  one outer quote pair (done in GimbalPlanViewButton).
- **VBA import duplicates modules** — importing a .bas whose module name
  already exists creates `Name1`; remove the old module first or the
  button calls stale code.
- **Python 3.14** on the operator machine — matplotlib/openpyxl wheels
  are fine as of this session; flag if a future package lacks a 3.14
  wheel.
