# WORKFRONT — Idle UI-death (half-open association) — investigation + bench

Operating mode for this fault (reuse): detailed investigation of reasonable faults,
search manufacturer + forum + internet, enumerate the modes, instrument AGAINST a
probable, then PROVE it by cause/remove/cause/remove. "If you cannot cause it you
have not solved it." Be meticulous, rigorous, no short cuts, preventative — common
sense, not extreme anticipation. This is the Trial1–10 (25/6) bench discipline,
ported for the FIRST time to the INBOUND :80 / UI side (Trial1–10 only covered the
outbound W5500/CCAPI side).

---

## 1. SYMPTOM (as observed, corrected)

- UI was working and useful.
- Operator left it, did something else, came back — UI broke.
- NO load trigger: no big SVG/chart push, nothing happening. It broke while
  essentially idle/unattended.
- First field UI failure that yielded NO diagnostic info, because the SD/HTTPX
  instrumentation cannot distinguish this mode from a healthy idle cart.

This is the IDLE failure, not the LOAD failure. It rules OUT the socket-send-stall
family (those need a response in flight).

## 2. WHAT IS RULED OUT (read, not guessed)

- **#905 mbed write infinite-hang** — NOT present. Our RawClient::write (line ~6637)
  breaks on `r <= 0` and flips `_open=false`; it does NOT spin on connected() like
  the stock buggy MbedClient::write. Crossed off by reading the code.
- **Thread wedge / hard-fault (accept thread dead)** — does NOT match. The accept
  loop (line ~6708) stamps g_httpx_alive_ms every cycle (5s accept timeout), and the
  field tail showed alive_age SMALL + served CLIMBING right up to the freeze = the
  serving thread was ALIVE. A dead thread would show alive_age climb + watchdog fire.
- **Socket-pool / accept leak (v234 fix)** — that presents as served-flat + streak
  CLIMBING + lasterr -3004/-3005. Not the idle-death signature.

## 3. THE PROBABLE — HALF-OPEN ASSOCIATION (mode #5)

Mechanism, exact:
- AP silently drops the cart's association while idle (documented Giga/mbed + general
  WiFi behaviour; see Arduino forum + our own v231/v233 saga).
- `WiFi.status()` keeps reporting `WL_CONNECTED` — the half-open LIE.
- `wifiReconnectTick` keys off status, so it NEVER fires (line ~7144 returns early
  when status==CONNECTED).
- The accept loop keeps spinning, but `srv.accept()` returns WOULD_BLOCK forever
  because no packet ever arrives on the dead link.

Why the current HTTPX/SD row CANNOT see it — it looks identical to a healthy idle cart:
- alive_age  = SMALL  (loop spinning happily)
- served     = FLAT   (no accepts — but that is also true when simply idle)
- streak     = 0      (WOULD_BLOCK is the idle path, NOT an error)
- wifi       = 3      (the half-open lie)
- rssi       = some plausible value
=> Come back, UI dead, card says "all normal, just quiet." This IS the "no info".

This is the leading probable BECAUSE: it fires at idle (matches), needs no load
(matches), recovers only on reboot/power (matches "just broke"), and our prior
hunt (v231/v233) chased it with RSSI instead of association state and could never
force it — so it was never proven or removed.

## 4. THE DISTINGUISHING MEASUREMENT WE DO NOT YET RECORD

The single fact that separates half-open from healthy-idle and from clean-drop:
**"is the link actually carrying traffic, or only associated?"**

Cheap proxies already half-present in the firmware:
- `g_httpx_last_req_ms` (line ~6609, stamped at ~6743) — gives last_req_age.
- LINKDOWN / LINKUP soak logger (line ~3282) — brackets a REAL status drop.

Reading rule for the next idle-death, once instrumented:
- served FLAT + last_req_age HUGE + NO LINKDOWN logged  => HALF-OPEN (associated but
  dead — status never went non-CONNECTED, so reconnect never fired).
- LINKDOWN logged (then no LINKUP)                       => CLEAN DROP the reconnect
  should have handled (different bug — reconnect path).
- alive_age CLIMB + watchdog stale line                  => THREAD wedge / hard-fault
  (NOT this mode).

---

## 5. INSTRUMENTATION (preventative — so the NEXT idle-death self-identifies)

Goal: make the SD HTTPX row carry enough to tell half-open vs clean-drop vs
thread-wedge apart WITHOUT a laptop, the first time it happens again.

Add to the HTTPX SD row (and the serial httpxmon line):
1. **last_req_age** = millis() - g_httpx_last_req_ms — seconds since the last REAL
   accepted request. Huge + served-flat + wifi=3 = the half-open fingerprint.
