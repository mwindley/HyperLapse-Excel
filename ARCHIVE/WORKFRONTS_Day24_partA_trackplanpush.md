# WORKFRONTS.md — Day 24 (part A) — Trackplan pusher + load-disarm safety

**Append after the Model B note. First of the four gimbal next-steps
done. Sketch → soak-v13a.**

---

## Excel trackplan pusher — built + proven (Day 24)

First real Excel pusher for the gimbal half (was raw-URL all session).

**New Excel module — TrackPlanPush.bas** (separate, like CartPlanPush).
Reads the middle-zone gimbal plan, finds Track / Track-yaw GPs, pushes
them as TrackIntervals to `/settings/trackplan`.
- Shoot t=0 = first GP's Fires-at. Each interval ts/te converted to
  ms-from-start via (excel_time - plan_start)*86400*1000 (same
  day-fraction convention AstroPush uses).
- target → obj char: sun→S, moon→M, gc/mw→W. Track→mode F (offy=Δyaw,
  offp=Δpitch); Track-yaw→mode Y (offy=Δyaw, offp=Rp fixed pitch).
- Pushes idx 0,1,2… in sequence (cart requires idx==count; idx=0
  resets). Dry-run guarded; real push pings /status then one GET per
  interval. Transport mirrors CartPlanPush (WinHttp, dataArduinoIP,
  Utils.LogEvent).
- Cap: TRACK_PLAN_MAX=10.

**Test (bench):** plan = GP01 pan-follow @WP01, GP02 Track sun @WP03,
GP03 END +15min. Dry-run → one interval
`idx=0 obj=S mode=F ts=18000ms te=918000ms offy=0 offp=0`. Times check:
ts=18s = WP03 arrival (500mm @100m/hr ≈18s drive); window = te-ts =
900s = the 15-min END offset. Real push → `OK {"count":1}`. **Interval
pushed from Excel, accepted by cart.**

Execution run-order is now: AstroPush pushes cubics → TrackPlanPush
pushes intervals → /track/start.

## Load-disarm safety fix (soak-v13a) — found on hardware

**Incident:** after the real trackplan push, the gimbal swung 10°→100°
fast — UNEXPECTED, since pushing an interval shouldn't move anything.
Cause: the executor was still ARMED from the earlier Model B test
(/track/stop never sent). Pushing the new interval made the still-armed
executor immediately act on it + the stale sun cubic (rt0 ~minutes in
the past, so its real-time value had grown large) → big fast swing.

**Lesson:** loading a plan must NEVER cause live motion.

**Fix:** `/settings/trackplan?idx=0` AND `/settings/trackpath?seg=0`
(the reset/first push of a new plan or cubic) now set
`track_exec_on = false` and reset track_active_idx. Loading or
reloading disarms; motion resumes only on an explicit /track/start.
Push steps are now inert.

Found on a bare gimbal (no camera/cables) — exactly where you want to
find it. Reinforces the no-camera-during-first-motion-tests discipline.

**Status — gimbal next-steps (4):**
1. Excel gimbal pushers — trackplan DONE (this). Still: previewplan
   pusher, rt0 on AstroPush trackpath (Model B cubics), Move-cubic
   Stage 4.
2. Phase-A ease-onto-curve (executor).
3. BNO cart-yaw correction into gimbal yaw.
4. Pan-follow execution.

Next logical: AstroPush sends rt0= so cubics are Model-B-ready, pairing
with the just-proven interval push for a full Excel→cart→track run.
Ry=Cy still holds.
