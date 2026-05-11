# HyperLapse Cart — Project State

**Last updated:** 11 May 2026 (end of session B)

This file is the handoff document between sessions. Update at the end of
every working session. Upload it with the latest `.bas` files at the
start of the next session to get straight back to productive work.

---

## System overview

A self-driving photography cart that runs an unattended overnight
hyperlapse from late afternoon through to the following morning,
automatically transitioning camera and gimbal through the night sky
from daytime → sunset → astronomical night → sunrise → daytime.

### Hardware
- **Camera:** Canon EOS R3, controlled over WiFi via CCAPI v1.4.0
- **Gimbal:** DJI Ronin RS4 Pro, driven via CAN bus by Arduino
- **Controller:** Arduino Uno R4 WiFi (Giga R1 also on hand, see Session C)
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
| `Sequence`      | Master timing loop, single RunShot handler, replay   |
| `Camera`        | Canon R3 CCAPI, luminance feedback, mode-driven walk |
| `Gimbal`        | RS4 Pro control via Arduino HTTP                     |
| `Cart`          | Cart log retrieval, replay plan generation           |
| `Astro`         | Sun and Milky Way galactic centre angle calculations |
| `Utils`         | Shared timing, phase math, Tv lookup, NextTv walker  |
| `BackupRestore` | Export/Import (in-place overwrite), CheckDeclaration |
| `Buttons`       | RunButton, CellFormat, AllBorder; BuildControlSheet  |

Plus: `Control` sheet has its own code module with the
`Worksheet_BeforeDoubleClick` dispatcher (sheet code, not exportable).

---

## Working baseline (end of session B)

System runs end-to-end with:
- **Single `RunShot` handler** replacing the seven phase-specific handlers
  (RunPhase1, 2a, 2b, 3, 4, 4a, 4b, 5). Exposure is driven entirely by
  pure luminance feedback, not by phase timing.
- **Two modes** decided by clock vs `dataAstroDusk + 30 min`:
  - **MODE_BRIGHTEN** (afternoon → night): adjustments only ever brighten.
    Tv slows first toward 20", then ISO climbs toward 1600. Lum-too-bright
    → do nothing (post fixes it).
  - **MODE_DARKEN** (night → morning): adjustments only ever darken.
    ISO drops first toward 100, then Tv speeds up toward 1/5000.
    Lum-too-dark → do nothing.
- **Monotone walks per mode**: a knob never reverses during one mode.
  Eliminates oscillation as a failure mode.
- **Photo primacy**: TakePhoto fires before any adjustment in the cycle.
  Adjust failures are caught and logged; the photo always happens.
- **Bug B clamp**: next-shot scheduling anchored off `g_scheduledTime`,
  not `Now()`, with resync + TIMING-log on slip.
- **503 retry hardening**: both CameraGet and CameraPut now retry on
  503 with body-message parsing per CCAPI spec §3.3.3. Retries only
  on transient messages ("Device busy", "During shooting or recording",
  "Out of focus", "Can not write to card"); permanent states give up
  immediately ("Mode not supported", "Live view not started" etc.).
- **Kickoff throttled**: luminance kickoff fires every 3rd cycle only,
  and BEFORE TakePhoto so its CCAPI calls land in the natural idle gap
  rather than on top of the camera's write window.

### Validation results — fast-forward bench runs

Indoor 27-shot runs through the brightening sweep showed consistent
3-second intervals. Tv walked from 1/5000 down to 1/50–1/60 over 22-23
shots; algorithm correctly idled once lum entered the deadzone band.
Zero photos missed across multiple runs. One small cadence slip per
run on average (1-2s), explained.

### The 3-second cadence floor

The shoot now runs at a steady 3-second photo interval during the
fast-Tv stretches (Phase 1 / Phase 5). The cadence rule asks for 2s
at fast Tv, but `Application.OnTime` has approximately 1-second
resolution and the loop body work (status + monitor + heartbeat +
kickoff + adjust + photo) consumes 0.5-1.5s, leaving no headroom for
Excel to schedule sub-second precisely.

