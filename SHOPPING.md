# HyperLapse Cart — Shopping List

Consolidated parts list extracted from WORKFRONTS.md. Update on
order/receipt; remove or strike through when fully integrated.

## On order (from day 6)

### Optocoupler swap

- **Jaycar ZD1928** — 4N25 / 4N28 optocoupler. Buy ×2 for spare.
  Stay in the 4N25 family. ~$5 total.
- **220Ω resistor pack** — paired with the 4N25.

### Logic analyser

- **SparkFun TOL-18627** — USB logic analyser, 24MHz / 8-channel,
  ~$30. Source: Core Electronics. Open-source PulseView / sigrok.
  Purpose: measure both sides of opto simultaneously **before**
  swapping, to confirm diagnosis.

## To order (from day 8 — WiFi / RF link)

### Cart antenna

- **Jaycar AR3277** — 11dBi 2.4GHz dipole, RP-SMA, 1.5m lead,
  magnetic base. **$49.95**.
  - 2.4GHz only — fine because Giga R1's WiFi is 2.4GHz-only
    (802.11b/g/n, 65 Mbps max).

### Antenna pigtail (cart side)

- **Phipps Electronics u.FL to RP-SMA female pigtail ×2** — one
  spare. u.FL is fragile, rated ~30 mating cycles.
- Connects Giga R1 J14 (u.FL) → pigtail → AR3277 (RP-SMA).

### Antenna mast (deferred, sourcing local)

- Non-metallic mast, 300–500mm. Fibreglass / PVC / tent pole.
  Purpose: lift cart antenna out of the steppers + Ronin RF
  neighbourhood. Position becomes a test variable.

## On hand (no purchase)

- 2× Wavlink WL-WN536AX6 AX6000 routers (van + field)
- 1× Arduino Giga R1 WiFi (includes u.FL flex antenna in box)
- 60m Cat6 cable for wired backhaul
- Spare WCMCU CAN breakout board

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

## Cross-reference

See **WORKFRONTS.md** for context:
- §"Hardware (from day 6)" — items 1, 2, 3 (opto + analyser)
- §"WiFi / RF link" — items 22-26 (Giga port, cart antenna, mast,
  wired backhaul, diagnostic instrumentation)
