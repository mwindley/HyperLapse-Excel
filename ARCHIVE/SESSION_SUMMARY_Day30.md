# HyperLapse Cart - Session Summary, Day 30 (05 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. Operator style held:
SHORT replies, ONE thing at a time, lead with the answer, MEASURE/READ before
theorising, NEVER guess, keep separate hardware/frames separate, pure ASCII.
Formatting rules reinforced this session: macros in CODE BOXES (copy button),
test URLs as BARE URLs on their own line in chat (never code-boxed - backticks
break click-through). When the operator says "stop", stop.

The headline: WP-event gimbal coordination (Phase 1-3) was built and PROVEN
end-to-end, including a nudge-divergence test. Mid-session a two-convention
heading bug was found and fixed - the whole system is now unified on the
Ronin/standard clockwise-POSITIVE frame. Phase 4 (astro) was scoped; the live
sun run was deferred (sun down, ~6pm Adelaide June).

---

## WHAT LANDED THIS SESSION

### WP-event gimbal coordination - Phases 1-3 (DELIVERED, PROVEN)
The design gap from Day 29: cart and gimbal ran on two independent clocks, so a
gimbal point (GP) fired off /track/start time, not off the cart actually
reaching its waypoint (WP). Now each GP fires on the cart's ACTUAL WP arrival.

- Phase 1 (carry the binding + record arrivals):
  - TrackPlanPush.bas: appends two tail tokens to /settings/trackplan -
    `awp` (anchor WP number, parsed from "WPnn"; 0 = not WP-anchored) and
    `offms` (col P "Offset (min)" x 60000 -> ms). ts/te kept for preview +
    fallback. Append-only (build-lesson 12). Dry-run logs a `bind:` line.
    MEASURED: col P is MINUTES (col Q formula uses P/1440), not ms.
  - Sketch (soak-v35): TrackInterval gains anchor_wp + offset_ms; the
    trackplan parser reads awp/offms; absent => 0 => fall back to ts/te.
  - Sketch (soak-v36): planSegmentEnter stamps wp_arrival_ms[idx+1] (the
    actual arrival = the WP's Commence). WP number = segment idx + 1 (the
    cart logs SEG idx+1). planReset zeroes the array. Record-only.
  - Proven: real push, four `[track] ... awp=N offms=N` lines on the cart;
    cart-plan run printed `[wp] arrival WP1..4` at the right deltas.

- Phase 2 (fire off WP events) - sketch soak-v37:
  - trackPlanTick now selects the active interval from LIVE windows in
    absolute millis(). New helper trackIntervalOpenAbs(i): WP-anchored ->
    wp_arrival_ms[awp] + offset_ms; returns 0 (pending) if that WP not
    reached yet; non-WP (astro/time) -> legacy track-start-relative window
    (made absolute via the anchor), so pure astro/time plans are byte-for-
    byte unchanged. Intervals are contiguous by construction (TrackPlanPush
    sets each te = next GP Fires-at), so the active interval is the LATEST
    one whose window has opened; the LAST interval closes at its planned
    duration past its own open (= the pushed END time = GP05 END).
  - /track/start vs /plan/start order no longer matters. /track/start stays
    arm+anchor (anchor still needed for the astro now_s fallback); WP-
    anchored intervals ignore it. This SUPERSEDES the parked "re-stamp at
    /plan/start" idea.

- Phase 3 (validate) - PASSED:
  - Coordinated run: armed /track/start, gimbal sat still (all WPs pending),
    then GP01 fired on `[wp] arrival WP1`, GP02 on WP2, etc. It did NOT fire
    on the track clock.
  - Nudge divergence: mid-WP1 `/plan/nudge?d=2000` (1000->3000mm). WP3/WP4
    arrived hundreds of seconds late; `[track] interval -> N` landed on each
    late `[wp] arrival`, not on the stale planned time. This is the
    acceptance proof: GPs track the actual WP through slip/nudge.

### Heading convention UNIFIED (cart was running two frames) (DELIVERED)
- Discovery: the Ronin gimbal yaw is clockwise-POSITIVE (right = +), confirmed
  on the bench (GP02 Delta yaw -30 panned LEFT) AND by DJI docs (negative yaw =
  port/left). The cart bicycle/recon frame was clockwise-NEGATIVE (east = -90,
  MEASURED Day-27). Two conventions. Operator chose to unify on the Ronin /
  standard / phone frame: N 0 / E +90 / S 180 / W -90.
- BicycleModel.bas - BOUNDARY FLIP (lowest risk): the proven Day-8 integration
  core runs untouched (internally still CW-negative, so path geometry stays
  validated); only two boundaries negated - the seed read
  (theta_rad = -(C value)*PI/180) and the heading OUTPUT (Trace col 4 + BIKE
  log). Steering (+ = right) is a separate convention, untouched.
