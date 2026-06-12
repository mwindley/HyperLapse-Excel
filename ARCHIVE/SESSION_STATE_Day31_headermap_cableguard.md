# HyperLapse Cart - Session State (Day 31+)
Header-map refactor (column-reorder enabler) + 450 deg cable guard

Operator: Maurice (Adelaide, UTC+9.5). Lat -35.6416, lon 138.2514.
Cart at 192.168.1.97. Excel `HyperLapse.xlsm` = planning brain;
firmware `DJI_Ronin_Giga_v2.ino` (~8600 lines) = executor.

Operator preferences (carry forward): terse; lead with the answer; small
steps with a test at each; measure-don't-guess (Debug.Print/dry-run over
speculation); no multiple-choice widgets; whole .bas files (LF, pure ASCII,
ChrW() for any non-ASCII glyph); bare URLs; Windows cmd; never suggest
ending the session. Graphic artifacts OK; strange gimbal movement not OK
(a real motion corner stays even if it looks odd; only smooth drawing
artifacts).

================================================================
WHAT THIS SESSION DELIVERED (both complete + verified on cart dry-runs)
================================================================

## 1. Header-map: column-reorder enabler (DONE)

GOAL: let the operator reorder the MIDDLE gimbal-plan columns in Excel
(toward a left-to-right "reading order": when -> what -> where -> how)
without breaking any code. Achieved by reading/writing every MIDDLE column
BY HEADER NAME instead of fixed letter.

