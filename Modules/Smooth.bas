Attribute VB_Name = "Smooth"
' ============================================================
' HyperLapse Cart — Smooth Selection Module (workfront #44)
'
' PURPOSE
'   Take a wobbly multi-row segment of CartLog (operator's drive recon)
'   and propose a single clean arc that achieves the same start->end
'   position + heading. Operator inspects the overlay, then commits or
'   discards.
'
' WORKFLOW (operator-facing, all on CartLog sheet)
'   1. Highlight contiguous rows in CartLog (e.g. rows 5..8)
'   2. Double-click "Smooth Selection" button (cell G1)
'      -> computes proposed arc, writes it to hidden cells Q1..T6,
'         draws an overlay series on the chart, sets status banner
'   3. Inspect the overlay. Then either:
'      - Double-click "Commit Smooth" (H1) -> rewrites CartLog rows
'        as 2-row arc form, re-integrates, clears proposal
'      - Double-click "Discard Smooth" (I1) -> clears proposal + overlay
'   4. Excel native Ctrl+Z undoes a Commit (one step).
'
' ARC RULE (option 2, locked in chat day 10)
'   N selected rows -> always 2 rows after commit:
'     - First row: T-event with computed steering value, RearSteps = the
'                  RearSteps of the first selected row (unchanged)
'     - Last row : T-event with steering = 0 (return to centre),
'                  RearSteps = RearSteps of the last selected row
'                              (preserves total distance)
'   Selection boundary = arc boundary. Neighbouring rows untouched.
'
' MATHS — chord-to-arc inverse
'   Given (x0, y0, theta0) at start and (x1, y1, theta1) at end:
'     chord_dx  = x1 - x0
'     chord_dy  = y1 - y0
'     chord     = sqrt(chord_dx^2 + chord_dy^2)
'     dtheta    = NormaliseSigned(theta1 - theta0)        radians
'     If |dtheta| < TINY:
'         steering_deg = 0
'         arc_length   = chord
'     Else:
'         R            = chord / (2 * sin(dtheta/2))      signed
'         arc_length   = R * dtheta                       always positive
'         phi_wheel    = atan(WHEELBASE_M / R)            wheel-angle radians
'         steering_deg = (phi_wheel * 180/PI) / SERVO_TO_DEG
'   Sign convention: positive dtheta = left turn = positive wheel angle
'                    = negative steering value in CartLog (matches the
'                    "Steer left 5 deg" convention used in existing log).
'
' HIDDEN PROPOSAL STORAGE on CartLog
'   Q1: "PendingProposal"  (label, also acts as flag — non-empty => pending)
'   Q2: start_row          (Excel row index of first selected row)
'   Q3: end_row            (Excel row index of last selected row)
'   Q4: steering_value     (the value to write in column C of start row)
'   Q5: R_metres           (turning radius, for status banner)
'   Q6: deviation_mm       (max perp distance from wobbly to proposed arc)
'   S2..T26 (25 rows max): proposed arc (x, y) sample points for overlay
'
'   Hidden = column width 0 once the layout is built. Operator never
'   scrolls there; macros read/write directly by column letter.
'
' STATUS BANNER
'   J1 cell shows either "" (no proposal) or
'   "PROPOSAL PENDING: rows 5-8 -> R=2.3m, deviation 80mm"
'
' DEPENDENCIES
'   - BicycleModel.bas (M_PER_STEP, WHEELBASE_M, SERVO_TO_DEG,
'     IntegrateBicycle, the Trace sheet with CartLogRow in column H)
'   - Utils.bas (LogEvent)
'   - The chart "TraceChart" on CartLog sheet, built by RefreshTraceChart
' ============================================================

Option Explicit

' --- Constants -----------------------------------------------------

' Cell addresses on CartLog where pending-proposal data lives.
' Q column = "proposal metadata", S..T = "proposal arc xy samples".
Private Const PROP_FLAG_CELL    As String = "Q1"
Private Const PROP_STARTROW     As String = "Q2"
Private Const PROP_ENDROW       As String = "Q3"
Private Const PROP_STEER        As String = "Q4"
Private Const PROP_R_M          As String = "Q5"
Private Const PROP_DEV_MM       As String = "Q6"
Private Const PROP_ARC_XY_FIRST As String = "S2"     ' first (x,y) sample
Private Const PROP_ARC_MAX_SAMPLES As Long = 50      ' max points in overlay

