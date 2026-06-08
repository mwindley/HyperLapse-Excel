# HyperLapse Cart — Session Summary, Day 27 (02 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first — strict style:
SEQUENTIAL one-step-at-a-time; NO option menus / "maybe"s; MEASURE/READ
before theorising, NEVER guess (operator pulled Claude up repeatedly this
session for guessing — see process note at the end); never suggest
pausing/ending; bare URLs on their own line in chat; deliver code as
DOWNLOADABLE files. On "let's discuss": one-line restatement, then stop.

Session was steering ramp + heading work. The headline outcome: the BNO085
cold-boot heading is NOT trustworthy, and the design pivoted toward an
operator iPhone-compass anchor entered on the cart. Firmware went v27→v33.

---

## WHAT LANDED THIS SESSION (firmware now at soak-v33)

Cart sketch DJI_Ronin_Giga_v2.ino, cumulative v28→v33. Each shipped as a
downloadable file.

1. **Steering ramp rate 1°/sec → 1° per 250ms (v28).** `CART_STEERING_STEP_MS`
   1000→250 (= 4°/sec) after the BEC power refit. Three stale "1°/sec"
   comments updated. NOTE (carried from Day 26): watch for mechanical bind at
   the 133 right extreme on the first faster ramp.

2. **Recon UI heading readout — several iterations, ended at v32/v33 form.**
   - v29: live BNO heading put on the Cart Recon status line in place of the
     IMU cal field; `true_yaw` APPENDED to `/status` at idx 16 (tail, never-
     insert per lesson 16).
   - v30: cold-boot settle gate — UI + /debug/imu showed "settling" for the
     first 15s (BNO_SETTLE_MS), because the BNO emits dumb headings for
     ~10s after a cold boot (operator observation).
   - v31: switched to RAW yaw display (no offset, no settle) for direct
     sensor observation during diagnosis.
   - **v32 (current display): ADJUSTED heading + cal shown as e.g. `175°2`**
     (raw − SD offset, applied immediately at cold boot, NO settle gate).
     idx 16 = adjusted true_yaw; cal is idx 14; UI renders both as
     `<deg>°<cal>`. The 15s settle was REMOVED entirely (also from
     /debug/imu, which now returns true_yaw immediately).

3. **Operator iPhone-compass entry → 'C' row (v33).** Recon UI now has a
   **"Compass → last WP"** button: prompt modal asks for the iPhone compass
   degrees, POSTs to new `/compass?deg=N`, which logs a **`C` event**:
   `value` = degrees as typed (verbatim, no conversion), `aux` = the current
   waypoint number (binds to the most recent `W`, explicitly, not by log
   position — operator may enter it a few seconds after the WP press while
   steering). WP press is untouched/instant. CSV row exports as
   `HH:MM:SS,C,<deg>,<rear>,<front>,<wp#>`. Alert confirms which WP it hit
   (and warns if not recording).

### BicycleModel.bas — reframed to cart coordinates (delivered as file)
4. **Trace now in the cart's compass frame: +Y = NORTH (0°), +X = EAST
   (−90°), clockwise-NEGATIVE.** Matches the 4-quad measurement (below).
   - Seed: heading used DIRECTLY from the first `A` value (negate REMOVED,
     line was `(-CDbl(hdr0))`, now `CDbl(hdr0)`).
   - `SteerToRadians`: negate REMOVED (phi positive for right; the right-
     turn-clockwise sign now lives in the arc as `dtheta = -d/R`).
   - Straight: `x -= d·sin(theta)`, `y += d·cos(theta)`.
   - Arc: `R=WHEELBASE_M/tan(phi)`, `dtheta=-d/R`, `theta_new=theta+dtheta`,
     `x += R·(cos(theta)−cos(theta_new))`, `y += R·(sin(theta)−sin(theta_new))`.
   - Signs verified by a synthetic N/E/S/W Python unit test BEFORE writing
     (N→(0,+1); right turn curves clockwise to East; E→(+1,0); W→(−1,0)).
   - Validated on the real recon run: chart redrew correctly (start leg, the
     35° right arc clockwise, recentre tail). The start leg points ~ESE not
     south — that's THIS run's suspect −101° seed (a BNO capture problem,
     below), NOT a model error. The reframe is sound.

---

## THE BIG FINDING — BNO085 COLD-BOOT HEADING IS NOT TRUSTWORTHY

Measured, not theorised. This supersedes the Day-24/26 "raw yaw is compass-
locked, SD anchor bulletproof" conclusion for the COLD-BOOT case.

- **4-quad measurement (cart heading convention):** N≈0, E≈−84, S≈−179,
  W≈+97. Going N→E→S→W (clockwise) the number DECREASES → the BNO is
  **clockwise-NEGATIVE, North=0**. This confirms the Day-25 finding and
  contradicts a one-off live read earlier in the session (NE→+48.5) that had
  suggested CW-positive. The measured convention is the one used.

- **The SD true-north offset (BNOANCHR.TXT) is sound** — saved/restored
  correctly, survives reboot as a number. That part is NOT the problem.

