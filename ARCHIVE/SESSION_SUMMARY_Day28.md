# HyperLapse Cart - Session Summary, Day 28 (03 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. Operator style is
strict and was reinforced hard this session: SHORT replies, ONE thing at a
time, NO stories / no narrating a finding before you have it, MEASURE/READ
before theorising, NEVER guess, never suggest pausing/ending, bare URLs on
their own line, deliver code as DOWNLOADABLE files. NEW standing preference
this session: "I like simple - remove fancy stuff (decorative Unicode, etc.)
as we go." Files were made pure ASCII accordingly. Operator pulled Claude up
repeatedly for over-talking and for "making a story without the answer" -
answer the question asked, lead with the answer, stop.

The headline: first full edit -> push -> replay round trip worked. Cart drove
the edited plan. BNO now isolated (STUB_BNO); the iPhone compass is the
heading source.

---

## WHAT LANDED THIS SESSION (all delivered as downloadable files, pure ASCII)

### Cart.bas (3 changes, cumulative)
1. **GetCartLog imports the 'C' (iPhone-compass) row.** New tail cols:
   col 14 = "iPhone compass (deg)" (deg verbatim), col 15 = "Compass WP"
   (the bound WP#, from the C-row aux/field 5). Readable description
   "iPhone compass -180 -> WP1". Cols 14/15 survive ProcessCartLog and
   collide with nothing (BicycleModel only reads col 12; CartPlanPush reads
   B-G). Was Day-27 next-step #3.
2. **GetCartLog now WIPES the CartLog sheet before writing** (ws.Cells.Clear
   after the non-empty check, before headers). Fixes runs stacking + stray
   col 12-15 leftovers. Empty buffer still exits early -> sheet untouched, so
   a stray re-pull can't wipe a good sheet. Header-empty guard dropped
   (always fresh now).
3. **ProcessCartLog made NON-DESTRUCTIVE on col 5/6** (the Day-26 fix was
   NEVER actually in this workbook - measured, not assumed). Now: reads
   RearSteps live from col 5, clears ONLY G:K (+P:Q), Distance stays col 7,
   Duration/Scout RELOCATED to cols 16/17 (P/Q). NB: could NOT use the
   Day-26 target cols 14/15 - those are now the compass cols. Result:
   btnIntegrateBicycle and ProcessCartLog can run in EITHER order now.

### PlanBuilder.bas
4. **Compass heading carried into the Cart Plan.** Pre-scans C rows -> map
   WP# (col15) -> deg (col14); writes each WP's deg into Plan **col H**
   ("Heading (deg)", H5 labelled). Uses the explicit col-15 binding, not log
   position. Col H confirmed free (CartPlanPush reads only B-G; inside the
   B:K cleared zone). Was Day-27 next-step #4.

### BicycleModel.bas
5. **theta0 now seeds from the first 'C' row (col 14 iPhone compass), NOT the
   'A' BNO row (col 12).** BNO is stub/untrusted. C value used DIRECTLY
   (same cart frame: N=0, CW-negative; -180 = due south). Verified -180->-275
   in the log = ~90 deg clockwise = the physical right turn, so the frame is
   sound. Start leg now points due south instead of the BNO's ~SSW (162.7).

### DJI_Ronin_Giga_v2.ino  (soak-v34)
6. **STUB_BNO RE-ENABLED** (uncommented line ~82). The stub mechanism already
   existed and is wired through all the right #ifndef guards (driver, Wire2,
   A-row logging, /debug/imu, SD anchor; /status keeps idx 14/16 present
   emitting --/-1 so NO parser index churn). Verified compiles clean
   (bno_cal_status declared at 1027, OUTSIDE the guard, stays defined).
   RE-ENABLE BNO = comment that one line back out. Banner bumped to soak-v34
   "BNO STUBBED". Excel/log need NO change - A rows just stop arriving; the
   GetCartLog A-import path stays dormant.

---

## KEY UNDERSTANDINGS REACHED (operator-driven, measured)

### The recon -> plan column semantics (big one)
- CartPlanPush sends each Plan row as ONE segment `m,<dist_mm>,<steer>,<speed>,d`
  (STOP -> `s,<hold_ms>,0,0,t/o`). The sketch's planSegmentEnter EXECUTES it
  by setting that steer+speed then driving that distance. So a plan row = "drive
  this far at this state going forward." Confirmed end-to-end (Excel + sketch).
- Operator's WORKFLOW RULE (firm): set the state (speed/steer), THEN press W.
  Each W marks the START of a new constant-state segment = "state going forward
  from this WP." This MATCHES how the cart logs steering: the 'T' row records the
  TARGET (set at press, instant), not the actual (which ramps 1 unit/250ms and
  is logged as lowercase 't' only on arrival). So "state going forward" is
  consistent with the firmware.
- The plan's Turn/Speed currently land one WP late vs that rule (builder reads
  the leg-OPENING state). NOT yet fixed in code - operator hand-edited the plan
  instead this session. A forward-attribution fix to BuildPlanFromCartLog was
  DISCUSSED and is the clean fix, but DEFERRED (operator edits by hand for now).
- "Commences" vs "Arrives": operator renamed the Plan time column to
  **Commences** = when the cart STARTS that leg (= prev Commences + prev leg
  time). An END/STOP row gives the final ARRIVAL time (prev + its leg) which the
  gimbal anchors actions to. Plan completes with a STOP row (not "HOLD" - the
  push only knows DRIVE/STOP; HOLD would error).

### Arrives/Commences timing recompute
- There is NO macro that recomputes the Plan's Arrives/Commences from edited
  Speed. Builder only seeds col J with the raw recon timestamp (placeholder).
  GenerateReplayPlan (Cart.bas) DOES do dist/speed*3600 timing maths but writes
  the separate replay/Sequence sheet, off col-8 "Replay speed" - not the Plan.