' Status banner cell, visible above the chart.
Private Const STATUS_BANNER_CELL As String = "J1"

' Sentinel string written to PROP_FLAG_CELL to mark "proposal pending".
Private Const PROP_FLAG_TEXT As String = "PendingProposal"

' Number of (x, y) samples in the overlay arc — keep low; the chart
' draws a smooth curve regardless because it's only 30+ points across
' a few metres of arc.
Private Const ARC_SAMPLE_COUNT As Long = 30

' Tolerance for "straight" (radians of heading change below which we
' treat the segment as a chord, not an arc).
Private Const ARC_STRAIGHT_TINY As Double = 0.00017453   ' ~0.01 deg

Private Const PI As Double = 3.14159265358979

' Stash of the last "data row" selection on CartLog. Written by the
' Worksheet_SelectionChange handler in the CartLog sheet's code
' module; read by btnSmoothSelection. Public so the sheet can write
' to it from outside this module — VBA needs Public variables for
' cross-module write access.
Public gLastCartLogSelection As String


' ============================================================
' BUTTON 1 — Smooth Selection
' ============================================================
'
' Reads operator's current Selection on CartLog. Maps first and last
' selected rows to (x, y, theta) on Trace. Computes single-arc
' replacement. Writes proposal to hidden cells. Draws overlay series
' on the existing TraceChart. Sets status banner.
'
' Does NOT modify CartLog rows. Commit step does that.
'
Public Sub btnSmoothSelection()
    On Error GoTo ErrHandler

    Dim wsLog As Worksheet
    Set wsLog = Sheets("CartLog")

    Dim wsTrace As Worksheet
    Set wsTrace = Sheets("Trace")

    ' Pull the operator's last data-row selection from the module-
    ' level stash. The button-cell double-click changes the live
    ' Selection out from under us, so we rely on the SelectionChange
    ' handler in the CartLog sheet's code module to keep this fresh.
    Dim selAddress As String
    selAddress = gLastCartLogSelection

    ' DIAGNOSTIC — temporary, remove once this works.
    Debug.Print "[Smooth] selAddress = '" & selAddress & "'"
    LogEvent "SMOOTH", "selAddress='" & selAddress & "'"

    If selAddress = "" Then
        MsgBox "No row selection remembered." & vbCrLf & vbCrLf & _
               "Click on the data rows in CartLog you want to smooth," & vbCrLf & _
               "then double-click Smooth Selection.", _
               vbExclamation, "Smooth Selection"
        Exit Sub
    End If

    Dim sel As Range
    Set sel = wsLog.Range(selAddress)

    ' Find first and last DATA rows in the selection. Header row 1 is
    ' excluded; we only operate on rows >= 2.
    Dim firstRow As Long, lastRow As Long
    firstRow = sel.Row
    lastRow = sel.Row + sel.Rows.count - 1
    If firstRow < 2 Then firstRow = 2
    If lastRow < firstRow Then
        MsgBox "Selection looks empty. Highlight at least one data row.", _
               vbExclamation, "Smooth Selection"
        Exit Sub
    End If
    If lastRow = firstRow Then
        MsgBox "Selection is a single row — nothing to smooth." & vbCrLf & _
               "Highlight at least 2 rows (start and end of the wobble).", _
               vbExclamation, "Smooth Selection"
        Exit Sub
    End If

    ' Refuse if a proposal is already pending — operator must commit
    ' or discard first. Avoids confusion about which one is "current".
    If wsLog.Range(PROP_FLAG_CELL).value = PROP_FLAG_TEXT Then
        MsgBox "A proposal is already pending. Commit or Discard it first.", _
               vbExclamation, "Smooth Selection"
        Exit Sub
    End If

    ' Map firstRow / lastRow on CartLog to (x, y, theta) on Trace via
    ' the CartLogRow column (Trace column H). Each event row in
    ' CartLog has exactly one corresponding final sub-step row in
    ' Trace where H = the CartLog Excel row index.
    Dim x0 As Double, y0 As Double, theta0_rad As Double
    Dim x1 As Double, y1 As Double, theta1_rad As Double
    Dim ok As Boolean

    ok = FindTracePointForCartLogRow(wsTrace, firstRow, x0, y0, theta0_rad)
    If Not ok Then
        ' Special case: firstRow is the very first event after the
        ' initial S+T pair (rows 2-3). Start position is the origin.
        If firstRow <= 4 Then
            x0 = 0#: y0 = 0#: theta0_rad = 0#
        Else
            MsgBox "Could not locate start row " & firstRow & " on Trace sheet." & _
                   vbCrLf & "Did you run Integrate Bicycle after the latest log?", _
                   vbExclamation, "Smooth Selection"
            Exit Sub
        End If
    End If

    ok = FindTracePointForCartLogRow(wsTrace, lastRow, x1, y1, theta1_rad)
    If Not ok Then
        MsgBox "Could not locate end row " & lastRow & " on Trace sheet." & _
               vbCrLf & "Did you run Integrate Bicycle after the latest log?", _
               vbExclamation, "Smooth Selection"
        Exit Sub
    End If

    ' Compute the single-arc replacement.
    Dim steering_deg As Double, R_m As Double
    Dim arc_length_m As Double, dtheta_rad As Double
    Call ComputeArc(x0, y0, theta0_rad, x1, y1, theta1_rad, _
                    steering_deg, R_m, arc_length_m, dtheta_rad)

    ' Convert wheel-angle degrees back to the value in CartLog's Value
    ' column. Cart.bas writes steering as servo-offset units; the
    ' integrator multiplies by SERVO_TO_DEG (=1 placeholder) to get
    ' wheel angle. We invert: steer_value = wheel_deg / SERVO_TO_DEG.
    Dim steer_value As Double
    steer_value = steering_deg / SERVO_TO_DEG

    ' Estimate deviation: max perpendicular distance from each Trace
    ' (x, y) row that falls within firstRow..lastRow to the proposed
    ' arc. Quick numerical scan; not exact, good enough for a status
    ' line.
    Dim deviation_mm As Double
    deviation_mm = EstimateDeviation(wsTrace, firstRow, lastRow, _
                                      x0, y0, theta0_rad, _
                                      R_m, dtheta_rad)

    ' Write proposal to hidden cells.
    wsLog.Range(PROP_FLAG_CELL).value = PROP_FLAG_TEXT
    wsLog.Range(PROP_STARTROW).value = firstRow
    wsLog.Range(PROP_ENDROW).value = lastRow
    wsLog.Range(PROP_STEER).value = steer_value
    wsLog.Range(PROP_R_M).value = R_m
    wsLog.Range(PROP_DEV_MM).value = deviation_mm

    ' Write the arc XY samples for the chart overlay.
    Call WriteArcSamples(wsLog, x0, y0, theta0_rad, R_m, dtheta_rad)

    ' Status banner — visible above the chart.
    Dim banner As String
    If Abs(dtheta_rad) < ARC_STRAIGHT_TINY Then
        banner = "PROPOSAL PENDING: rows " & firstRow & "-" & lastRow & _
                 " -> near-straight (R large), deviation " & _
                 Format(deviation_mm, "0") & "mm"
    Else
        banner = "PROPOSAL PENDING: rows " & firstRow & "-" & lastRow & _
                 " -> R=" & Format(Abs(R_m), "0.0") & "m, " & _
                 "steer " & Format(steering_deg, "0.0") & "°, " & _
                 "deviation " & Format(deviation_mm, "0") & "mm"
    End If
    wsLog.Range(STATUS_BANNER_CELL).value = banner

    ' Refresh chart so the overlay series shows up.
    Call RefreshChartWithOverlay(wsLog, wsTrace)

    LogEvent "SMOOTH", "Proposal: rows " & firstRow & "-" & lastRow & _
             " R=" & Format(R_m, "0.00") & "m steer=" & _
             Format(steering_deg, "0.00") & "° dev=" & _
             Format(deviation_mm, "0") & "mm"
    Exit Sub

