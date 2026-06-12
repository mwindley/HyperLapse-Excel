# HyperLapse - Soon-to-do (parked, Day 32)

Items deferred during the Day-32 session, in rough priority.

## ===== STATUS REVIEW (Day 32 cont., firmware soak-v114) - read this first =====
Single clean numbering of the live review. Detailed bodies for older items kept
below under their original labels (N/S/numbered) for reference - the multi-naming
there is historical; THIS block is the current truth.

OPEN (valid, to work):
  R7.  Moon step-5 firmware: below-horizon goto-rise-and-wait (cart waits at the
       moonrise pose until the moon clears the horizon, then tracks) -- the same
       treatment sun/GC already have; the ONLY un-built moon item (WORKFRONTS B
       step 5). NOTE: the moon ZENITH-BAND yaw ease (alt>70) is a SEPARATE item
       and is now DONE (AstroPush + planview, Day 32) -- not this.
  R10. Cable strip index-alignment for astro Track GPs (preview emits start+end,
       strip skips -> CableStripPush must enumerate identically).

DEFERRED:
  R1.  Health-orange during shutter+liveview run (watch LOOP-LONG/max_loop_us).

DONE / NON-ISSUE this review:
  R2.  Chart dots structural version - DONE.
  R3.  Pan Speed -> acquire_ms / park->GP01 snap - did not reoccur, DONE.
  R4.  Chart speed/object colour - DONE (Day 32, GimbalPlanViz_v3): get-there
       swings coloured by Pan Speed (Slow blue / Mid green / Fast orange);
       track legs by object (Sun yellow / Moon grey / GC white). Replaced the
       crude 90 deg/step red flag. (The 20 deg/s firmware cap is the separate
       anti-whip backstop, NOT a chart colour.)
  R5.  Yaw/pitch cap - DONE (Day 32, v111 universal slew-rate floor in
       setPosControl: floors time_for_action to swing/20 deg/s on EVERY motion
       path, caps BOTH axes via the swing max). Subsumes the pitch-cap twin.
  R6.  Exec UI row rework - DONE (Day 32, v112): earth-frame GP shows hdg button
       AND eta together; eta direction explicit (+elapsed up / countdown / done).
  R8.  Canon R3 overnight power verification - stale/DONE. (NB: the battery-swap
       PAUSE fallback is a SEPARATE unbuilt workfront - WORKFRONT_canon_battery_pause.)
  R9.  GIMBAL_PLANVIEW_BUILD.md doc update - stale/DONE.
  N1.  Negative ETA on live row - FIXED (etaField: now=elapsed, done=0,
       pending=countdown) in soak-v110.
  S4/S5. Exec START fires shutter / E-STOP + firmware stop halt shutter - DONE.
  S6.  Dateless fire-time class - ROOT FIXED (Utils.DatedFireSerial; Python live
       ephemeris + robust fire_minutes).
  S1.  Build banner sync - DONE (keep bumping).
  S7.  Two-clocks / GP01 Pan Follow glyph / AstroTable staleness - NON-ISSUES.

DONE this session (Day 32, firmware soak-v110 -> v114):
  - v110 START fires shutter (exposure-init + shutter-start) + E-STOP/stop halt.
  - v111 universal slew-rate floor (anti-whip, 20 deg/s, all paths).
  - v112 Exec UI row rework (R6).
  - v113 END stops shutter content-independent (astro -> track END; cart-only ->
    cart DONE).
  - v114 Clear clears track (no stale GP row after Clear). Verified on rig.
  - Moon zenith-band ease (AstroPush + planview).
  - R4 chart speed/object colours.
  - PushFormulaToCart folded into PushToCart (3 Excel buttons cover everything).
  - README.txt (firmware repo) rewritten Uno->Giga.

(Original detailed entries follow.)

## NEW (Day 32, post-rig)

