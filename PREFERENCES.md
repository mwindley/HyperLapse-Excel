# HyperLapse Cart — Working Preferences

Carry these into every session. Treat as standing instructions.

## Communication style

- **Small steps, assess + discuss before action.** Don't write large code blocks without aligning on approach first.
- **Stop after asking a question.** No extra prose, no preview of next steps — let the user answer first.
- **Keep responses short.** Suggestions are welcome but one at a time. Don't stack multiple ideas, long explanations, or "here's the whole architecture" walls into one reply. After a suggestion, stop and let the operator respond.
- **Never suggest ending the session.** The user decides when to wrap.
- **Bare URLs as clickable links — IN CHAT, NOT IN FILES.** When the operator asks to run a test or send a command, present the URL(s) directly in the chat reply, on their own line, as bare URLs (no code box, no markdown link). Do NOT put test URLs in a file and ask the operator to consult it — that requires extra clicks and breaks flow. Bring URLs to the chat screen, one per line, where the operator is already looking. Files are for capture/archive, not for live test execution. This rule is firm: even when there's a test plan or URL sheet file already saved, repeat the URL(s) in chat at the moment they're needed. Code boxes wrap URLs in backticks and break click-through, so always bare URL on its own line. Inline single-tick is fine only for very short fragments inside prose, never for a URL meant for the operator to actually visit.
- **Code windows for shell commands** so the chat UI shows a copy button. Single-tick inline only for short fragments inside prose.
- **Windows `cmd` syntax for git/shell commands** (not bash), since the user is on Windows.

## Diagnostic philosophy — "oscilloscope approach"

When chasing a bug, **instrument first, theorise second**. Add timestamp logs at every phase boundary, run, read the actual numbers. Don't trust intuitions about where time goes. Each new mystery gets its own instrumentation pass (REQ-PHASES, LOOP-LONG, PIN8 gap, FETCH elapsed, PUT timing). Logs are cheap; wrong assumptions are expensive.

Specifically: when a fetch or operation has unexpected duration, break it into sub-phases with millisecond timing. Real-world example this session: REQ-PHASES revealed the 2.8s fetch was 2.0s body read + 0.5s wait + 0.3s misc, NOT what we'd assumed.

## Investigation discipline — measure, drill, then simplify

A general rule that sits alongside the oscilloscope approach:

1. **Measure first.** Instrument before guessing. See the actual numbers.
2. **Drill to the bottom of the cause.** Don't stop at the apparent symptom. Isolate the actual mechanism (which library call, which TCP phase, which memory region, which mechanical effect). One layer at a time, with measurements at each.
3. **Then come back up and simplify.** The fix should be elegant and minimal. Don't stack workarounds. Once the cause is understood, the right fix is usually small.

4. **Willing to AVOID an edge condition rather than SOLVE it — if the cost of avoiding is low and the risk of avoiding is acceptable.** Not every bug needs a code fix. Sometimes "don't go there" is the right answer:
   - Bound the problem space rather than handle every case
   - Operator-in-the-loop instead of autonomous recovery
   - Conservative limits instead of dynamic adjustment
   - "Close all UI tabs during plan execution" instead of fixing WiFi saturation

   The bar for avoidance: the avoidance must be **cheap to apply consistently** (low operator friction) AND **low-risk if forgotten** (graceful degradation, not catastrophic). When both hold, avoid. When either fails, solve.

   Worked examples already embedded in the architecture:
   - "Photos sacred, never delayed; wrong exposure fixable in post" — avoid the perfectionist exposure-fix branch that risks the loop.
   - "Pin-8 must work when CCAPI is unreachable" — avoid the failure mode entirely by having a hardware fallback path.
   - "Distance tolerance is large; turn-at-spot and stop-before-hazard are not" — avoid the calibration depth for distance; operator-supervise the few hard cases.

The order matters. **Don't decide avoid-vs-solve until you've measured and drilled.** Otherwise you're guessing whether avoidance is safe.

## Architectural principles (sacred)

