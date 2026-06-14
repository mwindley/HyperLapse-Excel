# HyperLapse Cart - PROJECT_STATE

_Last updated: 14 Jun 2026 (Day 33) - current firmware **soak-v135**._
_The detailed body below is the **Day-31 / soak-v101-v102 checkpoint** and is kept
as the build record. For the freshest state read **SOON_LIST.md** (status review at
top); for open work read **WORKFRONTS.md**. The Day-32 deltas since the v101
headline are summarised immediately below._

## Day-33 deltas (v128 -> v135 + Excel), 14 Jun

Firmware (all flashed + on-rig verified except where noted):
- **v128 idle de-energise fix** - boot no longer exitSafeStart on the Tics
  (which, with auto-energize config, brought coils live before asked and left
  cart_motor_state DEENERGISED so the idle check never fired). Boot leaves Tics
  in safe-start; exitSafeStart+energize only in cartEnergise; cartDeenergise
  also enterSafeStart so de-energise sticks. 2-min idle auto-de-energise verified.
- **v129 auto-energise on motion** - cartSetSpeed energises the Tics if
  de-energised and a non-zero speed is commanded (recon jog / move "just works"
  without a separate ENRG; starts the 2-min idle clock). Zero never energises.
- **v130 cam status** - label cam->Cam; comms 'deg' fix: a successful battery
  poll (free-running every 60s) now recovers comms_mode->NORMAL out-of-plan (the
  PROBING->NORMAL recovery probe only ran inside the shutter cadence, so 'deg'
  stuck outside a plan). Verified "UI reports Cam as OK".
- **v131 phase-aware lum target** - exposure moved cart-side long ago but the
  target was never pushed, so the LIVE walk centred on the boot default 128 not
  the authored 60/40. /exposure/target now takes ss=<sunset> sr=<sunrise>;
  meterAndAdjustLive picks target+mode by isCurrentlySunrise (sunset->ss+BRIGHTEN,
  sunrise->sr+DARKEN), same phase switch as the Tv/ISO table. Excel Formula.bas
  PushFormulaToCart pushes the pair from dataLumTargetSunset/Sunrise.
- **v132 acquire-ease shortest-path** - the entry ease onto a Track/Move interval
  interpolated raw (target-start) yaw with no wrap. Cubic/astro yaw is 0-360
  azimuth while the Ronin pose is +-180, so easing from pose 0/22 onto a sun
  target of 346 drove the LONG way (through SW). Steady-state track already
  wrapped to +-180; the acquire ease now wraps its delta the same way. ON-RIG
  VERIFIED: gimbal slews short way to the sun, no SW swing.
- **v133 exposure walk to target** - the deadzone was one-sided (BRIGHTEN stopped
  at target-10, DARKEN at target+10), settling up to 10 lum short. Now each mode
  walks to the target itself (BRIGHTEN while lum<target, DARKEN while lum>target);
  one-sided per mode so no dither.
- **v134 Tv ceiling in LIVE walk** - the Tv ceiling (tvc) was only honoured in
  TABLE fallback, so LIVE BRIGHTEN slowed Tv to the ladder end (30s) past the
  ceiling. LIVE BRIGHTEN now caps Tv at exp_tv_ceiling_sec and hands off to ISO
  there.
- **v135 ISO ceiling/base in LIVE walk** - same gap for ISO: LIVE walked ISO to
  the ladder ends (1600/100) ignoring isoc/isob. LIVE BRIGHTEN now caps ISO at
  exp_iso_ceiling, DARKEN floors at exp_iso_base. With v134 the LIVE walk now
  respects all the same Tv/ISO bounds as TABLE (TABLE = time-curve fallback when
  CCAPI is down; LIVE = metered walk).

Excel (AstroPush.bas, Formula.bas):
- **Cubics fit over the GP's plan window, not a fixed astronomical window** -
  ROOT CAUSE of "sun track didn't point at sun". PushTrackPathsToCart fit the sun
  cubic over sunset->sunrise (night), so for a midday GP the cart evaluated the
  cubic ~5h before its window start and CLAMPED to the sunset endpoint (~298deg).
  New PlanTrackWindows() scans the plan's Track GPs and returns each object's
  window [fire-pad, next-fire+pad]; each cubic is fit over its GP window (so the
  evaluated time is always inside by construction). Objects the plan doesn't
  track are skipped (no stale cubic). ON-RIG VERIFIED: sun cubic seg0 ts ~= -299
  brackets the GP fire; gimbal points at the live sun.
- **Coverage gate (Prep Cart)** - after the fits, any object the plan TRACKS
  whose cubic failed to fit/push aborts the push with a clear "do NOT arm"
  message - caught on the bench, not the cart. It already caught a real case:
  the moon, forced to 8 segments over a 120-min GP window, starved each segment
  below the 6-sample minimum.
- **Window-aware segment count** - FitAndPushTrackPath caps nSegs so each segment
  keeps >=6 samples at the 5-min step (moon auto 8->4 over a short window). The
  fixed 8 was sized for the old 30h moon window.

On-rig end-of-session state: cart at north, eh=0; full chain verified on a
sun->moon bench plan - sun pointing correct (short-way acquire), cart MOVE 200mm
then STOP halts at ~7s (velFactor 0), exposure LIVE walk settles at the authored
target with Tv/ISO bounds honoured. STILL OPEN: moon GP in this test plan is
mostly below horizon (timing, not a bug); cable-strip swing/fire-order cue
(not requested); night-palette red tuning.

## Day-32 deltas (v103 -> v114), since the v101 headline

Firmware (all flashed + on-rig verified except where noted):
- **v103 heading baseline** - trackPlanTick subtracts the plan's expected cart
  heading (col-H / `eh` token) as the earth-frame baseline; cart aims from the
  plan with no operator action, `hdg` is now just the optional drift trim.
- **v104 Move earth-frame** - astro Move sends real-world azimuth + eh; re-aims
  on a plan heading change or a live bump.
- **v107-v109** acquire safety floor, stop-releases-gimbal, track entry ease
  (yaw+pitch).
- **v110 START fires shutter** - Exec START runs exposure-init + shutter-start
  after track/plan start (one field press arms gimbal + plan + photos); E-STOP
  and every stop path halt the shutter.
- **v111 universal slew-rate floor** - setPosControl floors time_for_action to
  swing/20 deg/s on every motion path (anti-whip backstop).
