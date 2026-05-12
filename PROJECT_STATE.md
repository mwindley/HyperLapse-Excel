# HyperLapse Cart — Project State

**Last updated:** 12 May 2026 (end of Session C day 3 — exposure walk in service, Tv/ISO autonomy on cart, all Session C core deliverables complete)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

---

## ⚠️ Top-of-file context — Session C day 3 outcomes

### Exposure walk shipped — Tv/ISO autonomy on cart

Day 3 ports `AdjustExposureByLuminance + NextTv + NextISO` from Excel
`Camera.bas` / `Utils.bas` to the Arduino. The cart now owns exposure
control end-to-end: read luminance via CCAPI live view → walk Tv/ISO
one step toward target → PUT to camera via CCAPI → update local state.

**Committed at `331d242`.** Validated on real hardware:

| Test | Result |
|---|---|
| E1 — `/exposure/init` loads Tv/ISO from camera | PASS (matched camera display) |
| E2 — `/exposure/state` returns walk state JSON | PASS (all fields correct) |
| E3 — Walk with no luminance available | PASS (returns `reason:"no_luminance"`, no PUT) |
| E4 — BRIGHTEN walk, real PUT | PASS (Tv 1/20 → 1/15, camera confirmed) |
| E5 — DARKEN walk, real PUT | PASS (Tv 1/15 → 1/20 → 1/25, two walks correct) |

Day 2's pin-8 architecture and RAW-only buffer fix remain in service
(commits `71f62c2` and `a2ccca1` from yesterday). Total Session C state:

| Commit | Subject |
|---|---|
| `331d242` | Exposure walk (Tv/ISO via CCAPI PUT) |
| `a2ccca1` | RAW-only buffer fix (5120 → 6144) |
| `71f62c2` | Pin-8 owns shutter (CAN shutter retired) |
| `ffe7dce` | (Day 1 — luminance + resilience plumbing) |

### What's NOT done yet (deferred to next session)

- **Auto-trigger of walk from luminance fetch path.** Currently the walk
  is manual-endpoint-only. Wiring it to run automatically after every
  successful luminance fetch is the next step — estimated ~3 lines of
  code. Stage 2 of the two-stage plan.
- **Deliberate WiFi drop test** — resilience layer caught a real outage
  today (`live view RECOVERED after 5 attempts`) but a controlled drop
  test still pending.
- **Excel-side changes** — Excel should stop firing TakePhoto, stop
  calling CCAPI directly, and poll the new cart endpoints instead.
- **Cleanup commit** — `cameraShutter()` dead-code function definition
  still present; removable.

### R3 WiFi-profile drop — incident #4 observed

Camera power-cycled today (battery saving), self-cleared battery
warning on restart, came up with no WiFi profile selected. Recovery
procedure (SET3 reselect) worked. **First incident with a clear
trigger: camera power cycle.** The earlier three drops had unclear
triggers; this one didn't.

Operational implication unchanged: operator should not need to
power-cycle the camera during a shoot. Pin-8 architecture means cart
keeps shooting through any camera WiFi loss; only luminance and
exposure updates pause until SET3 is reselected.

### Resilience layer demonstrated in production-like conditions

During today's E4-prep mode-3 run, live view initially failed to start
(camera was in some transient state) and the cart entered the retry
loop. After 5 retries (~2.5 minutes), live view came up and luminance
started flowing normally: `[lum] live view RECOVERED after 5 attempts`,
then steady `[lum] mean=66 photos=N` lines. The cart kept firing
photos via pin-8 throughout. **This is the first observed real-world
fire of the resilience plumbing**, and it behaved exactly as designed.

### Recovery procedure for R3 WiFi drop (when it does happen)

1. Camera menu → wireless settings
2. Cycle through saved profiles: SET1, SET2, SET3
3. Re-select **SET3 = "Rosedale CCAPI"**
4. Green WiFi light should come on immediately
5. Verify with `http://192.168.1.99:8080/ccapi` in browser

---

## System overview

Self-driving photography cart for unattended overnight hyperlapse from
late afternoon → sunset → astronomical night → sunrise → daytime.

### Hardware

