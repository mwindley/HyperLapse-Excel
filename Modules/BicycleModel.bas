Attribute VB_Name = "BicycleModel"
' ============================================================
' HyperLapse Cart — BicycleModel Module
'
' PURPOSE
'   Convert the event-driven Cart Log (timestamps + steering/speed
'   changes + TIC step counts) into a continuous (x, y, theta) ground
'   trace using a rear-axle bicycle / Ackermann model.
'
'   Inputs:  CartLog sheet (6 columns — populated by Cart.GetCartLog)
'   Outputs: Trace sheet  (7 columns — t, x, y, theta_deg, segment
'                          distance, steering, speed)
'            Chart on CartLog sheet (XY trace of x,y for the operator)
'
' STATUS day 8
'   M_PER_STEP measured = 0.00178 mm/step (~1.77 µm/step), validated
'     across 10-100 m/hr at locked OD=1.00 in three clean runs.
'   WHEELBASE_M = 0.490 m measured day 7.
'   SERVO_TO_DEG = 1.0 is a PLACEHOLDER. Real value comes from circle
'     test (workfront #20) — drive a known servo angle, measure circle
'     diameter, derive degrees-per-servo-PWM-unit.
'
' MATHS (rear-axle bicycle, no slip assumed)
'   For each segment between event i and event i+1:
'     d     = (rear_steps[i+1] - rear_steps[i]) * M_PER_STEP        [m]
'     phi   = wheel angle in radians (positive = left turn)
'     theta = current heading in radians (0 = +X axis, CCW positive)
'
'   Straight segment (|phi| < TINY):
'     x_new     = x + d * cos(theta)
'     y_new     = y + d * sin(theta)
'     theta_new = theta
'
'   Arc segment:
'     R         = WHEELBASE_M / tan(phi)        ' turning radius
'     dtheta    = d / R                          ' heading change
'     theta_new = theta + dtheta
'     x_new     = x + R * (sin(theta_new) - sin(theta))
'     y_new     = y - R * (cos(theta_new) - cos(theta))
'
'   Initial state: x = 0, y = 0, theta = 0 (cart points +X at start).
'
' USAGE
'   1. Run Cart.GetCartLog to retrieve the latest CartLog
'   2. Run BicycleModel.IntegrateBicycle (or click Control button)
'   3. View Trace sheet for numeric data; chart on CartLog renders xy
' ============================================================

Option Explicit

' --- Calibration constants ----------------------------------------
' Update these as measurements improve.

' Cart drivetrain: metres travelled per microstep at the rear axle.
' Day-8 measured: ~1.77 µm/step. Verified speed-independent 10-100 m/hr.
Public Const M_PER_STEP As Double = 0.00000178

' Wheelbase centre-to-centre (rear axle to front axle), metres.
' Day-7 measured.
Public Const WHEELBASE_M As Double = 0.49

' Servo PWM offset (from CART_STEERING_CENTRE) to wheel angle in degrees.
' Cart.bas servo values come through as offsets-from-centre.
' PLACEHOLDER — to be calibrated by circle test (workfront #20).
' Once known, replace with measured value.
Public Const SERVO_TO_DEG As Double = 1#

' Numerical tolerance for "this is a straight segment" — radians.
' Below this, we treat phi=0 to avoid divide-by-near-zero on tan(phi).
Private Const STRAIGHT_TINY As Double = 0.00017453  ' ~0.01 degree

' Visualisation: maximum arc length per emitted trace point. For real
' Cart Logs the operator may hold steering across long arcs (one T event,
' one X event) — that's only two trace points, so the chart would draw a
' straight chord instead of the arc. We subdivide arcs into pieces no
' longer than this value so the chart can render the curve. Maths is
' unchanged; we only add intermediate output rows.
Private Const ARC_VIZ_STEP_M As Double = 0.1

Private Const PI As Double = 3.14159265358979

' --- Public entry point -------------------------------------------

