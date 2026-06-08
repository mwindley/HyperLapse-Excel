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

## Status-line changes to apply elsewhere in WORKFRONTS.md

- **Header "As of:"** → Session H day 24 (part A), 30 May 2026.
- The #63 entry (currently "close-out test for #61 build discipline …
  Blocks on flash + smoke test landing first") is superseded: first
  run is done and #63 is reframed — update to the Day-24 status above.
- Any line still implying #63 is purely a duration/stability test is
  stale; #63 is now primarily a field link-margin / edge-finding test
  (duration is a secondary axis).
