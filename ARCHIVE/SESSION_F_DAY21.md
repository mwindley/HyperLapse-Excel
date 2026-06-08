# Session F — P7 build (Stages 1-3), MW→GC rename, encoding cleanup

**Date:** 27 May 2026
**Continuation of:** Session E day 20 (26 May, P6 anchor resolver +
P7 design lock)
**Status:** P7 Stages 1-3 built and verified end-to-end in dry-run
against the live Plan sheet. Stage 4 (real push) deferred until
hardware reassembled. Workfront #67 Phase 1 (mw→gc rename) executed.
Plan_mockup_P7 layout brought into HyperLapse_P7.xlsm.

---

## What this session was about

Hardware (replacement SN65HVD230 + W5500) arrived but not yet
assembled. Decision: keep working the Excel Plan-authoring side
while the cart is offline. Specifically build P7 (`PushGimbalPlan`)
as the design from Session E specified — but in dry-run mode so it
can be developed and validated without a cart on the network.

Working preferences (plain-text questions one at a time, no
multi-choice, small steps with confirmation) held throughout.

---

## Working copy created

Operator created `HyperLapse_P7.xlsm` from `HyperLapse.xlsm` per
recommendation to work on a copy. All Day-21 changes landed in the
P7 copy; the original `HyperLapse.xlsm` is unchanged.

Copy strategy: Plan sheet from `Plan_mockup_P7.xlsx` was copied
into the working copy via Excel's right-click → Move or Copy → To
book → HyperLapse_P7.xlsm. Mockup sheet brought the full Session E
layout (M..AB middle zone, AD..AM right zone) plus the GP01..GP04
demo rows with verified P6 anchor resolver formulae.

---

## Settings sheet — new named ranges

Built one-shot macro `Settings_P7_Init` (module `Settings_P7_Init`)
to append the 7 named ranges Session E introduced but never wrote
into HyperLapse.xlsm:

| Name                    | Type | Seed value | Settings cell |
|------------------------|------|------------|---------------|
| dataShootStart          | Time | 15:42:00   | C49           |
| dataMWRiseTime          | Time | 22:30:00   | C52 (renamed) |
| dataMWTransitTime       | Time | 02:15:00   | C53 (renamed) |
| dataMWSetTime           | Time | 06:00:00   | C54 (renamed) |
| dataEaseJustPerceptible | Int  | 3          | C57           |
| dataEaseComfortable     | Int  | 10         | C58           |
| dataEaseCinematic       | Int  | 30         | C59           |

Append block lives at Settings rows 48-61 with section headers,
labels in col B, values in col C, comments in col D. Idempotent —
re-running InitSettingsP7 just paints "(already defined)" on each
row instead of duplicating.

Second pass (after Stage 1 design decisions) added an 8th name via
the standalone `AddPlanPushDryRunFlag` sub:

| Name                | Type | Seed   | Settings cell |
|---------------------|------|--------|---------------|
| dataPlanPushDryRun  | Bool | TRUE   | C65           |

The standalone sub was needed because re-running InitSettingsP7
would paint "(already defined)" greyed-out rows over the existing
labels. AddPlanPushDryRunFlag finds the first empty row past the
existing block (looked for two consecutive blanks for safety) and
writes only the one new name.

*Build lesson:* `"Boolean"` is NOT a valid Excel NumberFormat
string. Excel doesn't have a built-in Boolean format; the cell
just displays the value's word using General format. First attempt
of AddPlanPushDryRunFlag failed with `Unable to set the
NumberFormat property of the Range class`. Fix: don't set
NumberFormat for boolean cells, just write the value.

*Build lesson:* a half-written row from a failed setup macro left
orphan label "P7 Plan push" / "Plan push dry-run" rows at C63-64.
The succeeding run started past it at row 65. Cosmetic noise;
operator cleared the orphans manually.

---

## Existing .bas modules — found and imported

Discovery: `PlanBuilder`, `PlanAuthoring`, `GimbalLogPuller`
modules did NOT exist in HyperLapse.xlsm. Per Session E note
"HyperLapse.xlsm is at Day-19 state" but actually it was earlier —
the .bas modules from Day 19 onwards had been saved to disk but
never imported. Clean slate for the P7 import.