1. **Photos sacred, never delayed.** Pin-8 cadence is the heartbeat. Anything that blocks the loop more than a few ms is suspect.
2. **No photo fatal; wrong exposure fixable in post.** A dropped photo breaks the hyperlapse; a slightly-wrong exposure is fixable. Optimise for delivery, not for perfect exposure.
6. **Luminance changes per minute.** Sparse sampling is fine. Don't over-fetch.
12. **WiFi-dependent vs WiFi-independent separation.** Pin-8 must work even when CCAPI is fully unreachable. The hardware shutter is the failsafe.
13. **Tv + 1.5s cadence rule.** Photo interval = `ceil(Tv_seconds + 1.5) * 1000`, minimum 2000ms. Derived from real-world Excel table.

## Hardware/camera facts

- **Camera: Canon R3.** High-spec body, network-capable via CCAPI over WiFi at 192.168.1.99:8080. Pin-8 trigger is via the hardware shutter port (not USB or wireless).
- **Cart: Arduino Uno R4 WiFi** at 192.168.1.97. Runs all timing logic. WiFiS3 library is used for HTTP.
- **Red LED on camera = photo being taken.** 1:1 with successful pin-8 → shutter actuation. If pin-8 fires but no red LED, camera dropped the trigger.
- **Real-world baseline:** Excel-table-driven shooting (no CCAPI) = 0 photo loss across thousands of overnight shots. CCAPI fetches are the only source of photo drops.

## Known library quirks (Arduino Uno R4 WiFi / WiFiS3)

- `WiFiClient::setConnectionTimeout()` is **NOT honoured** for `client.connect()`. The default 10-second block applies regardless. Workaround: backoff after failure, not bounded connect.
- `delay(5)` in tight read loops over WiFi adds 5ms per iteration, which accumulates badly over 500+ TCP chunks. Use `delay(1)` and idle-timeout exit instead.
- Cart resets clear all state (`lum_fetch_disabled`, `fetch_delay_ms`, mode, init). Every flash or reset means re-running the full setup sequence.

## Standard test setup sequence

Always run in order before any timed test. Verify each response before moving on.

1. **CCAPI alive check** — should return JSON dump of endpoints
   ```
   http://192.168.1.99:8080/ccapi
   ```

2. **Exposure init** — must show `ok:true` AND correct `interval_ms`. Retry if needed; known transient.
   ```
   http://192.168.1.97/exposure/init
   ```

3. **Mode darken** (or skylight, depending on test)
   ```
   http://192.168.1.97/exposure/target?mode=darken
   ```

4. **Fetch delay** (for edge-finding tests; default 0)
   ```
   http://192.168.1.97/debug/fetchdelay?ms=0
   ```

5. **Delete card images** so delivery count is unambiguous.

6. **Camera state check:** Tv setting, lens cap, ISO, mode dial all match test plan.

7. **Start timer:**
   ```
   http://192.168.1.97/shutter/start
   ```

8. **Stop timer:**
   ```
   http://192.168.1.97/shutter/stop
   ```

9. **Report:** `photos_taken=N` from /stop, card count, serial output if anomalies.

## Useful debug endpoints

```
http://192.168.1.97/debug/fetch?on=0
```
Disables CCAPI fetch entirely. Use to isolate pin-8 reliability from fetch interference.

```
http://192.168.1.97/debug/fetchdelay?ms=N
```
Delays fetch start by N ms after pin-8 fires. Used for edge-finding (where in the cycle is the safe window).

## Arduino IDE workflow

- **Verify** (✓) only checks size — output ends with "Sketch uses N bytes". Does NOT flash the board.
- **Upload** (→) actually flashes — output includes "Erase flash / Write N bytes / [progress bars] / Done".
- If you only see the size summary, the flash didn't happen. Always confirm progress bars before running tests.

## Code style

- Comments above non-trivial logic explain the *why*, not the *what*.
- New constants live near related ones with a comment explaining purpose and chosen value.
- Diagnostic Serial.print lines tagged with module: `[lum]`, `[exp]`, `[shutter]`, `[cart]`, `[T+millis]` for time-critical events.

## Per-session deliverables

Each session ends with:
- Code committed to local git with descriptive message
- PROJECT_STATE.md updated with current behaviour, known issues, deferred items
- Transcript saved with summary header for future-session compaction
