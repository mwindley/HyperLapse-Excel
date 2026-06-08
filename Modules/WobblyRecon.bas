Attribute VB_Name = "WobblyRecon"
' ============================================================
' SimulateWobblyRecon - synthetic CartLog for Smooth Selection (#44)
' ============================================================
'
' PURPOSE
'   Produce a realistic 16-row wobbly recon log that exercises the
'   Smooth Selection workflow. Operator highlights ranges of rows
'   that "should have been one segment" and clicks Smooth; the
'   integrator re-runs against the reduced log; the chart redraws.
'
' SHAPE OF THE DRIVE (intent vs. what was actually driven)
'
'   Operator's intent              Actually driven (this log)
'   -----------------------        --------------------------
'   Gentle left bend ~10 deg          Left 5 deg / centre / Left 5 deg / centre
'                                    (4 rows - should smooth to 1 arc)
'
'   Drive straight for a bit       Right 3 deg / Left 2 deg / centre
'                                    (3 rows - should smooth to 1 near-
'                                    straight large-radius arc)
'
'   Clean right turn ~16 deg          Right 8 deg / centre
'                                    (2 rows - control case, already clean)
'
'   Drive straight to finish       Right 2 deg / Left 3 deg / centre / stop
'                                    (4 rows - another wobbly-straight cluster)
'
'   At 100 m/hr each "leg" takes 2-3 minutes of real driving, which
'   matches the operator's description: hard to judge degrees and
'   durations by eye, so the operator over/under-corrects.
'
' OUTPUT
'   CartLog sheet cleared and re-populated with header + 16 events.
'   RearSteps populated assuming straight-line distance (close enough
'   for the integrator; arc inner/outer divergence not modelled here).
'   Then run IntegrateBicycle to see the wobbly trace.
'
' USAGE
'   Run from Immediate Window:  SimulateWobblyRecon
'   Then double-click "Integrate Bicycle" button on Control sheet.
'
' DEPENDENCIES
'   - SecToHms helper (already in BicycleModel.bas)
'   - LogEvent (Utils.bas)
'   - M_PER_STEP constant (BicycleModel.bas) - assumed 1.78 um/step
'   - SERVO_TO_DEG = 1.0 currently (placeholder), so the T-row Value
'     column reads directly as wheel-angle degrees. If SERVO_TO_DEG
'     changes to 0.35 (day-9 measurement) the Value column will need
'     to express servo offset, not degrees - caller's responsibility.
' ============================================================

Option Explicit

