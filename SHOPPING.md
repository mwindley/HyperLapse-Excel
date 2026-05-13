# Shopping list

From PROJECT_STATE.md day 6 priorities. Buy analyser-first so you can
PROVE the opto diagnosis before swapping (measure both sides
simultaneously).

## Core Electronics (analyser)

| Item | Why | Approx |
|------|-----|--------|
| SparkFun USB Logic Analyzer (TOL-18627) | 24MHz, 8-channel. Open-source PulseView/sigrok. Measure opto IN and OUT side-by-side; confirm cart-pristine + opto-degraded before swap. | ~$30 |

## Jaycar Australia (opto + resistor)

| Item | Code | Qty | Why | Approx |
|------|------|-----|-----|--------|
| 4N25/4N28 optocoupler | ZD1928 | 2 | One install, one spare. Stay in 4N25 family — 6N138 needs Vcc on output side (not available). | ~$1.75 ea = $3.50 |
| 220Ω 1/4W resistor pack | (any 220Ω 0.25W pack) | 1 | LED-side current limit. Or 330Ω pack for safer LED current. | ~$1-2 |

**Total: ~$35 incl analyser, ~$5 without.**

## Notes

- Existing opto is sealed/wrapped — can't inspect resistor or model.
  Buying new known parts is cheaper than reverse-engineering the old one.
- Get the analyser first so the swap is a measured fix, not a guess.
- Confirm 4N25/4N28 spec sheet matches the cart's drive current
  (Arduino pin sources ~20mA at 5V → 220Ω gives ~14mA through opto LED,
  well within 4N25 forward current rating of 60mA).