### N1. Negative ETA STILL showing after v106 (regression / not applied?)
After pushing the new plan with v106 flashed, WP01 + GP01 rows STILL show
negative times. Expected fix (done-row eta -> 0) was in v105/v106. Either the
flash didn't take, or the clamp condition (st=="done") isn't matching these
rows (they may be st=="now" with a negative eta, not "done"). CHECK: a row that
is current ("now") but whose start is in the past also goes negative -> the
clamp must cover "now" with past start too, not only "done". Re-examine the
eta sign for st=="now" rows (the live row counting up from a past start).

### N2. Gimbal park->GP01 move too fast (no ease on the acquire)
On push, the gimbal SNAPPED from its parked pose to GP01's heading too quickly.
This is the acquire_ms=0 (ease retired, Pan Speed->acquire not yet wired -> see
#3). The initial park->first-GP move has no get-there easing. Tie the fix to
the Pan Speed -> acquire_ms wiring (#3): the FIRST move (park -> GP01) should
also honour a get-there rate, not snap.

## 1. Astro-track charting (Exec gimbal-plan SVG)  [DONE this session]
Ported into ChartPush.bas (samples Track GPs via EvalAstro + cart-heading-at-
time, emits the yaw/pitch polyline). Loaded. Note: a low-altitude target
(e.g. sunset sun, alt~0) plots below the fixed 20-80 pitch band -- verify with
a higher target. Left here for reference; no longer open.

## 1b. Astro-track charting (original note)
ChartPush.bas SKIPS Track / Track-yaw GPs ("astro charting deferred"). So an
astro Track GP contributes no points to the Exec gimbal-plan chart, and the
live camera icon has no path to ride on those rows.
- Fix: emit the astro track sweep as a polyline (yaw-over-time), the same curve
  the cable strip + plan view already compute. Then the path populates and the
  camera icon tracks it.
- Note: distinct from the "one-point" case - a plan with >=2 Move/Pan-Follow
  GPs already draws a path; this is specifically about charting the astro sweep.

## 2. Negative ETA on done WP/GP rows (firmware, v104 sketch)
execFeedJSON sends eta = arrival_ms - now even for a WP/GP already passed
(st="done"), and etaMsToSec preserves the sign -> Exec UI shows a negative
countdown on completed rows. Cosmetic only; run/timing/aim unaffected.
- Fix (next flash): when st=="done", emit eta as 0 (or null) instead of the
  negative. Same one-line change in BOTH the WP-row emit (~line 4724) and the
  GP-row emit in appendGpRow (~line 4663).

## 3. Pan Speed -> acquire_ms wiring (the "step 4" wire)
Ease retired this session; acquire_ms now pushes 0 (cart snaps). Pan Speed
(rate, deg/min) should drive acquire_ms so the slew uses the operator's get-there
rate instead of snapping.
- TrackPlanPush: derive acquire_ms from Pan Speed rate x swing (replaces the old
  Ease-frames x cadence). EaseFrames() is now dead code there - remove in the
  same pass.

## 4. Rate colour (cadence-aware whip flag) - "step 3"
Plan gimbal / cable / exec: a cadence-aware deg/frame whip signal
(peak = 1.5 x rate(deg/s) x cadence_s vs ~2 deg/frame cap; at night 22s only
Slow clears a big swing) - distinct from the crude 90 deg/step fast-yaw flag.

## 5. Non-halting render-failure (cosmetic, harness)
RenderPlanView/RenderCableStrip now Err.Raise on rc<>0, which halts BuildPlan
with no handler (raw VBA stop). Detail is already traced to the copyable log.
- Fix: swap the raise for a module-level gStepFailed flag that RunStep checks,
  so BuildPlan keeps flowing and still reports FAILED. (Discussed, not built.)

## 6. Dir EXECUTION on the cart
Cart Move/Track currently takes the shortest path; the plan's Dir (CW/CCW) is
indicator-only. Make the cart honour the wound direction.

## ===== Day 32 (mwhang + plan-view segment) =====

### S1. Build banner kept in sync  [DONE this session]
Banner now bumped to soak-v110 (START/STOP fires shutter). KEEP DOING: bump the
[build] banner every time firmware behaviour changes so the boot log is truthful.

### S2. Health went ORANGE during shutter+liveview run  [OPEN - investigate]
After START armed shutter_mode 3 + liveview, /exec/feed health went green->orange.
Likely the extra CCAPI (liveview fetch every 3rd frame) nudging loop time, but
NOT confirmed. Measure: watch LOOP-LONG / max_loop_us in Serial during a firing
run; if it stays orange or climbs to red, the LUM liveview fetch is the suspect.

### S3. Chart dots: structural version  [OPEN - cosmetic]
Took r='1.2' for now (small dots). Cleaner end-state: dots ONLY at real Move/GP
targets, the astro track drawn as a pure line (no per-sample dots). Needs ChartPush
to tag which points are track samples vs targets.

### S4. EXEC START now fires shutter  [DONE this session - CRITICAL gap closed]
START sequence: realtime -> btn15 -> track/start -> plan/start -> /exposure/init
-> /shutter/start. One field press arms gimbal + plan + photos; init sets Tv so
cadence is Tv-driven (not 2s default); LUM walks exposure every 3rd frame.

### S5. EXEC E-STOP + firmware stop now halt shutter  [DONE this session]
E-STOP runs /shutter/stop first; /plan/stop in firmware also sets shutter_mode=0
so EVERY stop path (E-STOP, abort, operator) halts firing, mirroring v108.

### S6. The "time" class - dateless fire-time  [ROOT FIX this session]
"Fires at"/"Commences" cells are TIME-OF-DAY only. Consumers were stamping a date
inconsistently (Int(Date)=today vs shoot-date vs StampClock). UNIFIED:
 - Excel: new Public Utils.DatedFireSerial (shoot-date anchor + post-midnight roll);
   ChartPush + GimbalPlanViz_v3 (AstroBaseForRow + CartHeadingAtTime) call it.
 - Python: astro_az now LIVE ephemeris at dated fire-time; fire_minutes made
   robust to datetime cell types (was returning None -> world 0 -> 320 long arc).
 - GimbalViz validation chart already correct (cart-frame, heading subtracted).
 Remaining Int(Date)/Int(Now) uses are all INTENTIONAL (today-relative tables/
 scans) - not bugs. Class closed.

### S7. Confirmed NON-issues (do not re-chase)
 - "Two clocks" scare: cart real-time tracking works; early START shows GC where
   it really is (it converges to plan at plan-time). By design.
 - GP01 Pan Follow glyph: truthful (pan=cart heading, pitch held). RS4 Pro holds
   Pan Follow natively (cart goes silent, Ronin follows). Operator just sets the
   resulting per-WP heading. No fix.
 - AstroTable staleness: display-only now (dial uses live ephemeris). Arc SHAPE is
   declination/lat-driven = stable within a day; Init Shoot rebuilds it each prep.
   Non-issue.

### S8. Parked workfronts (status updated Day 32)
 - Pitch CAP firmware (Layer 2): DONE -- subsumed by v111 slew floor (caps both
   axes via swing max).
 - Exec UI row rework: DONE (v112).
 - Moon step-5 firmware: STILL OPEN (= R7) -- below-horizon goto-rise-and-wait,
   the only un-built moon item. (Moon zenith ease is separate and DONE.)
 - Canon R3 overnight power verification: stale/done (battery-swap PAUSE fallback
   is a separate unbuilt workfront).
 - GIMBAL_PLANVIEW_BUILD.md doc update: stale/done.
 - Cable strip index-alignment for astro Track GPs: STILL OPEN (= R10) -- preview
   emits start+end, strip skips -> CableStripPush must enumerate identically.

### F1. (FUTURE) Cart motors not stopping after a short DRIVE+STOP plan
Observed: a cart plan with ~7s of motion (DRIVE 0.2m @100m/hr -> STOP, WP01
22:04:19 -> WP02 22:04:26) left the motors not stopped after the drive completed.

Operator note: suspects the cart LOAD did it. On a prior occasion, re-importing
fixed it -- as though something was stale and the second push got it.

Not yet diagnosed. To trace next time it happens.
