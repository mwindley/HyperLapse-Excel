# WORKFRONTS.md — Day 24 (part A) — Track executor PROVEN

**Append to the gimbal-half map note. Relates to #5a / #50 / #47.**

---

## #5a gimbal track executor — built + proven on hardware (Day 24)

The keystone missing piece (per the gimbal-half map) is built and
drives the real gimbal. Build progression: soak-v10 → v10a (const
order) → **v10b** (explicit prototypes — the working build).

**What was built:**
- `trackEvalAt()` — reusable cubic evaluator extracted from the inline
  `/debug/trackeval` code (single source of truth).
- `trackSlotForObj()` — GTO_ byte → cubic slot + valid-mask bit.
- `trackPlanTick()` — the runtime engine: 5 Hz, walks `track_plan[]`,
  finds the interval active at shoot-time, evaluates that object's
  cubic, drives the gimbal via `setPosControl(yaw,0,pitch,0x01,0x02)`.
  FULL = yaw+pitch+offsets; YAW = yaw+offY, pitch=offP fixed.
- `/track/start` arms (re-stamps anchor = shoot t=0), `/track/stop`
  disarms (gimbal holds last pose).

**Two Arduino-specific compile traps hit + fixed (build lessons):**
1. Const-ordering: executor placed above the GTO_/GTM_ #defines it
   uses → moved defines up.
2. **Arduino auto-prototype bug** (arduino-cli #2696/#1269): functions
   taking/returning the custom type `TrackPath*` get an auto-generated
   prototype hoisted ABOVE the struct definition →
   "'TrackPath' does not name a type". Standard C++ compiles clean
   (verified with g++); only the Arduino sketch preprocessor breaks.
   Fix: explicit forward declarations right after the struct, which
   makes the preprocessor skip generating its own.

**Hardware test (Rosedale bench, gimbal powered, NO camera/cables for
safety):**
- Pushed test cubic (sun, 1 seg, yaw 0→30° over 300s = 0.1°/s, pitch
  flat) via /settings/trackpath → mask:1, num_segs:1.
- Pushed aligned interval (0→300000ms, obj=S, mode=F) via
  /settings/trackplan → count:1.
- /debug/trackeval confirmed cubic math (yaw 9.99 at t=30 for the
  0.333°/s test; 0.1°/s for the slow test).
- /track/start → **gimbal tracked the cubic: slow, smooth, steady
  creep.** Executor proven driving real hardware.

**Known issues (noted, not chased):**
- `/debug/trackeval` time origin uses the cubic's `t0_ms` (set at cubic
  push) while the executor uses `track_plan_anchor_ms` (reset at
  /track/start). The two display different t for the same moment —
  cosmetic (eval display only); executor timing is correct.
- Initial park→cubic-start move uses the fast 0x02 time-byte → one
  quick snap to the cubic's starting angle on arm. Steady-state motion
  is correct/slow. Park gimbal near cubic start (btn3) before arming
  to minimise the snap. Real fix TBD (ramp the first move).

**Status — gimbal half now:**
- Cubic fit+push (AstroPush) ✓ · cubic store+eval ✓ · interval store ✓
  · **runtime executor ✓ (NEW)**.
- STILL MISSING: pan-follow execution; Excel trackplan pusher
  (nothing POSTs /settings/trackplan from Excel — tonight pushed via
  raw URL); Move (cubic-slew) push from PlanPush (Stage 4); the
  initial-move ramp.
- Ry=Cy still holds throughout — track executor is separate from the
  (deferred) BNO gimbal-yaw correction.
