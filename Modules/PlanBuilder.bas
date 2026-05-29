Attribute VB_Name = "PlanBuilder"
' ============================================================
' HyperLapse Cart — Plan Builder
'
' Builds the left zone (Cart Plan) of the Plan sheet from
' CartLog recon data. Requires Cart.ProcessCartLog to have
' been run first so col G (per-event distance) is populated.
'
' Public entry points:
'   BuildPlanFromCartLog   — walks CartLog W events, writes
'                            one Plan row per waypoint leg
'
' Day 19 — initial P2 implementation. Reads CartLog only;
' GimbalLog → right zone is P4 (separate macro).
'
' CartLog column layout (post-ProcessCartLog):
'   A=Timestamp, B=Type, C=Value, D=Description,
'   E=Duration(s), F=Scout speed, G=Distance(m), H=Replay speed
'
' CartLog event types (per DJI_Ronin_Giga_v2.ino):
'   S — speed set; value = m/hr
'   T — steering target set (authoritative); value = RAW servo code
'       (CART_STEERING_CENTRE = 98; offset_deg = value - 98)
'   t — steering ramp complete (informational; sketch line 3159)
'   W — waypoint mark; value = waypoint #
'   X — stop
'   P / p / a — execution-time plan markers (not seen in recon)
'
' Plan sheet left-zone columns (P1 mockup):
'   B=Step, C=Action, D=Dist(m), E=Speed(m/hr), F=Turn(deg),
'   G=Hold(s), H=WP#, I=DistSum(m), J=Arrives, K=Note
' ============================================================

Option Explicit

' Row layout on Plan sheet (matches P1 mockup)
Private Const PLAN_FIRST_ROW As Long = 6       ' first data row
Private Const PLAN_MAX_ROWS  As Long = 60      ' safety bound for clear
Private Const CART_COL_FIRST As String = "B"
Private Const CART_COL_LAST  As String = "K"

' CartLog column constants (1-based)
Private Const CL_TIME = 1
Private Const CL_TYPE = 2
Private Const CL_VALUE = 3
Private Const CL_DESC = 4
Private Const CL_DURATION = 5
Private Const CL_SCOUT_SPEED = 6
Private Const CL_DISTANCE = 7

' Steering centre offset used in CartLog T-events
Private Const CART_STEERING_CENTRE As Integer = 98


