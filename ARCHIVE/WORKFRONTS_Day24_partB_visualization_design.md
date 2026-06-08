# WORKFRONTS — Visualization architecture (design)

Status: **DESIGN AGREED, not yet built.** Day 24 (part B) discussion.
Three separate visualizations for three purposes/places. All rendering is
OFF-CART (Python at the desk + a client beside the cart); the cart never
grows a rendering UI. Render engine = **Python** (previous sessions
already used Python tasks).

---

## (1) Cart 2D top-down plan

- **What:** top-down XY plot of the cart/dolly path — waypoints,
  drive/turn/stop segments.
- **Home:** Excel (XY scatter). Already has some capability.
- **Status:** exists; cosmetic polish wanted; **low priority, on the
  list.** No real design work pending.

---

## (2) Gimbal-plan visualization — polar sky plot (the "PhotoPills" model)

- **What:** a cart-centred top-down az/alt (polar) plot for PLANNING.
  Reference: operator's PhotoPills planner screenshot.
    - Astro arcs: GC drawn as a semicircle of dots, **big dot = GC
      centre**; sun and moon as their own coloured arcs/markers.
    - Gimbal points overlaid as lines from centre: **direction = yaw,
      length = pitch** (long line = low pitch / near horizon; short line =
      high pitch / overhead). This makes the GC zenith problem visible —
      near transit the line shrinks toward a dot, which is exactly where
      yaw whips.
    - PREV/NEXT cycles which GP is shown. **One image per GP** — does not
      need to be fancy/animated.
- **Home:** **Python (matplotlib polar), on the laptop, planning-time.**
  Python does polar far more naturally than Excel.
- **Status:** **still required**, not yet built. Its own renderer
  (distinct from (3) — see note below).

---

## (3) Gimbal EXECUTION UI — linear cable-budget strip

This is the field/execution view, on a **phone beside the cart**. Its
purpose is **REASSURANCE**, not analysis: middle of the night, the
operator glances to confirm "where am I in the plan, is it doing what it
should" — tracking along a path, holding on sunset, about to take off to
GC after the long hold. No action expected, no decision. So: legible at a
glance, in the dark, dead simple.

### Why LINEAR, not polar (the cable constraint)
- The gimbal plan is **capped at 450 deg total span** to prevent cable
  wrap. The execution view is a **linear strip** with axis =
  gimbal-min -> 450 deg (the literal cable budget). The marker slides
  left->right along it through the night. (This is a real departure from
  the polar (2) plot — execution cares about "how far along the windable
  range am I," which is a horizontal axis.)
- Setup procedure that makes the budget work: actual spans are often well
  under 450 (e.g. -30 to +150 = 180). The operator pre-positions the
  gimbal to ~mid-travel (e.g. +60) in setup using Ronin's hand-push mode
  (enabled only via the iPhone app), dresses the cables there, then
  manually reverses to the start. Starting half-wound lets the gimbal
  unwind one way and re-wind the other across the night without the
  cables fighting. So the 450 axis = the cable budget; mid-travel setup
  keeps a 180 plan safely inside it.

### What the strip carries (kept minimal)
- **Only the marker (symbol) + the GP number.** Nothing else on the strip
  — no state text, no pitch, no speed colour. Cable wrap is a yaw
  phenomenon, so pitch is likely irrelevant to this view.
- Below the strip: a **summary list** of cart waypoints (WP) and gimbal
  GPs. **Not yet planned** ("maybe all"); likely leans on the existing
  rolling-window / ToGo behaviour and the GP-by-GP stepping (PREV/NEXT,
  continuations skipped) rather than being fresh design — CHECK existing
  notes against it before building.

### Architecture: Excel/Python renders, cart serves, client overlays
- At plan-push time, **Python renders the execution backdrop** (the strip)
  and it is pushed to the cart.
- The cart **stores it on the SD card** and serves it to any client
  (phone/laptop) along with the **live symbol position**; the client
  overlays the moving marker. Cart stays dumb: stores a file, reports one
  position, renders nothing.
- **The SD card is the enabler** — a pre-rendered backdrop (even a few KB
  SVG) has no room in the Giga's RAM; SD makes "push an image, cart serves
  it" viable. This design depends on the SD card.
- **Backdrop format: SVG** (Python emits it easily) — a few KB not
  hundreds (kind to SD + WiFi push), crisp on a pinch-zoomed phone, and
  the moving marker is a clean overlay element rather than compositing
  onto a raster.

---

## Key structural conclusions

- **(2) and (3) are DIFFERENT renderers**, not one with two playheads (an
  earlier idea that did NOT survive the cable-budget reframe). (2) =
  polar sky geometry for planning ("where in the sky"); (3) = linear
  cable-budget strip for execution ("where in my windable range / where
  in the sequence"). Different questions, different homes.
- **All rendering is off-cart.** The only new cart capability for (3) is
  "hold an image on SD + emit a symbol position" — small, firmly in the
  dumb-executor spirit. No cart firmware grows a canvas/rendering UI.
- Render engine is **Python** throughout (laptop). Excel keeps only (1).

---

## Flags for build time (not decided now)

- **Symbol-position coordinate contract for (3):** does the cart send
  yaw/pitch and the client maps it onto the strip, or does the cart send
  x/y% and stay ignorant of the plot geometry? The latter keeps the cart
  dumber but means Python/Excel must hand the cart the mapping at push.
- **Serving path for (3):** a new endpoint to fetch the SVG off SD, and
  the symbol position folding into the existing /status JSON.
- **(3) summary list:** confirm it reuses the existing rolling-window /
  GP-stepping behaviour before designing anew (operator: "we check before
  executing/coding").

Nothing here is BNO-blocked. Nothing here is a build yet — design only.
