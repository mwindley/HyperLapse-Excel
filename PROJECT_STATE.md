# HyperLapse Cart — Project State

**Last updated:** 10 May 2026 (end of session 2)

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

## Working baseline (end of session 2)

System runs end-to-end through all 7 phases with:
- Tv encoding correct (Canon's `0"5`, `20"` format)
- JSON properly escaped for shutter values containing `"`
- Phase transitions firing gimbal moves at correct moments
- Luminance pipeline working — real numbers (0-255) flowing through
- ISO/Tv adjustment in feedback to luminance values
- No blocking MsgBoxes
- Per-shot overhead in night phases ~800ms (was 9000ms pre-session)

State preserved on GitHub at commit `a31cd55` (10 May 2026).

---

## Bugs fixed this session (session 2)

| Bug | Description | File |
|---|---|---|
| MsgBox in GimbalToMilkyWay | Blocked shoot if GC below horizon | Sequence.bas |
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

Also added: timing instrumentation in SequenceLoop, declaration-style
checker, photo-line log format with `int=` interval column, log
timestamps showing seconds.

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

4. **Predictive Tv/ISO step tables still in use** — they work, but
   will be retired in Session B in favour of pure luminance feedback.

5. **Luminance scale 0–255** — different from previous projects.
   Operator targets need re-calibration. Provisional starting values
   for Session B (subject to outdoor calibration):
   - Sunset target: ~50–80
   - Sunrise target: ~30–60

6. **Indoor test runs always saturate 255** at long exposures. Real
   sunset/sunrise validation requires outdoor twilight session.

---

## Session A (next, revised scope)

Original Session A was "add settings + every-Nth gate." Mid-session
discussion clarified the architecture and merged Session A with what
was previously Session C.

**Revised Session A scope: non-blocking parallel luminance + operator
targets, replacing the every-Nth gate with emergent scheduling.**

Operator priority — explicitly stated:
> "Taking the photo is always priority. Calculation runs in parallel
> over 3 photos. Adjustments may be 0-30 seconds late from predicted
> time, that is fine."

### What to build

1. **Settings sheet additions** (2 new named ranges):
   - `dataLumTargetSunset` (default ~60)
   - `dataLumTargetSunrise` (default ~40)
   - (No `dataLumSampleEvery` — emergent, not configured)

2. **Camera.bas — non-blocking luminance:**
   - Module-level state: `g_luminanceJob` (running exec object or Nothing),
     `g_lastLuminance`, `g_lumStaleness` (shots since last update)
   - New `KickOffLuminanceCalc(jpegPath)` — non-blocking start
   - New `PollLuminanceCalc()` — checks status, returns
     BUSY / READY+value / DONE_NORESULT
   - Old blocking `GetLastThumbnailLuminance` retired or wrapped

3. **Sequence.bas — loop reorder:**
   - Each loop iteration:
     1. Poll for ready luminance result, store if ready
     2. Take photo (non-negotiable, never blocked)
     3. Schedule next iteration
     4. If no Python job running and current phase wants luminance,
        kick off new measurement (uses last-saved thumb, fire-and-forget)
   - Phase handlers consume `g_lastLuminance` (most recent value),
     don't wait for fresh measurement

4. **Phase logic update:**
   - Phase 2a/2b: feedback toward sunset target
   - Phase 3: optional measurement, no acting
   - Phase 4a/4b: feedback toward sunrise target

### Key principle for Session A

**Photos are sacred.** Adjustments are best-effort. Adjustments may be
applied 1-3 photo-cycles after the luminance reading they're based on,
which is fine because luminance changes per-minute, not per-second.

---

## Session B (after Session A)

- Replace predictive Tv/ISO step tables with pure luminance feedback
- BuildPhase2aSteps and BuildPhase4bSteps retired
- g_phase2a_steps and g_phase4b_steps arrays removed
- Phase boundaries become advisory only (gimbal trigger + cadence
  rule, no exposure logic dependency)

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

## Future sessions

### Session C — Gimbal Plan (separate large feature)

Operator workflow:
1. Rehearsal pass at high speed with cart and gimbal
2. Operator marks waypoints in `GimbalLog` via UI button
   ("mark current gimbal position to log")
3. Post-process log into a slow-time plan on a sheet
4. During real shoot, plan executor runs alongside SequenceLoop,
   issuing GimbalPosition commands at planned times

The current `GimbalToSunset / GimbalToMilkyWay / GimbalToSunrise`
calls are **interim placeholders** — replaced by plan execution
when this lands.

`UpdateGimbalDisplay_FUTURE` in Gimbal.bas is the seed — see header
notes there.

Astronomy info (GC visibility, sunset direction) is **advisory** to
plan authoring, not commands. Operator may follow or ignore.

### Session D — Cart Plan (parallel to Gimbal Plan)

Same pattern, cart movement instead of gimbal pointing. Foundation
already partly built — StartCartReplay / RunCartReplayStep from
session 1 implements the OnTime-driven plan executor pattern.

Operator workflow:
1. Drive recce pass at speed; Arduino logs cart events to CartLog
2. Post-process into slow-time replay plan on Sequence sheet
3. Plan executor walks the rows during shoot

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

Both repos clean, pushed. Last commit: `a31cd55`.

Files in good state:
- `HyperLapse.xlsm` — tracked binary
- `Modules/*.bas` — current versions (Astro, BackupRestore, Buttons,
  Camera, Cart, Gimbal, Sequence, Utils)
- `Python/luminance.py` — modernised, Pillow-based, diagnostic-friendly
- `.gitattributes`, `.gitignore` — in place

Pillow installed in user's Python environment. luminance.py confirmed
working from command line.

---

## Restart checklist

When opening the next session, the first message should:

1. Reference this file (upload it).
2. Upload the current `.bas` files. Run `ExportModules` first to
   make sure they're current, then upload.
3. State what to work on this session — most likely Session A
   (non-blocking parallel luminance + operator targets).

Claude has no memory between sessions and cannot fetch private GitHub
repos. Pasting a URL gives Claude nothing — files must be uploaded.

---

## Suggested next session opening

```
Continuing HyperLapse Cart project — picking up Session A.

State: end of session 2, 10 May 2026. Working baseline confirmed —
luminance pipeline functional, all infrastructure bugs fixed, predictive
control still in place.

This session: Session A — non-blocking parallel luminance + operator
target settings. See PROJECT_STATE.md for full scope.

Attached: PROJECT_STATE.md, all .bas files, luminance.py.
```
