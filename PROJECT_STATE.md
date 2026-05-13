# HyperLapse Cart — Project State

**Last updated:** 12 May 2026 (end of Session C day 5 — Stage 3 Tv-driven cadence committed, body-read 30× speedup, backoff after fetch failure, photo-drop problem partially solved)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

Also upload `PREFERENCES.md` (sibling file) — that contains the working
agreement, the oscilloscope diagnostic approach, the standard test
sequence, and the WiFiS3 gotchas. Read both at session start.

---

## ⚠️ Top-of-file context — Session C day 5 outcomes

### Three things shipped today

**1. Stage 3: Tv-driven cadence.** Photo interval is now derived from
camera Tv setting per the production rule `interval = max(2000, ceil(Tv + 1.5s) * 1000)`.
Removed the standalone `/shutter/interval` endpoint — interval is now a
read-only consequence of Tv. Updated automatically on `/exposure/init`,
on each auto-walk that changes Tv, and on manual `/exposure/walk` Tv
changes. `/exposure/init` JSON gained `interval_ms` field for verification.

**2. Body-read speedup — 30× faster (real).** Discovered via REQ-PHASES
instrumentation that fetch bodies were taking ~2000ms to read 500-2700
bytes over local WiFi. Root cause: `delay(5)` after every empty-buffer
check in the read loop, accumulating across many small TCP chunks.
Replaced with `delay(1)` plus an idle-timeout exit (50ms since last
byte received). Body-read dropped from ~2000ms → ~270ms.
Total fetch dropped from ~2800ms → ~550-1000ms.

**3. Backoff after fetch failure.** When a fetch fails (any reason —
10s connect timeout, response timeout, etc), the next 2 fetch cycles
are skipped. Gives the camera time to recover and prevents stacking
10-second blocks. Tested under stress conditions and confirmed working
(backoff cycles fire correctly, no double-failures during recovery).

### NOT shipped — photo drops in stress conditions persist

Five-minute soak at Tv=2" / lens covered / mode darken showed **105/154
= 68% delivery.** This is despite body-read fix and backoff working as
designed. Drops are camera-side — pin-8 fires on time (gap=4000ms in
serial) but camera doesn't capture the image. Concurrent CCAPI traffic
seems to suppress the camera's pin-8 handler even when traffic is
finishing well before the next pin-8 due time.

**Important context:** stress conditions are worst case. Real-world
overnight shooting uses Tv≥6s mostly, where:
- Photo cadence is 8+ seconds (more headroom for any fetch)
- Camera has actual scene to process (not idling on a black frame)
- Light changes drive walks; fetches result in meaningful PUTs

The Excel-table production system (no CCAPI fetches at all) had **zero
drops across 3000 photos over 2 overnight runs.** So the camera+pin-8
combination is fundamentally reliable; the cart's CCAPI fetches are
the regression.

### Commits today

| Commit | Subject |
|---|---|
| `<pending>` | Session C day 5: Stage 3 Tv-driven cadence + body-read fix + backoff |
| `<pending>` | Session C day 5: phase-timing instrumentation (REQ-PHASES) |

Pending commits — code is in `/home/claude/work/DJI_Ronin_UnoR4_v2.ino`
ready to be copied into the local repo and committed.

### Hardware-validated changes

| Test | What | Result |
|---|---|---|
| Body-read fix | First fetch after fresh boot | total 789ms (was 2804ms), body 69ms (was 2088ms) |
| Body-read fix | Subsequent warm fetches | total 200-600ms typical |
| Backoff | Single 10s connect-fail event in 80s run | 28/28 delivery, late PIN8 by 10s once, no drops |
| Backoff | Multiple failure events in 5-min run | Drops still occurred (105/154) — fetch traffic interferes with camera pin-8 handler even when fetches succeed |

---

## Pending work for Session C day 6

### Priority 1: Real-world Tv test

The 5-minute stress soak at Tv=2" is *not* representative. Test at
Tv=8" or Tv=15" (overnight-realistic):
- Cadence is 10-17s, so fetches occupy <10% of cycle vs ~20% at Tv=2"
- Camera is processing real scene data
- Compare delivery rate to determine whether production is OK

If production is fine at slow Tv, the only remaining concern is the
sunset transition window (Tv=2-6s, fetches frequent, walks active).
That's a smaller part of overnight runs.

### Priority 2: Non-blocking fetch (if needed)