Three imports landed cleanly:
- `PlanBuilder_P7.bas` (350 lines)
- `GimbalLogPuller_P7.bas` (304 lines)
- `PlanAuthoring_P7.bas` (619 lines)

`Module1` and `Module2` (unnamed, pre-existing in HyperLapse.xlsm)
left alone per operator — not relevant to current work.

---

## Astro.bas — pre-existing bug surfaced

First `Debug → Compile VBAProject` after the imports failed with:

> `GetMoonGimbalAngles: argument not optional`
> `yaw = AzimuthToGimbalYaw(az)`

Astro.bas's `GetMoonGimbalAngles` was calling AzimuthToGimbalYaw
with one argument; the function requires two (`worldAzimuth`,
`cartHeading`). Pre-existing bug from a copy-paste of one of the
sun/GC sibling functions that lost the cartHeading argument. Hadn't
surfaced because nothing called GetMoonGimbalAngles until today.

Fix: rewrote GetMoonGimbalAngles to match its siblings:

```vba
Public Function GetMoonGimbalAngles(ByVal atTime As Date, _
                                     ByVal cartHeading As Double, _
                                     ByRef gimbalYaw As Double, _
                                     ByRef gimbalPitch As Double) As Boolean
    Dim az As Double, alt As Double
    GetMoonPosition atTime, az, alt
    gimbalYaw = AzimuthToGimbalYaw(az, cartHeading)
    gimbalPitch = alt
    GetMoonGimbalAngles = (alt > -5)
    LogEvent "ASTRO", "Moon at " & Format(atTime, "HH:nn:ss") & ...
End Function
```

Workbook then compiled clean.

---

## Smoke test — PlanAuthoring macros

Three macros verified against the imported Plan sheet:

1. **`AddBlankPlanRow`** — new GP05 row appended at row 11 with
   sensible defaults (Anchor type=WP, Action=Move, Rate=Cinematic
   ease, etc.). Step column formula populated, Note "(blank row)".

2. **`DeletePlanRow`** — clicked into row 11, ran macro, GP05
   removed cleanly. No leftover formatting artifacts. The Step
   formula automatically re-evaluated when adjacent rows shifted.

3. **`InsertPlanRowAbove`** — clicked into row 11, ran macro,
   existing row shifted down to row 12, new blank at row 11. Step
   formula re-applied. CopyMiddleRow's special handling of cols
   13/17/18 (Step / Fires at / Total dur — all formula columns)
   worked correctly.

`AddPlanRowFromLog`, `BuildPlanFromCartLog`, `PullGimbalLogToPlan`
NOT exercised — would need real CartLog / GimbalLog data which
operator deferred.

---

## Em-dash encoding round-trip (build lesson, recurring)

Smoke test of AddBlankPlanRow showed GP05's Ry/Rp cells displaying
`â€"` instead of `—`. Root cause: VBE exports .bas files in
Windows-1252, but the em-dash literal in source had at some point
been written by an external editor as UTF-8. Multiple round-trips
through VBE → disk → VBE compounded the corruption.

Fix pattern (now applied to PlanAuthoring.bas and PlanPush.bas):

```vba
Private Function EmDash() As String
    EmDash = ChrW(8212)
End Function
```

All `"—"` literals in code paths replaced with `EmDash()` calls.
Pure ASCII source, builds the em-dash at runtime, immune to .bas
round-trip corruption.

The encoding pattern is general — applies to any non-ASCII char in
a string literal. By end of session also applied to:
- `→` (right arrow) in Astro.bas log lines (replaced with `->`)
- `°` (degree) in Astro.bas sheet headers (replaced with Chr(176))
- `Δ` (delta) in PlanPush.bas log line (replaced with "delta")
- `—` (em-dash) in Astro.bas comments (replaced with `--`)

**Going forward:** any new string literal containing a non-ASCII
char should use ChrW (or Chr for chars below 256) at the point of
use. ASCII-only source survives every round-trip cleanly.

---

