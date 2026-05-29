# Opto Test Plan — Logic Analyser Diagnosis

**Status:** Parked, ready to execute when SparkFun TOL-18627 arrives.
**Goal:** Determine whether the 2-4% photo drop (CCAPI active, Tv=0.8"+3s) is electrical (opto/cable) or camera-side (firmware busy with CCAPI).

---

## Hardware ready

- **4N25 replacement on breadboard** — wired and ready to swap in if diagnosis points at the opto. Pin 1 (anode) ← 220Ω ← Uno pin 8; pin 2 (cathode) → GND; pin 5 (collector) → Canon Shutter; pin 4 (emitter) → Canon Ground. Pins 3/6 NC.
- **Spare stereo socket with jumper tails** — to be soldered. Three tails (Shutter, Focus, Ground) even though only Shutter + Ground used in production. Inserts between existing opto's stereo plug and the Canon cable that goes to camera. No production cable disturbance.
- **Existing opto** — left in place, sealed/wrapped, untouched until diagnosis complete. Measure suspect before swapping.

## Hookup

Two channels + ground, all referenced to Uno GND.

| Channel | Tap point | What it measures |
|---|---|---|
| CH0 | Pin 9 header on Uno (shares pin-8 signal via existing Y-split — `CART_SHUTTER_READBACK`, see `.ino` line 179) | Pin-8 drive signal *as the opto sees it on the input side* |
| CH1 | Shutter tail on spare stereo socket, inserted between opto plug and Canon cable | Opto output / camera input |
| GND | Uno GND header | Shared reference |

**Pin 9 sharing:** plug the analyser clip's leg into pin 9 alongside the existing readback jumper. Both reference the same pin 8 Y-split. Cart firmware readback keeps running as a sanity cross-check.

## Skip Stage 1 — go straight to camera + CCAPI

Original plan had a sterile Stage 1 (no camera, no CCAPI, with a 10kΩ pull-up on the Shutter tail to provide a defined high level). Skipped — the question we care about is whether the electrical path is clean *during real drops*, which only happens with CCAPI active and camera connected. Camera provides the Shutter pull-up natively.

## Capture setup (PulseView)

- **Sample rate:** 2 MHz. Comfortable headroom over the ~6µs cart edges and ~2-5µs typical 4N25 edges. (24 MHz max on the analyser; nowhere near needed.)
- **Mode:** Streaming. fx2lafw streams over USB; 2 MHz × 2 channels ≈ 4 Mb/s, well within USB 2.0. ~450 MB raw for 15 min, much less compressed.
- **Trigger:** Single trigger on first CH0 rising edge after pressing Run, then free-run / continuous capture.
- **Duration:** 15 min run at Tv=0.8"+3s ≈ 300 pin-8 pulses. At 2-4% drop rate that's 6-12 drop events — enough to see a pattern, short enough that disk + focus hold.

## Cross-reference plan

The analyser timeline runs on its own clock; cart logs run on `millis()`. To align them post-hoc:

1. PulseView armed, streaming, waiting on CH0 rising-edge trigger.
2. Hit `http://192.168.1.97/shutter/start` — cart serial logs `T=0 [start]`, first pin-8 pulse triggers the analyser, all subsequent pulses align by index.
3. Run 15 min.
4. `http://192.168.1.97/shutter/stop` — reports `photos_taken=N`.
5. Card image count.

## The four numbers

After each run, reconcile:

| cart pulses | CH0 pulses | CH1 pulses | card images | Verdict |
|---|---|---|---|---|
| 300 | 300 | 300 | 300 | Nothing dropping — push to harder edge case |
| 300 | 300 | 300 | 290 | **Camera dropped despite clean electrical → CCAPI/firmware suspect** |
| 300 | 300 | 290 | 290 | **Opto failed to pass pulses → opto swap justified** |
| 300 | 290 | 290 | 290 | Cart fired but didn't drive line → cart wiring fault |

The row-2 vs row-3 distinction is the entire diagnosis. Row 2 → swap opto won't help; row 3 → swap opto.

## Post-hoc analysis in PulseView

Load the streamed `.sr` file, scroll/search for CH0 rising edges that don't have a matching CH1 falling edge within ~50µs of CH0's rise. Those are the electrical drops, if any exist.

## Software setup notes

- **PulseView** (sigrok GUI) — Windows installer from sigrok.org/wiki/Downloads bundles backend + GUI.
- **Zadig** for one-time WinUSB driver swap on first plug-in (2-min setup, covered on the SparkFun TOL-18627 product page).
- No power required beyond USB.

## What we expect (priors, not predictions)

- Cart-side pin-8 already measured pristine (day-9, rise/fall 6-7µs, high 28395-28405µs, gap 3000-3010ms). CH0 should confirm this.
- Intervalometer (bypasses opto AND CCAPI) hits 100% on the same camera+cable — so the camera+cable physical path is innocent when CCAPI isn't running.
- The remaining 2-4% drop co-occurs with CCAPI activity. The plausible mechanisms are:
  - Opto degraded under thermal/electrical stress → would show as missing/weak CH1 pulses
  - Camera firmware deprioritising shutter input under CCAPI HTTP load → would show as clean CH1 pulses with no shutter actuation
- Row 2 outcome is consistent with "photos sacred, never delayed" architectural principle: CCAPI fetch never blocks photo cadence on the cart, but the *camera* may be doing its own blocking internally.

## After diagnosis

- **Row 2 (camera-side)**: don't swap opto. Add to workfronts: investigate CCAPI quiet windows, or fetch-during-camera-busy avoidance. The 4N25 breadboard build stays on the shelf as a spare.
- **Row 3 (opto)**: swap to the 4N25 breadboard build, re-run the same test, confirm CH1 cleanliness improves and delivery rate climbs.
