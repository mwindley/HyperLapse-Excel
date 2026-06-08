# HyperLapse Cart — Session Summary, Day 26 (01 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first — the operator's
style is strict: SEQUENTIAL one-step-at-a-time; NO option menus / "maybe"s;
MEASURE/READ before theorising, never guess (the word "guess" itself is
disliked — if you don't know, say so and ask); never suggest pausing/ending;
bare URLs on their own line in chat; deliver code as DOWNLOADABLE files, not
paste-in snippets (operator stated this preference explicitly).

Goal of the session was to repeat cart-recon trials and calibrate the
bicycle-model visualisation. We got partway, then uncovered a hardware
blocker (steering servo power) that gates clean calibration data.

---

## WHAT LANDED THIS SESSION (firmware now at soak-v27)

Each change shipped as a downloadable file. Cart sketch went v23→v27.

1. **Cart-log UI button colour (v23).** The b19 "Cart log" button now goes
   GREEN while recording, red when stopped (inline style in the /status
   poll — beats the `.rec` class specificity, the reason it was hard before).

2. **BNO true-north anchor PERSISTS to SD (v24).** `/debug/imu/capture` now
   writes the offset to `BNOANCHR.TXT`; boot restores it and prints a LOUD
   banner line (`ANCHOR RESTORED from SD offset=…` / `NO stored anchor…`).
   Excel just calls the capture link as a trigger. VALIDATED end-to-end:
   survives reflash AND power-cycle AND orientation (raw yaw is magnetometer-
   referenced via enableRotationVector, so it is repeatable across boots).
   Caveat baked in: a stored anchor is only valid while the BNO mounting is
   undisturbed — re-capture after any physical remount (banner reminds).

3. **Recon UI turn display = ACTUAL/TARGET (v25).** Turn now shows e.g.
   `+12/+30°` (+ = right), so the 1°/sec ramp lag is visible against the
   instant command. Speed already showed the commanded target (v[6]).
   /status gained steering TARGET at idx 15 (APPENDED, never inserted —
   lesson 16). Turn buttons (1–5) now re-poll ~200ms so target shows on press.

4. **Steering buttons step the TARGET, not the actual (v26).** `cartAdjustSteering`
   was `cart_steering + delta` (lagging actual) → repeated +5 presses gave
   5,7,9,11… Now `cart_steering_target + delta` → clean 5,10,15,20,25,30.

5. **Steering range made symmetric (v27).** Was MIN60/MAX130 about centre98
   (offset +32 / −38, imbalanced — an old issue). Now MIN63/MAX133 = even
   ±35 servo units. NOTE: 133 is 3 past the old 130 ceiling — operator to
   watch for mechanical bind at the right extreme on first test.

### Excel VBA fixes (delivered as files)
6. **ProcessCartLog no longer clobbers raw steps (Cart.bas).** ROOT CAUSE of
   a recurring data-loss: ProcessCartLog cleared `E:K` and reused cols 5/6
   for Duration/Scout-speed — destroying RearSteps(5)/FrontSteps(6), which
   are a SYSTEM-WIDE convention (written by GetCartLog + the simulators
   Module1/Module2/WobblyRecon; read by BicycleModel + Smooth). Fix: clear
   only G:K (+N:O), keep RearSteps/FrontSteps in 5/6, keep Distance at col 7
   and replay at 8–11 (consumers untouched), move Duration/Scout-speed to
   cols 14/15. Raw steps now survive ProcessCartLog regardless of run order.
   Delivered as the FULL Cart.bas (mojibake from extraction cleaned, written
   cp1252 so it re-imports as the "Cart" module). The earlier one-sub file
   `Cart_ProcessCartLog_FIX.bas` is SUPERSEDED — do NOT import it; it caused
   an "Ambiguous name detected: ProcessCartLog" because it imported as its
   own module, duplicating the sub. Operator removed it.

7. **BicycleModel steering SIGN fix (BicycleModel.bas).** Trace drew a RIGHT
   drive as a LEFT (CCW) arc. Cause: cart steer offset is +ve = RIGHT, but
   the model's wheel-angle convention is +ve = LEFT, so `SteerToRadians` now
   NEGATES. Arc now bends correctly. (The theta0 BNO-seed negate is correct
   and stays — confirmed by the east sign-check this session.)

### Calibration / frame work validated
- theta0 sign CONFIRMED (open from Day 25): cart north→east, true_yaw went
  negative while iPhone went +90 → negate is correct, NOT mirrored.
- Correct macro order for calibration: GetCartLog → BicycleModel (btnIntegrateBicycle)
  → ProcessCartLog → BuildPlanFromCartLog. BicycleModel must precede
  ProcessCartLog ONLY mattered before fix #6; now col 5 survives either order.
- The CircleFit/Calibration sheet machinery (InitCalibrationSheet →
  MatchWaypointsToLog → FitCircle) is for the 8-point CIRCLE runs (FitCircle
  needs ≥3 x/y points; the sheet's input block is for hand-measured ground-
  truth points). Operator is NOT using it for the turn runs.

---

## HARDWARE BLOCKERS — REPEAT THESE ON REFIT (operator's closing note)

### Servo power supply — NOK
- Steering servo is fed from a **Jaycar AA0236** DC-DC step-down: 6–28V in,
  3–15V out, **max 1.5A**, with overload/overheat auto-shutoff.
- 1.5A is the bottleneck. The servo (stock **Spektrum S905**, rated ~555 oz-in
  @7.2V — NOT a weak servo) STALLS partway (~15° instead of commanded 30°)
  on a DRY turn (turning while stopped = max tyre scrub = peak current).
  Delivered torque tracks current; capped at 1.5A the servo can't develop
  its rating → looks like a weak servo but is SUPPLY STARVATION.
- Cheap modules can't be paralleled to cheat more current (they hog/fold-back/
  back-feed; not current-sharing). Don't.
