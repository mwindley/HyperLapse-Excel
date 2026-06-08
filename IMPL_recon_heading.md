# Implementation — recon IMU heading → Excel (plan + bicycle model)

**Verified against live code (Day 25): DJI_Ronin_Giga_v2.ino + the VBA
inside HyperLapse.xlsm.** Paste-ready edits. Cannot compile the sketch or
run the VBA here, so each edit ships with a verification step you run.
Objective: bring the measured BNO heading back from recon and make it
available to the Excel Plan and to BicycleModel (as a true-north anchor +
per-waypoint check). Record-only; no correction; cal 0 accepted (cal
logged for the record only).

Apply in order. Step 1 (cart) is independent — flash + bench-verify it
before doing the Excel side, so a bad capture is caught at the source.

---

## STEP 1 — CART: capture BNO heading at Mark-Waypoint

**File:** DJI_Ronin_Giga_v2.ino · **Location:** `btn` handler, `case 22`
(~L5381, "Mark wpt. Bakes 'W' event.").

**Edit — add the heading capture right after the existing W write:**

Find:
```cpp
            case 22: {
                // Day-15 part 10 — Mark wpt. Bakes 'W' event.
                cart_waypoint_count++;
                cart_last_waypoint_steps = ticRear.getCurrentPosition();
                cartLogEvent('W', cart_waypoint_count);
```
Add immediately below the `cartLogEvent('W', ...)` line:
```cpp
                // #40 recon-heading: pair each waypoint with a measured
                // BNO heading + cal byte (record-only, Ry=Cy holds).
                // Cart is parked here → clean stationary read. Same
                // helper/format as the 3a execution anchors.
#ifndef STUB_BNO
                cartLogAnchor(bno_offset_set ? (bno_yaw_raw - bno_yaw_offset)
                                             : bno_yaw_raw,
                              (int)bno_cal_status);
#endif
```
(Leave the existing `Serial.print` lines below untouched.)

**Also:** bump the `[build]` boot-banner version string (build-lesson 15
— proves the flash actually took).

**Why this is safe / minimal:** reuses `cartLogAnchor` verbatim (already
shipping for 3a); no struct change; no CSV-schema change (the `aux` tail
field already exists). Each waypoint now logs `W` then `A`.

**Verify (bench, no Excel):**
1. Reflash; confirm the new `[build]` version prints at boot.
2. `/btn15` to ensure recording active (or however recording starts), then
   point the cart at a known heading, `/btn22` (Mark wpt). Repeat at 2–3
   distinct headings.
3. `GET /cartlog`. Confirm each `W,<n>` row is immediately followed by an
   `A,<yaw×10>,...,<cal>` row, and `<yaw×10>/10` matches the cart's true
   heading at that mark. cal may read 0 — that's expected and ACCEPTED.

Stop here until this passes. Then do Step 2.

---

## STEP 2 — EXCEL: import the heading and make it available

Two macros change: `Cart.GetCartLog` (import the dropped tail field +
route A rows) and `BicycleModel.IntegrateBicycle` (use the measured start
heading as the true-north anchor). Plan-side surfacing is 2c.

**Verified column facts that constrain this:**
- `GetCartLog` reads only `fields(0..4)` → CartLog cols 1–6; **field(5)
  (aux/cal) is dropped today.**
- `ProcessCartLog` overwrites cols 5–11 and AutoFits E:K — **cols 12/13
  (L/M) are free.**
- `IntegrateBicycle` writes the **Trace** sheet: col 4 = `theta_deg`
  (integrated heading), col 8 = source CartLog row. Its **θ starts at 0
  (relative, +X = 0, CCW-positive)** — NOT a true bearing.
- BNO convention (Day 23): CW = negative; compass/world CW = positive →
  the measured heading must be sign-aligned before it anchors the model.

### 2a — `Cart.GetCartLog`: capture the aux field, route A rows to L/M