2. **link-transition count / last LINKDOWN age** — so the row itself says whether a
   real status drop was ever seen. (The LINKDOWN/LINKUP rows already exist in the
   soak file; surface a counter in the HTTPX row so one row is self-contained.)

These two fields turn "all normal, just quiet" into a positive half-open ID. Small,
specific, common-sense — not speculative defensive code.

(Instrumentation is documented here but BENCH-FIRST per operator: prove the cause
before changing the logging shape, so the new fields are validated against a known
half-open event rather than guessed.)

---

## 6. BENCH TEST — FORCE THE HALF-OPEN (cause / remove / cause / remove)

Purpose: PROVE half-open is real and reproducible on THIS cart + AP, and capture its
exact signature, before any fix. Same shape as Trial1–10 but on the inbound :80 side.

### Setup
- Cart on RosedaleVan / 192.168.20.97, UI reachable, serial attached at the bench.
- A client polling the UI lightly (phone or a curl loop every ~3s) so "served" is
  advancing — establishes the healthy baseline.
- Serial open; optionally /debug/httpxlog?on=1 to see accept/idle lines live.

### CAUSE — force the association to drop WITHOUT a clean link-down
The whole point is to drop the association in a way that leaves WiFi.status() still
reading CONNECTED (the half-open lie). Candidate triggers, try in order, cheapest
first — we need ONE that reproduces:
- a) On the AX6000 admin page, deauth/kick the cart's MAC (client list -> remove),
     or toggle the 2.4GHz radio off for ~10–20s then on. A deauth often leaves the
     STA believing it is still associated.
- b) Power-cycle the AX6000 radio band only (not a full reboot) so the beacon stops
     briefly — the STA may hold CONNECTED through a short outage.
- c) Walk the cart to the association edge and back quickly (the v231 RSSI -88 case)
     — but this is the RSSI route we already know; prefer (a)/(b) which target the
     ASSOCIATION state directly, which is the actual mechanism.

### MEASURE — at the moment the UI goes dead, read on serial:
- Does `WiFi.status()` still return `WL_CONNECTED` (==3)? (the lie — confirm it)
- Does the accept loop keep printing "idle (waiting in accept)" / alive stamps, i.e.
  thread ALIVE, just no accepts?
- Does `wifiReconnectTick` FAIL to fire (because status==CONNECTED)?
- Capture g_httpx_last_req_ms growing while served stays flat.
If all true: half-open is CAUSED and identified. That is the proof the v231/v233
hunt never got.

### REMOVE — apply the fix and show the UI recovers without reboot
The mechanism the fix must break: status==CONNECTED but link dead for too long.
Lever (to be designed after the cause is proven — do NOT pre-build):
- a watcher that, when status==CONNECTED AND no accepted request for N seconds AND
  (optionally) a cheap liveness probe fails, forces WiFi.disconnect() so the NEXT
  wifiReconnectTick sees status!=CONNECTED and re-associates. (Groundwork already
  sketched around line ~7303; the v231 RSSI-floor version was backed out v233 for
  thrashing — the association/last-req trigger is the better signal.)
- Re-run the CAUSE step: confirm the UI now recovers on its own, no power cycle.

### CAUSE AGAIN / REMOVE AGAIN
Revert the fix, force half-open again, confirm it breaks again; re-apply, confirm it
recovers. Only when it toggles cleanly is it SOLVED. "If you cannot cause it you have
not solved it."

### Bench deliverable
A standalone bench sketch (soak_wifi_trial lineage) is NOT strictly needed here —
the cart firmware itself already has the accept loop + status + reconnect plumbing;
the bench is mostly the AP-side deauth procedure + serial reading. If a dedicated
sketch helps isolate (strip everything but the :80 accept loop + a status print +
g_httpx_last_req_ms), build it in the soak_wifi_trial pattern.

---

## 7. ORDER OF WORK (operator: bench first)
1. BENCH — force half-open by association-deauth, capture the signature, PROVE it is
   the idle UI-death cause (cause/remove not yet — first just CAUSE + identify).
2. Then design the REMOVE lever against the proven cause.
3. Then port the two SD-row fields (last_req_age, link-transition) so the field
   instrumentation matches what the bench proved.
4. cause/remove/cause/remove to declare solved.

## 8. OPEN / NOT YET RULED OUT (carry, do not chase yet)
- #937 idle-teardown stall (mbed core) — outbound side; less likely for an inbound
  idle-death but keep on the list.
- #4 MbedOS hard-fault (no auto-reset, 4-fast/4-slow red LED) — would show as log
  STOPS mid-file with the loop counter frozen; distinguishable once a per-row uptime
  counter exists. If the red LED was NOT seen at the cart, this is less likely.
