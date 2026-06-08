# Gimbal Execution - WP-Event Coordination (Day 29 build plan)

**As of:** Day 29, 04 Jun 2026. **Status (UPDATED Day 30): Phases 1-3 of
section 3 are now BUILT + HARDWARE-PROVEN (soak-v37; nudge-divergence test
passed). Phase 4 (astro + heading 3b) REMAINS — see WORKFRONTS.md item G.**
The section-3 build plan below is the original Day-29 design; it is preserved
for reference. Each GP now fires on the cart's ACTUAL WP arrival (arrival +
offset), surviving slip/nudge, exactly as designed. Companion to
GIMBAL_EXECUTION_CAPABILITIES.md
(what each GP does), CART_HEADING_DESIGN.md (the heading spine), and the
#40/#41 entries in WORKFRONTS.md. This block supersedes the parked
"re-stamp the track anchor at /plan/start" idea (it was a partial fix for
a symptom; see step 6).

---

## 1. The headline finding

The plan binds every gimbal point (GP) to a cart waypoint (WP). In the
Plan sheet, a GP's "Fires-at" (col Q) is `the WP's Commence time (col J)
+ Offset (col P)`. There is no independent gimbal timebase anywhere in
the plan - the only times are WP times (or astro/explicit-time anchors
when chosen), and Offset is a delta from them.

The firmware does NOT honour that binding at run time. At push,
TrackPlanPush flattens each GP to an absolute `ts/te` in milliseconds,
and the executor (`trackPlanTick`) walks those against its own clock,
`millis() - track_plan_anchor_ms`, where the anchor is set at
`/track/start`. The executor never reads the cart's actual WP progress.

Consequence, seen on the Day-28 run: the gimbal ran on a clock that
started minutes before the cart (track start vs plan start), and nothing
re-synced it. Open-loop time replay also drifts whenever the cart's real
drive time diverges from plan (slip, over-rotation, a `/plan/nudge`).

**The fix is to fire each GP off the cart's ACTUAL arrival at its anchor
WP, plus the Offset - not off a clock.** This is not new design; it is
what the plan already encodes. It also dissolves the start-offset problem
entirely, because there is no longer a separate gimbal clock to fall out
of sync.

The cart already generates the needed event: `planSegmentEnter(idx)`
stamps `plan_seg_start_ms = millis()` at the moment the cart starts a
WP's leg - which IS that WP's Commence/arrival moment, the same instant
Excel's col J represents. So WP-event anchoring is hooking the gimbal
onto an event the cart already produces.

---

## 2. Two GP classes at run time

The runtime needs differ by GP kind:

- **Relative pans** (e.g. the 0 / -30 / +30 / 0 test). Need only: the WP
  event + Offset. The yaw is relative to the cart nose, so cart heading
  is irrelevant. These are the immediate target of this build.
- **Astro GPs** (Track / Move-to-astro). Need: the WP event + Offset,
  the real wall-clock time at that moment (for the object's position),
  and - for accurate earth-frame aim - the cart's real heading to seed
  Ry. The cubic eval is already real-time-anchored (Model B,
  `cartRealTimeMs`/`real_t0_ms`), so once the WP event sets WHEN the
  interval opens, the cubic gives WHERE the object is at that real time.
  The heading correction is the separate 3b/heading work (section 4).

---

## 3. Stepwise build plan (relative-pan coordination first)

Dependency order. Each step is small and most reuse a proven pattern
(tail-token push per build-lesson 12; record-only event capture like the
3a anchor instrumentation; the executor already walks intervals).

### Phase 1 - carry the WP binding through to the cart

**Step 1 (Excel).** TrackPlanPush emits, per interval, the anchor WP id
and the Offset in ms, as tail tokens on the existing
`/settings/trackplan` query (append-only, order-independent, per
build-lesson 12). Keep the existing `ts/te` for preview and as a
fallback. Excel already holds both values (col O = WPnn, col P = offset).

**Step 2 (cart).** The `TrackInterval` struct gains `anchor_wp` and
`offset_ms`. The trackplan parser reads the new tail tokens; absent =
fall back to the pushed `ts/te` (old behaviour preserved).

**Step 3 (cart).** Record actual WP-arrival times. In
`planSegmentEnter`, stamp `wp_arrival_ms[wp] = millis()` for the WP that
segment starts (its Commence). One small array, written at an event that
already fires. Record-only; nothing else changes.

### Phase 2 - fire the gimbal off WP events

**Step 4 (cart).** In `trackPlanTick`, compute each interval's live
window from the actual arrival: `ts_live = wp_arrival_ms[anchor_wp] +
offset_ms`, `te_live = next interval's ts_live` (or this interval's own
WP arrival + its duration, per the END-bound rule already in use).
Replace the pushed-absolute comparison with this.

