# HyperLapse Cart — Shopping List

**As of:** Session C day 15, 22 May 2026

Consolidated parts list extracted from WORKFRONTS.md. Update on
order/receipt; move items between sections as their status changes.

## To order

### CAN transceiver replacement + spares (#48)

- **Adafruit CAN Pal (TJA1051T/3)** ×2–3 — Core Electronics
  ADA5708. Candidate replacement transceiver for the WCMCU-230/
  SN65HVD230 fried by the Day-15 `/shutter/stop` bus fault (#48).
  Wires to Uno R4 native CAN pins (10/13). Onboard 120Ω
  termination is switchable. Buy multiple — until #48 is fixed,
  every stop-handler crash risks taking another out. Verify
  price + stock at order time.

### Cart antenna (#23)

- **Jaycar AR3277** — 11dBi 2.4GHz dipole, RP-SMA, 1.5m lead,
  magnetic base. **$49.95**.
  - 2.4GHz only — fine because Giga R1's WiFi is 2.4GHz-only
    (802.11b/g/n, 65 Mbps max).

### Antenna pigtail (cart side)

- **Phipps Electronics u.FL to RP-SMA female pigtail ×2** — one
  spare. u.FL is fragile, rated ~30 mating cycles.
- Connects Giga R1 J14 (u.FL) → pigtail → AR3277 (RP-SMA).

### Antenna mast (sourcing local)

- Non-metallic mast, 350mm useful length from cart deck to IMU
  mount, plus enough above the IMU for the antenna. Fibreglass
  rod ≥10mm, or PVC pipe with wall thick enough to not sway
  visibly on cart start/stop. Non-metallic throughout (no steel
  reinforcement, no aluminium sleeves at top). Purpose: lift cart
  antenna out of the steppers + Ronin RF neighbourhood AND host
  the BNO085 IMU. Position becomes a test variable.

  **Mechanical requirement:** the mast fold mechanism must have
  a **repeatable hard-stop in the shoot-up position** — pin,
  latch, or bolt-locked hinge. Guarantees the antenna's ferrous
  mass returns to the same location relative to the IMU each
  time, so the BNO085's hard-iron calibration done once in shoot
  config remains valid across power cycles. Also good for RF
  repeatability and matches what the gimbal already has.

## On hand (no purchase)

- 2× Wavlink WL-WN536AX6 AX6000 routers (van + field)
- 1× Arduino Giga R1 WiFi (includes u.FL flex antenna in box)
- 60m Cat6 cable for wired backhaul
- Spare WCMCU CAN breakout board
- **SparkFun TOL-18627** USB logic analyser (received Day 12;
  used to identify the 200ms shutter pulse-width requirement)
- **Adafruit BNO085 9-DOF Orientation IMU** (received and
  bench-tested Day 12; first-light done, tracks within ±3° of
  iPhone compass; awaiting production-sketch integration per
  #40 build phase)
- Spare 4N25 optocouplers + 220Ω resistors (#1 cluster; not
  needed since Day 12 made the swap unnecessary, kept as
  inventory)

## Worst-case escalations (don't buy yet)

- **Outdoor AP with detachable antennas.** Replacement field AP if
  cart upgrade + wired backhaul is insufficient. Candidates:
  Wavlink AERIAL HD6 outdoor, or similar with RP-SMA.
- **Point-to-point bridge** for van↔field link. Ubiquiti
  NanoStation or similar; treats the Wavlink AP purely as
  cart-side serving.

## Rejected (don't buy)

- ~~AP-side directional antenna (Alfa APA-M25)~~ — Wavlink
  antennas not detachable, so AP-side upgrades require replacing
  the AP entirely.
- ~~ESP32-S3-MINI-1 → MINI-1U swap on Uno R4~~ — SMD rework too
  fiddly; Giga R1 migration is the better lever.

## No longer needed

- ~~Jaycar ZD1928 4N25/4N28 optocoupler + 220Ω resistor pack~~ —
  Day 12 identified the photo-drop root cause as the cart's
  100ms shutter pulse width, not the opto path. Pulse raised to
  200ms, 100% delivery validated end-to-end. Opto swap
  unnecessary. Spares listed in "On hand" above as inventory.

## Cross-reference

See **WORKFRONTS.md** for context:
- §"Open workfronts — WiFi / RF link" — #22 (Giga port, held in
  reserve), #23 (cart antenna), #24 (mast placement), #25
  (wired backhaul), #26 (diagnostic instrumentation)
- §"Open workfronts — heading + gimbal stream" — #40 (BNO085
  integration, architecture resolved Day 13), #41 (iPhone
  compass anchors), #42 (gimbal CAN rate)
- §"Closed items — one-line stubs" — #1, #2 (opto swap and
  analyser, both Day 12)