If even at production Tv the drops remain, refactor `ccapiFetchLuminance`
and `ccapiRequest` into a state machine that polls one phase per loop
iteration, bounded to <10ms per iteration. Significant surgery — only
worth doing if the slower-Tv test shows it's needed.

### Priority 3: /exposure/init retry

Init has no retry — a single GET tv + GET iso. Transient CCAPI failures
cause `ok:false`. Add ~10 lines: 3 retries with 1s backoff between
attempts. Low risk, addresses the recurring "init failed, retry"
workflow drag.

### Priority 4: Excel-side change

Excel currently fires TakePhoto every interval. Change to: Excel polls
cart endpoints for telemetry but does NOT fire photos. Cart owns timing.
Excel becomes display/logging, not controller.

---

## Architecture summary (carried forward)

### Hardware
- Canon R3 camera (high-spec, CCAPI over WiFi at 192.168.1.99:8080)
- DJI Ronin RS4 Pro gimbal (CAN bus, address 0x223 TX / 0x222 RX)
- Arduino Uno R4 WiFi (192.168.1.97, the cart controller)
- Pin-8 hardware shutter trigger (the WiFi-independent failsafe)
- Two Tic stepper controllers + servo (front/rear axles)

### Software layering
- **Pin-8 photo timer**: highest priority, must never be delayed. Uses
  `millis()` against `shutter_interval_ms`. Currently fires within
  4ms of target time.
- **CCAPI fetch (luminance)**: every 3 photos. Returns mean brightness.
  Triggers Stage 2 auto-walk if outside deadzone.
- **CCAPI PUT (Tv/ISO)**: triggered by walk decisions. Used only when
  needed; deadzone prevents oscillation.
- **Live view management**: needed for the luminance endpoint to return
  data. Restart on 3 consecutive conn failures.

### Architectural principles (sacred)
1. Photos sacred, never delayed.
2. No photo fatal; wrong exposure fixable in post.
3. Stage 1 (luminance fetch) and Stage 2 (auto-walk) are inline, not
   pre-emptive — single thread, no concurrency.
4. WiFi-dependent (CCAPI) vs WiFi-independent (pin-8, CAN gimbal) cleanly
   separated. Pin-8 must work when CCAPI is fully down.
5. Tv + 1.5s cadence rule. Photo interval derived from Tv, not set
   independently.

---

## Known library quirks (Arduino Uno R4 WiFi / WiFiS3)

- `WiFiClient::setConnectionTimeout()` is NOT honoured for
  `client.connect()`. The default 10-second block applies regardless.
  Workaround: backoff after failure (shipped this session).
- Tight `delay(5)` in read loops accumulates badly over many small TCP
  chunks. Use `delay(1)` plus idle-timeout exit (shipped this session).
- Cart resets clear all state (`lum_fetch_disabled`, `fetch_delay_ms`,
  mode, init). Every flash or reset means re-running the full setup.

---

## Standard test setup sequence (use every session)

See `PREFERENCES.md` for the full ordered checklist. Briefly:

1. CCAPI alive: `http://192.168.1.99:8080/ccapi`
2. Init (verify `ok:true` AND `interval_ms`): `http://192.168.1.97/exposure/init`
3. Mode: `http://192.168.1.97/exposure/target?mode=darken`
4. Fetch delay (default 0): `http://192.168.1.97/debug/fetchdelay?ms=0`
5. Delete card images
6. Confirm camera state
7. Start: `http://192.168.1.97/shutter/start`
8. Stop: `http://192.168.1.97/shutter/stop`
9. Report `photos_taken=N`, card count, anomalies.

---

## Diagnostic instrumentation in current build

- `PIN8 #N gap=Xms target=Yms` — every photo fire
- `FETCH start since_photo=Xms delay_target=Yms` — fetch begins
- `FETCH end ok=Y/N elapsed=Xms` — fetch completes
- `REQ-PHASES connect=Xms send=Yms wait=Zms hdrs=Ams body=Bms stop=Cms total=Tms bytes=N` — sub-phase timing for every HTTP request
- `LOOP-LONG elapsed=Xms` — any loop iteration over 100ms
- `[lum] fetch FAIL — backoff for N cycles` — backoff engaged
- `[lum] fetch skipped (backoff, N cycles left)` — backoff in progress
- `PUT-Tv start/end` and `PUT-ISO start/end` with timing

Debug endpoints:
- `http://192.168.1.97/debug/fetch?on=0|1` — disable/enable fetches
- `http://192.168.1.97/debug/fetchdelay?ms=N` — fetch start delay
