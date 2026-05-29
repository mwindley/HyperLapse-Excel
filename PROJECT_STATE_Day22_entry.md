# Session G — Day 22 (28 May 2026) — Step 3 CAN PASSED on Giga

**Paste this entry into PROJECT_STATE.md as the new most-recent
session block (above the Day-18 entry). Also apply the two
corrections noted at the bottom.**

---

## Session G — Day 22: CAN transceiver replaced, Step 3 passed end-to-end

Hardware bring-up session. The SN65HVD230 cooked on Day 18 (reversed
3V3/GND during handling) was replaced with an **Adafruit CAN Pal
(5708, TJA1051T/3)** per GIGA_PIN_PLAN.md. Wired CAN-only on the bench
(Tic, servo, BNO, W5500 all unwired) to isolate CAN as the single
variable under test. Bidirectional CAN to the RS4 Pro confirmed
end-to-end. **Step 3 of GIGA_MIGRATION_STRATEGY is now PASSED** —
the last foundational subsystem, closing the gap left when the old
transceiver died.

### Hardware wiring (Adafruit CAN Pal 5708, TJA1051T/3)

Per GIGA_PIN_PLAN.md, confirmed correct by the test result:

- CAN Pal **CTX → Giga CANTX**, **CRX → Giga CANRX**
- CAN Pal **S → GND** (normal/active mode — the new pin the old
  SN65HVD230 didn't have; floating/high = silent mode = bus appears
  dead. Tied low, transmitter enabled.)
- CAN Pal **VCC → 3V3** — onboard charge pump generates the 5V the
  TJA1051 core needs; no external 5V, no VIO on this header variant
  (VCC/GND/CTX/CRX/S only). Confirmed against Adafruit product page.
- CAN Pal **GND → GND**, **CANH/CANL → gimbal CAN bus**
- Termination switch left as-is (gimbal end already terminated; the
  Uno setup worked, so not double-terminated).

### Arduino core updated to 4.x (mbed_giga) before session

The Arduino mbed Giga core was updated to the 4.x line before this
session (came up via the IDE; not a deliberate pre-test step). This
added a second variable on top of the new transceiver. Mitigation:
treated a clean compile + the boot CRC self-test as the toolchain
sanity gate before trusting any CAN result.

- **Compile warnings (both non-fatal, explained):**
  - `Arduino_CAN claims to run on mbed, mbed_portenta ... may be
    incompatible with mbed_giga` — architecture-tag metadata gap, NOT
    a functional break. `CAN.begin()` succeeding at runtime proved the
    bundled Arduino_CAN driver brings up the Giga FDCAN peripheral
    regardless of the tag. There is only ONE CAN driver (Arduino_CAN,
    bundled with the core) — no alternative to select/install.
  - `Servo claims to run on ... may be incompatible with mbed_giga` —
    same kind of tag gap; servo worked on this board pre-migration and
    is stubbed out this session anyway.
- **Build size on Giga:** 379,900 bytes flash = **19%** (max 1,966,080);
  globals 92,392 = **17%** (max 523,624). Tiny vs the Uno R4's
  ~52%/69% — exactly the headroom the migration rationale predicted.
- **No Tools-menu CAN config exists** in the IDE — bitrate (1 Mbps via
  `CAN.begin(CanBitRate::BR_1000k)`) and IDs/SOF (via `GIMBAL_MODEL`)
  are code-level only. Nothing to set in the IDE before flashing.

### STUB_CART — new bench-isolation stub (must be removed later)

Added `#define STUB_CART` alongside the existing
STUB_CAN/STUB_BNO/STUB_WIRED_ETHERNET stubs. When defined, all I²C/Tic
and servo access is skipped so the bench has ZERO I²C traffic while
CAN is the only variable under test. Guards added at THREE sites:

1. `setup()` — skips `Wire.begin()`, both Tic `haltAndSetPosition` /
   `exitSafeStart`, and `cartServo.attach/write`.
2. `cartLoop()` — skips the 2s `ticFront.getVinVoltage()` poll.
3. `buildStatusCSV()` — skips `ticRear.getCurrentPosition()`, reports
   `0` for the mm-since-waypoint field instead.

For this session STUB_CAN was COMMENTED OUT (real CAN path live);
STUB_BNO and STUB_WIRED_ETHERNET stayed defined (that hardware not
wired). **STUB_CART must be removed when the cart's Tic/servo are
reassembled** — it is bench-only.