- **Camera:** Canon EOS R3 via CCAPI v1.4.0 over WiFi
- **Gimbal:** DJI Ronin RS4 Pro, driven via CAN bus (for motion only;
  shutter no longer goes through it)
- **Controller (production):** Arduino Uno R4 WiFi
- **Controller (backup, on shelf):** Arduino Giga R1 WiFi — dual-core
  STM32H747. CAN proven working (RX + TX). Future-headroom option only.
- **Cart:** custom drive platform
- **Camera shutter path:** Arduino pin 8 → cable → R3 remote shutter port
  (WiFi-independent)
- **Operator UI:** Excel workbook (van) + cart's HTTP server (phone)

### Network in the field

- Excel laptop in the van (not portable to cart)
- **Wavlink AX6000 #1 in the van**
- **Wavlink AX6000 #2 in the field**, battery-powered, 50–100 m from van
- Phone connects to the same WiFi as cart and Excel
- Cart-to-Excel WiFi is **non-critical during the shoot** — see WiFi
  windows below.

### Software

- **Arduino sketch (production):** `DJI_Ronin_UnoR4_v2` on
  `session-c-uno-luminance` branch
- **Excel workbook:** `HyperLapse.xlsm`
- **Python helper:** `Python/luminance.py` — **slated for retirement**
  once Session C is complete (replaced by Arduino histogram fetch)

### Camera details (R3) for next session

- **CCAPI base URL:** `http://192.168.1.99:8080/ccapi`
- **Live view start:** `POST /ccapi/ver100/shooting/liveview` with body
  `{"liveviewsize":"small","cameradisplay":"on"}`
- **Histogram fetch:** `GET /ccapi/ver100/shooting/liveview/flipdetail?kind=info`
  — binary response with `FF 00 01` header + 4-byte size (big-endian) + JSON
  + `FF FF` end marker. JSON contains `liveviewdata.histogram[0]` = 256
  ints (Y channel). **RAW-only mode returns ~5.3KB; RAW+JPEG ~4.5KB.**
  Code now sizes buffer for the RAW-only case.
- **Live view stop:** `DELETE /ccapi/ver100/shooting/liveview/scroll`
  (NOT `/liveview` — that returns 405)
- **Stop call can return 503 (camera busy)** — observed today. Treat as
  transient; live view typically still gets cleaned up on camera side.
- **Tv GET/PUT:** `GET / PUT /ccapi/ver100/shooting/settings/tv`
  - GET returns `{"value":"<canon>","ability":[...]}` — value extracted
    via `parseCcapiValue()`. Decodes `\/` and `\"` escapes.
  - PUT body: `{"value":"<canon>"}` — Canon's seconds-symbol `"` must
    be JSON-escaped to `\"`. Done by `jsonEscapeTv()`.
  - Cart GET-once at `/exposure/init`; PUT on every walk step.
- **ISO GET/PUT:** `GET / PUT /ccapi/ver100/shooting/settings/iso`
  - Same shape. ISO values are plain digit strings; no escaping needed.
- **503 retry policy** for Tv/ISO PUTs: 5 retries, 3s initial backoff,
  1.5× growth (max ~33s worst-case wait). Matches `CameraPut` in
  `Camera.bas`. Busy-message-aware via `isBusyRetryable()`.

---

## Today's deliverables — what's committed and what's verified

### Branches on GitHub (`mwindley/DJI-Ronin-RS4-Arduino`)

| Branch | Contents | Status |
|---|---|---|
| `main` | Uno R4 v13 production sketch | Stable, behind by Session C work |
| `session-c-giga` | Giga TX test sketch | Parked — Giga CAN proven, not the path forward |
| `session-c-uno-timer` | Mode 3 photo timer (CAN-shutter era) | Superseded by `session-c-uno-luminance` |
| `session-c-uno-luminance` | **Current head** — pin-8 shutter, mode 3 timer, CCAPI luminance, WiFi resilience, RAW-only buffer, **exposure walk (Tv/ISO via CCAPI PUT)** | All work below committed and pushed |
| `session-c-liveview-test` | One-shot coexistence test sketch | Archived — not for merge |

The `session-c-uno-luminance` branch is the cumulative head of Session C
work. Three commits today on top of yesterday's `ffe7dce`:

| Commit | Subject |
|---|---|
| `331d242` | Session C day 3: exposure walk — Tv/ISO control via CCAPI PUT |
| `a2ccca1` | Session C: bump LUM_RESP_BUF_SIZE 5120 to 6144 for RAW-only payloads |
| `71f62c2` | Session C: pin-8 owns shutter; CAN shutter retired |
| `ffe7dce` | (previous head — yesterday's luminance + resilience work) |

### What's verified (cumulative across Session C)

✅ Architectural reframe (Excel out of critical path, cart owns shoot)
✅ Giga CAN bus (RX + TX) — kept as future-headroom backup
✅ CCAPI histogram endpoint — works as documented
✅ Live view + histogram fetch path — clean operation in RAW-only mode
   with 6KB buffer
✅ Mode 3 photo timer **end-to-end via pin-8** — Test 2 22-photo and
   Test 4 311-trigger / 308-card runs (99% delivery)
✅ Pin-8 single-shot via `/shutter` and `/shutter/pin8` endpoints —
   photo on card, red LED ✓
✅ Live view + pin-8 shutter coexistence — proven by Test 4
✅ Buffer-overflow bug fix validated by 10-min full-op test
✅ Resilience layer absorbs transient CCAPI failures (~10% transient
   failure rate at 2s cadence with mode 3, never crossed 3-in-a-row
   threshold during Test 4)
✅ Camera WiFi profile holds through full-operation CCAPI traffic
   (Test 4, but see drop-history note above — single-run negative is
   not the same as proof)
✅ **Exposure walk end-to-end** — `/exposure/init`, `/exposure/state`,
   `/exposure/target`, `/exposure/walk` all working; both BRIGHTEN and
   DARKEN modes confirmed walking the right direction; Tv PUT verified
   against camera back-screen; JSON escaping of Canon `"` works;
   ladder math correct in both directions
✅ **Resilience caught a real outage during day-3 testing** —
   `[lum] live view RECOVERED after 5 attempts` then steady fetches.
   First production-like fire of the resilience plumbing.

### What's NOT verified

❌ Resilience behaviour under deliberate WiFi drop (a real outage was
   recovered today, but a controlled drop/recover test hasn't been
   forced)
❌ Walk auto-trigger from luminance fetch path (walk only fires via
   manual endpoint — Stage 2 of two-stage plan)
❌ Walk deadzone branch (luminance within ±DEADZONE of target — the
   "no action needed" path); implicit from BRIGHTEN E3 but not
   explicitly exercised
❌ Excel-side changes — not started

### What's been retired

- CAN-via-Ronin shutter (`cameraShutter()` still exists as a function
  definition but no execution path calls it; will be removed in a future
  cleanup commit)
- Deprivation test toggle (used Session C day 2, stripped before commit
  `a2ccca1`)

---

## The architecture — two ends and a phone

### Excel (van laptop) — the planning end

What it's good at: tables, cut-and-paste, save copies, what-if edits.
**The operator's creative workspace.**

Phases:
- **Pre-shoot:** author cart and gimbal plans from logs; compute astro
  tables; upload plans to cart
- **During shoot:** monitor cart via HTTP polls; intervene if needed;
  raise alarms. **Not on the critical path.**
- **Post-shoot:** retrieve logs; analyse with pivot tables/charts;
  plan next shoot

### Cart (Arduino Uno R4) — the hardware reliability end

What it's good at: deterministic timing, hardware loops, CAN, motors.
**The shoot runtime.**

Owns (post-Session-C day 3):
- Photo trigger timing (mode 3 via pin-8 — **validated**)
- Single-shot trigger via pin-8 — **validated**
- Luminance fetch via CCAPI histogram (validated, RAW-only safe)
- Resilience under transient CCAPI failure (validated, including real
  recovery from a live-view start outage)
- **Exposure walk (Tv/ISO via CCAPI PUT) — validated end-to-end**
- Auto-trigger walk from luminance fetch — not yet wired (next session)
- Phase clock + gimbal repointing (later)
- Gimbal and cart plan execution (Sessions D/E)
- Shoot-time logging

**Once a plan is loaded and the shoot starts, the cart needs nothing
from Excel until the shoot ends.** WiFi outage during plateau is harmless.
Camera WiFi outage during plateau is now also harmless for photo cadence
(pin-8 keeps firing); only luminance updates freeze.

### Phone (cart's HTTP server) — the field interface

- Prep mode: drive cart, capture cart-log and gimbal-waypoint data
- Walk-outs at 2am: check status, exposure, alarms
- **Emergency stop** — first-class requirement
- Scope is "as is" — no expansion needed for Session C

---

## Guiding principle — overrides everything

**No photo is fatal. A wrong-exposure photo is fixable in post.**

1. **Take the photo, always.** Cadence is sacred.
2. **Try to get the right exposure.** Luminance feedback walks Tv/ISO.
3. **If exposure adjustment fails, take the photo anyway.** Post-edit
   fixes wrong exposure; nothing fixes a missed photo.

Migration ordering:
- **Critical:** photo trigger autonomous on cart ✅ (done — pin-8)
- **Nice-to-have:** Tv/ISO + luminance autonomous on cart ✅ (done — walk
  works on manual endpoint; auto-trigger from fetch path is the small
  follow-up)
- **Convenience:** plan execution autonomous on cart

---

## Operator reality — the lens for all design

- Cart 50–100m from van, day and night
- Operator walks out with phone. Excel laptop stays in van.

### The operator's overnight

- **Pre-shoot to ~21:00** — up watching the sunset transition (rapid
  Tv/ISO changes). Alarms armed.
- **~21:00 to ~05:00** — sleeping. Shoot on plateau (Tv 20" ISO 1600,
  22s cadence, nothing changes). **Alarms should be silent.** WiFi drop
  here is harmless. Camera WiFi drop here is now also harmless for
  cadence (exposure frozen at last good).
- **~05:00 to ~07:00** — up watching sunrise transition.

### Alarm-quality is the migration lens

Each step kills a class of alarm:
- Move photo trigger to cart → kills "missed photo" on WiFi drop ✅ (done)
- Move Tv/ISO + luminance to cart → kills "exposure adjust failed"
  ✅ (done — walk validated on manual endpoint; auto-trigger pending
  but the autonomy is in place)
- Move plan execution to cart → kills "Excel/Python round-trip"

### WiFi-criticality windows

- **Daytime / fast-Tv stretches:** 2s photos, frequent Tv changes. WiFi
  drop costs photos today. Post-Session-C: fully autonomous.
- **Sunset/sunrise transitions (~1 hour each):** rapid Tv/ISO changes
  via luminance feedback. WiFi drop costs wrong exposures today.
  Post-Session-C: no impact.
- **Astronomical night plateau (~10 hours):** nothing changes. Already
  harmless on WiFi drop.

Total WiFi-critical hours today: ~2. Session C removes that.

---

## Session C — current goal and what's left

### Goal (revised during discussion)

**Move photo trigger + luminance + Tv/ISO control from Excel to the
Uno R4.** Excel stops calling `TakePhoto`, stops running Python+Pillow,
stops calling CCAPI directly. Arduino does all of it.

### Why Uno R4, not Giga (key reframe)

CCAPI exposes a histogram directly. Mean luminance = `sum(i*Y[i])/sum(Y[i])`.
No JPEG decode needed. JPEG decode in MicroPython was the original
justification for Giga; it no longer applies. Uno R4 has the memory and
CPU for the simpler path. Giga is preserved as future-headroom backup.

### Session C deliverables — status

| # | Deliverable | Status |
|---|---|---|
| 1 | Mode 3 photo timer with /shutter/start, /stop, /interval, /pause, /resume, /status | **Validated end-to-end via pin-8** (Test 4: 311 triggers, 308 photos on card, 99% delivery) |
| 2 | CCAPI HTTP client + histogram fetch + /luminance endpoint | **Validated in RAW-only mode** with 6KB buffer (Test 4: stable mean=94-95 across ~150 fetches, ~10% transient failures absorbed by resilience layer) |
| 2b | WiFi resilience (retry on connection failure) | **Validated** — caught a real outage during day-3 testing, recovered after 5 retries, photo cadence uninterrupted |
| 3 | Tv/ISO walk + CCAPI Tv/ISO PUTs | **Validated end-to-end via manual endpoint** (E4 BRIGHTEN, E5 DARKEN, both PUT-verified against camera back-screen). Auto-trigger from fetch path is the small Stage-2 follow-up |
| 4 | Excel-side changes (stop firing, stop fetching, poll cart) | **Not started** |

### Suggested next-session work, in order

1. **Wire walk to auto-fire from luminance fetch** (Stage 2 of two-stage
   plan). After every successful fetch of `lum_last_value`, call
   `adjustExposureByLuminance()` with stored `lum_target` and `lum_mode`,
   PUT if action returned. Estimate ~3-10 lines of code. The walk's
   own deadzone logic naturally throttles PUTs to real-need rate (~1/min
   in production), even though it evaluates every 6s.
2. **Long soak with walk auto-firing** (30-60 min) — full system
   running, verified by card-file count. Watch luminance + walks
   produce sensible exposure trajectory over the run.
3. **Deliberate WiFi drop test** — turn off camera WiFi mid-shoot,
   watch live view marked down → recovery on reconnect. Confirm
   resilience layer behaves as designed under controlled outage.
4. **Excel-side changes** — Excel polls `/luminance`, `/shutter/status`,
   `/exposure/state`; no longer fires or fetches itself. Excel becomes
   the planning/monitoring/alerting end; cart owns the shoot runtime.
5. **Optional cleanup commit** — remove now-unused `cameraShutter()`
   function definition (CAN shutter dead code).
6. **Update PROJECT_STATE.md** to reflect what Session C completed.

### Out of scope for Session C

- Migration of CCAPI calls to Giga (later session, if ever)
- Plan execution on cart (Sessions D and E)
- Phone UI changes (stays as is)
- Definitive root-cause for R3 WiFi profile drops (monitor in production)

---

## Module inventory (Excel)

| Module | Role | Post-migration |
|---|---|---|
| `Sequence` | Master timing loop, single RunShot, replay | Mostly retired |
| `Camera` | CCAPI, luminance, mode walk | Retired (moves to cart) |
| `Gimbal` | RS4 Pro via Arduino HTTP | Retired (cart owns) |
| `Cart` | Cart log retrieval, replay plan | Plan authoring stays |
| `Astro` | Sun/Milky Way angles | Stays (pre-shoot) |
| `Utils` | Tv lookup, NextTv walker | Walker moves to cart |
| `BackupRestore` | Export/Import modules | Stays (dev tool) |
| `Buttons` | Excel-side UI buttons | Stays |

---

## Bugs fixed in Session B (recap)

| Bug | Description | File |
|---|---|---|
| Predictive Tv/ISO tables retired | Single RunShot handler | Sequence.bas |
| NextTv direction sign | Walked wrong way | Utils.bas |
| Bug B — OnTime cadence slip | Anchor off g_scheduledTime + clamp | Sequence.bas |
| 503 cascade on SetShutterSpeed | Photo primacy via error handler | Sequence.bas |
| 503 on kickoff GETs | CameraGet retry added | Camera.bas |
| 503 body unparsed | Parse "message" + IsBusyRetryable | Camera.bas |
| Kickoff hammering mid-write | Moved before TakePhoto | Sequence.bas |
| Kickoff every cycle | Throttled every 3rd cycle | Sequence.bas |
| ImportModules rename collision | Overwrite via CodeModule.AddFromString | BackupRestore.bas |

From Session A: Bug A (MsgBox blocked photo loop), Bug C
(PollLuminanceCalc killed finished jobs).

---

## Known issues / observations

1. **R3 WiFi profile drop (recurring, manual recovery, partial trigger
   identified).** Camera has dropped its selected WiFi profile four
   times across three sessions. **Day 3's incident #4 had a clear
   trigger: camera power cycle following a self-clearing battery
   warning.** The earlier three drops had unclear triggers. Recovery
   in all cases is operator-only: cycle SET1 → SET3 in camera wireless
   menu. **Architecturally de-risked** — pin-8 shutter keeps cart
   shooting through any camera WiFi loss; only luminance updates and
   exposure adjustments pause until SET3 is reselected. Operational
   guidance: avoid power-cycling the camera during a shoot.

2. **Exposure walk auto-trigger pending.** The walk has manual endpoint
   `/exposure/walk?mode=...` that takes one step on demand, but no
   auto-firing from the luminance fetch path yet. Excel/operator can
   trigger walks today; cart will do it autonomously next session.

2. **CCAPI fetch transient failures (~10% at 2s cadence).** Test 4
   showed individual fetches occasionally fail (mix of `connect failed`
   and `response timeout`) — never 3 in a row. Causes likely include
   mesh handoffs, camera momentary busy, AP burst traffic. The
   resilience layer handles them. Watch for elevated failure rates;
   3-in-a-row triggers live-view-down state and retry loop.

3. **Card delivery rate at 2s cadence: 99%.** Test 4 produced 311
   triggers and 308 photos on card. Gap likely end-of-test in-flight
   triggers. Budget for ~1% loss in production planning at this cadence.

4. **CCAPI live-view stop can return 503.** Observed today in Test 4.
   Treat as transient; live view typically still gets cleaned up on
   camera side. Don't retry aggressively.

5. **The "trust the counter" lesson stands.** Always verify by card
   file count. Today: 311 counter vs 308 card. Counter alone would
   have hidden the 1% gap.

6. **Live view DELETE quirk.** `DELETE /ccapi/ver100/shooting/liveview`
   returns 405 Method Not Allowed. The correct stop path is
   `DELETE /ccapi/ver100/shooting/liveview/scroll`. Code uses the
   correct path. Documented for clarity.

7. **CAN ID / SOF mis-documentation.** Production sketch uses SDK-spec
   `0x223 / SOF 0xAA` which works for gimbal motion. Bus capture shows
   Ronin actually broadcasts on `0x530 / SOF 0x55`. Both sketches
   mis-label the SDK-spec values as "CONFIRMED RS4 Pro". Cleanup as
   we touch sketches.

8. **CCAPI camera-busy timing investigation deferred.** 503 body
   parsing in place; histogram of camera-busy durations is bench work
   for later.

9. **RAM headroom on Uno R4 WiFi is tighter than the raw spec suggests.**
   32KB SRAM total, ~21.6KB consumed by globals (66%) after today's
   work. 10KB buffer attempt caused linker overflow. Plan future
   memory work conservatively; budget ~5-6KB for new feature work.

---

## Session D — Gimbal plan (design refined in Session A)

(Brief — see prior history for full notes.)

- **Sparse plan source:** Excel sheet with rows from GimbalLog (recorded
  actuals) + Astro table (computed celestial positions), operator-edited.
- **Action vocabulary:** `goto&hold`, `goto&track`, `goto&tracknextposition`.
- **Expander:** Python script `expand_plan.py`. Smoothing maths there.
- **Astro single-sourced in VBA**, dense astro table exported at expansion time.
- **Per-row time_for_action** set by the expander.
- **Executor:** generalised `RunCartReplayStep` walking action-prefixed rows.
- Current `GimbalToSunset/MilkyWay/Sunrise` calls are interim — replaced
  by plan execution when this lands.

**Care needed for Session D:** the cart will be doing more work — gimbal
moves on a precise schedule alongside the photo timer. Watch CAN bus
contention. Bench-test rapid shutter during gimbal moves before relying
on it overnight. Pin-8 shutter is independent of CAN, but the cable
adds tangle risk during gimbal motion.

---

## Session E — Cart plan (design refined in Session A)

Same pattern as Session D, cart movement instead of gimbal pointing.
Foundation partly built — `StartCartReplay` / `RunCartReplayStep`.

- **Sparse plan source:** Arduino CartLog from a high-speed rehearsal.
- **Expansion:** turns at logged distance (no smoothing); speed changes
  no smoothing; stops linear-smoothed via Arduino's SPEED_DECAY (6-min
  ramp to zero); expander back-calculates trigger point.
