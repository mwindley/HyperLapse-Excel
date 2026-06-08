# HyperLapse — Session Summary + Prep Order

**As of:** 07 Jun 2026 (Day 31). What got built, the order it runs in, and
the "Prep" button idea that chains it. Companion to WORKFRONTS.md and the
per-topic workfront docs.

---

## The goodness (what now exists)

Gimbal Plan View (#2) — the dial:
- `Python/gimbal_planview_v2.py` — renderer. Cart at centre, true-N up,
  radius = altitude. Non-cumulative reference model. Reads moon cols
  defensively. WORKS.
- `Modules/GimbalSweepDir.bas` — proposes col AC sweep direction
  (shortest-path rule); operator accepts/overrides. WORKS.
- `Modules/GimbalPlanViewButton.bas` — the Render Plan View button.
  Fills AC, saves, runs Python, opens PNG. Auto-uses Python\map.png.
  WORKS.
- `Modules/GimbalMapFetch.bas` — fetches a 60km north-up Esri satellite
  tile (keyless, personal use) to Python\map.png. WORKS.

Moon astro:
- `Astro.bas` (GenerateGCTable) — AstroTable now has Moon Az/Alt/above-
  horizon (cols G/H/I). Swapped + compiled.
- `AstroPush.bas` (PushAstroToCart) — pushes moon rise/set
  (mnry/mnrp/mnsy/mnsp). Swapped + compiled. Cart confirmed mask=127.
- Track-path cubic push for moon was already in production.

Docs:
- WORKFRONTS.md updated (Day 31 block at top).
- WORKFRONT_moon_astro.md, WORKFRONT_canon_battery_pause.md,
  GIMBAL_PLANVIEW_REMAINING.md.

---

## Run order (how a shoot gets prepped today)

Sequenced by dependency — each step needs the ones above it:

1. **Get Sunset Time** — sets dataSunriseTime / dataSunsetTime.
2. **Init Shoot** — sets astroDusk / phase times (CCAPI camera optional;
   Tv fallback covers an absent camera).
3. **Generate GC Table** — builds the 15-min astro table incl. moon
   cols G/H/I. (Needs 1+2 for the window.)
4. **Push Astro to Cart** — sun + moon + MW keypoints to the cart
   (needs 3's times; returns mask, expect 127 when moon in window).
5. **Push Track Paths to Cart** — the cubics (sun/moon/MW), production.
6. **Fetch Gimbal Map** — Esri tile to Python\map.png (only when the
   site/location changes; otherwise skip — the file persists).
7. **Render Plan View** — fills col AC, saves, draws the dial (auto-uses
   the map). Operator reviews framing + sweep here.

Note: 6 is location-bound, not nightly. 1-5 are nightly (date-bound).
7 is whenever you want to eyeball the plan.

---

## The "Prep" button idea

One button that calls the above in order, so prep is one press instead of
seven. High-level behaviour:

- Runs steps 1 -> 5 unconditionally (the nightly astro chain).
- Step 6 (map): skip if Python\map.png already exists, OR expose a
  "refresh map" checkbox / separate button for when the site changes.
- Ends on step 7 (Render Plan View) so the operator lands on the dial.
- Each step logs; on any failure, stop and report which step (don't
  push half a chain to the cart).
- Camera/CCAPI absence is NOT a failure (Tv fallback) — Prep should
  tolerate it, since the rig is often apart during planning.

Open design questions (decide at build time):
- Does Prep require the cart online (steps 4/5 push)? If the cart's not
  up, should Prep do 1-3 + 7 (Excel-only) and skip/flag 4-5? A
  "cart online?" check up front would make Prep safe whether or not the
  GIGA is connected.
- Re-run safety: all steps are idempotent (recompute + overwrite), so
  pressing Prep twice is harmless — confirm that holds for the cart
  pushes.

---

## Remaining (not in Prep yet — separate workfronts)

- **Cable strip (view #3)** — own page. Unwraps yaw from col AC
  (CW/CCW), plots min -> min+450 axis, shows used span + headroom, max-
  wind GP. Shared unwrap step feeds both the strip and the dial's sweep
  arrows. Prev/next buttons step GP-by-GP for the reach check. Operator
  uses dial and/or strip to accept/reject the macro's AC proposal.
- **Fix #11 validation chart** — still uses the old cumulative model;
  cable numbers wrong. Re-base on the non-cumulative + col-AC unwrap.
- **Moon step 5 (firmware)** — below-horizon goto-rise-and-wait in the
  cart executor.
- **Canon overnight power** — battery-swap pause fallback.
- Update GIMBAL_PLANVIEW_BUILD.md to the non-cumulative + col-AC model.

When the cable strip exists, it slots into the Prep order after Render
(or as a second output of the same render press).
