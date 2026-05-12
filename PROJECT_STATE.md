# HyperLapse Cart — Project State

**Last updated:** 12 May 2026 (end of Session C day 2 — pin-8 architecture in service, RAW-only buffer fix committed, R3 WiFi-drop investigation open but de-risked)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

---

## ⚠️ Top-of-file context — Session C day 2 outcomes

### Yesterday's open issue is resolved (by architecture change)

Day 1 ended with the Ronin's CAN-via-cable shutter broken — could send
the command, no photo on card. Day 2 confirmed this couldn't be recovered
cheaply: Ronin's only "supported" R3 shutter path is Bluetooth (M-button),
which doesn't coexist with the camera-control cable used for focus/record.
**CAN-via-Ronin shutter is now retired** as a near-dead capability.

**Architectural pivot:** the Arduino's existing pin-8 + cable to the
camera's remote shutter port is now the shutter path. WiFi-independent.
Tangle risk on the gimbal accepted. CCAPI is reserved for luminance only.

**This change is committed and validated:**
- Commit `71f62c2` — pin-8 owns shutter, CAN shutter retired
- All shutter modes (manual, button-18 backup, mode 3 timer) now fire pin-8
- Test 1 single shot: photo on card, red card-write LED ✓
- Test 2 mode-3 timer: 22 photos at 2s cadence, card-verified ✓

### Today's other commit — RAW-only buffer fix

Commit `a2ccca1` — `LUM_RESP_BUF_SIZE` bumped from 5120 to 6144.

When the camera was switched from RAW+JPEG to RAW-only during this session,
the CCAPI `liveview/flipdetail?kind=info` response grew from ~4521 bytes
to ~5360 bytes, overflowing the 5KB buffer. Symptoms: every fetch failed
with "bad data size" or "response timeout". 10KB was attempted first but
caused linker RAM overflow on the Uno R4. 6KB fits with ~700-byte headroom
and is now the production-safe size.

Validated by the 10-minute Test 4 below.

### R3 WiFi profile drop — open investigation, de-risked

The camera's WiFi profile selection has been observed to drop three times
across two sessions, requiring manual operator recovery (cycle camera
menu through SET1 to SET3 = "Rosedale CCAPI" to reselect). This is a
camera-side behaviour; no software path from the Arduino can recover it.

**Root cause: not conclusively identified.** Two tests today:

- **Test 3 (deprivation):** 5-min mode-3 pin-8 run with ALL spontaneous
  CCAPI traffic disabled. Camera survived — green light on, /ccapi
  responsive. CCAPI traffic implicated as candidate trigger family.
- **Test 4 (full operation):** 10-min mode-3 pin-8 run with full CCAPI
  traffic (live view, ~150 luminance fetches). Camera survived — green
  light on, /ccapi responsive, 99% card delivery. **Did not reproduce
  the drop** despite significant CCAPI use.

**Most plausible remaining hypothesis:** today's earlier drop happened
during a run with the 5KB buffer where every fetch failed with
oversized/timeout errors. Repeated *failed* fetches (not successful
ones) may be the trigger family. Pre-buffer-fix this kind of stress
was inevitable in RAW-only mode; post-fix it should be rare.

**Mitigation already in place by architecture:**
- Pin-8 shutter keeps photos flowing through any CCAPI failure
- Resilience layer (3-fail threshold, 30s retry, rate-limited logging)
  absorbs transient camera unresponsiveness
- Worst-case overnight failure: exposure freezes at last good values;
  shoot continues; operator recovers SET3 in the morning

**Operationally accepted as a residual risk.** Worth instrumenting for
next time it happens, but no longer blocking production.

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

---

## Today's deliverables — what's committed and what's verified

### Branches on GitHub (`mwindley/DJI-Ronin-RS4-Arduino`)

| Branch | Contents | Status |
|---|---|---|
| `main` | Uno R4 v13 production sketch | Stable, behind by Session C work |
| `session-c-giga` | Giga TX test sketch | Parked — Giga CAN proven, not the path forward |
| `session-c-uno-timer` | Mode 3 photo timer (CAN-shutter era) | Superseded by `session-c-uno-luminance` |
| `session-c-uno-luminance` | **Current head** — pin-8 shutter, mode 3 timer, CCAPI luminance, WiFi resilience, RAW-only buffer | All work below committed and pushed |
| `session-c-liveview-test` | One-shot coexistence test sketch | Archived — not for merge |

The `session-c-uno-luminance` branch is the cumulative head of Session C
work. Two new commits today on top of yesterday's `ffe7dce`:

| Commit | Subject |
|---|---|
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

### What's NOT verified

❌ Resilience behaviour under deliberate WiFi drop (transient failures
   recovered, but a full disconnect/reconnect cycle hasn't been forced)
❌ Tv/ISO walk — code not written yet
❌ Excel-side changes — not started

### What's been retired

- CAN-via-Ronin shutter (`cameraShutter()` still exists as a function
  definition but no execution path calls it; will be removed in a future
  cleanup commit)
- Deprivation test toggle (used today, stripped before commit `a2ccca1`)

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

Owns (post-Session-C day 2):
- Photo trigger timing (mode 3 via pin-8 — **validated**)
- Single-shot trigger via pin-8 — **validated**
- Luminance fetch via CCAPI histogram (validated, RAW-only safe)
- Resilience under transient CCAPI failure (validated)
- Luminance feedback decision (next deliverable: Tv/ISO walk)
- CCAPI Tv/ISO PUT calls with 503 retry (next deliverable)
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
- **Nice-to-have:** Tv/ISO + luminance autonomous on cart (luminance done;
  Tv/ISO walk next)
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
  (luminance done; Tv/ISO walk next)
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
| 2b | WiFi resilience (retry on connection failure) | Code complete, transient-failure absorption verified; deliberate drop test still pending |
| 3 | Tv/ISO walk + CCAPI Tv/ISO PUTs | **Not started — next deliverable** |
| 4 | Excel-side changes (stop firing, stop fetching, poll cart) | **Not started** |

### Suggested next-session work, in order

1. **Tv/ISO walk + CCAPI PUTs** — port `AdjustExposureByLuminance` and
   `NextTv` from `Camera.bas` to C. Test with luminance feedback
   actually driving exposure.
2. **Deliberate WiFi drop test** — turn off camera WiFi mid-shoot,
   watch live view marked down → recovery on reconnect. Verify
   resilience layer behaves as designed.
3. **Long soak** (30+ min, ideally 60+) of everything together,
   verified by card-file count. Aim for ~99% delivery to match Test 4.
4. **Excel-side changes** — Excel polls `/luminance` and `/shutter/status`,
   no longer fires or fetches itself.
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

1. **R3 WiFi profile drop (recurring, manual recovery).** Camera has
   dropped its selected WiFi profile three times across two sessions.
   Root cause not conclusively identified; suspected trigger is
   repeated failed CCAPI exchanges (which Test 4's buffer fix should
   reduce in production). Recovery is operator-only: cycle SET1 → SET3
   in camera wireless menu. **Architecturally de-risked** — pin-8
   shutter keeps cart shooting through any camera WiFi loss; only
   luminance updates are affected. Worth instrumenting next time it
   happens (note time, recent CCAPI traffic pattern, camera state).

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

## Repo state (end of session 12 May)

### Arduino repo (`mwindley/DJI-Ronin-RS4-Arduino`)

`main` and feature branches as listed in "Branches on GitHub" above.
The `session-c-uno-luminance` branch is the cumulative Session C head,
with two new commits today (`71f62c2` pin-8 architecture, `a2ccca1`
RAW-only buffer fix). Both pushed to origin.

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
Continuing HyperLapse Cart project — Session C day 3.

End-state of day 2 (12 May 2026):
- session-c-uno-luminance branch now has pin-8 shutter ownership
  (commit 71f62c2) and RAW-only buffer fix (commit a2ccca1). Both
  validated by Test 4: 311 triggers, 308 photos on card (99%
  delivery), luminance stable at mean=94-95 across ~150 fetches,
  resilience absorbed ~10% transient failures, camera survived
  10 minutes of full operation.
- Yesterday's Ronin shutter problem resolved by architectural
  pivot: CAN-via-Ronin retired (near-dead), pin-8 + cable now owns
  shutter. WiFi-independent. Tangle risk accepted.
- R3 WiFi profile drop investigation: 3 historical incidents,
  cause not conclusively identified, mitigated by architecture
  (pin-8 keeps shooting through any camera WiFi loss). Open
  hypothesis: pre-buffer-fix CCAPI failure traffic was the
  trigger family. Operationally accepted as residual risk;
  recovery is manual (operator cycles SET3 in camera menu).

Next deliverable: Tv/ISO walk + CCAPI PUTs from the Arduino —
port AdjustExposureByLuminance and NextTv from Excel's Camera.bas.

Attached: PROJECT_STATE.md, all .bas files, current Arduino
sketch from session-c-uno-luminance branch.
```
