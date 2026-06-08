# WORKFRONTS.md — Day 24 (part A) — rt0 cubics verified + epoch convention LOCKED

**Append after the trackplan-push note. Second gimbal Excel pusher done
+ a critical convention pinned. Sketch → soak-v13b.**

---

## AstroPush rt0 (Model B cubics) — built + verified end-to-end (Day 24)

**AstroPush.bas change:** on seg=0 the trackpath push now appends
`&rt0=<epoch_ms>` — the cubic's real-time t0. New helper
`DateToEpochMs(d)` = (serial - 25569) * 86400 * 1000. Cart stores it in
TrackPath.real_t0_ms and evaluates the cubic at real time per Model B.

**Sketch (soak-v13b):** rt0 now VISIBLE — trackpath serial line prints
`rt0=<lld>` on seg=0, and `/settings/trackpath` status JSON reports
`"rt0":<lld>` per object (buffer widened to 520).

**Verified end-to-end (real shoot data):** InitShoot set sunset
17:12:58 → PushTrackPathsToCart fitted sane windows (sun seg0 ts≈5000s
≈sunset, te≈55000s ≈sunrise; mw similar w/ a FREEZE seg). Readback:
`{"mask":5,"sun":{"t0_ms":17615,"rt0":1780156200000,"num_segs":2},
"moon":{...rt0:0,num_segs:0},"mw":{...rt0:1780156200000,num_segs:2}}`.
mask=5 = sun+mw valid; moon untouched. **rt0 = full 13-digit epoch-ms,
stored for sun+mw. Model B cubic path confirmed: real astro cubic,
real-time-keyed, pushed from Excel, stored + readable on cart.**
Also /debug/trackeval?obj=sun&t=5206 → yaw 299.71 pitch -1.45 (sensible
WNW sunset bearing on the horizon).

## EPOCH CONVENTION — LOCKED (critical)

Decoding the stored rt0=1780156200000 → reads as 2026-05-30 15:50:00
*UTC*, which is exactly the Adelaide WALL-CLOCK push time. I.e.
DateToEpochMs treats VBA Now() (LOCAL Adelaide) serial as-is →
epoch-ms that reads back as local-time-as-UTC. This is the LOCAL
convention.

**RULE (locked by this test):** rt0 AND the /settings/realtime anchor
the Execution UI hands in MUST use the SAME convention —
`DateToEpochMs(Now())`, i.e. LOCAL serial × day-ms. NOT a true UTC
epoch. The cart only subtracts (real_now - rt0), so a constant offset
cancels ONLY if both sides match. If the UI sent true UTC (e.g. a
`date +%s%3N`-style value, as used in earlier bench tests) while rt0
is local-as-UTC, they'd differ by the Adelaide offset (~9.5h) and the
gimbal would point wildly wrong.

→ Execution UI realtime-anchor push must reuse DateToEpochMs(Now()).
Bench tests that fed true-UTC epoch-ms are NOT representative of the
production convention — re-test the anchor with local-as-UTC ms.

## Status — gimbal next-steps (4)
1. Excel gimbal pushers: trackplan DONE; rt0-on-cubics DONE (this).
   Remaining: previewplan pusher; Move-cubic Stage 4 (PlanPush).
2. Phase-A ease-onto-curve (executor eases onto real-time sun cubic).
3. BNO cart-yaw correction into gimbal yaw (real-world heading).
4. Pan-follow execution.

Full Excel→cart→track chain now exists & each piece proven separately:
AstroPush cubics(+rt0) → TrackPlanPush intervals → /settings/realtime
(local-as-UTC) → /track/start. End-to-end live run (real shoot, cart
armed) not yet done as one sequence. Ry=Cy still holds (track path
separate from deferred BNO correction).
