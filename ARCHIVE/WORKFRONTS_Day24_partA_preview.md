# WORKFRONTS.md — Day 24 (part A) — Preview/step mode PROVEN

**Append to the executor note. New capability + a real-world operator
requirement captured. Relates to #5a / Execution UI / cable mgmt.**

---

## Gimbal preview / step mode — built + proven (Day 24)

**The requirement (operator field-craft):** once the gimbal plan is on
the cart, the operator needs to step through the GP poses ON DEMAND
(not timed) to (a) verify start position + Ry/Cy geometry, (b) imagine
where the tracks go even though the real astro target is elsewhere, and
(c) — the big driver — MANAGE CABLES. Cable strategy: slew the gimbal
to the half-tangled point, set up nice cable routing there, then
reverse the GP points back to start, unwind the first half, re-tangle
the second half. This only works if the operator can cycle through GP
poses on demand, forward AND back, watching the actual rotations and
testing the cable against them. If rotations are "all over the place"
this is how the operator finds a workable routing.

**Model (from the real Ronin app):** the Ronin has a Track mode that
executes video moves over many hours, and a preview mode that runs
each move at safe-but-fast slew rates to get through it quickly.
Mirror that: preview = walk the GP list, slew to each GP's
representative pose at a safe fixed rate, stepped on operator command.
A Track-sun GP in preview = move to the sun's start pose, held ~5s
(NOT an hours-long track). Preview uses the PLANNED astro positions
(the real geometry the night will produce), shown at preview speed.

**Architecture — cart stays DUMB:** Excel computes each GP's preview
pose (it has all the geometry — marker endpoints, astro keyframes) and
pushes a flat pose list. Cart just slews to pose[idx] on command. No
GP-row logic on the cart (it doesn't store the gimbal plan, only
decomposed track intervals + cubics + astro keyframes — so a separate
flat preview list is the clean dumb-cart fit).

**Built (build soak-v11 → v11a 6dps → v11b 12dps):**
- `preview_plan[PREVIEW_PLAN_MAX=20]` of PreviewPose{yaw,pitch,label},
  `preview_count`, `preview_idx`.
- `previewGoto(idx)` — slews to pose[idx] at PREVIEW_SLEW_DPS, time-byte
  from angular distance (like panoIssueSlew).
- `/settings/previewplan?idx=N&yaw=&pitch=&label=` — Excel pushes one
  pose per GP (idx=0 resets).
- `/preview/step?dir=fwd|rev` — slew to next/prev GP.
- `/preview/goto?idx=N` — jump to a GP.
- `/preview/status` — current GP/pose/count.

**Hardware test (gimbal powered, no camera/cables):** pushed 3 poses
(start / GP2 45°,10° / GP3 -30°,5°) via raw URL, stepped fwd/fwd/rev.
Bidirectional stepping works. Rate tuned 3→6→12°/s; **12°/s is the
keeper** — brisk but controlled even on the 75° GP2→GP3 jump.

**Note — overshoot:** at 12°/s the gimbal shows a small
overshoot-then-correction landing at each pose. That's the gimbal's
own motion-profile settling (not a double command) — same family as
cart decel overshoot #54. Harmless for preview/cable use; if it ever
matters, dial the rate down (overshoot scales with speed). PREVIEW_
SLEW_DPS is a single #define, trivially tunable.

**In production:** this becomes an Execution UI feature (step buttons,
pose readout, GP labels). Tonight = raw URLs.

**STILL MISSING (Excel side):** the previewplan PUSHER — Excel must
compute each GP's preview pose (Move → endpoint; Track → astro
keyframe pose; Pan Follow → heading-relative, still an open question;
Lock/END → held pose) and push the list to /settings/previewplan.
Tonight pushed poses by hand. Pan-follow's preview pose is undefined
(it follows cart heading — what pose to show when the cart isn't
moving?) — design question for the pusher.
