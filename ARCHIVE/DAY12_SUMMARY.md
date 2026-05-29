# Day 12 — Session Summary

## Headline finding

**The "CCAPI stress" framing of Day 11 was wrong.** The real cause of
the chronic 70-74% delivery on 2-second cadence was **the 100ms shutter
pulse width**, which sat at the edge of what the Canon R3 reliably
registers. CCAPI activity made the situation worse only by making the
camera slower, but CCAPI was never the stressor in its own right.

Raising the pulse from 100ms to 200ms restored delivery to 96-100%
across all conditions tested today, including the Day 11 stress
condition (luminance fetch every 3rd photo + live view active).

## How the day went

Today started as Day 11 had ended: trying to find the recovery-time
edge with full CCAPI stress. The plan was to build a separate test
sketch on an empty Uno R4 WiFi to sweep variables independently of
the production cart.

That plan ran into trouble:
1. A separately-built sketch had multi-second HTTP latency that the
   production sketch did not have on the same Uno, same WiFi.
2. After much chasing (cable swap, firmware upgrade, DHCP test, etc.)
   we abandoned the standalone sketch and built the test rig as a
   minimal-modification fork of production (added analyser-marker
   pins and a `liveview_at_start` disable flag).
3. Once stable, the rig reproduced the Day 11 ~70% delivery — and
   then started producing surprises.

The breakthrough came from comparing the Uno+opto output trace
against the manual intervalometer output on the logic analyser.
The intervalometer (which the camera honours at 100%) drives a
**200ms LOW pulse**. The Uno+opto was driving a **100ms LOW pulse**.

## The data

Numbered chronologically.

| # | Date | Pulse | CCAPI | Fires | On card | Delivery |
|---|---|---|---|---|---|---|
| 1 | Day 11 | 100ms | luminance every 3rd + liveview | 81 | 57 | 70.4% |
| 2 | Day 12 | 100ms | liveview only (no fetch) | 28 | 23 | 82.1% |
| 3 | Day 12 | 100ms | none (zero-CCAPI) | 39 | 21 | 53.8% |
| 4 | Day 12 | 200ms | none (manual intervalometer) | 20 | 20 | 100% |
| 5 | Day 12 | 200ms | none (zero-CCAPI) | 26 | 25 | 96.2% |
| 6 | Day 12 | 200ms | none (zero-CCAPI repeat) | 61 | 60 | 98.4% |
| 7 | Day 12 | 200ms | luminance every 3rd + liveview (= Day 11 stress) | 37 | 37 | 100% |

Key comparisons:

- **#1 vs #7**: same CCAPI load (Day 11 stress condition). Only
  difference is pulse width. 100ms → 70.4%, 200ms → 100%.
- **#3 vs #5,#6**: same zero-CCAPI condition. Only difference is
  pulse width. 100ms → 53.8%, 200ms → 96-98%.
- **#4 vs #5,#6**: 200ms with no CCAPI, intervalometer vs Uno+opto.
  Effectively identical (100% vs 96-98%). The opto path is innocent.

## Why pulse width matters

The Canon R3 shutter-trigger input needs the line held LOW for long
enough to debounce, register, and queue the shot. 100ms is right at
the edge of "long enough", and any slight delay in the camera's
input-handling path (e.g. while CCAPI is busy) pushes a fraction of
triggers past the edge → drops.

200ms gives the camera comfortable headroom. Even with full CCAPI
load and an active fetch timeout / backoff cycle in #7, every photo
landed.

## The resilience code is verified

Run #7 included a real CCAPI fetch timeout mid-run:

    [T+42790] FETCH start since_photo=211ms delay_target=0ms
    [T+43435] REQ-PHASES connect=71ms send=58ms wait=506ms TIMEOUT
    [lum] fetch FAILED status=0 err=response timeout
    [T+43450] FETCH end ok=N elapsed=660ms
    [lum] fetch FAIL — backoff for 2 cycles
    [lum] fetch skipped (backoff, 1 cycles left)
    [lum] fetch skipped (backoff, 0 cycles left)
    ...
    [T+60806] FETCH start since_photo=212ms delay_target=0ms   ← resumed cleanly

The fetch failed, production logged it, skipped two cycles to let
the camera recover, then resumed automatically. Pin-8 cadence never
broke. All 37 photos still landed. The architectural principle
"photos sacred, never delayed; wrong exposure fixable in post" held
under real stress, with verification today.

## Drop test sketch (`DropTest.ino`)

Built tonight as a minimal fork of `DJI_Ronin_UnoR4_v3.ino`:

