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

## Asking for input — NO MULTI-CHOICE, REMEMBER PREFERENCES

The operator has stated, repeatedly and with rising frustration, that he does not
like the multi-choice question widget. Stop using it. Even when this CLI has a
nice-looking tool for asking questions with selectable buttons, **do not use it**
for this project. Ask in plain text. Wait for a plain-text answer.

Specific failure modes Claude has fallen into this session that operator has
called out, repeatedly:

1. **Multi-choice in lieu of a real conversation.** Claude reaches for the
   selection tool whenever it could just ask a question in prose. The result
   is that operator must pick from Claude's pre-baked options instead of
   answering in their own words. Operator's reply often doesn't fit any of
   the options — they then have to either pick the closest one (wrong) or
   write a plain-text answer (which makes the multi-choice tool a waste).
   Ask the question in plain text. Let the operator answer in plain text.

2. **Forgetting the preference within the same conversation.** Operator says
   "stop with multi choice" → Claude apologises → Claude asks the next
   question with multi-choice anyway. This is the strongest version of the
   pattern operator was warning against. **When the operator states a UI
   preference, the next Claude reply must demonstrate that preference is
   being held.** No backsliding. No "just this once, the question is
   complex." Plain text from then on, unconditionally.

3. **Stacking the question half in prose half in widget.** Operator: "half my
   answer is in text other in you reply panel." When Claude writes a long
   prose summary of options and ALSO presents a multi-choice widget, the
   operator's answer ends up split across the two — referencing items in the
   prose that aren't in the widget, or vice versa. Pick one or the other.
   For this operator: pick prose.

**The rule, written firmly:**

- **No multi-choice tool calls** unless the operator explicitly invites them
  ("give me options") in the immediately-preceding message.
- **Plain-text questions** — one question, at most a sentence or two, then
  stop and wait.
- **No bullet-list-of-options-disguised-as-prose either.** "Should we do X,
  Y, or Z?" with three named choices is the same anti-pattern in prose form.
  Frame as an open question: "What do you want here?" or "How should this
  work?"
- **Preferences once stated are sticky for the whole conversation.** If
  operator says "no X" at any point, X never appears again in this session.

## Diagnostic philosophy — "oscilloscope approach"

When chasing a bug, **instrument first, theorise second**. Add timestamp logs at every phase boundary, run, read the actual numbers. Don't trust intuitions about where time goes. Each new mystery gets its own instrumentation pass (REQ-PHASES, LOOP-LONG, PIN8 gap, FETCH elapsed, PUT timing). Logs are cheap; wrong assumptions are expensive.

Specifically: when a fetch or operation has unexpected duration, break it into sub-phases with millisecond timing. Real-world example this session: REQ-PHASES revealed the 2.8s fetch was 2.0s body read + 0.5s wait + 0.3s misc, NOT what we'd assumed.

**When chasing software, compare against a known-good reference first.** A working intervalometer puts ~200ms pulses on the camera Shutter line and hits 100% delivery. Measuring that on the logic analyser, then comparing against the Uno+opto trace, would have identified the pulse-width difference on Day 11 if we had done it then. The lesson: when something works (intervalometer) and something similar doesn't (our sketch), measure both with the same instrument before chasing more complex hypotheses. (Day 12 worked example.)

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

## No guessing — name the cause anti-patterns

This section exists because Claude has, repeatedly, generated plausible-sounding causal stories with **zero supporting measurement** and presented them as if they were findings. Every such instance is a waste of operator time and worse, can lead to wrong fixes, wrong shopping, wrong workfronts. The Investigation discipline section above is the rule. This section is the enforcement: specific failure modes to recognise and stop.

**No causal claim without evidence. Ever.** "X happened, then Y happened, therefore X caused Y" is not evidence. It is post-hoc rationalisation. Temporal correlation is the weakest form of evidence and Claude must not present it as anything stronger.

### Anti-patterns Claude must catch in itself

1. **The plausible story.** Claude generates a mechanism that *could* explain what was observed, and writes it up as if it were the explanation. Examples from prior sessions: "bus fault damaged the transceiver" (no electrical analysis done), "heat killed the chip" (no temperature measured), "thermal feedback loop" (no current draw or junction-temp data). If the sentence contains "likely", "probably", "must have", "presumably", or "the mechanism is" — and there is no measurement on the table — DELETE the sentence and replace with "cause unknown."

2. **Pile-on speculation.** When one guess gets pushback, Claude generates a *different* guess to replace it, instead of stopping. This is worse than the first guess because it gives the impression that investigation is happening when only more storytelling is. The correct response to a rejected guess is "I don't know, what would we need to measure?" — not a new guess.

3. **Inventing facts from search results.** Claude reads a search snippet, infers a plausible-sounding number (price, spec, comparison), and presents it as fact. Examples: "~$11 AUD" when no price was in the source, "better ESD protection than X" when no comparison was made, "leave termination ON to match" when nothing in the source supports that recommendation. If the source did not state it, Claude did not learn it. Verify or omit.

