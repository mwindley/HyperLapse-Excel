# Giga R1 — Cart Firmware Design

**Status:** draft v0, Day 18. Captures the architectural target for the Giga cart firmware as Excel-vs-Giga development begins, before any large code is written.

This doc is the design contract between Excel and the Giga. It does not specify implementation order — that's `GIGA_MIGRATION_STRATEGY.md` (Steps 1–7). It does specify what the finished Giga should be, so that the implementation steps converge on it.

---

## 1. Role in the system

The cart is one of four runtime actors:

```
                   Excel (operator's laptop)
                          │
                          │ WiFi (external AP, e.g. Rosedale)
                          │
        ┌─────────────────┴─────────────────┐
        │              Giga cart            │
        │  (operator UI · plan executor ·   │
        │   gimbal driver · photo timer)    │
        └──┬────────┬──────────────┬────────┘
           │        │              │
       I²C │    CAN │              │ WiFi or Ethernet
           │        │              │
    ┌──────▼──┐ ┌───▼────────┐ ┌──▼─────────┐
    │ Pololu  │ │ DJI Ronin  │ │ Canon R3   │
    │ Tics    │ │ RS4 Pro    │ │ (CCAPI)    │
    │ (motors)│ │ (gimbal)   │ │            │
    └─────────┘ └────────────┘ └────────────┘
```

Excel owns the **plan**. Cart owns the **execution**. Camera takes **photos**.

The Giga's job in one sentence: **translate Excel's plan (pushed once) and Excel's real-time commands (during execution) into cart motion, gimbal pose, and camera exposure, while firing photos on its own schedule.**

The cart is "dumb" in the sense that it does not author plans. It is "smart" in the sense that it owns time-critical loops (pin-8 cadence, luminance walk, gimbal cubic evaluation, motor velocity) that would be too jittery if driven from Excel.

---

## 2. Endpoint surface

Every Excel→cart call is HTTP GET. No POST or PUT from Excel. Bodies are encoded as query strings.

### 2.1 Recon stage (operator drives manually, cart records)

| Endpoint | Purpose | Response |
|---|---|---|
| `/btn{N}` | Operator UI button press (steering, speed, motors, log, waypoint). N=1..22 per UI_DESIGN_v2. | `OK` |
| `/status` | Polled by Excel and by browser UI. 13 CSV fields: yaw, roll, pitch, heartbeat, steering, voltage, velocity, overdrive, recording, gimbalLogCount, motor_state, waypoint_count, mm_since. | CSV |
| `/cartlog` | Retrieve-and-clear CartLog buffer. Returns S/T/X/W event rows with timestamps and Tic step counts. | text |
| `/gimballog` | Retrieve-and-clear GimbalLog buffer. Returns timestamped yaw/pitch waypoints. | text |
| `/heartbeat?msg=HH:nn:ss` | Excel keepalive. Stored for /status reporting. | `OK` |
| `/cameramsg?msg=...` | Push exposure trio string (Av, Tv, ISO) for cart's gimbal-mounted display. | `OK` |

### 2.2 Plan push stage (Excel sends prebaked plan to cart, one-shot before shoot)

