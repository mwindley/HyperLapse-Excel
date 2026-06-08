# Yaw Runaway Protection - design report (pre-code)

## What happened
A time-base fault (sun cubic keyed to local time, realtime anchor set in UTC,
9.5 h apart) made the executor evaluate the cubic ~34,000 s outside its fitted
window. `trackEvalAt` does not refuse out-of-window time - it extrapolates the
cubic, producing a huge yaw, and the gimbal chased it as a continuous fast spin.

The UTC clock fix (AstroPush) removes that specific cause. This report covers
protection so that **any** fault fails safe (slow/bounded) instead of failing
fast (spin).

## Principle
Never let a computed target drive the gimbal unbounded. Two independent guards:
- **Rate cap** - bounds how fast yaw can change (deg/s). Catches runaway speed
  from any cause. Works without knowing the plan envelope.
- **Envelope clamp** - bounds where yaw may go (min..max, span 450). Catches
  cumulative over-travel. Needs a yaw_min reference.

They are independent: a bug in one does not disable the other.

## Why a rate cap alone is not enough
At 19 deg/s (just under a 20 deg/s cap) for 90 s the gimbal still travels
1710 deg (~4.75 turns). A speed cap stops the violent spin but not slow
cumulative over-travel. The envelope clamp is what bounds total travel to 450.

## Envelope reference (yaw_min / yaw_max)
- 450 deg is the maximum yaw span for any cable layout (hard cap).
- yaw_min is **per-plan** (the cumulative yaw extent of that gimbal plan, <=450).
- yaw_max = yaw_min + 450.

The cart does not currently hold an authoritative per-plan yaw_min for the
executor. The only yaw_min values on the cart are `chart_yaw_min` and
`cable_yaw_min`, set solely by the chart / cable-strip SVG push (display axis).
They can be 0 or stale during a track run, so they are NOT safe to clamp against.

## Envelope lifecycle (agreed)
Gimbal and sketch boot independently; the cart must ASK the gimbal for yaw,
never assume it.

1. **Gimbal present / reconnect** - cart queries current yaw, sets
   yaw_mid = reply, yaw_min = mid - 225, yaw_max = mid + 225.
   (Centred 450 envelope, valid immediately, no assumed 0.)
2. **yaw_min push** - yaw_min = pushed value, yaw_max = yaw_min + 450 (override).

Both events leave a valid envelope; the push is authoritative once it arrives.

## What the code already has (measured)
- `setPosControl(yaw,roll,pitch,...)` (line ~2330): stateless - packs bytes and
  sends the CAN frame. No timing, no last-yaw memory. Right place for a position
  clamp; wrong place for a rate cap (no state, and one-shot recon/preview gotos
  legitimately command a far target and rely on gimbal interpolation).
- Live gimbal yaw: `g_yaw` (line 1056), updated by the 0x0E/0x08 attitude push
  handler (line ~2503). This is the value to read when querying "where are you".
- A near-zenith yaw rate limiter ALREADY exists in the steady-track path
  (lines ~1660-1681), in deg/frame. BUG: it has an escape hatch
  `if (dt_s > 0 && dt_s < 5.0)` that PASSES YAW UNCLAMPED on large gaps
  (restart). A fresh arm with a wild target sails straight through - this is
  the path the spin took.
- Link transition is watched for WiFi only (`soakLinkWatch`, line ~2779); there
  is no explicit "gimbal came online" event yet. Gimbal-present must be derived
  from attitude-push freshness (g_yaw updating) or a yaw query reply.

## Actions required (firmware: DJI_Ronin_Giga_v2.ino)

1. **Add envelope state**: `yaw_env_min`, `yaw_env_max`, plus an "envelope set"
   flag. Default unset until first gimbal yaw is known.

2. **Set envelope on gimbal-present / reconnect**: when the cart confirms the
   gimbal is on (fresh attitude push / successful yaw query), set
   mid = g_yaw, min = mid - 225, max = mid + 225. Re-do on reconnect.

3. **Reset envelope on yaw_min push**: extend the track-plan push (ride along
   on `PushTrackPlanToCart` / its handler) with a yaw_min param; on receipt set
   min = pushed, max = min + 450.

4. **Envelope clamp** in the command path: before sending, clamp commanded yaw
   to [yaw_env_min, yaw_env_max] and pitch to [20, 80]. (Position guard.)

5. **Global rate cap 20 deg/s** on the autonomous track/plan execution path,
   AND close the existing limiter's `dt_s < 5.0` escape so a restart cannot
   bypass it. (Speed guard.)

6. **Decision still open**: does the 20 deg/s cap apply to the hands-on recon /
   preview gotos too, or only the autonomous (unattended) track/plan run?
   Recommendation: autonomous path only - operator gotos are eyes-on and the
   envelope clamp still protects them from position runaway.

## Excel side (only for action 3)
`TrackPlanPush.bas` (or wherever the trackplan URL is built) adds the plan's
yaw_min as a query param. Small, additive.

## Suggested staging (lower flash/test risk)
- Stage A: rate cap + close the escape hatch (stops the spin; no yaw_min needed).
- Stage B: envelope state + set-on-present + clamp (bounds travel; no push yet,
  uses the mid+/-225 default).
- Stage C: yaw_min push (Excel + handler) for the true per-plan envelope.

## Open items to confirm before coding
- Action 6 scope (cap autonomous-only vs all paths).
- How the cart should decide "gimbal is present" - simplest reliable signal is
  "g_yaw has updated within the last N ms" (attitude push is ~5 Hz). Confirm.
- Staging A/B/C in order, or all at once.
