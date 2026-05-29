Attribute VB_Name = "GimbalLogPuller"
' ============================================================
' HyperLapse Cart — Gimbal Log Puller (P4)
'
' Copies GimbalLog sheet rows into the Plan sheet's right
' zone (cols AA–AJ) as read-only operator reference for
' authoring the middle-zone Gimbal Plan.
'
' Public entry:
'   PullGimbalLogToPlan — reads GimbalLog, detects shape
'                         (4-field legacy vs 7-field post-#49),
'                         writes into Plan right zone with
'                         appropriate column mapping.
'
' Day 19 — initial P4 implementation. Defensive against #49
' not being landed yet.
'
' GimbalLog shapes:
'   Legacy (4-field, today): A=Timestamp, B=Yaw, C=Pitch, D=Notes
'   Post-#49 (7-field):      A=Timestamp, B=Type, C=Yaw,
'                            D=Pitch, E=Keyframe, F=DeltaYaw,
'                            G=DeltaPitch, H=Label
'                            (Type = "marker" or "astro";
'                             markers populate C/D, astro
'                             populates F/G + E + astro_target)
'
' Plan sheet right-zone columns (P1 mockup):
'   AA=LogRow#, AB=Time, AC=Type, AD=AstroTgt, AE=KF,
'   AF=Ry,      AG=Pitch, AH=Δyaw, AI=Δpitch,    AJ=Label
' ============================================================

Option Explicit

Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_MAX_ROWS  As Long = 60
Private Const RIGHT_COL_FIRST As String = "AA"
Private Const RIGHT_COL_LAST  As String = "AJ"

' Read-only fill (matches P1 mockup convention)
Private Const RO_FILL_COLOR As Long = &HF0F0F0


' ============================================================
' Public entry — PullGimbalLogToPlan
' ============================================================
Public Sub PullGimbalLogToPlan()
    On Error GoTo ErrHandler

    Dim wsLog As Worksheet, wsPlan As Worksheet

    On Error Resume Next
    Set wsLog = ThisWorkbook.Sheets("GimbalLog")
    Set wsPlan = ThisWorkbook.Sheets("Plan")
    On Error GoTo ErrHandler

    If wsLog Is Nothing Then
        MsgBox "GimbalLog sheet not found. Run Gimbal.GetGimbalLog first.", _
               vbExclamation, "PullGimbalLogToPlan"
        Exit Sub
    End If
    If wsPlan Is Nothing Then
        MsgBox "Plan sheet not found.", vbExclamation, "PullGimbalLogToPlan"
        Exit Sub
    End If

    ' --- Detect log shape from header row ---
    Dim logShape As String
    logShape = DetectGimbalLogShape(wsLog)
    If logShape = "UNKNOWN" Then
        MsgBox "GimbalLog header doesn't match either known shape:" & vbCrLf & _
               "  Legacy 4-field: Timestamp | Yaw | Pitch | Notes" & vbCrLf & _
               "  Post-#49 7-field: Timestamp | Type | Yaw | Pitch | KF | DeltaYaw | DeltaPitch | Label" & vbCrLf & vbCrLf & _
               "Header found: " & DescribeHeader(wsLog), _
               vbExclamation, "PullGimbalLogToPlan"
        Exit Sub
    End If

    Dim lastLogRow As Long
    lastLogRow = wsLog.Cells(wsLog.Rows.count, 1).End(xlUp).row
    If lastLogRow < 2 Then
        MsgBox "GimbalLog is empty.", vbExclamation, "PullGimbalLogToPlan"
        Exit Sub
    End If

    ' --- Confirm overwrite if right zone has existing data ---
    Dim existingRows As Long
    existingRows = CountRightZoneRows(wsPlan)
    If existingRows > 0 Then
        Dim resp As VbMsgBoxResult
        resp = MsgBox("Right zone has " & existingRows & " row(s) of " & _
                     "GimbalLog reference data." & vbCrLf & vbCrLf & _
                     "Clear and overwrite from GimbalLog?", _
                     vbYesNo + vbQuestion + vbDefaultButton2, _
                     "PullGimbalLogToPlan")
        If resp <> vbYes Then Exit Sub
    End If

    ' --- Clear existing right-zone rows ---
    wsPlan.Range(RIGHT_COL_FIRST & PLAN_FIRST_ROW & ":" & _
                 RIGHT_COL_LAST & (PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1)).ClearContents

    ' --- Walk GimbalLog, write to right zone ---
    Dim planRow As Long: planRow = PLAN_FIRST_ROW
    Dim writtenRows As Long: writtenRows = 0
    Dim r As Long

    For r = 2 To lastLogRow
        If planRow >= PLAN_FIRST_ROW + PLAN_MAX_ROWS Then
            ' Safety bound
            Exit For
        End If

        If logShape = "LEGACY_4FIELD" Then
            WriteRowLegacy wsLog, r, wsPlan, planRow
        Else
            WriteRowRich wsLog, r, wsPlan, planRow
        End If

        planRow = planRow + 1
        writtenRows = writtenRows + 1
    Next r

    ' --- Apply read-only fill across all written rows ---
    ApplyReadOnlyFormatting wsPlan, PLAN_FIRST_ROW, writtenRows

    ' --- Log ---
    LogEventSafe "PLAN", "PullGimbalLogToPlan: " & writtenRows & " rows (" & logShape & ")"

    Dim msg As String
    msg = writtenRows & " GimbalLog row(s) copied into Plan right zone." & vbCrLf & vbCrLf
    If logShape = "LEGACY_4FIELD" Then
        msg = msg & "Log is in legacy 4-field shape (timestamp/yaw/pitch/notes)." & vbCrLf
        msg = msg & "Type/AstroTgt/KF/Δyaw/Δpitch left blank — operator can" & vbCrLf
        msg = msg & "annotate by hand, or wait for #49 (rich-row firmware)."
    Else
        msg = msg & "Log is in post-#49 7-field shape. Full intent preserved."
    End If
    MsgBox msg, vbInformation, "PullGimbalLogToPlan"

    Exit Sub

