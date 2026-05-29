# Day 12 — Documentation update inserts

This file contains paste-ready blocks for the existing project docs.
Each block has a target file and a recommended insertion point.

---

## Target: `PROJECT_STATE.md`

**Update the "Last updated" header** to:

```
**Last updated:** 20 May 2026 (end of Session C day 12 — Drop Test
rig built, 200ms pulse identified as root cause of the chronic
delivery drops previously attributed to CCAPI stress)
```

**Insert this block at the top, before any existing day-by-day section:**

```markdown
## Day-12 session — Pulse width identified as root cause

The Day 11 hypothesis that "CCAPI activity stresses the camera and
causes drops" is overturned. The Canon R3 needs the shutter line
held LOW for ~200ms to register reliably; production's 100ms pulse
was at the edge, and any CCAPI-induced camera slowdown pushed a
fraction of triggers past the edge into drops.

Built `DropTest.ino` — a minimal fork of the production sketch on a
spare Uno R4 WiFi — to sweep variables independently. Key changes:
analyser marker pins on 2/3/5/6, /echo verification endpoint,
/debug/liveview_at_start?on=N flag for true zero-CCAPI baseline,
and pulse width raised to 200ms.

Results across 7 test runs proved:
- Pulse width is the cause (100ms → 53.8-70.4%, 200ms → 96-100%)
- CCAPI load is not the cause (200ms holds up under full Day-11
  stress condition: 37/37 = 100%)
- The opto path is innocent (200ms with intervalometer = 100%,
  200ms with Uno+opto = 96-98%)
- Production resilience verified: a real fetch timeout mid-run was
  handled cleanly, backoff applied, recovery automatic, and all
  photos still landed

See `DAY12_SUMMARY.md` for full data table, traces, and reasoning.

**Production action**: change `backupShutter()` micros window from
100000 to 200000 (`(micros() - t0) < 200000`). One-line change.

**Architectural notes superseded by Day 12**:
- Day-11 "Open question — recovery gap edge" is moot. No edge exists
  in the 2s zone; previous drops were the pulse-width artefact.
- The Tv + 1.5s cadence rule still stands as a sensible minimum
  interval.
- No need to investigate CCAPI quiet windows, fetch-frequency
  sweeps, or live view cycling as stress-reduction strategies.
```

---

## Target: `PREFERENCES.md`

**Insert this entry under "Build lessons (carry forward)":**

```markdown
9. **Canon R3 shutter pulse needs 200ms LOW, not 100ms.** The chronic
   drops at 2s cadence (70-74% delivery, attributed to "CCAPI stress"
   on Day 11) were caused by the production sketch driving pin 8 HIGH
   for only 100ms. The manual intervalometer that hits 100% delivery
   uses 200ms LOW pulses. Verified Day 12 with 7 runs spanning zero-
   CCAPI to full Day-11 stress condition. `backupShutter()` should
   drive pin 8 HIGH for 200000 microseconds, not 100000.
```

**Insert this under "Diagnostic philosophy — oscilloscope approach":**

```markdown
- **When chasing software, compare against a known-good reference
  first.** A working intervalometer puts ~200ms pulses on the camera
  Shutter line and hits 100% delivery. Measuring that on the logic
  analyser, then comparing against the Uno+opto trace, would have
  identified the pulse-width difference on Day 11 if we had done it
  then. The lesson: when something works (intervalometer) and
  something similar doesn't (our sketch), measure both with the same
  instrument before chasing more complex hypotheses.
```

**Insert this under "Build lessons" as a separate entry:**

```markdown
10. **USB cable quality can manifest as WiFi / HTTP latency.** Early
    Day-12, multi-second HTTP response times on the test Uno were
    resolved entirely by swapping the USB cable. A flaky cable causes
    power brownouts that destabilise the ESP32 WiFi co-processor on
    the Uno R4 without obvious failure. If a fresh-flashed sketch
    behaves dramatically worse than production on the same hardware,
    swap the USB cable before chasing sketch bugs.
```

---

## Target: `WORKFRONTS.md`

**If there is a Day 11 "Open question" or "Recovery gap" task,
mark it as superseded:**

```markdown
~~Find the recovery-gap edge condition for 2s cadence under CCAPI
stress~~ — SUPERSEDED Day 12. No edge exists; the apparent edge
was the 100ms pulse width sitting on the camera's debounce
threshold. With 200ms pulse, the 2s zone delivers 96-100% regardless
of CCAPI load. See `DAY12_SUMMARY.md`.
```

**Add new tasks (or move existing ones to "Done"):**

```markdown
- [ ] **Apply 200ms pulse to production sketch.** One-line change in
  `backupShutter()`. Validate on next real shoot before declaring
  the chronic drop issue resolved.
- [ ] **Port `DropTest.ino` markers / `liveview_at_start` flag back
  to production** if any future stress-investigation needs the
  diagnostic surface. Otherwise keep `DropTest.ino` as a parked
  diagnostic asset.
- [x] **Drop Test sketch built** (Day 12)
- [x] **Day-11 drop rate cause identified** (Day 12)
```

---

## What is unchanged

- `EXPOSURE_FALLBACK.md` — exposure logic and Appendix A reference
  table are unaffected. The Tv + 1.5s interval rule still applies.
- `GIMBAL_VIZ.md` — unaffected.
- `UI_DESIGN_SUMMARY.md` — unaffected.
- `SHOPPING.md` — the SparkFun TOL-18627 analyser purchase paid off
  tonight. No new shopping needs from Day 12.
- `OPTO_TEST_PLAN.md` — the planned diagnosis (CH0 pin-8 vs CH1 opto
  output) is now partially answered: pin 8 is clean, opto path is
  innocent (the 200ms intervalometer hits 100% through the same
  opto). The plan can be marked "ANSWERED — opto is innocent" or
  retained as a future fallback if drops reappear after applying
  200ms to production.
