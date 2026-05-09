# HyperLapse Cart — Project State

**Last updated:** 10 May 2026

This file is the handoff document between sessions. Update at the end of
every working session. Upload it with the latest `.bas` files at the
start of the next session to get straight back to productive work.

---

## System overview

A self-driving photography cart that runs an unattended overnight
hyperlapse from late afternoon through to the following morning,
automatically transitioning camera and gimbal settings through 5 phases:
daytime → sunset → astronomical night → sunrise → daytime.

### Hardware
- **Camera:** Canon EOS R3, controlled over WiFi via CCAPI v1.4.0
- **Gimbal:** DJI Ronin RS4 Pro, driven via SBUS by Arduino
- **Controller:** Arduino Uno R4 WiFi
- **Cart:** custom drive platform with steering / speed / battery telemetry
- **Operator UI:** Excel workbook on laptop, talks HTTP to both Arduino
  (gimbal + cart) and camera (CCAPI)

### Software
- **Arduino sketch:** `DJI_Ronin_UnoR4_v2` v13
  GitHub: `mwindley/DJI-Ronin-RS4-Arduino` (private)
- **Excel workbook:** `HyperLapse.xlsm`
  GitHub: `mwindley/HyperLapse-Excel` (private)

---

## Current module inventory (HyperLapse.xlsm)

| Module          | Role                                                 |
|-----------------|------------------------------------------------------|
| `Sequence`      | Master timing loop, phase handlers, replay execution |
| `Camera`        | Canon R3 CCAPI wrappers, luminance feedback loop     |
| `Gimbal`        | RS4 Pro control via Arduino HTTP                     |
| `Cart`          | Cart log retrieval, replay plan generation           |
| `Astro`         | Sun and Milky Way galactic centre angle calculations |
| `Utils`         | Shared timing, phase math, JSON, logging             |
| `BackupRestore` | Export/Import all modules to/from GitHub folder      |
| `Buttons`       | RunButton, CellFormat, AllBorder; BuildControlSheet  |

Plus: `Control` sheet has its own code module with the
`Worksheet_BeforeDoubleClick` dispatcher.

---

## What works (confirmed)

- `SystemCheck` — pings camera and Arduino
- `InitShoot` — fetches sunset/sunrise from API, computes phase
  boundaries, initialises camera to M / f1.8 / ISO100 / 1/5000
- `StartSequence` — kicks off the OnTime-driven shoot loop
- Camera fires photos on the loop
- Control sheet — 8 double-click buttons working with orange→blue
  visual feedback (yellow on error)
- Module export to GitHub via `ExportModules` macro
- Module import from GitHub via `ImportModules` macro

## What's been patched but not yet field-tested

These were fixed on 10 May 2026 and need a real overnight run (or a
fast-forward dry run with sunset set 5 minutes in the future) to
confirm they hold up:

- **Bug 1** — `WaitForCamera` is now a function that returns False if
  exposure isn't done; phase handlers gate on it via
  `If Not WaitForCamera(secs) Then Exit Sub`. Previously it was a Sub
  that mutated state but couldn't tell callers to bail out.
- **Bug 2** — `StopSequence` cancels OnTime using a new
  `g_scheduledTime` variable that records the exact time given to
  `Application.OnTime`. Previously used `g_nextShotTime` which could
  drift out from under the cancel.
- **Bug 3** — `OnPhaseEnter` hook fires the previously-orphaned
  `GimbalToSunset` / `GimbalToMilkyWay` / `GimbalToSunrise` transitions
  when the active phase number changes.
- **Bug 5** — `RunCartReplay` rewritten as `StartCartReplay` +
  `RunCartReplayStep` (OnTime-driven). No longer blocks Excel during
  cart playback.
- **Bug 7** — `CameraPut` retries up to 5 times with growing backoff on
  503 Device Busy. Critical for Phase 3 (20s exposures).

## Deferred work

- **Bug 4** — `UpdateGimbalDisplay` was identical to
  `UpdateArduinoDisplay`. Renamed to `UpdateGimbalDisplay_FUTURE` and
  parked with a comment because it's the seed of the gimbal-log replay
  feature, not actually dead code. Wire up when building that pipeline.
- **Bug 6** — `CalcLuminance` Python timeout uses
  `Application.Wait Now + TimeValue("00:00:00") + 0.0001` which is
  actually 8.6s per iteration, not the intended ~100ms. Fix when
  tackling real-time plan playback (timing is in same area of code).
- **Cart log → replay plan pipeline** — the cart-side analogue of the
  gimbal-log feature. Concept: drive the route at high speed during a
  recce pass, Arduino logs cart events, post-process into a slow-time
  plan, replay via `StartCartReplay` during the actual shoot.
- **Gimbal log → replay plan pipeline** — same idea for the gimbal.
  See "Future Work" section in `Gimbal.bas` header for full notes.

---

## Repo state

Both repos are clean, pushed, and have proper `.gitattributes` +
`.gitignore`. `HyperLapse.xlsm` is tracked as binary.

`secrets.h` has never been committed to the Arduino repo (verified
via `git log --all --full-history -- secrets.h` returning empty).

---

## Restart checklist

When opening the next session, the first message should:

1. Reference this file (upload it).
2. Upload the current `.bas` files from
   `C:\Users\mauri\OneDrive\Documents\Github\HyperLapse-Excel\Modules\`
   (or run `ExportModules` first to make sure they're current, then
   upload).
3. State what you want to work on this session.

Claude has no memory between sessions and cannot fetch private GitHub
repos. Pasting a GitHub URL gives Claude nothing — files must be
uploaded.

The `/mnt/transcripts` reference in the very first message of session 1
(10 May 2026) was empty / not populated. Don't rely on transcripts
carrying over unless that mechanism is genuinely set up.

---

## Suggested next session

Whichever of these you fancy — listed roughly in order of value:

1. **Dry-run test of the 5 bug fixes.** Set sunset to 5 minutes from
   now, run StartSequence, watch the Log sheet tick through phases
   in fast-forward. Confirms Bugs 1, 2, 3 in particular.
2. **Cart log → replay plan pipeline.** The biggest missing capability.
   Turns the rig from "fires photos on a timer" into "executes a
   planned drive."
3. **Gimbal log → replay plan pipeline.** Same idea, gimbal side.
4. **Fix Bug 6** while in the timing code anyway.
