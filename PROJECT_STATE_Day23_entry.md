# Session H — Day 23 (29 May 2026) — Cart recommissioned on Giga (existing capability)

**Paste this entry into PROJECT_STATE.md as the new most-recent
session block (above the Day-22 entries).**

---

## Session H — Day 23: full-assembly recommissioning on the Giga R1

First integrated power-up of the reassembled cart on the Giga. Day 22
had proven CAN and the W5500 each in isolation on a stripped bench
(STUB_CART on, single subsystem under test). This session brought the
whole existing stack up together for the first time — CAN gimbal +
Tic-I²C + steering servo + WiFi/Excel/UI + D7 shutter — and verified
each subsystem in a low-to-high integration order. **All existing
capability is back online on the Giga.** No faults across the bring-up.

Scope was deliberately bounded to *recommissioning existing
capability*. BNO085 full integration (#40) and the W5500 wired-Ethernet
build (#69) are explicitly NOT in this session — they are the next
work, handled separately as new capability.

### Recommissioning order (each verified before the next)

1. **CAN — quick repeat (Day-22 sketch as-is).** Booted with STUB_CART
   still defined (CAN-only config). Clean boot: CRC self-test OK, CAN
   1 Mbps ready, push subscribe sent, WiFi STA at 192.168.1.97.
   - **TX:** `GET /home` → gimbal slewed home, `/status` read back
     yaw 0.3 (settle tolerance, dead on).
   - **RX:** moved gimbal by hand → `/status` tracked yaw -37.1 /
     pitch -18.9. Pose-push frames arriving, reassembling, parsing.
   - Bidirectional CAN confirmed; Day-22 result reproduced.

2. **I²C bus scan (standalone scanner, no motion).** Used a minimal
   no-drive scan on `Wire` (D20/D21) rather than the production sketch
   or the Tic-driving Step-4 sketch — one-variable discipline, and it
   sidesteps the Day-22 trap of an I²C read before the bus is trusted.
   - Full sweep returned exactly three: **14 (Tic front), 15 (Tic
     rear), 0x4A (BNO085)**. No phantom 0x60, nothing missing.
   - External 4.7 kΩ pull-ups confirmed working with all three devices
     on the shared bus.
   - NB: BNO presence confirmed at the bus level only. The production
     sketch does NOT read it (STUB_BNO defined; Ry=Cy shortcut). Live
     rotation-vector reads remain #40 build-phase work.

3. **D7 camera shutter (production sketch, STUB_CART still defined).**
   Reflashed to DJI_Ronin_Giga_v2.ino — flashed with STUB_CART STILL
   defined so the shutter was the only thing under test (D7 is not
   gated by any stub). Camera: manual mode, lens on, WiFi LAN, empty
   card.
   - `GET /shutter/pin8` → red LED, one image landed on card.
   - Sacred photo path confirmed on the Giga.

4. **STUB_CART removed — Tic/servo init live (first un-stubbed boot).**
   Commented out `#define STUB_CART`, reflashed. Boot now prints
   `[Cart] Tic controllers and servo initialised.` (replacing the
   STUB_CART-skipped banner), servo physically snapped to centre (98)
   on attach. Rest of boot identical to the CAN run. No I²C hang on
   the now-live Tic init.

5. **Servo steering.** `GET /btn4` (+5 off centre) → ramped smoothly
   at 1°/s and settled; `GET /btn3` returned toward centre. Smooth
   motion confirmed.

6. **Tic drive range (via Cart Recon UI on phone).** Energise → +1 →
   +10 → STOP (decel ramp). Turns, both speed steps, and the decel
   stop all good. Full Tic motion path confirmed: I²C bus, both
   motors, velocity ramps, decel stop.

### Notes

- **WiFi RSSI -67/-68 dBm** — healthier than Day-22's -81. Giga has no
  onboard aerial populated yet; the extension fitting is on, aerial
  arrives later today. Bench WiFi is fine as-is.
- **Dead stop (btn12) absent from Cart Recon UI — confirmed
  intentional, no action.** Per the Day-16 v2 UI spec, DEAD was
  removed from the Cart Recon motor row (STOP / DE-E / ENRG only);
  the handler still exists and fires by URL. Operator confirms this is
  fine for recon: de-energise covers the "stop now" need (cart coasts
  to halt), and dead-stop's haltAndHold-lock distinction matters for
  Execution precision, not recon. No workfront raised. (Execution
  screen, which was to own a quick-stop, remains a placeholder.)
- **Integration risks did NOT bite** in this short bring-up — #61
  (ISR-vs-network) and #52 (I²C cliff) are load/duration-dependent.
  Real confidence is the #63 multi-hour soak, not a bench check.

### Post-recommissioning bench work (same session, new capability)

After existing capability was recommissioned, two new-capability items
were bench-validated with standalone sketches (NOT folded into the
production sketch — STUB_BNO and STUB_WIRED_ETHERNET both stay defined
in DJI_Ronin_Giga_v2.ino; integration is the build work these unblock).

**BNO085 first-light on the Giga (polled, shared Wire bus).** Flashed a
Giga-safe rewrite of the Day-12 bench sketch — polled `begin()` (no INT
pin), no `Wire.setClock()` (hangs the Giga), `Wire` on D20/D21, no
INT/RST pins (matches the Day-22 I²C-on-Wire decision; D7 is the
shutter, not the BNO INT as the old Uno sketch had it).
- Connected, rotation vector @ 10 Hz. Figure-8 → `acc` climbed
  0→2→3, all axes responded through motion, converged and held
  stable at rest at **acc=3 (high)**.
- True-north offset path verified: `c` captured offset, true_yaw
  tracked.
- **Heading accuracy + sign convention:** deliberate 40° CLOCKWISE
  rotation → iPhone compass read 40°, BNO read true_yaw **-40**.
  Magnitude agrees within ~0.5°; **sign is opposite** — BNO reads
  clockwise as NEGATIVE yaw, compass/world reads clockwise as
  POSITIVE. *Build note for #40:* negate BNO yaw (or flip the
  correction-term sign) when folding into the gimbal yaw correction.
  Day-12 measured magnitude (±3°); this adds the sign characterisation.

**W5500 wired Ethernet — dual-interface CCAPI proven end-to-end.**
Used `W5500_relay.ino` (WiFi server + wired W5500 running
simultaneously; laptop→Giga over WiFi relays to camera over the wire).
Reuses the Day-22 proven stock-SPI path (`SPI.begin` → `Ethernet.init(10)`
→ `Ethernet.begin(mac, ip)`, NOT mbed EMAC; no `setConnectionTimeout`/
`setRetransmissionTimeout`).
- **Subnet design resolved (the Day-22 deferred question): camera moved
  to its own subnet.** Camera wired interface now **192.168.20.99**,
  Giga wired **192.168.20.98**; WiFi/Excel/UI stay on 192.168.1.x.
  No dual-.1.x routing ambiguity. Camera shows green LAN.
- Boot: WiFi 192.168.1.116, wired hwStatus=3, `wired_link` settled to
  1 (LinkON) after a couple of seconds (it reads 2/LinkOFF for the
  first instant before the PHY negotiates — read it after grace, not
  at the first sample).
- `/link` → wifi UP, wired_link 1. `/ccapi` → **200 ALIVE** + endpoint
  dump. `/get/tv` → 200, current Tv 1/8000 + full 60-value ladder.
  `/tv?v=1/5000` (PUT) → **200**, camera echoed 1/5000, confirmed on
  the camera body. GET and PUT both proven over the wire.
- An earlier `W5500_spi_connect.ino` run failed connect cleanly — it
  was still hard-coded to the OLD 192.168.1.99 camera address (stale
  after the subnet move), not a transport fault. The relay sketch on
  .20.x is the correct/current one.

### Production sketch — transport switch integrated + hygiene (same session)

After both new-capability items were bench-proven, the wired-CCAPI
path was integrated into DJI_Ronin_Giga_v2.ino as a **compile-time
transport switch**, and recommissioning hygiene was applied. Decision:
`#define`, not runtime — production ships ONE transport; A/B soak each,
then pick. (Runtime selection rejected: WiFi outage is handled by TABLE
mode; wired is the alternative, not a live failover, so no need to
carry both stacks in the shipped binary.)

**STUB_WIRED_ETHERNET is now a real switch (was comment-only):**
- DEFINED → CCAPI over WiFi, camera 192.168.1.99 (v1 path, unchanged).
- UNDEFINED → CCAPI over wired W5500, camera 192.168.20.99, Giga wired
  .20.98. Direct-SPI stock Ethernet (NOT mbed EMAC). WiFi/Excel/UI run
  in BOTH builds — only the camera transport changes.

Edits (all gated on the `#define`, so the WiFi build is behaviourally
unchanged bar the hygiene):
- `#include <SPI.h>`/`<Ethernet.h>` under `#ifndef`.
- `CCAPI_HOST` conditional (.1.99 WiFi / .20.99 wired), kept as a
  string both branches (EthernetClient::connect + Host header take it
  directly).
- Wired statics (mac, .20.98, CS=D10) + W5500 bring-up in setup()
  (`SPI.begin`/`Ethernet.init(10)`/`Ethernet.begin`).
- `ccapiRequest()`: one-line client-type switch (WiFiClient vs
  EthernetClient). Entire body otherwise unchanged — it already used a
  manual bounded wait, not setConnectionTimeout, so the Day-22
  EthernetClient trap doesn't apply.

**Hygiene (#68 + comments):**
- #68 D9 shutter-readback STRIPPED: the define, the setup() pinMode,
  and the three `digitalRead` calls in `backupShutter()`. D7 200ms
  pulse timing preserved exactly (busy-wait, identical duration). D9
  now unwired/free. Zero `digitalRead` calls remain in the sketch.
- Stale header comments fixed (BNO is I²C/0x4A not UART-RVC; W5500 is
  built not future).

**Both builds compile clean** (only the known Arduino_CAN/Servo
architecture-tag warnings, non-fatal):
- WiFi build: 379,508 bytes flash (19%), 92,392 globals (17%) —
  essentially identical to Day-22's 379,900, confirming no behavioural
  change.
- Wired build: 394,588 bytes flash (20%), 94,648 globals (18%) —
  +15 KB flash / +2.3 KB globals for the Ethernet library. **Resolves
  the open question: Ethernet.h and WiFi.h coexist in the full build.**

**Wired CCAPI proven IN THE PRODUCTION SKETCH (not just the relay):**
Flashed the wired build. Boot: `[WIRE] hwStatus=3 ip=192.168.20.98`,
WiFi up alongside at .97. `GET /exposure/init` (the CCAPI wake — forces
live Tv + ISO GETs through ccapiRequest) returned `ok:true
current_tv=1/5000 current_iso=320` — the 1/5000 being the exact value
PUT over the relay earlier. Serial showed two clean REQ-PHASES lines:
connect 0–1 ms, totals 67 ms / 63 ms, bodies 525 / 253 bytes. Wired
round-trips are fast and clean over the dedicated link.
(STUB_CART was left defined for this flash — Tic power was off and the
wired test needs neither cart nor motors. STUB_CART must come out for
any cart-involved soak.)

**AR3277 WiFi aerial fitted:** RSSI jumped from -67/-68 dBm (bare) to
**-31 dBm**. Aerial coupling confirmed good.

### Workfront status changes

- **STUB_CART removal — DONE** for the recommissioning verification.
  NB: was re-defined for the final wired-CCAPI flash (Tic power off);
  must be removed again for any cart-involved soak.
- **#68 D9 shutter-readback — DONE.** Stripped from the sketch; D9
  unwired/free.
- **D7 shutter — first live frame on the assembled Giga.** The D8→D7
  reassignment was decided in the Day-18 pin plan (D8 freed for a
  potential Wire2) and has been in the sketch since the port; today is
  the first time D7 fired a real photo on the assembled cart. Not a
  change made this session — a verification of the existing assignment.
- **#47 Giga migration — recommissioning of existing capability
  COMPLETE.** Steps 1–5 + the Step-7 v2 sketch all validated running
  together on the assembled cart for the first time. Step 6
  (side-by-side subsystem coexistence) is effectively satisfied by
  this integrated bring-up. **#63 multi-hour soak remains the gate
  before Step 7 is declared fully done.**
- **#40 BNO085 — bench-validated on Giga.** First-light to acc=3,
  stable, true_yaw path works, heading magnitude ±0.5° vs iPhone, sign
  convention characterised (BNO clockwise = negative; negate when
  folding into gimbal correction). Standalone sketch only —
  STUB_BNO still defined in production. Remaining: the integration
  build (correction scalar, `/debug/imu`, two-attempt retry, CartLog
  `A` events).
- **#69 W5500 wired Ethernet — INTEGRATED into the production sketch
  and proven.** Compile-time `STUB_WIRED_ETHERNET` switch; both builds
  compile; wired CCAPI round-trips proven in the full sketch via
  `/exposure/init` (67/63 ms, ok:true). Subnet design resolved (camera
  .20.99). Remaining: side-by-side soak of each build (#63) and the
  final WiFi-vs-wired production decision. The shutter-over-CCAPI vs
  sacred-D7 question stays separate/deferred.

---

## Corrections to apply elsewhere in PROJECT_STATE.md

1. **"State of the system (current)" → Hardware notes:** the line
   `Cart: Arduino Uno R4 WiFi at 192.168.1.97` is stale. The cart is
   the **Giga R1 at 192.168.1.97** (Uno retired Day 18); existing
   capability recommissioned and verified on it Day 23.

2. **Camera wired addressing:** the camera's WIRED interface is now
   **192.168.20.99 / 255.255.255.0** (moved off 192.168.1.99 for the
   dual-interface design). WiFi-side camera address (if ever used
   again) and all WiFi/Excel/UI traffic stay on 192.168.1.x.
   Production `CCAPI_HOST` becomes 192.168.20.99 when the wired path
   goes live (STUB_WIRED_ETHERNET undefined).