## Workfront #67 — MW → GC rename (Phase 1 done)

Raised mid-session during Stage 3 design. The Plan-level token
"mw" for the Milky Way Galactic Centre was inconsistent with the
broader meaning of "Milky Way" (whole galaxy band) and with the
existing function name `GetGCGimbalAngles` in Astro.bas.

**Scope decision (option B):** Excel operator-facing surfaces
rename to "gc". Cart wire protocol stays "mw" (the
`/settings/trackpath?obj=mw&...` parameter and the cart-side
`track_mw` C identifier are unchanged). Translation NOT needed —
AstroPush.bas's `FitAndPushTrackPath("mw", ...)` call stays as-is.

Excel rename macro `MWToGCRenamer` (module name) with public sub
`RenameMWToGC` did:

1. Renamed 3 named ranges:
   - dataMWRiseTime → dataGCRiseTime (at C52)
   - dataMWTransitTime → dataGCTransitTime (at C53)
   - dataMWSetTime → dataGCSetTime (at C54)
2. Updated 3 col-B labels: "MW core rise" → "GC rise" etc.
3. Rewrote Plan!Q6:Q9 anchor-resolver formulas:
   - `dataMWRiseTime` → `dataGCRiseTime` (and the other two)
   - String literals `"mwrise"` → `"gcrise"` (and the other two)
4. Updated Settings section header B51:
   - "Milky Way times..." → "GC (Galactic Centre) times..."

**Code-side updates (in PlanAuthoring.bas and PlanPush.bas):**

- `PlanAuthoring.AddPlanRowFromLog` heuristic outputs `"gc"` for
  astro Milky Way targets (still accepts `"mw"` or `"gc"` on input
  for back-compat with pre-rename GimbalLog rows).
- `PlanAuthoring.RebuildAnchorDV`'s ASTRO dropdown list:
  `sunset,sunrise,moonrise,moonset,mwrise,mwtransit,mwset` →
  `sunset,sunrise,moonrise,moonset,gcrise,gctransit,gcset`
- `PlanPush.IsAstroTarget` accepts both `"gc"` and `"mw"`.
- `PlanPush.EvalAstro` routes both to `Astro.GetGCGimbalAngles`.

**Phase 2 deferred:** AstroPush.bas internal VBA variable names
(`mwRiseTime`, `mwMidTime`, etc.) still use "mw" prefix.
Operator/maintainer-facing through LogEvent strings only — not
wire-protocol. Rename to `gc*` is a quiet-session task; ~20 edits
in AstroPush.bas. Adds to workfront #67 as Phase 2.

