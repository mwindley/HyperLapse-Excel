# WORKFRONTS.md — Day 24 (part A) update block

**Paste above the Day-23 (part 2) update block. Apply the status-line
changes noted at the bottom.**

---

## Day 24 (part A) update (30 May 2026) — Soak baseline PASS + edge instrument

Two things this session: (1) ran the **first #63 soak** and it passed
on every axis, and (2) **reframed #63** from a duration/stability test
into a field **link-margin / edge-finding** test, then built the
instrumentation that reframing needs.

### First soak run — close-range baseline: PASS

Build `soak-v7`. WiFi/CCAPI only, RAW-only, lens-capped, cart
stationary on the bench network (Rosedale, cart .1.97, camera .1.99),
2 s cadence, Tv alternating 0"5/0"4.

- **Duration** 7,485 s (~2 h 05 m). **Frames** 2,880.
- **Triggered = accepted = on-card = 2,880.** shutter POST 2,880/2,880
  (zero fail); camera card delta 0 → 2,880 RAW files. Perfect
  three-way match — no loss anywhere in the chain.
- **Heap dead-flat:** mallinfo uordblks first/min/max/last all 25,288,
  **drift = 0** across the whole run, identical to idle baseline. No
  leak, no creep — the cleanest possible result for the failure mode
  #63 was built to catch.
- **No stalls:** max_gap_ms = 10,003 (one heartbeat interval),
  stalls_gt_30s = 0. No blocking-call stall, no silent disconnect.
- **RSSI** -32 to -49 (last -35). Strong throughout.
- **status_err_total = 713** — ALL of them PUT-Tv 503s, none on the
  shutter path. Cause: the 0"5 shutter inside the 2 s window collides
  with the next PUT (camera busy → 503). The soak's deliberate
  no-TABLE-fallback lets these show as failed rows instead of hiding
  them. Benign cadence artifact, not instability. (put_tv 3,593
  attempts / 2,880 ok = 713 = err total — they reconcile exactly.)