' ============================================================
' Public entry — BuildPlanFromCartLog
' ============================================================
Public Sub BuildPlanFromCartLog()
    On Error GoTo ErrHandler

    Dim wsLog As Worksheet, wsPlan As Worksheet

    ' --- Resolve sheets ---
    On Error Resume Next
    Set wsLog = ThisWorkbook.Sheets("CartLog")
    Set wsPlan = ThisWorkbook.Sheets("Plan")
    On Error GoTo ErrHandler

    If wsLog Is Nothing Then
        MsgBox "CartLog sheet not found. Run Cart.GetCartLog first.", _
               vbExclamation, "BuildPlanFromCartLog"
        Exit Sub
    End If
    If wsPlan Is Nothing Then
        MsgBox "Plan sheet not found. Open the Plan workbook.", _
               vbExclamation, "BuildPlanFromCartLog"
        Exit Sub
    End If

    ' --- Sanity check: ProcessCartLog must have run (col G populated) ---
    If wsLog.Cells(1, CL_DISTANCE).value <> "Distance (m)" Then
        MsgBox "CartLog col G is not 'Distance (m)' — has " & _
               "Cart.ProcessCartLog been run?" & vbCrLf & vbCrLf & _
               "Run ProcessCartLog first, then retry.", _
               vbExclamation, "BuildPlanFromCartLog"
        Exit Sub
    End If

    Dim lastCartRow As Long
    lastCartRow = wsLog.Cells(wsLog.Rows.count, 1).End(xlUp).row
    If lastCartRow < 2 Then
        MsgBox "CartLog is empty.", vbExclamation, "BuildPlanFromCartLog"
        Exit Sub
    End If

    ' --- Confirm overwrite if Plan has existing data ---
    Dim existingRows As Long
    existingRows = CountPlanRows(wsPlan)
    If existingRows > 0 Then
        Dim resp As VbMsgBoxResult
        resp = MsgBox("Plan sheet has " & existingRows & " row(s) of " & _
                     "authored cart-plan data." & vbCrLf & vbCrLf & _
                     "Clear and overwrite from CartLog?", _
                     vbYesNo + vbQuestion + vbDefaultButton2, _
                     "BuildPlanFromCartLog")
        If resp <> vbYes Then
            Exit Sub
        End If
    End If

    ' --- Clear existing left-zone rows ---
    wsPlan.Range(CART_COL_FIRST & PLAN_FIRST_ROW & ":" & _
                 CART_COL_LAST & (PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1)).ClearContents

    ' --- Walk CartLog, aggregate per waypoint ---
    Dim currentSpeed As Double:     currentSpeed = 0
    Dim currentSteer As Integer:    currentSteer = 0      ' offset from centre
    Dim legStart As String:         legStart = ""
    Dim legStartSpeed As Double:    legStartSpeed = 0
    Dim legStartSteer As Integer:   legStartSteer = 0
    Dim legDistance As Double:      legDistance = 0
    Dim wpNum As Long:              wpNum = 0
    Dim planRow As Long:            planRow = PLAN_FIRST_ROW
    Dim writtenRows As Long:        writtenRows = 0

    ' First event timestamp is the seed for "Way01 start"
    Dim firstTimestamp As String
    firstTimestamp = CStr(wsLog.Cells(2, CL_TIME).value)

    Dim r As Long
    For r = 2 To lastCartRow
        Dim evtType As String
        Dim evtTypeRaw As String
        Dim evtTime As String
        Dim evtValue As Double
        Dim evtDist As Variant

        evtTime = CStr(wsLog.Cells(r, CL_TIME).value)
        ' Preserve case: 'T' (target set, authoritative) vs 't' (ramp-complete, informational).
        ' Per DJI_Ronin_Giga_v2.ino line 1317 vs line 3159 — case is meaningful.
        evtTypeRaw = Trim(CStr(wsLog.Cells(r, CL_TYPE).value))
        evtType = evtTypeRaw   ' do NOT UCase
        evtValue = SafeDouble(wsLog.Cells(r, CL_VALUE).value)
        evtDist = wsLog.Cells(r, CL_DISTANCE).value

        ' Accumulate distance attributed to the *prior* segment
        If IsNumeric(evtDist) Then
            legDistance = legDistance + CDbl(evtDist)
        End If

        Select Case evtType
            Case "S"
                ' Speed change
                If legStart = "" Then
                    legStartSpeed = evtValue
                    legStart = evtTime
                End If
                currentSpeed = evtValue
            Case "T"
                ' Steering TARGET set — authoritative. Value is RAW servo code
                ' (CART_STEERING_CENTRE = 98). Per sketch line 1317.
                Dim steerDeg As Integer
                steerDeg = CInt(evtValue) - CART_STEERING_CENTRE
                If legStart = "" Then
                    legStartSteer = steerDeg
                    legStart = evtTime
                End If
                currentSteer = steerDeg
            Case "t"
                ' Steering ramp COMPLETE — informational only (sketch line 3159).
                ' Do NOT update currentSteer here; the 'T' event already set it.
                ' Listed explicitly so future readers see it was considered.
            Case "W"
                ' Waypoint mark — close out the current leg
                wpNum = wpNum + 1
                WritePlanRow wsPlan, planRow, wpNum, _
                             "DRIVE", legDistance, legStartSpeed, legStartSteer, _
                             "", evtTime, "Way" & Format(wpNum, "00") & _
                             " (recon " & evtTime & ")"
                planRow = planRow + 1
                writtenRows = writtenRows + 1

                ' Reset leg accumulator; new leg starts from this waypoint
                legDistance = 0
                legStart = evtTime
                legStartSpeed = currentSpeed
                legStartSteer = currentSteer
            Case "X"
                ' Stop — close out as final leg, then emit STOP row
                If legDistance > 0 Or wpNum = 0 Then
                    wpNum = wpNum + 1
                    WritePlanRow wsPlan, planRow, wpNum, _
                                 "DRIVE", legDistance, legStartSpeed, legStartSteer, _
                                 "", evtTime, "Way" & Format(wpNum, "00") & _
                                 " (recon stop @ " & evtTime & ")"
                    planRow = planRow + 1
                    writtenRows = writtenRows + 1
                End If

                ' Emit explicit STOP row (no waypoint number — STOP is an action)
                WritePlanRow wsPlan, planRow, Empty, _
                             "STOP", Empty, 0, Empty, _
                             Empty, evtTime, "Cart parked"
                planRow = planRow + 1
                writtenRows = writtenRows + 1

                legDistance = 0
                legStart = ""
            Case "P", "p", "a"
                ' Execution-time markers (plan segment start / phase / abort).
                ' Per sketch lines 2592, 2609, 2624. Should not appear in a
                ' recon CartLog; ignored defensively if they do.
            Case Else
                ' Unknown event type — ignore but don't fail.
        End Select
    Next r

    ' --- Cosmetic: apply seed-fill colour to written rows ---
    ApplySeedFormatting wsPlan, PLAN_FIRST_ROW, writtenRows

    ' --- Log ---
    LogEventSafe "PLAN", "BuildPlanFromCartLog: " & writtenRows & " rows written"

    MsgBox writtenRows & " plan row(s) written from CartLog." & vbCrLf & vbCrLf & _
           "Edit speed / distance / turn as needed, then review " & _
           "downstream timing.", vbInformation, "BuildPlanFromCartLog"
    Exit Sub