NEW shared module **PlanCols.bas** - single source of truth:
- `ResolveMiddleCols(ws)` -> Scripting.Dictionary of normalised-header-name
  -> 1-based column index. MIDDLE-bounded (scans from the "Step" column to
  the recon-log block / double-blank), so it never matches the DUPLICATE
  header names that also live in the cart-plan block (cols B..) and the
  recon-log block (Log row#..): Action, Note, Ry, dyaw, dpitch all appear
  twice. Fail-loud (returns Nothing + MsgBox + log) if header row or any
  required header missing.
- `NKey(v)` normaliser: maps BOTH delta cases to "d" BEFORE LCase (LCase
  folds U+0394 -> U+03B4, so post-lcase replace of the capital misses),
  lowercases, strips spaces / degree sign / "(deg)" / "()".
- RequiredKeys: step, anchortype, anchorref, offset(min), firesat, totaldur,
  action, target, rate, ry, rp, dyaw, dpitch, ease, dir(cw/ccw).

CONVERTED to PlanCols (all staged, all dry-run verified by operator):
- TrackPlanPush.bas  - COL_* now vars populated from resolver at entry.
- CableStripPush.bas - was reading stale Dir at col 29 (live bug); fixed.
- PlanPush.bas       - both entries (PushGimbalPlan, PushPreviewPlanToCart)
                       call EnsureCols. Latent bug fixed: old COL_RY=22 was
                       WRONG (Ry is 23, Rate is 22).
- ChartPush.bas      - 6 cols by name.
- PlanDVFix.bas      - rebuilt: now CLEARS all DV across MIDDLE block first
                       (kills stale ranges anchored to old letters - e.g. the
                       sun/moon/gc Target list that was bleeding onto the new
                       Dir column and blocking CW/CCW entry), then reapplies
                       each list to its RESOLVED column: Anchor type, Action,
                       Target, Dir(CW/CCW), Rate, Ease. Run `FixPlanValidations`
                       after any reorder. (MIDDLE only; cart-plan dropdowns
                       col C / N / P are separate, out of scope.)
- MWToGCRenamer.bas  - col 17 -> firesat by name.
- GimbalSweepDir.bas - was DANGEROUS: computed all cols as fixed offset from
                       Step, so after the reorder it would have written CW/CCW
                       into Note (col 29) and created a phantom Dir header
                       there. Now resolves Anchor ref / Ry / dyaw / Dir /
                       Action by name. `FillSweepDirections` fills shortest
                       cart-frame direction into the real Dir column, blanks
                       only by default (preserves operator overrides), leaves
                       GP1 blank (no incoming leg). `True` forces overwrite.
- PlanAuthoring.bas  - the WRITER (last). Live bug fixed: WriteMiddleRow wrote
                       rate->col21(=Dir) and ry->col22(=Rate). Now WriteMiddleRow,
                       CopyMiddleRow (Step/Fires-at/Total-dur specials by name),
                       occupancy probes + cursor jumps via new AnchorTypeCol(ws)
                       helper. Dir NOT seeded here (FillSweepDirections owns it).
- gimbal_planview_v2.py + gimbal_cablestrip.py - resolve() reads MIDDLE by
                       header name (golden-output identical to old index code;
                       verified unchanged after a real in-Excel Dir-move).

CURRENT SHEET STATE: operator already reordered - Dir (CW/CCW) moved from
col 29 (AC) to **col 21**, right after Target (col 20). MIDDLE header order
(row 5) now: Step(13) Anchor type(14) Anchor ref(15) Offset(min)(16)
Fires at(17) Total dur(18) Action(19) Target(20) Dir(CW/CCW)(21) Rate(22)
Ry(23) Rp(24) dyaw(25) dpitch(26) Ease(27) Move t(28) Note(29). Recon-log
block starts col 31 (Log row#).

IMPORT ORDER (matters - others depend on PlanCols): PlanCols.bas FIRST,
then the rest.

NOTE on testing limits: openpyxl cannot recalc .xlsm formula cells
(Fires-at/Total-dur are formulas), so any workbook re-saved in the Python
env reads empty (no GPs). Column-reorder safety and Dir CW/CCW span changes
can only be verified in real Excel. The golden-diff (index vs header-map on
the ORIGINAL layout) was byte-identical; operator confirmed reorder in Excel.

## 2. 450 deg cable-span guard (DONE)

OPERATOR RULE: alert the operator, then prevent the operator. Three Control-
sheet buttons -> GimbalPrep.bas: Prep Session=`PrepSession`, Prep Plan=
`BuildPlan`, Prep Cart=`PushToCart`. Guard sits at the Plan->Cart boundary.

KEY DESIGN - single source of truth (after a false start, see lesson below):
- gimbal_cablestrip.py computes the swept span and writes a sidecar
  `Python/cablestrip_span.txt` = one line "span headroom limit" (deg).
- NEW **CableSpan.bas** READS that sidecar; it does NOT recompute. So the
  chart banner, the detect log, and the push gate can never disagree.
  - `DetectCableSpan` (called by BuildPlan after RenderCableStrip): reads
    sidecar, logs span/headroom/OK, MsgBox alert if over limit. Does NOT block.
  - `CableSpanOK` (called at top of PushToCart): reads sidecar; if span>450
    OR sidecar missing -> refuse push (MsgBox + abort). No sidecar = cannot
    prove safety = blocked. Dry-run inspect unaffected (gate is in the Prep
    sequence, not in the individual dry-run push macros).
- gimbal_cablestrip.py over-limit banner: bold red
  "EXCEEDS N deg CABLE LIMIT by M deg - CART PUSH BLOCKED" + red wash,
  shown only when headroom<0.
- GimbalPrep.bas wired: BuildPlan runs CableSpan.DetectCableSpan after the
  two renders; PushToCart first checks `If Not CableSpan.CableSpanOK() Then
  ...Exit Sub`.

VERIFIED end-to-end on a real over-limit plan (GP01 Ry=50, GP02 20-hour moon
track 21:00->17:00 Dir=CCW): span 510 deg, banner shown, BuildPlan alert +
OK=False, PushToCart logged "PUSH BLOCKED: span 510 over limit by 60" and
"ABORTED". Under-limit moon plan (126 deg cart-frame) passed clean.

CRITICAL FRAME FIX (operator caught this): the cable strip MUST use
CART-FRAME yaw (cable tangle is relative to the cart body), NOT world bearing.
The renderer's old `unwrap_world` unwrapped raw world azimuth -> wrong number
(357 deg). Renamed/rewrote to `unwrap_cart(gps, wp_hdg)`: cart-frame =
world - anchor_heading, for point GPs and every track sample. For the current
plan WP headings are 0 so cart==world numerically, but the frame is now
correct for any non-zero cart heading.

SPAN MODEL (endpoint-based, agreed "simple is good"): swept cart-frame yaw,
tracks contribute BOTH endpoints (start = obj az at fire time, end = obj az
at fire+dur), unwrapped per leg by col Dir (CW=+, CCW=-, blank=shortest).
For sun/moon/GC over a night window the extreme sits at an endpoint, so
endpoints capture the span without sampling the full cubic.

================================================================
LESSONS / GOTCHAS FOR FUTURE CLAUDE
================================================================
- DUPLICATE HEADER NAMES across the three Plan sections (cart-plan, MIDDLE,
  recon-log). Any header-name resolver MUST bound its scan to MIDDLE.
- NKey delta-before-lcase ordering bug (U+0394 -> U+03B4 under LCase).
- Several macros had pre-existing latent index bugs (COL_RY=22 wrong;
  GimbalSweepDir fixed-offset-from-Step) that the reorder turned live and
  the header-map exposed/fixed. Expect more if other sections get reordered.
- Data validations are anchored to CELL ADDRESSES, not headers - they do NOT
  move with a reorder. `PlanDVFix.FixPlanValidations` is the sheet-side fix;
  run it after any reorder.
- DON'T reimplement a computed quantity in a second place (the CableSpan VBA
  first reimplemented span in VBA and disagreed with the renderer - 289 vs
  357). Make one component compute, the other read. Single source of truth.
- openpyxl can't recalc .xlsm formulas; can't fully test reorder/Dir-span
  changes in the Python env. Operator verifies in Excel.
- CableSpanPush MACRO still skips Track rows in its OWN display (reports
  used=0); that's a separate cosmetic gap. The guard (sidecar from the .py
  renderer) is authoritative and DOES include the track sweep. Acceptable.

