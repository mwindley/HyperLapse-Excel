# HyperLapse Cart — Open Workfronts

**As of:** Day 35, 22 Jun 2026 (firmware soak-v188). This file is the
workfront catalog + standing record. The Day-31 block below is kept as a
historical checkpoint (labelled as such). Numbered entries marked
RETIRED/CLOSED are done; the rest are open.

## Closed Day-35 (17 Jun) — PanoCycle 2-row grid (landscape 2x4)

- **PanoCycle reshaped to a landscape 2x4 grid** (4 yaw columns x 2 pitch rows,
  8 cells). Driver: the RS4 Pro portrait mount won't balance the Canon R3, so the
  body stays landscape and the second framing dimension is a pitch ROW. Firmware
  soak-v153 + Excel PanoSheet.bas + PanoConfigPush.bas. ON-RIG VERIFIED on a live
  arch GP (NOT yet flown overnight).
- **Cart contract = dumb:** PanoConfig gains `rows` + `rowstep`; the cart fans the
  yaw columns over `rows` pitch rows (row r pitch = centre + r*rowstep). Lower row
  = the arch GP Rp (live via offP, not pushed); upper = Rp + rowstep. Per-cell via
  panoCellTargetYaw/Pitch. Firing raster (bottom L->R then top L->R); cable-unwind
  RETURN targets cell 0.
- **rowstep from the PANO sheet** = vfov/2 (50% vertical overlap); vfov uses the
  short edge for landscape. 14mm -> ~41 deg (whole-degree on the wire).
- **PanoCentre unchanged:** rows=1, pose-pitched, operator out-and-back.
- **Authoring fix (trace-found, no code change):** the arch GP must be Action =
  "Track-yaw" (mode Y, reads Rp), NOT "Track" (mode F, reads Dpitch). With "Track"
  the push sent offp=0 and the lower row sat at 0; Track-yaw -> offp=Rp.
- **Cadence:** 2x4 = 193.7 s/cycle (8 photos), ~24.5 s/photo, Tv-dominated (Tv=20s
  = 83%); was ~124 s at the old 5-shot single row.

Standing (Day-35 flags, not bugs): the RETURN rate-log spikes (173/87 dps) are a
+-180 logger-wrap artefact, not real whip (commanded slew is a single 40 dps move)
- confirm on footage. 2-min idle auto-de-energise can fire mid-pano (harmless when
parked through the arch). pano_planner.py still labels the 2nd block "Portrait" +
draws it single-row - cosmetic, doesn't show the grid. On-sky overnight is the real
proof.

## Closed Day-35 continued (17 Jun) — manual pano buttons, field network, headless boot, WiFi retry

- **Gimbal-UI manual pano (v154-v157).** Pano Center + Pano Cycle buttons on the
  Gimbal Recon screen, both firing at the CURRENT gimbal pose. Endpoints
  /gimbal/panocentre + /gimbal/panocycle (ordered before the /gimbal/pano prefix),
  panoStart(force_pose,oneshot), refused while a plan/track/shutter runs
  (manual-framing only; buttons grey out on exec RUNNING). All on-rig verified.
- **Three manual-pano fixes (v155-v157):** v155 read live camera Tv via
  ccapiGetCurrentTv(), NO 800ms default - refuse if unreadable (this was the v144
  fault reintroduced by copying an old idiom); v156 manual Center skips the rejoin
  fire (no 5th frame standalone); v157 one-shot Cycle returns to the captured
  CENTRE not cell 0 (was drifting 78deg/press on repeat).
- **Field-test network (v158).** Wavlink AX6000 "RosedaleVan" 192.168.20.x; cart
  static .20.97, camera CCAPI .20.99, gw/dns .20.1. Excel dataArduinoIP -> .20.97.
  Router must broadcast 2.4GHz + WPA2 (Giga is 2.4/WPA2-only).
- **Gated serial logging (v159).** GatedLog drops USB writes when no host -> boots +
  serves headless. (Insufficient for mid-run physical unplug - see open item below.)
- **WiFi join retry (v160-v162) = the real fix.** Cold-start first WiFi.begin is
  unreliable (bench: attempt 1 FAIL even with a 3s settle, attempt 2 connect). Now
  config once + up to 5 begin attempts before AP fallback. VERIFIED end-to-end on
  VIN-only, no serial lead: joins RosedaleVan in ~30s, reachable at .20.97. The 3s
  settle is kept but is NOT the mechanism.

OPEN (Day-35, carried):
- **Serial-write quarantine (DEFERRED, robust fix).** A physical USB unplug doesn't
  drop DTR, so (bool)Serial stays true and a mid-run Serial.write can still block
  the loop (observed: pano halted between photo 1 and 2 on unplug, resumed on
  replug). availableForWrite is unreliable on this core, so gating on connection
  state can't be made safe. Fix: route all logging through a lossy ring buffer
  drained by ONE dedicated logging thread (the only caller of Serial.write); the
  loop/pano/HTTP never block. Not yet built.
- **Manual pano endpoints print from the HTTP thread** (against the stash-to-volatiles
  pattern; harmless while unplugged via the gate, small interleave risk plugged).
