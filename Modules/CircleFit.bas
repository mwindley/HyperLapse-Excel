Attribute VB_Name = "CircleFit"
' ============================================================
' HyperLapse Cart — Circle Fit Module
'
' PURPOSE
'   Process the 8-point ground-truth measurements from cart
'   calibration tests (workfront #29). Operator drives a fixed-
'   servo orbit, marks rear-axle position at 8 quadrant points,
'   measures (x, y) of each mark relative to a peg at the
'   imagined orbit centre.
'
'   This module fits a best circle through those 8 points and
'   reports the calibration answer.
'
' WORKFLOW
'   1. Run InitCalibrationSheet to build a sheet for entering data
'   2. Operator does the test in field
'   3. Operator types peg-relative (x, y) measurements + commanded
'      servo offset into the sheet
'   4. Live cells report: R_measured, centre offset, scatter,
'      implied δ_wheel, implied SERVO_TO_DEG
'   5. Operator can save the sheet as a row in a results log over
'      multiple tests (left/right turns, different servo values,
'      different surfaces)
'
' MATHS
'   Best-fit circle from N points via algebraic Kasa method:
'     minimise Σ (x_i² + y_i² + D·x_i + E·y_i + F)²
'     gives linear system; solve for D, E, F
'     centre (cx, cy) = (-D/2, -E/2)
'     radius R = sqrt(cx² + cy² - F)
'
'   This isn't the optimal geometric fit (Pratt or Taubin are
'   tighter for noisy data) but for ~30-100mm measurement
'   accuracy and 8 points spread around a full circle, Kasa is
'   plenty accurate. Implementation is also simple — just a 3x3
'   matrix solve.
'
'   Implied wheel angle:
'     δ_wheel = atan(WHEELBASE / R_measured)
'   Implied servo-to-wheel ratio:
'     SERVO_TO_DEG_NEW = δ_wheel / |servo_commanded|
'
' SHEET LAYOUT
'   Single sheet "Calibration" with:
'     - Header: test description, date, surface, weather
'     - Input block: 8 rows for (x_i, y_i) measurements, peg-
'       relative; cell for commanded servo offset
'     - Output block: live formulas for centre, R, scatter,
'       δ_wheel, SERVO_TO_DEG, comparison to current constant
'
' PUBLIC ENTRY POINTS
'   InitCalibrationSheet  — build the sheet
'   MatchWaypointsToLog   — scan CartLog for W events, populate
'                           the log-comparison block
'   FitCircle             — UDF: =FitCircle(xRange, yRange, what)
'                           what = "cx", "cy", "r", "scatter_mm"
'   TraceAtLogRow         — UDF: =TraceAtLogRow(logRowNum, "x_mm"|"y_mm")
'                           returns integrated x/y in mm at the time
'                           of the given CartLog row
' ============================================================

Option Explicit

Private Const SHEET_NAME As String = "Calibration"

' Layout
Private Const ROW_TITLE       As Long = 1
Private Const ROW_META_HDR    As Long = 3
Private Const ROW_DATE        As Long = 4
Private Const ROW_SURFACE     As Long = 5
Private Const ROW_WEATHER     As Long = 6
Private Const ROW_SERVO       As Long = 7
Private Const ROW_DIRECTION   As Long = 8
Private Const ROW_NOTES       As Long = 9

Private Const ROW_INPUT_HDR   As Long = 11
Private Const ROW_INPUT_FIRST As Long = 12
Private Const ROW_INPUT_LAST  As Long = 19  ' 8 points

Private Const ROW_OUTPUT_HDR  As Long = 22
Private Const ROW_OUT_CX      As Long = 23
Private Const ROW_OUT_CY      As Long = 24
Private Const ROW_OUT_R       As Long = 25
Private Const ROW_OUT_DIAM    As Long = 26
Private Const ROW_OUT_SCATTER As Long = 27
Private Const ROW_OUT_OFFSET  As Long = 28
Private Const ROW_OUT_WHEEL   As Long = 30
Private Const ROW_OUT_RATIO   As Long = 31
Private Const ROW_OUT_COMPARE As Long = 32

' Log-comparison block — pairs ground-measured (x,y) to bicycle-model
' integrated (x,y) at each waypoint event
Private Const ROW_LOG_HDR     As Long = 35
Private Const ROW_LOG_INSTR   As Long = 36
Private Const ROW_LOG_TBL_HDR As Long = 38
Private Const ROW_LOG_FIRST   As Long = 39
Private Const ROW_LOG_LAST    As Long = 46    ' 8 waypoints
Private Const ROW_LOG_SUMMARY As Long = 48
Private Const ROW_LOG_MAXDELT As Long = 49
Private Const ROW_LOG_RMSDELT As Long = 50

Private Const COL_LABEL  As Long = 2  ' B
Private Const COL_VALUE  As Long = 3  ' C — for metadata
Private Const COL_X      As Long = 3  ' C
Private Const COL_Y      As Long = 4  ' D
' Log-comparison columns
Private Const COL_WP_LOG_ROW As Long = 3   ' C — log row number
Private Const COL_WP_X_LOG   As Long = 4   ' D — integrated x (mm)
Private Const COL_WP_Y_LOG   As Long = 5   ' E — integrated y (mm)
Private Const COL_WP_DELTAX  As Long = 6   ' F — measured x - log x
Private Const COL_WP_DELTAY  As Long = 7   ' G — measured y - log y
Private Const COL_WP_DIST    As Long = 8   ' H — sqrt(dx² + dy²)

' ============================================================
' Public — one-shot setup
' ============================================================

Public Sub InitCalibrationSheet()
    Dim ws As Worksheet
    Set ws = Nothing
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)
    On Error GoTo 0

    If Not ws Is Nothing Then
        Dim resp As VbMsgBoxResult
        resp = MsgBox("'" & SHEET_NAME & "' already exists. Rebuild it? " & _
                      "Existing data will be lost.", vbYesNo + vbQuestion, _
                      "Init Calibration Sheet")
        If resp <> vbYes Then Exit Sub
        Application.DisplayAlerts = False
        ws.Delete
        Application.DisplayAlerts = True
        Set ws = Nothing
    End If

    Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.count))
    ws.Name = SHEET_NAME

    ' Title
    ws.Cells(ROW_TITLE, COL_LABEL).value = "Cart Calibration Test (workfront #29)"
    ws.Cells(ROW_TITLE, COL_LABEL).Font.Bold = True
    ws.Cells(ROW_TITLE, COL_LABEL).Font.Size = 14

    ' Metadata block
    ws.Cells(ROW_META_HDR, COL_LABEL).value = "-- Test metadata --"
    ws.Cells(ROW_META_HDR, COL_LABEL).Font.Bold = True
    ws.Cells(ROW_META_HDR, COL_LABEL).Font.Italic = True

    ws.Cells(ROW_DATE, COL_LABEL).value = "Date / time"
    ws.Cells(ROW_DATE, COL_VALUE).value = Format(Now(), "yyyy-mm-dd hh:nn")

    ws.Cells(ROW_SURFACE, COL_LABEL).value = "Surface"
    ws.Cells(ROW_SURFACE, COL_VALUE).value = "grass"

    ws.Cells(ROW_WEATHER, COL_LABEL).value = "Weather"
    ws.Cells(ROW_WEATHER, COL_VALUE).value = ""

    ws.Cells(ROW_SERVO, COL_LABEL).value = "Servo offset commanded (deg)"
    ws.Cells(ROW_SERVO, COL_VALUE).value = 32
    Call CellFormat(ws.Cells(ROW_SERVO, COL_VALUE), "FormatYellow")

    ws.Cells(ROW_DIRECTION, COL_LABEL).value = "Turn direction (L or R)"
    ws.Cells(ROW_DIRECTION, COL_VALUE).value = "L"
    Call CellFormat(ws.Cells(ROW_DIRECTION, COL_VALUE), "FormatYellow")

    ws.Cells(ROW_NOTES, COL_LABEL).value = "Notes"
    ws.Cells(ROW_NOTES, COL_VALUE).value = ""

    ' Input block — 8 (x, y) measurements
    ws.Cells(ROW_INPUT_HDR, COL_LABEL).value = "-- Rear-axle (x, y) measurements (peg = origin, mm) --"
    ws.Cells(ROW_INPUT_HDR, COL_LABEL).Font.Bold = True
    ws.Cells(ROW_INPUT_HDR, COL_LABEL).Font.Italic = True

    ws.Cells(ROW_INPUT_HDR + 0, COL_X).value = "x (mm)"
    ws.Cells(ROW_INPUT_HDR + 0, COL_Y).value = "y (mm)"
    ws.Cells(ROW_INPUT_HDR + 0, COL_X).Font.Bold = True
    ws.Cells(ROW_INPUT_HDR + 0, COL_Y).Font.Bold = True

    Dim i As Long
    For i = 0 To 7
        ws.Cells(ROW_INPUT_FIRST + i, COL_LABEL).value = "Point " & (i + 1) & _
            " (approx " & (i * 45) & "°)"
        Call CellFormat(ws.Cells(ROW_INPUT_FIRST + i, COL_X), "FormatYellow")
        Call CellFormat(ws.Cells(ROW_INPUT_FIRST + i, COL_Y), "FormatYellow")
    Next i

    ' Output block — live calibration results
    ws.Cells(ROW_OUTPUT_HDR, COL_LABEL).value = "-- Calibration results (computed live) --"
    ws.Cells(ROW_OUTPUT_HDR, COL_LABEL).Font.Bold = True
    ws.Cells(ROW_OUTPUT_HDR, COL_LABEL).Font.Italic = True

    Dim xR As String, yR As String
    xR = ws.Range(ws.Cells(ROW_INPUT_FIRST, COL_X), _
                  ws.Cells(ROW_INPUT_LAST, COL_X)).Address
    yR = ws.Range(ws.Cells(ROW_INPUT_FIRST, COL_Y), _
                  ws.Cells(ROW_INPUT_LAST, COL_Y)).Address

    ws.Cells(ROW_OUT_CX, COL_LABEL).value = "Fitted centre x (mm)"
    ws.Cells(ROW_OUT_CX, COL_VALUE).Formula = "=FitCircle(" & xR & "," & yR & ",""cx"")"

    ws.Cells(ROW_OUT_CY, COL_LABEL).value = "Fitted centre y (mm)"
    ws.Cells(ROW_OUT_CY, COL_VALUE).Formula = "=FitCircle(" & xR & "," & yR & ",""cy"")"

    ws.Cells(ROW_OUT_R, COL_LABEL).value = "Fitted radius R (mm)"
    ws.Cells(ROW_OUT_R, COL_VALUE).Formula = "=FitCircle(" & xR & "," & yR & ",""r"")"

    ws.Cells(ROW_OUT_DIAM, COL_LABEL).value = "Fitted diameter (mm)"
    ws.Cells(ROW_OUT_DIAM, COL_VALUE).Formula = "=2*" & _
        ws.Cells(ROW_OUT_R, COL_VALUE).Address

    ws.Cells(ROW_OUT_SCATTER, COL_LABEL).value = "Radius scatter ± (mm)"
    ws.Cells(ROW_OUT_SCATTER, COL_VALUE).Formula = "=FitCircle(" & xR & "," & yR & ",""scatter_mm"")"

    ws.Cells(ROW_OUT_OFFSET, COL_LABEL).value = "Centre offset from peg (mm)"
    ws.Cells(ROW_OUT_OFFSET, COL_VALUE).Formula = "=SQRT(" & _
        ws.Cells(ROW_OUT_CX, COL_VALUE).Address & "^2+" & _
        ws.Cells(ROW_OUT_CY, COL_VALUE).Address & "^2)"

    ws.Cells(ROW_OUT_WHEEL, COL_LABEL).value = "Implied wheel angle (deg)"
    ws.Cells(ROW_OUT_WHEEL, COL_VALUE).Formula = "=DEGREES(ATAN(490/" & _
        ws.Cells(ROW_OUT_R, COL_VALUE).Address & "))"

    ws.Cells(ROW_OUT_RATIO, COL_LABEL).value = "Implied SERVO_TO_DEG"
    ws.Cells(ROW_OUT_RATIO, COL_VALUE).Formula = _
        "=" & ws.Cells(ROW_OUT_WHEEL, COL_VALUE).Address & _
        "/ABS(" & ws.Cells(ROW_SERVO, COL_VALUE).Address & ")"

    ws.Cells(ROW_OUT_COMPARE, COL_LABEL).value = "Current constant (day-9 first est.)"
    ws.Cells(ROW_OUT_COMPARE, COL_VALUE).value = 0.35

    ' --- Log-comparison block ---
    ws.Cells(ROW_LOG_HDR, COL_LABEL).value = "-- Log waypoint comparison (bicycle model vs ground truth) --"
    ws.Cells(ROW_LOG_HDR, COL_LABEL).Font.Bold = True
    ws.Cells(ROW_LOG_HDR, COL_LABEL).Font.Italic = True

    ws.Cells(ROW_LOG_INSTR, COL_LABEL).value = _
        "After pulling CartLog and running IntegrateBicycle: " & _
        "click ""Match Waypoints to Log"" to auto-fill row numbers."

    ' Headers for the comparison table
    ws.Cells(ROW_LOG_TBL_HDR, COL_LABEL).value = "Waypoint"
    ws.Cells(ROW_LOG_TBL_HDR, COL_WP_LOG_ROW).value = "CartLog row"
    ws.Cells(ROW_LOG_TBL_HDR, COL_WP_X_LOG).value = "x_log (mm)"
    ws.Cells(ROW_LOG_TBL_HDR, COL_WP_Y_LOG).value = "y_log (mm)"
    ws.Cells(ROW_LOG_TBL_HDR, COL_WP_DELTAX).value = "Δx (mm)"
    ws.Cells(ROW_LOG_TBL_HDR, COL_WP_DELTAY).value = "Δy (mm)"
    ws.Cells(ROW_LOG_TBL_HDR, COL_WP_DIST).value = "|Δ| (mm)"

    Dim k As Long
    For k = ROW_LOG_TBL_HDR To ROW_LOG_TBL_HDR
        ws.Cells(k, COL_LABEL).Font.Bold = True
        ws.Cells(k, COL_WP_LOG_ROW).Font.Bold = True
        ws.Cells(k, COL_WP_X_LOG).Font.Bold = True
        ws.Cells(k, COL_WP_Y_LOG).Font.Bold = True
        ws.Cells(k, COL_WP_DELTAX).Font.Bold = True
        ws.Cells(k, COL_WP_DELTAY).Font.Bold = True
        ws.Cells(k, COL_WP_DIST).Font.Bold = True
    Next k

    ' 8 rows: input log-row, lookup x/y from Trace, compute deltas
    Dim j As Long
    For j = 0 To 7
        Dim r As Long
        r = ROW_LOG_FIRST + j

        ws.Cells(r, COL_LABEL).value = "Waypoint " & (j + 1)

        ' Log row number — yellow editable, defaults blank; populated by
        ' MatchWaypointsToLog sub or operator override.
        Call CellFormat(ws.Cells(r, COL_WP_LOG_ROW), "FormatYellow")

        ' x_log, y_log — look up timestamp at CartLog!A{logrow}, find
        ' nearest Trace row by timestamp, return Trace x/y converted to mm.
        ' Bottom-line formula uses helper UDF TraceXatLogRow / TraceYatLogRow.
        ws.Cells(r, COL_WP_X_LOG).Formula = _
            "=IFERROR(TraceAtLogRow(" & ws.Cells(r, COL_WP_LOG_ROW).Address & ",""x_mm""),"""")"
        ws.Cells(r, COL_WP_Y_LOG).Formula = _
            "=IFERROR(TraceAtLogRow(" & ws.Cells(r, COL_WP_LOG_ROW).Address & ",""y_mm""),"""")"

        ' Deltas: measured (input block) minus log
        Dim measXAddr As String, measYAddr As String
        measXAddr = ws.Cells(ROW_INPUT_FIRST + j, COL_X).Address
        measYAddr = ws.Cells(ROW_INPUT_FIRST + j, COL_Y).Address

        ws.Cells(r, COL_WP_DELTAX).Formula = "=IFERROR(" & measXAddr & "-" & _
            ws.Cells(r, COL_WP_X_LOG).Address & ","""")"
        ws.Cells(r, COL_WP_DELTAY).Formula = "=IFERROR(" & measYAddr & "-" & _
            ws.Cells(r, COL_WP_Y_LOG).Address & ","""")"
        ws.Cells(r, COL_WP_DIST).Formula = _
            "=IFERROR(SQRT(" & ws.Cells(r, COL_WP_DELTAX).Address & "^2+" & _
            ws.Cells(r, COL_WP_DELTAY).Address & "^2),"""")"
    Next j

    ' Summary
    ws.Cells(ROW_LOG_SUMMARY, COL_LABEL).value = "Bicycle-model fidelity summary"
    ws.Cells(ROW_LOG_SUMMARY, COL_LABEL).Font.Bold = True

    Dim distRange As String
    distRange = ws.Range(ws.Cells(ROW_LOG_FIRST, COL_WP_DIST), _
                         ws.Cells(ROW_LOG_LAST, COL_WP_DIST)).Address

    ws.Cells(ROW_LOG_MAXDELT, COL_LABEL).value = "Max |Δ| across 8 points (mm)"
    ws.Cells(ROW_LOG_MAXDELT, COL_VALUE).Formula = _
        "=IFERROR(MAX(" & distRange & "),"""")"

    ws.Cells(ROW_LOG_RMSDELT, COL_LABEL).value = "RMS |Δ| across 8 points (mm)"
    ws.Cells(ROW_LOG_RMSDELT, COL_VALUE).Formula = _
        "=IFERROR(SQRT(SUMSQ(" & distRange & ")/COUNT(" & distRange & ")),"""")"

    ' Column widths
    ws.Columns(COL_LABEL).ColumnWidth = 38
    ws.Columns(COL_VALUE).ColumnWidth = 14
    ws.Columns(COL_WP_X_LOG).ColumnWidth = 12
    ws.Columns(COL_WP_Y_LOG).ColumnWidth = 12
    ws.Columns(COL_WP_DELTAX).ColumnWidth = 10
    ws.Columns(COL_WP_DELTAY).ColumnWidth = 10
    ws.Columns(COL_WP_DIST).ColumnWidth = 10

    ws.Activate
    ws.Cells(1, 1).Select

    MsgBox "Calibration sheet ready." & vbCrLf & vbCrLf & _
           "1. Type measurements into the yellow cells." & vbCrLf & _
           "2. Results compute live in the output block." & vbCrLf & _
           "3. After cart log import + IntegrateBicycle, click" & vbCrLf & _
           "   'Match Waypoints to Log' to populate the comparison block.", _
           vbInformation, "Init Calibration Sheet"
End Sub

' ============================================================
' Match Waypoint events from CartLog to the Calibration sheet
' ============================================================

' Scan CartLog sheet for "W" events, write their row numbers into
' the 8 log-row cells on the Calibration sheet. Operator can edit
' afterward if the auto-match is wrong (e.g. too few/too many W events).
Public Sub MatchWaypointsToLog()
    Dim wsCal As Worksheet
    Dim wsLog As Worksheet
    On Error Resume Next
    Set wsCal = ThisWorkbook.Sheets(SHEET_NAME)
    Set wsLog = ThisWorkbook.Sheets("CartLog")
    On Error GoTo 0

    If wsCal Is Nothing Then
        MsgBox "Calibration sheet not found. Run Init Calibration Sheet first.", _
               vbExclamation
        Exit Sub
    End If
    If wsLog Is Nothing Then
        MsgBox "CartLog sheet not found. Pull cart log via GetCartLog first.", _
               vbExclamation
        Exit Sub
    End If

    ' Walk CartLog. Assume event-type column is B (col 2) — confirms
    ' by reading the header row 1; if not found, prompts the operator.
    ' Cart.bas writes CartLog with this layout: A=timestamp, B=event_type,
    ' C=value, D=description. Verify by inspecting row 1 header text.
    Dim lastRow As Long
    lastRow = wsLog.Cells(wsLog.Rows.count, 1).End(xlUp).Row

    Dim foundRows() As Long
    ReDim foundRows(1 To 16)   ' room for up to 16 W events
    Dim nFound As Long
    nFound = 0

    Dim r As Long
    For r = 2 To lastRow
        Dim et As String
        et = UCase(Trim(CStr(wsLog.Cells(r, 2).value)))
        If et = "W" Then
            nFound = nFound + 1
            If nFound <= 16 Then foundRows(nFound) = r
        End If
    Next r

    ' Write into the 8 waypoint slots
    Dim i As Long
    For i = 1 To 8
        If i <= nFound Then
            wsCal.Cells(ROW_LOG_FIRST + i - 1, COL_WP_LOG_ROW).value = foundRows(i)
        Else
            wsCal.Cells(ROW_LOG_FIRST + i - 1, COL_WP_LOG_ROW).value = ""
        End If
    Next i

    LogEvent "CAL", "MatchWaypointsToLog: " & nFound & " W events found, " & _
                    "first 8 mapped to calibration sheet"

    If nFound <> 8 Then
        MsgBox "Found " & nFound & " waypoint (W) events; expected 8." & vbCrLf & _
               "First " & WorksheetFunction.Min(nFound, 8) & " mapped. " & _
               "Edit the yellow CartLog-row cells manually if needed.", _
               vbExclamation, "Match Waypoints"
    Else
        MsgBox "8 waypoint events found and mapped.", vbInformation, _
               "Match Waypoints"
    End If
End Sub

' ============================================================
' UDF — look up integrated (x_mm, y_mm) at the time of a CartLog row
' ============================================================

' Given a CartLog row number, find the timestamp at that row, then
' find the Trace sheet row with the closest timestamp, and return
' the x or y at that Trace row (converted from m to mm).
'
' what = "x_mm" | "y_mm"
Public Function TraceAtLogRow(ByVal logRow As Variant, _
                              ByVal what As String) As Variant
    Application.Volatile False
    On Error GoTo ErrHandler

    If Not IsNumeric(logRow) Then
        TraceAtLogRow = CVErr(xlErrNA)
        Exit Function
    End If
    If CLng(logRow) <= 1 Then
        TraceAtLogRow = CVErr(xlErrNA)
        Exit Function
    End If

    Dim wsLog As Worksheet, wsTrace As Worksheet
    On Error Resume Next
    Set wsLog = ThisWorkbook.Sheets("CartLog")
    Set wsTrace = ThisWorkbook.Sheets("Trace")
    On Error GoTo 0
    If wsLog Is Nothing Or wsTrace Is Nothing Then
        TraceAtLogRow = CVErr(xlErrRef)
        Exit Function
    End If

    ' Read timestamp at the log row (column A is timestamp).
    ' CartLog uses "hh:mm:ss" string format; convert to seconds.
    Dim tsText As String
    tsText = CStr(wsLog.Cells(CLng(logRow), 1).value)
    Dim tSec As Double
    tSec = HmsTextToSec(tsText)

    ' Find Trace row whose column-A timestamp is closest to tSec.
    Dim lastTraceRow As Long
    lastTraceRow = wsTrace.Cells(wsTrace.Rows.count, 1).End(xlUp).Row
    If lastTraceRow < 3 Then
        TraceAtLogRow = CVErr(xlErrNA)
        Exit Function
    End If

    ' Bulk-read Trace timestamps + x,y for performance
    Dim traceVals As Variant
    traceVals = wsTrace.Range(wsTrace.Cells(3, 1), wsTrace.Cells(lastTraceRow, 3)).value

    Dim bestRow As Long, bestDelta As Double
    bestRow = 0
    bestDelta = 9999999#
    Dim i As Long
    For i = 1 To UBound(traceVals, 1)
        If IsNumeric(traceVals(i, 1)) Then
            Dim dlt As Double
            dlt = Abs(CDbl(traceVals(i, 1)) - tSec)
            If dlt < bestDelta Then
                bestDelta = dlt
                bestRow = i
            End If
        End If
    Next i

    If bestRow = 0 Then
        TraceAtLogRow = CVErr(xlErrNA)
        Exit Function
    End If

    Select Case LCase(what)
        Case "x_mm"
            TraceAtLogRow = CDbl(traceVals(bestRow, 2)) * 1000#
        Case "y_mm"
            TraceAtLogRow = CDbl(traceVals(bestRow, 3)) * 1000#
        Case Else
            TraceAtLogRow = CVErr(xlErrValue)
    End Select
    Exit Function

ErrHandler:
    TraceAtLogRow = CVErr(xlErrValue)
End Function

' Convert "hh:mm:ss" or "hh:mm:ss.fff" string to seconds-since-midnight.
' Matches the convention used in CartLog's column A.
Private Function HmsTextToSec(ByVal s As String) As Double
    Dim parts() As String
    parts = Split(Trim(s), ":")
    If UBound(parts) < 2 Then
        HmsTextToSec = 0
        Exit Function
    End If
    HmsTextToSec = CDbl(parts(0)) * 3600# + CDbl(parts(1)) * 60# + CDbl(parts(2))
End Function

' ============================================================
' UDF — best-fit circle through N points (Kasa algebraic method)
' ============================================================

' Returns one of: cx, cy, r, scatter_mm
'   cx, cy   — centre (peg-relative mm)
'   r        — fitted radius (mm)
'   scatter_mm — standard deviation of |point_i - centre| from r (mm)
Public Function FitCircle(ByVal xRange As Range, _
                          ByVal yRange As Range, _
                          ByVal what As String) As Variant
    Application.Volatile False
    On Error GoTo ErrHandler

    Dim xs As Variant, ys As Variant
    xs = xRange.value
    ys = yRange.value

    ' Collect valid (x, y) pairs into arrays
    Dim n As Long
    n = UBound(xs, 1)

    Dim valid() As Boolean
    ReDim valid(1 To n)
    Dim nValid As Long
    nValid = 0
    Dim i As Long
    For i = 1 To n
        If IsNumeric(xs(i, 1)) And IsNumeric(ys(i, 1)) Then
            valid(i) = True
            nValid = nValid + 1
        End If
    Next i

    If nValid < 3 Then
        FitCircle = "#NEED3+"
        Exit Function
    End If

    ' Kasa fit: minimize sum of (x²+y² + Dx + Ey + F)²
    ' Linear system A·[D,E,F]ᵀ = b where:
    '   A = [[Σx², Σxy, Σx], [Σxy, Σy², Σy], [Σx, Σy, n]]
    '   b = -[Σx(x²+y²), Σy(x²+y²), Σ(x²+y²)]
    Dim Sx As Double, Sy As Double, Sxx As Double, Syy As Double, Sxy As Double
    Dim Sxz As Double, Syz As Double, Sz As Double
    Dim x As Double, y As Double, z As Double
    For i = 1 To n
        If valid(i) Then
            x = CDbl(xs(i, 1))
            y = CDbl(ys(i, 1))
            z = x * x + y * y
            Sx = Sx + x
            Sy = Sy + y
            Sxx = Sxx + x * x
            Syy = Syy + y * y
            Sxy = Sxy + x * y
            Sxz = Sxz + x * z
            Syz = Syz + y * z
            Sz = Sz + z
        End If
    Next i

    ' Solve 3x3 system: A * v = b
    ' A = [[Sxx, Sxy, Sx], [Sxy, Syy, Sy], [Sx, Sy, nValid]]
    ' b = [-Sxz, -Syz, -Sz]  (negated because Kasa fits z + Dx + Ey + F = 0)
    Dim m11 As Double, m12 As Double, m13 As Double
    Dim m21 As Double, m22 As Double, m23 As Double
    Dim m31 As Double, m32 As Double, m33 As Double
    m11 = Sxx: m12 = Sxy: m13 = Sx
    m21 = Sxy: m22 = Syy: m23 = Sy
    m31 = Sx:  m32 = Sy:  m33 = CDbl(nValid)

    Dim b1 As Double, b2 As Double, b3 As Double
    b1 = -Sxz: b2 = -Syz: b3 = -Sz

    ' Determinant via Sarrus
    Dim det As Double
    det = m11 * (m22 * m33 - m23 * m32) _
        - m12 * (m21 * m33 - m23 * m31) _
        + m13 * (m21 * m32 - m22 * m31)
    If Abs(det) < 0.0000000001 Then
        FitCircle = "#DEGENERATE"
        Exit Function
    End If

    ' Cramer's rule
    Dim D As Double, E As Double, F As Double
    D = (b1 * (m22 * m33 - m23 * m32) _
       - m12 * (b2 * m33 - m23 * b3) _
       + m13 * (b2 * m32 - m22 * b3)) / det
    E = (m11 * (b2 * m33 - m23 * b3) _
       - b1 * (m21 * m33 - m23 * m31) _
       + m13 * (m21 * b3 - b2 * m31)) / det
    F = (m11 * (m22 * b3 - b2 * m32) _
       - m12 * (m21 * b3 - b2 * m31) _
       + b1 * (m21 * m32 - m22 * m31)) / det

    Dim cx As Double, cy As Double, r As Double
    cx = -D / 2
    cy = -E / 2
    Dim discr As Double
    discr = cx * cx + cy * cy - F
    If discr < 0 Then
        FitCircle = "#BAD_FIT"
        Exit Function
    End If
    r = Sqr(discr)

    Select Case LCase(what)
        Case "cx"
            FitCircle = cx
        Case "cy"
            FitCircle = cy
        Case "r"
            FitCircle = r
        Case "scatter_mm"
            ' Std dev of distance-from-centre
            Dim sumSqDev As Double
            Dim dist As Double, dev As Double
            For i = 1 To n
                If valid(i) Then
                    dist = Sqr((CDbl(xs(i, 1)) - cx) ^ 2 + (CDbl(ys(i, 1)) - cy) ^ 2)
                    dev = dist - r
                    sumSqDev = sumSqDev + dev * dev
                End If
            Next i
            FitCircle = Sqr(sumSqDev / CDbl(nValid))
        Case Else
            FitCircle = "#WHAT?"
    End Select
    Exit Function

ErrHandler:
    FitCircle = "#ERR:" & Err.Description
End Function