**Phase 3 deferred:** the cart-side sketch's `track_mw` C
identifier and the URL parameter `obj=mw` going to the cart. Best
done during the v2 Giga sketch port pass (workfront #47).

**Module naming gotcha:** first attempt at the rename macro used
`Attribute VB_Name = "RenameMWToGC"` + `Public Sub RenameMWToGC()`
— same name, same module. VBA compile error: "Expected variable or
procedure, not module". Fix: module renamed to `MWToGCRenamer`,
sub kept as `RenameMWToGC`. VBA allows a sub to share its name
with its module is what *I'd* expected from many languages, but
VBA doesn't.

---

## P7 build — Stages 1-3 (all green, dry-run only)

New module `PlanPush` with public sub `PushGimbalPlan`. Stages
built incrementally with smoke test after each.

### Stage 1 — skeleton

PushGimbalPlan reads `dataPlanPushDryRun` from Settings, reports
mode (DRY RUN / REAL PUSH) to Log sheet and MsgBox. No real work
yet. ReadDryRunFlag is fail-safe — missing name or unreadable
value defaults to TRUE (never surprise the operator with a real
push when intent is unclear).

*Build lesson:* `Utils.LogEvent` silently swallows any log line
starting with `=`. Excel treats it as a formula attempt, formula
fails, LogEvent's `On Error Resume Next` eats the error. Stage 1
first run showed `=== PushGimbalPlan start (DRY RUN) ===` log
entries coming through *blank*. Fix: switched prefix to `---`.
Pattern matches a PREFERENCES.md Day-9 lesson about strings
starting with `==` raising error 1004 on cell writes.

### Stage 2 — Phase 1 Validate

`Phase1Validate` walks middle zone:

**Plan-level checks** (cross-row):
- At least one populated row
- Last populated row's Action must be END
- No populated rows after the END row

**Row-level checks** (per populated row, "populated" = col N
Anchor type non-empty):
- Fires at (col Q) is numeric (= anchor resolved)
- Action (col S) is one of 6 known values (Pan Follow / Lock /
  Move / Track / Track-yaw / END)
- Target sensible for Action:
  - Pan Follow / Lock / END → Target should be blank/em-dash
  - Move → Target required (marker or astro)
  - Track / Track-yaw → Target must be sun/moon/gc
- Rate required for Move / Track / Track-yaw
- Ry/Rp required for Move (marker target only — astro targets
  compute their own endpoint)
- Track-yaw: Rp required (operator-typed absolute pitch)

**Output:** one Log entry per row that has any errors (errors
joined by semicolons within the row). Plan-level errors logged
separately. PushGimbalPlan aborts with row-count message if any
errors found.

Verified end-to-end:
- Green pass on GP01-GP04 once mockup data was clean
- Caught NO END ROW when GP04's Action was accidentally changed
- Caught "rows past END" when GP05/GP06 still populated past END
- Caught "Move: Target required" when target was deliberately
  cleared on GP03

### Stage 3 — Phase 3 Decompose

`Phase3Decompose` walks populated rows in order, emits one Log
line per row describing the cart-side artifact:

| Plan row | Log one-liner |
|---|---|
| Pan Follow | `PANFOLLOW seg, ts=T1 te=T2` |
| Lock | `HOLD seg @ current pose, ts=T1 te=T2` |
| Move (marker) | `CUBIC slew to (Y, P) [marker Tree], ts=T1 te=T2` |
| Move (astro) | `CUBIC slew to (Y, P) [astro sun @ T1+delta], ts=T1 te=T2` |
| Track | `TrackInterval mode=F obj=sun offY=X offP=Y, ts=T1 te=T2` |
| Track-yaw | `TrackInterval mode=Y obj=gc offY=X pitchAbs=Y, ts=T1 te=T2` |
| END | `END: plan ends at T1 (provides hold-tail end for previous)` |

ts = this row's Fires-at, te = next row's Fires-at.

**Astro endpoint preview (dry-run only):** for Move with astro
target, EvalAstro calls Astro.GetSunGimbalAngles /
GetMoonGimbalAngles / GetGCGimbalAngles directly, reads
`dataCartHeading` for the cart-frame transform, computes endpoint
yaw/pitch, adds row's Δyaw/Δpitch. Direct call (not
Application.Run) because Application.Run does NOT propagate ByRef
arguments — a real gotcha this session that produced wrong-but-
plausible numbers (0+Δyaw instead of astroYaw+Δyaw) until caught.

**Cubic coefficients NOT computed in Stage 3** (deferred — needs
Ease band → frames → real-world-seconds conversion which isn't
built). Stage 3 emits just endpoint + duration.

**TRACK_PLAN_MAX warning:** if intervalCount > 10, Phase 3 emits a
warning line. Hard failure would happen at Phase 4 push anyway.

**Verified end-to-end** against GP01-GP04:
```
GP01 PANFOLLOW seg, ts=15:42 te=16:30
GP02 TrackInterval mode=F obj=sun offY=0.0 offP=0.0, ts=16:30 te=17:15
GP03 CUBIC slew to (55.0°, 19.2°) [astro sun @ 17:15+delta], ts=17:15 te=19:15
GP04 END: plan ends at 19:15
Phase 3 OK: 2 plan segment(s), 1 TrackInterval(s)
```

Sun position at 17:15:28 in Adelaide computes to yaw=25.0°, pitch=-0.8°
(0.8° below horizon — about right for ~30 min before astronomical
sunset at 17:42). GP03's Δyaw=30, Δpitch=20, giving endpoint
(55.0°, 19.2°). Math validated against expectation.

---

## What's NOT done (Stage 4 deferred)

