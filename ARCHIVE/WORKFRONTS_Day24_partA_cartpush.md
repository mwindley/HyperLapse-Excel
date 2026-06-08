# WORKFRONTS.md — Day 24 (part A) — Cart-plan push PROVEN

**Append to the Day-24 part A record (relates to #47 / #72 / plan
execution).**

---

## Cart plan: Excel → cart push + execute, proven end-to-end (Day 24)

The "ready half" of the Excel plan → cart handoff is now proven on
hardware. Excel authors the cart motion plan, a new push macro sends
it, the cart executes it.

**New Excel module — CartPlanPush.bas** (separate from PlanPush.bas,
which is the gimbal half). Reads the LEFT-zone Cart Plan (DRIVE/STOP
rows) on the Plan sheet, builds cart segments, pushes to /plan/load.
- Mapping: DRIVE → `m,<dist_mm>,<turn>,<m/hr>,d`; STOP →
  `s,<hold_ms>,0,0,t` (or `,o` operator-ends when Hold=0).
- Blank-distance/speed DRIVE rows (the WP01 seed/start marker) skip
  silently — matches earlier working cart-plan behaviour.
- Scan stops at first blank Action row (avoids reading the colour-
  legend rows lower on the sheet).
- Dry-run (default-safe via dataPlanPushDryRun) builds + logs the URL;
  real push pings /status then GETs /plan/load. Transport mirrors
  AstroPush (WinHttp, dataArduinoIP, Utils.LogEvent).
- WP01 is authored as STOP (operator-ends) = cart holds at start
  position so the opening gimbal step can establish before first move.
  Operator-readable AND a valid anchor for the initial gimbal plan.

**New cart endpoint — /plan/advance** (build soak-v9e). END_OPERATOR
segments do nothing on their own (just hold); nothing previously
released them. /plan/advance calls planSegmentComplete() when the
current segment is operator-ends, advancing to the next. Errors if
plan not running or current segment isn't operator-ends.

**Test run (Rosedale bench, 30 May):** plan = WP01 STOP(op) → WP02
DRIVE 500mm @5m/hr → WP03 STOP(op).
- PushCartPlan dry-run → correct 3 segments, correct URL.
- Real push → `OK loaded n=3`.
- /plan/start → held at cur=1 (WP01 operator-stop) as designed.
- Motors energised (/btn15).
- /plan/advance → released into WP02; status showed cur=2,
  steps climbing to 282500 (= 500mm × 565 steps/mm, calibration
  confirmed).
- Drove the 500mm, advanced to cur=3, holding at final WP03
  operator-stop. **Full path executed.**

**Notes:**
- 5 m/hr is a crawl (~1.4 mm/s, ~6 min for 500mm) — authored speed,
  bump the Speed cell for test convenience; plan reflows instantly.
- Final steps slightly > target = STOP_DECEL ramp overshoot (the
  photogenic ~5s decel coasts past the mark). Expected, benign at
  slow speed; relates to #54 at higher speeds.

**Status:**
- Cart-motion push + execute: **DONE / proven.** Excel authors, pushes,
  cart runs. (Was the untested link in #47 / #72 plan execution.)
- Gimbal half (PlanPush.bas) still NOT push-capable: no Stage 4 POST,
  and cubic coefficients not computed (ease-band→frames→seconds
  conversion unbuilt). That is the next build target.

**Next: gimbal half** — the simple test plan's gimbal steps (pan-follow
-30, move-to-sun, track-sun) need: cart endpoints exist
(/settings/trackpath cubic loader, /settings/trackplan TrackIntervals,
/debug/trackeval) BUT PlanPush has no Stage 4 to POST to them and
doesn't compute cubic coefficients yet. Build order TBD next session.