**Step 5 (cart).** Edge handling, explicit:
  - Anchor WP not yet reached -> interval is PENDING; the gimbal holds
    (does not fire early).
  - Offset not yet elapsed after arrival -> wait, then fire.
  - WP shortened / nudged / extended -> arrival stamp moves, the GP
    moves with it automatically (the whole point).
  - Offset window still open when the next WP arrives -> decide:
    fire-late vs skip. Default proposal: fire on arrival of the anchor
    WP regardless, clamp the hold to the next event. Confirm at build.

**Step 6 (cart).** Retire the gimbal's dependence on its own clock.
`/track/start` becomes arm-only (load + enable the executor); the WP
events drive timing. This SUPERSEDES the parked "re-stamp the anchor at
/plan/start" task - with WP-event firing there is no anchor to re-stamp.

### Phase 3 - validate

**Step 7 (bench / dry).** Drive the cart plan (or inject simulated WP
arrivals) and confirm each GP fires at the actual arrival + offset.
Then shorten/extend a WP (a `/plan/nudge`) and confirm the GP tracks the
change rather than firing on the stale planned time.

**Step 8 (real, coordinated).** Cart + gimbal, single operator start.
Confirm GP02's pan lands while the cart is actually at WP02, independent
of any cart timing drift. This is the acceptance test for the capability.

### Phase 4 - astro + heading (future, not this build)

**Step 9.** Astro GPs slot into the same WP-event firing (the cubic is
already real-time-anchored, so it self-corrects to the real fire moment).
The earth-frame aim correction is the heading work in section 4 -
explicitly future.

---

## 4. Heading model (FUTURE work, captured)

BNO is currently stubbed. The heading source moves to the iPhone (the
operator-in-the-loop rung 1 of the CART_HEADING_DESIGN trust ladder),
with the planned `expected_cart_heading` as the floor.

New refinement agreed Day 29: Cart Recon now captures a compass reading
per WP. That recon compass becomes `expected_cart_heading` in the plan
(pushed per WP) - so the planned heading is measured at recon, not pure
bicycle integration. At execution, an iPhone request on approach to an
astro GP serves as compare / override / offset against that expected
heading, and the correction propagates forward to improve the next WP's
heading and prevent cumulative drift.

This feeds the existing 3b correction
`gimbal_yaw_correction = (heading) - expected_cart_heading` (+ Adelaide
declination / mount offset) on earth-frame GPs only. Relative pans and
the cart path stay heading-independent. All future work; not part of the
section-3 build.

---

## 5. CAN resolution this session (factual record)

State of the parts after the CAN debugging, no asserted root cause for
the production transceiver:

- Transceiver 1: dead, reverse polarity (known cause, operator note).
- Transceiver 2: the production/suspect part, removed; cause unconfirmed.
- Transceiver 3 + spare Giga: now in the rig and working - gimbal streams
  0x530, `/home` good.
- Bus: 1 Mbit confirmed both ends; ~60 ohm termination confirmed
  (Pal 120 on + gimbal 120).

Correction for the record: during debugging I called the S (silent-mode)
pin as the production fault. That was premature - the production Pal had
S tied to GND (normal mode), the spare had S unconnected (also normal).
Both are normal-mode wiring, so the S pin does not explain the production
failure. Treat transceiver 2's failure cause as unconfirmed.

---

## 6. Done this session

- TrackPlanPush dated-timeline ease fix. Phase-A ease now computes:
  the sun-time cells were read date-tolerantly (they are date-typed; the
  old SafeNum/IsNumeric read returned 0), and fire times + sun-event
  times were put on one dated timeline (sunrise rolled to the
  end-of-shoot morning) so cadence resolves and works across midnight.
  Dry run then real push: cadence 22.0s, acquire_ms non-zero, four
  intervals accepted.

---

## 7. Parked / superseded

- "Re-stamp the track anchor at /plan/start" - SUPERSEDED by section 3
  step 6 (WP-event firing removes the separate gimbal clock).
- Yaw-rate cap to replace freeze-yaw near zenith (GC ~84 deg here).
- Distance-aware Move-t (Plan col AA).
- Pano (manual interrupt + Excel geometry), off-cart visualisation,
  the Pan-Follow -> Track handoff-ease decision.
- Execution-screen UI - still a placeholder.

---

## 8. Staleness flag

PROJECT_STATE_CONSOLIDATED.md "State of the system (current)" still lists
gimbal plan execution as "design only." That is out of date: Day 24
(part B) built and hardware-proved Phase-A ease, Pan Follow, Move, and
sun Track, and Day 28 ran a 4-interval plan end-to-end. The Day-24 block
in WORKFRONTS.md plus this entry are the accurate gimbal build record.