This is a hard-floor architectural limit, not a bug. Software
optimisation has been exhausted on the Excel side. Long-cadence
performance (Phase 2b/3/4a at 22s, etc.) is unaffected — the 3s floor
only bites in fast daytime cadence.

**The operator's stated requirement is 2-second cadence: ~7800 photos
over the overnight shoot drive the image-stabilisation pipeline.
Small frame-to-frame changes are critical for clean stabilisation.**
Session C is the work to deliver 2s.

---

## Bugs fixed this session (session B)

| Bug | Description | File |
|---|---|---|
| Predictive Tv/ISO tables retired | g_phase2a_steps, g_phase4b_steps, BuildPhase2aSteps all gone. Phase handlers collapsed to one RunShot. | Sequence.bas |
| NextTv direction sign | Walked Tv toward 1/64000 instead of 20" when feedback wanted "slower". g_tvStrings is slow→fast so the +1 direction had to subtract from the index, not add. | Utils.bas |
| Bug B — OnTime cadence slip | Next-shot anchored off Now() instead of g_scheduledTime, so any cycle overrun shifted the schedule forward. Now anchored correctly with a Now()+interval clamp + log line on slip. | Sequence.bas |
| 503 cascade on SetShutterSpeed | Adjust call fired immediately after TakePhoto, hit 503 on every adjusting cycle, retried 3s. Adjust moved to BEFORE TakePhoto with error containment around it; photo primacy preserved via the error handler, not via call ordering. | Sequence.bas |
| 503 on kickoff GETs | Same root cause as above, on the luminance-fetch CCAPI GETs. CameraGet had no retry logic (asymmetric with CameraPut Bug 7). Added retry with shorter backoff than CameraPut. | Camera.bas |
| 503 body unparsed | Spec §3.3.3 documents nine 503 messages; only four are transient. Both CameraGet and CameraPut now parse the body's "message" field and use IsBusyRetryable() to decide retry vs give-up. Body message logged on every retry — diagnostic gold for future investigations. | Camera.bas |
| Kickoff hammering camera mid-write | Kickoff fired after TakePhoto during the camera's write window. Moved BEFORE TakePhoto so it lands in the idle gap; fetches the previous shot's thumbnail, which is fine since luminance is already 1-3 cycles stale anyway. | Sequence.bas |
| Kickoff every cycle on fast cadence | At 2-3s cycle the camera never got idle time. Throttled to every 3rd cycle (LUM_KICKOFF_EVERY_N). Matches the real-world 3-shot measurement cadence from prior shoots. | Sequence.bas |
| ImportModules rename collision | VBComponents.Remove is deferred — a subsequent Import in the same run found the name still in use and renamed incoming modules to "Camera1" / "Utils1" / "Buttons1". Rewrote ImportModules to overwrite in place via CodeModule.AddFromString, never touching the VBComponent. | BackupRestore.bas |

---

## Bugs fixed previously (session A)

| Bug | Description | File |
|---|---|---|
| Bug A — MsgBox in GimbalToMilkyWay | Modal dialog blocked photo loop ~18s when GC below horizon | Sequence.bas |
| Bug C — PollLuminanceCalc kills finished jobs | Timeout check before status check terminated finished-but-unpolled jobs | Camera.bas |

(Plus the eleven bugs from session 2 — see git history.)

---

## Known issues / observations

1. **3-second cadence floor in fast-Tv stretches** — Excel's
   `Application.OnTime` resolution + the loop work budget can't deliver
   2-second photos. This is Session C's headline task.

2. **Phase 1 first-7-shots drift** — first sequence start has ~5-6s
   intervals for shots 8-10 before settling. Camera buffer warming up.
   Not worth optimising.

3. **GetGimbalStatus 21-second timeout in one run** — Arduino WiFi
   hiccup. Has 3-second per-call timeout configured. Not yet
   investigated. Bears watching when the cadence rate increases.