ErrHandler:
    LogEventSafe "PLAN", "BuildPlanFromCartLog error: " & Err.Description
    MsgBox "Error in BuildPlanFromCartLog:" & vbCrLf & vbCrLf & _
           Err.Description, vbCritical, "BuildPlanFromCartLog"
End Sub


' ============================================================
' Helper — write one Plan row
' ============================================================
Private Sub WritePlanRow(ByVal wsPlan As Worksheet, _
                          ByVal r As Long, _
                          ByVal wpNum As Variant, _
                          ByVal action As String, _
                          ByVal distance As Variant, _
                          ByVal speed As Variant, _
                          ByVal turn As Variant, _
                          ByVal hold As Variant, _
                          ByVal arrives As String, _
                          ByVal note As String)
    ' Col B = Step #  (derived from row index, not authored)
    wsPlan.Cells(r, 2).value = r - PLAN_FIRST_ROW + 1
    ' Col C = Action
    wsPlan.Cells(r, 3).value = action
    ' Col D = Distance (m)
    If Not IsEmpty(distance) Then
        If IsNumeric(distance) Then
            wsPlan.Cells(r, 4).value = Round(CDbl(distance), 3)
        End If
    End If
    ' Col E = Speed (m/hr) — seed with recon speed
    If Not IsEmpty(speed) Then
        wsPlan.Cells(r, 5).value = speed
    End If
    ' Col F = Turn (deg)
    If Not IsEmpty(turn) Then
        wsPlan.Cells(r, 6).value = turn
    End If
    ' Col G = Hold (s)
    If Not IsEmpty(hold) Then
        wsPlan.Cells(r, 7).value = hold
    End If
    ' Col H = WP #
    If Not IsEmpty(wpNum) Then
        wsPlan.Cells(r, 8).value = wpNum
    End If
    ' Col I = Dist Σ — derived, leave for P3 formulae to fill
    '   (P2 deliberately does not compute running total — P3 will)
    ' Col J = Arrives — seed with raw CartLog timestamp for now
    wsPlan.Cells(r, 10).value = arrives
    ' Col K = Note
    wsPlan.Cells(r, 11).value = note
End Sub


' ============================================================
' Helper — count existing non-empty Plan rows (col C = Action)
' ============================================================
Private Function CountPlanRows(ByVal wsPlan As Worksheet) As Long
    Dim n As Long: n = 0
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Not IsEmpty(wsPlan.Cells(r, 3).value) Then n = n + 1
    Next r
    CountPlanRows = n
End Function


' ============================================================
' Helper — apply seed-fill colour to written rows
' Pale yellow (FFFFEE) matches the P1 mockup convention
' ============================================================
Private Sub ApplySeedFormatting(ByVal wsPlan As Worksheet, _
                                 ByVal firstRow As Long, _
                                 ByVal nRows As Long)
    If nRows <= 0 Then Exit Sub
    Dim rng As Range
    Set rng = wsPlan.Range(CART_COL_FIRST & firstRow & ":" & _
                           CART_COL_LAST & (firstRow + nRows - 1))
    rng.Interior.Color = RGB(255, 255, 238)   ' pale yellow seed
End Sub


' ============================================================
' Helper — safe Double parse (returns 0 for non-numeric)
' ============================================================
Private Function SafeDouble(ByVal v As Variant) As Double
    If IsNumeric(v) Then
        SafeDouble = CDbl(v)
    Else
        SafeDouble = 0
    End If
End Function


' ============================================================
' Helper — log to Log sheet if LogEvent exists, else silent
' ============================================================
Private Sub LogEventSafe(ByVal category As String, ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", category, msg
    On Error GoTo 0
End Sub