Public Sub SimulateWobblyRecon()
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = Sheets("CartLog")

    ws.Cells.Clear

    ' Headers - match the live cart's /cartlog output
    ws.Cells(1, 1).value = "Timestamp"
    ws.Cells(1, 2).value = "Type"
    ws.Cells(1, 3).value = "Value"
    ws.Cells(1, 4).value = "Description"
    ws.Cells(1, 5).value = "RearSteps"
    ws.Cells(1, 6).value = "FrontSteps"
    ws.Range("A1:F1").Font.Bold = True

    ' Force column A to text format BEFORE writing any rows, otherwise
    ' Excel auto-converts strings like "00:00:05" into time-fraction
    ' numbers (5/86400 = 5.787E-05) and the chart-side timestamp parser
    ' fails. Applied here, not at the end, because the conversion
    ' happens at the moment of write.
    ws.Columns(1).NumberFormat = "@"

    ' --- Drive parameters ---------------------------------------
    Const SIM_M_PER_STEP As Double = 0.00000178
    Const V_MHR As Double = 100#         ' recon speed
    Dim v_mps As Double
    v_mps = V_MHR / 3600#                ' ~0.0278 m/s

    ' Cumulative step counter; advances by (leg_duration * v_mps) / M_PER_STEP
    Dim cumSteps As Double
    cumSteps = 0#

    ' Cumulative wall-clock time, seconds
    Dim t As Double
    t = 0#

    Dim row As Long
    row = 2

    ' --- Row 1: initial speed = 0 -------------------------------
    WriteEvent ws, row, t, "S", 0#, "Speed set to 0 m/hr", cumSteps
    row = row + 1

    ' --- Row 2: initial steering centred ------------------------
    WriteEvent ws, row, t, "T", 0#, "Steering centred", cumSteps
    row = row + 1

    ' --- Row 3: t=1s, speed up to 100 m/hr ----------------------
    t = 1#
    WriteEvent ws, row, t, "S", V_MHR, "Speed set to " & V_MHR & " m/hr", cumSteps
    row = row + 1

    ' === Cluster A: fumbled left bend (4 rows, should smooth to 1 arc) ===
    ' Intent: gentle left ~10 deg over ~5 minutes.
    ' Actually: left 5 deg (2 min), centre (3 min), left 5 deg (3 min), centre

    ' Row 4: left 5 deg, drive 2 min
    WriteEvent ws, row, t, "T", -5#, "Steer left 5 deg", cumSteps
    row = row + 1
    Call AdvanceLeg(120#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 5: back to centre, drive 3 min straight ("oops not enough left")
    WriteEvent ws, row, t, "T", 0#, "Steer centre", cumSteps
    row = row + 1
    Call AdvanceLeg(180#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 6: more left, drive 3 min
    WriteEvent ws, row, t, "T", -5#, "Steer left 5 deg", cumSteps
    row = row + 1
    Call AdvanceLeg(180#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 7: back to centre - end of fumbled bend
    WriteEvent ws, row, t, "T", 0#, "Steer centre", cumSteps
    row = row + 1

    ' === Cluster B: wobbly straight (3 rows, should smooth to 1 near-straight) ===
    ' "Straights are a series of curves" - small corrections only.

    ' Row 8: drive 90s straight, then small right wobble
    Call AdvanceLeg(90#, v_mps, SIM_M_PER_STEP, t, cumSteps)
    WriteEvent ws, row, t, "T", 3#, "Steer right 3 deg", cumSteps
    row = row + 1
    Call AdvanceLeg(60#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 9: small left wobble
    WriteEvent ws, row, t, "T", -2#, "Steer left 2 deg", cumSteps
    row = row + 1
    Call AdvanceLeg(60#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 10: back to centre - end of wobbly straight cluster
    WriteEvent ws, row, t, "T", 0#, "Steer centre", cumSteps
    row = row + 1

    ' === Cluster C: clean right turn (2 rows, control case) ===
    ' One steering input, hold, return to centre. Already a clean arc;
    ' Smooth Selection on these rows should propose ~the same arc.

    Call AdvanceLeg(60#, v_mps, SIM_M_PER_STEP, t, cumSteps)
    ' Row 11: right 8 deg, hold for 2 min
    WriteEvent ws, row, t, "T", 8#, "Steer right 8 deg", cumSteps
    row = row + 1
    Call AdvanceLeg(120#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 12: back to centre - end of clean right turn
    WriteEvent ws, row, t, "T", 0#, "Steer centre", cumSteps
    row = row + 1

    ' === Cluster D: wobbly finishing straight (4 rows, should smooth) ===

    Call AdvanceLeg(60#, v_mps, SIM_M_PER_STEP, t, cumSteps)
    ' Row 13: small right wobble
    WriteEvent ws, row, t, "T", 2#, "Steer right 2 deg", cumSteps
    row = row + 1
    Call AdvanceLeg(45#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 14: small left wobble
    WriteEvent ws, row, t, "T", -3#, "Steer left 3 deg", cumSteps
    row = row + 1
    Call AdvanceLeg(45#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 15: back to centre
    WriteEvent ws, row, t, "T", 0#, "Steer centre", cumSteps
    row = row + 1
    Call AdvanceLeg(60#, v_mps, SIM_M_PER_STEP, t, cumSteps)

    ' Row 16: stop
    WriteEvent ws, row, t, "X", 0#, "Stop", cumSteps
    row = row + 1

    ws.Columns("A:F").AutoFit
    ws.Columns(1).NumberFormat = "@"

    MsgBox "Wobbly recon log written: " & (row - 2) & " events." & vbCrLf & vbCrLf & _
           "Clusters to test Smooth Selection on:" & vbCrLf & _
           "  Rows 4-7: fumbled left bend (4 rows -> 1 arc)" & vbCrLf & _
           "  Rows 8-10: wobbly straight (3 rows -> 1 near-straight)" & vbCrLf & _
           "  Rows 11-12: clean right turn (control, already 1 arc)" & vbCrLf & _
           "  Rows 13-15: wobbly straight (3 rows -> 1 near-straight)" & vbCrLf & vbCrLf & _
           "Now double-click Integrate Bicycle to see the wobbly trace.", _
           vbInformation, "Simulate Wobbly Recon"

    LogEvent "BIKE", "SimulateWobblyRecon: 16-row synthetic log written"
    Exit Sub

ErrHandler:
    LogEvent "BIKE", "SimulateWobblyRecon error: " & Err.Description
    MsgBox "SimulateWobblyRecon error: " & Err.Description, vbExclamation
End Sub

' --- Helpers ---------------------------------------------------

' Write one CartLog event row.
Private Sub WriteEvent(ws As Worksheet, row As Long, t As Double, _
                       evtType As String, value As Double, _
                       desc As String, cumSteps As Double)
    ws.Cells(row, 1).value = SecToHms(t)
    ws.Cells(row, 2).value = evtType
    ws.Cells(row, 3).value = value
    ws.Cells(row, 4).value = desc
    ws.Cells(row, 5).value = Round(cumSteps, 0)
    ws.Cells(row, 6).value = Round(cumSteps, 0)
End Sub

' Advance simulated time and rear-step count by a leg duration.
' Note: we model RearSteps as straight-line distance (cumSteps += v * dt / M_PER_STEP).
' Real cart on an arc would show inner/outer divergence; the integrator only reads
' rear, so this is faithful enough for testing Smooth Selection. ByRef on t and
' cumSteps so the caller sees the advance.
Private Sub AdvanceLeg(durationSec As Double, v_mps As Double, _
                       mPerStep As Double, ByRef t As Double, _
                       ByRef cumSteps As Double)
    t = t + durationSec
    cumSteps = cumSteps + (durationSec * v_mps) / mPerStep
End Sub