In the per-line write block (after the `fields(4)`/col-6 write), add:
```vba
                ' #40 recon-heading: A rows carry a measured BNO heading
                ' (value = true_yaw x10) + cal byte (field 5 / aux).
                ' Land them in dedicated tail cols 12/13 so ProcessCartLog
                ' (which overwrites cols 5-11) can't stomp them.
                If fields(1) = "A" Then
                    ws.Cells(NextRow, 12).value = CDbl(fields(2)) / 10#   ' BNO heading (deg)
                    If UBound(fields) >= 5 Then
                        ws.Cells(NextRow, 13).value = CDbl(fields(5))     ' BNO cal byte
                    End If
                End If
```
And header cols 12/13 once, in the same `If ws.Cells(1,1).value = ""`
header block that sets cols 1–6:
```vba
        ws.Cells(1, 12).value = "BNO heading (deg)"
        ws.Cells(1, 13).value = "BNO cal"
```
S/T/W/X handling is left exactly as-is — additive only, existing indices
untouched (build-lesson 16: positional surfaces grow at the tail).

### 2b — `BicycleModel.IntegrateBicycle`: anchor θ₀ to the measured start heading

Today `theta_rad = 0#` at init (relative frame). To make the trace
absolute, seed it from the FIRST waypoint's measured BNO heading when one
is present. Find:
```vba
    x_m = 0#: y_m = 0#: theta_rad = 0#
```
Replace with (reads the first A-row heading from col 12 if any; falls back
to 0 = current behaviour):
```vba
    x_m = 0#: y_m = 0#: theta_rad = 0#
    ' #40: anchor the trace to true north if a measured start heading
    ' exists. BNO is CW-negative; model theta is CCW-positive → negate.
    ' Falls back to 0 (relative frame, unchanged) if no A row present.
    Dim hdr0 As Variant, rr As Long
    For rr = 2 To lastRow
        If CStr(wsLog.Cells(rr, 2).value) = "A" Then
            hdr0 = wsLog.Cells(rr, 12).value
            If IsNumeric(hdr0) Then theta_rad = (-CDbl(hdr0)) * PI / 180#
            Exit For
        End If
    Next rr
```
Effect: Trace col 4 `theta_deg` becomes a **true bearing** instead of a
relative angle, when a recon heading exists — which is what makes the
integrated per-waypoint θ comparable to the gimbal plan's astro azimuths
and to the measured A-row headings. With no recon heading it behaves
exactly as before.

> NOTE — sign convention is the one place a silent error hides
> (CART_HEADING_DESIGN.md §4). The `-CDbl(hdr0)` assumes the Day-23
> finding (BNO CW negative, world CW positive) AND that the model's
> CCW-positive θ should read as a compass bearing. VERIFY empirically on
> the first real trace: drive a known path, check Trace col 4 at a
> waypoint against the iPhone bearing there. If it's mirrored, the negate
> is wrong — fix here, one line, not downstream.

### 2c — surface measured-vs-integrated (the deliverable)

No correction — just put them side by side so the operator (and UAT) can
judge agreement. Cheapest form, pick one:
- **Easiest:** the Trace sheet already has integrated θ (col 4) + source
  row (col 8); the CartLog sheet now has measured heading (col 12) on the
  A rows. A small lookup column on Trace (or a 2-column block on the Plan
  sheet next to each waypoint) showing `measured θ` beside `integrated θ`
  per waypoint is enough. No new math.
- Optional later: a delta column (measured − integrated) to make
  disagreement obvious at a glance.

**Verify (after a real recon drive):**
1. `GetCartLog` → confirm A rows imported with heading in col 12, cal in
   col 13; S/T/W/X rows unchanged.
2. `ProcessCartLog` → confirm cols 12/13 untouched (not overwritten).
3. `IntegrateBicycle` → confirm Trace col 4 now reads near the measured
   start bearing at t=0 (not 0), and check one mid-path waypoint's
   integrated θ vs the iPhone bearing — confirm the sign (2b note).
4. Confirm the side-by-side view shows measured vs integrated per waypoint.

---

## What this achieves vs leaves for later

- **Achieves the objective:** the recon IMU heading is back in Excel and
  available to BOTH the Plan (per-waypoint measured value) and the
  BicycleModel (true-north θ₀ anchor + per-waypoint check).
- **Generates the UAT data:** measured-vs-integrated over a real path —
  the evidence that decides whether `expected_cart_heading` stays
  pure-integration or wants recon-correction.
- **Does NOT:** apply correction, gate on cal, change the plan stream, or
  touch gimbal aim (steps C/D, later). Fully reversible; existing
  behaviour preserved when no A rows are present.
```