| Endpoint | Purpose | Response |
|---|---|---|
| `/exposure/load?...` | Appendix A formula push. ~1.3 KB query string. Tv ceiling, ISO ceiling/base, sunset/sunrise Tv crossovers, sunset/sunrise ISO ramps, time anchors. Cart uses this in TABLE mode (camera comms down) or as the master exposure walk on v2 wired link. | `OK` |
| `/settings/astropos?...` | 5 yaw/pitch pairs (sun rise/set, MW rise/mid/end). Cart serves these via `/gimbal/showastro`. Moon deferred (#55). | `OK` |
| `/settings/trackpath?obj=&seg=&ts=&te=&ay0..3=&ap0..3=` | Per-segment cubic polynomial coefficients for sun and MW gimbal tracking. Per object, multiple segments stitched at runtime. | `OK` |
| `/settings/...` (other) | Yaw envelope, BNO offset, other prebaked Settings values. Push pattern same as above. | `OK` |

### 2.3 Execution stage (Excel walks Sequence sheet via OnTime, fires commands)

| Endpoint | Purpose | Response |
|---|---|---|
| `/btn{N}` | Repeated `/btn{6,7,9,10}` for ±1/±10 m/hr speed steps. `/btn{1,2,4,5}` for steering. `/btn11` for stop. `/btn8` for decay. | `OK` |
| `/move?yaw=&roll=&pitch=&time=` | Gimbal absolute move with timed easing. Yaw is cumulative (cable budget enforced by Excel). | `OK` |
| `/home` | Gimbal to (0,0,0). | `OK` |

### 2.4 Cart-internal (cart talks to camera, not Excel)

| Endpoint | Purpose |
|---|---|
| `GET /ccapi/ver100/shooting/liveview/flipdetail?kind=info` | Luminance histogram fetch every Nth photo. Binary frame (FF 00 01 + size + JSON), 4.5–5 KB. |
| `POST /ccapi/ver100/shooting/liveview` | Liveview start (one-shot per shoot). |
| `PUT /ccapi/ver100/shooting/settings/tv` | Tv nudge from cart-side luminance walk. |
| `PUT /ccapi/ver100/shooting/settings/iso` | ISO nudge. |
| `POST /ccapi/ver100/shooting/control/shutterbutton` | (v2 optional) Replace pin-8 shutter with CCAPI fire over wired Ethernet. |

Pin-8 stays the production shutter on v1 and is retained on v2 as fallback unless retired by operator decision.

---

## 3. Internal state

The Giga holds three buckets of state.

### 3.1 Recon state (transient, retrieve-and-clear)

- **CartLog** — ring buffer of S/T/X/W events. Sized at TBD (Uno had 64 max; Giga can have 1000+ trivially). Cleared by `/cartlog` GET or `/cartlog/clear`.
- **GimbalLog** — ring buffer of (ts, yaw, pitch) waypoints. Sized similarly.
- **Live pose state** — `g_yaw`, `g_roll`, `g_pitch`, `g_focus` updated by CAN push frames from the gimbal at ~10 Hz.
- **Cart motion state** — `cart_motor_state` (DE-E / STOP / ENRG), `cart_velocity_factor`, `cart_steering`, `cart_overdrive`. Updated by `/btn` handlers.
- **Waypoint counter** — incremented by btn22 (Mark Waypoint).

### 3.2 Plan state (pushed by Excel, persistent for shoot duration)

- **Exposure formula (Appendix A)** — Tv/ISO ladders, time anchors, ceilings. Pushed by `/exposure/load`. Used by TABLE mode and luminance walk.
- **Astro positions** — 5+ yaw/pitch pairs. Pushed by `/settings/astropos`. Used by `/gimbal/showastro`.
- **Track path cubics** — per-object, per-segment polynomial coefficients. Pushed by `/settings/trackpath`. Evaluated at runtime by the track runtime block (#59) to drive gimbal during shoot.
- **Yaw envelope** — `gimbalYawEnvelopeMin/Max` (default ±225°). Enforced cart-side on `setPosControl` calls. Excel also enforces at command time.
- **BNO offset** — declination + bench offset, single float. Applied to every BNO yaw reading.

### 3.3 Runtime state (cart's own bookkeeping)

- **Photo cadence** — pin-8 timer. Fires every (Tv + 1.5s) seconds when `shutter_mode = 3`. Owned by cart, not Excel.
- **Luminance fetch state** — `lum_last_value`, `lum_target`, `lum_mode`, fetch counter (every Nth photo).
- **Exposure mode** — `LIVE` or `TABLE`. Defaults LIVE; flips on comms failure.
- **Comms mode** — `NORMAL`, `PROBING`, (no TABLE bucket — TABLE is exposure-side). Manages 3-fail ping detection (v1) or replaced by always-live wired link (v2).
- **HTTP request log** — optional `req_log_enabled` for instrumentation.
- **Plan execution state** — current segment index, segment timer, at-rest gate, decay state. Cart-side plan executor (#5a, in development).

---

## 4. What survives from Uno v1prod, what changes

### 4.1 Survives unchanged

- **DJI R SDK frame format** (CRC16 + CRC32 tables, frame builder, push subscribe at 0x0E/0x07, position parse at 0x0E/0x08). Step 3 sketch confirms `Arduino_CAN` library API is identical.
- **Pin-8 shutter logic** — 200ms HIGH pulse, photo cadence timer. Just moves to pin D7 per pin plan.
- **Luminance histogram parse** — binary frame (FF 00 01 + size), Y-channel mean computation. Step 5b validated.
- **Tic API** — `setTargetVelocity`, `energize`, `exitSafeStart`, `haltAndHold`. Step 4 confirmed.
- **CCAPI request pattern** — explicit `\r\n` headers, bounded body read, binary-frame parsing. Step 5/5b validated.
- **Operator UI HTML/JS** — three-screen routing (Cart Recon / Gimbal Recon / Exec), shared header + tab bar. Step 6 confirmed verbatim port works.
- **Plan executor (#5a Day 17)** — segment dispatcher M/S/E/D, at-rest gate, time-based open-loop completion. Brings forward as-is.

### 4.2 Changes for Giga

- **`Wire` bus is on pins 20/21, not D18/D19.** External 4.7kΩ pull-ups required (no internal pull-ups on STM32 I²C).
- **WiFi library is `WiFi.h`** (not `WiFiS3.h`). Same `WiFiClient` API. Static IP via `WiFi.config()`.
- **CAN moves to dedicated CANTX/CANRX pins** (off D10/D13). Library API unchanged.
- **HTTP outbound requests must use explicit CRLF** (`\r\n`). `client.println` sends bare LF; Canon CCAPI rejects with 400 + empty body.
- **`Wire.setClock(50000)` blocks mbed Wire** — leave default. Pull-ups handle marginal-bus issues instead.
- **`PROGMEM` and `F()` become no-ops.** Strings live in RAM. With 1 MB RAM available it doesn't matter, but the assumption changes.
- **`String` heap behaviour differs.** mbed allocator is different from AVR newlib. Multi-hour shoots need soak testing.
- **Defensive disciplines per workfront #61:** bounded network timeouts (≤2s), `delay(1)` at bottom of loop, fixed-buffer `snprintf` for hot paths, CAN RX in ring buffer never touching network code.

### 4.3 No longer needed

- **SRAM ceiling avoidance.** TRACK_SEGS_MAX=2 → N=16+ trivial. CartLog and GimbalLog buffers can be ten times larger.
- **PROBING state machine for connect-fail.** v2 wired Ethernet eliminates the failure mode. v1 keeps it; Giga v1-equivalent on WiFi-only also keeps it.
- **Appendix A as primary exposure source.** Cart's CCAPI luminance walk is the primary path; Appendix A is the TABLE-mode fallback. Same as v1 architecturally but with reliability boosted by the wired link.

---

## 5. Deferred to later in migration

Items that are part of the Giga design but not built yet, and not needed for Excel-vs-Giga development to begin:

### 5.1 Hardware-blocked

- **CAN comms** — Step 3 sketch ready, waiting on transceiver. Until CAN lands, `g_yaw/roll/pitch` are placeholder globals. Excel pulls /status and reads zeros for pose.
- **BNO085 integration** — UART-RVC wiring confirmed on hand, but #40 build pending. Ry=Cy shortcut until then.
- **W5500 Ethernet shield** — pending order. v2 wired-camera path not testable until shield arrives.

### 5.2 Code-blocked

- **Track runtime block (#59)** — 1 Hz cubic evaluator drives gimbal from pushed trackpath data. Drafted Day 17 on Uno, reverted (SRAM). Trivial to add on Giga; deferred until basic Excel-vs-Giga flow works.
- **Plan executor full reuse (#5a M/S/E/D dispatcher)** — Day 17 architecture proven on Uno; needs porting to Giga.
- **Camera control over wired Ethernet (v2)** — W5500 + Ethernet library. Cart→camera path on a second interface alongside cart→external-AP WiFi.

### 5.3 Cleanup-blocked

- **Excel Camera.bas cleanup (#62)** — Camera.bas has dead per-photo CCAPI walk and Python luminance pipeline. Removing it changes no runtime behaviour but clarifies the live architecture. Do during the Giga port pass when Excel HTTP calls are being repointed anyway.

---

## 6. Open questions

Not blocking; capture here so they don't get lost.

- **IP allocation.** Giga sits at 192.168.1.95 during parallel development. Final production IP after Step 7? Same as Uno (.97), or new permanent?
- **Cart UI ports.** v1 UI runs on port 80. v2 wired Ethernet to camera puts cart on a second IP/interface. Does the operator UI live on the WiFi interface only, or both?
- **Shutter retirement (v2 architectural principle #12).** Drop pin-8 in favour of CCAPI shutter over wired Ethernet? Decision deferred until v2 hardware is on the bench.
- **CartLog and GimbalLog buffer sizes.** Uno had 64-ish entries. Giga can hold thousands. What's the right size — enough for a full recon (~30 minutes at scout speed) or unlimited streaming to Excel?
- **String response building.** Workfront #61 risk #2 says replace String concatenation with snprintf in hot paths. Is /status hot enough to need this, or only the /cartlog/dump path?

---

## 7. Implementation order

This is the contract; the implementation order is in `GIGA_MIGRATION_STRATEGY.md`. To summarise:

- **Steps 1, 2 passed** — toolchain, WiFi.
- **Step 3 paused** — CAN, waiting on transceiver.
- **Steps 4, 5, 5b passed** — I²C/Tics, CCAPI, full-luminance headroom.
- **Step 6 scaffolded** — three-screen UI port, /status with placeholder pose data, ready for Excel-vs-Giga work.
- **Step 7 deferred** — full port, after Step 6 validates against real gimbal.

Excel-vs-Giga development sits between Step 6 (scaffold) and Step 7 (full port). The Giga gets the Excel-facing endpoint surface above, with placeholder backing where hardware isn't connected. Excel drives the full plan-push and execution flow against the Giga without needing the gimbal or motors running.

This means the Giga becomes a useful **simulator** for Excel development before any hardware-blocked piece lands. When a piece lands (transceiver, BNO, Ethernet), it slots into the existing endpoint surface without changing Excel.