4. **Phase 4a→4b transition int=21s residue** — when fast-forward test
   compresses the phase boundary, leftover camera write from 20"
   exposures spills into the fast-Tv phase. In a real shoot the
   Phase 4 transition takes 25-60 min, plenty of time to drain.

5. **CCAPI camera-busy timing investigation deferred** — the 503 body
   parsing now in place gives us per-call diagnostic data. A proper
   bench session would fire TakePhoto then poll for a "ready" status
   at 50ms intervals to build a histogram of how long the camera
   actually takes to return idle. Would feed WaitForCamera's hardcoded
   `WRITE_BUFFER = 2#` constant from data instead of guesswork.

---

## Session B — complete (11 May 2026)

Replaced predictive Tv/ISO step tables with pure luminance feedback,
folded in Bug B fix, hardened CCAPI 503 handling, and learned the
fundamental limit of Excel-as-photo-scheduler.

### Key architectural learnings

1. **Excel `Application.OnTime` has ~1-second resolution.** Whatever
   sub-second timing we ask for, it'll fire on the next whole-second
   tick after Excel is idle. The loop body cost (0.5-1.5s) plus this
   resolution makes 2-second cadence impossible to deliver reliably.

2. **The R3 returns 503 for nine distinct reasons** per CCAPI §3.3.3,
   not just "busy writing". Parsing the body message tells us exactly
   why, and which 503s deserve retries.

3. **Photo primacy beats adjustment timing.** Reordering RunShot so
   the adjust runs *before* TakePhoto (in the natural idle gap)
   removed every 503-on-SetShutterSpeed event we'd been retrying
   through. Wrapping the adjust in `On Error Resume Next` preserves
   photo primacy without needing to put TakePhoto first.

4. **Luminance staleness doesn't matter.** Lum changes per-minute, not
   per-second. Throttling kickoff to every 3rd cycle, and fetching
   the *previous* shot's thumbnail, costs us nothing.

5. **VBA's `VBComponents.Remove` is deferred** — never combine Remove
   and Import in one run. Use CodeModule.AddFromString in place.

---

## Session C — next: Arduino owns the shutter trigger

**Goal:** deliver true 2-second photo cadence by moving the photo timer
out of Excel and onto the Arduino, which has microsecond-precision
timing via `millis()` and no scheduler resolution problem.

### Hardware path

Arduino → CAN bus → Ronin RS4 Pro → Ronin fires the camera shutter.

This adds no new cables. The Ronin already has the camera control
cable; we're just adding a CAN frame to the existing Arduino-to-Ronin
bus to tell the Ronin to fire. One less cable through the gimbal
rotation point compared to a pin-8 shutter cable from Arduino to
camera directly.

**Validation needed before relying on this:**

- Confirm DJI R SDK's CAN command for "trigger shutter" (R SDK §2.x).
- Bench test: rapid shutter via CAN while gimbal is sweeping at
  several speeds. Confirm no missed frames, no Ronin command-queue
  stalls, no interaction with simultaneous gimbal position commands.
  Real-world experience says it works but we validate before shipping.

### Software split — minimal version