4. **Datasheet-free assertions.** Statements about hardware behaviour — "this chip runs hot under polling", "the transceiver is rated for X", "frames are getting through" — require the datasheet open in front of Claude, not vague memory of a prior session's note. Look up the spec, quote the spec, then reason from the spec. The Day-8 note about a "warm transceiver" is a single anecdotal observation, not a thermal spec, and cannot be used as a premise for any further reasoning.

5. **Asking the operator to choose between guesses.** Claude offering multiple-choice questions where every option is speculative is laundering uncertainty through the operator. The operator should not be asked to pick which guess to believe. The correct option is "stop, measure, return when there is data."

### What to do instead

When the operator asks "why did X happen" and Claude does not have measured evidence:

1. State plainly: **"I don't know. I have no measurements that distinguish between possibilities."**
2. List what *would* distinguish (e.g. "to know if heat killed the chip, we would need surface temperature under load; if bus voltage damaged it, we would need a scope trace of CANH/CANL during the suspected event").
3. Stop. Wait for the operator to decide whether to invest in those measurements.

It is never wrong to say "I don't know." It is often wrong to fill that gap with a story.

### What counts as evidence

In descending order of strength:
- Direct measurement of the suspected mechanism (oscilloscope, multimeter, thermocouple, log timing data, byte-level dump)
- Datasheet specification covering the operating regime in question
- Reproducible observation under controlled conditions (same setup, same trigger, same outcome multiple times)
- Single observation matching a known failure mode documented elsewhere
- Temporal correlation alone — **not evidence**. Mention it as a starting point for investigation, not as a conclusion.

### Recognising "I am about to guess"

Internal cues for Claude to catch itself:
- Reaching for "most likely" / "probably" / "the cause is" — STOP, check if there is measurement
- Generating a confident-sounding explanation within seconds of the question being asked — STOP, the explanation arrived too fast to have been derived from evidence
- Building on a prior session's anecdotal note as if it were a measured fact — STOP, re-read the note for what it actually says
- Filling silence rather than waiting — STOP, silence is fine, the operator can ask again

When in doubt: short reply, "cause unknown, here is what would tell us." Always.

## Architectural principles (sacred)

1. **Photos sacred, never delayed.** Pin-8 cadence is the heartbeat. Anything that blocks the loop more than a few ms is suspect.
2. **No photo fatal; wrong exposure fixable in post.** A dropped photo breaks the hyperlapse; a slightly-wrong exposure is fixable. Optimise for delivery, not for perfect exposure.
6. **Luminance changes per minute.** Sparse sampling is fine. Don't over-fetch.
12. **WiFi-dependent vs WiFi-independent separation.** Pin-8 must work even when CCAPI is fully unreachable. The hardware shutter is the failsafe.
13. **Tv + 1.5s cadence rule.** Photo interval = `ceil(Tv_seconds + 1.5) * 1000`, minimum 2000ms. Derived from real-world Excel table.
14. **Uno R4 is current; Giga R1 is held in reserve.** Arduino Uno R4 WiFi is the cart's current controller and is sufficient for everything built so far. Giga R1 migration (workfront #22) activates only when a specific design need genuinely outgrows the Uno — SRAM exhaustion, WiFi capacity limits, computational load that doesn't fit, or a feature requiring more I/O than Uno provides. Don't migrate proactively for headroom; migrate when a specific workfront demonstrates Uno is the blocker. Ask the question at design time: *"does this break the Uno?"* If yes → Giga migration becomes part of the work. If no → stay on Uno.

15. **Visualisation > Manipulation.** A clear visualisation of what the operator did is more valuable than a tool to mathematically clean it up. Operator's eye + redrive is simpler than algorithmic smoothing, and avoids the drift / knock-on / trust-breach problems that come with edit-after-the-fact operations on integrated state. When evaluating "should we build a thing that edits / cleans / fits operator output?", first check whether *seeing it clearly* is enough. Operator usually wants to know "did I do that right?" — a clear chart answers that without changing the data. Worked example: #44 Smooth Selection (day 10) — built end-to-end, mathematically correct, but rejected because smoothing rows i..j shifted downstream (x, y) positions and broke the operator's mental model. The trace chart with row labels (kept) is more valuable than the smoother that was removed.

## Build lessons (carry forward)

VBA / Excel gotchas captured across sessions. Worth knowing before debugging from cold:

1. **VBA line continuations capped at ~24 per logical line.** Long `Array(Array(...), ...)` literals fail to compile. Use row-by-row assignment to a pre-sized array instead. (Day 9 late evening, Formula.bas build.)

2. **Excel parses cell strings starting with `==` as formulas.** Section headers like `"== Sunset Tv crossovers =="` raise runtime error 1004 on write. Use `--` or prefix with apostrophe. Error message doesn't hint at this. (Day 9 late evening.)

