# UI failure at plan start — open investigation

Status: OPEN. No root cause found. This document records the symptom and the
current line of exploration only. No fix, no firmware change.

## SYMPTOM
The field WiFi UI (iPhone / laptop, http://192.168.20.97) dies shortly after a
plan is started. The heartbeat/poll stops updating while the cart itself keeps
running. Reported timing: the UI goes dead a short way into the plan (on the
order of the first several frames / ~20s after start), not at rest and not
immediately at boot.

## WHAT IS NOT AFFECTED
- The cart main loop keeps running.
- The wired (W5500) camera path keeps working — fire, liveview, meter unaffected.
- A single manual fetch of /exec/feed returns correct JSON while the auto-poll
  is dead, i.e. the endpoint and the cart are alive; the repeated UI poll is what
  stops getting replies.
- Only the WiFi-served UI is affected. WiFi and W5500 are separate hardware/stacks.

## CURRENT LINE OF EXPLORATION — was the plan bad?
Being explored: whether a malformed / unusual plan is involved in the failure,
rather than (or alongside) the UI fault. Reasons this is being looked at:

- A recent plan started but produced NO photos. Separately from the UI, this
  raised the question of whether the plan itself was well-formed.
- The plan in question used a gimbal GP that did not result in firing, and the
  push/anchor details (start-marker row, anchor type, WP vs TIME anchor) are
  being reviewed to see if the plan shape contributed.

NOTE: "no photos" and "UI died" are being treated as POSSIBLY SEPARATE faults.
It is not established that a bad plan causes the UI to fail; that link is only
being explored, not concluded.

## NOT YET ESTABLISHED
- Whether the UI failure depends on the plan at all (it has been seen with the
  UI surviving on some runs and dying on others).
- Whether plan validity, firing vs not-firing, or camera/liveview behaviour at
  start has any bearing on the UI death.
- Any root cause on the WiFi serve side.

## NEXT (exploration only, not committed)
- Confirm whether a known-good firing plan and a known-bad non-firing plan differ
  in whether the UI survives — i.e. is the UI death correlated with the plan at all.
- Keep the two questions separate: (1) does a plan fire photos, (2) does the UI
  survive plan start. Do not assume one explains the other.

No findings beyond the above. No changes made.
