# WORKFRONTS.md — Day 24 (part B) — Step 4 Pan Follow execution PROVEN (soak-v16)

**Append to the Pan Follow / LOCK design note. This moves Pan Follow
from "designed" to "built + hardware-proven." Build: soak-v16.
Ry=Cy holds (Pan Follow uses no cart heading / no correction).**

---

## Step 4 — Pan Follow execution: BUILT + PROVEN on hardware (Day 24 pt B)

The design (Ronin permanently in Pan Follow; SDK position commands
override while issued, gimbal reverts to follow when the cart goes
silent) is now executed on the cart and confirmed on the real gimbal.

**Built:**
- **Cart (soak-v16):** new interval mode `GTM_PANFOLLOW = 'P'`. On
  entering a 'P' interval, the executor eases ONCE from the gimbal's
  actual pose to the goto offset (`offY`/`offP`) using the Phase-A
  smoothstep, over `acquire_ms` (or `PANFOLLOW_EASE_MS_DEFAULT = 3000`
  if none pushed). When the ease completes it sets `track_acquire_idx
  = -1` and `return`s SILENT for the rest of the window — no cubic, no
  per-tick command. The key realisation that made this small: the
  executor was ALREADY silent between intervals (`idx < 0 → return`),
  so "go silent → Ronin follows" needed no new machinery; Pan Follow is
  just "eased entry + that existing silence."
- **Excel (TrackPlanPush.bas):** now also emits Pan Follow rows —
  `mode=P`, `offy=Δyaw` (the goto-yaw), `obj=N` (unused for P), with the
  same `acquire` ease as Track GPs.

**Hardware test (gimbal powered, no camera/cables):** pushed a single
'P' interval by raw URL —
`/settings/trackplan?idx=0&ts=0&te=600000&obj=N&mode=P&offy=-30&offp=0&acquire=4000`
then `/track/start`.
- Gimbal eased to yaw -30 over the acquire ramp, logged
  `pan-follow at offset -> silent, Ronin follows`, then stopped
  commanding.
- **Operator hand-rotated the cart → the gimbal stayed in Pan Follow,
  tracking the cart heading while holding the offset.** This confirms
  the one assumption we could NOT verify on a bare bench: that the Ronin
  reverts to its native Pan Follow the instant SDK position commands
  stop. The cart commanding nothing IS the follow. **Pan Follow proven
  end-to-end.**

**Properties confirmed:**
- BNO-independent (no cart heading read) — matches the resolved #40
  "pan-follow untouched, cart drives blind." Unaffected by the BNO
  motor-power stall.
- Ry=Cy still holds.

## Step-4 status now

- **Pan Follow execution: DONE + hardware-proven.**
- **Pan Follow preview pose:** resolved earlier (goto-yaw at current
  heading) — unblocks the previewplan pusher (Step-1 leftover).
- **LOCK:** still parked — best enabled by BNO (moving-cart case needs a
  live heading-change source); revisit after the BNO electrical fix.

## Session close — where 2/3/4 stand

- **Step 2 (Phase-A ease):** DONE both sides — cart eases (soak-v14+),
  Excel sends `acquire_ms` (TrackPlanPush, cadence from FormulaTv ->
  CalcInterval, no fabricated values; verified dry-run pushes 0 + warns
  when sunset/sunrise times unset).
- **Step 3a (anchor instrumentation):** DONE + verified.
- **Step 3b (correction into earth-frame cubics):** BLOCKED on the BNO
  motor-power electrical fix (not code).
- **Step 4 (Pan Follow):** DONE + proven (this note). LOCK parked on BNO.

## Next (BNO-independent, still open)

- Previewplan pusher (now unblocked by the resolved pan-follow preview
  pose).
- Move-cubic Stage 4 in PlanPush (compute + POST the cubic; reuse
  AstroPush.FitCubic).

## Tomorrow (hardware)

- BNO proximity test on the spare GIGA (instrumented bench sketch with
  the heartbeat/age probe) to split conducted vs radiated, then the
  Tier-1 fixes (stronger pull-up on the 30 cm branch + local 5V
  decoupling). Unblocks 3b and LOCK.