- **Executor:** same unified walker as gimbal plan.

**Care needed:** cart movement is the biggest commitment-of-trust change.
Plan-load-and-execute path needs real validation. Likely a
rehearsal-day-before pattern.

---

## Architectural principles (for any future session)

1. **Photos are primary, sacred, never delayed.** Luminance, gimbal,
   adjustments all happen "around" the photo schedule. ~7800 photos
   over the overnight shoot drive the image-stabilisation pipeline.
2. **No photo is fatal; wrong exposure is fixable in post.** This is
   the principle that orders the migration.
3. **Phase boundaries are advisory only.** They mark astronomical
   events for operator reference. Exposure control is luminance
   feedback, not phase-driven.
4. **Plans (gimbal, cart) are operator-authored from logs.** Code
   provides info; operator decides creative shape; code executes.
5. **R3 + good card is fast.** Camera is never the bottleneck for
   cadence. The bottleneck was the host scheduler.
6. **Luminance changes per minute, not per second.** Sample sparsely;
   stale-by-3-shots is fine.
7. **Feedback control is self-limiting per mode.** Monotone walks pin
   at floors. No clamp code needed.
8. **The right job for the right device.**
   - Excel (laptop): planning, authoring, log analysis, post-shoot
   - Arduino: real-time, CAN, photo timer, motors, HTTP server,
     CCAPI client, luminance compute
   - Phone: in-field UI for rehearsal recording
