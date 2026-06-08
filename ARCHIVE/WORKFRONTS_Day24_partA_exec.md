# WORKFRONTS.md — Day 24 (part A) — execution-testing workfront

**Append to the Day-24 (part A) "New workfront" list, after #71.**

---

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

## Status-line note

- This folds the standalone **#54** (gimbal slew overshoot) into #72
  step 8 as the place it gets exercised and fixed; #54 stays its own
  numbered item but is no longer "not yet exercised — deferred," it is
  "to be exercised under #72."
