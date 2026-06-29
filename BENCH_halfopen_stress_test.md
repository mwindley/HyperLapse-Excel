# BENCH STRESS TEST — Half-open association (idle UI-death)

Model: STRESS the suspected failure mode hard (harder than the field).
- Failure appears under stress  => PROVEN (then remove/cause/remove).
- Failure does NOT appear        => not proven, but PROACTIVE (mode ruled down,
                                     instrumentation in place for the real one).

## THE TRAP WE MUST NOT REPEAT (v231/v233)
Old mistake: "move further away, watch things fail at low RSSI."
- Low RSSI far out failing = EXPECTED physics, not the bug.
- It CONFLATES two failures: genuine weak-signal loss vs the half-open bug.
- You can prove NEITHER, because RSSI is an uncontrolled variable.

THE BUG (half-open) is: association dies but WiFi.status() still == WL_CONNECTED,
so wifiReconnectTick never fires and the cart never recovers. THIS CAN HAPPEN AT
GOOD RSSI. The only clean proof is to force it WHILE RSSI IS STRONG, so signal
strength is explicitly excluded as the cause.

## GUARD RAIL (built into the procedure)
- Cart sits STILL at a STRONG-RSSI spot for the whole test. Target RSSI -50..-65.
- RSSI is read and logged EVERY cycle. If RSSI drifts below ~-70, STOP — you have
  reintroduced the propagation variable; move the cart closer and restart.
- Association is attacked AT THE AP (deauth / radio toggle), NOT by moving the cart.
- A failure only counts as "half-open proven" if it occurs with RSSI in the good band.

## SETUP
- Cart on RosedaleVan / 192.168.20.97, sitting still at a strong-signal spot.
- Confirm good RSSI first:  http://192.168.20.97/status   (or the boot serial RSSI)
- Serial attached. Turn the accept/idle trace on:
    http://192.168.20.97/debug/httpxlog?on=1
- A light client poll so "served" advances (healthy baseline): phone on the UI, or a
  curl loop every ~3s from the laptop.
- AX6000 admin page open (client list / 2.4GHz radio control).

