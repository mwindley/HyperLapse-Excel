# HyperLapse Cart - GC Arch Feature Session

**Date:** 2026-06-13 (Day 32 continued)
**Rig:** Adelaide overnight astrophotography timelapse cart. Arduino Giga R1 @ 192.168.1.97
driving DJI Ronin RS4 Pro gimbal (CAN) + Canon R3 (CCAPI). Planned via HyperLapse.xlsm
(VBA) + Python renderers. lat -35.6416, lon 138.2514, UTC+9.5.

---

## What this session delivered

A new astro target, **GC Arch** - tracks the Milky Way band's arch with the camera
held at a fixed foreground pitch, sweeping in yaw. Built end to end (solver -> fit ->
firmware -> plan authoring -> both renderers), then the validation surfaces were
corrected and the stale ones retired.

---

## The feature, as settled

**What it is.** Operator wants to shoot the Milky Way arch with foreground. The camera
points perpendicular to the line joining the band's two horizon "feet" (the solid white
line in PhotoPills), holding a fixed pitch, sweeping only in yaw as the sky rotates.

**Two targets.** `arch_rise` and `arch_set` are the two opposite perpendiculars to that
one rotating line (180 deg apart). The operator Moves between them whenever composition
calls for it - using their own eyes / PhotoPills. Zenith / overhead is NOT in the maths
and not an operator constraint.

**The key simplification (operator insight).** The perpendicular to the feet-line is,
exactly, the **azimuth of the galactic pole**. Computed directly - no feet scan, no
candidate pick, no carry-state, no overhead flip. The pole never nears the zenith here
(max alt ~27 deg) so the bearing is smooth all night.

- `arch_rise` = galactic SOUTH pole azimuth (points AT the arch at the start, ~east/SE)
- `arch_set`  = galactic NORTH pole azimuth (= arch_rise + 180)
- altitude returned 0 (horizon bearing); held pitch comes from **Rp**, not the solver.

**Pitch (Rp).** Portrait orientation + 15 deg foreground anchor -> fixed pitch
**Rp = +37 deg** (frame spans -15 deg to +89 deg vertical; 14mm Canon R3 portrait =
104.3 deg vertical FOV). Track-yaw holds pitch = offP = Rp; the solver's alt=0 is ignored
for aim.

**Plan shape.** arch_rise Track-yaw GP -> Move (bridges the ~180 deg flip, blank Pan Speed
is fine: firmware 20 deg/s slew floor handles it in ~9s, a blink that gets culled) ->
arch_set Track-yaw GP -> END.

---

## Files changed (all in /mnt/user-data/outputs/)

### Firmware
- **DJI_Ronin_Giga_v2.ino** (soak-v115) - GTO_ARCH_RISE 'A' / GTO_ARCH_SET 'B';
  slots track_arch_rise/track_arch_set; mask bits 3/4; objName labels; obj-string parse
  in both trackpath sites. Flashed + verified on rig.

### VBA - solver + pipeline
- **Astro.bas** - GetGCArchRise/SetAzAltAtTime = direct galactic-pole-azimuth
  (rise=SGP az, set=+180). Removed the dead feet-scan worker + FindGCArchOverhead +
  GCArchApexAlt + GalToEq + AngDist + NormalizeDeg180. Added GetGCArchRise/SetGimbalAngles
  (valid at alt=0; pitch held by Rp).
- **AstroPush.bas** - fits both arch objects over the FULL GC rise->set window
  (no overhead split, no guard). Both overlap everywhere; operator's Move sits anywhere.
- **PlanPush.bas** - IsAstroTarget + EvalAstro now resolve arch_rise/arch_set.
- **TrackPlanPush.bas** - ObjToChar maps arch_rise->A, arch_set->B.
- **ChartPush.bas** - exec-UI chart samples arch tracks (track-sampling + marker whitelists).
- **PlanDVFix.bas** - Target dropdown adds arch_rise, arch_set (run FixPlanValidations).

### Python renderers
- **gimbal_planview_v2.py** - arch ephemeris = pole azimuth (rise=SGP, set=+180);
  EPHEM + astro_az dispatch; track sampling extended to Track-yaw + arch targets;
  target whitelist fixed (was blanking arch); track-aware sweep-order connector
  (leg origin = track END az, not marker/start); arch colours (rise teal, set pink).
- **gimbal_cablestrip.py** - track-entry unwrap fix (see bug log).