| Concern | Owner |
|---|---|
| Photo trigger timing | Arduino (millis()-based, precise) |
| Tv / ISO setting via CCAPI | Excel (unchanged) |
| Thumbnail fetch + luminance | Excel (unchanged) |
| Plan execution, monitor, log | Excel (unchanged) |
| Sequence start/stop | Excel commands Arduino |
| Cadence changes (Tv → 20") | Excel tells Arduino new interval |
| Shutter inhibit during Tv-change | Excel sets flag, Arduino respects |

### Proposed Arduino endpoints

- `POST /shutter/start?interval_ms=2000` — start firing every N ms
- `POST /shutter/stop` — stop
- `POST /shutter/interval?ms=22000` — change cadence
- `POST /shutter/inhibit?ms=1000` — defer next pulse (wraps SetShutterSpeed)
- `GET /shutter/status` — last-fire time, interval, inhibit state

### Excel side changes

- `RunShot` no longer calls `TakePhoto`. Arduino does it autonomously.
- `RunShot` still does: WaitForCamera (CCAPI gating only), inhibit-wrap
  + AdjustExposureByLuminance, cadence-update-to-Arduino if Tv changed
  enough to warrant a new interval.
- The whole `g_scheduledTime` / `g_nextShotTime` / Bug B clamp scaffolding
  stays for Excel's own loop, but the loop becomes leisurely (3-5s).
  Photo timing is decoupled from Excel's scheduler entirely.

### Open design questions for Session C

1. **Does Excel need a "photo fired" callback from Arduino?** Probably
   no — Excel adjusts Tv/ISO at its own pace, trusts Arduino is shooting.
2. **Inhibit duration.** SetShutterSpeed p95 ~440ms; pair Tv+ISO worst
   case ~900ms. Inhibit ~1000ms before the PUT, release after returns.
3. **Should WaitForCamera be deleted?** It exists to prevent CCAPI
   calls during the camera's write window. 503 retry now handles this.
   Reconsider whether the explicit gate is still earning its keep.
4. **What happens at exactly the strategy-switch moment?** Arduino is
   shooting at 2s, Excel decides to switch to 22s. Arduino must accept
   the new interval and apply it to the *next* pulse, not retroactively
   to one mid-fire.

### Also for Session C (validation work, lower priority)

- **Giga R1 CAN bus retry.** Previous Giga attempts failed because the
  `mbed::CAN` global constructor claims the FDCAN peripheral before
  `Arduino_CAN.begin()` runs. Documented in `DJI_Ronin_UnoR4_Diag.ino`
  header. The Uno R4 was the workaround. With this known, retry Giga
  — its 1 MB RAM could host the luminance pipeline directly (MicroPython
  on Giga can decode JPEGs), eliminating the Excel/Python round-trip
  for luminance. Aspirational; not on the critical path.
- **Validate "Arduino fires camera via Ronin" end-to-end.** Bench session
  with diag sketch, capture frame timing while gimbal moves, look for
  interaction effects.

---

## Session D — Gimbal plan (design refined during Session A)

(Unchanged — see prior PROJECT_STATE history. Brief:)

**Sparse plan (operator-authored):** Excel sheet with rows copy-pasted
from GimbalLog (recorded actuals) and the Astro table (computed
celestial positions). Operator edits offsets and picks an action.

**Action vocabulary:** `goto&hold`, `goto&track`, `goto&tracknextposition`.

**Expander:** Python script `Python/expand_plan.py`, same pattern as
`luminance.py`. Smoothing maths (catmull-rom or natural cubic spline)
lives here.

**Astro single-sourced in VBA.** Dense astro table exported at
expansion time; Python interpolates.

**Per-row `time_for_action`** set by the expander. Big initial moves
20-30s; per-photo tracking 0.5s; holds emit no command.

**Executor:** generalised version of `RunCartReplayStep` walking
action-prefixed rows.

The current `GimbalToSunset / GimbalToMilkyWay / GimbalToSunrise`
calls are **interim placeholders** — replaced by plan execution
when this lands.

`UpdateGimbalDisplay_FUTURE` in Gimbal.bas is the seed.

**Astronomy info advisory to plan authoring, not commands.**

**Open unblockers for the next Session D session:**
1. A worked sparse-plan example from a realistic shoot
2. Confirm column layouts of GimbalLog and Astro table
3. Real GC arc vs smoothed approximation for Milky Way tracking

---

## Session E — Cart plan (design refined during Session A)

Same pattern as Session D, cart movement instead of gimbal pointing.
Foundation already partly built — StartCartReplay / RunCartReplayStep
from session 1.

**Sparse plan source:** Arduino CartLog from a high-speed rehearsal.

**Expansion rules:**
- **Turns:** execute at the distance recorded in the log (no smoothing).
- **Speed changes:** no smoothing; applied at operator-chosen moment.
- **Stops:** linear smoothing via Arduino's SPEED_DECAY (6-min ramp
  to zero). Expander back-calculates the trigger point.

