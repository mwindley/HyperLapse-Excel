# Heading Convention - SINGLE SOURCE OF TRUTH (Day 29, 05 Jun 2026)

The whole system uses ONE heading frame: clockwise-POSITIVE.

    N = 0
    E = +90
    S = 180
    W = -90   (equivalently 270)

This is the standard compass frame, the same one a phone compass shows,
and the same sense as the Ronin gimbal yaw (right = positive). Before
Day 29 the cart side ran clockwise-NEGATIVE (E = -90) while the gimbal ran
clockwise-positive - two conventions. They are now unified on the Ronin /
phone / standard frame.

## What you DO

- Cart recon compass entry (`/compass?deg=N`): type the RAW phone reading.
  East = +90. No hand-negation. (Previously you negated to -90 - stop doing
  that.)
- Reading a heading anywhere (Trace `theta_deg`, BIKE log, Plan col H):
  it is in this CW-positive frame. South prints as +180; a right turn makes
  the heading climb (e.g. through +180 and on toward -90 = west).

## What is NOT this convention

- Steering / wheel angle is a SEPARATE convention: steer offset + = RIGHT.
  Unchanged by the heading unification. How you steer and recon is the same.

## How it is implemented (so future edits stay consistent)

- BicycleModel.bas: BOUNDARY FLIP. The proven Day-8 integration math runs
  internally in the old CW-negative frame (so the validated path geometry is
  untouched). Only two boundaries are negated:
    - seed read: `theta_rad = -(C value) * PI/180`
    - output:    reported heading = `-(internal theta)` (Trace col 4 + log)
  The internal representation is an implementation detail; everything you
  type and read is CW-positive.
- PlanBuilder.bas: writes the C value to Plan col H VERBATIM - so the raw
  +90 you enter flows straight through. No change needed.
- Gimbal (DJI_Ronin_Giga_v2.ino): Plan col X "Delta yaw" is authored in the
  Ronin frame already (right = +, left = -). Relative-pan Delta yaw goes to
  the Ronin unmodified. No change needed.
- Future earth-frame gimbal correction (`expected_cart_heading` -> gimbal
  yaw, the 3b path): because cart and gimbal now agree, this needs NO sign
  flip when it is built (Phase 4).

## Migration gotcha

Any CartLog recorded UNDER THE OLD convention (east entered as -90) will
integrate WRONG now (the seed negate turns the old -90 into east->west).
Only re-integrate logs recorded with the new +90-for-east entry. Old logs
are stale for integration.

## Still open (not part of this unification)

- SERVO_TO_DEG = 0.504 is still the Day-9 placeholder; the model
  OVER-rotates (a +35 leg reads ~128 deg vs a true ~90). Needs the
  controlled slip test (linearity +5/+15, symmetry -30). The frame flip did
  not change this - it preserves the geometry, just reports it in the right
  frame.

## Docs to reconcile to this note (still describe the old CW-negative frame)

- CART_HEADING_DESIGN.md
- GIMBAL_EXECUTION_CAPABILITIES.md  (Delta yaw sign wording)
- WORKFRONTS.md  (#40/#41 heading entries)
- WORKFRONT_gimbal_WP_coordination_Day29.md  (section 4 heading model)
- PROJECT_STATE_CONSOLIDATED.md  (if/where it states the frame)
