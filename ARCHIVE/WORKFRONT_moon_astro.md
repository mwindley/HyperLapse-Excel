# Workfront — Moon astro (init → UI execution)

**As of:** 07 Jun 2026. **Status: SCOPE + HORIZON decided; build pending.**
No code this session — read/check/ask only. Companion to
GIMBAL_EXECUTION_CAPABILITIES.md (#55 moon maths), WORKFRONTS.md (#50/#55),
PROJECT_STATE.md (#9 "moon not pushed").

---

## Decisions made this session (the two free gates)

1. **Moon is IN scope** for the gimbal Plan. (Resolves PROJECT_STATE #9
   "decide whether to push moon" and the WORKFRONTS open question
   "moon tracking in/out of scope".)
2. **Moon obeys no-shoot-under-horizon → goto-rise-and-wait.** When the
   moon is below the horizon the gimbal parks at its rise bearing and
   holds; it does NOT track the moon underground. This **SUPERSEDES** the
   old GIMBAL_EXECUTION_CAPABILITIES line that moon has "no horizon
   gating / clamp the steep-down pitch." Same rule as sun/GC now.

---

## What already exists (do NOT rebuild)

- **Astro maths — DONE (#55, Day 18).** Astro.bas: GetMoonPosition +
  public wrappers (Schlyter ephemeris), FindMoonCrossing /
  BisectMoonAltitude root finder, window selection for all four cases
  (rise+set, rise-only, set-only, neither). Validated vs timeanddate.com
  (moonset 01:07 vs 01:09). Fully local — no API.
- **Cart side — DONE (#50, Day 17).** Moon globals + mask bits,
  /settings/astropos carries mnry/mnrp/mnsy/mnsp,
  /gimbal/showastro?type=moon&kf=rise|set works.
- **Recon UI — DONE (#50, Day 17).** Moonrise/Moonset type buttons,
  Show astro / Snap var wired.
- **AstroPush + trackpath — built, test-proven (#55).** AstroPush.bas can
  populate moon on /settings/astropos; PushTrackPathsToCart adds moon as
  a third object (Day-18 test pushed sun+moon+MW). NOT in the production
  push path yet — see remaining (b/d).

So the gap is wiring + planning data, not new astronomy.

---

## Build plan (dependency order)

**3. Moon column in the generated AstroTable — FIRST BUILD (keystone).**
   The workbook's 15-min astro table is Sun + GC only today; no moon.
   Wire GetMoonPosition into the table generator ("Generate GC Table" /
   the astro-table builder) to add Moon Az/Alt columns. Everything below
   (cubic, plan, viz) depends on this. Maths exists; this is wiring.

**4a. Enable moon in the production astropos push (Excel).**
   btnInitShoot / AstroPush production call sends sun rise/set + MW
   rise/mid/end (mask=115) but NOT moon (bits 2/3 = 0), so the UI's
   Moonrise/Moonset return "slot not pushed" (hardware-confirmed 07 Jun).
   Add mnry/mnrp/mnsy/mnsp + set the mask bits in the production call.

**4b. Confirm moon track-path is in the production push.**
   PushTrackPathsToCart was test-pushed with moon Day 18 — verify it's in
   the production "Push Track Paths to Cart" sequence, dark-window cubic
   (astroDusk → darkEnd), not just the standalone test.

**5. Apply goto-rise-and-wait to moon (per decision 2).**
   Below-horizon window → park at moon-rise bearing + hold; no underground
   tracking / pitch clamp. Reuse the sun/GC park-and-wait path. Remove or
   annotate the stale "no horizon gating" note in CAPABILITIES.

**6. Downstream viz (falls out).** The plan-view renderer already supports
   moon as an earth-frame object colour; once step 3 gives it table data
   it draws with no renderer change. Verify on a real moon Track GP.

Tangential (not moon-specific, capture only): PROJECT_STATE #9 VBA
degree-symbol mojibake in the "Astro pushed" MsgBox — cosmetic, fix with
ChrW(176).

---

## Build log

**07 Jun 2026 — steps 3, 4a, 4b, 6 DONE; 3 + 4a hardware-confirmed.**
- Step 3 (AstroTable moon column): `GenerateGCTable` updated in Astro.bas;
  whole-module swap imported + compiled clean. Table now writes Moon Az/
  Alt/above-horizon (cols G/H/I).
- Step 4a (astro push): `PushAstroToCart` updated in AstroPush.bas (calls
  FetchMoonTimesForNight, pushes mnry/mnrp/mnsy/mnsp for crossings that
  exist). Whole-module swap imported + compiled clean.
- Step 4b (track-path cubic): already in production
  (PushTrackPathsToCart -> FitAndPushTrackPath "moon"); not a gap.
- Step 6 (plan-view renderer): reads moon cols G/H defensively; runs
  unchanged on a no-moon table, draws moon arc once present.
- Modules were ASCII-normalised on swap (cleared #9 mojibake in these two
  modules; degree glyphs in untouched dialogs became spaces).

**Hardware-confirmed push (spare GIGA, no gimbal/camera):**
Sun rise 62.6/-0.9, set 297.5/-0.8; MW rise 116.5/13.0, mid 2.1/84.1,
end 253.5/29.6; Moon rise 23:23 -> 100.3/-0.5, set 12:21 -> 263.6/-0.5.
Cart returned **`"mask":127`** (all 7 slots set; was 115 before = moon
bits 2/3 now on) and echoed moon_rise/moon_set. So table->push->cart
moon flow is proven on the spare GIGA. CCAPI timeouts in the same
InitShoot run are the absent camera (Tv fallback used, expected).

## Still NOT verified (rig apart: main GIGA repackaging, spare in use)
- Show astro -> Moonrise/Moonset actually SWINGING the gimbal (no gimbal
  connected). Stored OK (mask 127); motion untested until reassembly.

## Semantics check raised this session (not a bug)
- Tonight moonset resolved to 12:21 / az 264 deg — a MIDDAY set, outside
  the 4pm-8am dark window. FetchMoonTimesForNight clamps to shootSunrise
  + 0.5 and accepted it as the bookend. Confirm that's desired vs
  treating "no set within the dark window" as none. (Moonrise 23:23 is
  inside the window and clean.)

## One thing to measure, not assume
The moon cubic window is the dark window (astroDusk → darkEnd), same as
GC. With goto-rise-and-wait now in force, confirm the window logic and the
park behaviour agree at the edges (moon rising mid-window, moon already up
at dusk, moon never rising in the dark window) — the four #55 cases now
each need a defined park/track handoff.
