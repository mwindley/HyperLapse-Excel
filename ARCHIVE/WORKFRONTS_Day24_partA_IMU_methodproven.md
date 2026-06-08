# WORKFRONTS.md — Day 24 (part A) — IMU cal METHOD PROVEN (session close)

**Append to the #40 cal-result note. This is the session conclusion.**

---

## #40 BNO085 — off-cart cal method proven on hardware (Day 24)

Builds this session: soak-v9a (un-stub observe) → v9b (calibrateAll +
savecal/endcal) → v9c (BNO_CAL_CAPTURE switch) → **v9d (production:
stored DCD, no calibrateAll)**. Ry=Cy held throughout — no gimbal
correction applied; observe + calibrate only.

**Proven end-to-end:**
- BNO reaches cal 3 by free-air figure-8 (off the fixed mount), in the
  cart's field, electronics on. The bolted cart CANNOT cal in place
  (yaw + ±30° pitch never leaves 0) — confirmed motion-diversity
  limit, not a field problem.
- `/debug/imu/savecal` → `stored:true` at cal 3. DCD written to BNO
  flash.
- **DCD persists across power cycles.** Proof: after reboot, a small
  off-plane wiggle snaps cal back to 3 instantly (a from-scratch cal
  would need a full figure-8). The hard/soft-iron solution loaded.
- Production build (no calibrateAll) boots on the stored DCD.

**Key nuance — cal-accuracy BYTE ≠ stored calibration.** The byte
reports *current confidence*, not whether a valid DCD is loaded. On a
mounted, stationary or flat-moving cart the byte reads 0–1 even though
the stored DCD is valid and the heading is good. It only climbs (to 2,
sometimes 3) with off-plane motion the bolted cart struggles to
produce. So the byte cannot be read at boot to gate trust.

**Two-build workflow (the fix for boot-reset):**
- `#define BNO_CAL_CAPTURE` → cal session build: calibrateAll + game-RV
  + mag on; figure-8 to 3; `/savecal`. DO NOT ship (calibrateAll
  re-arms dynamic cal each boot and resets the reported cal).
- `BNO_CAL_CAPTURE` commented out → production: rotation vector only,
  runs on stored DCD. Shipping build = soak-v9d.
- `endcal` dropped from the workflow (suspected to interfere with the
  save; not needed — production never starts dynamic cal).

**Operating procedure (current best):**
- DCD calibration is ONE-TIME (persists; redo only if magnetic
  environment or mount changes materially).
- Pre-shoot: ~2 min deliberate cal motion to bring the byte to 2
  (NOT the 30-min recon — normal cart movement has not reached 2 on
  its own in testing). Then trust through the night.
- Heading can be spot-checked against iPhone compass.

**OPEN — to be settled by real-world use, not more bench:**
- Power-up-and-go in the field is the real conclusion. Does normal
  field operation ever bring the byte to 2, or is a deliberate motion
  always needed — and what mounted-cart motion achieves it in ~2 min?
- **Is cal 1 actually usable?** If real-world heading at byte=1 is good
  enough (DCD is valid regardless of byte), the byte is safe to ignore
  — which would retire the "reject ≤1" rule and make the UI cal field
  unnecessary.

**UI decision (pending):** IMU cal field stays on Cart Recon UI for
now. Candidate for REMOVAL from the final build IF real-world says the
byte can be ignored (cal 1 OK) — then it's just operator noise. The
`/debug/imu*` endpoints stay regardless.

**Build state:** soak-v9d flashed = production BNO, calibrated unit,
running on stored DCD, Ry=Cy holds. Gimbal correction still NOT wired
(waits on plan-stream anchor fields, #72-adjacent).