**Explicit limit — what this run did NOT prove:** the link was never
stressed (cart close, strong signal), and the production envelope was
not exercised — no Excel/showastro plan loop, no gimbal slews (#54),
no concurrent CAN load (#61 ISR-vs-network), flat 2 s cadence rather
than a real variable plan. So this is a clean proof of the **CCAPI
transport + shutter + Tv-write path under sustained cadence** — a
baseline, not a production sign-off.

### #63 reframed — duration test → field link-margin / edge test

The real soak isn't a longer bench run; it's a measurement of **link
margin under field conditions**. Timelapse is shot in a remote area
(no competing traffic, 2.4 GHz only for reach), AX6000(s) in/near the
van, cart far out with terrain in between. Failure is an **acceptable,
expected outcome** — the instrument's job is decision support: let the
operator stand at a candidate cart position, soak, and read whether
the link is good enough to trust a sunset→sunrise run, or not. The
deliverable is an **empirically measured edge RSSI** for a given
terrain / aerial / AP arrangement, and a clean before/after when a
second (cabled) AX6000 is added nearer the cart.

### Edge instrument built (build `soak-v8`)

- **Per-row RSSI.** RSSI now stamped on every PUT/GET/POST row, not
  just heartbeats — so each failure is correlated to the signal it
  happened at. (CSV column count unchanged; rssi field was already
  present, now populated on all rows.)
- **LINKDOWN / LINKUP rows** on WiFi state transitions; LINKUP carries
  seconds-down in its rtt field. A data gap is now diagnosable:
  bracketed by LINKDOWN/LINKUP = real link drop; gap with no
  transition = code hang. Different problems.
- **`/soak/summary` edge lines added:**
  `edge: first_fail_rssi=<dBm> @<s> worst_fail_rssi=<dBm> longest_fail_run=<n>`
  and `link_drops=<n> longest_outage_s=<s>`. `first_fail_rssi` is the
  headline number — the measured edge. `longest_fail_run` separates
  scattered churn from a dead patch.
- **`/soak/summary` + `/soak/dump` (from soak-v6):** whole-run tally
  and bounded byte-range readout over WiFi, because the logging
  microSD is sealed in the cart and not physically accessible.
  `/soak/dump?off=N&len=M` (len capped 4096) pulls the raw CSV in
  chunks; iterate off using the byte count from `/soak/info`.
- **Heap on heartbeat rows (from soak-v7):** mallinfo().uordblks —
  catches a leak (bytes-in-use creep). Does NOT expose largest-free
  block, so pure fragmentation still shows only as a stall; the two
  signals (heap drift + stalls) together cover both shapes.

### Cart Recon UI — live link + IMU status line

New status line on the Cart Recon screen under the voltage line:
`WiFi <rssi> <OK|marginal|WEAK> · IMU <cal n/3 | -->`, color-banded
(green ≥ -60, amber -60..-72, red < -72) on the existing 3 s poll —
at-a-glance OK/NOK read for the operator at a candidate cart position.
Bands are a first guess; reset them to the measured `first_fail_rssi`
once a field soak provides it. Fed by two appended `/status` fields
(idx 13 RSSI, idx 14 BNO cal) — existing indices unchanged, Excel/UI
parsers intact.

### BNO085 on UI — prep only, #40 untouched

Status idx 14 = `bno_cal_status` (0..3), driven by a new global that
sits at -1 ("IMU --" on the UI) while STUB_BNO is defined. When #40
brings the BNO live, set that one global from the rotation-vector
accuracy byte and the field lights up — no further UI/status work.
Production BNO path was NOT touched; #40 stays separate.

**Workfront status changes:**

- **#63 Multi-hour soak — FIRST RUN COMPLETE, PASS (close-range
  baseline); REFRAMED to field link-margin / edge-finding.** Baseline
  proved transport+shutter+Tv path clean (2,880/2,880, heap drift 0,
  no stalls) but link was unstressed. Now an instrument for measuring
  the field edge. **Open:** longer envelopes (4 h, 12 h — fragmentation
  can be duration-dependent, invisible at 2 h); transport matrix (WiFi
  done at 2 h; **wired #69 build entirely un-soaked**); production
  envelope (Excel plan + slews + CAN) still not soaked; PUT-cadence
  decision (ms=2500 or idle-gate to clean the 713 cosmetic 503s — does
  not affect shutter).
- **#69 W5500 wired Ethernet — WiFi build now soak-proven; wired build
  un-soaked.** "Soak each, then pick" — first cell (WiFi × 2 h) done.
- **#40 BNO085 — UI surface prepped (display only).** `bno_cal_status`
  global + `/status` idx 14 + Cart Recon line, all stub-safe at -1.
  Live integration still open/separate; remaining items unchanged from
  Day 23.
- **#54 Gimbal slew overshoot** — still open/deferred; not exercised
  (no slews in the soak).

**New workfront:**

- **NEW #70 Soak run protocol for edge-finding.** Define the field
  procedure the instrument now supports: characterise across range
  (note RSSI at working position, ideally a walk-out or several
  positions) rather than one fixed spot; one-AP vs two-AP (cabled,
  nearer cart) before/after to decide whether the repeater earns its
  place; record `first_fail_rssi` per terrain/aerial/AP combo as the
  operator's OK/NOK edge reference. Confirm the soak loop never wedges
  on a drop (logs the non-200, continues, resumes when link returns) —
  in particular that a TCP connect timeout at the edge doesn't block
  the loop for seconds per frame. Not blocking; shapes future runs.

---

---

---

## New workfront (continues Day-24 part A list)

- **NEW #71 Firing-hold for manual camera LAN reconnect (Execution
  UI).** The Canon R3 does not auto-reconnect to the AP when WiFi
  returns — recovery is a manual menu sequence on the camera body
  (~3 clicks), and Canon's own networking docs warn against operating
  the camera during connection setup. Real-world: a LAN drop far out
  can leave the camera offline for the rest of the night, and the
  operator cannot complete the manual reconnect while the cart is
  actively firing at the camera. **Requirement:** an operator-asserted
  **firing hold** in the Execution UI that idles EVERY active firing
  path — CCAPI traffic (Tv/ISO PUTs, GETs, photo POSTs), pin-D7
  pulses, and any running plan's frame pushes — for the duration of
  the manual reconnect, then resumes firing by whatever transport is
  live in that build. Single global hold, transport-agnostic (it
  pauses everything live, doesn't special-case a transport).
  - **In direct tension with the "always fire" objective by design:**
    the hold is a deliberate, operator-chosen firing gap. Accepted as
    the cost of recovering a camera that is otherwise lost for the
    night (a short gap beats an indefinite one). Kept honest only by
    making the gap short and operator-controlled.
  - **Open (defer detail):** manual-only vs also auto-detect (a run of
    failed CCAPI calls auto-asserts the hold); resume manual vs gentle
    auto-probe; plan interaction (does a mid-execution plan hold or
    keep moving while firing is idled).
  - **Dependency:** definition-of-done waits on the #63 edge-finding
    soak verdict. If WiFi at real field range drops often, that bears
    on whether WiFi CCAPI can be the production transport at all,
    which reshapes this feature. **Scaffold now, finalise after soak.**
  - Lives with #70 (soak run protocol) and the transport ladder
    decision below.

---

---

---

## New workfront (continued)

- **NEW #72 Cart + gimbal execution feature testing on the assembled
  Giga (in motion, under a plan).** Day 23 brought the subsystems up
  together and confirmed they *run* (low-to-high integration, no
  faults) but deliberately did NOT run plan execution with motion or
  slews. The execution *features* exist in code and several were
  bench-✓'d in earlier (Uno-era) sessions — MOVE-to-MOVE merge (tr=M),
  STOP decel variants (S / D / E), Tic accel/decel ramps, the cubic
  evaluator + segment dispatcher (#5a, marked DONE), ±100 mm nudge,
  PAUSE/RESUME ramp, S-curve plans (B-S, C2, E1 ✓). None of this has
  been *seen working on the assembled Giga in motion*. This workfront
  is the quality-validation pass: watch the features actually move and
  confirm they do the smooth, photogenic thing — distinct from #63,
  which is duration/transport stress, not motion quality.

  **Independent of the transport verdict** (a move is a move whether
  CCAPI or D7 fires the shutter), so it can run in parallel with the
  #63 soak ladder. But it is where **#54 (large-angle slew overshoot)**
  will surface, and where cubic/easing behaviour is actually visible —
  so #54 is effectively folded into this.

  **Suggested test sequence (low-to-high, each watched before next):**
  1. **Single MOVE with easing** — one segment, confirm Tic accel ramp
     in and STOP_DECEL ramp out; no jerk at the ends. The base unit.
  2. **MOVE→MOVE merge (tr=M)** — two segments, confirm the speed
     change merges smoothly (no stop between) per the M-transition.
  3. **STOP variants** — S (decel-to-rest + hold), D (6-min decay
     ramp), confirm at-rest timing and clean re-accel into the next
     segment (re-validate the Uno-era B-S / C2 ✓ on Giga).
  4. **Short multi-segment plan end-to-end** — e.g. the E1 S-curve
     (`m,300,-5,20,d` → `m,300,5,20,d`); confirm steering ramp and
     segment hand-off on the assembled cart.
  5. **±100 mm nudge mid-MOVE** — confirm live target adjust + the
     past-zero completion path.
  6. **PAUSE / RESUME mid-MOVE** — Tic ramps down (photogenic), holds,
     ramps back up via ACCEL, rear_steps continues from where it
     stopped.
  7. **Gimbal cubic-eval motion** — per-tick cubic evaluation driving
     the gimbal along a curve (not stepwise); confirm smooth tracking,
     not jumps. (#5a evaluator is coded but the *motion* hasn't been
     watched.)
  8. **Gimbal astro drive** — `/gimbal/showastro` and
     `/showastrooffset` to a stored target and back; THIS is where
     **#54 overshoot** on large-angle slews (e.g. home → 120° pan)
     is expected to show. Apply/confirm the #54 fix here.

  **Open:** whether to test with the production exposure loop running
  concurrently (motion + firing together) or motion-only first; how
  smoothness is judged (by eye / movewatch logging / both). Not
  blocked by soak.

---

---

---

## Status-line note

- This folds the standalone **#54** (gimbal slew overshoot) into #72
  step 8 as the place it gets exercised and fixed; #54 stays its own
  numbered item but is no longer "not yet exercised — deferred," it is
  "to be exercised under #72."

---

---

## Camera-loss recovery + transport ladder (Day 24 — recorded)

**For the resolved-architecture region near the top of WORKFRONTS.md.**

**Objective:** always fire; minimum cables.

**Transport ladder — soak-adjudicated, ship one:** The firing-transport
options form a priority ladder. Each rung stays built in the codebase
as a compile/runtime option; soak results decide which one ships.
Lower rungs are retired (archived, not deleted) if a higher rung
passes its soak.

1. **WiFi CCAPI over AX6000 (no cables) — preferred.** Currently in
   soak (#63). If it passes the field edge-finding soak, it ships and
   the rungs below are archived.
2. **Wired HTTP CCAPI — archived.** Promoted to a full soak only if
   WiFi CCAPI fails its soak. If it then passes, it ships.
3. **Pin-D7 hardware shutter — archived.** Reaches production only if
   BOTH CCAPI transports fail their soaks.

This is a single-transport production ship, not a runtime-layered
stack — the rungs are competing candidates for one production slot.
(Consistent with the Day-23 note: "production ships one transport;
soak each, then pick.")

**R3 reconnect behaviour — established (Day 24, from Canon docs +
field experience):** The EOS R3 does not auto-rejoin the AP after a
WiFi drop. Across the EOS R line (R1/R5/R6 III siblings), Canon's
documented reconnect is always a manual menu action — select
Connection settings → saved SET → Connect — with connection settings
*retained* (fast) but not *automatic*. The WFT-R10 (pro networking
accessory) guide explicitly states operating the shutter/controls
during connection configuration closes the wizard and is not allowed
— documenting the same camera-input vs firing-activity collision seen
in the field. Conclusion: recovery is manual and cannot proceed while
the cart fires → motivates the #71 firing hold.

**Implication captured:** because the production build may ship as
CCAPI-only (if WiFi CCAPI wins), the firing hold cannot assume a D7
path is firing underneath to keep frames alive during the hold — in a
CCAPI-only build the hold is a true firing gap. In a build where D7 is
still present, the hold idles that too (the camera's UI fights ALL
firing activity, not just network traffic). Hence the hold is defined
as transport-agnostic: idle whatever is live.

---

## Status-line changes to apply elsewhere in WORKFRONTS.md

- **Header "As of:"** → Session H day 24 (part A), 30 May 2026.
- The #63 entry (currently "close-out test for #61 build discipline …
  Blocks on flash + smoke test landing first") is superseded: first
  run is done and #63 is reframed — update to the Day-24 status above.
- Any line still implying #63 is purely a duration/stability test is
  stale; #63 is now primarily a field link-margin / edge-finding test
  (duration is a secondary axis).

fallback architecture (Day 15 — resolved)".**

---