**Executor:** same unified walker as gimbal plan.

---

## Important architectural principles (for any future session)

1. **Photos are primary, sacred, never delayed.** Luminance
   calculations, gimbal moves, settings adjustments all happen
   "around" the photo schedule. Operator's stated requirement:
   ~7800 photos over the overnight shoot, 2s cadence in daytime,
   feeding the image-stabilisation pipeline. Small frame-to-frame
   changes are critical for clean stabilisation.

2. **Phase boundaries are advisory only.** They mark astronomical
   events for operator reference and trigger gimbal repointing.
   Exposure control is luminance feedback, not phase-driven.

3. **Plans (gimbal, cart) are operator-authored from logs.** Code
   provides info; operator decides creative shape; code executes
   the plan during the shoot.

4. **R3 + good card is fast.** 14 fps mechanical shutter indefinitely;
   the camera is never the bottleneck for cadence. The bottleneck is
   the host scheduler.

5. **Luminance changes per minute, not per second.** Sample sparsely,
   apply adjustments later. Stale-by-3-shots is fine.

6. **Feedback control is self-limiting per mode.** Tv can't go slower
   than 20", ISO can't go above 1600, monotone walks. No clamp code
   needed; the algorithm pins at the floors and stays quiet.

7. **The right job for the right device.** Excel: planning, UI,
   floating-point math, image processing. Arduino: real-time loops,
   precise timing, hardware I/O. Don't ask Excel for sub-second
   timing; don't ask Arduino for Pillow.

8. **503 is information, not just an error.** CCAPI's nine 503
   messages tell you exactly what state the camera is in. Parse
   the body, log the message, decide retry intelligently.

---

## Repo state (end of session B)

Files in good state:
- `HyperLapse.xlsm` — tracked binary, all Session B changes imported
- `Modules/*.bas`:
  - `Sequence.bas` — single RunShot handler, Bug B clamp, kickoff throttle
  - `Camera.bas` — mode-driven AdjustExposureByLuminance, 503 body parsing
  - `Utils.bas` — new CalcInterval (ceiling(Tv+1.5)), NextTv walker
  - `BackupRestore.bas` — ImportModules now overwrites in place
  - `Astro.bas`, `Cart.bas`, `Gimbal.bas`, `Buttons.bas` — unchanged
- `Python/luminance.py` — unchanged from session A
- `.gitattributes`, `.gitignore` — in place

Pillow installed in user's Python environment. luminance.py confirmed
working from command line.

---

## Restart checklist

When opening the next session, the first message should:

1. Reference this file (upload it).
2. Upload the current `.bas` files. Run `ExportModules` first to
   make sure they're current.
3. State what to work on this session — most likely Session C
   (Arduino owns the shutter trigger).
4. For Session C specifically: also upload the current Arduino
   sketch (`DJI_Ronin_UnoR4_v2.ino`) so the protocol changes can
   be designed against the real sketch state.

Claude has no memory between sessions and cannot fetch private GitHub
repos. Pasting a URL gives Claude nothing — files must be uploaded.

---

## Suggested next session opening

```
Continuing HyperLapse Cart project — picking up Session C.

State: end of session B, 11 May 2026. Session B shipped pure luminance
feedback, Bug B fix, 503 body-aware retry hardening. Steady 3-second
cadence achieved indoors but Excel's Application.OnTime resolution is
the hard floor — 2-second cadence requires Arduino to own the photo
timer.

This session: Session C — move the photo trigger to the Arduino,
firing the camera via CAN bus to the Ronin. Excel keeps CCAPI work
(Tv/ISO/luminance) but stops calling TakePhoto. Target: reliable 2s
cadence for ~7800 overnight photos.

Pre-work to validate: Arduino-via-Ronin shutter command end-to-end,
including during gimbal sweeps. Possibly retry Giga R1 with the
mbed::CAN-vs-Arduino_CAN issue documented in the diag sketch header.

Attached: PROJECT_STATE.md, all .bas files, current Arduino sketch.
```
