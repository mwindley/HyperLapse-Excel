# WORKFRONT - chart + cable strip must render Track (astro) cubics

Status: NOT built. Real gap, surfaced Day 31/32. Priority: cable strip first.

## Problem
The Gimbal Plan View and the Cable Strip both SKIP Track (astro) rows:
  CHARTPUSH  NOTE row N: TRACK (astro) - charting deferred, skipped
  CABLEPUSH  NOTE row N: action 'TRACK' - skipped
So an all-Track GC plan produces empty visuals - markers only, no path, and the
cable strip reads "used span 0 / headroom 450" even though a GC track can sweep
~100 deg of yaw near transit. The cubic IS correctly pushed to the cart; only
the Excel-side CHART AUTHORING ignores Track rows. ("charting deferred" =
unbuilt feature, not a regression.)

## Why it matters
The cable strip's job is "does this plan wrap the cable" (cart-frame yaw vs the
450 deg span limit). For autonomous tracking that's THE safety review - a GC
transit pass eats ~100 deg of cumulative yaw. With Track rows skipped, the strip
can't answer the one question it exists for on a tracking plan.

## What yaw does on a Track row (the key point)
A Track GP is not one yaw value - it is a yaw PATH over the interval. On the
strip it must appear as a SWEPT band: from yaw-at-interval-start to
yaw-at-interval-end, and crucially the MIN and MAX yaw reached across the
interval (the path may swing past both endpoints). Cable cost = (max - min)
cumulative, cart-frame, unwrapped.

## Approach (cable strip first)
For each Track row, instead of skipping:
1. Resolve which object/cubic (sun/moon/GC=mw) and the interval [ts, te].
2. Sample the SAME cubic Excel just fit (AstroPush) across the interval - reuse
   the fit, do not re-derive - to get yaw(t) over the window.
3. Convert each sampled yaw to CART frame (cf = world - heading(anchor)), the
   same resolver the dial/strip already use (this is the frame the cable lives
   in - see the Day-31 cable-frame correction).
4. Take min / max / endpoints of the cart-frame yaw across the interval.
5. Draw the swept band on the strip (start->end, with min/max extent) and add
   its sweep into the cumulative used-span total vs the 450 limit.

This will also VISUALISE the new alt>70 zenith-band yaw ease: the eased sweep
through the >70 window shows the cable cost of a transit pass before commit.

## Chart (Gimbal Plan View) - second
Same idea in the polar dial: sample the cubic to a yaw/pitch path and draw the
arc (glyph dir = world bearing, length = pitch), instead of only the GP marker.
Lower priority than the strip (strip answers the cable-wrap question).

## Notes / cautions
- Reuse AstroPush's fit + sampling; don't re-implement the ephemeris in the
  chart code. Single source of truth for the cubic.
- Unwrap yaw consistently (same single-frame approach AstroPush now uses for the
  zenith band) so the cumulative sweep is correct across the interval.
- Sun/moon Track rows benefit too (same mechanism), not just GC.
- Cart side unchanged - this is Excel chart/strip authoring only.