ErrHandler:
    LogEvent "SMOOTH", "btnSmoothSelection error: " & Err.Description
    MsgBox "Smooth Selection error: " & Err.Description, vbExclamation
End Sub


' ============================================================
' BUTTON 2 — Commit Smooth
' ============================================================
'
' Apply the pending proposal: replace CartLog rows [start..end] with
' the 2-row arc form, then re-integrate.
'
Public Sub btnCommitSmooth()
    On Error GoTo ErrHandler

    Dim wsLog As Worksheet
    Set wsLog = Sheets("CartLog")

    If wsLog.Range(PROP_FLAG_CELL).value <> PROP_FLAG_TEXT Then
        MsgBox "No proposal pending. Run Smooth Selection first.", _
               vbExclamation, "Commit Smooth"
        Exit Sub
    End If

    Dim startRow As Long, endRow As Long
    Dim steerValue As Double
    startRow = CLng(wsLog.Range(PROP_STARTROW).value)
    endRow = CLng(wsLog.Range(PROP_ENDROW).value)
    steerValue = CDbl(wsLog.Range(PROP_STEER).value)

    ' Capture the data we keep from the original rows:
    '   - startRow's RearSteps (the "enter the arc here" reference)
    '   - endRow's RearSteps (the "exit the arc here" reference —
    '     preserves total distance travelled across the selection)
    Dim startRearSteps As Double, endRearSteps As Double
    Dim startTimestamp As String, endTimestamp As String
    startTimestamp = CStr(wsLog.Cells(startRow, 1).value)
    endTimestamp = CStr(wsLog.Cells(endRow, 1).value)
    startRearSteps = CDbl(wsLog.Cells(startRow, 5).value)
    endRearSteps = CDbl(wsLog.Cells(endRow, 5).value)

    ' Plan A: write the two new rows in place at startRow and endRow.
    ' Then delete the rows in between (startRow+1 .. endRow-1).
    ' Doing it this way preserves Excel-undo behaviour: it's one
    ' Cells.value batch + one Rows.Delete; Ctrl+Z reverts both.

    ' Row at startRow: T event with computed steering.
    wsLog.Cells(startRow, 1).value = startTimestamp     ' unchanged
    wsLog.Cells(startRow, 2).value = "T"
    wsLog.Cells(startRow, 3).value = steerValue
    wsLog.Cells(startRow, 4).value = "Smoothed: enter arc steer=" & _
                                     Format(steerValue, "0.00")
    wsLog.Cells(startRow, 5).value = startRearSteps     ' unchanged
    wsLog.Cells(startRow, 6).value = wsLog.Cells(startRow, 6).value

    ' Row at endRow: T event returning to centre, RearSteps preserved.
    wsLog.Cells(endRow, 1).value = endTimestamp         ' unchanged
    wsLog.Cells(endRow, 2).value = "T"
    wsLog.Cells(endRow, 3).value = 0
    wsLog.Cells(endRow, 4).value = "Smoothed: exit arc, steer centre"
    wsLog.Cells(endRow, 5).value = endRearSteps         ' unchanged
    wsLog.Cells(endRow, 6).value = wsLog.Cells(endRow, 6).value

    ' Delete the rows in between.
    If endRow - startRow >= 2 Then
        wsLog.Rows((startRow + 1) & ":" & (endRow - 1)).Delete Shift:=xlUp
    End If

    ' Clear the proposal cells now that the change is committed.
    Call ClearProposal(wsLog)

    ' Re-integrate so Trace and the chart reflect the smoothed log.
    Call IntegrateBicycle

    LogEvent "SMOOTH", "Committed: rows " & startRow & "-" & endRow & _
             " -> 2 rows, steer=" & Format(steerValue, "0.00")
    Exit Sub

ErrHandler:
    LogEvent "SMOOTH", "btnCommitSmooth error: " & Err.Description
    MsgBox "Commit Smooth error: " & Err.Description, vbExclamation
End Sub


' ============================================================
' BUTTON 3 — Discard Smooth
' ============================================================
'
' Throw away the pending proposal. Clear hidden cells + status banner
' + remove the overlay series from the chart.
'
Public Sub btnDiscardSmooth()
    On Error GoTo ErrHandler

    Dim wsLog As Worksheet
    Set wsLog = Sheets("CartLog")

    If wsLog.Range(PROP_FLAG_CELL).value <> PROP_FLAG_TEXT Then
        ' Nothing to discard — silently no-op rather than nag.
        Exit Sub
    End If

    Call ClearProposal(wsLog)

    ' Redraw chart without the overlay (i.e. trace-only).
    Dim wsTrace As Worksheet
    Set wsTrace = Sheets("Trace")
    Call RefreshChartWithOverlay(wsLog, wsTrace)

    LogEvent "SMOOTH", "Discarded pending proposal"
    Exit Sub

ErrHandler:
    LogEvent "SMOOTH", "btnDiscardSmooth error: " & Err.Description
End Sub


' ============================================================
' Internal — proposal storage helpers
' ============================================================

Private Sub ClearProposal(ByVal wsLog As Worksheet)
    wsLog.Range(PROP_FLAG_CELL).ClearContents
    wsLog.Range(PROP_STARTROW).ClearContents
    wsLog.Range(PROP_ENDROW).ClearContents
    wsLog.Range(PROP_STEER).ClearContents
    wsLog.Range(PROP_R_M).ClearContents
    wsLog.Range(PROP_DEV_MM).ClearContents
    wsLog.Range(STATUS_BANNER_CELL).ClearContents
    ' Clear the arc XY samples.
    wsLog.Range("S2:T" & (1 + PROP_ARC_MAX_SAMPLES)).ClearContents
End Sub


' ============================================================
' Internal — arc maths
' ============================================================

' Compute the single-arc replacement: given two endpoint poses,
' return the wheel steering angle (degrees), turning radius (metres,
' signed), arc length (metres, positive), and heading change (radians,
' signed).
Private Sub ComputeArc(ByVal x0 As Double, ByVal y0 As Double, _
                        ByVal theta0 As Double, _
                        ByVal x1 As Double, ByVal y1 As Double, _
                        ByVal theta1 As Double, _
                        ByRef steering_deg As Double, _
                        ByRef R_m As Double, _
                        ByRef arc_length As Double, _
                        ByRef dtheta As Double)
    Dim chord_dx As Double, chord_dy As Double, chord As Double
    chord_dx = x1 - x0
    chord_dy = y1 - y0
    chord = Sqr(chord_dx * chord_dx + chord_dy * chord_dy)

    dtheta = NormaliseSignedRad(theta1 - theta0)

    If Abs(dtheta) < ARC_STRAIGHT_TINY Then
        ' Near-straight — large-radius arc treated as chord.
        R_m = 1000000#                 ' "very large"
        arc_length = chord
        steering_deg = 0#
    Else
        ' Signed R from chord-arc geometry. Positive R = left turn.
        R_m = chord / (2# * Sin(dtheta / 2#))
        arc_length = Abs(R_m * dtheta)
        ' Inverse bicycle: phi = atan(WHEELBASE / R)
        Dim phi_rad As Double
        phi_rad = Atn(WHEELBASE_M / R_m)
        steering_deg = phi_rad * 180# / PI
    End If
End Sub

' Estimate max perpendicular distance from the wobbly Trace points
' (within the selected CartLog row range) to the proposed arc.
' Approximate but adequate for the status line.
Private Function EstimateDeviation(ByVal wsTrace As Worksheet, _
                                    ByVal firstRow As Long, _
                                    ByVal lastRow As Long, _
                                    ByVal x0 As Double, _
                                    ByVal y0 As Double, _
                                    ByVal theta0 As Double, _
                                    ByVal R_m As Double, _
                                    ByVal dtheta As Double) As Double
    Dim maxDev As Double
    maxDev = 0#

    ' Arc centre — perpendicular to initial heading, distance R.
    Dim cx As Double, cy As Double
    cx = x0 + R_m * Cos(theta0 + PI / 2#)
    cy = y0 + R_m * Sin(theta0 + PI / 2#)
    Dim absR As Double
    absR = Abs(R_m)

    ' Scan Trace rows; each row in [firstRow..lastRow] should have a
    ' Trace point with CartLogRow = that row index (Trace column H).
    ' Distance from each such Trace (x,y) to the arc = | dist_to_centre - |R| |.
    ' Near-straight case (R huge): use perpendicular distance to chord.
    Dim lastTraceRow As Long
    lastTraceRow = wsTrace.Cells(wsTrace.Rows.count, 1).End(xlUp).Row

    Dim r As Long
    For r = 2 To lastTraceRow
        Dim cartRow As Variant
        cartRow = wsTrace.Cells(r, 8).value
        If IsNumeric(cartRow) Then
            Dim cr As Long
            cr = CLng(cartRow)
            If cr >= firstRow And cr <= lastRow Then
                Dim px As Double, py As Double
                px = wsTrace.Cells(r, 2).value
                py = wsTrace.Cells(r, 3).value
                Dim dev As Double
                If absR > 100000# Then
                    ' Near-straight: perpendicular distance to chord
                    ' from (x0,y0) along heading theta0.
                    Dim hx As Double, hy As Double
                    hx = Cos(theta0): hy = Sin(theta0)
                    Dim relx As Double, rely As Double
                    relx = px - x0: rely = py - y0
                    ' perp = | rely*hx - relx*hy |
                    dev = Abs(rely * hx - relx * hy)
                Else
                    Dim dx As Double, dy As Double
                    dx = px - cx: dy = py - cy
                    dev = Abs(Sqr(dx * dx + dy * dy) - absR)
                End If
                If dev > maxDev Then maxDev = dev
            End If
        End If
    Next r

    EstimateDeviation = maxDev * 1000#   ' to mm
End Function

' Normalise an angle to (-pi, +pi] radians.
Private Function NormaliseSignedRad(ByVal a As Double) As Double
    Dim x As Double
    x = a
    Do While x > PI
        x = x - 2# * PI
    Loop
    Do While x <= -PI
        x = x + 2# * PI
    Loop
    NormaliseSignedRad = x
End Function

' Write ARC_SAMPLE_COUNT (x,y) sample points along the proposed arc
' into hidden cells S2:T(1+ARC_SAMPLE_COUNT). The chart overlay
' series reads from this range.
Private Sub WriteArcSamples(ByVal wsLog As Worksheet, _
                             ByVal x0 As Double, ByVal y0 As Double, _
                             ByVal theta0 As Double, _
                             ByVal R_m As Double, ByVal dtheta As Double)
    Dim n As Long
    n = ARC_SAMPLE_COUNT

    ' Clear any old samples first
    wsLog.Range("S2:T" & (1 + PROP_ARC_MAX_SAMPLES)).ClearContents

    Dim i As Long
    For i = 0 To n - 1
        Dim t As Double
        t = CDbl(i) / CDbl(n - 1)        ' 0..1
        Dim x As Double, y As Double
        Call ArcPointAt(x0, y0, theta0, R_m, dtheta, t, x, y)
        wsLog.Range("S" & (2 + i)).value = x
        wsLog.Range("T" & (2 + i)).value = y
    Next i
End Sub

' Sample one point along the arc, parameter t in [0,1].
Private Sub ArcPointAt(ByVal x0 As Double, ByVal y0 As Double, _
                        ByVal theta0 As Double, _
                        ByVal R_m As Double, ByVal dtheta As Double, _
                        ByVal t As Double, _
                        ByRef x_out As Double, ByRef y_out As Double)
    If Abs(dtheta) < ARC_STRAIGHT_TINY Then
        ' Near-straight: linear interp along heading.
        Dim chord As Double
        chord = Abs(R_m * dtheta)        ' approx 0; instead use arc_length
        ' Use t * arc_length along heading
        x_out = x0 + t * R_m * dtheta * Cos(theta0)   ' = approx 0
        y_out = y0 + t * R_m * dtheta * Sin(theta0)
    Else
        Dim theta_t As Double
        theta_t = theta0 + t * dtheta
        x_out = x0 + R_m * (Sin(theta_t) - Sin(theta0))
        y_out = y0 - R_m * (Cos(theta_t) - Cos(theta0))
    End If
End Sub


' ============================================================
' Internal — Trace lookup
' ============================================================

' Find the Trace row whose CartLogRow (column H) equals the given
' CartLog Excel row number. Returns its (x, y) and theta (radians).
Private Function FindTracePointForCartLogRow(ByVal wsTrace As Worksheet, _
                                              ByVal cartLogRow As Long, _
                                              ByRef x_out As Double, _
                                              ByRef y_out As Double, _
                                              ByRef theta_rad_out As Double) As Boolean
    Dim lastTraceRow As Long
    lastTraceRow = wsTrace.Cells(wsTrace.Rows.count, 1).End(xlUp).Row

    Dim r As Long
    For r = 2 To lastTraceRow
        Dim v As Variant
        v = wsTrace.Cells(r, 8).value
        If IsNumeric(v) Then
            If CLng(v) = cartLogRow Then
                x_out = wsTrace.Cells(r, 2).value
                y_out = wsTrace.Cells(r, 3).value
                theta_rad_out = wsTrace.Cells(r, 4).value * PI / 180#
                FindTracePointForCartLogRow = True
                Exit Function
            End If
        End If
    Next r
    FindTracePointForCartLogRow = False
End Function


' ============================================================
' Internal — chart overlay
' ============================================================

' Re-draw the TraceChart with the wobbly trace as series 1, and (if
' a proposal is pending) the proposed arc as series 2. Series 2 reads
' from the hidden S2:T(...) range.
'
' This is a thin wrapper that calls back into IntegrateBicycle's
' chart refresh — but we need to add the overlay ourselves because
' RefreshTraceChart only knows about the single trace series.
Private Sub RefreshChartWithOverlay(ByVal wsLog As Worksheet, _
                                     ByVal wsTrace As Worksheet)
    Dim co As ChartObject
    Dim cobj As ChartObject
    Set cobj = Nothing
    For Each co In wsLog.ChartObjects
        If co.Name = "TraceChart" Then
            Set cobj = co
            Exit For
        End If
    Next co

    If cobj Is Nothing Then
        ' No chart yet — let IntegrateBicycle build one, then we add overlay.
        Call IntegrateBicycle
        For Each co In wsLog.ChartObjects
            If co.Name = "TraceChart" Then
                Set cobj = co
                Exit For
            End If
        Next co
        If cobj Is Nothing Then Exit Sub
    End If

    With cobj.Chart
        ' Remove any existing overlay series (series 2).
        Do While .SeriesCollection.count > 1
            .SeriesCollection(.SeriesCollection.count).Delete
        Loop

        ' If proposal pending, add the overlay.
        If wsLog.Range(PROP_FLAG_CELL).value = PROP_FLAG_TEXT Then
            ' Find the last populated arc sample row.
            Dim lastArcRow As Long
            lastArcRow = wsLog.Cells(wsLog.Rows.count, "S").End(xlUp).Row
            If lastArcRow >= 2 Then
                .SeriesCollection.NewSeries
                With .SeriesCollection(2)
                    .Name = "Proposed arc"
                    .XValues = wsLog.Range("S2:S" & lastArcRow)
                    .Values = wsLog.Range("T2:T" & lastArcRow)
                    .MarkerStyle = xlMarkerStyleNone
                    With .Format.Line
                        .Visible = msoTrue
                        .Weight = 2.5
                        .ForeColor.RGB = RGB(220, 60, 30)    ' red-orange
                    End With
                End With
            End If
        End If
    End With
End Sub


' ============================================================
' Setup — paints the three button cells and status banner on CartLog
' ============================================================
'
' Run once after importing this module. Reuses CellFormat from
' Buttons.bas for the visual styling.
'
' Also reminds the operator that the sheet-code-module handler still
' needs to be pasted by hand (matches Control sheet pattern).
'
Public Sub BuildCartLogButtons()
    Dim ws As Worksheet
    Set ws = Sheets("CartLog")

    ' Three button cells at G1, H1, I1. Status banner at J1.
    ws.Cells(1, 7).value = "Smooth Selection"
    ws.Cells(1, 8).value = "Commit Smooth"
    ws.Cells(1, 9).value = "Discard Smooth"
    ws.Cells(1, 10).value = ""              ' status banner — blank initially

    Dim cell As Range
    Dim col As Long
    For col = 7 To 9
        Set cell = ws.Cells(1, col)
        cell.HorizontalAlignment = xlCenter
        cell.VerticalAlignment = xlCenter
        cell.Font.Bold = True
        cell.RowHeight = 24
        cell.ColumnWidth = 18
        Call CellFormat(cell, "FormatBlue")

        ' Named ranges so the sheet code module can refer to them by name.
        Dim nm As String
        Select Case col
            Case 7: nm = "btnSmoothSelection"
            Case 8: nm = "btnCommitSmooth"
            Case 9: nm = "btnDiscardSmooth"
        End Select
        On Error Resume Next
        ThisWorkbook.Names(nm).Delete
        On Error GoTo 0
        ThisWorkbook.Names.Add Name:=nm, _
                               RefersTo:="='" & ws.Name & "'!" & cell.Address
    Next col

    ' Status banner cell width — wider to fit the message.
    ws.Cells(1, 10).ColumnWidth = 60
    With ws.Cells(1, 10)
        .Font.Italic = True
        .HorizontalAlignment = xlLeft
    End With

    ' Hide the proposal-storage columns Q..T so the operator doesn't
    ' see the working data. The chart can still read them.
    ws.Range("Q:T").EntireColumn.Hidden = True

    MsgBox "CartLog buttons painted." & vbCrLf & vbCrLf & _
           "Final step: paste the Worksheet_BeforeDoubleClick handler " & _
           "into the CartLog sheet's code module " & _
           "(see CartLog_SheetCode.txt).", _
           vbInformation, "Build CartLog Buttons"
End Sub