### Diagnostics (kept)
- **arch_diag.py** - prints what openpyxl reads per plan row (found the whitelist bug).
- **cable_diag.py** - prints per-GP cable unwrap (found the phantom-360 bug).

---

## Bugs found and fixed (the debugging arc)

1. **Overhead-split was wrong (caught pre-ship).** Original fit split arch_rise/arch_set
   at GC transit; the band apex actually peaks ~21 min earlier, so the 180 deg flip landed
   inside the rise window. Superseded entirely by the galactic-pole model (no split needed).

2. **az/alt swap** in the first Python arch port (helper returns az,alt; code read alt,az).

3. **Seed inverted.** arch_rise first pointed at the galactic NORTH pole (away from the
   arch). Operator's check "camera ~190 deg at 7:05pm" caught it - arch_rise must be the
   SOUTH pole az (points AT the arch at the start). Swapped the +180.

4. **planview blanked arch before sampling.** A leftover target whitelist
   `target in ("sun","gc","moon")` wiped arch to "" before the track block. arch_diag
   proved the read was fine, pointing past it to the whitelist.

5. **Cable strip false 540 / "CART PUSH BLOCKED".** Real cable wind was ~180 (plan view
   read it right). A track GP's entry junction applied the row's CW/CCW dir; when the prior
   Move already arrived at the track start (entry delta ~0), CW forced +360 - a phantom
   turn. Fix: track entry uses shortest path; dir still governs the within-track sweep.

6. **Move-era logic bleeding onto track rows** (the recurring pattern - 3 instances):
   - cable strip cumulative (fixed, #5)
   - GimbalPlanViz Dir paint - false red on Track-yaw rows (gated to Move rows)
   - GimbalSweepDir auto-fill - re-populated GP03 Dir after operator blanked it
     (gated to skip Track/Track-yaw; clears stale value)
   Swept all row-walking modules for further instances - none (CableSpan reads the Python
   sidecar; Gimbal/WobblyRecon aren't plan-row walkers; CableStripPush correctly defers).

---

## GimbalPlanViz retirement (validation re-org)

The cumulative-yaw chart used a point-to-point model that can't represent track sweeps
(it inflated cable with the phantom 360). Retired the chart; kept the load-bearing
formula layer.

- **Removed:** BuildChart sub, chart-only columns (Cum yaw / Pitch / Yaw step / Fast /
  speed-band + track-object series), summary block, limit line, tunable inputs.
- **Kept:** Fires-at, Actual (mins), Dir validation + not-shortest paint, Aim (col N),
  Short (col O). Sheet relabelled "formula layer / Not operator-facing".
- **Pan Time re-homed:** swing now = shortest-path delta between consecutive Aim values
  (correct: GP02 Move = 91.5 deg, track rows ~0), no longer reads the broken cumulative
  yaw-step (col E).

**Validation responsibilities now split cleanly:**
- Cable -> Python cable strip PNG (pops up during prep; authoritative)
- Pitch limit -> plan view PNG (the >80 deg flag)
- Fast-yaw -> covered by firmware 20 deg/s slew floor (no longer a separate check)
- Pan Time / Fires-at / Actual / Dir -> Plan sheet (GimbalViz formula layer)

---

## Live verification

Full Prep Cart push succeeded: arch_rise + arch_set fit and pushed (4 segs each) over the
full window, firmware parsed obj=arch_rise/arch_set (no "bad obj"). Plan view renders the
two arch arcs sweeping (rise teal through the south, set pink), Move between. Cable strip
reads ~180 deg used / ~270 deg headroom after the unwrap fix - agreeing with the plan view.

Test plan authored:
- GP01 arch_rise Track-yaw Rp=37, 18:00 -> 01:14 (434 min)
- GP02 Move arch_set, 01:14, 2-min bridge (blank Pan Speed, slew floor handles it)
- GP03 arch_set Track-yaw Rp=37, 01:16 -> 05:51 (275 min)
- GP04 END 05:51

---

## Open items after this session

- **R10** - CableStripPush.bas (the cart's on-board Cable screen) still SKIPS astro track
  rows. Under-reports rather than mis-reports; desktop Python strip is the cable authority.
  Deliberate deferral, not a bug.
- **R7** - moon step-5 firmware (below-horizon goto-rise-and-wait), still open.
- arch plan not yet flown overnight on the real sky - the maths/fit/render are verified;
  the on-sky shot is the next real test.
