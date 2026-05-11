# HyperLapse Cart — Project State

**Last updated:** 11 May 2026 (end of session A)

This file is the handoff document between sessions. Update at the end of
every working session. Upload it with the latest `.bas` files at the
start of the next session to get straight back to productive work.

---

## System overview

A self-driving photography cart that runs an unattended overnight
hyperlapse from late afternoon through to the following morning,
automatically transitioning camera and gimbal through 5 phases:
daytime → sunset → astronomical night → sunrise → daytime.

### Hardware
- **Camera:** Canon EOS R3, controlled over WiFi via CCAPI v1.4.0
- **Gimbal:** DJI Ronin RS4 Pro, driven via SBUS by Arduino
- **Controller:** Arduino Uno R4 WiFi
- **Cart:** custom drive platform with steering / speed / battery telemetry
- **Operator UI:** Excel workbook, talks HTTP to Arduino (gimbal + cart)
  and Canon CCAPI

### Software
- **Arduino sketch:** `DJI_Ronin_UnoR4_v2` v13
  GitHub: `mwindley/DJI-Ronin-RS4-Arduino` (private)
- **Excel workbook:** `HyperLapse.xlsm`
  GitHub: `mwindley/HyperLapse-Excel` (private)
- **Python helper:** `Python/luminance.py` in repo, requires Pillow

---

## Module inventory

| Module          | Role                                                 |
|-----------------|------------------------------------------------------|
| `Sequence`      | Master timing loop, phase handlers, replay execution |
| `Camera`        | Canon R3 CCAPI, luminance feedback, Tv lookup table  |
| `Gimbal`        | RS4 Pro control via Arduino HTTP                     |
| `Cart`          | Cart log retrieval, replay plan generation           |
| `Astro`         | Sun and Milky Way galactic centre angle calculations |
| `Utils`         | Shared timing, phase math, JSON, logging             |
| `BackupRestore` | Export/Import all modules + CheckDeclarationStyle    |
| `Buttons`       | RunButton, CellFormat, AllBorder; BuildControlSheet  |

Plus: `Control` sheet has its own code module with the
`Worksheet_BeforeDoubleClick` dispatcher (sheet code, not exportable).

---

## Working baseline (end of session A)

