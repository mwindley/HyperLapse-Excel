# WORKFRONT — Exposure fallback removal + clock-driven phase/target

Status: SPECIFIED, not started. No code written. Two independent work items.
Context build: soak-v244b. Cart↔camera on W5500 wired (proven clean, Test9d).

---

## Why (the real bug + the cleanup)

1. **Wrong-day phase bug.** Plan started at 4am flipped mode using a *baked* astro
   boundary that pointed at *tonight's* astro dark (~14 h ahead), not the one just
   passed. Mode was decided at author-time in Excel and replayed on the cart from
   relative offsets against an anchor — so it could anchor to the wrong day.

2. **Stale fallback machinery.** The cart carries an open-loop "TABLE mode" exposure
   walk (clock-driven cubic Tv/ISO from pushed tables) as a fallback for when the
   CCAPI luminance read fails. It dates from the WiFi era and was always weak: if the
   transport was down, the open-loop result couldn't be PUT to the camera anyway.
   Now CCAPI is on W5500 wired and proven reliable — the wired link is no longer the
   suspect. Decision: REMOVE the fallback. Cleaner code; old time-driven exposure
   path is confusion once on the cart.

Architecture principle held throughout: **Excel is the brain, cart is dumb.** Cart
does NO astro maths. Excel computes everything and pushes absolute values.

---

## ITEM 1 — REMOVE the open-loop exposure fallback (TABLE mode)

### New behaviour on a wired meter-read fail
- Cart **HOLDS** current Tv/ISO (no flip, no table, no clock-walk).
- Existing **alarm** fires (cam=nok / comms watcher) — operator notified.
- **Operator fixes** the link in the field.
- Cart **RESUMES** the LUM walk automatically when reads succeed again (just starts
  metering next cycle; no re-arm).
- The **held period** (frozen-exposure frames during the outage) is **fixed in post**.
  Consistent with shoot-low / fix-in-post philosophy.

So: meter fail = HOLD + ALARM + RESUME. No automatic exposure compensation.

### Remove (the whole TABLE/formula fallback — all of it)
Confirmed by dependency map (read 2026-06-28):
- `EXP_MODE_TABLE` and every flip to it
- `tryFlipToTableMode()` (line ~1069) and its callers on fetch-fail / liveview-fail
- `formulaTv()` (line ~1006), `formulaIso()` (line ~1040) — only caller is the
  TABLE block ~7667/7668
- `getCurrentTrel()` (line ~991)
- `getElapsedSinceAnchor()` (line ~976)
- `isCurrentlySunrise()` (line ~984) — NOTE: now only feeds diagnostic `cur_event`
  strings (lines ~7832, ~8338); the LIVE walk mode does NOT use it (see below)
- `exp_t0ss_at_receipt`, `exp_t0sr_at_receipt` (line ~830-831)
- `exp_cross_trel` (line ~832)
- `exp_t0_millis_at_receipt` (line ~833)
- `exp_anchor_set` (line ~834) — if nothing else uses it after the cull
- the pushed exposure ladders `exp_sstv / exp_srtv / exp_ssiso / exp_sriso` + counts
- the `/exposure/load` parser fields that fill t0ss/t0sr/cross + the ladders
- TABLE-related diagnostic JSON: t0ss, t0sr, cross, trel_now, cur_event, anchor block
  (lines ~7818-7833, ~8333-8340)