- PlanBuilder.bas writes the C value to Plan col H VERBATIM -> the raw +90 you
  now type flows straight through. NO change needed.
- Gimbal Delta yaw (Plan col X) is already authored in the Ronin frame -> NO
  change. Future earth-frame correction now needs NO sign flip (cart + gimbal
  agree).
- Validation drive: started south (theta_deg = +180), right turn climbed
  through the +/-180 seam toward west (-90); path shape matched the ground.
  Frame PROVEN. (Cart ended ~-49 WNW because steering straightened mid-turn -
  faithful, not an error.)
- HEADING_CONVENTION.md written as the single source of truth.

### Phase 4 SCOPED (not built)
- Piece A - astro GPs fire WP-anchored: needs NO new code (the Phase-2 window
  selection is mode-agnostic, so a Track GP anchored to a WP already opens on
  WP arrival; cubic eval / Model B real-time is hardware-proven Day-24). A
  live Sun Track run is the only confirmation left - DEFERRED (sun down).
- Piece B - earth-frame heading correction (3b): the genuinely new build.
  expected_cart_heading pushed per WP (recon compass), iPhone live heading
  compare/override/offset on approach, applied to earth-frame GPs only. Now
  needs NO sign flip thanks to the unification. Future.

---

## KEY UNDERSTANDINGS (measured / read, not guessed)
- WP number = cart segment idx + 1 (the cart logs SEG idx+1). awp is 1-based.
- Phase-2 interval selection is MODE-AGNOSTIC; Move and Track open identically.
- Astro epoch footgun: the cubic's rt0 (AstroPush, treated as UTC) and the
  /settings/realtime anchor MUST both be UTC epoch-ms; local time = sun aimed
  off by the Adelaide offset (~9.5-10.5 h). There is NO realtime-push macro -
  the (unbuilt) Execution UI was meant to hand it; bench test = hit
  /settings/realtime?ms=<UTC epoch> by hand.
- Migration gotcha: any CartLog recorded with the OLD -90-for-east entry now
  integrates WRONG (seed negate flips it). Only re-integrate logs entered with
  the new +90-for-east convention.

---

## NEXT STEPS (when operator returns)
1. Phase 4 piece A: live Sun Track WP-anchored run in DAYLIGHT - author a Sun
   Track GP anchored to a WP, PushTrackPathsToCart, set UTC realtime anchor,
   PushTrackPlanToCart, arm, run. Confirm the Track interval opens on WP
   arrival and the gimbal follows the sun. Mind the UTC epoch consistency.
2. Phase 4 piece B: build the earth-frame heading correction (3b) -
   expected_cart_heading per WP + iPhone live heading. No sign flip needed.
3. SERVO_TO_DEG calibration (controlled slip test: linearity +5/+15, symmetry
   -30). Model still OVER-rotates (+35 leg reads ~128 deg vs true ~90). The
   frame flip did not touch this - geometry preserved, just reported in the
   right frame.
4. Reconcile the remaining docs to HEADING_CONVENTION.md: CART_HEADING_DESIGN,
   GIMBAL_EXECUTION_CAPABILITIES (Delta yaw wording), WORKFRONTS (#40/#41),
   WORKFRONT_gimbal_WP_coordination_Day29 (sec 4), PROJECT_STATE.
5. LOOP-LONG ~1.7-2.0s stalls at /track/start and first interval entry - noted,
   NOT investigated. Instrument before theorising (CAN setPosControl burst? or
   WiFi handling?).

Two build-time decisions still parked (workfront): fire-late-vs-skip when an
offset window is still open at the next WP (our offsets were all 0, not
exercised); Pan-Follow -> Track handoff ease.

---

## DELIVERABLES IN /mnt/user-data/outputs/
- TrackPlanPush.bas        - Phase-1 awp/offms tail tokens (Excel repo)
- DJI_Ronin_Giga_v2.ino    - soak-v37: Phase-1 store + arrival stamp + Phase-2
                             WP-event firing (sketch repo)
- BicycleModel.bas         - heading boundary flip to CW-positive (Excel repo)
- HEADING_CONVENTION.md    - single source of truth for the unified frame
- SESSION_SUMMARY_Day30.md - this file

## MISTAKES OWNED THIS SESSION
- "No code to change" when the operator asked to unify the conventions - that
  was true only for the gimbal relative-pan path. Unifying the WHOLE system
  required the cart-side BicycleModel change. Corrected and called out.
- Formatting: handed a macro as bare text, and repeated it, against the
  standing rule (macros in code boxes, test URLs bare). Corrected mid-session;
  hold it going forward.

## PROCESS NOTE
The discipline that worked: read/measure the actual code (sheet cols, executor,
/compass handler, BicycleModel math, DJI docs) before stating anything; lead
with the answer; stop when the operator said stop. Sign conventions were
settled by MEASUREMENT (bench + datasheet), not assertion.
