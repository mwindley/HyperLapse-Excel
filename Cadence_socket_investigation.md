# Cadence + Socket Investigation (SOURCE OF TRUTH)

Day 36 bench investigation of the audible photo-cadence regression on the main
Giga. Method: Test9c/Test10 RAM-capture-over-WiFi (silent run into RAM, dump via
http://192.168.1.96/dump after - no Serial in the timed path, so no USB-CDC
stall confound). Tv=0.5s (0"5), ISO=100, 2s cadence, walk-compliant.

## What was RULED OUT (measured, not guessed)

- **Aperture/iris** - KILLED by a 6-run test (3x F1.8, 3x F2.5). F1.8 stalled in
  all 3 runs; F2.5 had the single cleanest run of all six. Both apertures stall
  both ways. The iris stop-down move is audible and real but is NOT the stall.
- **AF / focus** - camera is Manual focus (afoperation=manual) + af:false in the
  fire POST. No AF runs on the shutter press. "Out of focus" 503 impossible.
- **Drive overhead** - Single shot drive, no continuous/servo per-frame cost.
- **Card write** - card is 2TB, sustains 30fps continuous; far too fast to be the
  per-frame block at 0.5fps. "Can not write to card" ruled out by bandwidth.
- **Metering** - Evaluative; the flipdetail GET reads the full ~5.5KB histogram
  in ~55-150ms EVERY time the socket gets through. Never the stall.

## The TWO real faults (intermittent, separated by measurement)

### 1. recv-timeout = CAMERA busy (camera-side, ~800ms)
connect OK + send OK, then recv gets ZERO bytes until the 800ms timeout
(firmware recv loop: set_timeout(800), 4000ms wall cap). status=0, fail_phase=4,
conn_err=0. The camera accepted the connection and request, then went silent.
- Persists ~3s: a post-stall probe burst (cheap GET tv back-to-back) showed the
  camera stays dark ~2-3s, then recovers SHARPLY (silent, silent, clean 200) -
  not gradual. Even the cheap GET gets nothing during the window.
- The pre-fire GET proved the camera is sometimes ALREADY dark before the fire
  (G stalls before F) - so the fire does not always trigger it; the fire can
  just land in an existing dark window.
- Hits state-changing POSTs (shutterbutton fire, liveview-start) AND, once the
  window is open, anything sent - including the GET. Outside the window all calls
  are fast.

### 2. connect -3004 (NO_MEMORY) = mbed SOCKET POOL (Giga-side, can be many sec)
connect returns NSAPI_ERROR_NO_MEMORY (-3004) - the mbed pool could not give a
socket. This is OUR side, not the camera; the request never left the Giga.
- Distinct from a slow-but-successful connect (which can also take seconds on
  mbed and is documented in firmware - set_timeout does NOT bound connect()).
- Appears in some runs, absent in others. Alternates with the recv-timeout fault
  run to run - they are two different things.

A 503 ("device busy") is a THIRD, benign thing: clears in ~20ms on one retry.

## The POOL is 4 (proven) and the test HOLDS it

- mbed TCPSocket pool = exactly 4 (boot probe: open #5 -> -3005, both Gigas).
  Matches firmware v205 finding.
- Test9c probes the pool at boot AND end-of-run: a clean run shows
  pool_start=4, pool_end=4, NO LEAK - every ccapi() close() freed its slot.
- Test demand during the run = 1 socket at a time (single-threaded, open/use/
  close per call). During the dump = 2 (listen + one accept). Both under 4.
- A clean run posts conn_-3004=0, open_fail=0, open_retried=0, recv_timeout=0 -
  neither fault fired. The faults are SPORADIC, not steady-state.

## Firmware work that keeps the cart under the 4-limit (prior sessions)

- v205 listen backlog 2->1: frees one permanent slot (listen(1) + 1 serialized
  outbound CCAPI = 2, leaving headroom). The single biggest fix.
- #ccapi-serialize: one mutex (g_ccapi_mtx) caps outbound CCAPI sockets at 1;
  fire uses a non-blocking trylock so the photo loop never waits.
- #sockretry: open() retries 4x/30ms when the pool is momentarily full.
- v208/210/213 #pollserialize: UI screens chained their 3 parallel pollers into
  one sequential poller - no parallel sockets at page load.
- v206: HTTP watchdog made observe-only - it was rebinding :80 and leaking a
  pool slot per cycle (the root cause of the 3-day regression).
- v207 free_slots probe REMOVED: opened 6 sockets per error to count slots, drained
  the pool itself. Lesson: probe the pool at the ENDS (boot/end-of-run), never
  per-error in the hot path.

## HEALTHY BASELINE (clean run, the number to compare a regression against)

- Fire (POST shutterbutton): ~100ms (connect 2-3ms, recv 30-160ms).
- Meter (GET flipdetail): ~140ms (connect 50-90ms, recv 55ms, ~5.5KB body).
- GET tv (cheap probe): ~12-100ms (recv ~5-11ms, ~624B body).
- In-run connect: 2-191ms. recv: 5-163ms.
- A STALL = recv hits 799 (camera silent, st=0) OR connect returns -3004 (pool)
  OR connect blocks multiple seconds (slow mbed connect).

## Cold-start (separate, consistent)
The FIRST CCAPI call after boot/fresh-state has a slow connect (seen 5841, 11781,
14857, 17827ms). Shows in nearly every run on the cold ISO PUT. Separate
mechanism from the in-run stalls; everything after it (when clean) is fast.

## Test method notes
- RAM capture + WiFi /dump is the proven method (Serial.print blocks on Giga USB
  CDC and halts the sketch on PuTTY attach - looks identical to a socket stall).
- Test9c now matches firmware ccapiRequestRawSocket EXACTLY: open-retry 4x/30ms,
  connect set_timeout(2000), recv loop set_timeout(800)+4000ms cap+Content-Length
  early-stop, body {"af":false}, liveview started once (not per-frame).
- Walk order: 2s interval clock (not delay-after-work), meter (flipdetail GET)
  before the fire every 3rd frame, fire last, nothing after.
- Instrumentation: per-call open/connect/send/recv/close ms + status + recv
  bytes + open_tries + fail_phase + t_start; per-verb rollups; pool start/end
  leak check; post-stall probe-burst edge; pre-fire GET responsiveness probe.

## ===== W5500 WIRED TEST - THE DECISIVE RESULT (Day 36) =====

**Question (48hr): is the cadence regression a CHANGE we made, or a change that
REVEALED something? The wired test isolates the LAYER.**

### Test
Test9d_Wired.ino: same trace+measure sketch as Test9c, but ccapi() moved from
WiFi (mbed TCPSocket) to W5500 wired EthernetClient (the blue cable Giga<->camera).
Single-buffer client.write() (#wire-onebuf). Camera .20.99, Giga W5500 .20.98,
CS=D10, MAC DE:AD:BE:EF:FE:ED. WiFi dump server UNCHANGED (Giga stays on WiFi
.1.96; only the camera transport moved to the cable). 30s startup hold + Serial
countdown (flashing power-cycles the W5500, dropping the camera link; the camera
needs time + CCAPI re-enable). Ran at BOTH 5s and 2s cadence, probe off.

### Result: THE WIRE IS CLEAN AT BOTH CADENCES
| metric            | WiFi 5s (prior) | WIRED 5s | WIRED 2s |
|-------------------|-----------------|----------|----------|
| connect avg / max | 282 / 8672      | 16 / 1002| 16 / 1002|
| recv-timeouts     | 3               | 0        | 0        |
| slow-connect >2s  | 4               | 0        | 0        |
| meter (flip) avg  | ~1151           | 57       | 58       |
| cadence gaps      | blew to 16498   | 4897-5153| 1945-2098|
| stalls (excl cold)| many            | 0        | 0        |

Every wired connect 0-1ms. Fire 31-151ms. Flip a flat 55-61ms. Zero recv-timeouts,
zero slow-connects, cadence dead-on at both 2s and 5s. The only blemish is frame 1
(cold-start fire, st=0, recovered via pin-7 P probe - the documented first-frame
loss; conn_other=1 is this). Everything from frame 2 on is 100%.

### BYTES ARE IDENTICAL ACROSS TRANSPORTS - only timing differs
Per-frame byte counts match exactly: fire sends ~170, gets 102 back (empty {}).
flip sends ~113, gets back the ~5.5KB YRGB histogram (wired 5537, WiFi 5671 - same
payload). The camera sends/receives the SAME bytes on both. Wired delivers them in
43-151ms every time; WiFi delivers the SAME bytes but intermittently takes
1900-4900ms or fails - frame 7 WiFi get got 0 bytes (recv-timeout); frame 9 WiFi
flip got only 3870 of ~5500 (TRUNCATED mid-transfer). Wired always gets the full
~5530.

### What this PROVES (measured, not theorised)
1. **The stalls are WiFi transport. NOT the camera, NOT the Giga socket logic.**
   Same camera, same walk, same cadence, same Tv, same bytes - the wire is perfect.
2. **The metering-timer / idle / keep-alive theory is DEAD.** Wired 5s (long idle)
   is as clean as wired 2s. If the camera went dark from idle, wired 5s would stall.
   It doesn't. The camera was NEVER going dark - WiFi failure only LOOKED like the
   camera going dark (zero bytes / truncated reads = WiFi dropping the response).
3. **Cadence length is irrelevant on the wire.** 2s and 5s equally perfect. The
   "busiest case" (0.5s/2s) and the idle theory are both off the table.

### STILL OPEN (the 48hr question, now precise)
The wire isolates WHERE (WiFi transport) but not WHY. Rosedale worked during
hardened testing 4 days ago; the same Rosedale is stally now. So: did a change in
the CURRENT WiFi request path make WiFi slow, or did a change REVEAL a latent WiFi
issue that now affects WiFi generally? Rosedale is constant; the WiFi behaviour
differs from 4 days ago. NEXT: diff the current sketch's WiFi path vs the hardened
version (open-retry, recv-loop timeouts, liveview-once, WiFi stack handling).

### Production note
Firmware already supports the wired camera transport as a COMPILE-TIME switch
(#define STUB_WIRED_ETHERNET defined = WiFi .1.99; undefined = W5500 wired .20.99).
The wired path is proven solid (this test + v78-v94). Moving the camera to the
cable in production is an available, measured-clean option.
