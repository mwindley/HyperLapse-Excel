# Giga R1 Migration Strategy

Workfront #47 — migrate cart from Uno R4 WiFi to Arduino Giga R1.

## Why migrate

**Uno R4 WiFi headroom is exhausted.**

- 32 KB SRAM total
- Toolchain reserves ~8 KB for heap (locked region)
- Effective static-global ceiling: ~23.2 KB
- Currently using: 23,240 bytes (70% reported by IDE)
- Headroom for new globals: a few hundred bytes before hitting heap/stack overlap

**Blockers caused by Uno SRAM ceiling (as of Day 17):**

- TRACK_SEGS_MAX stuck at 2; N=4 would give ~9° max yaw error instead of 20°
- `/debug/trackplan?idx=N` read-back endpoint can't link (had to remove)
- Track runtime block (1 Hz check in `loop()`, ~80 lines) can't link
- Future feature additions blocked until SRAM cleanup or migration

**Giga R1 advantages:**

- 1 MB SRAM (32× Uno R4)
- No heap/stack contention at our usage levels
- Dual-core M7/M4 — can offload work
- More flash, more I/O pins
- USB host (could one day replace WiFi+CCAPI with USB to camera)

On Giga, all of #58/#59 constraints disappear. Track N=8 or N=16 trivial. Multiple full HTTP buffers trivial. Plenty of room for future features.

**Cost:** migration effort. Pinout differences, possibly library changes, new board to learn. Cart is mature on Uno; full port is weeks of work.

## Strategy: small capability demonstrations

Build confidence one capability at a time on a spare Giga, not big-bang migrate. Each step has a clear pass/fail. Migration not committed until step 6 proves out.

### Step 1 — Blink + Serial

Confirm toolchain works. IDE recognises Giga R1. Upload a basic sketch with `Serial.begin(115200)` and an LED blink. Pass = LED blinks, Serial output appears in monitor.

### Step 2 — WiFi connect, basic HTTP server

Confirm WiFi stack equivalent to WiFiS3. Port the simplest `/status` endpoint. Browse to the board's IP, get a response. Pass = HTTP server responds to a GET.

Risk: Giga uses different WiFi library (mbed-os based). Library name and API may differ.

### Step 3 — CAN bus

DJI gimbal SDK comms. Probably uses a different CAN library on Giga (mbed-os has its own CAN stack). Hook up a CAN transceiver and a known-good gimbal. Send a getPosData() request, parse the response.

Pass = gimbal position reported back accurately.

Risk area: this is the most specialised library and the hardest to find drop-in equivalents for. May need custom driver work.

### Step 4 — I²C

Pololu Tic controllers. Standard Wire library should work without changes. Hook up one Tic, send a setVelocity command, verify motor moves.

Pass = stepper turns.

### Step 5 — CCAPI

Connect to camera over WiFi, take a photo. Bigger HTTP buffers test (luminance responses ~4.5 KB, no longer a problem on Giga).

Pass = `/shooting/control/shutterbutton` returns 200, photo lands on SD card.

### Step 6 — One full subsystem side-by-side

Port just the gimbal-recon path (Gimbal Recon UI + /status endpoint + setPosControl). Run Giga in parallel with the Uno cart on the same network (different IP). Operator can drive gimbal from Giga's UI while the Uno still handles everything else.

Pass = parallel operation matches Uno behaviour exactly. No regression in slew accuracy, response time, network reliability.

This is the decision point. If step 6 passes cleanly, the migration is viable; commit to step 7. If step 6 reveals significant issues (e.g. CAN library quirks, timing differences, WiFi stack flakiness), abort and look for an Uno SRAM cleanup instead.

### Step 7 — Full port

Move everything else: plan executor, formula push, luminance, exposure, all UI screens, tracking. Swap cart hardware over.

## Pacing

Can be done over evenings, not all at once. Migration not committed until step 6 proves out. Bench setup needed: Giga + CAN transceiver + a known-good gimbal would make steps 1-3 concrete.

## Related workfronts

- **#58** Track-path cubic SRAM ceiling. Migration resolves this fully (N=16+ possible).
- **#59** Track runtime integration. Migration unblocks this immediately.
- Future Cart features blocked by SRAM ceiling will all be unblocked.

## Recommendation

Start step 1 in a side session before any more cart-side feature work pushes RAM further. Steps 1-4 individually are short evenings. Steps 5-6 are larger. Don't begin step 7 until step 6 is solid.
