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
