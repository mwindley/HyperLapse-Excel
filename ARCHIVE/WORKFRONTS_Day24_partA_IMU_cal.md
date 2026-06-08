# WORKFRONTS.md — Day 24 (part A) — IMU cal findings (append to #40 note)

**Append to the #40 Day-24 findings note.**

---

## #40 BNO085 — calibration approach for the heavy cart (Day 24)

Cart is now ~13 kg, ~70 × 400 mm footprint, high CoG with gimbal +
camera. **No figure-8s** — won't manhandle 13 kg through that gesture.
Achievable cart motions: full horizontal yaw rotation; pitch ±45°;
roll 30°.

**Findings (datasheet + field practice):**

- **Figure-8 is NOT required.** Moving the sensor through varied
  orientations is what mag cal needs; orthogonal positions or a slow
  full horizontal rotation do the job. A slow 360° yaw exposes the
  magnetometer to a full circle of headings — the main thing cal
  wants. The cart's available motions are sufficient.
- **Cal target 2, not strictly 3.** BNO rotation vector is typically
  ~5° accurate; standard practice acts once mag accuracy reaches 2–3.
  **Rule: cal ≥2 → use the reading (A_OK); cal ≤1 → skip, keep
  previous correction (A_SKIP).** At cal 1 the heading is unreliable
  enough that folding it in risks making gimbal aim worse than the
  bicycle-model estimate alone — so ≤1 is no-use, by design.
- **Calibrate ON the cart, in the field, powered up.** The real threat
  to heading accuracy is hard/soft-iron distortion from the cart's own
  Tic drivers, motors, CAN gimbal, battery wiring — not the cal
  gesture. CEVA recommends recal when the magnetic environment changes
  significantly, so a clean-bench cal doesn't transfer; the cart's own
  magnetic signature must be part of what's calibrated out.

**Cal motion recipe (starting point, refine on bench):** slow yaw
rotation ×2–3 full turns + pitch sweep + roll sweep; watch the cal
byte climb; stop when it holds at 2+. Turn count is "until it reaches
2," not a fixed number.

**OPEN — field-test question, NOT decidable from datasheet: Tics on /
motor running during cal?**
- Tics energized = captures the real operating magnetic environment
  (good).
- But a *running* motor = a *changing* field, which may corrupt the
  mag read rather than calibrate it out (bad).
- Instinct: Tics energized, motor NOT driving during the read — but
  this is a guess. Settle on the bench: watch whether the cal byte can
  reach 2 with motor running vs idle. Five-minute observation.

---

## Next: BNO085 bench testing — see what the real world does to the plan

Goal of the next IMU bench session: stop theorising, observe. Run the
Giga-safe polled bench sketch on the assembled cart and watch:
1. Can cal reach 2 with the achievable motions (yaw + pitch + roll),
   on-cart, powered up?
2. Motor on vs idle during cal — does the cal byte still climb?
3. Heading vs truth (iPhone/compass) once at cal 2 — does the ±0.5°
   magnitude / negated-sign finding from Day 23 still hold on the
   heavier assembled cart with all electronics live?
4. How much does the cart's own field pull the heading — is the
   Excel-pushed offset (declination + mount) still ~+9° or has the
   fuller assembly shifted it?

"Everybody has a plan until they get punched in the mouth" — the
resolved #40 architecture is the plan; the bench is the first punch.
Expect the real-world magnetic environment + the heavier platform to
move numbers the bench-clean Day-23 sketch didn't see.