- PLAN (operator going to order): **HobbyKing YEP 20A HV SBEC** (~US$21–25):
  2–12S input (feeds from the onboard 6S aux), jumper output set to **7V**,
  20A continuous. Do NOT select 9V on the S905 (over its 7.2V rating).
  Wiring: BEC output → servo +/−, signal → Arduino D5, BEC ground tied to
  Arduino ground (common ground).
- TEST ON REFIT: put the EXISTING S905 on the YEP BEC and re-run the dry turn.
  If it now reaches 30°, the servo was never the problem — saved a A$260
  S6510 (which is also discontinued / down to single AU stock). If it still
  stalls when properly fed, THEN the S6510 (820 oz-in, 6–8.4V, 15T, giant-
  scale so a mount change) is justified. Both are 15T spline → aluminium
  clamping horn either way.
- ALSO: turning while ROLLING (not dry from a stop) avoids the stall — the
  good-practice ramp-while-moving sidesteps the worst case.

### Turn info in plan — NOK (resolved in firmware, re-verify on refit)
- The plan records ONE steer per leg = the value at the waypoint that OPENS
  the leg, and it's the TARGET (from 'T' events), not the trailing actual.
  WP03 showed +30 after a recenter because the recenter (T,98) landed INSIDE
  the WP2→WP3 leg, and the builder doesn't split a leg at a mid-leg steering
  change. WP02 showed speed 0 for the same reason (Start pressed at rest,
  speed raised during the leg).
- OPERATOR WORKFLOW RULE established: press WP *after* setting the speed and
  steering for the upcoming segment, and mark a waypoint at EVERY speed/steer
  change, so every leg is constant-state and the plan captures it. (Trade-off:
  more waypoints. For calibration runs, mark at each change.)
- The calibration is only trustworthy from turns where the servo ACTUALLY
  reached the commanded angle — i.e. once the power fix lands. A stalled
  servo logs target +30 while the wheel only made ~15°, which would corrupt
  any SERVO_TO_DEG / slip number. So: fix power, then repeat the recon trials.

---

## OPEN / CARRIED FORWARD
- Slip factor / SERVO_TO_DEG still NOT settled. Two clean +30 driven turns
  this session (carpet, R≈2.08 / 2.30 m) vs Day-25 grass circle (R≈1.69 m).
  Surface (carpet vs grass) is ONE known difference but NOT proven causal —
  speed, drive style, step-distance accuracy all also differ. Needs a
  controlled test holding all-but-surface constant, AND a properly-fed servo.
- Dot pitch on the Trace chart: the fine arc dots are 0.1m interpolation
  fill (ARC_VIZ_STEP_M), NOT per-step measurements; straights aren't
  subdivided. Read calibration spacing from the LOGGED event points (W/S/T),
  not the fill. (Optional future: make fill vs logged points visually distinct.)
- GetCartLog APPENDS to the CartLog sheet and does not clear first; it also
  calls /cartlog/clearcart after a confirmed import (so the cart buffer is
  emptied — a sheet mishap then can't be re-pulled). Operator flagged folding
  a sheet-clear into the macro as a future change. Consider also dropping the
  post-import clearcart so the buffer stays recoverable.

## DELIVERABLES IN /mnt/user-data/outputs/
- DJI_Ronin_Giga_v2.ino  — soak-v27 (all firmware edits above; NOT yet
                            flashed by end of session? operator was flashing
                            through v23–v27 live — v27 was the last delivered)
- Cart.bas               — full module, ProcessCartLog non-destructive fix
- BicycleModel.bas       — steering sign fix (SteerToRadians negate)
- Cart_ProcessCartLog_FIX.bas — SUPERSEDED, do not import (caused the
                            ambiguous-name duplicate); archive/delete.

## NEXT STEPS (when operator returns, post servo-power refit)
1. Fit the YEP 20A BEC at 7V to the existing S905; re-run the dry turn to
   confirm it reaches the commanded angle. Decide S905-stays vs S6510 then.
2. Re-verify v27 steering: symmetric ±35, clean +5 target steps, no bind at 133.
3. Repeat the controlled recon/circle trials with the servo properly fed,
   marking a WP at every speed/steer change, to finally pin slip / SERVO_TO_DEG.
4. Confirm the steering-sign-fixed Trace bends right on a fresh run.