### Keep (the live closed-loop walk — already correct)
- `meterAndAdjustLive()` (line ~5972)
- LUM-vs-target compare for direction (line ~5997):
  `lum_mode = (lum < target) ? BRIGHTEN : DARKEN` — this is the LIVE walk mode and
  is ALREADY phase-independent (v222 #lumbidir). It does NOT use isCurrentlySunrise.
- The Tv/ISO ladders for stepping (`TV_LADDER`, `ISO_LADDER`) — these are the walk's
  step ladders, NOT the pushed cubic exposure tables. KEEP.
- v244b cadence-adaptive meter trigger (#lumcad).

### ? Open / verify during implementation
- `?` After removing TABLE, confirm `exposure_mode` collapses to a single state
  (LIVE only) cleanly — every `exposure_mode == EXP_MODE_TABLE` / `!= EXP_MODE_LIVE`
  branch must be re-read and simplified, not left dangling.
- `?` `EXP_DEFAULT_MODE` / `lum_mode` default — keep the BRIGHTEN/DARKEN enum for the
  *step direction* (it's still the walk's internal up/down), even though the *name*
  is poor (see Item 2 naming note). Do NOT confuse the walk's step-direction enum
  with the new phase.
- `?` Does anything outside exposure use `exp_anchor_set` or the rt anchor? (rt
  anchor `rt_offset_ms` at line ~1343 is SEPARATE and STAYS — it's the live UTC clock,
  needed by Item 2. Do not remove the rt anchor.)

---

## ITEM 2 — Clock-driven phase + style targets (replaces baked mode)

### Concept (operator does NOT set mode)
- Operator sets only **style targets**, once, per their look:
  - sunset target ~60 (brighter — holds real-world dusk feeling)
  - sunrise target ~40 (darker — keeps deep blues, kills early white light)
- Cart picks the **active target** live by comparing its own UTC clock to pushed
  **astro dark / astro dawn** instants. No operator mode input. No astro maths on cart.

### Why flip at astro dark/dawn (not sunrise/sunset)
At astro dark/dawn the exposure is pinned at the night rail (Tv 20" / cadence 22 /
ISO 1600), so a mode flip there has **no consequence** — the walk isn't moving. This
removes the dangerous flip-mid-twilight jump. The flip always lands while parked at
the night limit.

### Handles all start cases automatically
- Start 3am, 3 h GC then home: upcoming event is a sunrise; pinned at night rail the
  whole time so the flip (if reached) is consequence-free; if operator leaves before
  it, never matters.
- Start 4pm: heading into astro dark → it's a sunset; active target = sunset.
- Overnight: crosses astro dark (→ night) then astro dawn (→ sunrise side); flips at
  each, both consequence-free.

Rule: **active target = which side of the pushed astro dark/dawn epochs `now` is on**,
re-evaluated ~every 60 s. Pure compare, recomputed continuously → no stale-day bug.

### New names (proposed)
| New name | What | Source |
|---|---|---|
| `cartNowEpochMs()` | live UTC ms = existing `millis()+rt_offset_ms` (line ~1349) | EXISTS, just name/use it |
| `astro_sunset_epoch` | astro-dark instant, absolute UTC ms | Excel push absolute |
| `astro_sunrise_epoch` | astro-dawn instant, absolute UTC ms | Excel push absolute |
| `lum_target_sunset` | sunset style target (~60) | Excel `dataLumTargetSunset` |
| `lum_target_sunrise` | sunrise style target (~40) | Excel `dataLumTargetSunrise` |
| `lum_target_active` | target in force now | cart, picked by phase |
| `lumPhaseSelect()` | dumb compare: now vs the two astro epochs → which target | cart, no astro maths |

- Exec UI override: operator can bump the active target for tonight (cloudy: sunset
  60→70). Reuse existing `/exposure/lumtarget` to override the active value.

### Excel side
- New pushes: `dataLumTargetSunset`, `dataLumTargetSunrise`, `astro_sunset_epoch`,
  `astro_sunrise_epoch` (all absolute, all computed laptop-side).
- Replaces the old baked t0ss/t0sr/cross + exposure-ladder push.

### ? Open for next session
- `?` Naming: BRIGHTEN/DARKEN is an *outcome* not an *input* — poor name. The new
  PHASE input could be SUNRISE/SUNSET (matches Excel target names) or RISING/FALLING.
  Decide. (The walk's internal step-direction enum can stay BRIGHTEN/DARKEN — that's
  genuinely an action.)
- `?` Which two epochs exactly: astro dark + astro dawn only, or does the cubic GIMBAL
  track still need civil sunrise/sunset for its geometry? (Gimbal track t_rel is
  SEPARATE from exposure t_rel — do not conflate. Verify the gimbal cubic is untouched
  by Item 1's removal.)
- `?` Confirm `/exposure/load` (or a new endpoint) is where the two targets + two
  epochs arrive; design the parser fields.
- `?` Single override target vs separate sunset/sunrise override in Exec UI.

---

## Hard guardrails for whoever implements
- Cart stays DUMB: no astro calc. Excel pushes absolute epochs + targets.
- Do NOT remove the rt anchor (`rt_offset_ms`, line ~1349) — Item 2 needs it.
- Do NOT touch the GIMBAL cubic track t_rel — only the EXPOSURE formula path goes.
- Keep `TV_LADDER` / `ISO_LADDER` (walk step ladders) — only the pushed CUBIC exposure
  tables go.
- Build banner: bump version every edit, single println, exactly 2 quotes.
- Test-to-close each item separately.

---

## ITEM 2 — UNIFIED with #57 (date-specific astro) — read 28Jun, both sides

Item 2 (clock-driven phase + style targets) CANNOT be a cart-only change. Reading
both halves (firmware + HyperLapse.xlsm VBA) on 28Jun proved the real work is on the
EXCEL side, and it is exactly workfront #57. Item 2 and #57 are now ONE workfront.

### What was read (FACT)

**Cart side (firmware, today):**
- /exposure/load parser (parseExposurePayload) receives: br, tvc, isoc, isob, the four
  cubic ladders sstv/ssiso/srtv/sriso, and time fields t0ss/t0sr/cross.
- t0ss/t0sr are RELATIVE seconds-from-now, replayed on the cart against
  exp_t0_millis_at_receipt = millis(). This relative anchor IS the wrong-day bug.
- lum_target_sunset / lum_target_sunrise / lum_targets_set ALREADY EXIST as globals
  but are dormant - the walk currently uses only lum_target_exec (single value).
- cartNowEpochMs() exists (millis()+rt_offset_ms, rt anchor set by push). Item 2 has
  its clock source already.

**Excel side (Formula.bas PushFormulaToCart):**
- The whole push is the TABLE fallback feed - self-described "CCAPI fallback when live
  luminance reads are unavailable." With TABLE removed (v253/254), PushFormulaToCart
  now pushes to DEAD cart code. The module even notes a cart 404 is "acceptable".
- It computes t0ss = (Now() - sunsetTime)*86400 etc - RELATIVE seconds, anchored on
  Now() at push time. Same wrong-day root, on the Excel side.
- Targets 40 (sunrise) / 60 (sunset) are documented here and EXIST as named ranges
  dataLumTargetSunrise (C42=40) / dataLumTargetSunset (C41=60).

**Excel side (Utils GetSunsetTime):**
- shootDate = Int(Now()) - anchors the WHOLE sun computation on today's calendar date.
- Evening events (sunset, astroDusk) computed for shootDate; morning events (sunrise,
  astroDawn) for morningDate = shootDate+1.
- astroDawn IS computed but NOT written to any named range (thrown away). Only
  dataAstroDusk is persisted. astro DAWN must be persisted (one line) for Item 2.
- Comment in code: "Future workfront #57 will read dataShootDate; for now default to
  today." -> the fix was always known.

**Start anchor cells (Settings sheet):**
- C49 dataShootStart = currently =NOW() (operator set lazily; gimbal catches up ~3min).
  Underlying value is a full date-serial so it DOES carry a date - but it was DESIGNED
  time-only (init default TimeSerial(15,42,0)).
- Plan sheet column N "Fires at" (e.g. N6 = first GP) is TIME-ONLY - no date.
- CRITICAL: GetSunsetTime does NOT read C49 or any shoot anchor. The astro times and
  the shoot start are computed by TWO INDEPENDENT mechanisms that never reference each
  other. Nothing guarantees the dusk/dawn belong to the same night as the start.

### The 2:30am-author / 3am-start failure (traced, FACT)
- Operator authors at 2:30am for a 3am (this-morning) start.
- GetSunsetTime run at 2:30am: shootDate = Int(Now()) = today -> "tonight's" dusk is
  the COMING evening (~15h away), "tomorrow's" dawn is a DAY+ away.
- The astro epochs come back for the WRONG NIGHT, because GetSunsetTime never consults
  the shoot anchor. The cart-side absolute-epoch fix alone does NOT cure this - the
  epochs themselves would be wrong.

### #57 prior thinking (from WORKFRONTS.md, still valid)
- Problem #57 named exactly this: Excel computes from Now()/today; dusk-to-dawn shoots
  cross midnight so the shoot's dawn is the NEXT day's sunrise.
- Operational driver: operator often prepares a shoot EARLIER (different date),
  potentially days in advance, potentially WITHOUT internet.
- The internet dependency was later PROVEN UNNECESSARY (local Astro.bas wins on accuracy
  AND offline). So the "no-internet, prep-3-days-ahead" rationale SURVIVES as a reason
  to want date-specific anchoring, even though its original API justification is gone.
- #57 fix: add dataShootDate named range (defaults today, operator-editable); ALL astro
  anchors on it; Astro.bas already takes atTime so works once given the right date.

### UNIFIED REQUIREMENT (Item 2 == #57)
The exposure phase rework and #57 are the same job. The full change:

EXCEL:
1. Add `dataShootDate` (named range, defaults today, operator-editable). The single
   source of truth for WHICH NIGHT the shoot belongs to.
2. GetSunsetTime anchors shootDate on `dataShootDate`, NOT Int(Now()). Then dusk/dawn
   and the plan start are guaranteed the same night. Offline, days-in-advance capable.
3. Persist astroDawn to a new named range (dataAstroDawn) - currently computed then
   discarded.
4. Replace PushFormulaToCart: stop sending the four dead ladders + relative
   t0ss/t0sr/cross. Send instead:
   - astro_dusk_epoch  (absolute, evening, light->dark boundary)
   - astro_dawn_epoch  (absolute, morning, dark->light boundary)
   - lum_target_sunset  (from dataLumTargetSunset, ~60)
   - lum_target_sunrise (from dataLumTargetSunrise, ~40)
   All ABSOLUTE epochs / explicit values - no relative-to-Now seconds.
5. Ensure C49 dataShootStart is consistent with dataShootDate's evening (or derived
   from it). Decide NOW()-vs-explicit only if future-scheduling is wanted; for
   "push and start now" NOW() is sufficient because it carries today's date.

CART:
6. Receive astro_dusk_epoch / astro_dawn_epoch + the two targets in the (redesigned)
   /exposure/load parser. Drop the dead ladder/relative-anchor fields.
7. lumPhaseSelect(): dumb compare cartNowEpochMs() vs the two epochs:
   - now < dusk          -> daylight/sunset side  -> sunset target
   - dusk <= now < dawn  -> deep night            -> sunrise target (pinned at night
                                                      rail, flip is consequence-free)
   - now >= dawn         -> past dawn/sunrise side -> sunrise target
   Re-evaluated ~every 60s. Pure compare, no astro maths on the cart.
8. Wire the selected target into the walk (replace the hardcoded lum_target =
   lum_target_exec). One source of truth: active target initialised from Excel,
   operator can override any time via /exposure/lumtarget (overwrites the active value).
9. GUARD: plan must NOT start without the required Item-2 data (epochs + targets
   present). Add /exposure/check + an xstart() guard (same pattern as v229 camera /
   v241 gimbal guards). No silent fallback to a default target.

### Boundary choice (DECIDED)
Flip at astro DUSK and astro DAWN (the true-dark boundaries), NOT civil sun events -
because at those instants exposure is pinned at the night rail so the target flip has
no visible consequence. Astro dawn must be persisted Excel-side (item 3 above).

### Open (small)
- ? exact named-range names for the two epochs in the push (astro_dusk_epoch etc).
- ? whether C49 stays =NOW() or becomes explicit - only matters if future-scheduling
  is added; not blocking for push-and-start-now.

## Guardrails (unchanged)
- Cart stays DUMB: no astro calc. Excel pushes absolute epochs + targets.
- Do NOT remove rt anchor (rt_offset_ms) - the cart clock Item 2 needs.
- Do NOT touch the GIMBAL cubic track t_rel.
- Keep TV_LADDER / ISO_LADDER (walk step ladders).
- This is a COORDINATED cart+Excel change - neither half ships alone (the push
  contract changes on both sides at once).

---

## ITEM 2 COMPLETE - verified end-to-end (28Jun, ~21:43 Adelaide)

Both halves built, both proven against the real shoot night.

CART (firmware v255/v256, flashed + bench-proven):
- lumPhaseSelect(): cart compares cartRealTimeMs() to the two pushed astro epochs
  and picks the target. now<dusk -> sunset(ss); else -> sunrise(sr).
- Wired into meterAndAdjustLive (epochs+targets set -> phase-select, else fall back
  to lum_target_exec; operator /exposure/lumtarget override still wins live).
- Routes: /exposure/epochs (set dusk+dawn ms), /exposure/target (ss/sr), /exposure/
  check (ready=epochs+targets+clock), /exposure/phase (live decision read, debug).
- xstart() gates on /exposure/check after gimbal/check -> EXPOSURE NOT READY if the
  night facts are not pushed (no silent default).
- BENCH PROOF (cause/remove): future dusk -> active_target:60 side:sunset;
  past dusk -> active_target:40 side:night_sunrise. Same clock, only dusk moved.

EXCEL (Formula.bas PushFormulaToCart, rewritten + live in Prep Cart):
- Pushes the two ABSOLUTE astro epochs (/exposure/epochs?dusk=&dawn=) + the two
  style targets (/exposure/target?ss=60&sr=40). Drops the dead /exposure/load push
  (TABLE ladders sstv/ssiso/srtv/sriso + relative t0ss/t0sr/cross).
- Reads dataAstroDusk/dataAstroDawn (local) -> absolute UTC epoch-ms via
  ExcelLocalToEpochMs using dataUTCOffset (Settings C10 = 9.5 Adelaide).
- BUG FOUND+FIXED 28Jun: first cut read a NON-EXISTENT name "dataUtcOffsetHours";
  the failed read left offset=0, so dusk 18:44 LOCAL was sent as 18:44 UTC (9.5h
  late = wrong night, 29/06 04:14). Correct name is dataUTCOffset. After fix the
  push sends dusk=1782638072000 (28/06 18:44 local) / dawn=1782678366000 (29/06
  05:56 local) - verified correct against the Settings cells.
- LIVE PROOF: Prep Cart log shows both FORMULA lines OK; cart /exposure/phase then
  returns active_target:40 side:night_sunrise for the real night (now past dusk).

Anchor chain (the #57 fix this depended on, also done + field-verified):
- Operator enters the shoot START as a full date-time in dataShootStart (C49).
- GetSunsetTime anchors shootDate on dataShootStart's DATE (not Int(Now())),
  validates the shoot is not already over, persists dataAstroDawn (Settings F23).
- CalculatePhaseTimes Phase-1 anchor also moved to dataShootStart's date.

================================================================================
## STANDING ITEMS (open, none urgent) - as of 28Jun end of session
================================================================================

1. WALK-USES-TARGET, real plan (UNTESTED). Bench proved lumPhaseSelect picks the
   right target; NOT yet proven that meterAndAdjustLive actually walks Tv/ISO
   toward the phase-selected value during a LIVE plan with camera metering. Same
   wiring the single-target walk already used (just fed a different number), so
   low risk, but unproven. Verify on a real overnight or a metered bench run:
   confirm the walk targets 40 at night and 60 before dusk, and that the operator
   /exposure/lumtarget override still wins live.

2. LEGACY-LOOP REMOVAL (deferred, big, mapped). The old laptop-driven shoot loop
   is NOT used by the three-button design (PrepSession/BuildPlan/PushToCart) and
   should be removed in a careful multi-module pass:
   - Sequence.bas: REMOVE StartSequence/StopSequence/IsSequenceRunning/SequenceLoop/
     OnPhaseEnter/RunShot/GetLumMode/LumModeName/GetActiveLumTarget/ScheduleNextShot/
     WaitForCamera/GimbalToSunset/MilkyWay/Sunrise/StartCartReplay/StopCartReplay/
     RunCartReplayStep + GetCurrentPhase/PhaseLabel (the latter two parked here this
     session, dead - read dataPhase1-5 which are no longer written).
     KEEP: InitShoot (PrepSession needs it), SystemCheck (own button), CameraReachable
     + ArduinoReachable (SystemCheck needs them).
   - Camera.bas: KEEP live crossovers CameraGet, AdjustExposureByLuminance,
     UpdateArduinoDisplay, InitTvLookup. REMOVE ~28 legacy shoot helpers (TakePhoto,
     SetShutterSpeed, SetISO, PollLuminanceCalc, WaitForCamera, InitCamera, etc).
   - Cart.bas (replay), Buttons.bas (Start/Stop Sequence buttons), Sheet8.cls
     (their dispatch lines) - prune to match.
   - GetLumMode = the OLD Excel-side live phase decision, SUPERSEDED by cart-side
     lumPhaseSelect; goes with the legacy loop.
   Do it as a dedicated pass with the operator testing between - NOT a blind sweep.

3. FIRMWARE GIT COMMIT (standing risk). v235 -> v256 ALL UNCOMMITTED (repo HEAD is
   v234). Commit when ready: half-open detect+kick+toggle (v249-251), black-box SD
   snapshot (v252), TABLE removal (v253-254), cart-side LUM phase select + debug
   route (v255-256).

4. /exposure/phase DEBUG ROUTE (v256) - cheap, harmless; keep for field verification
   or strip in a later hygiene pass.

5. RECURRING REQ-PHASES connect=1002ms FAILED every 60s (battery telemetry poll,
   wired side) seen in earlier field logs - separate workfront, not Item 2.

6. dataShootStart NOW()-vs-explicit-typed: only matters if future-scheduling is
   wanted; for push-and-start-now an explicit typed date-time works (operator now
   enters it as a full date-time, validated not-already-over).

7. EXCEL dead helpers left in Formula.bas: BuildTvBlock/BuildIsoBlock/FormulaTv/
   FormulaISO + the FallbackFormula sheet are no longer called by the push (the UDFs
   may still be used in-sheet). Prune in a later Excel hygiene pass if confirmed dead.

================================================================================
## STANDING ITEM 8 [PROPOSED, not built] - LATCH THE WALK BETWEEN DUSK AND DAWN
================================================================================

PROBLEM (operator concern, talked through 28Jun, no code):
The luminance walk chases measured LUM every meter. A transient light source
during true dark corrupts it:
- Night riding at operator's value (e.g. Tv=20"), real scene LUM ~7.
- A car drives into scene: LUM jumps high -> walk DARKENs 20->15->10 chasing it.
- Car leaves: scene is deep-night again, BUT the walk already stepped to Tv=10".
  At Tv=10" the same dark scene now meters ~20 LUM (less exposure = lower
  reading), not the original 7.
- A single-direction (darken-only) sunrise walk never brightens back, so it
  RATCHETS: the transient walked it darker and it never recovers - the REST OF
  THE NIGHT is ~1 stop underexposed, not just the few frames the car was in.
(Bidirectional v222 walk instead HUNTS/oscillates around the target on the same
transient - also wrong. Neither one-way nor two-way handles a true-dark transient.)

A cloudy-day sun-gap (sun out for ~10s) is the daytime analogue but is easier to
fix in post; the night ratchet ruins the whole rest of the night.

PROPOSED FIX (uses the Item 2 epochs the cart already owns):
Between astro dusk and astro dawn (true dark), LATCH the walk: suspend all
metering-driven Tv/ISO steps. No car, cloud-gap, or transient can move the
exposure. The walk only runs OUTSIDE that window - sunset side before dusk,
sunrise side after dawn - where the real light change happens and a transient
costs a few frames at worst (fixable in post).

KEY DECISION (settled): the OPERATOR owns the exposure value; the latch only
PREVENTS the walk. Firmware does NOT choose a night rail, does NOT override -
it simply stops stepping. Whatever Tv/ISO the operator set going into true dark
is what holds until dawn. (Sidesteps any "what is the night rail" question.)

RULE: dusk < now < dawn  -> walk SUSPENDED, exposure held at operator's value.
      else (now<dusk or now>=dawn) -> walk LIVE.

FITS THE ARCHITECTURE: Item 2 used the dusk/dawn epochs to pick WHICH target
(40 vs 60). This uses the same epochs to decide WHETHER THE WALK RUNS AT ALL.
Inside true dark the target is moot (scene is rail-pinned by the operator), so
latching there is consequence-free - same boundary logic as the Item 2 flip
(flip/latch at true dark, never at the civil sun events).

SECOND DECISION (settled same session): REVERT the walk to SINGLE-DIRECTION.
This is BOTH changes, not just the latch.
- v222 #lumbidir made the walk bidirectional (per-meter lum-vs-target: lum<target
  -> BRIGHTEN, else DARKEN). On a transient that makes it HUNT/oscillate around
  the target, and at sunrise it overshoots (40->36) then reverses instead of
  riding the brightening up.
- Revert to one-way per phase: sunset = BRIGHTEN-only, sunrise = DARKEN-only
  (the original May design, mode set once per phase). At sunrise, if LUM dips
  below band the walk just WAITS - does nothing - until the sun climbs and LUM
  rises past the top of band, then takes the next darken step. Monotonic, no
  hunting, follows the natural light change.

HOW THE TWO COMBINE across the night:
- now < dusk  (sunset wing) : walk LIVE, BRIGHTEN-only, target = sunset (60).
- dusk <= now < dawn (true dark) : walk LATCHED, held at operator's value.
- now >= dawn (sunrise wing) : walk LIVE, DARKEN-only, target = sunrise (40).
So outside the dusk..dawn window the walk runs single-direction (it "hunts" the
twilight in one direction only); inside the window it is frozen. A transient in
a wing costs a few frames (post-fixable); a transient in true dark costs nothing
(latched).

NOT YET BUILT. No firmware edit this session - design captured only.
Two firmware changes when built: (1) latch walk between dusk/dawn epochs;
(2) revert v222 bidirectional back to single-direction per-phase (sunset
brighten-only / sunrise darken-only).
