# Day 11 — Session Summary

## Workfront: edge condition testing on photo capture at 2-second cadence

The cart fires pin-8 every 2 seconds; the camera saves only 70-74% of those
photos. Today's session set out to find **the edge of the stress condition** —
the boundary between settings where the camera delivers reliably and settings
where it drops photos. The 2-second interval is not optional: per Appendix A
of EXPOSURE_FALLBACK.md, the dominant operating mode of a hyperlapse spans
~4 hours of 2s-interval shooting (sunset+sunrise), about 7,200 photos per
event. A 30% drop rate there is not survivable.

## What edge condition testing means in this project

An edge condition is the boundary between a working configuration and a
failing one. Finding the edge requires:

1. **Hold all variables sacred except one.** Identify what's allowed to
   change (the swept variable) and what isn't (Tv, interval, +1.5s rule,
   lens cap state, mode). Everything else stays exactly the same across
   runs, or comparison is meaningless.

2. **Move the swept variable in steps from a known-failing point toward
   a known-working point** (or vice versa). The edge is the value at which
   delivery transitions.

3. **Measure delivery against the cart's fire count, not just the photo
   count.** Cart fires are the test signal; saved photos are the response.
   The ratio is what's measured. Cart-side cadence is independently verified
   via the gap histogram in the PIN8 log lines.

4. **Pair-up per fire, not summary.** Counts hide phase information.
   A 70% delivery summary doesn't tell you whether drops cluster or scatter,
   whether they correlate with the swept variable's transitions, or whether
   they self-cluster regardless of what's swept. The pair-up script
   `pair_fires_to_photos.py` matches each PIN8 fire against EXIF
   DateTimeOriginal and prints DROP for unmatched fires. The output
   is the diagnostic surface, not the summary.

## Reading everything before responding

Today opened with the discovery that previous sessions' "CCAPI on" tests
weren't testing CCAPI at all — a `T1b` test flag committed in the sketch
suppressed live view start in two places. The signal was visible in the
code (literal `*** T1b TEST ONLY — REVERT AFTER TEST. ***` comment),
and visible in transcripts as the absence of FETCH log lines, but went
undiscovered because the code wasn't read end-to-end before each session's
hypothesis. The four "Read before responding" preferences added today
(now expanded to eight) capture this discipline:

1. **Read the .ino fully when it's in play.** Grep finds keywords; reading
   finds existing mechanisms, committed test flags, and the structural
   decisions that make a proposed change unnecessary.
2. **Read the .md files fully when they're in play.** Appendix A in
   EXPOSURE_FALLBACK.md exists; its 71 rows of 2s-interval shooting are
   the project's operating mode. The +1.5s rule is derived from it.
3. **Read existing logs and counters before proposing new instrumentation.**
   PIN8, PULSE, FETCH, REQ-PHASES, LOOP-LONG, ANCHOR all exist.
4. **Capture full transcripts, not excerpts.** PuTTY logging now in place.
5. **No hypothesis without a measurement to support or refute it.**
6. **Critical-thinking checklist before responding to a measurement.**
7. **Use every column the measurement collected.** EXIF CSV has 8 columns;
   today used 2. ExposureTime, ISO, BrightnessValue, GPS sit unused.
8. **Correlate against the actual variable, not just the count.**
   Bucket counts hide phase information.

## What was done today

**Tooling:**
- T1b reverted in both places — live view now starts properly with /shutter/start
- New runtime knobs: `/debug/fetchevery?n=N`, `/debug/pathlog?on=N`,
  `/debug/liveview?period=N&window=N`
- Run-stats summary added then removed (RAM exhausted on Uno R4; freed by
  reducing CCAPI response buffer from 6KB to 4KB)
- Live view cycling state machine — opens streaming for `window_ms` every
  `period_ms`, closes between. Two CCAPI calls per cycle. Word "streaming"
  adopted to mean live-view-on + luminance-fetching.
- PuTTY serial logging working end-to-end with substitutions like
  `&Y&M&D&T` for unique filenames
- `pair_fires_to_photos.py` matches PIN8 fires to EXIF photos. Compact
  burst notation in output (e.g. `20-30,38,44-46`)
- Word adopted: **recovery gap** = interval - Tv. The time between end of
  exposure and start of next exposure. The camera-side rest period.

**Three CCAPI sweep runs at fixed Tv=0.5", interval=2000ms, cap on,
mode=darken (the stress condition):**

| Run | CCAPI variable | Actual fetches | Delivery |
|---|---|---|---|
| 1 | fetch_every_n=3 | 27 | 57/81 = 70.4% |
| 2 | fetch_every_n=30 | 3 | 77/108 = 71.3% |
| 3 | Streaming cycling 3s/30s | 0 | 89/121 = 73.6% |

**Finding 1: CCAPI traffic is not the stressor.** Reducing fetches from
27 to 0 across three runs produced delivery rates within 3% — flat. The
stress is camera-internal.

**Finding 2: drops are not random.** All three runs show bursts of 2-10
consecutive drops separated by recovery periods of 6-46 seconds. Pattern
is irregular (not periodic).

**Finding 3: streaming windows don't correlate with bursts.** Run 3's 10-fire
burst (PIN8 #71-80) spans 20 seconds and crosses an OPEN/CLOSED streaming
boundary. The streaming state of the camera at fire time has near-equal
drop rate (33% OPEN vs 26% CLOSED, within sample noise).

**Finding 4: cart-side is perfect.** Across all three runs, every fire fell
in the 2000-2009ms gap bucket. Anchored cadence absorbs any loop jitter
from CCAPI calls. The PULSE log confirms pin-8 electrically pristine.

## Open question — where the session lands

The stressor lives inside the camera, on the camera's own schedule, and
isn't caused by anything the cart sends or doesn't send. The remaining
sweep is **recovery gap at fixed Tv=0.5"**:

| Run | Interval | Recovery gap | Status |
|---|---|---|---|
| measured | 2000ms | 1500ms | 70% (stress) |
| A — next | 2500ms | 2000ms | pending |
| B | 3000ms | 2500ms | pending |

Override via `/shutter/start?ms=N` to bypass the Tv→interval auto rule.
Find the recovery gap at which delivery returns to 100%. That's the edge.

The historical 98% case (Tv=0.8" at 3s = 2200ms recovery gap) suggests
the edge sits between 1500ms and 2200ms. Run A measures the midpoint.

## Leads not yet pulled

- **EXIF columns unused.** ExposureTime, ISO, BrightnessValue across each
  saved photo. If the camera's internal state was visible in any of these,
  it would surface here. Worth checking per-photo before next session's
  sweep.
- **The 2s zone is the project's bread and butter.** Appendix A: 71 rows
  at 2s interval, ~7,200 photos per sunset+sunrise. The edge measurement
  is not academic — it sets the actual operating boundary.
