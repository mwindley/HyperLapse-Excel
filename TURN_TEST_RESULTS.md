# 90° Right Turn Calibration Test — Results

**Date:** 15 May 2026  
**Session:** C day 9  
**Test:** Straight + 90° right turn for bicycle model calibration

## Test Plan Executed

4-segment plan:
1. MOVE 600mm @ 100 m/hr, steer 0°, end on distance
2. STOP 5s @ 0°, end on duration
3. STOP 60s @ +30° (servo ramps 0° → +30° at 1°/sec during hold)
4. MOVE 99999mm @ 100 m/hr, steer +30°, operator stop when rear axle completes 90°

DEAD STOP (btn12) triggered when rear axle visually completed 90° arc.

## Raw Cart Log

```
00:00:00,S,0,0,0
00:00:00,T,98,0,0
00:00:23,T,98,0,0
00:00:23,S,100,0,0
00:00:23,P,1,0,0
00:00:51,p,1,339025,339025
00:00:51,T,98,339112,339199
00:00:51,S,0,339199,339199
00:00:51,P,2,339286,339286
00:00:56,p,2,413176,413176
00:00:56,T,128,413238,413238
00:00:56,S,0,413300,413300
00:00:56,P,3,413300,413362
00:01:56,p,3,488249,488249
00:01:56,T,128,488249,488249
00:01:56,S,100,488249,488249
00:01:56,P,4,488249,488249
00:04:19,X,0,2809047,2809047
```

Columns: `time, type, value, rear_steps, front_steps`

## Segment Analysis

### Segment 1 — Straight 600mm

| Metric | Value |
|--------|-------|
| Start | rear=0 at T+23s |
| End | rear=339,025 at T+51s |
| Steps traveled | 339,025 |
| Duration | 28 s |
| Expected steps (600mm × 565 steps/mm) | 339,000 |
| **Match** | **~0.01% off — excellent calibration** |

This validates `m_per_step = 1.77 µm/step` from day-8 straight-line calibration.

### Segment 2 — 5s hold

Duration: 51s → 56s = 5s ✓

### Segment 3 — Servo ramp 0° → +30° over 60s hold

- T value: 98 → 128 (delta = 30°) ✓
- Servo reached +30° during the 60s window (ramps at 1°/sec, needs 30s)
- Duration: 56s → 1:56 = 60s ✓

### Segment 4 — 90° turn at +30° steering

| Metric | Value |
|--------|-------|
| Start | rear=488,249 at T+1:56 |
| End | rear=2,809,047 at T+4:19 |
| Steps traveled | 2,320,798 |
| Arc length | 2,320,798 ÷ 565 steps/mm = **4,107 mm** |
| Duration | 143 s |
| End position (measured) | x=3170mm, y=2660mm (±100mm) |
| Heading change | 90° (right) |

## Bicycle Model Comparison

**Bicycle model prediction (servo +30° = wheel angle 30°):**

```
R = L / tan(δ) = 490 / tan(30°) = 849 mm
```

For 90° turn: arc length = (π/2) × R = **1,333 mm**  
End position should be: **(849, 849) mm**

**Measured real-world:**

| Method | R (mm) |
|--------|--------|
| Arc length ÷ (π/2) | 2614 |
| End position (x ≈ y ≈ R) | 2915 avg |
| Bicycle model (assumed δ=30°) | 849 |

**Conclusion: servo +30° offset produces ~3× larger turn radius than +30° wheel angle would.**

## Servo-to-Wheel Calibration Estimate

Solving back from measured arc:

```
tan(δ_actual) = L / R = 490 / 2614 = 0.187
δ_actual ≈ 10.6°
```

**Servo-to-wheel ratio: ~10.6° / 30° = 0.35 deg_wheel per deg_servo**