## STRESS LOOP (tight, repeated — this is the hammer)
Repeat 20–50 times, fast cadence, logging each cycle:

  CYCLE n:
  1. Record RSSI (must be in the good band — if not, STOP, move closer, restart).
  2. Confirm UI alive: served is climbing, page responds.
  3. ATTACK ASSOCIATION AT THE AP (pick one, keep it consistent across the run):
       a. Kick the cart's MAC from the AX6000 client list (deauth), OR
       b. Toggle the AX6000 2.4GHz radio OFF ~10-15s then ON.
     (Both kill association while the cart is at strong signal. Prefer the one that
      most reliably leaves the cart's WiFi.status() reading CONNECTED.)
  4. WATCH THE CART for ~30-60s and record, at the moment the UI goes dead:
       - WiFi.status() value  — is it still 3 (WL_CONNECTED)?  <-- the half-open LIE
       - accept loop          — still printing "idle (waiting in accept)" / alive
                                 stamps? (thread ALIVE, just no accepts)
       - wifiReconnectTick     — does it FIRE, or stay silent because status==CONNECTED?
       - served               — frozen? last_req age growing?
       - RSSI                 — still good? (confirms it is NOT a weak-signal failure)
  5. Recover (re-enable radio / let it re-associate) and go to next cycle.

## PASS / FAIL (unambiguous, RSSI excluded)
- HALF-OPEN PROVEN:
    At GOOD RSSI, after an AP-side association kill, the cart shows:
    status==3 (CONNECTED lie) + accept loop alive + reconnect NOT firing + served
    frozen + UI dead, requiring reboot/forced-disconnect to recover.
    => This is the idle UI-death cause. RSSI was good, so propagation is excluded.

- NOT THIS BUG (proactive rule-out):
    At GOOD RSSI, every forced association kill is followed by a clean recovery
    (status goes non-CONNECTED -> wifiReconnectTick fires -> re-associates -> UI back),
    across all cycles. => Half-open is NOT the field idle-death; move down the list,
    keep the instrumentation for the real one.

- INVALID (the old trap — do NOT count):
    Any failure that occurs while RSSI is poor. That is the weak-signal confound;
    discard it, move the cart closer, restart.

## IF PROVEN — then (separate step, do NOT pre-build)
- Design the REMOVE lever: a watcher that, when status==CONNECTED AND no accepted
  request for N seconds (g_httpx_last_req_ms) AND optionally a cheap liveness probe
  fails, forces WiFi.disconnect() so the NEXT wifiReconnectTick re-associates.
  (The v231 RSSI-floor version thrashed and was backed out v233 — the
   association/last-req trigger is the correct signal, NOT RSSI.)
- cause/remove/cause/remove to declare solved.

## THEN — port the field instrumentation (so natural failures are caught too)
- Add last_req_age + link-transition to the HTTPX SD row, validated against the
  bench-proven signature.

---

# AMENDMENT — anchor to the Trial1-10 baseline + method (25/6)

## Run at the PROVEN OPERATING ENVELOPE, not an artificial cadence
The "gaps that let mbed succeed" are the real operating point, not arbitrary:
- 0.5 Tv steps, 2-second cadence, the established action order (meter pre-fire on
  idle camera -> fire -> rest; the v90 #reorder order), a plan ticking.
- Run the bench AT that envelope so it stresses the RIGHT mode inside the KNOWN-GOOD
  rhythm. Do NOT hammer with no gaps: mbed/lwip on this Giga is known fragile under
  tight back-to-back load (#937 every-5th-connect, pool-of-4 contention). A no-gap
  hammer induces a COMPOUND failure (pool exhaustion + reconnect thrash + accept
  storm tangled) that proves nothing. The field is mostly idle with occasional real
  drops - test THAT.
- One association kill, then FULL recovery + settle (status CONNECTED, served
  climbing, RSSI good, a few clean cycles) BEFORE the next kill. One kill, one clean
  recovery window, one observation. A failure then = one clean drop from a settled
  state at good RSSI = the actual field condition.

## THE BENCH IS A DIFFERENTIAL TEST (keep this approach - do NOT discard)
The bench is almost the field on the main sketch, but with OTHER time-users stripped
out. That isolation is the value:
- Bench FAILS (half-open at good RSSI from settled state) -> PROVEN, even isolated.
- Bench PASSES but FIELD FAILS -> the cause is NOT half-open itself; it is something
  ELSE that uses time in the real sketch that the bench removed. That delta is a
  CAUSABLE lead: add the stripped time-users back one at a time until it fails. This
  is "the thing I can cause to follow up on." Do not throw it away - the isolation
  HANDS you the next probable.

## READ THE FAILURE VIA RAM CAPTURE, NOT LIVE SERIAL (Test10 method)
CRITICAL - this is the proven method from Trial1-10:
- On the Giga, Serial.print blocks on USB CDC flow control; attaching PuTTY mid-run
  can halt the sketch, and a SERIAL stall then reads IDENTICAL to a socket/link
  stall. Test9c hit exactly this confound.
- Test10 fixed it: capture the timed/state data into RAM during the silent run, dump
  it over the WiFi /dump endpoint AFTER. That is the only trustworthy readout for
  this stack.
- For half-open: capture into RAM, per cycle: WiFi.status(), millis()-g_httpx_last_req_ms
  (last_req_age), g_httpx_served, g_httpx_accept_streak, g_httpx_alive_ms age, RSSI,
  and any LINKDOWN/LINKUP transition. Dump over /dump (or /soak) after. Do NOT rely
  on watching it live on serial - that can manufacture the very stall you are hunting.

## TRIAL1-10 BASELINE NUMBERS (the success bar to measure against)
Wired W5500 CCAPI, proven clean (the envelope the cart runs all night):
- connect avg/max: 16 / 1002 ms     (WiFi prior was 282 / 8672)
- recv-timeouts: 0                   (WiFi: 3)
- slow-connects >2s: 0               (WiFi: 4)
- meter/flip avg: 55-61 ms           (WiFi: ~1151)
- cadence gap at 2s: 1945-2098 ms    (WiFi blew to 16498)
A half-open event must be read against THIS baseline: if the cadence/cadence-gap and
connect numbers stay in-band but the UI is dead, the failure is in the LINK/accept
layer (half-open), not the fire/CCAPI layer (which Trial1-10 already proved clean).

## METHOD PROGRESSION (for reference)
Test9 (WiFiClient) -> Test9b (TCPSocket, firmware-identical) -> Test9c (serial,
CONFOUNDED) -> Test10 (RAM capture + WiFi dump, CLEAN). Use the Test10 method.