- **v112 Exec UI row rework (R6)** - earth-frame GP shows hdg button AND eta;
  eta direction explicit (+elapsed / countdown / done).
- **v113 END stops shutter** content-independent (astro -> track END; cart-only
  -> cart DONE).
- **v114 Clear clears track** - no stale GP row after Clear.

Excel / Python:
- GC tracking pipeline rebuilt (UTC/local fix, live-ephemeris dial), GC zenith
  band ease (alt>70).
- **Moon zenith-band ease** added (AstroPush + planview) - moon transits >70 deg
  ~1 week/month here.
- **R4 chart speed/object colours** (GimbalPlanViz_v3): swings by Pan Speed,
  tracks by object.
- Dateless fire-time class root-fixed (Utils.DatedFireSerial; Python robust).
- **PushFormulaToCart folded into PushToCart** - the 3 Excel buttons now cover
  everything (incl. the exposure ramp); 2 UI buttons (START/E-STOP) run it.

Still open (see SOON_LIST): R7 moon step-5 (below-horizon goto-rise-and-wait
firmware), R10 cable-strip index-alignment, F1 cart-motor-stop (future).

---

_(Historical Day-31 / v101-v102 checkpoint follows.)_

## Headline this session (Day 31 / v101)

The multi-day HTTP loop-stall that threatened photo cadence is **structurally solved** (v59):
HTTP runs entirely on its own RTOS thread, off the photo loop - smoother eases, immediate
track-start. Built on that: **Step 3 concurrency safety** (v60-v66) - track config is
lock-protected, plan is safe by enforcement, and pano now runs DURING a track as an OVERLAY,
proven on hardware 06 Jun: the timelapse yields BOTH the gimbal (v64) and the photo cadence (v65)
for the pano sweep, then eases back onto the live sun cubic and re-anchors the cadence to catch up
(frame-based ease - see item 1). v63's earlier "forbid pano during track" guard was the opposite
of the design and is gone. The pano overlay is complete. Per-request serial spam gated off (v62).
The photo path (pin-D7) never takes a lock.

**This session also closed out the CCAPI fire path (v69-v77).** The pano/cadence now fire via a single
`firePhoto()` entry (CCAPI when comms NORMAL, else pin-D7). Building it surfaced a hard wedge: outbound
CCAPI used the Arduino mbed `WiFiClient`, whose `available()` BLOCKS INDEFINITELY on a connected-but-silent
socket (proven by a trace ladder, v72-v75: lock fine, connect r=1, send fine, first `available()`=0, then
the SECOND `available()` never returns - the software timeout can't fire because control never returns to
it). Fixed by rewriting outbound CCAPI onto a raw mbed `TCPSocket` with `set_timeout()` (v76) - the same
remedy already used inbound (v55-v59). Then trimmed the ~900ms recv tail by parsing Content-Length and
exiting as soon as the body is complete (v77). Sustained 2s soak now runs clean: 10/10 CCAPI fires,
`REQ-PHASES total` ~110-340ms, cadence dead-on 2000ms, no wedge. CCAPI confirmed healthy independently
via the Step5b reference harness + laptop curl throughout.

**Then proved the third transport - W5500 wired CCAPI (v78-v86).** Built the wired variant
(`STUB_WIRED_ETHERNET` undefined -> EthernetClient over the .20.x subnet, camera 192.168.20.99, GIGA
W5500 .20.98; WiFi stays on 192.168.1.97 for UI/Excel - only the camera transport changes). It fired,
but ~1 in 3 `shutterbutton` presses returned a bare `400 Bad Request` (Content-Length:0). Trace ladder
(v80-v84) ruled out timing (misses fell on clean 3000ms gaps) and ruled out a misread (dumped the raw
reply: the camera genuinely sent `HTTP/1.1 400`, empty body = the malformed-request signature). Root
cause: the old wired send used a dozen piecemeal `client.print()` calls, and the W5500 split the request
line across TCP segments, which strict Giga CCAPI intermittently rejected. Fix (v85 #wire-onebuf):
assemble the whole request into ONE buffer and `client.write()` it in a single call - the same shape as
the proven WiFi raw-socket send. Result: 9/9 `st=200` @3s, zero 400s, frames-on-card matched. **All
three fire transports now confirmed: pin-7 Y, WiFi CCAPI Y, W5500 wired CCAPI Y.** A bad lesson logged
mid-session: a per-fire pin-fallback counter was added then reverted (v82->v83) - pin-7 redundancy
engagement already belongs to the #36d comms state machine; don't rebuild what exists.

## Exposure cycle redesign - busy window dissolved (v87 -> v94)

**Measured the camera "busy window" properly, then redesigned the live cadence around it.** The live
path used to fire, THEN fetch luminance + PUT Tv/ISO immediately after (fetch_delay_ms=0) - so the
control CCAPI landed inside the post-fire busy window and got 503'd ("During shooting or recording",
Canon ref 4.8.1), which then triggered the Tv/ISO PUT retry storm (5x, 3s backoff) - a cadence-killer.

**The measurement (v87-v89, /debug/busywindow, since removed).** A self-valued Tv PUT probe after one
shot, polled until non-503. Key findings, all on hardware:
- **Gating is by call class, not uniform.** A GET (settings read) is NEVER gated - returns 200 mid-shot.
  Only WRITE/control (Tv/ISO PUT, and the next fire) get 503'd. So a GET probe measured nothing; the PUT
  probe measured the real window.