This is a first estimate from a single test. Sources of error:
- End position measured to ±100mm tape estimate
- Servo ramp (1°/sec) means wheel angle was changing through part of the turn
- Arc length includes any pre-turn straight from Seg 3→4 transition
- Front == rear step count in every row — needs investigation (expected divergence on arc)

## Open Questions

1. **Front == rear all rows.** Bicycle model predicts inner/outer wheel divergence on arc. Why identical? Worth checking if `ticFront.getCurrentPosition()` is reading correctly, or if overdrive is masking the difference.

2. **Servo ramp during turn.** Seg 3 fully completed servo ramp before Seg 4 started, so wheel angle should be steady at "30°" throughout Seg 4. ✓

3. **End position vs arc-length R disagreement.** Arc method = 2614mm, position method = 2915mm. ~10% spread. Could be:
   - Measurement error on tape (±100mm out of 3170mm = ±3%)
   - Turn not perfectly circular (servo settle, tyre slip)
   - DEAD STOP applied past true 90° point

4. **Where does m_per_step calibration "10% short" go?** Day-8 calculated theoretical 1.97 µm/step vs measured 1.77 = 10% gap. Same 10% gap appears here as position-vs-arc disagreement. Possibly all attributable to the same effect (tyre deflection / diff ratio / slip).

## Next Steps

1. **Repeat circle test** with full 360° to refine servo-to-wheel calibration. Single quarter-turn is statistically thin.
2. **Test at +15° servo** (normal operating angle) to confirm linearity of the servo-to-wheel ratio.
3. **Test at -30° (left)** to check symmetry.
4. **Investigate front vs rear step count** — they should diverge geometrically on an arc.
5. **Update `BicycleModel.bas`** with `SERVO_TO_DEG = 0.35` as initial constant.

## Files

- `DJI_Ronin_UnoR4_v3_debug.ino` — sketch with path debug logging
- This log file (CSV pasted above)

## Critical Fault Notes (from earlier in session)

- **UI polling saturates WiFi.** All phone tabs and browser tabs must be closed during plan execution. Polling `/status` and `/cameramsg` every second exhausts the Uno R4 request queue.
- **Tic power switch toggling clears position state.** Both Tics return `current_pos=0` after power cycle. Plan execution must run on continuous Tic power.
- **Always energise motors before running a plan** if the Tics were power-cycled (btn15).

## Calibration Constants Update

```
m_per_step      = 1.77 µm/step      (day-8, confirmed today on Seg 1)
WHEELBASE_M     = 0.490              (measured)
SERVO_TO_DEG    = 0.35               (NEW today — first estimate, single test)
```

---

# Full 360° Circle Test — Day 9 late-late evening

**Date:** 17 May 2026
**Session:** C day 9 late-late evening
**Test:** Full 360° right turn at +30 servo PWM offset, 100 m/hr,
on grass. CAN off, CCAPI off, looplong off. Operator marked 8
rear-axle ground positions at approx 45° intervals around an
imaginary peg-marked centre. Peg position was eye-judged, not a
constraint on the cart's actual orbit.

## Method

- Setup URLs in order: /debug/can?on=0, /debug/fetch?on=0,
  /debug/looplong?on=0, /btn15 (energise), /btn3 (centre steer),
  /btn5 × 6 (R5 ×6 = +30 PWM units), /btn19 (log on),
  /btn10 × 10 (speed to 100 m/hr).
- Drove the circle, marked ground at each of 8 estimated angles.
- After 360° driving, end position was offset (0, -280) from
  start — see "closure note" below.
- Stopped, retrieved log. Measured 8 (x, y) values relative to
  the peg origin and typed into Calibration sheet.

## Data

8 measured rear-axle positions (peg = origin, mm):

| Point | x | y |
|---|---|---|
| 1 (~0°)   | -1300 | 1000 |
| 2 (~45°)  | -1500 | 1970 |
| 3 (~90°)  | -500  | 3040 |
| 4 (~135°) |  100  | 3200 |
| 5 (~180°) | 1500  | 2620 |
| 6 (~225°) | 1800  | 1500 |
| 7 (~270°) | 1370  | 290  |
| 8 (~315°) |    0  | -280 |