Stage 4 = Phase 4 POST + Stage 5 polish:

- Ping cart `/status` before any push; abort cleanly if no
  response
- Sequential GETs to:
  - `/plan/load?seg=N&...` for HOLD/CUBIC/PANFOLLOW segments
  - `/trackplan/load?idx=N&ts=&te=&obj=&mode=&oy=&op=` for
    TrackIntervals
  - `/settings/trackpath?obj=mw&...` for cubic coefficients (if
    not already loaded — Phase 2 check)
- Phase 5 summary improvements
- Possibly: real cubic coefficient computation (lift from
  AstroPush's FitCubic) for full-fidelity dry-run preview

Blocked by hardware reassembly (replacement SN65HVD230 + W5500
arrived but not yet wired in). Cart not on the network. Stage 4
needs at least a `/status` endpoint reachable to test the ping
path.

When hardware is back, smoke test sequence for Stage 4:
1. `dataPlanPushDryRun=FALSE`
2. Cart off — run `PushGimbalPlan`, expect graceful abort with
   "cart unreachable" message
3. Cart on — run `PushGimbalPlan`, expect all 4 phases to fire
4. Verify on cart side: `/cartlog/get`, `/gimballog/get`, or
   whatever the right inspection endpoints are
5. Side-by-side dry-run vs real-push of the same plan to confirm
   the same artifact set is reported

---

## Smoke testing left undone (operator deferred)

Need real CartLog / GimbalLog data, so deferred:
- `BuildPlanFromCartLog` — left zone seeding
- `PullGimbalLogToPlan` — right zone seeding
- `AddPlanRowFromLog` — middle-zone seeding from right-zone selection

Plus from in-session observation:
- Plan sheet Target column (col T) dropdown is wrong — currently
  showing Rate options (Imperceptible / Cinematic ease / Fast /
  Snap / Computed). Should show marker labels + sun/moon/gc. Logged
  as future workfront candidate: a `RebuildTargetDV` helper
  analogous to RebuildAnchorDV, plus a `FixAllPlanDVs` walker.

---

## Files produced this session

In chat outputs:
- `Settings_P7_Init.bas` — 7 named ranges init + AddPlanPushDryRunFlag
- `PlanAuthoring.bas` — EmDash fix + #67 Phase 1 rename
- `PlanPush.bas` — Stages 1-3 of P7
- `MWToGCRenamer.bas` — one-shot rename macro (module name
  differs from sub name to avoid collision)
- `Astro.bas` — encoding cleanup (arrow + degree fixes)
- `SESSION_F_DAY21.md` — this file

In HyperLapse_P7.xlsm (working copy):
- Plan sheet (from mockup)
- Settings sheet — 8 new named ranges + section blocks rows 48-65
- VBE modules: PlanBuilder, PlanAuthoring, GimbalLogPuller,
  Settings_P7_Init, PlanPush, MWToGCRenamer (+ pre-existing
  modules)
- Astro module: GetMoonGimbalAngles fixed + log strings cleaned

---

## Next session candidates

**A) Update PROJECT_STATE.md and WORKFRONTS.md properly.** Fold
SESSION_E + SESSION_F into the canonical docs. ~30 min sit-down.
Worth doing soon while context is loaded.

**B) Stage 4 design work.** Sketch the POST machinery + ping
logic. Can be designed without hardware; build can start; smoke
test waits for cart.

**C) Tangential cleanups while waiting on hardware:**
- `RebuildTargetDV` helper + `FixAllPlanDVs` (the bad dropdown
  observed today)
- Workfront #67 Phase 2 (AstroPush.bas internal variable rename)
- Pano action vocabulary (still unresolved per SESSION_E open
  questions)
- "Refresh marker poses" macro (SESSION_E deferred)
- Ease band → real-world duration formula (SESSION_E deferred)

**D) Real-data smoke tests.** If operator can populate CartLog +
GimbalLog with recon data (real or simulated via WobblyRecon),
exercise BuildPlanFromCartLog / PullGimbalLogToPlan /
AddPlanRowFromLog end-to-end.

---

## Notes for future Claude