- **Busy window = exposure + ~1s settle.** Tv=0.5s -> 1.14s (3 runs, 1140-1152ms); Tv=20s -> 21.19s.
  Long-Exposure NR off confirmed (no dark-frame doubling, would've been ~40s).
- **The ~1s is NOT card write.** The R3 sustains 30fps to a fast 2TB CFexpress, so a single RAW writes
  in <100ms. The settle is CCAPI control-acceptance, not storage.
- Excel FallbackFormula schedule: tightest Tv/ISO change spacing anywhere in dusk/dawn is **60s** - one
  change per minute at most. Metering every ~20s is 3x oversampling to catch it promptly.

**The redesign (v90, Step 1): REVERSE the cycle to meter -> PUT -> fire.** New helper
`meterAndAdjustLive()` runs at the TOP of a metering cycle, BEFORE `firePhoto()`, when the camera is idle
(a full interval since the last shot). All control CCAPI happens up-front on an idle camera; nothing talks
to the camera after the fire, so the busy window is never hit. Removed the old post-fire fetch-service
block + lum_fetch_pending arming (fetch_delay_ms/lum_fetch_pending now dead in the live path). Anchor
stays on the scheduled beat (now not refreshed post-meter) so the meter delay does not accumulate - the
fire just lands ~meter-duration after its beat on metering cycles. This mirrors the existing soakCycle
ordering and is also MORE correct: the frame is shot with freshly-adjusted settings, not a frame late.

**Verified on hardware, both transports, both ends of the Tv range:**
- 0.5s / 2s and 20s / 22s, on W5500 wired (v93) AND WiFi (v94): meter->PUT->fire order, **zero 503s**,
  gap dead-on, fetch N/N/0.
- Cap off: `mean=162-252` steady, walk correctly `in_deadzone` - **RAW-only liveview histogram reads
  true** (earlier `mean=0` was the dark/capped bench, not a format artifact). This closes the last open
  caveat: luminance from the liveview histogram is independent of capture format (CCAPI ref 5.2, 6.2.16),
  so dropping dual RAW+JPEG capture was correct AND shortens the per-shot write.
- At Tv=20s the busy window (21.19s) sits ~0.8s inside the 22s interval, and the top-of-cycle meter still
  comes back clean - so **Step 1 alone dissolves the busy window across the whole range; no gate needed.**

**Step 2 (event/polling addedcontents write-gate) was TRIED and REVERTED (v91/v92 -> v93).** The idea: gate
the next cycle on the camera's own "file written" signal (addedcontents, ref 6.2.27). It failed: the FIRST
event/polling GET returns full camera state (~8KB, >1s) and consumes the addedcontents delta, so a cold
blocking poll never catches it; the rapid retries then tipped comms into PROBING->TABLE. (Also a 400 from a
stray `?timeout=immediately` query first.) Step 1 already proved sufficient, so the gate was removed. If
near-night ever needs it, the proper fix is a PERSISTENT BACKGROUND poller that continuously drains
event/polling and latches the last addedcontents - not a blocking wait. Not currently needed.

**Cleanup (v94).** Removed the /debug/busywindow scaffolding (served its purpose). Fixed a latent bug it
had introduced: the busywindow else-if had swallowed the /debug/can else-if header, leaving /debug/can dead
and busywindow's HTTP response overwritten by the can status - now restored. Re-enabled the WiFi build
(`#define STUB_WIRED_ETHERNET`, camera 192.168.1.99); both transports send identically (single write).

**Accepted, not a bug:** shot #1 fires via pin-7 fallback (CCAPI lock held during liveview startup) and may
not land a frame - losing the first frame is fine, every frame after is 100%. Seen consistently across runs.

## Gimbal recon cart-heading + mojibake fix (v95 -> v97)

**Gimbal-recon "Show astro" now aims correctly for any cart orientation (v95).** Previously
`/gimbal/showastro` drove to the raw earth-frame astro yaw with no heading applied, so it only aimed right
if the cart sat at true north. Now a new `/gimbal/carthead?deg=X` (set; `?clear=1` unset) stores
`recon_cart_heading` (true-north deg), and showastro computes `cmd_yaw = normalize_pm180(astro_azimuth -
cart_heading)` - the same geometric counter-rotation the live track uses via `track_yaw_correction`. New
Gimbal-UI button "Compass -> cart heading" prompts the iPhone compass (typed - iOS blocks the browser
compass read over plain HTTP, matching the existing recon/exec heading buttons), a status line shows the
current heading, and Show astro warns if it is unset (then falls back to raw / cart-at-north).
**HARDWARE VERIFIED 07 Jun:** with astro pushed (mask=115: sun rise/set + MW rise/mid/end; moon not pushed),
Show astro drove correctly to all five at heading 0 and at heading 90 - the `azimuth - heading` SIGN IS
CONFIRMED correct (no flip needed). All recon moves are eased at 2.0s (`timeForAction` 0x14, 0.1s units);
Snap var is read-only (no move). Astro is RAM-only - re-push via Excel `btnInitShoot` every boot.

**Mojibake fix (v96/v97).** The euro symbol in the Track warning was a UTF-8 em-dash (`E2 80 94`) decoded as
Windows-1252 because the served HTML declared no charset. Fixed: all served strings (`client.print*` +
`response`) are now pure ASCII (em-dash -> hyphen; raw Greek delta -> JS `\u0394` escape), and a
`<meta charset='utf-8'>` was added as defence-in-depth. Comments still contain non-ASCII (harmless - never
served). v96 first failed to compile (bare double-quotes in the build-marker text broke the string literal);
fixed in v97, no code change. NOTE: a separate Excel-side VBA degree-symbol mojibake remains in the "Astro
pushed to cart" dialog (display-only; see Open/pending #9).

## Near-zenith MW yaw + exposure gate (v98 -> v101)

The MW "mid" keyframe sits at pitch ~84 deg (near zenith), where yaw is geometrically near-meaningless
and the astro cubic demands a huge fast yaw swing. Previous-Claude advice (23 May) was a yaw rate limit
that ramps/catches-up with no snap; it had been DISCUSSED but never built (only a comment at ~line 1137).
Built this session as a chain:

**v98/v99 - near-zenith yaw limit.** Declared the cap and wired a clamp into `trackPlanTick` (cubic
YAW/FULL path only; Move/PanFollow return earlier and are untouched; pitch untouched). No engage/release -
always on, so a snap is impossible by construction; the gimbal lags the zenith swing then catches up.

**v100 - unit fix to PER FRAME.** Key realisation: the gimbal tracked CONTINUOUSLY at 5 Hz, so the
frame-to-frame yaw IS the 60fps on-screen jump. deg/s was the wrong unit (2 deg/s over a 22s interval =
~44 deg/frame whip). Switched to `MAX_TRACK_YAW_DEG_PER_FRAME` (2.0), converted to a per-tick step via the
live interval. Normal MW ~0.6-0.78 deg/frame passes free; only the zenith whip is clipped.

**v101 - EXPOSURE GATE.** `trackPlanTick` now HOLDS the gimbal still while the shutter is open
(`in_exposure = now - shutter_last_fire_ms < tvStringToSeconds(current_tv)*1000`) and moves only in the
gap; the time-based cubic catches up the drift in the gap. So NO gimbal motion blurs any frame -> sharp
stars, and the per-frame cap can never affect sharpness (every frame is shot stationary) - it only makes
the zenith catch-up pan a bit faster on screen (smooth). The cap now spreads the per-frame budget across
the GAP (interval - exposure), not the whole interval. Fast Tv (sun/day) exposure ~= 0 so it never gates
-> continuous tracking unchanged. `tvStringToSeconds` forward-declared for use in trackPlanTick.

**Astro-rule basis (web-checked).** 14mm full-frame: 500 rule = 35.7s, 300 rule (strict/high-MP) = 21.4s.
Tv=20s drifts the sky ~0.084 deg < ~0.089 deg (300-rule threshold) -> SHARP held, so during-exposure
tracking is NOT required at 20s (the gate's hold is fine). Ronin limits: 0.1 deg step, ~0.1s min move;
sidereal 0.0042 deg/s -> one 0.1 deg step = ~24s of sky ~= one step per 22s frame (natural match). Tv=60s
exceeds both rules (must track during exposure) AND the 0.1 deg resolution makes that marginal (~500-rule
quality) plus alt-az field rotation near zenith no tracking corrects - so operator stays Tv=20s/ISO1600
(sweet spot; more frames = longer MW run in the 60fps edit).

STATUS: built + bench-logic-verified; live confirmation is Open/pending #10 (incl. the daytime
Track-Sun-at-silly-Tv=20s 60-min soak stand-in). Tune the per-frame cap on the real MW pass.

## Earlier-built foundations now in firmware (v35 -> v44, Day 29-30)

These landed before the v51+ HTTP/CCAPI/exposure work above and are cumulative in the current
build. They were recorded only in the Day-29/30 session summaries until now; captured here so NOW
reflects them.

**WP-event-anchored gimbal coordination - Phases 1-3 BUILT + HARDWARE-PROVEN (v35 -> v37, Day 30).**
The design gap (Day 29): cart and gimbal ran on two independent clocks, so a gimbal point (GP) fired
off `/track/start` time, not off the cart actually reaching its waypoint (WP). Fixed: each GP now
fires on the cart's ACTUAL WP arrival.
- v35: `TrackInterval` gains `anchor_wp` + `offset_ms`; trackplan parser reads `awp`/`offms` tail
  tokens (TrackPlanPush appends them; col P Offset is MINUTES x 60000); absent -> 0 -> fall back to
  pushed `ts/te` (pure astro/time plans byte-for-byte unchanged).
- v36: `planSegmentEnter` stamps `wp_arrival_ms[idx+1]` (the actual arrival = that WP's Commence);
  WP number = segment idx + 1; `planReset` zeroes the array. Record-only.
- v37: `trackPlanTick` selects the active interval from LIVE absolute-millis windows via
  `trackIntervalOpenAbs(i)` (WP-anchored -> `wp_arrival_ms[awp] + offset_ms`, pending if that WP not
  reached; non-WP -> legacy track-start-relative made absolute). `/track/start` vs `/plan/start`
  order no longer matters; `/track/start` stays arm+anchor (astro now_s fallback only). SUPERSEDES
  the parked "re-stamp the anchor at /plan/start" idea (no separate gimbal clock to re-stamp).
- PROVEN: coordinated run - gimbal sat still (WPs pending), GP01 fired on `[wp] arrival WP1`, etc.,
  NOT on the track clock. Nudge-divergence test: mid-WP1 `/plan/nudge?d=2000`; WP3/WP4 arrived
  hundreds of seconds late and `[track] interval -> N` landed on each late arrival, not the stale
  planned time. Acceptance proof: GPs track the actual WP through slip/nudge.

**Execution UI - BUILT on the cart (v38 -> v44, Day 30).** Spectator model (UI_DESIGN_Execution_v3.md):
operator is a spectator; the UI is reassurance + two narrow interventions (heading refine, cart-safety
nudge). Served at `/?screen=exec` (day palette; night palette deferred - see WORKFRONTS D).
- v38 `/exec/feed` (JSON polled @3s: plan state, live gimbal yaw/pitch, time-ordered WP/GP rows with
  planned-time ETA, ribbon fields, ymin, pano phase/pidx); v39 honest GP feed state ('idle' when track
  unarmed, never a guessed 'done'); v40 idle auto-de-energise (energised+vel0+outside-plan, 2 min,
  reset on energise/Start); v41 ribbon fields; v42 Exec screen served; v43 chart receiver
  (`/settings/chartsvg` chunked+URL-decoded SVG, JS positions the live camera icon from yaw/pitch/ymin);
  v44 PANO button + feed pano fields.
- Chart contract (Excel authors, Giga moves the icon; LOCKED - do not change on a whim): viewBox
  `0 0 355 90`; `x=(yaw-yaw_min)/450*355`; `y=90-(pitch-20)/60*90` (pitch 20 bottom..80 top); dashed
  80deg limit line; 450deg yaw span. Authored by `ChartPush.bas` (PushChartToCart). PROVEN on phone.
- PANO was already-built firmware (state machine, offsets {-78,-26,26,78}); v44 added the Exec button
  + feed phase. PROVEN: swept -77.8/-25.9/+26.2/+78.2, shutter each, resumed to trigger pose.
- (Later increments are in Open/pending #4 Stop/Clear v68, #5 health dot v67, #6 live yaw.)

**Heading convention UNIFIED to clockwise-POSITIVE (Day 30).** The cart was running two frames: the
Ronin gimbal yaw is CW-POSITIVE (right=+, confirmed bench GP02 dyaw -30 panned LEFT, and DJI docs),
while the cart bicycle/recon frame was CW-NEGATIVE (east=-90, measured Day 27). Unified on the
Ronin/standard/phone frame: **N 0 / E +90 / S 180 / W -90.** Implementation = a BicycleModel.bas
boundary flip (proven Day-8 integration core untouched/internally CW-negative; only the seed read and
the heading OUTPUT negated). Gimbal Delta yaw (Plan col X) already authored in the Ronin frame -> no
change; future earth-frame correction now needs NO sign flip (cart + gimbal agree).
**`HEADING_CONVENTION.md` is the single source of truth for the frame.** Migration footgun: any
CartLog recorded with the OLD east=-90 entry integrates WRONG now - only re-integrate logs entered
with the new east=+90 convention. (BNO is stubbed since Day 28 - see WORKFRONTS #40.)

## What changed (v51 -> v63)

- **v51** - Introduced one recursive, priority-inheriting mutex `g_can_mtx` and wrapped the
  whole multi-chunk `sendFrame()` (the single CAN-TX chokepoint) so gimbal frames from two
  threads can never interleave. Photo path (pin-D7) never takes this lock.
- **v54** - Verified that lock is real. The GIGA "mutexes do nothing" report is real but
  conditional: `rtos::Mutex` compiles to empty stubs unless `MBED_CONF_RTOS_PRESENT` is
  defined, which requires `Arduino.h`/`mbed_config.h` *before* `mbed.h`. Added explicit
  `Arduino.h` ahead of `mbed.h` plus a compile-time `#error` guard so the lock can never
  silently degrade to a no-op.
- **v52/v53 (abandoned)** - Tried to run the Arduino `WiFiServer` on a worker thread. Dead end:
  its non-blocking `accept()` never yields a client from a non-main thread, and a `WiFiClient`
  can't be handed across threads (no-op copy ctor drops the socket; each client owns a reader
  thread and does the blocking close in its destructor).
- **v55-v57** - Pivoted to a raw mbed `TCPSocket` server with a **blocking** `accept()` on the
  worker (the standard mbed pattern). Found + fixed a double-free hardfault (red LED): an
  `accept()`-returned socket is `_factory_allocated` and **self-deletes inside `close()`**, so
  the extra `delete` freed it twice. Fix: call `close()` only.
- **v58 (Step A)** - Ran the real `handleHttpRequest` on the worker via a `RawClient` adapter
  (`Socket*` -> `arduino::Client`; worker pre-reads the request into a buffer, handler reads
  from it, writes go to `send()`, `stop()` closes). Signature `WiFiClient&` -> `Client&` accepts
  both. Kept port 80 in-loop as a safety net. Verified the full UI + endpoints served off-loop.
- **v59 (Step B)** - Migrated **port 80** onto the worker; retired the in-loop `WiFiServer`
  (`begin()` removed, loop WiFi block removed). HTTP fully off the photo loop.

## Proof (v59 hardware logs)

- Dead/speculative sockets close in ~600-1300ms **on the worker** with **zero `LOOP-LONG`**.
  Real requests close in ~10ms. Previously the same dead-socket close appeared as
  `LOOP-LONG ... http=915ms` stalling the loop.
- Full track cycle (`START` -> `ease 5000ms` -> `acquire done -> tracking` -> `STOP`) ran with
  the browser hammering port 80 throughout - no loop stalls, ease ran its full 5s uninterrupted.
- CAN TX from the worker's handler and from `trackPlanTick` serialized through the real
  `g_can_mtx`. No crashes.

## Locking model (current)

- ONE recursive, prio-inherit mutex `g_can_mtx` serializes ALL CAN TX at `sendFrame()`.
- The photo path (pin-D7) never takes any lock - structurally immune.
- HTTP worker thread: below-normal priority; blocking `accept()` on a raw `TCPSocket` (port 80);
  the slow close lives here, off-loop.

## Open / pending

1. **Step 3 - plan/track/pano concurrency safety - ALL DONE + hardware-proven. Track+plan proven earlier; pano overlay A+B (v64/v65, compile-fixed v66) PROVEN ON HARDWARE 06 Jun.**
   Photo path (pin-D7) never takes a lock; gimbal-only path uses the recursive `g_can_mtx`.
   NOTE: a prior summary called v64 "proven" before it even compiled - that was WRONG. The real
   hardware proof is the 06 Jun v66 run (evidence in the 3/3 line below).
   - **(1/3) track config - DONE (v60).** `trackPlanTick` + `/settings/trackplan` + `/settings/trackpath`
     share the recursive `g_can_mtx`; mid-run cubic push proven tear-free and smooth.
   - **(2/3) plan_segments - DONE (v61), by enforcement.** `/plan/load` rejects while `RUNNING`;
     `/plan/stop` = stop+clear. No concurrent writer, no lock on the photo path. Proven.
   - **(3/3) pano overlay - A+B DONE (v64/v65), compile-fixed (v66), PROVEN ON HARDWARE 06 Jun.**
     v63's "forbid pano during track" guards were the OPPOSITE of the design and have been REMOVED.
     The design is an OVERLAY (yield/resume), measured against the Day-30 summary + operator
     confirmation 06 Jun. HARDWARE PROOF (v66, 06 Jun, no camera/pin-7): ran `/shutter/start?ms=5000`
     then `/gimbal/pano`. Pre-pano cadence PIN8 #1-#7 all gap=5000ms. During the ~26s pano: ZERO
     PIN8 cadence lines (only the pano's own 4 shots) - cadence yielded cleanly, no double-master.
     First post-pano shot PIN8 #8 gap=5000ms (one clean interval, NOT ~26000ms and no burst) -
     proves the cadence pause AND the re-anchor. Both halves confirmed.
   - **CORRECT pano design = OVERLAY (yield/resume).** The unit is the *timelapse* = gimbal track
     moves + track photos on cadence. When a pano is triggered mid-timelapse: (1) the ENTIRE
     timelapse yields - gimbal track moves stop AND the track photo cadence stops; (2) pano runs
     its 4 moves + 4 photos centred on the current sun-pointing yaw; (3) on pano done the timelapse
     RESUMES by catching up - the track timeline kept running, so the gimbal EASES from the
     pano-end (trigger) pose to where the sun is NOW, and the photo cadence resumes. Pano is the
     temporary owner of both gimbal and shutter.
   - **Increment A - DONE (v64):** `trackPlanTick` yields the gimbal while `pano_phase` is active
     (latch `track_paused_by_pano`); on pano completion it forces a re-acquire (`track_active_idx=-1`)
     so the interval-entry path eases from the pano-end pose onto the LIVE cubic - the catch-up,
     reusing the interval's `&acquire=` ease. Yield is lock-free; photo path (pin-D7) untouched.
   - **Increment B - CODED (v65):** in the loop, just before the mode-2/mode-3 cadence blocks,
     while `pano_phase` is active BOTH cadence anchors (`backup_last_ms`, `shutter_last_fire_ms`)
     are slid forward to `now` every tick. That (a) suppresses cadence firing (now-anchor=0<interval)
     and (b) auto re-anchors so the first post-pano shot is a full interval after pano-end (clean
     resume, no burst, per `/shutter/resume`). Purely additive; fire logic + 200ms D7 pulse
     untouched. PROVEN ON HARDWARE 06 Jun (see the 3/3 line for the run + evidence).
   - **SETTLED - the recovery ease is FRAME-BASED; do NOT re-litigate.** A past session floated a
     "max yaw rate" catch-up. The system's native unit for "how gentle" is *audience frames at
     60fps*, not seconds and not deg/s. The Excel workbook defines ease bands in frames
     (Just-perceptible=3, **Comfortable=10**, Cinematic=more) and pushes `acquire_ms = frames x
     cadence_sec` (e.g. Comfortable 10f @ 22s cadence -> acquire_ms=220000; @ 2s -> 20000; cadence
     unavailable -> 0 = snap). So the firmware `acquire=` value already encodes the operator's
     chosen frame band. v64 reuses that same `acquire=` for the pano catch-up, which is correct by
     construction: the catch-up spans the chosen number of rendered frames regardless of the
     angular gap. Rationale: what the viewer sees is N frames of slightly-faster pan then normal;
     frames are the right unit for a 60fps timelapse. Do not invent a seconds- or rate-based
     recovery.
2. **Serial logging.** 209 handler `Serial.print` sites collide with the loop's prints (two
   threads, one UART) -> garbled logs during debug. Cosmetic; handler logging is debug-gated so
   normal logs stay clean. Proper fix later = async log ring buffer drained by the loop.
3. **Daylight Sun Track run** - confirm #40 1b earth-frame heading correction under real tracking.
4. **Exec UI: Stop / Clear control - DONE + hardware-proven (v68).** Tidy 3-way split:
   **Stop** (E-STOP) halts motion; **Clear** (`/plan/clear`, new) empties the plan to IDLE/loadable
   and does NOT halt motion or touch motor energise (energise = Cart Recon + 2-min auto-de-energise);
   **Load** (Excel push) is elsewhere and rejects while RUNNING. `/plan/clear` = `planReset()`,
   refuses while RUNNING ("use Stop first"). New Exec "Clear plan (ready next)" button (confirm).
   HARDWARE PROOF 06 Jun: clear from LOADED -> `IDLE,n=0,cur=0` (+ serial `[Plan] CLEAR -> empty/IDLE`);
   clear while RUNNING (60s STOP-hold plan) -> "ERROR: plan running - use Stop first", plan kept
   running. Both halves confirmed.
5. **Exec UI: GIGA health dot - DONE (v67).** `/exec/feed` now emits a worst-of `health` field
   (green|orange) = heap creep vs boot baseline (>30KB) OR loop overrun (worst loop since last
   poll >300ms; the 200ms photo pulse stays under it) OR CAN tx err. RSSI excluded per design.
   `cam` is now a real flag (ok=COMMS NORMAL, deg=PROBING/table) instead of `"?"`. The Exec ribbon
   shows one coloured dot: green/orange from `health`, RED client-side when poll age >=8s (stale).
   Firmware reports only green/orange; RED is the UI's call, exactly as specced.
6. **Exec UI: live numeric yaw - DONE (already present).** The Exec plan-state line shows
   `yaw X deg pitch Y deg` while RUNNING, and the chart's live camera icon is driven by
   `yaw/pitch/ymin` from the feed. Only gap: it's not shown numerically while idle/loaded
   (a one-line tweak if always-on is wanted).
7. **CCAPI fire path for pano + cadence - DONE + hardware-proven (v69-v77).** Single `firePhoto()`
   entry (def ~4453, fwd-decl ~3945): pano + cadence modes 2/3 call it instead of `backupShutter()`
   directly. Fires CCAPI `shutterbutton` when `comms_mode==NORMAL`, else/on-fail pin-D7. Manual
   `/shutter` + `/shutter/pin8` stay pin-only. **v71** added `g_ccapi_mtx` so only ONE outbound CCAPI
   request runs at a time (loop + worker); `firePhoto` takes it with a NON-BLOCKING `trylock()` so the
   sacred photo path never waits (pin-7 if the lock is held). **v76** = the real fix: outbound CCAPI
   rewritten onto a raw mbed `TCPSocket` with `set_timeout()` (connect 2s, recv 800ms/recv + ~4s wall
   cap) so `recv()` returns `WOULD_BLOCK` on a stall instead of blocking forever - the Arduino
   `WiFiClient.available()` blocked indefinitely on a connected-but-silent socket (root cause proven by
   the v72-v75 trace ladder; the in-loop software timeout could never fire). Wired `EthernetClient`
   path unchanged (`#else`). **v77** trims the ~900ms close-wait tail: parse `Content-Length`, stop the
   recv the instant the body is complete. HARDWARE PROOF 06 Jun: `/exposure/init` returns (was hanging);
   sustained 2s cadence soak (fetch off, fixed camera-set Tv) fired 10/10 CCAPI `st=200` with frames on
   card, `REQ-PHASES total` ~110-340ms, `gap=2000ms` every shot, no `connect=0ms`, no wedge. Known
   benign quirks: (a) cold-start fire #1 falls to pin because `/start` arms liveview and briefly holds
   the lock as the first fire lands - self-recovers next shot; (b) `shutterbutton` 200 = press accepted,
   not frame written - a press issued while the camera is still writing (e.g. a straggler at `/stop`,
   or very tight spacing) returns 200 but no frame. At 2s/0.5s spacing this doesn't occur. NOTE: there
   is still NO general raw-URL Tv/ISO setter in firmware (soak hardwires Tv 0"5/0"4; `/exposure/*` drives
   the auto-walk; operator sets Tv/ISO on the body or via laptop CCAPI directly).
   **WIRED TRANSPORT PROVEN (v78-v86):** the W5500 build (compile-time, `STUB_WIRED_ETHERNET` undefined,
   camera .20.99 / GIGA W5500 .20.98, WiFi UI unchanged on .1.97) was tested + fixed this session - the
   intermittent bare `400 Bad Request` was the W5500 splitting the request line across TCP segments; the
   wired send is now a single-buffer `client.write()` (v85 #wire-onebuf), 9/9 `st=200` @3s. All three
   fire transports confirmed solid: pin-7 Y, WiFi CCAPI Y, W5500 wired CCAPI Y. Production still ships ONE
   compile-time build; both transports now send identically.
8. **FUTURE - Document startup + execution procedures (operator runbook).** Capture the field
   sequence end-to-end so a session can be run without re-deriving it. Must cover at least:
   - **Per-boot state that does NOT persist** (RAM-only, lost on reboot/reflash): astro yaw/pitch
     pairs + `astro_valid_mask` (re-push via Excel `btnInitShoot` -> `/settings/astropos`);
     real-time anchor (`/settings/realtime?ms=` - cart has no RTC); exposure init
     (`/exposure/init` -> current_tv/iso + interval); recon cart heading (`/gimbal/carthead`).
     Symptom of forgetting astro push: Show astro returns "slot not pushed". Verify loaded state
     with no-arg GET `/settings/astropos`.
   - **Startup order:** power on -> WiFi join (192.168.1.97) -> Excel `btnInitShoot` (astro+location
     computed in Excel, positions pushed) -> realtime anchor -> exposure init.
   - **Gimbal recon flow:** set cart heading from iPhone compass (`/gimbal/carthead`, Gimbal UI
     "Compass -> cart heading") so Show astro aims true-azimuth from the cart's real orientation;
     capture PF/Lock/Move/astro/Track rows; bake via Next (`/gimballog/push`).
   - **Execution flow:** plan load/start/stop; the Exec UI; heading update at earth-frame GPs
     (`/track/heading`); the meter->PUT->fire cadence (v90+); shot #1 pin-7 fallback is expected.
   - **Build/transport note:** production ships ONE compile-time build (`STUB_WIRED_ETHERNET`
     defined = WiFi camera .1.99; undefined = W5500 wired .20.99).
   Deliverable: a runbook doc (likely alongside PROJECT_STATE / a STARTUP.md). Not yet written.

9. **Excel (HyperLapse.xlsm) astro fixes.** Updated 07 Jun (Day 31):
   - **Moon astro now PUSHED - DONE (Day 31), firmware piece remains.** Supersedes the old "moon not
     pushed" note. `PushAstroToCart` (AstroPush.bas) now sends mnry/mnrp/mnsy/mnsp and sets the mask
     bits; AstroTable carries Moon Az/Alt/above-horizon (Astro.bas `GenerateGCTable`, cols G/H/I);
     renderer reads moon defensively. Hardware-confirmed 07 Jun on the spare GIGA: cart returned
     `"mask":127` (all 7 slots; moon bits 2/3 now on, was 115), echoed moon_rise/moon_set. Decision:
     moon IS in scope; moon obeys no-shoot-under-horizon -> goto-rise-and-wait (same as sun/GC).
     REMAINING (not Excel): **firmware moon below-horizon goto-rise-and-wait** (park at rise bearing +
     hold, no underground tracking) - the only un-built moon item; and verify Show astro actually
     SWINGS the gimbal on Moonrise/Moonset (untested - main GIGA out for repackaging, no gimbal).
     Open: tonight's moonset resolved to a MIDDAY 12:21/az264 (outside the 4pm-8am window;
     FetchMoonTimesForNight clamped to sunrise+0.5 and accepted it as bookend) - confirm desired vs
     "none in window". See WORKFRONTS.md item B; full build log archived in the Day-31 workfront record.
   - **VBA degree-symbol mojibake - PARTIALLY cleared (Day 31).** The two swapped modules (Astro.bas,
     AstroPush.bas) were ASCII-normalised on import, clearing the mojibake there (degree glyphs in
     those untouched dialogs became spaces). The literal `deg`-symbol garble may remain in other
     dialogs not touched this session. Fix any remaining with `ChrW(176)` not a pasted literal.
     Display-only; pushed data is clean (URL sends plain numbers; cart stored exact values).

10. **FUTURE - Field-test the MW gimbal chain (heading + per-frame yaw cap + exposure gate).**
    The v95->v101 chain is built but only the recon cart-heading sign is hardware-verified; the
    yaw cap and exposure gate are bench-logic-verified only. Need a live confirmation that:
    - the gimbal HOLDS still through each exposure and steps only in the gap (frames sharp);
    - the per-frame yaw cap (2 deg/frame, spread across the gap) glides the zenith swing with no
      snap - watch for `[track] yaw rate-limited / released` around the MW-mid (pitch ~84) pass;
    - the catch-up reads as a brief smooth fast-pan in the 60fps edit, not a whip.
    **Executable daytime stand-in (no night needed):** run a **Track Sun with a deliberately silly
    Tv=20s** (massively overexposed - image content irrelevant) so the exposure gate engages exactly
    as it will for MW, and let it **soak ~60 min**. This exercises hold-during-exposure, gap-stepping,
    the per-frame cap, and the meter->PUT->fire cadence under a real 22s interval, in daylight, on the
    bench. Confirms gating + cadence + tracking interplay without waiting for a clear MW night.
    Tune MAX_TRACK_YAW_DEG_PER_FRAME on the real MW pass if the catch-up pan feels too fast/slow.

11. **Gimbal Plan visualisation - TWO deliverables.**

    **(A) DONE - native-Excel VALIDATION chart.** Module `GimbalPlanViz_v3.bas` (import into
    HyperLapse.xlsm; run `GimbalPlanViz_v3.BuildGimbalPlanViz`). Working + verified on the operator's
    real workbook 07 Jun. What it does: walks the Plan MIDDLE Gimbal-Plan section (anchored by finding
    "Step" header, data row below it) to an absolute trajectory - Move rows accumulate (prev + dyaw),
    rows with a numeric Ry/Rp use it as an absolute anchor (Ry + dyaw); writes a `GimbalViz` helper
    sheet with LIVE formulas; builds an XY chart (cumulative yaw X x pitch Y), flags fast-yaw steps red
    (|step yaw| > tunable B4, default 90 deg), dashed pitch-limit line at 80, summary block A8:B11 (max
    |cum yaw|, cable headroom vs +/-450, max pitch, fast count) with red conditional flags. Plan-sheet
    columns: Step=M, Action=S, Ry=V, Rp=W, dyaw=X, dpitch=Y (offsets +0/+6/+9/+10/+11/+12 from Step);
    header row 5, data from row 6 in the uploaded copy (code auto-detects). 
    BUG-HISTORY LESSON (do not repeat): a long 1004 hunt was caused by `ColLetter(n)` taking `n` ByRef
    and decrementing it to 0 inside the function - which zeroed `stepCol` after the scan. FIX = `ByVal n`.
    A self-tracing build (Debug.Print per scanned cell) is what finally exposed it: TRACE, don't theorise.
    PENDING refinement on (A): astro-TYPED plan rows carrying only Target+keyframe (no absolute Ry/Rp)
    are not yet placed - needs an AstroTable (target,KF) lookup (see data sources in (B)); for now put
    the recon'd absolute into Ry/Rp. Also optional: fast-yaw in deg/sec (jump / Move-t) when Move-t
    populated; a warning cell back on the Plan row; wire to a Control-sheet button.

    **(B) TO BUILD (operator wants this; START A NEW CHAT) - PhotoPills-style RADIAL plan-view in
    Python -> SVG/PNG.** This is the AUTHORING/visualisation picture, distinct from (A). Operator looked
    at (A) and confirmed the real want is a plan-view sky/compass map like PhotoPills, NOT the yaw x
    pitch chart. Decided Python (not native Excel) because Excel has no true polar chart and can't
    composite radial lines over a site image cleanly; Python (matplotlib polar + optional Pillow) does.
    Accepted tradeoff: it produces a STATIC image regenerated on demand, not a live-updating chart.
    REFERENCE IMAGE: operator's PhotoPills screenshot /mnt/user-data/uploads/1780796294935_image.png
    (Cape Jervis). That layout = satellite plan-view; red pin = location (=cart); thick/thin coloured
    radial lines = sun rise (thin yellow)/set (thick yellow), moon rise (thin blue)/set (thick blue);
    white DOTTED ARC = GC/Milky-Way path across the night with one dot per time-step; concentric range
    rings; bottom strip = time-of-day elevation graph (sun yellow, moon blue, twilight bands). Header
    showed "Visibility GC From 6:43pm az120.3 elev7.7 To 5:47am az257.6 elev36.1" = the GC rise->set
    sweep.
    DATA SOURCES (all already in HyperLapse.xlsm - read with openpyxl READ-ONLY, never save/round-trip
    the macro workbook):
      - Sheet `AstroTable`: time-indexed ephemeris, columns = Time (fractional day), GC Az, GC Alt,
        Sun Az, Sun Alt, "GC above horizon" (yes/no). Rows step ~15 min through the night. GC reaches
        ~84 alt near az ~10-340 around local midnight (the zenith pass = top/centre of the arc). THIS
        is the GC dotted-arc + sun-arc source.
      - Pushed astro slot values (the radial endpoints; also re-derivable from AstroTable rise/set):
        sun_rise az62.57 alt-0.86, sun_set az297.52 alt-0.81, mw_rise az116.50 alt12.97,
        mw_mid az2.12 alt84.08, mw_end az253.53 alt29.60. (moon not currently pushed - workfront #9.)
      - `recon_cart_heading` (true-north deg) if a cart-oriented view is wanted; else keep true-north
        up. Astro values are EARTH-FRAME true azimuth (0=N), so the map is natively true-north.
      - Optional overlay: the assembled Plan gimbal aim points (Plan MIDDLE section) as pins/labels on
        the map, to show where the plan points vs where the bodies are.
    PROJECTION MATH: az 0=N at top, clockwise (screen angle theta = 90 - az in standard math convention,
    or just plot with matplotlib `set_theta_zero_location('N')` + `set_theta_direction(-1)`). Radius
    from ALTITUDE for a sky-dome view: r = 90 - alt (horizon at outer rim, zenith at centre) - so the GC
    zenith pass lands near centre, rise/set near the rim, matching the eye. Sun/moon rise+set drawn as
    rays from centre to the rim at their horizon azimuth. Decide with operator: (i) true-north-up vs
    cart-heading-up; (ii) sky-dome (alt->radius) vs PhotoPills flat-map (ground range->radius); (iii)
    real site image behind (Pillow composite, aligned to north) vs clean compass rose; (iv) which bodies
    (sun + MW always; moon when pushed). Operator earlier leaned: clean compass-rose acceptable, site
    image nice-to-have; sky-dome is the honest "where in the sky" view.
    BUILD APPROACH: standalone Python script (matplotlib polar Axes; Pillow only if compositing a site
    image) that reads the workbook read-only, builds the radial figure, writes SVG + PNG to outputs.
    NOT a VBA/Excel deliverable. Keep it SIMPLE first pass: compass rose + sun/MW rise-set rays + GC
    dotted arc + cart pin, true-north up. Iterate on styling toward the screenshot after the geometry
    is right. (Cross-ref: GIMBAL_VIZ.md, UI_DESIGN_Execution_v3.md, HEADING_CONVENTION.md.)
    Distinct from the Excel "Cart trace (rear axle, m)" bicycle chart (exists, needs calibration) and
    the Arduino Execution gimbal chart (live yaw/pitch + camera icon + bands - already specced).

12. Parked (older): astro chart curves; gimbal unwind/cumulative-yaw; SERVO_TO_DEG slip cal;
   night palette for Exec screen; reconcile docs to HEADING_CONVENTION.md.

## Key firmware landmarks (v59, approx lines)

- `Arduino.h` before `mbed.h` + RTOS guard ~120-133
- `g_can_mtx` decl ~2044; locked `sendFrame()` ~2061-2081
- `RawClient` (Socket* -> Client adapter) ~4872
- `httpThreadFn()` (raw TCPSocket :80, blocking accept, real handler) ~4911
- httpx telemetry globals ~4859; loop-side telemetry printer ~5205
- HTTP thread start ~5086 (after WiFi connect; `wifiServer.begin()` retired)
- `handleHttpRequest(Client&)` fwd decl ~4805; def ~5343
- build marker ~5026

## Key CCAPI-fire landmarks (v77, approx lines)

- `g_ccapi_mtx` decl (next to `g_can_mtx`) ~1374
- `ccapiRequestRawSocket()` (raw TCPSocket, set_timeout, Content-Length early-exit) def ~3005
- `ccapiRequestRaw()` dispatcher: `#ifdef STUB_WIRED_ETHERNET` -> socket impl; `#else` EthernetClient
  (wired send = single `client.write()` #wire-onebuf v85; non-200 dumps raw `[wire]` status-line/hdr) ~3112
- `ccapiRequest()` logging wrapper takes `g_ccapi_mtx` (ScopedLock) ~3180
- `firePhoto()` (non-blocking trylock; CCAPI else pin-D7) def ~4453
- `backupShutter()` (pin-D7 floor, 200ms busy-wait) ~4429
- soak cycle `soakCycle()` ~2934 (alternates Tv 0"5/0"4); `/soak/start` ~6012
- NOTE: inactive `[ccapi-dbg]` traces remain in the wired-only `#else` body (don't compile in WiFi build)
