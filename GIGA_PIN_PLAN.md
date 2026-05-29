# Giga R1 — Pin Assignment Plan

Draft v2 (Day 22). CAN Pal + CCAPI-over-HTTP current; D9 readback (#68)
and W5500 wired Ethernet (#69) are future workfronts. **BNO085 moved from
UART-RVC to I²C** — it's an occasional heading-truth reference, not a
continuous stream (see decision note under the pin map).

## What's connecting

Carried over from Uno R4 v1prod, plus the new BNO085:

- **CAN bus** → DJI Ronin RS4 Pro (via Adafruit CAN Pal, TJA1051T/3 — ID 5708)
- **I²C** → Pololu Tic Front (addr 14) + Tic Rear (addr 15) + BNO085 IMU (addr 0x4A) — all on the shared `Wire` bus
- **Servo** → steering (centre=98, range 60–130)
- **GPIO output** → camera shutter backup (pin-8 equivalent, active HIGH, 200ms pulse)
- **UART** → none in use. (BNO085 was previously planned on UART-RVC; it's now on I²C, so Serial2 / RX1-TX1 is free.)
- **WiFi** → already proven Step 2 (onboard Murata 1DX, no pins to allocate)
- **Future** → W5500 Ethernet shield (SPI) for v2 wired-camera path. Not in Step 3 scope but reserve the pins now.

## Giga R1 — what's available

The Giga has the Mega/Due form factor plus extra pin rows. Relevant peripherals:

- **4 UARTs** — Serial1 (TX0/RX0), Serial2 (TX1/RX1), Serial3 (TX2/RX2), Serial4 (TX3/RX3)
- **3 I²C buses** — Wire (SDA/SCL on pins 20/21), Wire1 (SDA1/SCL1 near AREF), Wire2 (pins D8/D9 — collision risk, see below)
- **2 SPI buses** — SPI (ICSP header, default), SPI1 (pins 11/12/13)
- **1 FDCAN** — on the dedicated CANTX / CANRX pins on the digital row (external transceiver required)
- **76 GPIO** total, **3.3V logic** (no 5V tolerance!)

⚠️ **3.3V logic** — different from Uno R4, which is also 3.3V, so all carried-over wiring is fine. But double-check any 5V devices.

## Pin map (current)

Canonical Giga assignments as they stand now.

| Function | Giga pin | Note |
|---|---|---|
| **CAN TX** | CANTX (dedicated) | → CAN Pal CTX |
| **CAN RX** | CANRX (dedicated) | → CAN Pal CRX |
| **CAN mode select (S)** | GND | CAN Pal S tied low = normal/active mode |
| **I²C SDA** | D20 (Wire) | Tics + BNO085; external 4.7kΩ pull-up to 3.3V |
| **I²C SCL** | D21 (Wire) | External 4.7kΩ pull-up to 3.3V |
| **Steering servo** | D4 | PWM signal |
| **Camera shutter** | D7 | 200ms HIGH pulse |
| **W5500 chip-select** | D10 | SPI CS |
| **W5500 SPI (CIPO/COPI/SCK)** | ICSP header | Default SPI bus |
| **W5500 INT** | D2 | Reserved; unused by the polled direct-SPI path |

**I²C addresses (Wire bus):** Tic Front `14`, Tic Rear `15`, BNO085 `0x4A`.

**Optional:** BNO085 INT/RST — only if you move off pure polling; any free pin, **not D7**.

**Onboard, no pins:** WiFi (Murata module).

**Free / spare:** D2 (while W5500 INT stays unused), D5, D6, D8 + D9 (= Wire2, a full third I²C bus), D11/D12/D13 (= SPI1, a spare SPI bus).

**Power:** VIN (6–24V) or USB-C; 3.3V rail for all logic; GND. All logic is 3.3V — no 5V tolerance.

### Why BNO085 is on I²C, not UART-RVC (Day 22 decision)

The IMU is used only as an occasional heading-truth reference — a handful of
reads across a 12-hour shoot, taken with the cart at rest just before an
important gimbal waypoint. It gives the cart's *actual* heading so accumulated
steering error can be folded into the gimbal's real-world-yaw offset. The shoot
is slow (5 m/hr; pan-follow / lock / sun-track / Milky-Way-track) with a
~1-minute lead before each important waypoint.

That duty cycle favours I²C polled reads over the RVC stream:

- **Accuracy gating.** The I²C rotation vector exposes an accuracy field (0–3);
  UART-RVC does not. For a correction reference we must confirm the
  magnetometer fusion has converged before trusting a reading — the 1-minute
  at-rest window is ample for it to settle.
- **On-demand, not continuous.** RVC would stream 100 Hz for 12 hours to catch
  a few frames; I²C is read only when a waypoint needs it.
- **Frees Serial2.** RX1/TX1 are no longer reserved for the IMU.

Trade-off accepted: the BNO joins the Tic `Wire` bus, so the external pull-up
discipline matters more (three devices now) and the no-`setClock` rule stands.

## Collisions / things to watch

1. **The pins near AREF are `Wire1` (SDA1/SCL1), NOT `Wire`.** The Giga's main `Wire` bus is on pins **20 (SDA) and 21 (SCL)** at the other end of the digital header row. Easy to wire to the wrong pair — the silkscreen near AREF reads "SDA1/SCL1". Confirmed Day 17+1 (Step 4).

2. **External pull-ups required on every I²C bus.** Giga's mbed Wire stack does not apply internal pull-ups when the pins switch to peripheral mode. 4.7kΩ to 3.3V on each of SDA and SCL is mandatory. Without them, lines float ~1.4V and no device acks. Confirmed Day 17+1.

3. **`Wire.setClock(50000)` blocks the Giga.** Leave default clock. Pololu's "slow clock for marginal pull-ups" advice was for the Uno; on Giga it locks up `Wire.begin()`. Use proper external pull-ups instead.

4. **mbed Wire error codes differ from AVR.** `Wire.endTransmission()` returns `1` for NACK, not "data too long" as the AVR comment suggests. err=1 means "no device acknowledged at that address."

5. **Phantom 0x60 in I²C scan.** With nothing wired to the bus (just pull-ups), Giga's mbed Wire reports a phantom device at 0x60. Harmless — disregard 0x60 in scan output.

6. **Wire2 lives on D8/D9 — both now free.** D8 freed when the shutter moved to D7; D9's shutter-readback is confirmed not required (Day 22), so D9 is free too. Wire2 is therefore fully available as a third I²C bus if ever wanted — e.g. to give the BNO085 its own bus, isolated from the Tic traffic. Currently unused. (#68 is now just the code strip: remove the `digitalRead` calls in `backupShutter()`.)

7. **SPI1 lives on D11/D12/D13.** D11/D12/D13 are free for SPI1 if needed. Default SPI is on the ICSP header anyway, so SPI1 stays as a spare bus.

8. **CANRX / CANTX can double as ADC pins** (per Arduino docs) but we need them for CAN. Don't reuse.

9. **Pin numbering on the Giga is Mega-style**, not Uno-style. D4, D7, D10, D13 all exist and behave as expected. The new pins are D54+ on the extra rows — none of those are needed yet.

10. **3.3V logic.** Tic 36v4 I²C lines are 3.3V-tolerant (per Pololu datasheet) — fine. The Adafruit CAN Pal (TJA1051T/3) interfaces 3.3V–5V logic and runs its CAN core off an onboard charge pump, so VCC=3V3 keeps CTX/CRX at Giga-safe 3.3V — fine. BNO085 I²C is 3.3V — fine. Servo signal is 3.3V-driven but most hobby servos accept 3.3V PWM, just verify the steering servo responds the same.

11. **BNO085 shares the `Wire` bus (addr 0x4A).** No address clash with the Tics (14, 15) or the phantom 0x60. The Adafruit 4754 breakout carries its own onboard pull-ups (~10kΩ); in parallel with the external 4.7kΩ that's ~3.2kΩ effective — still fine at 3.3V on the default I²C clock, just be aware when scoping the bus. IMU is read on-demand (polled) only, while the cart is stopped before an important gimbal waypoint — it does not poll continuously.

## Power

- Giga input: 6-24V via VIN, or USB-C. The cart's existing power feed should work as-is.
- 3.3V rail powers all logic.
- Tic 36v4 has its own motor power supply — only the I²C signal pins connect to the Giga.

## What this means for Step 3 (CAN-only)

Wire just two things:
- **Adafruit CAN Pal (TJA1051T/3)**: connect Giga **CANTX → CAN Pal CTX**,
  Giga **CANRX → CAN Pal CRX**, CAN Pal **S → GND** (normal mode — must be
  tied low or the bus is dead), CAN Pal **VCC → 3V3** (onboard charge pump
  generates the 5V the transceiver core needs — no external 5V required),
  **GND → GND**, CAN Pal **CANH/CANL → gimbal CAN bus**.
- **Termination**: the CAN Pal has onboard 2×60Ω (120Ω) switched via the
  onboard slide switch. The Uno setup already worked, so the gimbal end is
  presumably terminated — start with the CAN Pal switch OFF and only enable
  if the bus needs it. (Don't double-terminate.)

That's all. No I²C, no servo, no shutter, no BNO yet — Step 3 isolates CAN.

## Open questions

- W5500 shield — **arrived** (Day 22). Wiring deferred to workfront #69;
  current session is CAN bus + CCAPI-over-HTTP (WiFi, `STUB_WIRED_ETHERNET`).
  Pin reservation (D10 CS, D2 INT, ICSP SPI) holds.
- BNO085 confirmed on hand and bench-tested over I²C (rotation vector +
  accuracy) on the Uno R4. Production: I²C on the `Wire` bus (D20/D21),
  addr 0x4A, polled on-demand. Earlier UART-RVC / Serial2 plan superseded —
  see the decision note above the collisions section.
- No other devices to capture at this time.

## Future workfronts raised here

- **#68 — Remove D9 shutter-readback** (decision confirmed Day 22: not
  required). Strip the `CART_SHUTTER_READBACK` pinMode + the three
  `digitalRead` calls in `backupShutter()` from DJI_Ronin_Giga_v2.ino. D9 is
  already treated as free for planning; this is the remaining code cleanup.
  Leave D9 unwired.
- **#69 — W5500 wired-Ethernet build.** Hardware on hand. Wire per reserved
  pins (D10 CS, D2 INT, ICSP SPI), then undefine `STUB_WIRED_ETHERNET` to
  route CCAPI over the wired subnet. Out of scope for the current CAN +
  CCAPI-over-HTTP session.