1. **HyperLapse_P7.xlsm is the working copy from Day 21 onwards.**
   Original HyperLapse.xlsm is unchanged from pre-session. If
   operator brings up "HyperLapse.xlsm", clarify which file —
   they may have promoted P7 to canonical by then, or they may
   still be running parallel copies.

2. **#67 Phase 1 done means "gc" is the new operator-facing
   token.** Anchor ref dropdown values are gcrise/gctransit/gcset.
   Named ranges are dataGC*. Plan sheet column T target dropdown
   should offer sun/moon/gc (and marker labels). AstroPush still
   uses "mw" on the wire; PlanPush.EvalAstro accepts both "gc" and
   "mw" defensively.

3. **PlanPush dry-run is the safe default.** `dataPlanPushDryRun`
   defaults TRUE; ReadDryRunFlag returns TRUE on any error/missing
   name. Operator must explicitly flip it FALSE to push for real
   (and Stage 4's ping-first check is the second safety net).

4. **ASCII-only string literals in all .bas files going forward.**
   Use Chr(176) for °, ChrW(8212) for —, "-" or "->" for arrows,
   "delta" for Δ. Anything non-ASCII in a string literal WILL get
   mangled across VBE export/import. Comments survive (no
   compilation, no execution), so comment glyphs are fine.

5. **`Application.Run` strips ByRef.** Always call cross-module
   functions directly when ByRef out-parameters matter. EvalAstro
   was the Day-21 worked example. Add to build lessons.

6. **`Step` is a VBA reserved-ish word.** Don't use it as a local
   variable name. Renamed `step` → `stepLabel` in Phase3Decompose
   prophylactically.

7. **Module name ≠ sub name.** If a module has `Attribute VB_Name
   = "Foo"` and a `Public Sub Foo()`, VBA can't disambiguate.
   Module name should differ from the sub's name. MWToGCRenamer
   was the Day-21 worked example.

---

## Future tasks raised this session (outside today's work)

**Competitive landscape check.** Look up motion-control timelapse
cart / motorised slider / gimbal-cart products and DIY projects on
the internet. Goal: confirm whether anyone else is doing what this
project does — long-duration sunset+sunrise timelapse with cart
motion + gimbal Plan synthesis + recon-driven plan authoring +
exposure walk + LIVE/TABLE fallback architecture. Operator's prior
is "probably not much like it" but worth verifying. Influences:
positioning if it ever goes public; spotting good ideas from
elsewhere; sanity-checking that architecture decisions taken were
genuinely the best ones available.

Suggested search angles: "motorised timelapse slider", "gimbal
slider sunset to sunrise", "Canon CCAPI cart automation", "Arduino
timelapse motion control", "DJI Ronin slider integration". Worth
looking at: Edelkrone, Syrp Genie, Rhino Slider, eMotimo, Dynamic
Perception. Plus Reddit r/timelapse and r/MotionControl, DIY logs
on YouTube, Cinematography Mailing List archives.

**Design/project summary write-up.** A short, written summary of
what the project actually IS — for sharing, for memory, for
grant/competition/portfolio purposes if any of that ever comes up.
Not a technical doc (PROJECT_STATE.md plays that role), but a 1-2
page narrative covering:

- The problem: long-form timelapse over sunset-to-sunrise with
  continuous cart motion and gimbal moves, photo reliability
  sacred, exposure walk through the daylight-twilight-darkness
  transition
- The architecture: Excel as the authoring + recon-replay layer,
  Arduino cart as the timing-critical executor, Canon R3 via CCAPI
  for camera control + pin-8 fallback, DJI RS4/R3 gimbal via DJI
  CAN protocol
- The unique pieces: recon-then-replay (drive the path manually,
  then have the cart re-execute precisely), three-phase exposure
  (CCAPI live-view luminance + table fallback + intervalometer
  fallback), gimbal Plan vocabulary, astro-aware (cart tracks
  sun/moon/GC through their predicted paths)
- The current state: working production v1 on Uno R4 WiFi, Giga R1
  v2 sketch ported and validated, P-sequence Excel Plan authoring
  being built right now