- **Raw yaw is NOT compass-locked across a true COLD boot.** Repeated cold
  boots (main power only, no laptop) gave raw ≈ the SAME value regardless of
  which way the cart physically pointed (−56 region, later −26 after a
  recapture), with `cal` stuck at 0. WITHIN a boot, rotation tracks correctly
  (NE→N moved ~40°). So: relative datum that comes up the same each cold
  boot, not an absolute compass heading. The laptop-fed "reboots" earlier
  held a stable correct value ONLY because the board never lost power (chip
  RAM DCD survived); true cold boots lose it.

- **Root cause (code-confirmed, not guessed):** production build runs only
  `enableRotationVector(100)` and relies on the chip auto-loading a stored
  DCD (mag calibration) from its OWN flash. It never creates/verifies one.
  `cal 0` on every cold-boot read = no valid mag calibration loading → the
  rotation vector yaw isn't magnetometer-referenced → relative. A flash DCD
  is only written by `/debug/imu/savecal` (cal-capture build).

- **Web-confirmed:** `saveCalibration()` → DCD-to-flash is a real command,
  BUT BNO085 DCD persist/reload is widely reported as unreliable/finicky
  (unlike the older BNO055's clean save/reload), and CEVA says to re-do mag
  calibration per environment / room change.

- **Operator's current BNO state:** was reaching cal 3 at 400mm from metal in
  prior sessions; now sticks at cal 1, captures at cal 2 don't repeat.
  Operator's read: BNO may be dead / unrecoverable. Operator DECLINED the
  "take it well away from the cart to isolate environment vs sensor" test.
  The IMU is DETACHABLE — operator's plan is to dismount, rotate to bring cal
  to 2–3, and hope.

---

## DESIGN DECIDED THIS SESSION (iPhone-compass heading path)

Because the BNO cold-boot heading can't be trusted, the iPhone compass moves
from cross-check to PRIMARY heading source/anchor.

- **Browser-reads-phone-compass is NOT viable on the cart as-is.** Safari's
  `webkitCompassHeading` needs an HTTPS secure context + a per-visit
  permission tap (iOS 13+). The cart serves plain HTTP. Putting HTTPS on the
  Giga means a scary self-signed cert warning each time + heavy TLS — not
  worth it. So: **manual entry chosen** (operator reads the phone's Compass
  app, types the number).

- **Entry mechanism (BUILT, v33):** cart-recon-UI prompt modal → `C` row
  bound to the last WP (above). Separate action from the WP press; enterable
  while steering. Stored verbatim.

- **Execution-side concept (NOT built — deferred):** as the cart approaches a
  tracking gimbal GP (x mm out), the EXECUTION UI will INVITE an optional yaw
  correction (non-blocking). Cart never stops. Operator ignores (keeps
  current offset) or submits a fresh compass number → cart updates its
  heading offset on the spot and stays "dumb" (applies whatever offset it
  holds to aim the gimbal). This lives in the gimbal plan / execution / exec
  UI, which are still incomplete — explicitly deferred.

---

## CART-LOG / CHART WORKFLOW THIS SESSION
- First import attempt looked wrong (a different/older run was on the sheet;
  a lone heading value sat detached in cols L/M). Redone carefully: cleared
  the CartLog sheet → `GetCartLog` (38 events, buffer cleared on confirmed
  import) → rows matched the paste.
- Reminder captured: the bicycle chart macro is **`btnIntegrateBicycle`**
  (reads raw steps directly), NOT `ProcessCartLog`. ProcessCartLog is the
  plan path and is the destructive step on the raw step columns.

---

## NEXT STEPS (tomorrow — test, then continue)
1. **Flash soak-v33**, confirm banner `soak-v33`. Verify steering: faster
   ramp (4°/sec), no bind at 133.
2. **Test the `C` entry:** start cart log → Mark wpt → Compass button → enter
   degrees → confirm a `C` row reaches the buffer with the right WP number in
   the last (aux) column.
3. **Then Cart.bas:** teach `GetCartLog` to import the `C` row (give it a
   Description; land value=deg and the WP number sensibly). NOT yet done.
4. **Then the cart plan (PlanBuilder):** carry the `C` heading through into
   the Cart Plan. NOT yet done.
5. **BNO:** dismount + rotate to try for cal 2–3; decide recoverable vs
   iPhone-compass-as-primary. If the BNO stays dead, the recon `A` rows have
   no sensor behind them and the iPhone `C` value becomes the heading the
   bicycle model/plan rely on.

## DELIVERABLES IN /mnt/user-data/outputs/
- DJI_Ronin_Giga_v2.ino  — soak-v33 (cumulative: ramp 250ms; heading-on-UI as
                           `175°2`; settle removed; operator compass `C`-row
                           entry via /compass + recon UI button)
- BicycleModel.bas       — cart-frame reframe (N=+Y/0°, E=+X/−90°, CW-neg;
                           seed + steer un-negated; straight & arc rewritten)

## PROCESS NOTE (carry into next session)
Operator is precise and repeatedly (and rightly) stopped Claude for guessing
this session: inferring "L/M leftovers", asserting a settle/cal story, and
misreading the operator's cold-boot test method. The discipline that worked:
make ONE measurement at a time, report only what the data shows, say "I don't
know" + name the distinguishing measurement. Also: two `web_search` calls
fired in error mid-session (unrelated results) — disregarded; avoid spurious
searches. The BicycleModel sign work was the model case: verified in a Python
unit test before writing the VBA.