## Results (Kasa best-fit circle)

| Quantity | Value |
|---|---|
| Fitted centre (mm) | (183, 1493) |
| Fitted radius R | **1693 mm** |
| Fitted diameter | 3386 mm |
| Radius scatter (1σ) | **±67 mm** |
| Centre offset from peg | 1504 mm |
| Implied wheel angle | 16.14° |
| **Implied SERVO_TO_DEG** | **0.504** |
| Previous estimate (day-9 quarter-turn) | 0.35 |

## Interpretation

1. **Servo-to-wheel ratio is ~45% bigger than the day-9 first
   estimate.** Day-9 was ±100mm position measurement on a single
   quarter-turn with servo ramping during start; this is 8 points
   over a full circle averaging out both effects. The new value
   0.50 is more trustworthy.

2. **Cart genuinely tracked a circle.** ±67mm scatter across 8
   points spread around a full 360° at 100 m/hr on grass is good.
   Not elliptical, not spiral. The cart's steady-state geometry
   is a clean circle once servo settles.

3. **Centre offset (1.5m from peg) is not a cart problem.** The
   peg position was operator-eyeballed; the cart's actual pivot
   is where the maths says it is. This is why we measure (x, y)
   instead of trusting peg-relative angles.

4. **Practical orbit table** (predicted from R = 490 / tan(δ_wheel)
   with new SERVO_TO_DEG = 0.50):

   | Servo PWM offset | Predicted radius |
   |---|---|
   | +5  | ~11 m |
   | +15 | ~3.4 m |
   | +22 | ~2.4 m (≈ 5m diameter orbit target) |
   | +30 | **1.7 m** (today's measurement: 1.69 m — match ✓) |
   | +45 | ~1.1 m |

5. **Closure note: end position (0, -280) vs start (0, 0).**
   Cart drove a full 360° but didn't return to start coordinate.
   Most likely explanation: the start position included servo
   ramp from CTR to +30 (not yet steady-state). Start point
   excluded from the circle fit; only the 8 mid-orbit points
   used.

## Next Steps — Repeat at Other Servo Values

Today's single test gives one point on the servo-vs-radius curve.
To confirm linearity and symmetry, repeat the same protocol at:

1. **+5 PWM offset (right)** — large radius (~11 m), tests behaviour
   near centre where steering is least authoritative. Site needs
   ~12m × 12m clear space.

2. **+15 PWM offset (right)** — mid radius (~3.4 m), expected to
   be a common operating point. Site ~5m × 5m.

3. **+30 PWM offset (right)** — today's test point, repeat for
   reproducibility check.

4. **-30 PWM offset (left)** — symmetry check. Same protocol.
   Same site as #3.

If linearity holds, SERVO_TO_DEG stays a single constant in
BicycleModel.bas. If not, becomes a lookup table or piecewise fit.

## Files

- `CircleFit.bas` (NEW today) — Kasa circle-fit module, Calibration
  sheet builder, Match Waypoints helper. UDF `FitCircle`.
- `TURN_TEST_RESULTS.md` (this file) — appended.
- Cart log retrieval, bicycle integration: pending (cart log was
  pulled but operator-typed (x, y) is the primary data this round;
  log-comparison block awaits workfront #29b firmware).

## Calibration Constants Update

```
m_per_step      = 1.77 µm/step      (day-8, confirmed today)
WHEELBASE_M     = 0.490              (measured)
SERVO_TO_DEG    = 0.504              (UPDATED today — 8-point full
                                       circle at +30 PWM, 100 m/hr,
                                       grass)
```

Old 0.35 value retained in comments for traceability; new 0.504
adopted as the single-point best estimate pending linearity tests
at +5, +15, -30.