- 4 analyser marker pins (Uno pins 2, 3, 5, 6) — drives a 3-bit
  call-type code + in-flight flag on every CCAPI request
- `ccapiRequest` and `ccapiPutWithRetry` take a `CcapiCall marker`
  parameter (per-attempt for retries → each retry shows as its own
  analyser pulse)
- `/echo?msg=X` endpoint for UI ↔ Uno round-trip verification
- `/debug/liveview_at_start?on=N` — disables `ccapiStartLiveview()`
  in `/shutter/start` AND `tryStartLiveviewIfNeeded()` in cartLoop
  AND the ANCHOR datetime call → true zero-CCAPI baseline mode
- `backupShutter()` now drives pin 8 HIGH for **200ms** instead of
  100ms (key change validated tonight)

## Analyser channels (as wired tonight)

| CH | Signal | Source |
|---|---|---|
| D0 | Pin 8 fire | Uno pin 8 (or pin 9 readback jumper) |
| D1 | Opto output | 4N25 pin 5 (collector / Canon Shutter line) — unreliable contact on breadboard, replaced by intervalometer-direct measurement |
| D2 | CCAPI in-flight | Uno pin 2 |
| D3 | Call-type bit 0 | Uno pin 3 |
| D4 | Call-type bit 1 | Uno pin 5 |
| D5 | Call-type bit 2 | Uno pin 6 |
| D6, D7 | spare | — |

Call-type codes (3 bits, MSB=D5, LSB=D3):

| Code | Binary | Type |
|---|---|---|
| 0 | 000 | IDLE |
| 1 | 001 | LUMINANCE |
| 2 | 010 | LIVESTART |
| 3 | 011 | LIVESTOP |
| 4 | 100 | TVSET |
| 5 | 101 | ISOSET |
| 6 | 110 | ANCHOR (datetime) |
| 7 | 111 | OTHER (init GETs, event polling) |

## Lessons (carry forward)

1. **Compare to a known-good reference before chasing software.**
   The intervalometer is a known-100% reference. Measuring it on the
   analyser instantly revealed the pulse-width difference. Without
   that comparison we would have kept chasing CCAPI.

2. **A USB cable can cause "WiFi" symptoms.** Multi-second response
   times early in the day were resolved by swapping the Uno's USB
   cable. Power browns out from a flaky cable destabilise the WiFi
   co-processor without obviously failing.

3. **Build from production, don't rebuild.** The standalone test
   sketch took hours to chase HTTP-serving problems that production
   didn't have. Forking production with surgical additions worked
   first time. Lesson aligns with PREFERENCES.md §"Investigation
   discipline — measure, drill, then simplify": don't recreate
   working machinery; modify it minimally.

4. **Hardware diagnostics: idle voltages first, then transitions.**
   Time spent measuring 4N25 LED forward voltage (1.2V), collector
   idle (3V from camera pull-up), collector-emitter saturated (25mV)
   was time well spent — it isolated the working pieces before we
   chased the wrong subsystem.

5. **The pin-9 readback is worth keeping.** Every PULSE log line
   showing `high=N/N` (every sample HIGH during the pulse window)
   builds trust that the cart side is electrically clean. When we
   accidentally unwired the readback, the log immediately showed
   degraded `high` counts and we knew to look at hardware first.

## Open items going forward

1. **Apply 200ms pulse to production sketch** (one-line change in
   `backupShutter()` — `100000` → `200000` microseconds). Validate
   on a real shoot.

2. **Day 11's Open Question about recovery-gap edge condition** is
   superseded. There is no recovery-gap edge to find — the apparent
   edge was a 100ms-pulse artefact. The Tv + 1.5s rule still stands
   as a sensible minimum interval, but the architectural anxiety
   about "the 2-second zone is the project's bread and butter and
   it drops photos" is resolved.

3. **CCAPI fetch every 3 photos is fine.** No need for `fetch_every_n`
   sweeps. Day 11's Run 1 (every 3) and Run 3 (none) showed near-
   identical drop rates with 100ms pulse — because drops were caused
   by pulse width, not fetch frequency.

4. **Live view cycling is unnecessary as a stress-reduction measure.**
   It was being investigated as a way to reduce CCAPI load on the
   camera. With 200ms pulse, the load is no longer harmful. Live view
   can stay on continuously, as production already does.

5. **The Drop Test sketch can stay as a permanent diagnostic asset.**
   Marker pins and zero-CCAPI mode are useful for any future
   investigation. The 200ms pulse should be ported back to production.
