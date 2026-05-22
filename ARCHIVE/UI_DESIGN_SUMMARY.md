# HyperLapse Cart — Three-Screen UI Design Summary

**Captured:** 17 May 2026 (Session D day 10), during design-mode discussion.
**Status:** Design-level only. No code, no mockups, no wireframes. Carrying forward to inform future implementation sessions.
**Revised:** 21 May 2026 (Day 13) — heading-architecture section
updated to reflect #40 BNO anchor design. Three-screen structure
and per-screen content unchanged.

This document captures the conclusions of a single design conversation that carved the cart's web UI into three production screens and reached agreement on what each does. Implementation decisions (HTML layout, colour, exact button placement, polling cadence specifics) are deliberately deferred.

---

## Why three screens

Current UI is one page mixing recon driving, gimbal capture, intervalometer fallback, and status — designed organically. Operator workflow is actually three distinct passes, each with a different mental mode. UI should match passes, not features.

**The three passes (operator's actual workflow):**

1. **Cart Recon** — Continuous drive end-to-end at recon speed. Cart Log fills event-driven (steering / speed changes). Gimbal pan-follows automatically. Operator focused on driving.

2. **Gimbal Recon** — Stationary. Walk back to each shoot spot, push gimbal by hand (DJI push-mode: mild resistance, stays put), capture yaw/pitch into one of 3–5 labelled slots. Bounded by aesthetic — more than ~5 manual events makes a bad timelapse.

3. **Execution** — Plan runs autonomously. Operator supervises and may nudge cart distance. Gimbal is monitor-only.

Three screens, one URL with a switcher tab at the top. Cart can know which screen is active and tailor /status payload accordingly.

---

## Cart Recon screen

**Purpose:** drive the cart, fill the Cart Log.

**Carries over from current UI (with cleanup):**
- Steering presets: L5 / L1 / CTR / R1 / R5
- Speed adjust: −10 / −1 / DEC / +1 / +10
- Motors: STOP / DE-E / ENRG (DEAD belongs elsewhere — see Execution)
- ● Cart (btn19) Log recording toggle
- Status: current steering, speed, voltage, motor state

**New:**
- "Mark Waypoint" button (workfront #29 already specified — produces a distinct log event so Excel can pair a ground (x,y) to the log timestamp, e.g. for sunset spot, circle-fit corner marks)

**Removed from current UI:**
- Gimbal yaw/roll/pitch readout (not operator's concern during driving)
- Home (test/diagnostic only)
- Photo (test only)
- PAUSE / interval / BKUP (belongs on Execution)
- ● Gimbal (btn20) — retired (Pass-2 capture handled by new Gimbal Recon screen)
- Camera message bar (belongs on Execution)
- btn13, btn21 unused/spare slots

---

## Gimbal Recon screen

**Purpose:** capture manual gimbal pointing at the 3–5 spots that matter.

**Workflow:**
- Operator at a physical spot
- Physically push camera to desired framing (DJI push-mode keeps it where pushed)
- Tap one of five "Capture M1..M5" buttons
- Optionally type a one-word label (sunset / MW / sunrise / etc.)
- Timestamp captured silently for Excel cart↔gimbal stitching

**Critical design decision overturned from GIMBAL_VIZ.md §3:**
- No Way# dropdown. Gimbal rows are NOT one-per-cart-waypoint. The relationship is many-to-many in time, stitched in Excel using timestamps. A 4-hour "track sun" gimbal row can span many cart waypoints.
- No yaw/pitch nudge buttons (−10°/−1°/etc.). Originally specified, now removed — DJI push-mode replaces software pointing.

**Layout:**
- Live yaw/pitch readout (so operator sees where they pushed to)
- Five fixed capture slots, each: `[Capture Mn] yaw=__ pitch=__ label:[____]`
- Unused slots sit grey
- That's it

**Astro rows (track sun / MW) don't appear on this screen** — they have no manual pointing component. Excel computes their endpoints from astro maths.

---

## Execution screen

**Purpose:** monitor a running Plan; allow bounded operator interventions.

**Architecture from PROJECT_STATE §"Cart position model" (day 9 late):**
- Operator-in-the-loop is the chosen path (Path B), not autonomous (Path A rejected)
- Cart distance nudge ±100mm exists; gimbal angle nudge explicitly does NOT exist (operator can't judge angles by eye)
- "Gimbal time is sacred; cart position is flexible" — when cart distance nudges, gimbal continues on its time schedule unchanged
- Push updates per 100mm change — event-driven, not polled (resolves WiFi polling fault by design)
- 3+4 combined into one screen because both happen at the same time with one operator

### Cart-active half (top)
- Current segment N of M, type (MOVE / STOP)
- Remaining distance on current MOVE segment (100mm resolution)
- Nudge buttons: −100mm, +100mm (only active during MOVE; STOP segments have no nudge — operator can't judge duration either)
- Past-zero shorten = immediate segment complete (no overflow)
- Adjust counter clears at segment boundary
- DEAD STOP button (always visible, large, red — parallels STOP on Cart Recon screen)

### Gimbal-passive half (chart)
- XY chart: yaw cumulative × pitch
- Yaw axis bounds come from Plan: `[yaw_min, yaw_min + 450°]` where yaw_min is computed by Excel at bake time
- Pitch axis fixed `[0°, 90°]`, dashed line at 80° (mechanical reminder)
- Chart is **cart-frame**, yaw=0 = front wheels straight ahead
- Waypoint dots from Plan (manual + astro endpoints)
- Catmull-Rom path drawn between waypoints
- Path coloured by velocity band (blue=ease, green<0.05°/s, amber 0.05–0.3, red>0.3, per GIMBAL_VIZ.md §7)
- Live camera icon at (current Plan yaw, pitch); colour matches current segment's velocity band
- Icon orientation FIXED (not rotated by yaw) — position alone tells the story
- Icon shows the **Plan's** current position, not actual gimbal readback (operator can't act on divergence anyway)
- No trail behind icon (no drift expected; would clutter)

### Pre-start checklist
- Operator ticks items before /plan/start enables
- One item: heading validation
- Shows IMU current heading; optionally compares to operator-provided iPhone compass reading
- 2° tolerance is fine — at 14mm Sigma (114° diagonal FOV, ~104° horizontal), 2° is ~2% of frame width, fixable in post crop
- Bar can be quite forgiving: operator eyeballs, ticks the box, goes

### Scheduled checkpoints (mid-execution)
- Plan can include heading-validation checkpoint rows
- Cart UI alerts operator 5min before each astro waypoint
- Operator points iPhone, enters compass value
- UI shows iPhone vs IMU; operator chooses "Apply iPhone" or "Accept IMU"
- Logged either way

### Live state visible at all times
- Plan running / DEAD-aborted / done
- Elapsed / remaining time
- Photo count (fires vs drops)
- Current `cart_heading_now` and `imu_offset`
- Exposure mode (CCAPI live / Excel fallback)

---

## Heading architecture (SUPERSEDED by Day 13 — see PROJECT_STATE day-13 entry)

The Day 10 version of this section proposed per-tick IMU subtraction
on cart for world-frame segments (`target_yaw_cart -= cart_heading_now`
every gimbal tick) with continuous `imu_offset` state. **This is no
longer the design.** Day 13 resolved #40 around a cheaper, simpler
shape:

**Day 13 design (current):**
- Cart does NOT subtract IMU per-tick. Earth-frame gimbal cubics are
  evaluated as `at³+bt²+ct+d + gimbal_yaw_correction` where
  `gimbal_yaw_correction` is a single scalar updated only at
  operator-placed anchor rows (handful per shoot, not per-tick).
- Each segment carries a frame tag (`earth_frame` vs `chassis_frame`).
  Pan-follow / manual hold / transition segments are `chassis_frame`
  and ignore the correction. Astro-track / earth-frame pan segments
  are `earth_frame` and have the correction added at cubic eval.
- Anchor flag is per-row in the plan. When cart reaches an anchor
  row, it pulls clean averaged BNO yaw from a continuous ring buffer
  and compares to Excel's pre-baked `expected_cart_heading` for that
  row. If `|delta| > threshold` (per-row), updates the scalar.
- Two-attempt retry at 500mm / 400mm before waypoint handles
  occasional BNO acc<2 dropouts. Both fail → keep previous
  correction, log A_FAIL, photos continue.
- BNO offset (declination + mount angle, ~+9° for Adelaide) lives
  in Excel-side Settings, pushed to cart at plan load.

**Implications for the Execution screen:**
- No live `cart_heading_now` display in the always-visible state bar
  is *required* — there is no continuous heading correction running.
  A `/debug/imu` endpoint exists for inspection; checkpoint flows
  can use it.
- The pre-start checklist's "heading validation" step is still
  valuable as operator reassurance, but the runtime mechanism is
  now anchor-driven, not continuous-offset-driven.
- Scheduled mid-execution iPhone-anchor checkpoints (described
  below) are now ONE source of anchor data. The BNO085 sampler is
  the OTHER source. Plan rows tagged `anchor` can pull from either
  (operator workflow: BNO automatic, iPhone if operator chooses to
  override with absolute reference).
- "Cart-frame rows" / "world-frame rows" terminology in this doc
  maps cleanly to Day 13's `chassis_frame` / `earth_frame` tags.

**What survives unchanged from this section:** the two-class split
of Plan rows is correct, the 1-bit frame flag is correct (just
renamed), graceful degradation philosophy is correct (drift → post
crop acceptable per "photos sacred" principle).

**What's superseded:** per-tick IMU read on cart, `imu_heading_raw`
+ `imu_offset` + `cart_heading_now` triple, continuous correction.
Replaced by single `gimbal_yaw_correction` scalar updated at anchor
events only.

---

## Hardware constraints reasoned through

**What doesn't break the Uno:**
- Serving HTML/CSS/JS once per page load (current UI already does this)
- Small JSON responses on demand
- Plan storage in SRAM (~1.6KB per GIMBAL_VIZ §10, fits)
- Charts and rich client-side visualisations (rendered on iPhone, not cart)

**What stresses the Uno:**
- Polling cadence (workfront #27: 1s polling saturated WiFi; resolved to 3s)
- Per-request payload size
- Computation under WiFi load

**Implication for UI design:**
- Plan can be fetched once at screen entry, rendered richly client-side
- Cart only pushes small live-state deltas during execution
- Live-state payload ≈ current_segment_id, current_yaw_dec, current_pitch_dec, elapsed_ms, photos_taken, cart_heading_now — well under 50 bytes
- Push event-driven (per 100mm cart distance change) rather than fixed polling — workfront #27 design

---

## Open / deferred questions

1. **Single-screen layout priorities** — Execution screen has cart-active controls, gimbal chart, pre-start checklist, scheduled-checkpoint prompts, and live state. Which earns top-of-fold real estate; which sits behind taps. Not decided.

2. **Heading-validation checkpoint placement in Plan** — operator-authored row, or auto-inserted by Excel before every world-frame segment? Likely auto-inserted; not decided.

3. **Cart heading-anchor UI before /plan/start** — explicit "Take Anchor" step, or optional / skippable? This session leaned skippable (IMU trusted, iPhone reassurance theatre). Not finalised.

4. **Live camera icon vs actual gimbal readback** — chart shows Plan's current position only. Actual position diagnostic could be logged for post-shoot analysis without displaying. Not decided whether to log readback.

5. **Switcher behaviour** — does selecting a screen change cart state (e.g. enable/disable polling cadence), or is it purely view-only? Likely view-only with cart auto-detecting context via /status query string. Not decided.

6. **What if the operator can't reach the iPhone-anchor checkpoint in time?** — Plan progresses regardless; world-frame segment runs with stale heading; recoverable in post if drift is small. Not formalised.

7. **DJI Track-mode visual borrowing** — full borrow (grid, dot waypoints, drag-to-edit) was considered for Excel side; for Execution screen we borrow only "camera icon on yaw×pitch grid." Whether to also borrow Track's "preview path" animation pre-start is open.

---

## Cross-references

- `PREFERENCES.md` — guiding principles (photos sacred, oscilloscope approach, etc.)
- `PROJECT_STATE.md` §"Cart position model" (day 9 late) — nudge architecture origin
- `PROJECT_STATE.md` §"Path A vs Path B" — operator-in-loop decision
- `GIMBAL_VIZ.md` §1–§4 — Plan/Stream/Execution separation; day-8 cart-frame-only decision (PARTIALLY REVERSED here for world-frame astro segments)
- `GIMBAL_VIZ.md` §6 — yaw cumulative range, velocity band thresholds
- `GIMBAL_VIZ.md` §7 — Excel chart design (Execution chart borrows from this)
- `GIMBAL_VIZ.md` §10 open-question #5 — heading anchor mechanics (now ANSWERED here)
- `WORKFRONTS.md` #10a — Gimbal UI page (this session refined the spec)
- `WORKFRONTS.md` #27 — UI polling resolution; event-driven push instead
- `WORKFRONTS.md` #29 — Mark Waypoint button (Cart Recon screen)
- `WORKFRONTS.md` #40–#42 — BNO085 + iPhone-anchor cluster (heading architecture)
- `WORKFRONTS.md` #41 — iPhone compass heading anchors
- `WORKFRONTS.md` #31 — Plan nudge endpoint and UI (Execution screen)

---

## What this session decided vs deferred

**Decided:**
- Three production screens, one URL, top tab switcher
- Cart Recon: trim of current UI + Mark Waypoint
- Gimbal Recon: five fixed labelled slots, push-mode capture, no nudge buttons, no Way# dropdown
- Execution: cart-active top half (segment + nudge + DEAD), gimbal chart half, checklist, scheduled checkpoints
- Chart specifics: cart-frame, yaw [min, min+450°], pitch [0°,80°,90°], waypoint dots + Catmull-Rom path + velocity bands, fixed-orientation camera icon at Plan's current position
- Heading architecture: two frame classes in Plan, runtime correction for world-frame only, IMU + scheduled iPhone-anchors, offset variable
- Hardware: none of this breaks the Uno — visualisation is client-side
- DEAD on Execution, STOP on Cart Recon — separate "stop everything" controls per screen

**Deferred:**
- Layout / priorities within Execution screen (above-the-fold)
- Explicit pre-start anchor flow vs skippable
- Auto vs operator-authored checkpoint placement
- Whether to log actual gimbal readback
- Switcher state-vs-view behaviour
- Missed-checkpoint recovery
- Preview animation for Plan pre-start

---

## Path back into this design

A future session can re-enter this design by:
1. Reading this file alongside `GIMBAL_VIZ.md` and `PROJECT_STATE.md`
2. Noting the day-8 "cart-frame only" decision is now revised — Plan rows are tagged per-frame
3. Picking up at one of the deferred questions, OR moving to mockup-level layout for one screen at a time, OR moving to firmware-level work (segment frame flag, imu_offset variable, anchor endpoint)