' Main entry point. Reads CartLog, integrates, writes Trace sheet,
' refreshes chart on CartLog.
Public Sub IntegrateBicycle()
    On Error GoTo ErrHandler

    Dim wsLog As Worksheet
    Set wsLog = Sheets("CartLog")

    Dim lastRow As Long
    lastRow = wsLog.Cells(wsLog.Rows.count, 1).End(xlUp).row
    If lastRow < 2 Then
        MsgBox "CartLog is empty. Run GetCartLog first.", vbExclamation
        Exit Sub
    End If

    ' Ensure Trace sheet exists with headers
    Dim wsTrace As Worksheet
    Set wsTrace = EnsureTraceSheet()

    ' Clear previous trace
    wsTrace.Range("A2:G" & wsTrace.Rows.count).ClearContents

    ' --- State -----------------------------------------------------
    Dim t_sec As Double, x_m As Double, y_m As Double, theta_rad As Double
    x_m = 0#: y_m = 0#: theta_rad = 0#

    ' Steering and speed are "current settings" — they persist between
    ' events until changed by an S or T row. Track them as we walk the log.
    Dim currentSteerVal As Double
    Dim currentSpeedVal As Double
    currentSteerVal = 0#  ' centred
    currentSpeedVal = 0#  ' stopped

    ' Read the first row to get the starting rear_steps reference.
    Dim prevRearSteps As Double
    prevRearSteps = SafeNum(wsLog.Cells(2, 5).value)
    Dim prevTimestamp As String
    prevTimestamp = CStr(wsLog.Cells(2, 1).value)

    ' Write the initial state (segment 0 — t=0, origin, no motion).
    Dim outRow As Long
    outRow = 2
    wsTrace.Cells(outRow, 1).value = 0#
    wsTrace.Cells(outRow, 2).value = 0#
    wsTrace.Cells(outRow, 3).value = 0#
    wsTrace.Cells(outRow, 4).value = 0#
    wsTrace.Cells(outRow, 5).value = 0#
    wsTrace.Cells(outRow, 6).value = 0#
    wsTrace.Cells(outRow, 7).value = 0#
    outRow = outRow + 1

    ' Apply the first event's settings (it may set initial speed / steering).
    ApplyEvent CStr(wsLog.Cells(2, 2).value), _
               SafeNum(wsLog.Cells(2, 3).value), _
               currentSteerVal, currentSpeedVal

    Dim r As Long
    For r = 3 To lastRow
        Dim evtType As String
        Dim evtValue As Double
        Dim rearSteps As Double
        Dim ts As String

        ts = CStr(wsLog.Cells(r, 1).value)
        evtType = CStr(wsLog.Cells(r, 2).value)
        evtValue = SafeNum(wsLog.Cells(r, 3).value)
        rearSteps = SafeNum(wsLog.Cells(r, 5).value)

        ' Segment distance from rear_steps delta (signed by direction —
        ' which is set by speed sign; here we trust the step count sign).
        Dim d_m As Double
        d_m = (rearSteps - prevRearSteps) * M_PER_STEP

        ' Steering angle held during the segment that just ended:
        ' it's the currentSteerVal BEFORE we apply this row's event.
        Dim phi_rad As Double
        phi_rad = SteerToRadians(currentSteerVal)

        ' Time at end of segment
        t_sec = HmsToSec(ts)
        Dim t_prev As Double
        If outRow = 3 Then
            t_prev = 0#
        Else
            t_prev = wsTrace.Cells(outRow - 1, 1).value
        End If

        ' Decide how many sub-steps to emit. Arc segments get subdivided
        ' for smooth chart rendering; straight and stationary segments
        ' don't need it. nSteps >= 1 always.
        Dim nSteps As Long
        If Abs(phi_rad) < STRAIGHT_TINY Or d_m = 0# Then
            nSteps = 1
        Else
            nSteps = CLng(Abs(d_m) / ARC_VIZ_STEP_M) + 1
            If nSteps < 1 Then nSteps = 1
        End If

        Dim k As Long
        For k = 1 To nSteps
            Dim d_sub As Double
            d_sub = d_m / CDbl(nSteps)
            Dim t_sub As Double
            t_sub = t_prev + (t_sec - t_prev) * (CDbl(k) / CDbl(nSteps))

            ' Integrate this sub-step
            Dim x_new As Double, y_new As Double, theta_new As Double
            BicycleStep x_m, y_m, theta_rad, d_sub, phi_rad, x_new, y_new, theta_new

            ' Write trace row
            wsTrace.Cells(outRow, 1).value = t_sub
            wsTrace.Cells(outRow, 2).value = x_new
            wsTrace.Cells(outRow, 3).value = y_new
            wsTrace.Cells(outRow, 4).value = NormalizeDeg(theta_new * 180# / PI)
            wsTrace.Cells(outRow, 5).value = d_sub
            wsTrace.Cells(outRow, 6).value = SteerToDeg(currentSteerVal)
            wsTrace.Cells(outRow, 7).value = currentSpeedVal
            outRow = outRow + 1

            ' Advance state
            x_m = x_new: y_m = y_new: theta_rad = theta_new
        Next k

        prevRearSteps = rearSteps

        ' Apply this event's effect on steering/speed (after the segment
        ' has been integrated using the previous setting).
        ApplyEvent evtType, evtValue, currentSteerVal, currentSpeedVal
    Next r

    ' Tidy formatting
    wsTrace.Columns("A:G").AutoFit

    ' Refresh/create chart on CartLog
    RefreshTraceChart wsLog, wsTrace, outRow - 1

    LogEvent "BIKE", "IntegrateBicycle: " & (outRow - 2) & " segments, " & _
             "end at (" & Format(x_m, "0.000") & ", " & Format(y_m, "0.000") & _
             ") m, heading " & Format(NormalizeDeg(theta_rad * 180# / PI), "0.0") & "°"
    Exit Sub

ErrHandler:
    LogEvent "BIKE", "IntegrateBicycle error: " & Err.Description
    MsgBox "IntegrateBicycle error: " & Err.Description, vbExclamation
End Sub

' --- Bicycle integration core -------------------------------------

' Integrate one segment of motion. Distance d_m signed (+ forward, − reverse).
' phi_rad is wheel steering angle in radians (+ left turn, − right turn).
Private Sub BicycleStep(ByVal x As Double, ByVal y As Double, _
                        ByVal theta As Double, _
                        ByVal d_m As Double, ByVal phi_rad As Double, _
                        ByRef x_new As Double, ByRef y_new As Double, _
                        ByRef theta_new As Double)
    If Abs(phi_rad) < STRAIGHT_TINY Then
        ' Straight segment
        x_new = x + d_m * Cos(theta)
        y_new = y + d_m * Sin(theta)
        theta_new = theta
    Else
        ' Arc segment — rear-axle bicycle model
        Dim R As Double
        R = WHEELBASE_M / Tan(phi_rad)
        Dim dtheta As Double
        dtheta = d_m / R
        theta_new = theta + dtheta
        x_new = x + R * (Sin(theta_new) - Sin(theta))
        y_new = y - R * (Cos(theta_new) - Cos(theta))
    End If
End Sub

' --- Helpers ------------------------------------------------------

' Apply an event row's effect to the running steering/speed state.
' Called AFTER the segment ending at this event has been integrated,
' so the new setting takes effect for the segment that follows.
Private Sub ApplyEvent(ByVal evtType As String, ByVal evtValue As Double, _
                       ByRef currentSteerVal As Double, _
                       ByRef currentSpeedVal As Double)
    Select Case UCase(Trim(evtType))
        Case "S"
            currentSpeedVal = evtValue   ' m/hr
        Case "T"
            currentSteerVal = evtValue   ' servo offset from centre
        Case "X"
            currentSpeedVal = 0#
        Case Else
            ' Unknown — leave state alone
    End Select
End Sub

' Convert servo offset (Cart.bas value column) to wheel angle in radians.
Private Function SteerToRadians(ByVal servoOffset As Double) As Double
    SteerToRadians = SteerToDeg(servoOffset) * PI / 180#
End Function

' Convert servo offset to wheel angle in degrees.
' PLACEHOLDER — circle test will give a real coefficient.
Private Function SteerToDeg(ByVal servoOffset As Double) As Double
    SteerToDeg = servoOffset * SERVO_TO_DEG
End Function

' Convert HH:MM:SS string to seconds (double).
Private Function HmsToSec(ByVal s As String) As Double
    On Error GoTo Fallback
    Dim parts() As String
    parts = Split(Trim(s), ":")
    If UBound(parts) >= 2 Then
        HmsToSec = CDbl(parts(0)) * 3600# + CDbl(parts(1)) * 60# + CDbl(parts(2))
        Exit Function
    End If
Fallback:
    HmsToSec = 0#
End Function

' Normalise an angle to (-180, +180] degrees for human-friendly display.
Private Function NormalizeDeg(ByVal d As Double) As Double
    Dim x As Double
    x = d
    Do While x > 180#
        x = x - 360#
    Loop
    Do While x <= -180#
        x = x + 360#
    Loop
    NormalizeDeg = x
End Function

' Safe numeric read — returns 0 if cell empty or non-numeric.
Private Function SafeNum(ByVal v As Variant) As Double
    If IsNumeric(v) Then
        SafeNum = CDbl(v)
    Else
        SafeNum = 0#
    End If
End Function

' --- Trace sheet management ---------------------------------------

' Ensure the Trace sheet exists with a header row. Create if missing.
Private Function EnsureTraceSheet() As Worksheet
    Dim ws As Worksheet
    Set ws = Nothing
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("Trace")
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add( _
            After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.count))
        ws.Name = "Trace"
    End If

    ' Write headers (overwrite, in case columns evolved between versions)
    ws.Cells(1, 1).value = "t_sec"
    ws.Cells(1, 2).value = "x_m"
    ws.Cells(1, 3).value = "y_m"
    ws.Cells(1, 4).value = "theta_deg"
    ws.Cells(1, 5).value = "segment_dist_m"
    ws.Cells(1, 6).value = "steering_deg"
    ws.Cells(1, 7).value = "speed_mhr"
    ws.Range("A1:G1").Font.Bold = True

    Set EnsureTraceSheet = ws
End Function

' Build (or refresh) an XY scatter chart on the CartLog sheet showing
' the (x,y) path. Lines connect successive points so the operator sees
' the trace as a continuous route.
Private Sub RefreshTraceChart(ByVal wsLog As Worksheet, _
                              ByVal wsTrace As Worksheet, _
                              ByVal lastTraceRow As Long)
    On Error GoTo Done

    If lastTraceRow < 2 Then Exit Sub

    ' Remove any existing chart called "TraceChart"
    Dim co As ChartObject
    For Each co In wsLog.ChartObjects
        If co.Name = "TraceChart" Then co.Delete
    Next co

    ' Place chart to the right of the data
    Dim left_pt As Double, top_pt As Double
    left_pt = wsLog.Cells(2, 8).Left
    top_pt = wsLog.Cells(2, 8).Top

    Dim cobj As ChartObject
    Set cobj = wsLog.ChartObjects.Add(left_pt, top_pt, 480, 360)
    cobj.Name = "TraceChart"

    With cobj.Chart
        .ChartType = xlXYScatterLines
        .HasTitle = True
        .ChartTitle.Text = "Cart trace (rear axle, m)"
        .HasLegend = False

        ' Add a single series with x in column B and y in column C
        .SeriesCollection.NewSeries
        With .SeriesCollection(1)
            .Name = "Trace"
            .XValues = wsTrace.Range("B2:B" & lastTraceRow)
            .Values = wsTrace.Range("C2:C" & lastTraceRow)
            .MarkerStyle = xlMarkerStyleCircle
            .MarkerSize = 4
        End With

        ' Equal-ish axes by default — Excel won't enforce true 1:1 aspect,
        ' but at least give the chart room to show the shape.
        With .Axes(xlCategory)
            .HasTitle = True
            .AxisTitle.Text = "x (m)"
        End With
        With .Axes(xlValue)
            .HasTitle = True
            .AxisTitle.Text = "y (m)"
        End With
    End With

Done:
End Sub

' --- Button callback for Control sheet ----------------------------

Public Sub btnIntegrateBicycle()
    Call IntegrateBicycle
End Sub

' --- Test fixture: simulate a Cart Log -----------------------------
'
' Writes a known synthetic log into the CartLog sheet, so the
' integrator can be tested without driving the cart.
'
' Shape: drive straight 5 m, then a 90-degree left arc at R = 2 m,
' then stop. End position should be approximately (5 + 2, 2) = (7, 2)
' with heading +90 degrees. Chart should look like an L.
'
' Numbers below use day-8 measured M_PER_STEP = 1.78 um/step.
'
Public Sub SimulateCartLog()
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = Sheets("CartLog")

    ' Clear existing
    ws.Cells.Clear

    ' Headers
    ws.Cells(1, 1).value = "Timestamp"
    ws.Cells(1, 2).value = "Type"
    ws.Cells(1, 3).value = "Value"
    ws.Cells(1, 4).value = "Description"
    ws.Cells(1, 5).value = "RearSteps"
    ws.Cells(1, 6).value = "FrontSteps"
    ws.Range("A1:F1").Font.Bold = True

    ' Constants for this simulation
    Const SIM_M_PER_STEP As Double = 0.00000178
    Const SIM_SPEED_MHR As Double = 100#       ' 100 m/hr to keep times short
    Const SIM_PHI_DEG As Double = 13.77        ' atan(0.49/2) = ~13.77° -> R=2m arc
    Const SIM_STRAIGHT_M As Double = 5#
    Const SIM_ARC_M As Double = 3.14159265358979 ' quarter-circle at R=2m

    Dim v_mps As Double
    v_mps = SIM_SPEED_MHR / 3600#

    ' Build the synthetic events
    Dim row As Long
    row = 2

    ' t=0: speed 0 (initial state)
    ws.Cells(row, 1).value = "00:00:00"
    ws.Cells(row, 2).value = "S"
    ws.Cells(row, 3).value = 0
    ws.Cells(row, 4).value = "Speed set to 0 m/hr"
    ws.Cells(row, 5).value = 0
    ws.Cells(row, 6).value = 0
    row = row + 1

    ' t=0: steering centred
    ws.Cells(row, 1).value = "00:00:00"
    ws.Cells(row, 2).value = "T"
    ws.Cells(row, 3).value = 0
    ws.Cells(row, 4).value = "Steering centred"
    ws.Cells(row, 5).value = 0
    ws.Cells(row, 6).value = 0
    row = row + 1

    ' t=1: speed up to 100 m/hr (drive begins)
    ws.Cells(row, 1).value = SecToHms(1)
    ws.Cells(row, 2).value = "S"
    ws.Cells(row, 3).value = SIM_SPEED_MHR
    ws.Cells(row, 4).value = "Speed set to " & SIM_SPEED_MHR & " m/hr"
    ws.Cells(row, 5).value = 0
    ws.Cells(row, 6).value = 0
    row = row + 1

    ' t = 1 + straight_time : start of arc — apply steering
    Dim t_end_straight As Double
    t_end_straight = 1# + (SIM_STRAIGHT_M / v_mps)
    Dim steps_after_straight As Double
    steps_after_straight = SIM_STRAIGHT_M / SIM_M_PER_STEP

    ws.Cells(row, 1).value = SecToHms(t_end_straight)
    ws.Cells(row, 2).value = "T"
    ws.Cells(row, 3).value = SIM_PHI_DEG
    ws.Cells(row, 4).value = "Steering to " & Format(SIM_PHI_DEG, "0.00") & " deg (left, R=2m)"
    ws.Cells(row, 5).value = Round(steps_after_straight, 0)
    ws.Cells(row, 6).value = Round(steps_after_straight, 0)
    row = row + 1

    ' t = end of arc : stop
    Dim t_end_arc As Double
    t_end_arc = t_end_straight + (SIM_ARC_M / v_mps)
    Dim steps_after_arc As Double
    steps_after_arc = (SIM_STRAIGHT_M + SIM_ARC_M) / SIM_M_PER_STEP

    ws.Cells(row, 1).value = SecToHms(t_end_arc)
    ws.Cells(row, 2).value = "X"
    ws.Cells(row, 3).value = 0
    ws.Cells(row, 4).value = "Stop"
    ws.Cells(row, 5).value = Round(steps_after_arc, 0)
    ws.Cells(row, 6).value = Round(steps_after_arc, 0)
    row = row + 1

    ws.Columns("A:F").AutoFit
    ws.Columns(1).NumberFormat = "@"

    MsgBox "Simulated Cart Log written:" & vbCrLf & _
           "  Straight 5 m, then 90 deg left arc at R=2 m, then stop." & vbCrLf & _
           "  Expected end position: (~7, ~2) m, heading +90 deg." & vbCrLf & vbCrLf & _
           "Now double-click Integrate Bicycle to test.", _
           vbInformation, "Simulate Cart Log"

    LogEvent "BIKE", "SimulateCartLog: synthetic log written"
    Exit Sub

ErrHandler:
    LogEvent "BIKE", "SimulateCartLog error: " & Err.Description
    MsgBox "SimulateCartLog error: " & Err.Description, vbExclamation
End Sub

' Helper: seconds (Double) to HH:MM:SS string
Private Function SecToHms(ByVal s As Double) As String
    Dim h As Long, m As Long, sec As Long
    Dim totalSec As Long
    totalSec = CLng(s + 0.5) - 1   ' floor-ish
    If totalSec < 0 Then totalSec = 0
    h = totalSec \ 3600
    m = (totalSec Mod 3600) \ 60
    sec = totalSec Mod 60
    SecToHms = Format(h, "00") & ":" & Format(m, "00") & ":" & Format(sec, "00")
End Function