3. **`With Range.Cells(r,c)` blocks** can fail with 1004 after recent operations on adjacent cells, even when direct `range.Cells(r,c).property = ...` works on the same cell. Direct access is more robust. (Day 9 late evening.)

4. **`Application.Run` requires module-qualified macro names across modules.** `Application.Run "btnFoo"` fails silently with "Cannot run the macro" if `btnFoo` is in a different module than the caller. Use `Application.Run "ModuleName.btnFoo"`. Failure mode is silent: `RunButton` catches the error, paints yellow, logs to BTN — no MsgBox. Check the Log sheet for diagnosis. (Day 10.)

5. **`SelectionChange` handler is the right way to stash operator's selection across button clicks.** A button-cell double-click changes live `Selection` out from under the triggered macro. Pattern: in the sheet's code module, `Worksheet_SelectionChange` writes the data-row selection to a Public module-level variable in a `.bas` module; the button macro reads from there. (Day 10.)

6. **Cross-module Public variables in `.bas` modules > custom sheet properties.** Generic `Worksheet` type doesn't resolve custom sheet code-module members at compile time. A Public variable in a standard module is cleaner. Naming convention `gLastSomething` for module-level Public state. (Day 10.)

7. **Excel data labels: `InsertChartField msoChartFieldRange` is the way to link labels to a cell range.** `.DataLabels(i).Text = ""` does NOT suppress a label — Excel falls back to showing the value. Correct pattern: `.HasDataLabels = True`, `.DataLabels.ShowValue = False`, `.DataLabels.ShowRange = True`, then `.Format.TextFrame2.TextRange.InsertChartField msoChartFieldRange, "='Sheet'!$H$2:$H$N", 0`. Blank cells in the source range produce blank labels. (Day 10.)

8. **Excel auto-converts time strings on write.** Writing `"00:00:05"` to a Number-formatted cell stores `5.787E-05` (a day fraction). Set `Columns(1).NumberFormat = "@"` **before** writing rows, not after. (Day 10.)

9. **Canon R3 shutter pulse needs 200ms LOW, not 100ms.** The chronic drops at 2s cadence (70-74% delivery, attributed to "CCAPI stress" on Day 11) were caused by the production sketch driving pin 8 HIGH for only 100ms. The manual intervalometer that hits 100% delivery uses 200ms LOW pulses. Verified Day 12 with 7 runs spanning zero-CCAPI to full Day-11 stress condition, then re-verified end-to-end on production: Tv=0.5"/2s + luminance every 3rd = 38/38 photos. `backupShutter()` drives pin 8 HIGH for 200000 microseconds, not 100000. (Day 12.)

10. **USB cable quality can manifest as WiFi / HTTP latency.** Early Day 12, multi-second HTTP response times on the test Uno were resolved entirely by swapping the USB cable. A flaky cable causes power brownouts that destabilise the ESP32 WiFi co-processor on the Uno R4 without obvious failure. If a fresh-flashed sketch behaves dramatically worse than production on the same hardware, swap the USB cable before chasing sketch bugs. (Day 12.)

11. **JS embedded in `client.println("...")` C++ strings — escape levels multiply, easy to over-escape into a parser error.** Each apostrophe / backslash inside a JS string literal inside a C++ string literal gets two layers of escaping (C++ first, then JS at parse time). A `\\'s` written intending `'s` inside JS instead produces a literal backslash followed by a string-terminating apostrophe — JS syntax error, **entire script dies silently**, only symptoms are downstream features not working (live polling stuck, no event handlers wired). The bug location can be far from the visible symptom: a Day-16 alert-string typo in `showAstro()` (a stub never called) killed the unrelated live-readout poll loop. Mitigation: prefer JS strings without apostrophes when embedding in C++ (rewrite "today's" as "today" / "the day's"); test served HTML in a browser dev console at least once per substantial UI change to surface syntax errors immediately; treat "feature X is broken but the code looks right" as a possible JS-parse failure elsewhere in the script. (Day 16.)

## Hardware/camera facts

- **Camera: Canon R3.** High-spec body, network-capable via CCAPI over WiFi at 192.168.1.99:8080. Pin-8 trigger is via the hardware shutter port (not USB or wireless).
- **Cart: Arduino Uno R4 WiFi** at 192.168.1.97. Runs all timing logic. WiFiS3 library is used for HTTP.
- **Red LED on camera = photo being taken.** 1:1 with successful pin-8 → shutter actuation. If pin-8 fires but no red LED, camera dropped the trigger.
- **Real-world baseline:** Excel-table-driven shooting (no CCAPI) = 0 photo loss across thousands of overnight shots, **using a manual intervalometer with 200ms LOW pulse**. Earlier CCAPI shoots with the cart's 100ms pulse showed 70-74% delivery; Day 12 identified the 100ms pulse width (not CCAPI activity) as the cause. With 200ms pulse, CCAPI-active shooting also delivers 100% (Day 12 end-to-end verified). The intervalometer's 200ms pulse is the project's reliability reference.

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
