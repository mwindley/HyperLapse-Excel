# Workfront — Cable UI (interactive cable-rigging screen)

**As of:** 07 Jun 2026. Context captured this session; build starting.
Companion to ChartPush.bas (exec chart author), PushPreviewPlanToCart
(preview/jog author), gimbal_cablestrip.py (the planning-side strip).

---

## The idea (two screens, two modes)

Two cart screens, BOTH authored in Excel, pushed to the cart, cart shows +
animates an icon (Excel = brains, cart = dumb renderer):

- **Execution UI** (exists) — PASSIVE. Gimbal steps in yaw+pitch (2-D
  trajectory) + live camera icon showing timelapse progress. No motion
  buttons. Safe to leave running.
- **Cable UI** (new) — INTERACTIVE. Yaw-only strip (unwrapped sweep vs the
  450 span) + PREV/NEXT buttons that DRIVE the gimbal point-to-point so
  the operator can walk the sweep: jog to a GP, dress cables, jog
  fwd/back to check clearance, repeat. Used BEFORE the shoot.

Safety: jog controls live ONLY on the Cable UI, never the Execution UI,
so no accidental button press moves the gimbal mid-timelapse. Plus a mode
interlock (below).

---

## Reuse map (what exists vs new)

EXISTS / reusable:
- SVG author + chunked push + cart-shows-and-animates-icon pattern:
  ChartPush.bas -> /settings/chartsvg, viewBox 0 0 355 90,
  x = (yaw - yaw_min)/450 * 355. The template.
- PREV/NEXT jog that drives the gimbal per GP -- ALREADY BUILT and its
  stated purpose includes "to route cables against the actual rotations":
  PushPreviewPlanToCart -> /settings/previewplan (idx,yaw,pitch,label,
  start; cap 20; Track GPs emit start+end), stepped via PREV/NEXT or
  /preview/step. This is the jog engine.

NEW:
- **Excel: cable-strip SVG author** (small; parallels ChartPush). Emits
  the 1-D yaw strip. MUST compute world bearing + unwrap via col AC the
  SAME way the dial/Python strip do (heading+offset, col-AC CW/CCW), NOT
  ChartPush's raw Ry+dyaw read -- so the cart strip agrees with the van.
- **Cart: Cable screen** (firmware; clone of the Execution screen made
  interactive). Same strip display + live marker, but PREV/NEXT call the
  existing /preview/step instead of being passive.

---

## Behaviours / decisions

- **2-sec ease between jog positions.** Operator wants a 2s ease GP->GP on
  PREV/NEXT (not a hard goto). Confirm whether /preview/step already eases
  or needs it added (firmware).
- **Mode interlock.** Jog must be blocked when a timelapse is armed/
  running -- a state gate, not just screen separation. (firmware)
- **No "max" shortcut.** Operator reaches the max-wind GP by repeated
  NEXT; no dedicated jump-to-max button needed.
- **Marker drive.** The cable strip's live marker = active preview-pose
  yaw mapped to strip x (same x = (yaw-yaw_min)/450*355 mapping the exec
  icon uses). Cart already tracks the PREV/NEXT index, so it knows the
  active GP.

---

## Open questions to confirm against the firmware (can't see C++ here)

1. Does /preview/step ease (2s) or hard-goto?
2. Can the cart hold a SECOND SVG slot (e.g. /settings/cablesvg) + a
   second screen alongside the Execution one, or does the preview jog
   currently reuse the execution screen? Determines whether the strip
   gets its own slot or shares.
3. Does the cart enforce any arm/run state we can hook the interlock to?

---

## Consistency rule (holds across ALL yaw views)

Dial PNG, planning strip PNG, exec SVG, cable SVG must all compute world
bearing + unwrap identically (heading+offset, col-AC CW/CCW). The Python
side already shares resolve(); the VBA authors must mirror that rule so
the van and the cart never disagree.

---

## Build order (this session)

1. Excel cable-strip SVG author (PushCableStripToCart), modelled on
   ChartPush, using the world-unwrap math. Pushable to a slot
   (cablesvg if available, else chartsvg to view immediately).
2. Wire into Prep / a button as desired.
3. Cart Cable screen + interlock + ease: firmware workfront (separate,
   not buildable here) once slot question (#2) is answered.