ErrHandler:
    LogEventSafe "PLAN", "PullGimbalLogToPlan error: " & Err.Description
    MsgBox "Error in PullGimbalLogToPlan:" & vbCrLf & vbCrLf & _
           Err.Description, vbCritical, "PullGimbalLogToPlan"
End Sub


' ============================================================
' Detect GimbalLog shape from header row
' ============================================================
Private Function DetectGimbalLogShape(ByVal wsLog As Worksheet) As String
    ' Read header cells A1..H1, uppercase + trim for comparison
    Dim h(1 To 8) As String
    Dim i As Integer
    For i = 1 To 8
        h(i) = UCase(Trim(CStr(wsLog.Cells(1, i).value)))
    Next i

    ' Legacy 4-field:
    '   A=Timestamp, B=Yaw, C=Pitch, D=Notes
    If InStr(h(1), "TIME") > 0 _
       And InStr(h(2), "YAW") > 0 _
       And InStr(h(3), "PITCH") > 0 _
       And h(5) = "" Then
        DetectGimbalLogShape = "LEGACY_4FIELD"
        Exit Function
    End If

    ' Post-#49 7-field:
    '   A=Timestamp, B=Type, C=Yaw, D=Pitch, E=Keyframe,
    '   F=DeltaYaw, G=DeltaPitch, H=Label
    If InStr(h(1), "TIME") > 0 _
       And InStr(h(2), "TYPE") > 0 _
       And InStr(h(3), "YAW") > 0 _
       And InStr(h(4), "PITCH") > 0 _
       And h(8) <> "" Then
        DetectGimbalLogShape = "RICH_7FIELD"
        Exit Function
    End If

    DetectGimbalLogShape = "UNKNOWN"
End Function


' ============================================================
' Describe header for error message
' ============================================================
Private Function DescribeHeader(ByVal wsLog As Worksheet) As String
    Dim s As String, i As Integer
    For i = 1 To 8
        Dim v As String
        v = Trim(CStr(wsLog.Cells(1, i).value))
        If v = "" Then v = "(empty)"
        If s = "" Then
            s = v
        Else
            s = s & " | " & v
        End If
    Next i
    DescribeHeader = s
End Function


