# Workfront — Canon R3 overnight power (battery-swap pause fallback)

**As of:** 07 Jun 2026. **Status: FUTURE WORKFRONT — not built.** Captured
from operator note. Companion to the exposure/sequence runbook.

---

## The need

An overnight shoot runs ~16 hours (4 pm → 8 am). At night cadence (22 s
cycle) the Canon R3 will not last on a single battery — it needs roughly
**three batteries** across the night, OR a **continuous power adaptor**.

- **Primary path (in place):** continuous power adaptor (mains / large
  battery → DC coupler). With the adaptor fitted there is no swap and no
  interruption — preferred, and the current setup.
- **Fallback (adaptor missing / fails):** the timelapse must **pause in
  its current gimbal pose**, hold, allow a quick hot-swap-style battery
  change, then resume — without losing framing or cadence sync.

This is the same shape of problem as a planned interrupt (cf. the parked
**pano** interrupt: suspend the active GP, do the thing, resume via
Phase-A ease). The battery-swap pause should reuse that suspend/resume
plumbing rather than invent a second mechanism.

---

## Behaviour to build (fallback path)

On operator-triggered "battery pause":
1. **Freeze pose.** Gimbal holds its current commanded yaw/pitch (it must
   keep commanding — silence lets the Ronin's Pan Follow drift). No new
   astro/track motion advances.
2. **Stop firing.** Shutter cadence suspends; the exposure clock holds so
   the resumed sequence keeps the same Tv/ISO and cadence it had.
3. **Hold through the swap.** Camera loses power briefly during the
   coupler/battery change; the cart/gimbal stay powered and posed. CCAPI
   link will drop and must re-establish on power-up (re-init, confirm
   shooting mode/Tv/ISO before resuming — do NOT assume settings survive).
4. **Resume.** Re-engage on the object's CURRENT position via Phase-A ease
   (object moved during the pause), exactly like the pano resume — no
   snap. Cadence continues from the held clock.

Open questions for the build phase:
- Does the R3 keep its M-mode Tv/ISO across a DC-coupler power cycle, or
  must Excel re-push via CCAPI on resume? (Measure — do not assume.)
- Time budget for a swap: how long can the gap be before the timelapse
  shows a visible seam? (At 1320× speedup a multi-minute hold is a few
  frames; likely tolerable, confirm.)
- Trigger surface: execution-UI button (same screen as the iPhone-heading
  popup), so the operator can pause/resume one-handed at the cart.

---

## Why it's a fallback, not primary

The adaptor is fitted and is the intended power path, so this is an
insurance feature for adaptor failure or a forgotten adaptor on a remote
shoot. Build priority accordingly — below the live render/cable work,
above nothing time-critical. Reuses pano suspend/resume, so cost is
mostly the CCAPI re-init-on-resume handling, not new motion code.
