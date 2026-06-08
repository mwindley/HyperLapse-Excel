# WORKFRONTS.md — Day 23 update block

**Paste into WORKFRONTS.md as the new most-recent dated update (above
the Day-18 update). Apply the status-line changes noted at the bottom.**

---

## Day 23 update (added 29 May 2026)

Hardware bring-up session. **Cart recommissioned on the Giga R1 —
all existing capability back online, verified running together for the
first time.** Day 22 had proven CAN and the W5500 each in isolation
(STUB_CART on, one subsystem at a time). Day 23 brought the whole
existing stack up together: CAN gimbal + Tic-I²C + steering servo +
WiFi/Excel/UI + D7 shutter. Verified low-to-high integration order,
no faults.

Scope was bounded to *existing capability*. BNO085 full integration
(#40) and W5500 wired Ethernet (#69) are NOT in this session — next
work, separate.

**Recommissioning order (each verified before the next):**

1. **CAN quick repeat** (Day-22 sketch, STUB_CART still on). TX
   `/home` → slew, yaw read back 0.3. RX hand-move → yaw -37.1 /
   pitch -18.9 tracked. Bidirectional confirmed, Day-22 reproduced.
2. **I²C scan** (standalone no-motion scanner on Wire D20/D21).
   Exactly three acks: 14, 15, 0x4A. No phantom 0x60. External
   4.7 kΩ pull-ups good with all three on the bus.
3. **D7 shutter** (production sketch, STUB_CART still on so shutter
   is the only variable). `/shutter/pin8` → red LED + image on card.
4. **STUB_CART removed**, reflashed. First un-stubbed boot:
   `[Cart] Tic controllers and servo initialised.`, servo snapped to
   centre, no I²C hang.
5. **Servo** `/btn4` → +5 ramp at 1°/s and settle, `/btn3` back.
6. **Tic drive** (Cart Recon UI): energise → +1 → +10 → STOP decel.
   Full motion path confirmed.

**Workfront status changes:**

- **STUB_CART removal — DONE.** Bench stub out of
  DJI_Ronin_Giga_v2.ino; Tic/servo init live.
- **#47 Giga migration — recommissioning of existing capability
  COMPLETE.** Steps 1–5 plus the Step-7 v2 sketch all validated
  running together on the assembled cart for the first time. **Step 6
  (side-by-side subsystem coexistence) effectively satisfied** by this
  integrated bring-up. Remaining gate: **#63 multi-hour soak** before
  Step 7 is declared fully done. Step 7 real-gimbal validation done
  in substance (CAN drives the real RS4 Pro bidirectionally).
- **#54 Gimbal slew overshoot** — not exercised this session
  (no large showastro slews run); remains open/deferred.
- **#63 Multi-hour soak of Giga v2 sketch** — now the single
  outstanding gate on #47 Step 7. Unblocked: flash + integrated
  bring-up have landed. Run a representative sunset→sunrise envelope
  with Excel driving; watch for blocking-call stalls, heap
  fragmentation, mbed-os starvation, silent WiFi disconnects, and
  the #52 cliff / #61 ISR-vs-network risks (load/duration-dependent,
  did not surface in the short bench bring-up).
- **#40 BNO085 integration — bench-validated on Giga, build still
  open.** Giga-safe polled bench sketch (no setClock, no INT/RST,
  Wire D20/D21): connected, rotation vector @10 Hz, figure-8 → acc
  0→3, stable at rest, true_yaw offset path works. Heading vs iPhone:
  magnitude ±0.5°; **sign opposite** — a deliberate 40° CW rotation
  read true_yaw -40 (BNO CW = negative; compass CW = positive). Build
  note: negate BNO yaw when folding into gimbal correction. Production
  sketch still STUB_BNO (Ry=Cy). Remaining: correction scalar +
  cubic-eval application, `/debug/imu`, two-attempt retry at
  500/400 mm, CartLog `A` events, Excel-pushed `bnoOffsetDeg`.
- **#68 D9 shutter-readback — DONE.** Stripped (define, pinMode, three
  digitalRead calls in backupShutter); D7 200ms pulse timing preserved
  exactly; D9 unwired/free. No digitalRead calls remain in the sketch.
- **#69 W5500 wired Ethernet — INTEGRATED + proven in production
  sketch.** Compile-time `STUB_WIRED_ETHERNET` switch (DEFINED=WiFi
  CCAPI .1.99 / UNDEFINED=wired CCAPI .20.99; WiFi/UI run in both).
  `ccapiRequest()` switches WiFiClient↔EthernetClient; body otherwise
  unchanged (already uses manual bounded wait, no setConnectionTimeout).
  **Both builds compile** (WiFi 379,508/19%; wired 394,588/20%, +15 KB
  for Ethernet lib) — confirms Ethernet.h + WiFi.h coexist in the full
  build. Wired CCAPI proven in the real sketch: `/exposure/init` →
  ok:true, Tv=1/5000 ISO=320, two REQ-PHASES round-trips at 67/63 ms,
  connect 0–1 ms. Decision was `#define` not runtime (production ships
  one transport; soak each, then pick). Remaining: #63 soak of each
  build + final WiFi-vs-wired decision. Shutter-over-CCAPI stays a
  separate deferred question.
- **AR3277 WiFi aerial fitted** — RSSI -67/-68 dBm (bare) → **-31 dBm**.
  Coupling confirmed; supersedes the earlier weak-RSSI flags.
- **D7 shutter — first live frame on the assembled Giga.** D8→D7 was a
  Day-18 pin-plan decision (D8 freed for potential Wire2), in the
  sketch since the port; today fired the first real photo on the
  assembled cart. Verification of the existing assignment, not a new
  change.

**Note — dead stop (btn12) absent from Cart Recon UI:** confirmed
intentional (Day-16 v2 spec removed DEAD from the Cart Recon motor
row). Operator confirms acceptable for recon — de-energise covers
"stop now"; dead-stop's haltAndHold-lock matters for Execution
precision, not recon. Handler still fires by URL. **No workfront
raised.**

---

## Status-line changes to apply elsewhere in WORKFRONTS.md

- **Header "As of:"** → update to Session H day 23, 29 May 2026.
- Any line still implying the cart is the Uno R4 or that Giga
  capability is unproven on the assembled cart is stale — existing
  capability is recommissioned and verified on the Giga as of Day 23.