' ============================================================
' Write one row — legacy 4-field log
' ============================================================
'   GimbalLog (4-field):  A=Timestamp, B=Yaw, C=Pitch, D=Notes
'   Plan right zone:
'     AA=LogRow#, AB=Time, AC=Type, AD=AstroTgt, AE=KF,
'     AF=Ry,      AG=Pitch, AH=Δyaw, AI=Δpitch,    AJ=Label
'   Mapping: yaw -> AF, pitch -> AG, notes -> AJ (label).
'   Type/AstroTgt/KF/Δyaw/Δpitch left blank — operator annotates.
Private Sub WriteRowLegacy(ByVal wsLog As Worksheet, ByVal logR As Long, _
                            ByVal wsPlan As Worksheet, ByVal planR As Long)
    wsPlan.Cells(planR, 27).value = logR                       ' AA — Log row#
    wsPlan.Cells(planR, 28).value = wsLog.Cells(logR, 1).value ' AB — Time
    ' AC Type left blank
    ' AD AstroTgt left blank
    ' AE KF left blank
    wsPlan.Cells(planR, 32).value = wsLog.Cells(logR, 2).value ' AF — Ry (from Yaw)
    wsPlan.Cells(planR, 33).value = wsLog.Cells(logR, 3).value ' AG — Pitch
    ' AH Δyaw left blank
    ' AI Δpitch left blank
    wsPlan.Cells(planR, 36).value = wsLog.Cells(logR, 4).value ' AJ — Label (from Notes)
End Sub


' ============================================================
' Write one row — post-#49 rich 7-field log
' ============================================================
'   GimbalLog (rich):     A=Timestamp, B=Type, C=Yaw, D=Pitch,
'                         E=KF, F=DeltaYaw, G=DeltaPitch, H=Label
'   Plan right zone:      AA=LogRow#, AB=Time, AC=Type, AD=AstroTgt,
'                         AE=KF, AF=Ry, AG=Pitch, AH=Δyaw, AI=Δpitch, AJ=Label
'
'   Note on AD AstroTgt: The post-#49 firmware does NOT separately
'   field the astro target (sun/moon/MW/sunset/etc.) — that's encoded
'   in the Type column (e.g. Type="sunset_mid"). Or per the Day-19
'   design the type could be just "astro" and the astro target lives
'   elsewhere. For now we copy Type verbatim into AC and leave AD
'   blank; can be re-parsed once #49's actual encoding is locked.
Private Sub WriteRowRich(ByVal wsLog As Worksheet, ByVal logR As Long, _
                          ByVal wsPlan As Worksheet, ByVal planR As Long)
    wsPlan.Cells(planR, 27).value = logR                       ' AA
    wsPlan.Cells(planR, 28).value = wsLog.Cells(logR, 1).value ' AB Time
    wsPlan.Cells(planR, 29).value = wsLog.Cells(logR, 2).value ' AC Type
    ' AD AstroTgt — leave blank for now; #49 encoding TBC
    wsPlan.Cells(planR, 31).value = wsLog.Cells(logR, 5).value ' AE KF
    wsPlan.Cells(planR, 32).value = wsLog.Cells(logR, 3).value ' AF Ry (Yaw)
    wsPlan.Cells(planR, 33).value = wsLog.Cells(logR, 4).value ' AG Pitch
    wsPlan.Cells(planR, 34).value = wsLog.Cells(logR, 6).value ' AH DeltaYaw
    wsPlan.Cells(planR, 35).value = wsLog.Cells(logR, 7).value ' AI DeltaPitch
    wsPlan.Cells(planR, 36).value = wsLog.Cells(logR, 8).value ' AJ Label
End Sub


' ============================================================
' Count existing right-zone rows (col AB = Time)
' ============================================================
Private Function CountRightZoneRows(ByVal wsPlan As Worksheet) As Long
    Dim n As Long: n = 0
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Not IsEmpty(wsPlan.Cells(r, 28).value) Then n = n + 1
    Next r
    CountRightZoneRows = n
End Function


' ============================================================
' Apply read-only formatting to written rows
' ============================================================
Private Sub ApplyReadOnlyFormatting(ByVal wsPlan As Worksheet, _
                                     ByVal firstRow As Long, _
                                     ByVal nRows As Long)
    If nRows <= 0 Then Exit Sub
    Dim rng As Range
    Set rng = wsPlan.Range(RIGHT_COL_FIRST & firstRow & ":" & _
                           RIGHT_COL_LAST & (firstRow + nRows - 1))
    rng.Interior.Color = RO_FILL_COLOR
End Sub


' ============================================================
' Log to Utils.LogEvent if available; silent otherwise
' ============================================================
Private Sub LogEventSafe(ByVal category As String, ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", category, msg
    On Error GoTo 0
End Sub