9. **503 is information, not just an error.** CCAPI's nine 503
   messages tell you what state the camera is in. Parse and decide.
10. **Redundancy by design.** Once a shoot starts, the cart should run
    autonomously through plateau hours regardless of WiFi or Excel.
    Critical paths must not depend on networked components that can
    enter unrecoverable states without operator presence.
11. **Never trust a counter — always verify with the artefact.** Photo
    counter says nothing about whether photos landed on the card.
12. **Separate the WiFi-dependent from the WiFi-independent.** Shutter
    is hardware-direct (pin 8 → cable). CCAPI is for luminance only.
    A WiFi failure freezes exposure but does not stop the shoot. (New
    principle, learned Session C day 2.)

---

## Repo state (end of session 12 May, day 3)

### Arduino repo (`mwindley/DJI-Ronin-RS4-Arduino`)

`main` and feature branches as listed in "Branches on GitHub" above.
The `session-c-uno-luminance` branch is the cumulative Session C head,
with three commits today (`71f62c2` pin-8 architecture, `a2ccca1`
RAW-only buffer fix, `331d242` exposure walk). All pushed to origin.

### Excel repo (`mwindley/HyperLapse-Excel`)

`HyperLapse.xlsm` with end-of-Session-B `.bas` modules. No Excel-side
changes today. Excel still does everything it did — Session C Excel work
hasn't started.