### The buildStatusCSV I²C crash (found + fixed mid-session)

First flash had STUB_CART guarding only setup + voltage poll, NOT
`buildStatusCSV`. TX tested fine (`/home` → gimbal physically went
home), but the first hit on **`/status` hard-faulted the board**
(red flashing LED). Recovery: double-tap reset went to a DFU COM port
that wouldn't connect; a **power-cycle** brought it back cleanly on the
normal COM port.

Cause (confirmed, not guessed): `buildStatusCSV()` calls
`ticRear.getCurrentPosition()` — an I²C read to a Tic that isn't wired
and has no pull-ups. On the empty bus this faulted the Giga. Added the
third STUB_CART guard, re-flashed, and `/status` then worked — the
before/after confirms I²C-on-empty-bus was the cause. (See PREFERENCES
build lesson added this session.)

### Test results — Step 3 PASSED

Boot (clean, on the updated core):
```
[Cart] STUB_CART defined — I2C/Tic/servo init skipped (CAN-only bench).
[CRC self-test] CRC16: 0x42A2 OK   CRC32: 0xBE97407B OK
[Config] SOF_TX=0xAA SOF_RX=0xAA  TX_ID=0x223  RX_ID=0x222
[CAN] 1 Mbps — ready.
[CAN] Push subscribe sent (CmdSet=0x0E CmdID=0x07).
[WiFi] STA IP: 192.168.1.97   RSSI: -81 dBm
```

- **TX:** `GET /home` → gimbal physically slewed to home. Frame built,
  CRC'd, transmitted through the new CAN Pal, received and acted on.
- **RX:** `/status` first three fields (yaw,roll,pitch) read live pose.
  Moved gimbal by hand → yaw tracked -63.0 → 0.3 across reads. Pose-push
  frames arriving, reassembling, parsing into g_yaw/g_roll/g_pitch.
- **Commanded-vs-reported (both directions at once):**
  `GET /move?yaw=45&pitch=10` (parsed `yaw=45.00 pitch=10.00 time=2.0s`)
  → `/status` read back `45.5, 0.0, 10.0`. The 0.5° yaw is gimbal
  settle tolerance, not error; pitch dead on. Commanded and reported
  agree — strongest end-to-end confirmation.

No sign of the #54 large-slew overshoot pathology in the settled
readings (transient overshoot wouldn't show in serial regardless;
#54 fix remains deferred).

### Loose ends / notes

- **WiFi RSSI -81 dBm** at boot — weak for bench proximity. No effect
  on CAN. Flag if WiFi flakiness appears later.
- **#66 empty-connection cost** still present: favicon + browser
  speculative pre-connects produce `req_len=0 — dropped` and
  LOOP-LONG lines (~300ms–3s). Cosmetic, expected, unrelated to CAN.
- **DFU recovery note:** double-tap reset → DFU COM port did NOT
  connect this time; power-cycle was the reliable recovery. (Day-18
  note said double-tap; add power-cycle as the fallback.)

### Workfront status changes

- **Step 3 (CAN) — PASSED.** Was "paused on cooked transceiver" since
  Day 18. Replacement Adafruit CAN Pal 5708 wired and verified
  bidirectional end-to-end. All foundational Giga subsystems
  (Steps 1,2,3,4,5) now pass; Step 6 (side-by-side) / Step 7 (full
  validation against real gimbal, STUB_CAN removed for real) remain.
- **#60 Step 3 transceiver hardware — CLOSED.** New transceiver
  received, wired, tested good.
- **NEW: STUB_CART removal** — bench stub must come out when Tic/servo
  reassembled. Track alongside #68 (D9 readback) / #69 (W5500).

---

## Corrections to apply elsewhere in PROJECT_STATE.md

1. **"State of the system" / migration status:** any line still
   reading "Step 3 paused on cooked transceiver" or "#47 Step 3 paused
   on transceiver hardware" is now stale — Step 3 is PASSED (Day 22).

2. **Open questions in GIGA_PIN_PLAN.md:** the CAN-Pal-VCC-to-3V3 +
   charge-pump assumption is now confirmed working in hardware, and
   the S→GND normal-mode wiring is verified. (No change needed to the
   plan's wiring guidance — it was correct.)