- The Plan's gimbal side (cols P/Q/R) ALREADY has live formulas: P = anchor
  resolver (INDEX/MATCH a WP's col-J time, or TIME/ASTRO) + offset; R = gap to
  next. They DEPEND on col J. So a col-J formula makes BOTH sides live.
- DELIVERED (as text, for operator to paste) a col-J formula for consistency:
  J6 = `=dataShootStart`; J7 down =
  `=IF(C6="","",J6+IF(C6="STOP",G6/86400,IF(AND(ISNUMBER(D6),ISNUMBER(E6),E6>0),D6/E6/24,0)))`
  (DRIVE adds Dist/Speed/24 hours; STOP adds Hold/86400). dataShootStart =
  Settings!$C$49. Operator had not confirmed pasting it by end of session.

### Diagnostics confirmed by reading the log/sketch (NOT guessed)
- Start-of-run "speed commanded but no TIC distance" (9->79 ramp, count flat):
  cause = motors were DE-ENERGISED during that ramp; the speed buttons set the
  factor regardless. The 79->10 "jump" = cartEnergise() does
  `cart_velocity_factor = 0.0` SILENTLY (no S log), then the next +10 -> S10.
  Buttons are +/-1 and +/-10 (cases 7/9 and 6/10), not "+/-10 only". GAP worth
  noting: cartEnergise emits no 'S', so the log can't show the zeroing - infer
  it from the 79->10 step. (Possible future: log S0 on energise.)
- Dead stop at end: speed 100->0 in ~0.5s real, but only 2 log points 15s
  apart (W5 then final C while typing compass), so the chart line between them
  is a sampling artefact, not a slow coast. 1 Hz logging can't resolve it.
- Bicycle "steering factor" = SERVO_TO_DEG = 0.504 (PLACEHOLDER, Day-9 grass
  circle). wheel_deg = offset*0.504; R = WHEELBASE_M(0.49)/tan(phi). +35 ->
  17.6deg -> R~1.54m. M_PER_STEP = 0.00000178.
- OVER-ROTATION re-confirmed: the +35 leg drove ~3.1m of arc; a true 90deg at
  R=1.54 would be only 2.42m, so 3.1m reads ~128deg. For 3.1m to BE 90deg, R
  must be ~1.98m. So 0.504 turns too sharp = slip/understeer. Compass
  (-180->-270/-275 = 90deg) is ground truth. SERVO_TO_DEG still NOT settled;
  needs the controlled test (linearity +5/+15, symmetry -30). NB operator
  thinks the YEP BEC servo-power upgrade helped the turn quality (plausible -
  servo no longer stalling - but NOT a substitute for the controlled test).

---

## THE REPLAYED PLAN (worked end-to-end this session)
Hand-edited, forward-state, speeds dropped 100->30, turn begins ~0.8m in:
```
WP01 DRIVE 1     30  0   -180
WP02 DRIVE 3.3   30  35  -180
WP03 DRIVE 1     30  0   -270
WP04 STOP  -     -   -   -270   (operator-hold end)
```
Dry-run URL verified, real push OK ("OK loaded n=4"), /plan/start -> "OK plan
started" -> operator reported "worked well". (Outstanding: get the on-ground
turn-vs-90deg number for the slip factor - operator hadn't reported it.)

---

## HARDWARE: charger selected (operator shopping)
SkyRC **B6neo** (SKU SK-100198-01, DC 200W, 1-6S, XT60 in) at Model Flight
Adelaide for **$65**. For the van's 12V/100Ah lithium bank. Covers 6-8A 6S
(<=200W); quiet (~48dB) at 6A, fan busiest at the 8A ceiling. Run via a fused
(~25-30A) XT60 lead - charger pulls ~18-20A from 12V at full 8A. Step-up
quiet-at-8A options noted (B6neo+ 240W / B6neo 2 300W, both spec'd 48dB at
full load) but plain neo chosen as 6A is the norm. Get the DC B6neo, NOT the
AC B6ACneo.

---

## NEXT STEPS (when operator returns)
1. (Optional) Paste the col-J Commences formula + set dataShootStart, so plan
   timing recomputes live on speed edits and the gimbal P/Q/R follow.
2. The controlled slip test (linearity +5/+15, symmetry -30, servo now
   properly fed) to finally pin SERVO_TO_DEG / decide pure-geometry x slip.
   Get the on-ground turn-vs-90 number from the replay too.
3. (Deferred, agreed clean fix, NOT done) forward-attribution in
   BuildPlanFromCartLog so Turn/Speed land on the WP where the state was set
   (not one WP late). Operator hand-edits for now.
4. Gimbal/execution side still incomplete (Day-27 carry): exec-UI optional
   yaw correction on GP approach, etc.

## DELIVERABLES IN /mnt/user-data/outputs/
- Cart.bas              - C-row import + sheet-wipe + non-destructive ProcessCartLog
- PlanBuilder.bas       - compass heading -> Plan col H (col-15 binding)
- BicycleModel.bas      - theta0 seeds from first C row (col 14), BNO dropped
- DJI_Ronin_Giga_v2.ino - soak-v34, STUB_BNO re-enabled (BNO isolated)

## PROCESS NOTE (carry forward, reinforced hard)
Operator wants ANSWERS, not narration. Several rebukes this session: "make a
story without the answer", "less talk i get confused", "too much", "why start
prior text with word No", "stop telling stories", "not too much talk". The
discipline that worked: read/measure the code, then state the finding in one
or two lines, lead with the direct answer to the exact question, stop. When
asked yes/no, start with yes/no. For tables, output the plain table and stop -
don't wrap it in paragraphs. Keep the "remove fancy stuff / ASCII" preference.