---

## Restart checklist

When opening the next session, the first message should:

1. Upload this file (PROJECT_STATE.md)
2. Upload `.bas` files (`ExportModules` first to ensure current)
3. Upload current Arduino sketch from `session-c-uno-luminance` branch
4. State what to work on this session

Claude has no memory between sessions and cannot fetch private GitHub
repos. Files must be uploaded.

---

## Suggested next session opening

```
Continuing HyperLapse Cart project — Session C day 4.

End-state of day 3 (12 May 2026):
- session-c-uno-luminance branch now has exposure walk
  (commit 331d242). Ports AdjustExposureByLuminance from
  Excel Camera.bas. Validated end-to-end on real hardware:
  /exposure/init reads Tv/ISO from camera, /exposure/state
  returns JSON, /exposure/walk runs one walk step and PUTs
  to camera if action needed. Both BRIGHTEN and DARKEN
  modes confirmed walking correctly, PUT-verified against
  camera back-screen.
- Day 3 also observed resilience layer absorbing a real
  outage during testing (live view RECOVERED after 5
  attempts), and incident #4 of the R3 WiFi profile drop
  (trigger: camera power cycle).
- Cart now owns: pin-8 shutter, mode 3 timer, luminance
  fetch, resilience, exposure walk.

Next deliverable: wire walk to auto-fire from luminance
fetch path (Stage 2 of two-stage plan, estimated ~3-10
lines). After that: long soak with everything running,
then Excel-side changes.

Attached: PROJECT_STATE.md, all .bas files, current
Arduino sketch from session-c-uno-luminance branch
(head commit 331d242).
```
