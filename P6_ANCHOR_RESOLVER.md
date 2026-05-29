# P6 — Anchor Resolver (built 26 May 2026)

**Status:** Built as formula, verified end-to-end against the worked example
plus three additional test cases.

**Continuation of:** Day-19 work (Sessions C/D). PLAN_AUTHORING.md §6.

---

## What was built

Live-recompute formula in a new `Fires at` column on the Plan sheet middle
zone. Converts each gimbal row's `(Anchor type, Anchor ref, Offset)` into
an absolute wall-clock time, recomputed instantly when any input changes
(no macro click required).

Deliverable: `Plan_mockup_P6.xlsx`.

---

## Changes vs P3 mockup

### Plan sheet — middle zone column shift

Two new columns inserted after Anchor ref (col O):

| Col | Field            | Editable | Notes                                    |
|-----|------------------|----------|------------------------------------------|
| P   | Offset (min)     | yes      | Plain number, positive or negative. Blank = 0. |
| Q   | Fires at         | derived  | Formula. Updates live when N/O/P change. |

Everything from old col P onwards shifts right by 2:

| Old | New | Field         |
|-----|-----|---------------|
| P   | R   | Action        |
| Q   | S   | Target type   |
| R   | T   | Target ref    |
| S   | U   | KF            |
| T   | V   | Rate          |
| U   | W   | Δyaw          |
| V   | X   | Δpitch        |
| W   | Y   | Move t        |
| X   | Z   | End anchor    |
| Y   | AA  | Note          |

Merged header `M3:Y3` ("MIDDLE — Gimbal Plan (editable)") expanded to
`M3:AA3` to cover the new width.

### Plan sheet — right zone also shifted +2

The middle zone's new `Note` column (AA) would have collided with the
right zone's `Log row#` column (also AA). Right zone is read-only
reference data, so the cleaner fix is to shift it right as well:

| Old | New | Field         |
|-----|-----|---------------|
| AA  | AC  | Log row#      |
| AB  | AD  | Time          |
| AC  | AE  | Type          |
| AD  | AF  | Astro tgt     |
| AE  | AG  | KF            |
| AF  | AH  | Ry            |
| AG  | AI  | Pitch         |
| AH  | AJ  | Δyaw          |
| AI  | AK  | Δpitch        |
| AJ  | AL  | Label         |

Merged header `AA3:AJ3` becomes `AC3:AL3`. Column AB is now a visual
gutter between middle and right zones.

### Plan sheet — WP # column to text

Left-zone `WP #` (col H) values converted from integers `1..6` to text
strings `WP01..WP06`. The Anchor ref convention is `WP0N`; left-zone
column now matches for direct string-to-string `MATCH()`. No `MID`/`VALUE`
parsing needed.

### Settings sheet — time values upgraded

`dataShootStart` and the seven `data*Time` astro placeholders were stored
as text strings (`"17:42:00"` etc.) in P3, which worked by accidental
coercion in the Cart Plan arithmetic but failed inside `IF(N="ASTRO", ...)`
branch — Excel/LibreOffice returned `#NAME?`/type errors mixing string
named ranges with `TIMEVALUE` results elsewhere.

P6 converts these cells to real Excel time values formatted `hh:mm:ss`.
Behaviour identical for callers; type-stable.

---

## .bas modules updated

Three of the existing P2/P4/P5 modules touch columns affected by the P6
shift. All three have been updated and ship alongside the xlsx mockup:

| Module                  | Why it changed                                        |
|-------------------------|-------------------------------------------------------|
| `PlanBuilder_P6.bas`    | Writes col H (WP #) as text `WP01..WPNN` instead of   |
|                         | integer. Matches Anchor ref convention.               |
| `GimbalLogPuller_P6.bas`| Right-zone constants AA→AC, AJ→AL. All `Cells(r,col)` |
|                         | writes +2. `CountRightZoneRows` now reads col 30 (AD).|
| `PlanAuthoring_P6.bas`  | Middle-zone constant MID_COL_LAST Y→AA. All           |
|                         | `Cells(r,col)` writes/reads for cols ≥16 bumped by +2.|
|                         | `WriteMiddleRow` skips cols 16 (P=Offset) and 17      |
|                         | (Q=Fires at) — operator/formula territory.            |
|                         | `CopyMiddleRow` preserves Q formula on row shift      |
|                         | (was a copy-as-value bug latent in original — would   |
|                         | have frozen Fires-at to source row's resolved time).  |
|                         | `BuildWPList` reads col H as text strings (was        |
|                         | `IsNumeric` + integer concat).                        |
|                         | Default Anchor refs `"WP1"` → `"WP01"` (3 sites).     |
|                         | Right-zone log-row# read in `AddPlanRowFromLog` bumped|
|                         | from col 27 (AA) to col 29 (AC); fields AC..AJ bumped |
|                         | to AE..AL.                                            |

The other modules (`Astro.bas`, `AstroPush.bas`, `BackupRestore.bas`,
`BicycleModel.bas`, `Buttons.bas`, `Camera.bas`, `Cart.bas`,
`CircleFit.bas`, `Formula.bas`, `Gimbal.bas`, `Sequence.bas`,
`SimulateWobblyRecon.bas`, `Smooth.bas`, `Utils.bas`) were grep-checked
for any Plan-sheet middle-zone or right-zone column references. None
found — they all touch their own sheets (CartLog, GimbalLog, Sequence,
etc.) which are not affected by P6.

---

## The formula

Lives in `Q6..Q25` (placeholder row range). One formula, three branches
on `N` (anchor type), all three add `P/1440` (offset in minutes, 1440
min/day):

```
=IF(N6="WP",
     INDEX($J$6:$J$20, MATCH(O6,$H$6:$H$20,0)) + IFERROR(P6,0)/1440,
   IF(N6="TIME",
     IFERROR(TIMEVALUE(O6),"") + IFERROR(P6,0)/1440,
   IF(N6="ASTRO",
     IF(O6="sunset",    dataSunsetTime,
     IF(O6="sunrise",   dataSunriseTime,
     IF(O6="moonrise",  dataMoonriseTime,
     IF(O6="moonset",   dataMoonsetTime,
     IF(O6="mwrise",    dataMWRiseTime,
     IF(O6="mwtransit", dataMWTransitTime,
     IF(O6="mwset",     dataMWSetTime, "")))))))
     + IFERROR(P6,0)/1440,
     "")))
```

Design notes:

- **Nested `IF` instead of `IFS`.** Tested both; `IFS` returned `#NAME?`
  in LibreOffice (and the .xlsx roundtrip lowercases `ifs(...)` in
  saved XML, which may be the trigger). Nested `IF` is verbose but
  bulletproof across both engines. Operator preference was verbose.
- **`INDEX`/`MATCH` (not `VLOOKUP`)** because the WP # column (H) is
  left of the Arrives column (J). VLOOKUP can't look leftward.
- **`IFERROR(P6,0)`** allows the offset cell to be blank — treated as 0.
- **Match range `$J$6:$J$20` / `$H$6:$H$20`** gives 15-row headroom for
  long cart plans. Lift the upper bound if a real-world recon exceeds it.
- **`IFERROR(TIMEVALUE(O6),"")`** for the TIME branch — if operator
  typo'd the time, cell shows blank rather than `#VALUE!`.

---

## Verification

`Plan_mockup_P6.xlsx` roundtripped through LibreOffice (forces recalc),
then values inspected. All three demo rows resolve correctly:

| GP  | Anchor type | Ref     | Offset | Expected | Got     |
|-----|-------------|---------|--------|----------|---------|
| GP1 | WP          | WP01    | (0)    | 15:42    | 15:42 ✓ |
| GP2 | WP          | WP05    | (0)    | 16:30    | 16:30 ✓ |
| GP3 | ASTRO       | sunset  | (0)    | 17:42    | 17:42 ✓ |

Plus three additional probe rows added temporarily then removed from
the deliverable:

| Probe | Type  | Ref    | Offset | Expected | Got     |
|-------|-------|--------|--------|----------|---------|
| 1     | WP    | WP03   | +5     | 16:11    | 16:11 ✓ |
| 2     | ASTRO | sunset | −10    | 17:32    | 17:32 ✓ |
| 3     | TIME  | 23:30  |  0     | 23:30    | 23:30 ✓ |

---

## What still needs doing — outside P6 scope

1. **Data validation list for Anchor type (col N).** Currently free-text.
   Worth a `WP / TIME / ASTRO` dropdown to prevent typos that would silently
   make `Fires at` return blank. Two minutes of work; not done here because
   the mockup is for inspection, not authoring.

2. **Data validation for ASTRO anchor ref (col O when N=ASTRO).** Limited
   to the seven recognised astro keys. Easy via Settings-sheet lookup
   list. Same rationale.

3. **Validation pass for P10 (planned phase).** When `Fires at` returns
   `""` (blank), the row is unresolved — should be flagged in red as part
   of P10 pre-flight validation.

4. **End anchor (col Z, was X) currently free-text** ("until GP3",
   "T0+120"). It belongs in the same anchor-resolver pattern but with a
   different output shape (duration or absolute end time). Out of scope
   for P6; logical next step is a parallel `Fires until` derived column
   that uses the same three-branch resolver, OR an "implicit-until-next"
   default rule. Re-raise when P7 (gimbal stream push) needs row durations.

5. **`CopyMiddleRow` formula-preservation latent bug.** Spotted while
   editing `PlanAuthoring.bas` for the column shift. The pre-P6 version
   copied col 23 (Move time) as a value not a formula — fine then because
   the original P5 mockup didn't have a formula there, just placeholder
   text. After P6, col 17 (Fires at) IS a formula, and the original
   value-copy pattern would have copied the resolved time as a static
   value, freezing the destination row's Fires-at to the source row's
   resolved time. Fixed in `PlanAuthoring_P6.bas`: cols 13 (Step) and 17
   (Fires at) both re-write the formula on the destination row so Excel's
   relative-ref resolution applies correctly. Note for the future: any
   new formula column in the middle zone needs the same special case in
   `CopyMiddleRow`.

---

## P-sequence status update

| P  | Description                                | Status                            |
|----|--------------------------------------------|-----------------------------------|
| P1 | Sheet design + layout                      | DONE                              |
| P2 | CartLog → Cart Plan macro                  | DONE                              |
| P3 | Left-zone recompute formulae               | DONE                              |
| P4 | GimbalLog → right zone copy                | DONE                              |
| P5 | Middle-zone authoring helpers              | DONE (col-letter update pending)  |
| P6 | Anchor resolver                            | **DONE — this session**           |
| P7 | Plan push — gimbal stream                  | Not started                       |
| P8 | Plan execute (both streams)                | Not started                       |
| P9 | Live-progress display                      | Not started                       |
| P10| Plan validation                            | Not started                       |

---

## Decision log additions

| When        | Decision                                                                  |
|-------------|---------------------------------------------------------------------------|
| Day 20 / P6 | Anchor resolver implemented as live formula, not macro. Operator sees    |
|             | fire-time update instantly while authoring; no button-click refresh.     |
| Day 20 / P6 | Offset stored in a dedicated `Offset (min)` column, not parsed from      |
|             | Anchor ref. Avoids string-parse complexity; bulletproof.                 |
| Day 20 / P6 | WP # column (H) and Anchor ref (O) both use `WP0N` text convention.      |
|             | Match is string-to-string; no integer extraction.                        |
| Day 20 / P6 | Nested `IF` chain for ASTRO branch instead of `IFS`. Cross-engine        |
|             | reliability over compactness.                                            |
| Day 20 / P6 | Settings sheet astro/anchor times stored as real Excel time values, not  |
|             | strings. Removes type-coercion surprises.                                |