- **On-sky 2x4 PanoCycle overnight** still the real proof (bench + rig-serial green).
- **Runtime WiFi auto-reconnect (SUPERSEDED -> see #47 RETIRED Day 35: BUILT + verified).**
  [The note below was the original FUTURE framing; the reconnect has since been
  built, on-rig verified under idle/pano/track, and retired - see the #47 entry.]
  Traced 17 Jun: WiFi connect +
  retry runs ONCE in setup() only; the sole loop-side WiFi code is soakLinkWatch(),
  which just logs LINKDOWN/LINKUP to the SD CSV - it never calls WiFi.begin. So if
  RosedaleVan drops and returns mid-run, a loaded plan keeps executing cart-side
  (RAM), but Excel/UI/CCAPI-over-WiFi stay unreachable until a power-cycle (driver-
  level silent re-associate is unverified - assume none). For an overnight rig this
  is a real gap. Fix: have loop() watch WiFi.status() (the LINKDOWN edge is already
  detected) and, once down for a few seconds, re-run WiFi.config + WiFi.begin to
  re-join - NON-blocking and throttled (retry every ~10-15s, skipped while STA up)
  so it never stalls the photo loop. Mirrors the boot retry. Confirm throttle/approach
  before building.

## Closed Day-34 (16 Jun) — pano + cable wind

- **PanoCentre hardening (v144–v151)** — deferred trigger at next due-fire
  boundary; per-cell hold = current_tv (real exposure); yaw-wrap fixes (offsets
  past ±180); settle flattened to 800ms; return-to-LIVE-centre + rejoin fire (no
  lost centre frame). Bench/serial verified.
- **PanoCycle hardening (v149)** — same ±180 yaw-wrap fixes on RETURN. Loops on
  the live arch centre (already correct). Verified on an arch GP.
- **E-STOP aborts pano (v150)** + **confirm() prompt (v151)**. Pause unchanged
  (graceful, defers to cycle end). Inventory: cart Move, Track, shutter, both
  pano modes all halt on E-STOP.
- **R10 CLOSED — cable strip draws astro track sweeps.** gimbal_cablestrip.py
  emits cablestrip_gps.txt; CableStripPush.bas reads + draws track bars (Python
  computes, Excel draws — single source). Was: track rows skipped, under-reported.
- **PanoCycle cable wind shown** — arch GPs widen the cable band by the portrait
  pano reach (±89°, from PANO sheet) so the photo-1/X swing is visible on top of
  the centre track; folded into span/headroom/sidecar.
- **arch below-horizon misclassification FIXED** (gimbal_planview_v2.py) — a
  Move/Track to arch_set was drawn as "goto-rise + wait"; arch bearings are valid
  all night, now excluded from the below-horizon test.
- **R7 CLOSED — general below-horizon rim hold (v152).** sun/moon/GC/mw: when the
  cubic altitude <= 0 the gimbal holds yaw + pitch 0 (rim), normal tracking above.
  Rise AND set, all rising/setting bodies — supersedes the narrow moon-only framing.
  Arch exempt. Cart decides from the cubic altitude it already evaluates (no new push).
- **Exec UI + ChartPush pitch axis 20-80 -> 0-80** so the rim hold (pitch 0) is on-
  chart, and the authored curve + live icon share one axis.
- **ChartPush below-horizon samples KEPT at rim** (was dropping them — GetSunGimbalAngles
  returns False below -5, so an 840-min overnight sun charted only 3 of 13 samples).
  Now matches the plan view + firmware rim hold; all three surfaces agree.

## Closed since Day 32 (Day-33 work)

- **Sun track didn't point at sun (cubic window)** — ROOT-CAUSED + FIXED (Excel
  AstroPush.bas). Cubics were fit over fixed astronomical windows (sun =
  sunset->sunrise) independent of the GP, so a midday GP evaluated the cubic
  before its window and clamped to the sunset endpoint (~298deg). Now each cubic
  is fit over its GP's plan window (PlanTrackWindows), with a Prep-Cart coverage
  gate + window-aware segment count. ON-RIG VERIFIED.
- **Gimbal long-way swing at acquire** — FIXED (v132). Acquire ease didn't wrap
  the yaw delta to +-180 (cubic is 0-360 azimuth, Ronin is +-180), so it slewed
  the long way round. Ease now wraps shortest-path like steady-state. ON-RIG
  VERIFIED.
- **Exposure target never reached cart** — FIXED (v131 + Formula.bas). Cart ran
  on the boot default 128; now Excel pushes the sunset/sunrise target pair and
  the LIVE walk selects by phase. Walk-to-target (v133) removed the one-sided
  deadzone undershoot. Tv ceiling (v134) and ISO ceiling/base (v135) now honoured
  in the LIVE walk, matching TABLE.
- **Cart idle de-energise / auto-energise** — FIXED (v128/v129). Boot leaves Tics
  de-energised; first motion auto-energises; 2-min idle drops it. VERIFIED.
- **Cam status 'deg' stuck out of plan** — FIXED (v130). Battery poll recovers
  comms_mode->NORMAL out-of-plan. VERIFIED.

STILL OPEN (this session): moon GP mostly below horizon in the bench test plan is
timing not a bug; cable-strip swing/fire-order cue (not requested to build);
night-palette red tuning first-cut.

## Closed since Day 31 (Day-32 work)

- **Earth-frame heading correction (3b baseline)** — BUILT (v103): trackPlanTick
  subtracts the plan's expected cart heading (col-H / `eh` token) as the
  earth-frame baseline; `hdg` is now the optional drift trim. Move earth-frame
  too (v104). SIGN still to confirm on a daylight Sun Track run.
- **Shutter wiring** — START fires shutter + exposure-init (v110); E-STOP / every
  stop path / plan END halt firing (v110/v113); Clear clears track (v114).
- **Anti-whip** — universal slew-rate floor 20 deg/s, all paths (v111).
- **Exec UI row rework (R6)** — hdg + eta coexist, eta direction explicit (v112).
- **Moon astro** — zenith-band ease added (moon transits >70 deg ~1 wk/month).
  Moon keyframes confirmed already wired. (Step-5 below-horizon goto-rise-and-wait
  firmware STILL OPEN = R7.)
- **Chart Track rendering (R4)** — swings coloured by Pan Speed, tracks by object.
- **Pan Speed model** — get-there duration + Pan Time + chart colour built;
  acquire ease retired in favour of Pan Speed rate.
- **Dateless fire-time class** — root-fixed (Utils.DatedFireSerial; Python live).

Still open: **F1** cart-motor-stop (future). **R7 below-horizon rim hold CLOSED
Day-34 (v152, general sun/moon/GC).** **R10 cable-strip astro-track sweeps CLOSED Day-34.**
See SOON_LIST.

Standing (not bugs): pano work (v144-v152) NOT yet flown overnight on real sky -
on-sky is the real test. Chart axis (chartsvg) must push every plan load or the
Exec icon maps to a stale yaw_min (saw a 3-push offset Day-34). E-STOP fetch chain
is success-chained (shutter->plan->btn14) with no catch - a failed first call skips
/plan/stop (seen Day-34: confirm hit, no serial). Fire the three independently,
plan/stop first, each with a catch. E-STOP confirm() adds a tap in an emergency.

---

**As of:** Day 31, 07 Jun 2026 — gimbal Plan View (#2) renderer + Excel
Render-Plan-View button LIVE; moon astro table->push->cart proven on the
spare GIGA (cart mask 127). See the Day-31 block immediately below for
remaining items. The numbered open-workfronts catalog further down keeps
each workfront's standing status. (Dated session-history blocks Day 13 ->
Day 25 - including the Day-25-part-2 BNO Wire2-isolation correction - have
been relocated to PROJECT_STATE_CONSOLIDATED.md; see the pointer below the
Day-31 block.)

This file lists work surfaced but not yet executed. Each item
references which session/day raised it. Prioritise per shoot
calendar.

## Day 31 (07 Jun 2026) — gimbal Plan View built; moon astro pushed; remaining items

Three work streams this session. Full detail in companion docs
(GIMBAL_PLANVIEW_BUILD.md, GIMBAL_PLANVIEW_REMAINING.md). Note: the
moon-astro and cable-UI workfront docs are now build-complete and have
been archived (see PROJECT_STATE_CONSOLIDATED.md); their remaining items
are carried in B and the Cart-UI block below. canon_battery_pause and
gimbal_WP_coordination remain LIVE deep-dives (still designed-not-built).

### A. Gimbal Plan View (#2) — renderer + Excel loop LIVE
DONE: Python renderer `Python/gimbal_planview_v2.py` (non-cumulative
reference model: base = Ry when present else WP heading; pitch = Rp else
0; deltas additive; NO accumulation). Pitch-as-length glyphs, world-sweep
legs (1->2->3->4) obeying col-AC CW/CCW with near-180 ambiguity flag when
blank, PREV/NEXT, map-underlay hook, park-and-wait marker. Excel side:
`Modules/GimbalSweepDir.bas` (auto-fills col AC shortest cart-frame
CW/CCW, preserves overrides) + `Modules/GimbalPlanViewButton.bas` (the
Render Plan View button; outer-quoted cmd /c; logs to render_log.txt).
Hardware-confirmed render loop on operator machine (Python 3.14).
REMAINING:
- **FIX #11 validation chart (real bug).** GimbalPlanViz_v3 accumulates
  Move rows — same stale cumulative model removed from the plan view.
  Its trajectory, max-|cum yaw| and +/-450 cable numbers are WRONG.
  Re-base on the non-cumulative reference model + col-AC cable calc.
- Cable strip (view #3): linear -450..+450, reads col AC, shows wind-up;
  the plan view deliberately omits cable (gimbal-pointing only).
- Map underlay v2: auto-fetch static tile from Settings lat/lon (needs
  API key + network; operator machine, not sandbox). v1 (manual
  screenshot --map) works; Tapanappa is the reference image.
- Update GIMBAL_PLANVIEW_BUILD.md — predates the non-cumulative + col-AC
  decisions; its resolver pseudocode is stale.

### B. Moon astro — table->push->cart proven; firmware piece remains
Decisions: moon IS in scope; moon obeys no-shoot-under-horizon ->
goto-rise-and-wait (supersedes the old "no horizon gating" line in
GIMBAL_EXECUTION_CAPABILITIES).
DONE + hardware-confirmed (spare GIGA, no gimbal/camera): step 3 moon
AstroTable column (Astro.bas GenerateGCTable, cols G/H/I); step 4a astro
push (AstroPush.bas PushAstroToCart -> mnry/mnrp/mnsy/mnsp); step 4b
track-path cubic was already in production; step 6 renderer reads moon
defensively. 07-Jun push returned cart `"mask":127` (all 7 slots; moon
bits 2/3 now on, was 115). Both .bas swapped as whole modules + compiled.
REMAINING:
- **Step 5 (FIRMWARE): moon below-horizon goto-rise-and-wait** in the cart
  executor/cubic — park at rise bearing + hold, no underground tracking.
  Same treatment as sun/GC. This is the only un-built moon item.
- Verify Show astro -> Moonrise/Moonset actually SWINGS the gimbal —
  untested (main GIGA out for repackaging, spare in use, no gimbal).
- DECIDE: tonight moonset resolved to 12:21 / az 264 (a MIDDAY set,
  outside the 4pm-8am window; FetchMoonTimesForNight clamped to
  sunrise+0.5 and accepted it as bookend). Confirm desired vs "none in
  window." Moonrise 23:23 is inside-window and clean.

### C. Canon R3 overnight power — battery-swap pause fallback (FUTURE)
Primary path = continuous adaptor (in place) for the ~16h 4pm-8am run.
FALLBACK if adaptor missing/fails: operator-triggered pause that freezes
the gimbal pose, holds the exposure clock, allows a quick battery change,
resumes via Phase-A ease — reuse the parked pano suspend/resume plumbing.
Measure-first: does R3 keep Tv/ISO across a DC-coupler power cycle
(CCAPI re-init on resume?); tolerable gap before a visible seam; trigger
on the execution UI. (Ronin can also feed the camera — native ~18W
USB-C, or true 12V via a P-Tap/V-mount accessory plate — as an alt to
the swap; 18W-sustains-R3-overnight is unverified, measure.)

### D. Exec night mode (red-on-black) — FUTURE, spec exists, never wired
The day/night toggle is a long-standing MOCKUP/spec, NOT built. The Day
tab in the cart UI is a dead stub (`<a href='#'>Day</a>`); both UI_DESIGN
docs confirm it was always a no-op pending the Exec screen (now built),
and PROJECT_STATE item 12 lists it "Parked". So this is build-the-parked-
item, not find-lost-code.
Spec (locked by mockup, transcribe don't invent):
- Global day/night theme; **only the Exec screen repaints** (Cart/Gimbal
  are daytime-only, toggle is a visible no-op there). Tab stays in the
  header, label flips DAY<->NIGHT.
- Trigger: auto hard-flip at nautical sunset/sunrise (cart has the sun
  times from astropos) PLUS a manual override button. DECIDE: auto+manual
  (as specced) or manual-only to start.
- Night palette (UI_DESIGN_v2, "no white anywhere"): bg #000; panels
  #0a0202; borders #2a0808; body text #7a1818 (dim red); active/labels
  #a82020; critical accent #d04040; button base #1a0606 / border #4a0c0c;
  action base #3a0a0a / border #7a1818; header icons red @50% opacity.
- v3 note: the toggle is also where the alert-sound audio-unlock
  ("tap to start") lives (UI_DESIGN_Execution_v3 section 5) — separable
  but co-located.
Build = an Exec-screen night-CSS block swapped by the toggle; firmware.

### E. Cable strip arcs on the cart SVG — DONE (Day 31)
Added the sweep-order arcs (green forward / red reverse-turnaround), GP id +
cart-frame yaw labels (staggered above/below by x-order to avoid overlap),
max-wind flag, and the right-edge "lim" tick to the cart SVG authored by
CableStripPush. "Excel authors the rich background, Giga moves the marker" —
cart firmware unchanged. Fragment grew ~611 -> ~1580 chars (5 -> 11 push
chunks). Verified by rendering the exact fragment.

### F. Cable strip frame: world -> CART-FRAME — DONE (Day 31), correctness fix
CONFLATION CORRECTED. The cable strip was unwrapping each GP's WORLD bearing
(180/280/440/270), which folds in the cart's own per-WP heading change as if
it were gimbal wind. Cable tangle is gimbal-relative-to-cart = CART-FRAME.
Fix (CableStripPush): per-GP value is now cf = world - heading(anchor),
matching the dial resolver (gimbal_planview_v2.py: cf = ((world-h+540)%360)-180);
chassis GPs reduce to cf = dyaw. Same col-AC unwrap, same 450 span, min left.
For the live plan this changes the read from world 180->440 (260 used /190
headroom) to cart-frame 0->170 (170 used /280 headroom) — the gimbal is far
from a cable problem; the old number was inflated by the cart turning between
waypoints.
Bonus: the strip and the preview/jog poses are now in the SAME frame
(both cart-frame 0/100/170/0), so the index-marker and the status-line
degrees on the cart agree — resolves the earlier frame-mismatch caveat.
Frames, settled:
- Gimbal/plan dial = WORLD (Ry, true-North) on the map — "where the camera
  looks in the real world". 180 = south, etc.
- Cable strip = CART-FRAME (cf, relative cart nose) — "how far the gimbal is
  wound off the cart body, vs the 450 cable limit". 0 = cart front.
These two SHOULD differ; they answer different questions.
OPEN: the planning-side gimbal_cablestrip.py still plots WORLD-unwrapped
(imports the resolver's world). One-line change there if the van PNG should
match the cart strip — not yet done.

### Cart UI tidy-up — DONE (Day 31)
- Cable screen (view #3) built + flashed (soak-v102): ?screen=cable,
  /settings/cablesvg, index-driven marker, PREV/NEXT jog reusing /preview/step,
  PLAN_RUNNING interlock. See WORKFRONT_cable_ui.md / FIRMWARE_PATCH_cable_screen.md.
- "Day" tab was a dead stub (href='#'); removed from the nav row. Day/Night
  toggle relocated to a button at the top of the Exec screen body (self-
  contained label flip; real red repaint = workfront D). Confirmed never-built
  mockup, not lost code.
- Tab order reordered Cart - Gimbal - Cable - Exec (left-to-right workflow).
- Cable strip was distorting under preserveAspectRatio='none' (viewBox stretched
  to a wider container). Changed the cable <svg> to 'xMidYMid meet' (uniform
  scaling, dots stay round, letterboxes on wide screens). Exec chart left as-is.
  A fixed viewBox can't be stretch-free across device widths under 'none'.

### G. Gimbal WP-event coordination — Phases 1-3 DONE; Phase 4 + 3b heading REMAIN
Phases 1-3 (WP-event-anchored GP firing) are BUILT + hardware-proven (soak-v37, nudge
test passed Day 30) — now recorded in PROJECT_STATE.md. REMAINING:
- **Phase 4 piece A — live Sun Track WP-anchored run (DAYLIGHT).** Needs NO new code
  (Phase-2 window selection is mode-agnostic; cubic eval / Model B real-time proven
  Day 24); only a live confirmation that a Track GP anchored to a WP opens on WP
  arrival and the gimbal follows the sun. DEFERRED Day 30 (sun down ~6pm Adelaide
  June). FOOTGUN: the cubic rt0 (AstroPush, UTC) and `/settings/realtime` anchor MUST
  both be UTC epoch-ms; local time aims the sun off by the Adelaide offset (~9.5-10.5h).
  No realtime-push macro exists — bench: hit `/settings/realtime?ms=<UTC epoch>` by hand.
- **Phase 4 piece B — earth-frame heading correction (3b), ENDPOINT FIRST.** The
  genuinely-new build (operator order Day 30: build both halves, endpoint first — the
  executor correction has nothing to apply until the endpoint feeds a value). No sign
  flip (cart + gimbal both CW-positive since Day 30; see #40).
  - 1a ENDPOINT: push per-WP `expected_cart_heading` (PlanBuilder already writes it to
    Plan col H — just send it to the cart); store cart-side; the Exec `hdg` button
    (currently a STUB) posts the operator's REAL heading; cart computes delta and stores
    it as the running offset — REPLACE not additive, FORWARD-only, non-blocking (no input
    -> planned floor). Test: post a heading, read the stored offset back in `/exec/feed`.
    NEXT ACTION on resume: read how col H / expected_cart_heading flows before wiring.
  - 1b EXECUTOR (3b): `trackPlanTick` astro path applies
    `gimbal_yaw_correction = real_heading − expected_cart_heading` (+ Adelaide declination
    + mount) to commanded gimbal yaw, EARTH-FRAME GPs ONLY. Testable once 1a exists,
    ideally in the daylight Sun Track run.
- Two build-time decisions still parked: fire-late-vs-skip when an offset window is still
  open at the next WP (offsets were all 0, not exercised); Pan-Follow -> Track handoff ease.
- Doc reconciliation to HEADING_CONVENTION.md still owed: CART_HEADING_DESIGN,
  GIMBAL_EXECUTION_CAPABILITIES (Delta-yaw wording), GIMBAL_VIZ, WORKFRONT_gimbal_WP_
  coordination_Day29 sec 4. (#40 + PROJECT_STATE done this pass.)
- LOOP-LONG ~1.4-3.0s stalls at `/track/start` + first interval entry — noted, NOT
  investigated (partly the gimbal SLEEPING; wake it). Instrument before theorising.

### H. SERVO_TO_DEG / slip calibration — STILL UNSETTLED (carried from Day 25-30)
The bicycle model OVER-rotates: the +35 leg drives ~3.1m of arc reading ~128deg vs a
true ~90deg (compass ground truth -180 -> -270). SERVO_TO_DEG = 0.504 is a Day-9 grass-
circle PLACEHOLDER; this recon implies ~0.33-0.35; circle implies slip ~0.54 — they
BRACKET the real value, not decided. Agreed structure (not yet implemented): pure
geometry (28deg wheel / 0.49m wheelbase) x a SLIP factor, replacing the single conflated
constant. RESOLUTION = a CONTROLLED re-test (linearity +5/+15, symmetry -30) with the
servo properly fed (YEP 20A BEC fitted Day 26), marking a WP at every speed/steer change.
The bicycle model is a planning VISUALISATION only (not fed to cart execution), so this
gates plan-trace trustworthiness, not live aiming. (Cross-ref calibration section #20/#21.)

### I. "Prep" button — one-press nightly prep chain (DESIGN, not built)
Chain the 7 prep steps into one press (operator idea, Day 31). Run order (each needs the
ones above): 1 Get Sunset Time -> 2 Init Shoot -> 3 Generate GC Table -> 4 Push Astro to
Cart -> 5 Push Track Paths to Cart -> 6 Fetch Gimbal Map -> 7 Render Plan View.
- Steps 1-5 are nightly (date-bound); step 6 is location-bound (skip if Python\map.png
  exists, or a "refresh map" checkbox); step 7 lands the operator on the dial.
- On any step failure, STOP and report which step (don't push half a chain to the cart).
- Camera/CCAPI absence is NOT a failure (Tv fallback) — Prep tolerates an absent camera.
- DECIDE at build: does Prep require the cart online (steps 4/5 push)? A "cart online?"
  check up front makes Prep safe to run Excel-only (1-3 + 7) when the GIGA is down.
  Re-run safety: all steps idempotent (recompute + overwrite) — confirm holds for cart pushes.
- When the cable strip becomes a standalone output, it slots in after Render (or as a
  second output of the same press).

---

> **Dated session-history blocks (Day 13 → Day 25) relocated to the archive.**
> They were build narrative, not open work. Find them in
> PROJECT_STATE_CONSOLIDATED.md under "WORKFRONTS history (relocated from
> WORKFRONTS.md)". The numbered open-workfronts catalog continues below.

---

## Open workfronts — cart firmware

**#5a Segment dispatcher + cubic evaluator.** ~50 lines C. Segment
types: HOLD, LINEAR, CUBIC (Catmull-Rom as standard cubic
coefficients), PANFOLLOW. Per tick: eval at (now - t_start),
quantise to 0.1°, accumulator-driven setPosControl. Day 8 design;
not yet built.

**#36d Table Mode + comms-recovery (DAY-15 STEP D COMPLETE).**
Architecture from Day 13. Build delivered Day 14. Step D recovery
delivered Day 15. End-to-end verified across two test cycles
(Day 14: LIVE → TABLE; Day 15: full LIVE → TABLE → LIVE).

Built:
- `exposure_mode` (LIVE/TABLE), `comms_mode` (NORMAL/PROBING)
- `findTableRowForTv()` with seconds-based comparison + 0.5% epsilon
  (handles Excel decimal vs Canon-format Tv strings)
- LIVE → TABLE handoff with `Δt_rel` capture, `last_table_tv/iso`
  seeding
- Comms-recovery state machine: any CCAPI connect-fail → PROBING;
  ping (1s, `WiFi.ping()`) every 3rd photo BEFORE pin-8 fires;
  3 ping fails → TABLE; ping success → NORMAL
- `tryStartLiveviewIfNeeded` gated on NORMAL + LIVE; ANCHOR call
  gated on NORMAL
- TABLE-mode gates at every CCAPI origination site
  (`lum_fetch_pending` arm, fetch service block, PROBING entry
  in ccapiRequest) — once in TABLE, only Step D's ping can move
  the cart out
- **Step D (Day 15):** 60s wall-clock TABLE-side ping probe;
  merged probe-fire block with explicit `from_table`
  classification; on success → `exposure_mode = LIVE`, discard
  `Δt_rel`, invalidate `lum_liveview_started` so a fresh
  `/liveview` POST restarts the histogram session
- `/debug/ping` endpoint for diagnostics (`/debug/match` retired
  Day-15 part 3 with `findTableRowForTv`)
- `/exposure/state` returns full mode + probe + comms state

Not yet built (and acceptable for production):
- **TABLE per-cycle PUT logic (Step 4 of original Day-13 plan).**
  CLOSED for v1 (Day-15 part 2): logically impossible, CCAPI
  unreachable in TABLE by definition. Re-opens as a v2 build task
  (wired Ethernet link is independent of the WiFi outage that
  caused entry to TABLE). Day-15 part 3 follow-up retired the v1
  scaffolding that anticipated Step 4 (`exp_delta_t_rel`,
  `last_table_tv`, `last_table_iso`, `findTableRowForTv`,
  `/debug/match`). Rebuilt from scratch in v2 if/when needed.

  **v2 ENABLER (recorded Day 35): the manual backup ladder CAN run
  over the W5500 wired link.** The "logically impossible" reasoning
  only holds when ALL cart->camera comms ride WiFi. The Giga has a
  W5500 Ethernet path to the camera that is independent of the WiFi
  AP. So the failure mode that triggers TABLE (WiFi/AP drop, or
  Excel<->cart link loss) does NOT necessarily take down cart->camera
  CCAPI if that runs over the W5500 hardwire. In that case the cart
  CAN still PUT Tv/ISO. The v2 build is therefore:
    1. On LIVE->TABLE, capture the millis->sunset offset (t_rel at the
       moment of the drop) and find the current rung on the pushed
       Tv/ISO ladder (the retired `findTableRowForTv` math) so the
       table resumes from where the live LUM walk had progressed - no
       jump.
    2. Each cycle in TABLE, evaluate formulaTv/formulaIso at the live
       getCurrentTrel() and PUT over the W5500 link, continuing the
       Tv/ISO walk toward sunset/sunrise on the time curve.
    3. Verify findability against current verified state: the pushed
       table blocks (exp_sstv/ssiso/srtv/sriso) ARE received + stored
       and the anchor (t0ss/t0sr/cross) drives getCurrentTrel() off
       the local clock - both already present; only the seed + the
       per-cycle PUT-over-W5500 are missing.
  Status as of Day 35: NOT in the sketch (grep confirms no
  findTableRowForTv / last_table_tv / delta_trel; formulaTv/Iso are
  reachable only via `/debug/formula`). TABLE currently just freezes
  Tv/ISO and fires the pin until a recovery probe restores LIVE.

**#36d cleanup (CLOSED Day 15 part 6).** Traced through the
original "dead state vars" list. Verified status of each:
- `FETCH_FAIL_BACKOFF_CYCLES` — dead, removed Day 15 part 5.
- `MODE_FLIP_THRESHOLD` — dead, removed Day 15 part 5
  (`PROBE_COUNT` is the live equivalent).
- `lum_fetch_skip_remaining` — dead, removed Day 15 part 6
  (branch was unreachable; nothing ever set it non-zero).
- `lum_consecutive_conn_fails` + `LUM_FAIL_THRESHOLD` — NOT dead.
  Still load-bearing as the liveview-died detector (3 connection-
  level fails invalidates `lum_liveview_started` for fresh re-POST).
  Also exposed in `/exposure/state` JSON. KEEP.
- `lum_in_outage` — NOT dead. Load-bearing for log-spam
  suppression (first fail logs verbose, subsequent fails throttle
  to every Nth attempt). Also exposed in `/exposure/state` JSON.
  KEEP.
- `consecutive_fetch_fails`, `consecutive_fetch_successes` — already
  kept in earlier passes, still consumed by `/exposure/state`.

Original WORKFRONTS line "all sitting at 0 / dead-branch" was
wrong about the lum_* vars; corrected by tracing.

**#36d follow-up: canFlip preconditions stale (CLOSED Day-15 part 6).**
`tryFlipToTableMode` originally required `exp_anchor_set &&
exp_tv_ceiling_sec != 0 && current_tv.length() > 0`. These existed
to feed `findTableRowForTv`, retired Day-15 part 3. Decision: the
execute UI (planned, separate workfront) prevents uninitialised
cart starts upstream, so the gates protected against a case that
can't happen at runtime. Removed. Also aligns with photos-sacred
+ autonomous-cart framing: if CCAPI fails, reaching TABLE is the
right move regardless of init state.

**#36d follow-up: TABLE-during-comms-dead semantic question
(CLOSED Day 15).** Question was: in TABLE, should we PUT Tv/ISO
to the camera over CCAPI (which we can't reach), or just walk
the table cart-side and let the camera stay frozen? Resolved
by the camera-as-AP decision (see fallback architecture
section above): with the external AP removed, the only outage
mode is camera-side WiFi failure (accepted risk, rare). When
that happens, TABLE walks cart-side state only; camera stays
frozen; LRTimelapse fixes drift in post. (a) accepted.

**#48 /shutter/stop bus fault — CLOSED Day-15 part 7.**
Resolution: minimal /stop handler. `ccapiStopLiveview()` removed
from the /stop path; that DELETE was housekeeping (the camera
times out its own liveview session and `ccapiStartLiveview()`
already handles "Already started" 503 from leftover sessions).
/stop now only sets `shutter_mode = 0`, clears pause, prints
summary. Cannot crash because no blocking network or CAN call.
Verified across two full /start → photos → /stop cycles, both
clean.

**Investigation summary (kept here for v2 reference):**

The crash was intermittent, in `WiFiClient::read` /
`Stream::readStringUntil` inside the DELETE call. addr2line on
crash dumps showed two distinct mechanisms:
- Mechanism A (3 of 4 dumps): CAN RX ISR preempted into the
  WiFi read at the wrong moment. `CanMsgRingbuffer::enqueue`
  wrote to a corrupted address — measured addresses were valid
  heap pointers with bit 16 or 17 flipped (0x20025961, 0x200259d2,
  0x2002ba5a — all OUTSIDE the 32 KB SRAM region).
- Mechanism B (1 of 4 dumps): crash in same WiFi read, but no
  CAN ISR in the stack. Fault address 0x810076c3 — different
  pattern, high bit set. Some other corruption source.

Stack measurement showed 1024/1024 bytes used in normal idle
operation (Uno R4 stack region is only 1 KB). Strongly suggestive
that ISR preempt has nowhere safe to push registers, but didn't
fully explain mechanism B.

**Things tried that didn't fix it:**
- Char-buffer reads in ccapiRequest (Day-15 part 7 fix attempt 1):
  removed our String allocations, but WiFiS3 library allocates
  Strings inside `client.read()` itself. Reverted.
- `enablePush(false)` + delay before DELETE (fix attempt 2):
  silenced CAN traffic during the vulnerable window. Removed CAN
  ISR from the crash stack but mechanism B still crashed. Reverted.
- v3 regression test: pre-cleanup sketch ran clean once but crashed
  on second test. Bug is intermittent on identical code.

**Why the bug appeared only on Day 15:** unclear. /stop call path
(`ccapiStopLiveview` → `ccapiRequest`) is unchanged from Day 14
era. Possibilities not investigated: heap fragmentation pattern
from accumulated WiFi traffic over longer test sessions; transceiver
replacement timing (some crashes happened with original transceiver,
some with replacement, so not a clean dividing line); or simply
more /stop tests today than ever in one session (statistical
exposure).

**Note on "hardware-damaging" claim from Day-15 part 5:** the
in-RAM corruption mechanism has no obvious path to damaging the
external transceiver chip. Transceiver death may be unrelated to
the bus fault; cause genuinely unknown. The Day-15 part 5
assertion is unsupported by evidence.

**For v2 (#47, Giga + Ethernet):** the WiFi-blocking-read +
CAN-ISR combination doesn't exist on v2 (camera over wired
Ethernet, different stack, much more SRAM). Whether to restore
the polite DELETE on /stop in v2 is a decision for that build —
measure first if the crash mechanism still surfaces.

**#47b Production v2 — wired Ethernet to camera (FUTURE,
not blocking).** v1 (current all-WiFi via external AP) is
sufficient. v2 reduces comms risk fundamentally by moving
the camera link to a wired Ethernet point-to-point.

**Hardware (chosen Day 15):**
- Arduino Giga R1 WiFi (already on hand — was held in
  reserve per #22)
- Arduino Ethernet Shield 2 (W5500, $51.15 AUD from Core
  Electronics) — to buy
- Short Cat5e/Cat6 cable cart→camera RJ-45

**Board choice rationale.** Both Uno R4 + Shield 2 and Giga
R1 + Shield 2 work technically. v2 picks the Giga because:
- Giga is already on hand
- v2 is the natural trigger for #22 (Giga migration). Per
  architectural principle #14, Giga activates only when a
  specific design need outgrows the Uno; v2's Ethernet
  stack + simultaneous WiFi STA for operator UI is the
  first design that materially benefits from Giga's headroom
  (1 MB SRAM, dual-core, more SPI ports, more flash)
- Going to Giga now avoids doing a board migration *after*
  v2 ships when something else outgrows the Uno

**#22 Giga migration is now part of v2.** No longer a
separate workfront — it's the migration step inside the v2
build. Port production sketch from Uno R4 (50% flash, 68%
globals) to Giga's STM32H747. Code is mostly portable;
attention needed on WiFi library, SPI assignment, pin
numbering, timer-based code (PIN8 PULSE timing, fetch
timing), and any AVR-specific bits if present.

**Topology:**
- Cart ↔ camera: Ethernet cable, CCAPI over the wire
- Camera WiFi: disabled, never used
- Cart WiFi: STA mode joining external AP, for operator UI /
  Excel only
- External WiFi never reaches the camera

**What this eliminates:**
- Camera-WiFi-off failure mode (no WiFi to fail)
- External-AP-to-camera failure path (doesn't exist —
  external AP only touches cart, not camera)
- Whole comms-outage architecture (TABLE mode, Step D) becomes
  irrelevant for normal operation. Could be retained as a
  belt-and-braces fallback for Ethernet-cable-fault, but the
  failure rate would be near-zero.

**What survives unchanged:**
- External WiFi for operator UI / Excel plan push. If
  external AP fails, operator loses visibility but photos and
  exposure tracking continue unaffected.
- Continuous power cable to camera (already in place).
- Day-15 reliability claims for CCAPI hold over Ethernet —
  same HTTP, same endpoints, same protocol.

**Additional simplification (operator's call):** drop pin-8
firing entirely, fire shutters via CCAPI HTTP over the wire.
- Removes the pin-8 cable from cart to camera N3 port
- Single comms path for both shutter and exposure control
- Photos-sacred guarantee transfers from pin-8 hardware to
  Ethernet+CCAPI reliability — acceptable because wired link
  is more reliable than WiFi by a wide margin
- Permanent / keep-alive HTTP connection avoids per-photo
  connect overhead and detects link loss immediately on
  write failure
- Latency variability vs pin-8: not a concern at 1320×
  audience speed; sub-frame jitter doesn't show
- Architectural principle "Pin-8 must work when CCAPI is
  unreachable" (PREFERENCES #12) becomes obsolete and would
  be retired

**What needs to be checked / built:**
- Hardware: W5500 SPI Ethernet shield or module on the Uno
  R4. Cat5e/Cat6 short cable to camera RJ-45.
- Coexistence: WiFiS3 (uses SPI) + W5500 (uses SPI) on
  different chip-selects — should be fine, verify
- CCAPI over Ethernet: confirm Canon CCAPI behaviour
  identical to WiFi (expected per Canon docs, R3 spec lists
  Ethernet as supported CCAPI transport)
- CCAPI shutter timing: measure cadence variance via HTTP
  shutter call, compare to pin-8 baseline (Day-12-style
  oscilloscope approach)
- Keep-alive strategy: persistent TCP connection across the
  shoot, write-fail detection as immediate outage signal
- Camera config: disable WiFi, enable Ethernet network mode,
  configure static IP on the camera-cart subnet

**Decision deferred to when v2 is actually wanted.** Real-world
v1 experience will tell us how often external AP issues
actually bite. If they're rare, v1 stays. If they're common,
v2 (wired Ethernet) is the chosen path. Camera-as-AP and
USB+Pi+EDSDK options from earlier Day-15 research are no
longer in the running — wired Ethernet is structurally
cleaner than either.

**#40 BNO085 integration (build phase).** SUPERSEDED by
the #40 BNO085 section below — work from that single source.
Status (Day 25): BNO is on the SHARED Wire bus (D20/D21, polled, no
INT/RST), NOT the originally-planned UART-RVC. Hardware + read PROVEN
and enabled (survives motors after the 2.2k pull-up fix; live read +
360° turn reproducible under production load). DONE: `/debug/imu*`
endpoints (offset/cal/raw_yaw/true_yaw/last_poll_ms_ago); CartLog `A`
events; calibration method (off-cart figure-8 → `/savecal` → stored DCD;
saved-DCD is the chosen path); cal rule ≥2 use / ≤1 keep-previous;
stationary "duck off" read model (replaces the old 500/400 mm two-
attempt retry). REMAINING for 3b: plan-stream `expected_cart_heading` +
per-segment earth/chassis frame tag (confirmed absent in soak-v18) →
then `gimbal_yaw_correction = (−true_yaw) − expected_cart_heading` on
earth-frame cubics + Excel `bnoOffsetDeg` push (negate BNO yaw; offset =
Adelaide declination +8.11° + ~+1° mount). `expected_cart_heading`
source = Excel `BicycleModel.bas` (planned θ per anchor waypoint).

**#43 Cart UI "Start New Log" button.** New endpoint
`/cartlog/clear` (or similar). Cart UI button POSTs to it,
clearing in-RAM cart log without requiring Excel-side retrieve
first. Existing `/cartlog` retrieve-and-clear stays; this is for
abandon-without-save. Promoted in importance Day 10 (with
Smooth Selection rejection, redrive is the correction mechanism).

**#45 Speed editing in CartLog — firmware side check.** Operator
edits S-row Value column to set per-segment execution speeds (5
m/hr photographable, 10 m/hr transitions). Open question: does
today's `/plan/load` segment format (`TYPE,VAL,STEER,SPEED,END`)
accept per-segment SPEED overrides cleanly, or does cart firmware
need an update? Verify before extending Excel side.

---

## Open workfronts — cart UI

**#10a Gimbal UI page — DELIVERED Day 16.** Implemented as Gimbal
Recon screen on the unified UI (one URL, server-side
`?screen=cart|gimbal|exec` routing, not a separate URL as Day-8
proposed). Spec: UI_DESIGN_v2.md (Day-15 Part 10). GIMBAL_VIZ.md §3
annotated as superseded by this delivery.

Built:
- Live readout `Ry · Cy · p` (Ry=Cy until BNO integration)
- 4 prior captured-row slots + Current row block (newest at slot
  closest to buttons)
- Type rows: PF / Lock / Move / Track sun (operator-authored);
  Sunrise / Sunset / MW (astro)
- Conditional sub-controls: keyframe (rise/mid/end) for astro,
  R/C frame toggle for PF+Move, yaw Δ / pitch Δ for astro,
  measured-variance line for astro
- Label field, Clear button on Current row
- Action row: Show astro / Snap var (TODO stubs — see #50) / Next
- Per-type pose handling: PF/Lock/Move capture pose AND write to
  cart gimbalLog via /btn20; astro and Track sun are intent-only
  with no pose, no gimbalLog write

Production-readiness pending #49 (rich-row persistence).

**#10b Notes / hints panel on cart UI (CLOSED Day-15 part 7).**
Built — multi-line text panel rendered below the action buttons
on Cart Recon screen. Day-16 build preserved the content (turning-
circle table) and moved it under the new Cart Recon screen.

Current content:
- Turning-circle table (servo 5°/10°/15°/20°/25°/30° → diameter
  18.0/10.0/7.5/5.6/4.8/4.2 m, tightest = 30°). Absorbed from
  retired #29a workfront.

The /stop warning that was planned for this panel is no longer
needed — #48 was resolved separately in Day-15 part 7 by making
/stop a no-op for housekeeping.

Add further tips by inserting `client.println` lines inside the
notes `<div>` block (Cart Recon body in v1prod sketch).

**#49 Gimbal Recon rich-row persistence (NEW Day 16).** Gimbal Recon
captured rows live client-side only as built; reload kills type/
label/keyframe/offset data. Cart-side struct extension + push
endpoint required before Gimbal Recon is production-usable.

*Scope:*
- Extend `GimbalLogEntry` struct with: type (1B enum), kf (1B enum),
  fr (1B enum), offY (float), offP (float), label (12-char fixed
  array — avoids heap fragmentation, #48 contributor)
- New endpoint `/gimballog/push?rows=...` accepting query-encoded
  rich rows; clears existing gimbalLog and replaces
- Gimbal Recon JS calls /gimballog/push on every Next-bake (or on
  a new explicit "Push to cart" button) instead of /btn20
- /gimballog Excel-pull endpoint returns the rich CSV; Excel parser
  updates for new columns

*Costs:* ~+600 bytes SRAM globals (struct grows, ~30B × ~20 slots).
68.9% → ~70.7% — still well clear of the ceiling that bit Day 7's
CART_LOG_MAX bump.

*Risks:* heap fragmentation from String labels — fixed-size char
array mitigates. Excel parser change requires coordinated update.

*Verification path:* author 5 mixed-type rows, reload page, captured
list reconstructs from /gimballog; pull from separate tab confirms
all rich fields; pose-types still write yaw/pitch, intent-types
carry zero pose.

**#50 Excel astro position push to cart (NEW Day 16).** Unlocks the
Show astro and Snap var buttons on Gimbal Recon.

*Architecture (Path A chosen Day 16):* Excel pre-computes today's
astro positions and pushes to cart in a new settings field. Cart
stores 7 yaw/pitch pairs (sun rise/set, moon rise/set, MW rise/
mid/end ≈ 56 bytes + 1 mask byte). On Show astro tap with
type+keyframe context, cart commands gimbal to stored position.

Path B (cart computes astro on-the-fly via ported `GetSunGimbalAngles`)
was considered and rejected — duplicates Excel logic, larger flash
hit, conflicts with day-8 architecture "astro pre-baked in Excel,
cart sees cubic coefficients only."

*Scope (final after Day 17 build):*
- Excel side: button to "Push astro to cart" that calls
  `GetSunGimbalAngles` / `GetGCGimbalAngles` for sun + MW (already
  built in Astro.bas), and new moon astro maths (see #55), posts
  to cart endpoint `/settings/astropos?...`
- Cart side ✅ BUILT Day 17 (second session). 10 globals + mask,
  `/settings/astropos` GET/POST, `/gimbal/showastro?type=...&kf=...`,
  `/gimbal/snapvar?type=...&kf=...`, `/gimbal/showastrooffset?...`
  (workflow B for typed-offset verification, not in UI)
- UI side ✅ BUILT Day 17 (second session). Show astro / Snap var
  buttons wired; Sunrise/Sunset/Moonrise/Moonset/MW type buttons;
  keyframe sub-row appears for MW only.

*Cart vocabulary:*
- types: sun, moon, mw
- keyframes: sun/moon → rise|set; mw → rise|mid|end
- URL params: sry/srp (sun rise), ssy/ssp (sun set),
  mnry/mnrp (moon rise), mnsy/mnsp (moon set),
  mry/mrp (mw rise), mmy/mmp (mw mid), mey/mep (mw end)

*Dispatch-order bug found and fixed Day 17:* original
`path.startsWith("/gimbal/showastro")` matched both showastro AND
showastrooffset (prefix collision). Changed to
`path == "/gimbal/showastro" || path.startsWith("/gimbal/showastro?")`.

*Status:* cart side ✅ done. Excel side ✅ done (Day 31) — moon now
pushed, cart returned mask 127. ~~Excel side pending — see #55 for
moon maths, #50-Excel for push button.~~ (Superseded by Day-31 block B.)

**#55 Moon astronomy maths in Excel — CLOSED Day 18.** Full
sun-equivalent treatment delivered: local Schlyter low-precision
ephemeris in Astro.bas (GetMoonPosition + public wrappers),
FindMoonCrossing/BisectMoonAltitude root finder, AstroPush.bas
populates mnry/mnrp/mnsy/mnsp on /settings/astropos and adds
moon as third object to /settings/trackpath. Window selection
handles all four cases: rise+set in envelope, rise-only,
set-only (moon up at sunset), neither. Validated against
timeanddate.com for Adelaide 25-May-2026: local moonset 01:07
vs timeanddate 01:09 — 2-minute agreement (~0.5° at moon's
apparent motion), well inside 14mm FOV tolerance.

**Note on data source:** initially planned to use api.sunrisesunset.io
for moon rise/set times. Cross-check vs timeanddate.com Day 18
revealed the API was 64 minutes off (reported 02:11 vs
correct 01:09). Local maths in Astro.bas was 2 min off.
Local wins on both accuracy and offline operation — API path
dropped from the design entirely. Zero internet dependency
for any astronomical computation now (closes part of #57).

End-to-end test (Day 18): PushAstroToCart returned mask=11
(sun_rise + sun_set + moon_set) with moon_set yaw 274.90° /
pitch -0.50° — matches timeanddate's 275° azimuth within 0.1°.
PushTrackPathsToCart pushed sun (4 segs) + moon (4 segs) + MW
(4 segs) successfully.

**#56 Morning astronomical dawn missing in Excel — PARTIAL Day 18.**
Sun computation moved fully local Day 18. Astro.bas
FindSunCrossing(date, targetAlt, dir) computes all 8 sun
crossings — sunrise/sunset/civil dawn/civil dusk/nautical
dawn/nautical dusk/astro dawn/astro dusk. GetSunsetTime now
populates dataSunsetTime/SunriseTime/CivilDawn/CivilDusk/
NauticalDusk/AstroDusk. Still missing on Settings sheet:
dataNauticalDawn, dataAstroDawn (need named ranges added).
Tonight (Day 18) MW push worked using the existing
sunrise-90min proxy via the +24h workaround. Real fix wants
the morning twilight ranges populated AND the dark-window
end-of-dark logic to use dataAstroDawn (tomorrow's) instead
of dataPhase4aStart. Defer to next pass.

Note: the existing "phase 1-5" scheme in CalculatePhaseTimes is
internal scaffolding (sunset-anchored offsets, not astronomy);
don't treat it as authoritative twilight data. See #64.

**#57 Shoot-date anchor for Excel astro (NEW Day 17).** Today
Excel computes everything from `Now()` / today's calendar date.
That's wrong for the operator's actual workflow:
- Shoots typically run dusk-to-dawn crossing midnight. The
  "dawn" of the shoot is the NEXT calendar day's sunrise.
  CalculatePhaseTimes uses today's sunrise instead, which is
  morning-already-past â€” useless.
- Operator often prepares the shoot earlier (different date),
  potentially without internet. Today's flow requires running
  Get Sunset Time on the day of the shoot.

Fix: add `dataShootDate` named range (defaults to today, operator
can edit). All astro reads/computes anchor on that date. API
calls (when available) cache values per-date. Local astro
(Astro.bas) already takes atTime parameter so works correctly
once given the right date.

This was uncovered during Day-17 push-astro testing: Push Astro
to Cart found MW core never above horizon in tonight's dark
window because dataPhase4aStart was computed from today's
sunrise (this morning), making the For-loop window go
backwards (dusk 18:44 â†’ "dawn" 05:37 same calendar day).

Workaround for early Day-17 testing: in PushAstroToCart, detect
when sunrise < dusk and add 24h locally. Real fix is #57.

**#58 Track-path cubic segments stuck at N=2 by SRAM (NEW Day 17).**
Cart's TRACK_SEGS_MAX is 2 due to RAM pressure on Uno R4. With
N=2 the MW core fit has 20Â° yaw / 2.75Â° pitch worst-case error
near zenith. With N=4 the error drops to ~9Â° yaw / 0.85Â° pitch
(zenith-segment only; other segments <0.5Â°). N=4 doesn't link
because the toolchain reserves an 8 KB heap region that pins
the global ceiling.

Same SRAM ceiling also blocks: the `/debug/trackplan?idx=N`
read-back endpoint (removed); the Track runtime block (1 Hz
plan-runner check, cubic eval, setPosControl) â€” a self-contained
~80 lines in `loop()` that won't link.

Excel side has freeze logic implemented (in FitAndPushTrackPath,
samples with pitch > 80Â° use constant yaw rather than fitting
through nonsense). Push pipeline + cubic storage + /debug/trackeval
all working at N=2.

Path forward (any of):
- Halve lum_resp_buf (4096 â†’ 2048) to free 2 KB. Risk: luminance
  HTTP responses can hit 4.5 KB; truncation may break the
  "histogram":[[ scan. Verify with sample R3 responses first.
- Use slice-by-16 CRC32 (64-byte table) instead of slice-by-8
  (1024-byte table). Saves 960 bytes. Touches CRC code path.
- Shrink other globals (CartLogEntry, GimbalLogEntry buffers).
- Migrate to Giga R1 (#47) which has 1 MB SRAM â€” no contention.

Acceptance at N=2: yaw error projects to ~7 pixels at 14mm in
worst case (yaw error Ã— cos(pitch)). Below visible threshold
for current shoots. Real fix needed before Track runtime block
can be added.

**#59 Track runtime integration in cart plan-runner (NEW Day 17).**
Blocked on #58 (SRAM). When SRAM cleanup lands, add a 1 Hz block
in `loop()` that:
- Computes shoot_time = millis() - track_plan_anchor_ms
- Linear-scans track_plan[0..count-1] for the active interval
  (one where ts_ms <= shoot_time < te_ms)
- If active: picks that interval's object cubic from track_<obj>,
  evaluates at t=(now - tp->t0_ms)/1000, applies offY/offP, calls
  setPosControl with the result
- Mode FULL: yaw = cubic + offY, pitch = cubic + offP
- Mode YAW:  yaw = cubic + offY, pitch = offP (fixed)
- Today setPosControl is called with world-frame yaw direct (Ry=Cy
  shortcut). When #40 BNO lands the conversion becomes
  `cart_yaw = world_yaw - cart_real_heading`.

Code drafted Day 17 but reverted after failing to link. See
git history (or this WORKFRONTS entry) for the block.

---

## Open workfronts — WiFi / RF link

**#22 Port cart firmware from Uno R4 to Giga R1.** ABSORBED
INTO #47 v2 BUILD (Day 15). Uno is not the blocker yet, but
v2's Ethernet+WiFi simultaneous use is the first design that
materially benefits from Giga's headroom, and doing the
migration as part of v2 avoids a separate later migration.
See #47 for details. Current Uno at 50% flash, 68% globals.

**#23 Cart antenna upgrade.** Hardware on hand; mast work
pending. Day-12 added constraint: mast fold mechanism needs
repeatable hard-stop in shoot-up position so BNO085 hard-iron
calibration survives transport/deploy cycles.

**#24 Cart antenna placement.** Mast specs refined Day 12:
350mm useful length from cart deck to IMU mount, plus enough
above the IMU for the antenna. Stiffness: rod-style ≥10mm
fibreglass, or PVC pipe with wall thick enough to not sway
visibly on cart start/stop. Non-metallic throughout.

**#25 Wired backhaul setup.** Lay 60m Cat6 van AP → field AP.
Confirm cable on hand. Field-test deferred until antenna work
above is done.

**#26 WiFi diagnostic instrumentation.** Oscilloscope philosophy
applied to RF link — log RSSI, retry counts, link quality per
fetch. Design ready, not built.

---

## Open workfronts — Excel

**#13 New Plan sheet schema.** Interleaves cart movement/stop
rows with gimbal pan-follow/astro-target/manual-waypoint rows.
Single shared timeline. Push to cart via `/plan/load`.

**#14 Catmull-Rom evaluator (Excel-side).** Excel evaluates the
spline densely, packs cubic coefficients per segment, POSTs to
cart. See GIMBAL_VIZ.md §8.

**#14a Astro endpoint computation.** For each "track sun / moon
/ milky" Plan row, evaluate astro formulas (existing Astro.bas)
at row_start_time and row_end_time. Computed (yaw, pitch) become
spline waypoints alongside manual waypoints.

**#14b Spline waypoint sequence assembly.** Build ordered
waypoint list from: operator-placed manual, computed astro track
endpoints, hold positions (repeated waypoints), phantom
waypoints for explicit transition rows.

**#14c Cubic-coefficient packing.** Each spline segment becomes
a parameter block for cart: `(type, t_start_ms, t_end_ms,
coefficients...)`. Compact binary or JSON for /plan/load POST.

**#15 Gimbal Plan XY chart with velocity bands.** yaw cumulative
(X, −380° to +70° span) × pitch (Y, 0°-90°, dashed at 80°).
Catmull-Rom spline through waypoints. Colour bands per
GIMBAL_VIZ.md §7. Plus execution-feasibility warning when
utilisation exceeds 0.5.

**#15a Audience-frame display for ease durations.** When
operator sets an ease duration, Excel shows audience-frame count
at 60fps × 1320× speedup.

**#46 Gimbal authoring against cart row labels.** GimbalPlan
rows reference CartLog row labels directly (W_start = CartLog
row, W_end = CartLog row), no separate CartPlan sheet. Operator
looks at chart, sees row-number label on the curve, references
in GimbalPlan. Visualisation-driven authoring. Depends on pano
master config (#33 resolved), Astro.bas (#14a).

---

## Open workfronts — Excel exposure / validation

**#37 Post-timelapse import workflow.** Single-pass workflow
that ingests EXIF data, validates against branch, saves CSV.
See EXPOSURE_FALLBACK.md.

**#38 Refit session.** DEFERRED until CCAPI shoots exist (weeks
to months away). Aggregate has zero CCAPI-driven data today;
nothing to refit yet. CSVs are forward-compatible.

**#39 EXPOSURE_FALLBACK.md upkeep.** "Shoots reviewed" log
within the doc, updated after each post-timelapse import.

---

## Open workfronts — calibration

**#18 Straight-line test at slow speed (2-3 m/hr).** Verifies
behaviour at slowest operating speed (production exec is 5 m/hr).

**#19 Acceleration overhead test.** Time a longish 5 m/hr run
from cold start, compare clock to distance ÷ speed. Result
folded into Plan time estimates as a constant overhead.

**#20 Circle test.** DONE Day 15 part 4. Six diameters measured
at servo offsets 5°/10°/15°/20°/25°/30°: 18.0/10.0/7.5/5.6/4.8/4.2 m.
Table in PROJECT_STATE Day-15 part 4. Bicycle-model fit declined
(40% climb in Ackermann constant = R×δ across the range; pure
bicycle with linear linkage doesn't fit; radius-only data has
L/k ambiguity anyway). Table used directly as operator lookup.

**#21 S-bend test.** Per #20 trigger condition ("only if straight
+ circle don't match bicycle model"): #20 showed mismatch, so #21
is technically triggered. But — per principle #15 + measurement
tolerances on SCX6 (long-travel suspension, tyre scrub, ±0.5m
honest), refining the physical model further isn't earning its
keep right now. Park unless a specific shoot needs sub-meter trace
accuracy. If revisited: also measure wheelbase static and one
front-wheel angle, to break the L/k ambiguity.

**#29 Refine servo-to-wheel calibration.** PARTIALLY DONE Day-15
part 4. The six-row turning-diameter table is the calibration. Full
"servo-to-wheel angle" decomposition not derivable from radius data
alone (needs independent measurement); not pursued. The table is
sufficient for visualisation/smoothing structure and for #29a
operator advice. Whether it's sufficient for COMMITTING executed
Plans depends on shoot tolerances — revisit if a shoot demands
sub-meter trace fidelity.

**#29a Operator-facing turn advice.** MOVED to cart-UI section
below (#10b notes/hints panel). Data table from Day-15 part 4
becomes one of the hints in that panel.

**#30 Cart log buffer size.** Day-9 Test 3 hit CART_LOG_MAX=64
during a long recon. Need a bigger buffer or streaming. Options:
SD card, streaming to Excel, or Giga migration (#22).

**#31 Plan nudge endpoint + UI.** Design ready, not built.
Operator nudges a running plan: adjust timing, skip a row, etc.

**#32 't' event integration into BicycleModel.bas.** Day-9
firmware addition lands a `t` (steering ramp) event in CartLog;
BicycleModel.bas needs to integrate it properly.

---

## Open workfronts — gimbal Plan additions

**#33 Panorama row type — Plan and Execution.** Day-9 evening
design + bench build. Pano firmware finalised. Master config
resolved. Master config defines pano cell yaws/pitches; per-row
choose which cells fire.

**#34 Gimbal settle time measurement.** Pano design assumes 1s
settle between cells; measure actual settle for confidence.

**#35 Operator "PANO NOW" trigger during execute.** Unplanned
pano injection from cart UI during plan execution. Design only.

---

## Open workfronts — heading + gimbal stream

**#40 BNO085 integration.** See the consolidated #40 BNO085 section below (single source of
truth) and the "Cart firmware" #40 entry above.
Architecture resolved Day 13; hardware+read proven and enabled Day 25;
3b gated only on the plan-stream change.

**#41 iPhone compass heading anchors at waypoints.** Storage in
plan: new column on Sequence sheet, `Compass Heading (°N true)`,
blank = no anchor. Workflow modes: pre-planned (operator scouts,
reads iPhone, types values) and in-field (operator captures at
each waypoint during recon). Complementary to #40 BNO anchors —
operator-in-the-loop absolute reference vs IMU-driven.

**#42 Gimbal CAN command stream update rate sizing.** Cart
streams pose updates to gimbal via CAN. Sizing study: how often
is fast enough for smooth motion? Defer until first prototype
running.

**#49 Laptop-side background alarm watcher (RETIRED Day 35 - built + delivered).**
DELIVERED: standalone hyperlapse_watcher.py polls /exec/feed every 5s,
ack-to-silence always-on-top Tk pop-up + one log line per event,
single-instance pidfile lock. 8 conditions: heading window, link-down
(watcher-side, the whole point), cbatt low, paused, plan ended, cart
batt < threshold, cam=nok / can=err, photos stalled. Threshold is the
cart-served "battlow" (Excel dataCartBattLow -> /settings/battlow, v186)
so watcher + cart agree. Watcher.bas Start/Stop; StartWatcherAuto fires
from GimbalPrep.PushToCart (Prep Cart) with a single-instance guard;
Stop confirmed on the Windows build. The remaining live-test of the
non-link conditions (cam/can/plan-end/photos-stalled/heading) is left to
normal field use - the mechanism is in and the link-down alarm is
confirmed live. NOT pursued further unless a condition misfires.

ORIGINAL NOTE:
The Exec-page audio
alarm (camera batt low, comms lost, plan end/fault) only sounds
while the Exec tab is OPEN, FOREGROUND, and the device AWAKE -
the beep is the page's JS poll loop + Web Audio, which the browser
suspends when the tab is backgrounded or the screen locks (noted
in the #36/Exec alarm work). For an unattended overnight rig that
is exactly when it is needed and absent. Workfront: a background
process on the operator laptop (Excel/VBA on a timer, or a small
Python service) that polls the cart's /exec/feed (or /status) on a
fixed cadence INDEPENDENT of any browser tab, edge-detects the
alarm conditions itself, and raises an OS-level alert (sound +
notification) that does not depend on a focused page. Must keep
working when the cart link drops (the alarm IS the link-loss) -
so a missed poll / connection refused is itself an alert state,
not silence. Scope notes: poll target + fields (cbatt, comms,
plan state); cadence; which conditions alert; dedup/re-alert
cadence; how it coexists with the W5500 vs WiFi transport (the
UI/Excel link rides WiFi either way). Independent of firmware -
this is a laptop-side watcher consuming endpoints the cart
already serves.

DETECT LIST (agreed Day 35, source of truth = the 5 edge-triggered
UI beeps in the Exec page xRender, ~line 9841). MIRROR these 5 so
the watcher fully replaces the browser beep:
  1. Heading window open - any earth-frame GP row in its red/alert
     window (operator must set a compass heading). UI: 880Hz double.
     Feed: f.rows[].alert && f.rows[].earth.
  2. Connection lost - feed stale > 10s. UI: 300Hz triple. Feed:
     xAge() > 10. NOTE the watcher gets this FOR FREE and stronger:
     its own poll failing (refused/timeout) IS this alarm, and it
     fires even when the browser tab could not (the whole point).
  3. Camera batt low - f.cbatt == 'low'. UI: 1200Hz triple.
  4. Pause reached - plan frozen at a pause. f.paused. UI: 600Hz single.
  5. Plan ended - f.state == 'DONE'. UI: descending double.
PLUS 3 NEW (not in the UI beep set, agreed to add):
  6. Cart batt low - f.batt < threshold (UI shows it, never beeped).
  7. Plan fault - fault/error flag.
  8. Photos stalled - frame count not rising while RUNNING.
All 8 read from /exec/feed. Edge-triggered (alert on false->true) with
a re-alert cadence so a persistent condition re-nags (the UI's
once-only edge is a known weakness; the watcher should periodically
re-sound while still true). Still to design: poll cadence, stale
threshold, re-alert interval, host (Python service vs Excel timer),
alert surface (sound + OS notification + log).

BUILD SPEC (LOCKED Day 35):
- HOST: standalone Python process, Windows. Independent of Excel so it
  survives an Excel hang (the watchdog must outlive the thing it
  watches). winsound for the alarm tone, Tkinter always-on-top window
  for the ack pop-up (both ship with Python - no installs).
- POLL: GET http://192.168.20.97/exec/feed every 5s. >15s with no good
  reply (3 missed polls) = LINK-DOWN alarm. The poll FAILING is itself
  the link-down detector - works precisely when the cart is
  unreachable, which the browser beep cannot.
- FEED FIELD MAP (read from execFeedJSON, ~line 5405; exact keys):
    1 heading window : rows[].st=='now'/alert AND row is earth-frame
                       (mirror UI hdgOpen = rows.some(alert && earth))
    2 link down      : poll fail / no reply >15s (watcher-side)
    3 camera batt low: cbatt == "low"
    4 pause reached  : paused == true
    5 plan ended     : state == "DONE"
    6 cart batt low  : batt < THRESHOLD volts (batt = Tic Vin; set the
                       low-volt threshold from the pack - TBD value)
    7a camera link   : cam == "nok" (CCAPI lost/degraded: PROBING/table).
    7b gimbal CAN     : can == "err" (CAN tx errors = gimbal comms lost).
                       (Two DISTINCT alarms, not one generic "fault", so the
                        pop-up names which hardware - camera vs gimbal.)
    8 photos stalled : photos not rising while state == "RUNNING"
                       (watch photos across polls; flat for >1 interval)
  Other useful keys present: state (IDLE/LOADED/RUNNING/DONE), cur, n,
  pano (0 idle..6 done), health (green/orange). rssi is in the feed but
  NOT used (operator rule: signal is off-limits as a factor).
- ARMING: poll always runs. Conditions 4/5/7/8 (plan-related) arm only
  when state==RUNNING; 2/3/6 (reachability + power) arm whenever the
  cart should be up; 1 (heading) when a plan is LOADED/RUNNING.
- ALERT: on a false->true edge, sound loops + an always-on-top pop-up
  shows until the operator clicks ACK. Ack silences THAT condition; it
  stays silent until the condition clears and re-occurs (clean edge
  re-arm, replaces a timed re-nag). Multiple conditions = stacked/
  queued pop-ups. One LOG LINE per event (timestamp, condition, value)
  appended to a file.
- CONTROL (start two ways, single-instance lock so they never double):
    AUTO  - the Excel START button's existing push chain also Shells
            "pythonw watcher.py"; plan-stop / E-STOP stops it.
    MANUAL- a Start Watcher / Stop Watcher button pair in HyperLapse.xlsm
            (run early during idle/recon to catch link/batt pre-shoot).
    LOCK  - watcher writes a pidfile / named mutex on start; a second
            launch sees it and no-ops, so AUTO is harmless if MANUAL
            already started one.
- TARGET IP: WiFi build 192.168.20.97. On a future W5500 build the
  UI/Excel link still rides WiFi, so the same IP/endpoint holds.
Status Day 35: spec locked, NOT yet built. Open value: cart-batt low
threshold (#6), and cart-batt low threshold (#6). Fault split FINAL: 7a cam=="nok" (camera link), 7b can=="err" (gimbal CAN) - both alarm, named distinctly. cbatt=="low" alarms directly (no critical tier).

**#47 WiFi runtime reconnect + cold-start cost (RETIRED Day 35 - built + verified).**
DELIVERED + on-rig verified: cold-start tuned (v174; worst ~14.7s vs
~21.5s), free WiFi.status() drop-detect, and a runtime reconnect that
re-begins only in dead-time slots (plan fire-boundary, pano return-slew,
idle), scan-gated so a down AP costs only a ~410ms scan (no ~15s begins
block). Verified reconnect under idle, live pano, and live GC track -
D7 carries the outage, gate bails free, link + CCAPI recover. The bound
:80 socket re-serves after reconnect (UI-return slow case proved
client-side, #uihealth). Diagnostic trace stripped (v187). ACCEPTED
residual: a rare cold boot still burns all 5 join attempts (module
coin-flip) and that window fails - not chased further; the cart simply
retries and the field net has been reliable. NOT pursued unless it bites.

ORIGINAL NOTE:
Two parts, one
session of bench tracing (Day 35, spare Giga, sketch
WiFi_BeginTiming_Giga_Bench.ino, module fw 1.94.0, AP RosedaleVan
-71..-74 dBm).

MEASURED FACTS (cold-boot bench, repeated):
- `WiFi.status()` costs ~0.1 us (cached read), down AND up. So the
  reconnect detector / link poll is FREE - poll it anywhere, no
  budget, no window gating. Closes the only open cost question.
- `WiFi.setTimeout()` is NOT honoured: with setTimeout(2000) the
  failing begin still blocked ~7.9-9.4s. Dead lever (matches the
  PREFERENCES note on connect-timeout).
- The FIRST `WiFi.begin` after power-on is a NON-DETERMINISTIC
  coin-flip: ~1 in 4 connects first try, the rest block ~9.4s then
  return CONN_FAILED. Independent of settle (0 or 3s), prime
  (disconnect / end), timeout, or pre-scan - none changed it. AP is
  VISIBLE in scanNetworks on the failing attempts (-71 dBm), so it
  is ASSOCIATION, not discovery. Intrinsic to the module/fw.
- Attempt 2 from status_before=CONN_FAILED connects RELIABLY in
  ~3.5s, every run.
- The 3s boot settle (#wifisettle) buys nothing and may worsen it
  (the 3s-settle runs blocked longer). Removable.

CONCLUSION - do NOT fight attempt 1; design to expect it to fail
and reach attempt 2 fast. Two cheap firmware wins (boot join):
  1. DROP the 3s settle (no benefit).
  2. BAIL re-begin the instant status==WL_CONNECT_FAILED instead of
     sitting the poll cap (~5s saved, measured 21.5s -> 16.4s ->
     14.7s stable). The ~9.4s failed-begin block itself is the
     module's, not ours - unavoidable.
Result envelope: best ~5.7s (attempt 1 hits), worst ~14.7s
(attempt 1 misses, attempt 2 carries) vs old ~21.5s.

RUNTIME RECONNECT design (from the detect/retry table, Day 35):
- Detect "maybe down" is FREE off the existing CCAPI/meter fail on
  the WiFi build (CCAPI rides the AP). On the W5500 build CCAPI is
  on the cable and blind to the AP, so there the detector is a
  WiFi.status() poll (free) on a 60s cadence - the UI/Excel link
  still rides WiFi even in a W5500 build ("CCAPI to camera only").
- Confirm + retry: WiFi.status() to disambiguate AP-vs-camera, then
  re-begin in an allowed-block window (60s cycle task slot for a
  plan, pano return slew for a pano). Retry MUST tolerate attempt 1
  failing - a reconnect may take two begins (first throwaway,
  second carries), same as boot.
- comms_mode PROBING is NOT reused as the universal flag (it can't
  see an AP drop on the W5500 build); kept out of this design.

IMPLEMENTED + ON-RIG VERIFIED (Day 35, v174-v179):
- BOOT (v174): 3s settle dropped, join poll BAILS on WL_CONNECT_FAILED.
  Three cold boots ~14.4-14.7s (attempt-1 miss path), best ~5.7s, vs
  old ~21.5s. The ~9.4-12s attempt-1 block is module-intrinsic and
  one-time at boot - accepted (unfixable + cheap). Boot does NOT gate
  on scan (begin connects even when scan says NOT visible).
- DETECT (v175): free WiFi.status() poll, identical WiFi/W5500 rule.
  The CCAPI hint is IGNORED for WiFi-reconnect (status is free, so no
  need to piggyback); CCAPI-camera-reachability stays CCAPI's own job.
- RECONNECT placement (v179): wifiReconnectTick() is called ONLY from
  dead-time slots so the begins never delay a frame: the PLAN
  fire-boundary (beside batt-poll/TABLE-probe/LUM), the PANO return
  slew (beside the LUM walk), and the main loop ONLY when fully idle
  (shutter_mode 0 + pano IDLE/DONE). Internal phase/fire gates removed
  - the caller guarantees the slot; kept the 15s rate-limit.
- RECONNECT body: NO disconnect()/end() (measured v176c: after
  disconnect() the scan goes blind; not disconnecting keeps the
  NetworkInterface + bound :80 socket so httpThreadFn's accept() loop
  resumes serving on its own). SCAN-GATED (v178): scan first, run the
  blocking begins ONLY if RosedaleVan is VISIBLE - so a down AP costs
  only the ~410ms scan per 15s window, never the ~15s begins block.
  Up to WIFI_RC_BEGINS=4 begins in-window (each CONN_FAILED-bail +
  300ms gap) to mirror boot's attempt1-fail -> attempt2-connect.
- ON-RIG result: AP down -> scan NOT visible -> no begins, just cheap
  scans. AP back -> scan VISIBLE same window -> begins run, connects,
  IP restored. The begins window measured ~15.5s (LOOP-LONG) but lands
  in idle/dead time so harmless. UI re-serve after reconnect: bound
  :80 socket survived (accept loop resumed) - the v175 BENCH-CHECK is
  thus effectively confirmed in the reconnect path.
OPEN: fast-cadence plans (interval < the begins block) have no gap big
enough; reconnect there waits for an idle/boundary slot. Not hit in
practice (astro is long-interval). Boot all-fail-fast path (rare slow
boot) still un-hardened. Per-begin + scan trace lines left in for now.

**#47a Reconnect test under a LIVE plan and a LIVE pano (CLOSED Day 35).**
VERIFIED on-rig: reconnect now tested under idle, a live pano (3-cycle
shoot, D7 carried), AND a live GC Track-yaw plan (v185 run). In every
case D7 carried the outage at clean 2s cadence, the gate bailed free
while down, and the link + CCAPI recovered (probe -> LIVE). The ~15s
reconnect begins block lands in dead time (harmless). Remaining costs
are the #50 items (18s first-hit, recovery 503 flag-lag), not reconnect
itself.

ORIGINAL NOTE (FUTURE):
The Day-35 on-rig reconnect verification was done with the cart IDLE
(no plan, no pano) - the begins blocked ~15.5s in dead time, harmless.
NOT yet tested is reconnect firing from its in-plan / in-pano slots:
(1) start a real timelapse plan, drop the AP mid-run, confirm reconnect
runs at the PLAN fire-boundary, pin-7 keeps firing (one frame may nudge
~the begins-duration but none dropped), and the link restores; (2) run
a looping arch PanoCycle, drop the AP, confirm reconnect runs in the
PANO return slew without disturbing the cells or the cable unwind.
Watch: the ~15s begins block landing at a boundary vs the actual
inter-frame gap - if the plan interval is shorter than the block, the
fire IS delayed (expected, accepted for long-interval astro; the
fast-cadence OPEN item above). Capture LOOP-LONG + the photo cadence
around the reconnect window to quantify the real nudge.

**#50 CCAPI connect 30s loop-block + reachability gate (CLOSED/RETIRED Day 35, v181-v183).**
[PROBLEM] On a WiFi/camera outage a CCAPI fire blocked ~30s on the
main loop (serial: connect=30117ms FAILED nsapi=-3004,
max_loop_us=30420618), freezing the loop, breaking cadence (a gap
hit 65s), and keeping D7 firing far longer than it should. D7 stops
the instant comms_mode returns NORMAL and a CCAPI fire succeeds -
no latch, re-evaluated every frame (firePhoto).

[MEASURED - CCAPI_Connect_Timing_Bench.ino, on rig]
- Camera ALIVE: connect ~1-400ms, fine.
- Camera DEAD: sock.connect() blocks ~25-30s then nsapi=-3004.
- set_timeout(2000) does NOT bound connect (measured ~30s anyway).
- set_blocking(false) + own millis() deadline ALSO does not bound it
  (~30s) - mbed connect() is fully synchronous at the lwIP level on
  this Murata stack. So connect CANNOT be made fast-fail from the
  socket side, by either lever.
- PING-GATE (method 2): WiFi.ping(camera, 255, 1000) FIRST - dead
  camera fails the ping in ~999ms (rtt=-1); only call the blocking
  connect if the ping succeeds. Camera back: ping 108ms -> connect
  1ms. PROVEN: the 30s block is never entered when the camera is dead.

[DESIGN - ping-gate at the chokepoint, settled, NOT yet coded]
- Gate ONE place: inside ccapiRequestRawSocket (before sock.connect),
  so ALL CCAPI callers are protected by one guard - sweep confirmed
  firePhoto, meterAndAdjustLive, and the exposure PUTs ALL share the
  blind-connect risk, not just firePhoto. #36d already IS the
  cheap-check pattern but only runs in TABLE mode on 60s.
- COST MANAGEMENT (do NOT ping every fire all night):
  * Healthy CCAPI -> NO pings. A successful CCAPI fire proves the
    camera reachable for free; the next fire needs no ping.
  * First failure after a drop pays the 30s once (flag flips to
    unreachable). The gate prevents the 2nd..Nth each costing 30s.
  * While unreachable -> ping on the slow recover cadence (the
    existing 60s), D7 carrying the shoot meanwhile. Ping success ->
    NORMAL, stop pinging. = the existing #36d ping-only-when-degraded.
- PING MUST NOT DELAY D7: fire D7 FIRST (~0.2s), then ping in the
  leftover cadence slack (~1.8s of a 2s interval) - the fire-boundary
  slot already used by batt poll + TABLE probe. Works because
  ping(1s) < post-fire slack; astro cadences >=2s always have room.
  (A cadence < ~1.2s would not fit - not used in practice.)
- CAMERA-IDLE CONSTRAINT: the camera responds poorly while TAKING the
  photo or SAVING to card. The ping must land in the camera-IDLE
  window (after save completes, before the next fire), NOT mid-
  exposure / mid-save - the same rule the existing fire-boundary
  CCAPI traffic already follows. So the ping goes in the LATE part of
  the post-fire slack, not immediately after the trigger.

[ALSO] D7 currently stops on the first CCAPI HTTP-200 after recovery,
not on camera-confirmed-ready (200 = camera reached + endpoint
accepted, NOT photo-confirmed). Deeper cause of "D7 ran too long" is
the 30s loop-freeze above, not the latch; fixing the block fixes the
symptom. Whether D7 should LATCH until the camera is confirmed
properly back (not just first 200) is a separate decision.

IMPLEMENTED (v181-v183, on-rig verified):
- v181 put a per-fire ping in ccapiRequestRawSocket. v182 fixed the
  ping to the 3-arg WiFi.ping(ip,255,1000) form (the 1-arg form
  returned -1 in 0ms when WiFi was down - no real timeout). v183 then
  REMOVED the per-fire ping entirely: it DUPLICATED the existing #36d
  recovery probe, which already pings on an economical cadence
  (every-3rd-photo in PROBING, then 1s/60s in TABLE) and was taxing
  every degraded fire ~1.2s on the loop.
- FINAL design (v183): the gate at ccapiRequestRawSocket just READS
  camera_reachable (free) and bails instantly if false - no ping in the
  hot path. The #36d probe is the SINGLE ping source and sets
  camera_reachable=true on success; connect-fail/non-200 sets it false;
  a 200 sets it true. While down, every fire = free flag read + D7.
- ON-RIG RESULT: D7 carried a full outage at clean 2s cadence (~232ms
  loops), gate bailed free once flagged down (no repeat 30s blocks),
  recovery clean (probe -> LIVE -> CCAPI resumes).
OPEN (minor, both observed, neither breaks anything):
- FIRST-HIT 18s: the first connect after a drop still blocks ~18s
  because camera_reachable is true going in (nothing knew yet). The
  gate stops the 2nd..Nth; only the first pays. To kill even the first,
  the flag would need to start pessimistic or key off WiFi.status().
- RECOVERY 503 flag-lag: on probe success the comms flip to NORMAL can
  beat the camera_reachable=true update by one frame, so the liveview
  restart hit "503 gate: camera unreachable (flag)" once, self-corrected
  next frame. One-frame ordering gap between probe-says-up and flag-up.
RETIRED Day 35: the gate is implemented and on-rig verified across idle,
pano, and live track. The two residuals are ACCEPTED, not blockers:
- first connect after a drop pays ~18s ONCE (flag true going in); gate
  stops every one after. Live with it unless it bites in the field.
- recovery 503 flag-lag self-corrects the next frame.
Not done, folded into general hygiene: a sweep for other blocking
chokepoints (CAN/SD/Tic) - none observed blocking in any soak run, so
not pursued unless one surfaces.

**#uihealth UI slow to return after reconnect (CLOSED Day 35 - client-side).**
After a WiFi reconnect the UI sometimes came back slowly (iPhone worse
than laptop). Suspected the cart's :80 server socket not resuming
accept(). v185 added an accept-error trace (err code + count, rate-
limited). RESULT: the socket throws a few -3004 accept errors only at
BOOT and self-recovers in ~0.5s ("accept recovered after 4 errors"); at
the mid-run reconnect there were ZERO accept errors and the UI returned
quickly. So the cart socket re-serves fine - NO re-bind needed. The
earlier slow return was CLIENT-SIDE (the iPhone holding a stale TCP
connection longer than the laptop). The v185 trace can stay (cheap,
boot-only) or be removed later. Conclusion: cart is not at fault.

---

## #40 BNO085 — heading correction (CONSOLIDATED, single source)

**Status (UPDATED Day 30): BNO is STUBBED (`STUB_BNO`, since Day 28); heading source is the iPhone
compass, NOT the BNO.** Day 27 measured the BNO cold-boot heading as NOT trustworthy (raw yaw not
magnetometer-locked across a true cold boot; `cal 0` every cold boot), so Day 28 stubbed it and moved
to operator iPhone-compass entry (`/compass` -> `C` row, bound per WP). The heading frame was then
UNIFIED to clockwise-POSITIVE on Day 30 (N 0 / E +90 / S 180 / W -90; see HEADING_CONVENTION.md), so
the old `(−true_yaw)` negation below is SUPERSEDED - cart and gimbal now share the CW-positive frame
and the 3b correction needs NO sign flip. 3b (earth-frame correction) remains the genuinely-new build
(see "Phase 4 / 3b heading" in the gimbal-coordination open item). The historical BNO read/cal detail
below is retained for reference only; it is not the live heading path.

### 1. What #40 is

Fold a real-world heading correction into the earth-frame gimbal cubics
so gimbal aim is accurate against the world, while the cart drives blind
on an approximate path. The correction (CW-positive frame, post-Day-30 unify):

`gimbal_yaw_correction = real_heading − expected_cart_heading`  (+ Adelaide declination + mount offset)

applied to earth-frame-tagged gimbal cubics only. Pan-follow and cart path untouched (cart drives
blind). `real_heading` is the operator iPhone compass on approach (BNO stubbed); `expected_cart_heading`
is the recon-compass floor pushed per WP. NO sign flip (cart + gimbal both CW-positive since Day 30).
~~OLD (pre-Day-30, CW-negative, BNO-based): `gimbal_yaw_correction = (−true_yaw) − expected_cart_heading`;
BNO yaw negated because BNO CW = negative. Superseded by the unify + BNO stub.~~
- `expected_cart_heading` comes from the recon iPhone compass (`C` rows -> Plan col H), carried per WP.
  NOT computed on the Giga. The build does not depend on the bicycle model being accurate — only on the
  heading read being accurate at the anchor.

### 2. Read model (confirmed)

- **Anticipatory + stationary "duck off", not the old 500/400 mm crawl.**
  The plan tells the cart, with lead time, when an earth-frame gimbal
  move that benefits from a fresh correction is coming. So: park, settle,
  take a generous averaged window (1–2 s of 10 Hz polled samples).
- **Validity condition:** chassis heading at read-time must equal heading
  at gimbal-move-time — read at the same parked waypoint the gimbal move
  happens from. Plan structure must guarantee the gimbal move occurs
  while the cart is parked at that known waypoint.
- **Frequency:** ~3 anchors over a 12 h night — one before each
  earth-frame gimbal move needing accurate real-world aim, not a
  fixed-distance schedule. IMU otherwise idle (suits the Giga-safe
  polled, no-interrupt sketch).
- **Skip/fallback:** cal-accuracy didn't reach threshold within available
  time → keep previous correction (A_SKIP / keep-previous).

### 3. Calibration — method PROVEN, byte semantics settled

The cart is ~13 kg, high CoG, ~70 × 400 mm footprint. **No figure-8s**
on the assembled cart. Achievable motions: full horizontal yaw; pitch
±45°; roll 30°.

- **Figure-8 NOT required for the math** — varied orientations are what
  mag cal needs; a slow full 360° yaw exposes a full circle of headings.
  BUT the bolted cart in practice CANNOT drive the byte up by itself
  (yaw + limited pitch never moved it off 0 in testing) — a confirmed
  motion-diversity limit, not a field problem.
- **Method proven end-to-end (Day 24):** BNO reaches cal 3 by free-air
  figure-8 *off the fixed mount*, in the cart's field, electronics on.
  `/debug/imu/savecal` → `stored:true` at cal 3, DCD written to flash.
  **DCD persists across power cycles** — after reboot a small off-plane
  wiggle snaps cal back to 3 instantly (a from-scratch cal would need a
  full figure-8). Production build boots on the stored DCD.
- **Key nuance — the cal-accuracy BYTE ≠ stored calibration.** The byte
  reports *current confidence*, not whether a valid DCD is loaded. On a
  mounted, stationary or flat-moving cart the byte reads 0–1 even though
  the stored DCD is valid and heading is good. So the byte CANNOT be
  read at boot to gate trust.
- **Two-build workflow (the fix for boot-reset):**
  - `#define BNO_CAL_CAPTURE` → cal session build: calibrateAll +
    game-RV + mag on; figure-8 to 3; `/savecal`. DO NOT ship
    (calibrateAll re-arms dynamic cal each boot and resets reported cal).
  - `BNO_CAL_CAPTURE` commented out → production: rotation vector only,
    runs on stored DCD.
  - `endcal` dropped from the workflow (suspected to interfere with the
    save; not needed — production never starts dynamic cal).
- **Design decision (Day 25): saved-DCD is the calibration path.**
  Converge once off-cart, `/savecal`, ship production on stored DCD.
  Live-cart cal behaviour becomes real-world field data later, NOT a
  current blocker and NOT chased on the bench further.
- **Cal threshold rule (from datasheet + practice):** cal ≥2 → use the
  reading (A_OK); cal ≤1 → skip, keep previous correction (A_SKIP). At
  cal 1 the heading is unreliable enough that folding it in risks making
  gimbal aim worse than the bicycle-model estimate alone.

### 4. Motor-power stall — ~~RESOLVED (Day 25)~~ SUPERSEDED — see Day-25 part-2 correction at top
> **NOTE (Day 25 pt 2):** the 2.2k-pull-up fix below was PREMATURE — it did
> not hold; the stall reproduced under motors while building recon-heading.
> Real cause = Tic I²C clock-stretch contention on the shared bus; real fix =
> BNO moved to its own bus Wire2 (D8/D9). The diagnosis below (air-gap proving
> 'not radiated') is still valid; only the 'conducted power noise → pull-ups'
> conclusion is wrong. Kept for the record.


**The Day-24 finding:** the BNO SHTP rotation-vector stream went silent
and did not self-recover (needed a power-cycle) whenever main/motor
power energised; with main off it streamed perfectly. Measured
signature: `last_poll_ms_ago` climbing in lockstep with real time
(6647 → 13812), `yaw_raw` frozen. Ruled out at the time:
enumeration/boot intermittency (stream confirmed live immediately
before) and GIGA-input brownout / USB sag (USB present and it still
died).

**Day-25 diagnosis — measured, single variable at each step:**

1. **Air-gap test (radiated vs conducted).** Built a like-for-like spare
   rig: spare GIGA ~2 cm from main, spare BNO ~2 cm from main BNO at the
   same ~50 cm from motors, cable matched (30 cm, unshielded, untwisted),
   spare on laptop power, cart on battery. Shared air only — power fully
   isolated as the single removed variable. **Result: spare rode through
   motors-energised flat** — `last_read_ms_ago` steady at ~75–78 ms,
   never climbed, no stall, acc 3. **Conclusion: radiated field through
   air is NOT sufficient to stall the BNO. The agent reaches the main
   sensor via a conducted path** (the cart's shared bus or BNO 5V),
   not by radiation. (Caveat retained: the surviving spare also had a
   short clean bus + clean rail, so this rules radiated-EM out as
   *sufficient* but does not by itself finger which conducted path.)
2. **CAN datapoint (supporting asymmetry).** The gimbal CAN run is
   similar length, similar proximity, untwisted, and has never stalled.
   Consistent with protocol fragility: CAN is differential with CRC +
   hardware retransmit (absorbs corruption); the BNO I²C SHTP stream is
   single-ended and stateful (one corrupted sequence-numbered packet
   wedges the whole stream until reset). Three protocols, same
   environment, one victim: Tics survive (stateless/short), CAN survives
   (differential/robust), only the BNO dies. Leans toward conducted
   noise on the BNO's specific shared branch.
3. **Fix applied — Tier 1, single change: pull-ups 4.7k → 2.2k** on the
   BNO SDA/SCL to stiffen the I²C rising edges over the 30 cm run.
   (Local 5V decoupling was the alternative Tier-1 lever; not used — no
   caps on hand.)

**Result — RESOLVED under full production load (Day 25):**
- Bench sketch, motors energised: heartbeat flat (`last_read_ms_ago`
  75–90 ms), no stall.
- **Production build (soak-v18), motors energised AND running, full bus
  load (Tic traffic, /status, soak logging, WiFi):** `/debug/imu` showed
  `last_poll_ms_ago` small (23–107 ms) and `yaw_raw` tracking real
  motion. No stall reproduced.
- The 2.2k swap holding under production load points at the I²C-lines
  path (edge integrity) over the BNO-5V path — consistent but NOT a
  scope-confirmed discrimination. The lines-vs-5V scope split is no
  longer needed for the fix; reserve it only if the stall ever returns.

### 5. Read validation — PROVEN (Day 25)

With motors running, production build:
- **Stream live under load** — `/debug/imu` `last_poll_ms_ago` stayed
  small across repeated pulls; `yaw_raw` changed with cart motion.
- **Heading plumbing proven** — `/debug/imu/capture` set offset
  (−58.35), then a full 360° cart turn: `true_yaw` tracked through the
  full ±180 wrap (−84.7 → −177.8 → +92.2 → +4.2) and returned to within
  ~4° of the 0° origin. Capture → offset → wrap → live-read-under-motion
  all work and repeat.
- **Limit:** cal stayed 0 throughout (no DCD saved this session, no
  figure-8). So this proves the PLUMBING and repeatability, NOT absolute
  heading accuracy. Absolute accuracy vs iPhone/compass waits on a
  saved-DCD unit and is by-design a real-world field check.

### 6. Endpoints (validation surface)

`/debug/imu` returns live JSON: `yaw_raw`, `true_yaw` (after capture),
`offset_set`, `pitch`, `roll`, `cal`, and `last_poll_ms_ago` (the stall
instrument — grows without bound if the SHTP stream stalls).
- `/debug/imu/capture` — set true-north offset (point front edge north
  per iPhone with cal ≥2, then call).
- `/debug/imu/savecal` — write DCD to BNO flash.
- `/debug/imu/endcal` — (dropped from workflow; see §3).

Note: `/status` carries NO live BNO heading — only the cal byte at
idx 14. The `g_yaw/roll/pitch` at idx 0–2 are gimbal attitude from CAN,
not the BNO. Use `/debug/imu` for all BNO read/validation.

3a anchor samples go to `/cartlog` as `A` events (true_yaw×10 in value,
cal in aux tail) — populated ONLY while executing a plan segment that
carries the anchor flag; empty otherwise.

### 7. Step status

- **Step 2 (Phase-A ease-onto-curve):** BUILT + PROVEN (soak-v14).
- **3a (anchor heading-sample instrumentation):** DONE + verified.
  `PlanSegment` carries the `anchor` flag (token `a`, tail position);
  while in an anchor segment the cart samples true_yaw + cal to CartLog
  `A` events every 500 ms, record-only (Ry=Cy holds).
- **Motor-power stall:** RESOLVED (Day 25 pt 2, BNO moved to Wire2/D8-D9 — NOT the 2.2k pull-ups, which did not hold). Was the
  part-B block on 3b — now cleared.
- **3b (fold the correction into earth-frame gimbal cubics):** STILL
  BLOCKED — but the block is now ONLY the plan-stream change.
  Confirmed by grep of soak-v18: `PlanSegment` has 8 fields (type,
  dist_mm, duration_ms, steer_offset, speed_mhr, end_cond, transition,
  anchor) — **no `expected_cart_heading`, no earth-frame/chassis frame
  tag.** 3b cannot be built until the stream carries
  `expected_cart_heading` + per-segment frame tag.

### 8. Enable decision (Day 25)

**BNO is ENABLED.** Hardware survives motors, read is live and
reproducible under production load, calibration method is proven and the
DCD path is chosen. Nothing electrical or cal-related blocks progress.

**3b remains gated on ONE dependency: the plan-stream anchor fields.**

### 9. Next workfront

**Plan-stream change (#72-adjacent): add `expected_cart_heading` +
per-segment earth-vs-chassis frame tag to `PlanSegment` and the s-string
parser/pushers.** Per build-lesson 12, append new tokens at the TAIL of
the positional surface (the `anchor` flag already set this precedent —
order-independent tail token). Once the stream carries
`expected_cart_heading`:

Build 3b — the correction scalar + cubic-eval application
(`gimbal_yaw_correction = (−true_yaw) − expected_cart_heading` on
earth-frame cubics), Excel `bnoOffsetDeg` push, with the A_OK/A_SKIP cal
gate (≥2 use, ≤1 keep-previous) and the stationary-settle averaged read.

Then: Step 4 (pan-follow), leftover previewplan / Move-cubic Stage-4
Excel pushers.

### 10. Open (real-world, not bench)

- Power-up-and-go: does normal field operation ever bring the cal byte
  to 2, or is deliberate motion always needed — and what mounted-cart
  motion achieves it in ~2 min?
- Is cal 1 actually usable? If real-world heading at byte=1 is good
  enough (DCD valid regardless of byte), the byte is safe to ignore —
  retiring the "reject ≤1" rule and making the UI cal field unnecessary.
- Heading vs truth (iPhone/compass) at cal 2 on the assembled cart —
  does the Day-23 ±0.5°/negated-sign finding still hold? Has the offset
  shifted from ~+9°?
- Tics-on / motor-running during cal: energised captures the real field
  (good), but a *running* motor is a *changing* field that may corrupt
  the read (bad). Settle by observation — can the byte reach 2 with
  motor running vs idle?
- UI cal field: stays on Cart Recon UI for now; candidate for removal if
  real-world says cal 1 is OK. `/debug/imu*` endpoints stay regardless.
- LOOP-LONG favicon/empty-request stalls (1.6–2.6 s) still present;
  harmless with camera off, still wants a request-read timeout before a
  live shoot.

---

## Open design decisions

- Sunrise transition table (only sunset table reviewed to date).
- Moon tracking in scope or out of scope for the gimbal Plan?
  ✅ RESOLVED (Day 31): moon IS in scope; obeys goto-rise-and-wait.
- Two reserved per-row inputs in Gimbal UI — TBD.
- Velocity-band thresholds (0.05 / 0.3°/s) — confirm in practice;
  adjustable if first shoots suggest otherwise.
- Stream size for /plan/load — JSON or binary? Uno R4 SRAM tight
  after recent additions; consider chunked POST.
- m_per_step canonical value: 1.77 µm/step or wait for
  circle-test cross-validation before committing?
- Front_steps logging: keep on by default, or only enable for
  calibration runs (small SRAM cost)?

---

## Stage 4 milestone

Reduced to a single item Day 12: **production-envelope soak**
(multi-hour sunset+sunrise) to confirm the 200ms pulse-width fix
holds across a real shoot.

---

## Closed items — one-line stubs

Full detail in `WORKFRONTS_old_ver1.md`.

- **#1 Replace optocoupler** — Day 12 resolved; opto innocent,
  not needed.
- **#2 Buy USB logic analyser** — Day 12 done.
- **#3 Post-opto Tv=0.8"+2s re-test** — Day 12 superseded by
  Tv=0.5"+2s at 100% delivery.
- **#4 rear_steps in CartLogEntry** — Day 8 done (front_steps
  also added for diagnostic).
- **#5 Plan endpoints** — Day 9 done (`/plan/load`,
  `/plan/start`, `/plan/stop`, `/plan/status`).
- **#6 Heading anchor endpoint at runtime** — Day 8 removed
  (Excel pre-bakes).
- **#7 Cart-θ integration during drives** — Day 8 removed.
- **#8 Port astro maths to C** — Day 8 removed.
- **#9 ±450° cumulative yaw** — Day 12 done via Settings
  envelope (`gimbalYawEnvelopeMin` / `gimbalYawEnvelopeMax`,
  default ±225°).
- **#10 setSpeedControl wiring** — Day 8 removed.
- **#11 Bicycle integration: Log → (x, y, θ) trace** — Day 8
  done via `BicycleModel.bas`.
- **#11a Control-sheet handler row for IntegrateBicycle** —
  Day 8 done in-session, note in README.
- **#12 Inverse fitting: trace → smooth Plan** — Day 10
  rejected with #44 cluster.
- **#16 Time-based luminance fetch** — Day 12 deleted (current
  every-Nth cadence + skip-2-on-fail resilience is enough).
- **#17 Straight-line test at 5 m/hr** — Day 8 done.
- **#27 WiFi unresponsiveness under UI polling** — Day 9
  resolved via avoidance.
- **#28 Front step counting on arcs diagnostic** — Day 9
  characterised.
- **#36 / #36a Simple fallback formula (Excel side)** — Day 9
  late evening done.
- **#36b Formula evaluator on cart** — Day 12 done; Excel
  pushes Appendix A via GET query (~1.3 KB inside 1.5 KB
  envelope).
- **#36c Time-based fetch (cart side)** — Day 12 deleted with
  #16.
- **#36d subtask 1 Time anchor on cart** — Day 12 done; cart
  advances sunset+sunrise trel in lockstep from millis base.
- **#36d Step D TABLE → LIVE recovery within a shoot** —
  Day 15 done; 60s ping probe in TABLE, on success → LIVE,
  liveview invalidated for restart, standard luminance walk
  nudges back into deadzone.
- **#36d Step 4 (per-cycle PUTs from TABLE)** — Day 15
  part 2 CLOSED for v1 (logically impossible — CCAPI
  unreachable in TABLE). Re-opens as a v2 build task.
- **#36d v1 TABLE simplification** — Day 15 part 3 done;
  retired `exp_delta_t_rel`, `last_table_tv/iso`,
  `findTableRowForTv()`, `/debug/match` and associated
  Serial logs / JSON fields. v1 sketch −143 lines.
  End-to-end verified 104/104 photos.
- **#20 Circle test** — Day 15 part 4 done; 6-row diameter
  table at 5°/10°/15°/20°/25°/30° servo. Bicycle fit declined
  (model mismatch + radius-only ambiguity). Table used directly
  as operator lookup. See PROJECT_STATE Day-15 part 4.
- **#44 Smooth Selection (Excel)** — Day 10 built end-to-end
  then REJECTED on operator-workflow grounds. Original
  Smooth.bas archived. New principle "Visualisation >
  Manipulation" added to PREFERENCES.
- **#44a Deviation calculation helper** — Day 10 rejected
  with #44.
- **#44b Plan sheet for smoothed segments** — Day 10 resolved
  differently: CartLog *is* the Plan.
- **#44c Chart wobbly trace + smooth overlay** — Day 10
  rejected with #44.
- **"Stage 4 milestone bundle"** — Day 12 reduced to soak only.
- **"Logic-analyser-first vs opto-first ordering"** — Day 12
  resolved (analyser-first was correct).
- **#10a Gimbal UI page** — Day 16 DELIVERED as Gimbal Recon
  screen on unified UI (one URL with ?screen= routing). Spec
  UI_DESIGN_v2.md. GIMBAL_VIZ.md §3 superseded. Production-
  readiness pending #49.
- **#29 Mark Waypoint button** — Day 16 DELIVERED as btn22 on
  Cart Recon screen. Writes new `'W'` event into CartLog with
  recon-session waypoint number as value. Operator-verified
  end-to-end.