System runs end-to-end through all 7 phases with:
- Tv encoding correct (Canon's `0"5`, `20"` format)
- JSON properly escaped for shutter values containing `"`
- Phase transitions firing gimbal moves at correct moments
- **Non-blocking luminance pipeline** — Python runs concurrently with
  the photo cycle, harvested next iteration. Photos never blocked.
- ISO/Tv adjustment in feedback to luminance values, using operator
  target values from Settings sheet (sunset 60, sunrise 40 provisional)
- No blocking MsgBoxes in the photo loop path
- Predictive Tv/ISO step tables still in use (retired in Session B)

State at end of session A: indoor validation confirms full pipeline,
including ISO step-down from 1600 → 1250 → 1000 → 800 → 640 under
indoor saturated luminance (255 vs target 40, band [25,55]).

---

## Bugs fixed this session (session A)

| Bug | Description | File |
|---|---|---|
| Bug A — MsgBox in GimbalToMilkyWay | Modal dialog when GC below horizon blocked the photo loop for ~18s. Earlier session's "fix" targeted a different MsgBox. | Sequence.bas |
| Bug C — PollLuminanceCalc kills finished jobs | Timeout was checked before process status, terminating already-completed Python jobs that hadn't been polled yet. Reorder: status first, timeout only if still running. | Camera.bas |

---

## Bugs fixed previously (session 2)

| Bug | Description | File |
|---|---|---|
| MsgBox in GimbalToMilkyWay (different one) | Earlier MsgBox along same path | Sequence.bas |
| Tv encoding | Canon `0"5` / `20"` format, lookup from camera | Utils.bas |
| JSON escape | `"` in Tv values broke JSON body | Utils.bas, Camera.bas |
| Phase 2b/3/4a hardcoded `"20"` | Sent invalid Tv to camera | Sequence.bas |
| Thumbnail JPG parser | Camera returns JSON array, not text lines | Camera.bas |
| GetLastThumbnailLuminance invalid arg | Missing pageNum bounds check | Camera.bas |
| First-shot warm-up | "Connection terminated" on first POST | Sequence.bas |
| Application.Wait polling (Bug 6) | 8.6s per iteration killing luminance | Camera.bas |
| Luminance script discovery | Hardcoded path, missed OneDrive location | Camera.bas |
| Pillow not installed | luminance.py silently swallowed ImportError | Python env + luminance.py |
| getdata() deprecation | Pillow 14 will remove it | luminance.py |

---

## Known issues / observations (deferred)

These are real but acceptable for now. Park for later:

1. **Phase 1 first-7-shots drift** — first sequence start has ~5-6s
   intervals for shots 8-10 before settling at 2s. Camera buffer
   warming up. 5 second hiccup on a 4-hour shoot — not worth optimising.

2. **GetGimbalStatus 21-second timeout in one run** — Arduino WiFi
   hiccup. Has 3-second per-call timeout configured. Either retried
   internally or some other path. Not yet investigated.

3. **Phase 4a→4b transition int=21s residue** — when fast-forward test
   compresses the phase boundary, leftover camera write from 20"
   exposures spills into the fast-Tv phase. In a real shoot the
   Phase 4 transition takes 25-60 min, plenty of time to drain.

4. **Bug B (deferred to Session B) — Application.OnTime scheduling slip.**
   Phase 5 in the Session A fast-forward run delivered 20-21s intervals
   for 22 consecutive shots against a 2s target, then suddenly caught up.
   Not introduced by Session A. Likely fix: compute `g_nextShotTime` from
   `g_lastShotTime` consistently rather than from `Now()` after the loop's
   housekeeping has eaten variable seconds. Investigation folds naturally
   into Session B since both touch the phase handlers.

5. **Predictive Tv/ISO step tables still in use** — they work, but
   will be retired in Session B in favour of pure luminance feedback.

6. **Luminance scale 0–255** — different from previous projects.
   Operator targets set to provisional values pending outdoor calibration:
   - Sunset target: 60
   - Sunrise target: 40

7. **Indoor test runs always saturate 255** at long exposures. Real
   sunset/sunrise validation requires outdoor twilight session.

---

## Session A — complete (11 May 2026)

Non-blocking parallel luminance + operator target settings, replacing
the every-Nth gate with emergent scheduling. **Architecture: Option A
(Python-only deferral)**, decided via the benchmark phase.

### Benchmark phase — what we learned

Built a temporary `Bench.bas` harness; ran 7 tests in real-world
configuration (camera + gimbal balanced in operating position). Key
findings:

- **TakePhoto:** 137–150ms median, 200–270ms p95
- **SetShutterSpeed / SetISO:** 250–280ms median, 315–440ms p95
- **GimbalPosition (Arduino HTTP):** 168–193ms median, 230–400ms p95
- **Combined worst case (Test 7 sunset cycle):** 620ms median, 1150ms p95 — well under the 1500ms threshold for Option A

Two surprises worth recording:

1. **Arduino is fire-and-forget for /move.** Reading the sketch
   confirmed: setPosControl writes the CAN frame (~16ms) and returns;
   no wait for gimbal completion. The HTTP roundtrip cost is the only
   real cost. This means `time_for_action` on the gimbal command is
   *not* a blocking duration on the VBA side — the gimbal carries out
   the smooth move autonomously while VBA returns instantly.

2. **The interval column in the bench results was quantised to
   whole seconds** due to `Now()`'s second-only precision. The
   apparent 31s/41s intervals on 22s-target tests were a measurement
   artefact, not real inflation. Per-call timings (Timer-based,
   millisecond precision) are the trustworthy data.

### DJI SDK note discovered during benchmark phase

DJI R SDK §2.3.4.1 specifies position commands as int16_t in 0.1°
units. The 0.1° resolution is a hard floor — we can't ask for finer.
`time_for_action` is uint8_t in 0.1s units, range 0.1s–25.5s. For the
overnight hyperlapse use case (smooth gimbal motion at ~0.025°/s
during photo intervals), small `time_for_action` values (0.5s) are
correct for incremental tracking moves; large values (10–30s) only
for big phase-boundary repointings.

### Changes shipped

**Settings sheet — two new named ranges (manual edit required):**

| Named range | Default | Notes |
|---|---|---|
| `dataLumTargetSunset` | 60 | Phase 2a/2b target luminance (0–255) |
| `dataLumTargetSunrise` | 40 | Phase 4a/4b target luminance (0–255) |

If either is missing, code logs a warning at sequence start and falls
back to the default (60/40). The shoot proceeds; it just uses the
hardcoded defaults.

**Camera.bas — new module state:**

- `g_lumExec` — the running WScript.Shell.Exec object, or Nothing
- `g_lumJobJpeg`, `g_lumJobStarted` — diagnostics for the in-flight job
- `g_lastLuminance` — most recent successful value (0–255), or -1
- `g_lumStaleness` — shots elapsed since last successful measurement

**Camera.bas — new public functions:**

- `KickOffLuminanceCalc(jpegPath)` — fire Python on a local JPEG, non-blocking
- `KickOffLuminanceFromLastThumb()` — CCAPI dance + kick-off in one call
- `PollLuminanceCalc()` — returns LUM_BUSY / LUM_DONE_NORESULT / 0..255
- `GetLatestLuminance()`, `GetLuminanceStaleness()` — accessors
- `BumpLuminanceStaleness()` — called per-shot by SequenceLoop
- `ResetLuminanceState()` — called by StartSequence
- `ValidateLuminanceSettings()` — startup warning if named ranges missing
- `GetSunsetLumTarget()`, `GetSunriseLumTarget()` — read named range with default fallback
- `FetchLastThumbnailToDisk()` — extracted from old monolithic GetLastThumbnailLuminance

**Camera.bas — modified:**

- `AdjustExposureByLuminance(targetLum)` — now takes target as parameter,
  reads from `g_lastLuminance` instead of blocking fetch
- `GetLastThumbnailLuminance()` — retained as synchronous wrapper around
  the new kick-off/poll primitives. Production loop uses the primitives
  directly; this wrapper is for ad-hoc diagnostics.
- `CalcLuminance` — left in place as a legacy synchronous utility

**Sequence.bas — IsSequenceRunning accessor added** (from bench phase, kept).

**Sequence.bas — StartSequence:**
- Now calls `ResetLuminanceState` and `ValidateLuminanceSettings` at startup

**Sequence.bas — SequenceLoop reorder:**
1. Poll for ready luminance (non-blocking harvest)
2. Housekeeping (status, monitor, heartbeat) — unchanged
3. Phase handler (the photo happens here) — unchanged
4. Bump luminance staleness counter
5. Kick off next luminance measurement if phase wants it
6. Schedule next loop

**Sequence.bas — phase handlers:**
- `RunPhase2b` — calls `AdjustExposureByLuminance GetSunsetLumTarget()`
- `RunPhase4a` — calls `AdjustExposureByLuminance GetSunriseLumTarget()`
- `RunPhase2a`, `RunPhase3`, `RunPhase4b` — unchanged exposure logic.
  Luminance kick-off happens in SequenceLoop's step 5 for all of them
  (data flows for Session B calibration; no acting on it in those phases).

### What didn't change

- The predictive Tv/ISO step tables (g_phase2a_steps, g_phase4b_steps)
  remain in use. Session B retires them in favour of pure luminance
  feedback. Phase 2a and 4b still ride those tables.
- WaitForCamera, OnPhaseEnter, GimbalTo* helpers — all unchanged
- Cart replay infrastructure (StartCartReplay etc.) — unchanged
- Gimbal commands in production code still use 10s/20s/30s
  `time_for_action`. This is a placeholder until Session C's plan
  expander assigns per-row times. Per-photo incremental tracking
  moves *should* use 0.5s per the gimbal plan design.

### Validation outcome (11 May 2026)

Ran a fast-forward compressed-phase test that exercised all 7 phases in
~13 minutes, plus a steady-state Phase 4a test confirming the Bug C fix.

**Working as designed:**
- ValidateLuminanceSettings ran at startup, both targets read (60, 40)
- New luminance pipeline plumbed through end-to-end. Phase 2b/4a saw
  `lum=255 stale=0..3` lines confirming poll/kick-off/staleness logic
- Phase 4a stepped ISO down (1600 → 1250 → 1000 → 800 → 640) using
  the new `AdjustExposureByLuminance(GetSunriseLumTarget())` call
- Phase transitions fired all GimbalTo* helpers
- TIMING line includes new kickoff column
- No crashes, no orphan Python jobs, no compile errors
- Per-photo cycle: 22–27s actual vs 22s target. Steady-state overrun
  of ~1s is Bug B (deferred); within operator-stated 0–30s tolerance.

---

## Session B (next) — replace predictive tables with pure luminance feedback

- Replace predictive Tv/ISO step tables with pure luminance feedback
- BuildPhase2aSteps and BuildPhase4bSteps retired
- g_phase2a_steps and g_phase4b_steps arrays removed
- Phase boundaries become advisory only (gimbal trigger + cadence
  rule, no exposure logic dependency)
- **Fold in Bug B investigation** (Application.OnTime drift): likely
  fix is to compute `g_nextShotTime` from `g_lastShotTime` consistently
  rather than from `Now()` after housekeeping. Phase handlers are
  being touched anyway, natural place to address this.

### Cadence rule (simplification confirmed)

Photo interval becomes a function of Tv:
```
interval = roundup(Tv + 1.5s)
```

Examples:
- Tv 1/5000 → 2s
- Tv 1/8 → 2s
- Tv 1" → 3s
- Tv 17" → 19s (or 20s)
- Tv 20" → 22s

Self-limiting: at Tv=1/5000 ISO=100 in daylight, luminance saturates
above target — feedback can't make Tv slower than the lookup's longest
value. Same at Tv=20" ISO=1600 in deep night. **No special-case Phase 1
or Phase 5 code needed** — the loop naturally pins at the limits.

---

## Session C — Gimbal plan (design refined during Session A)

The Session A discussion clarified the design substantially. Locking in:

**Sparse plan (operator-authored):** Excel sheet with rows copy-pasted
from two reference sources — the GimbalLog (recorded actuals from
rehearsal) and the Astro table (computed celestial positions). Operator
edits offsets and picks an action per row. No special UI required.

**Action vocabulary (open, shaped by examples):** at minimum we need
`goto&hold` (arrive and stay), `goto&track` (arrive at a celestial
target and follow it), `goto&tracknextposition` (smooth pan between
two operator-chosen waypoints). Actions describe the expansion
behaviour, not just the row's destination.

**Expander:** Python script `Python/expand_plan.py`, same pattern as
`luminance.py`. Smoothing maths (catmull-rom or natural cubic spline)
lives here. Operator clicks "Build Plan"; VBA exports sparse rows +
dense astro lookup table to a temp file, Python returns the dense plan,
VBA writes it to the Sequence sheet.

**Astro single-sourced in VBA.** At expansion time VBA generates a
dense astro table (every 30s through the shoot) and exports it. Python
interpolates within. No duplicate celestial maths.

**Per-row `time_for_action`** set by the expander. Big initial moves
get 20–30s. Per-photo tracking steps get 0.5s. Holds emit no command.

**Executor:** generalised version of the existing `RunCartReplayStep`
pattern, walking action-prefixed rows (`GIMBAL_GOTO`, `CART_SPEED` etc).

The current `GimbalToSunset / GimbalToMilkyWay / GimbalToSunrise`
calls are **interim placeholders** — replaced by plan execution
when this lands.

`UpdateGimbalDisplay_FUTURE` in Gimbal.bas is the seed — see header
notes there.

Astronomy info (GC visibility, sunset direction) is **advisory** to
plan authoring, not commands. Operator may follow or ignore.

**Open unblockers for the next Session C session:**
1. A worked sparse-plan example from a realistic shoot
2. Confirm column layouts of GimbalLog and Astro table (so paste-as-block works)
3. Real GC arc vs smoothed approximation for Milky Way tracking (assume real, confirm)

---

## Session D — Cart plan (design refined during Session A)

Same pattern as Session C, cart movement instead of gimbal pointing.
Foundation already partly built — StartCartReplay / RunCartReplayStep
from session 1 implements the OnTime-driven plan executor pattern.

**Sparse plan source:** Arduino CartLog from a high-speed rehearsal
pass. Operator reviews the log (which contains distance information
for each turn / start / stop event), then annotates with desired
production-speed timing. This is the sparse plan.

**Expansion rules:**
- **Turns:** execute at the distance recorded in the log (no smoothing).
- **Speed changes:** no smoothing; applied at operator-chosen moment.
- **Stops:** linear smoothing via the Arduino's existing SPEED_DECAY
  (6-minute ramp to zero). The expander must back-calculate the trigger
  point so the cart actually stops at the operator's intended distance.

**Executor:** same unified walker as gimbal plan.

---

## Important architectural principles (for any future session)

1. **Photos are primary, sacred, never delayed.** Luminance
   calculations, gimbal moves, settings adjustments all happen
   "around" the photo schedule.

2. **Phase boundaries are advisory.** They mark astronomical events
   for operator reference. The actual exposure control is luminance
   feedback. Phase boundaries trigger gimbal moves (placeholder until
   Session C) and set photo cadence rule by phase.

3. **Plans (gimbal, cart) are operator-authored from logs.** Code
   provides info; operator decides creative shape; code executes
   the plan during the shoot.

4. **R3 + good card is fast.** Design for typical-case timing
   (~22s for 20" exposures, ~2s for fast). Tolerate occasional
   spikes; don't optimise for worst-case.

5. **Luminance changes per minute, not per second.** Sample sparsely,
   apply adjustments later. Stale-by-3-shots is fine.

6. **Feedback control is self-limiting.** Tv can't go slower than
   20", ISO can't go above 1600. No clamp code needed.

---

## Repo state

Files in good state (post-session-A):
- `HyperLapse.xlsm` — tracked binary, Bench sheet removed
- `Modules/*.bas` — current versions (Astro, BackupRestore, Buttons,
  Camera, Cart, Gimbal, Sequence, Utils). Camera and Sequence updated
  for Session A non-blocking luminance pipeline.
- `Modules/Bench.bas` — REMOVE FROM REPO. Was added during Session A
  benchmark phase; module removed from workbook at session A close.
  Run `git rm Modules/Bench.bas` if it's still tracked.
- `Python/luminance.py` — modernised, Pillow-based, diagnostic-friendly
- `.gitattributes`, `.gitignore` — in place

Pillow installed in user's Python environment. luminance.py confirmed
working from command line (<3s typical runtime including spawn).

---

## Restart checklist

When opening the next session, the first message should:

1. Reference this file (upload it).
2. Upload the current `.bas` files. Run `ExportModules` first to
   make sure they're current, then upload.
3. State what to work on this session — most likely Session B
   (replace predictive tables with luminance feedback, fold in Bug B fix).

Claude has no memory between sessions and cannot fetch private GitHub
repos. Pasting a URL gives Claude nothing — files must be uploaded.

---

## Suggested next session opening

```
Continuing HyperLapse Cart project — picking up Session B.

State: end of session A, 11 May 2026. Working baseline confirmed —
non-blocking luminance pipeline shipped, indoor validation confirms ISO
feedback stepping ISO down under saturated luminance. Predictive Tv/ISO
step tables still in place (Session B retires them).

This session: Session B — replace predictive Tv/ISO tables with pure
luminance feedback, fold in Bug B investigation (OnTime drift).
See PROJECT_STATE.md for full scope.

Attached: PROJECT_STATE.md, all .bas files, luminance.py.
```