================================================================
NEXT TASK (the actual original goal - now fully unblocked)
================================================================
**Reading-order column reorder of the MIDDLE plan: when -> what -> where ->
how**, so a plan row reads like a sentence and enables many test scenarios.

Why it's safe NOW: every MIDDLE reader/writer reads by header name via
PlanCols, both Python renderers do too, and PlanDVFix rebuilds the dropdowns
to match. Dir (CW/CCW) is already pulled left (col 21, after Target).

Suggested target order (operator to confirm/adjust): Step, Fires at,
Total dur, Offset(min), Anchor type, Anchor ref, Action, Target, Dir(CW/CCW),
Ry, Rp, dyaw, dpitch, Rate, Ease, Move t, Note. (i.e. WHEN: fires/dur/offset;
WHAT: action/target; WHERE: anchor/dir; HOW: angles/rate/ease.)

Procedure (small steps, test each):
1. Operator drags columns in Excel to the new order; SAVE (Excel recalcs).
2. Run `FixPlanValidations` (dropdowns follow columns).
3. Run `FillSweepDirections` (Dir refills correctly).
4. Re-render plan view + cable strip; dry-run each push macro
   (PushGimbalPlan, PushPreviewPlanToCart, PushTrackPlanToCart,
   PushCableStripToCart, PushChartToCart). Confirm output unchanged from a
   known-good baseline (header-map guarantees this; the test confirms it).
5. Confirm `BuildPlan` -> `PushToCart` still gate correctly on span.

Other open / deferred (not blocking the reorder):
- CableStripPush MACRO does not draw astro-track sweeps (the .py renderer
  does). If cart-pushed cable strip should match the .py chart, port the
  sweep logic into the macro. Feature, not a bug.
- WP02 has no heading entry in the cart section (wp_hdg only has WP01=0);
  fine while the cart doesn't rotate between WP01/WP02, but if a plan needs a
  real WP02 heading the cable-frame math depends on it being present.
- 22s acquire cadence is EXPECTED (CCAPI timeout -> FallbackFormula table ->
  20s night Tv ceiling -> ceil(20+1.5)=22). Not a bug.

================================================================
FILES STAGED THIS SESSION (/mnt/user-data/outputs/)
================================================================
PlanCols.bas (NEW)         CableSpan.bas (NEW)
TrackPlanPush.bas          CableStripPush.bas        PlanPush.bas
ChartPush.bas              PlanDVFix.bas             MWToGCRenamer.bas
GimbalSweepDir.bas         PlanAuthoring.bas         GimbalPrep.bas
gimbal_planview_v2.py      gimbal_cablestrip.py

All .bas: LF, pure ASCII. Import PlanCols.bas FIRST.
Python files go in the workbook's Python/ subdir.
