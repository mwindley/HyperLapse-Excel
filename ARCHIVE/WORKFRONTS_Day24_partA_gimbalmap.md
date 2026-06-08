# WORKFRONTS.md — Day 24 (part A) — Gimbal-half push: state map

**Append to the Day-24 cart-push note. Mapping only — no gimbal code
written this session.**

---

## Gimbal plan → cart: what exists vs what's missing (Day 24)

Traced the cart sketch + .bas modules to size the gimbal half (the
"not-ready half"). Finding: the gimbal **data plumbing is built, the
execution engine is not.**

**EXISTS (cart + Excel):**
- Tracking cubics — fit + push. `AstroPush.PushTrackPathsToCart`
  already fits per-segment cubics (sun over sunset→sunrise, mw over
  dark window) via `FitCubic` least-squares and POSTs to
  `/settings/trackpath?obj=&seg=&ts=&te=&ay0..3=&ap0..3=`. The cart's
  PlanPush.bas "cubics deferred" note was misleading — the capability
  lives in AstroPush, not PlanPush.
- Cubic storage + evaluator on cart: `/settings/trackpath` stores
  per-obj segment cubics; `/debug/trackeval?obj=&t=` evaluates
  yaw/pitch at time t (picks the right segment, clamps ends). This is
  what #5a "DONE" meant — the evaluator works.
- Track-interval storage on cart: `/settings/trackplan?idx=&ts=&te=
  &obj=S|M|W&mode=F|Y&offy=&offp=` writes the `track_plan[]` table
  (TRACK_PLAN_MAX slots). Modes GTM_FULL='F' (yaw+pitch follow),
  GTM_YAW='Y' (yaw follows, pitch=offP fixed).

**MISSING (the real gimbal build):**
1. **Runtime track executor on the cart** — NOTHING walks `track_plan[]`
   at runtime: no loop code that, at the current time vs an interval's
   ts/te, evaluates the cubic and DRIVES the gimbal over CAN. The
   evaluator computes angles; nothing acts on them. This is the single
   biggest gap — without it, pushing trackplan stores data that never
   executes.
2. **Gimbal move/slew primitive** — no CAN drive-to-angle command in
   the production sketch except the pano state machine. The executor
   (and Move steps) would need one.
3. **Pan-follow execution** — not present on the cart at all.
4. **Trackplan pusher in Excel** — nothing in any .bas pushes
   `/settings/trackplan`. PlanPush decomposes to TrackIntervals in
   dry-run (logs only) but has no Stage 4 POST.
5. **Move (cubic slew) push** — PlanPush logs endpoint+duration only;
   the discrete-slew cubic isn't computed/pushed.

**Simple test plan mapping (drive + pan-follow -30 + move-sun +
track-sun):**
- drive 500 + stops → cart half, DONE this session.
- track-sun PATH → already pushable (AstroPush cubics) ✓
- track-sun INTERVAL → needs trackplan pusher + the cart executor ✗
- pan-follow -30 → no cart execution path ✗
- move-to-sun → no cubic-slew push + no move primitive ✗

**Conclusion:** the gimbal half is earlier-stage than the cart half.
Order of build (proposed, next session): (1) cart-side track executor
that consumes `track_plan[]` + cubics and drives the gimbal — the
keystone; (2) gimbal move/slew + pan-follow primitives; (3) Excel
trackplan pusher + Move-slew push (PlanPush Stage 4). Track-sun is the
nearest-to-ready behaviour (path already pushes); pan-follow and move
need the most new code.

**No gimbal code written this session — mapping only.**
