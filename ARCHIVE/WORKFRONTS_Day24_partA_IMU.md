# WORKFRONTS.md — Day 24 (part A) — IMU/#40 findings note

**Append under the #40 entry / near the resolved #40 architecture
section. Discussion-only this session; no code written.**

---

## #40 BNO085 — Day 24 findings (context for build session)

Confirmed the IMU build is **blocked on the plan-stream change**, and
nailed down the correction loop + read model. No code written today
beyond the UI cal-status surface (already noted).

- **Stream/struct verified BARE.** Current `PlanSegment` struct has 7
  fields (type, dist_mm, duration_ms, steer_offset, speed_mhr,
  end_cond, transition). **None** of the #40 anchor fields exist yet —
  no anchor flag, no `expected_cart_heading`, no frame-tag. So the IMU
  correction cannot be built until the held-over stream-format change
  (anchor flag / threshold / `expected_cart_heading` / per-segment
  earth-vs-chassis frame tag) lands. That stream work overlaps the
  #72 plan/execution session — do it there, then build IMU on top.

- **Correction loop (confirmed against resolved architecture):**
  `gimbal_yaw_correction = (−BNO_yaw) − expected_cart_heading`,
  applied additively to earth-frame-tagged gimbal cubics only.
  Pan-follow and cart path untouched (cart drives blind). The BNO sign
  is negated per the Day-23 finding (BNO CW = negative, compass CW =
  positive). Excel-pushed offset (Adelaide declination +8.11° + ~+1°
  mount) folds in at this same line — frame convention must be
  consistent (expected_cart_heading and the negated BNO both
  compass-CW-positive); a silent sign error would hide here.

- **`expected_cart_heading` source = Excel `BicycleModel.bas`**, not
  computed on the Giga. It integrates the cart log into an (x,y,θ)
  trace and the planned θ at each anchor waypoint is pushed down per
  row. NOTE the model's absolute accuracy is known-imperfect (#20/#21:
  bicycle-with-linear-linkage fit was declined, radius-only data
  didn't fit) — which is precisely WHY the IMU anchor exists: the
  cart path can stay blind/approximate because the IMU corrects only
  where the gimbal must aim. Build does not depend on the bicycle
  model being accurate, only on the IMU read being accurate at the
  anchor.

- **Read model refined — "duck off", not the 500/400 mm crawl.** The
  cart knows from the plan when an earth-frame gimbal move that
  benefits from a fresh correction is coming, with lead time. So the
  anchor read becomes anticipatory and STATIONARY: park, settle, take
  a generous averaged window (1–2 s of 10 Hz polled samples), gate on
  BNO cal-accuracy == 3 before accepting. This removes the
  moving-platform/linear-accel noise the original 500/400 mm crawl
  read suffered. **Validity condition:** the chassis heading at
  read-time must equal the heading at gimbal-move-time — so read at
  (or during the dwell at) the same parked position the gimbal move
  happens from. Plan structure should guarantee the gimbal move occurs
  while the cart is parked at that known waypoint.
  - The two-attempt 500/400 mm retry from the resolved architecture
    was built around the moving read; with a stationary settle, the
    skip condition becomes "cal-accuracy didn't reach 3 within
    available time → keep previous correction" (the A_SKIP/A_FAIL +
    keep-previous fallback still holds).

- **Frequency:** ~3 anchors over a 12 h night — one before each
  earth-frame gimbal move that needs accurate real-world aim, not a
  fixed-distance schedule. IMU otherwise idle (suits the Giga-safe
  polled, no-interrupt bench sketch).

**Dependency order:** plan-stream anchor fields (#72-adjacent) →
IMU correction build (#40 remaining items: correction scalar +
cubic-eval application, `/debug/imu`, A events, Excel `bnoOffsetDeg`).
