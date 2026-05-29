Attribute VB_Name = "PlanAuthoring"
' ============================================================
' HyperLapse Cart — Plan Authoring Helpers (P5)
'
' Middle-zone row management for the Plan sheet.
'
' Public entries (assign to ribbon buttons or shapes):
'   AddPlanRowFromLog    — read selected right-zone row, append
'                          middle-zone row with sensible defaults
'   AddBlankPlanRow      — append empty middle-zone row
'   InsertPlanRowAbove   — operator selects a middle row;
'                          inserts blank row above it
'   DeletePlanRow        — operator selects a middle row;
'                          deletes it and shifts rows up
'   RebuildAnchorDV      — refresh the dynamic dropdowns on a
'                          single anchor-ref cell (called from
'                          the Plan sheet's Worksheet_SelectionChange
'                          event handler — see comment block at
'                          bottom for the snippet to paste into
'                          the Plan sheet's code module)
'
' Day 19 — initial P5 implementation.
' Day 20 — P6 column shift: middle zone now M..AA (was M..Y).
'          Two new columns inserted after Anchor ref (col O):
'            P = Offset (min)   — editable, blank=0
'            Q = Fires at       — derived formula (anchor resolver)
'          Old cols P..Y shifted +2 to R..AA. All Cells(r,c) column
'          numbers from 16 upward in this module bumped accordingly.
'          Right zone ALSO shifted +2 to AC..AL to avoid AA collision
'          with the new middle-zone end (Note). Right-zone reads in
'          AddPlanRowFromLog updated; gap at column AB.
'          WP # convention also tightened: H column and Anchor ref
'          both use WP01..WPNN text strings (was integer in H,
'          "WP<n>" in O). BuildWPList updated to read strings.
'
' Plan sheet middle-zone columns (P6 layout):
'   M=Step, N=AnchorType, O=AnchorRef, P=Offset(min), Q=Fires at,
'   R=Action, S=TargetType, T=TargetRef, U=KF, V=Rate, W=Dyaw,
'   X=Dpitch, Y=MoveTime, Z=EndAnchor, AA=Note
'
' Right zone (P6: shifted +2):
'   AC=LogRow#, AD=Time, AE=Type, AF=AstroTgt, AG=KF, AH=Ry,
'   AI=Pitch, AJ=Dyaw, AK=Dpitch, AL=Label
' ============================================================

Option Explicit

Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_MAX_ROWS  As Long = 60

Private Const MID_COL_FIRST As String = "M"
Private Const MID_COL_LAST  As String = "AA"

Private Const RIGHT_COL_FIRST As String = "AC"
Private Const RIGHT_COL_LAST  As String = "AL"

' Seed fill colour matches P1 mockup (pale yellow)
Private Const SEED_FILL_COLOR As Long = &HFFFFEE
Private Const DERIVED_FILL_COLOR As Long = &HF5F5F5


' ============================================================
' Public — AddPlanRowFromLog
' ============================================================
' Reads the right-zone row containing the active cell; appends
' a new middle-zone row at the bottom with sensible defaults
' derived from the log row's Type:
'   Type=marker -> Approach with static log-label target
'   Type=astro  -> Approach with astro target, Delta yaw/pitch copied
Public Sub AddPlanRowFromLog()
    On Error GoTo ErrHandler

    Dim wsPlan As Worksheet
    Set wsPlan = ActiveSheet
    If LCase(wsPlan.Name) <> "plan" Then
        MsgBox "AddPlanRowFromLog must be run on the Plan sheet.", _
               vbExclamation, "AddPlanRowFromLog"
        Exit Sub
    End If

    Dim selRow As Long
    selRow = ActiveCell.row
    If selRow < PLAN_FIRST_ROW Or selRow >= PLAN_FIRST_ROW + PLAN_MAX_ROWS Then
        MsgBox "Click into a right-zone (gimbal log) row first, " & _
               "then run AddPlanRowFromLog.", vbExclamation, _
               "AddPlanRowFromLog"
        Exit Sub
    End If

    ' Verify selection is in right zone — col AA or later
    If ActiveCell.Column < Range(RIGHT_COL_FIRST & "1").Column Then
        MsgBox "Active cell is not in the right zone (GimbalLog " & _
               "reference). Click into a right-zone row first.", _
               vbExclamation, "AddPlanRowFromLog"
        Exit Sub
    End If

    ' Read right-zone row (P6: right zone shifted +2 to AC..AL)
    Dim logType As String
    Dim logAstroTgt As String, logKF As String, logLabel As String
    Dim logRy As Variant, logPitch As Variant
    Dim logDyaw As Variant, logDpitch As Variant
    logType = LCase(Trim(CStr(wsPlan.Cells(selRow, 31).value)))  ' AE Type
    logAstroTgt = CStr(wsPlan.Cells(selRow, 32).value)            ' AF AstroTgt
    logKF = CStr(wsPlan.Cells(selRow, 33).value)                  ' AG KF
    logRy = wsPlan.Cells(selRow, 34).value                        ' AH Ry
    logPitch = wsPlan.Cells(selRow, 35).value                     ' AI Pitch
    logDyaw = wsPlan.Cells(selRow, 36).value                      ' AJ Dyaw
    logDpitch = wsPlan.Cells(selRow, 37).value                    ' AK Dpitch
    logLabel = CStr(wsPlan.Cells(selRow, 38).value)               ' AL Label

    ' Find next free middle-zone row
    Dim newRow As Long
    newRow = NextFreeMiddleRow(wsPlan)
    If newRow = 0 Then
        MsgBox "Middle zone is full (max " & PLAN_MAX_ROWS & " rows).", _
               vbExclamation, "AddPlanRowFromLog"
        Exit Sub
    End If

    ' Seed defaults based on log row type
    Dim defAction As String:     defAction = "Approach"
    Dim defAnchorType As String: defAnchorType = "WP"
    Dim defAnchorRef As String:  defAnchorRef = "WP01"
    Dim defTargetType As String
    Dim defTargetRef As String
    Dim defKF As String:         defKF = ""
    Dim defRate As String:       defRate = "Cinematic ease"
    Dim defDyaw As Variant:      defDyaw = 0
    Dim defDpitch As Variant:    defDpitch = 0
    Dim defEnd As String:        defEnd = "until next"
    Dim defNote As String

    Select Case logType
        Case "marker"
            defTargetType = "log-label"
            defTargetRef = logLabel
            defNote = "Approach " & logLabel & " (from GimbalLog row " & _
                      wsPlan.Cells(selRow, 29).value & ")"
        Case "astro"
            ' Map AstroTgt to one of the Plan target types if possible.
            ' Right zone AD may be blank if #49 encoding not yet locked;
            ' fall back to "astro" generic.
            If logAstroTgt <> "" Then
                defTargetType = LCase(logAstroTgt)
            Else
                defTargetType = "sunset"   ' generic placeholder
            End If
            defTargetRef = LCase(logAstroTgt)
            defKF = logKF
            ' Astro framing uses anchor type ASTRO + the target name
            defAnchorType = "ASTRO"
            defAnchorRef = LCase(logAstroTgt)
            If Not IsEmpty(logDyaw) And IsNumeric(logDyaw) Then defDyaw = logDyaw
            If Not IsEmpty(logDpitch) And IsNumeric(logDpitch) Then defDpitch = logDpitch
            defNote = "Approach " & logAstroTgt & _
                      IIf(logKF <> "", " " & logKF, "") & _
                      " (from GimbalLog row " & wsPlan.Cells(selRow, 29).value & ")"
        Case Else
            MsgBox "GimbalLog row type '" & logType & _
                   "' not recognised (expected 'marker' or 'astro').", _
                   vbExclamation, "AddPlanRowFromLog"
            Exit Sub
    End Select

    ' Write the new row
    WriteMiddleRow wsPlan, newRow, _
                   defAnchorType, defAnchorRef, _
                   defAction, defTargetType, defTargetRef, _
                   defKF, defRate, defDyaw, defDpitch, _
                   "(computed)", defEnd, defNote

    LogEventSafe "PLAN", "AddPlanRowFromLog: row " & newRow & " from " & _
                          "log row " & selRow & " (" & logType & ")"

    Application.Goto wsPlan.Cells(newRow, 14), False   ' jump to new row, col N

    Exit Sub
ErrHandler:
    LogEventSafe "PLAN", "AddPlanRowFromLog error: " & Err.Description
    MsgBox "Error: " & Err.Description, vbCritical, "AddPlanRowFromLog"
End Sub


' ============================================================
' Public — AddBlankPlanRow
' ============================================================
Public Sub AddBlankPlanRow()
    On Error GoTo ErrHandler
    Dim wsPlan As Worksheet
    Set wsPlan = ThisWorkbook.Sheets("Plan")

    Dim newRow As Long
    newRow = NextFreeMiddleRow(wsPlan)
    If newRow = 0 Then
        MsgBox "Middle zone is full (max " & PLAN_MAX_ROWS & " rows).", _
               vbExclamation, "AddBlankPlanRow"
        Exit Sub
    End If

    ' Write a minimal seed — just the Action defaulted, rest blank
    WriteMiddleRow wsPlan, newRow, _
                   "WP", "WP01", _
                   "Approach", "", "", "", "Cinematic ease", _
                   0, 0, "(computed)", "until next", _
                   "(blank row)"

    LogEventSafe "PLAN", "AddBlankPlanRow: row " & newRow
    Application.Goto wsPlan.Cells(newRow, 14), False

    Exit Sub
ErrHandler:
    LogEventSafe "PLAN", "AddBlankPlanRow error: " & Err.Description
    MsgBox "Error: " & Err.Description, vbCritical, "AddBlankPlanRow"
End Sub


' ============================================================
' Public — InsertPlanRowAbove
' ============================================================
' Operator selects a middle-zone row. Inserts a blank row at
' that row index; existing rows from there down shift one row
' down. Stops if it would push the last row past PLAN_MAX_ROWS.
Public Sub InsertPlanRowAbove()
    On Error GoTo ErrHandler
    Dim wsPlan As Worksheet
    Set wsPlan = ActiveSheet
    If LCase(wsPlan.Name) <> "plan" Then
        MsgBox "InsertPlanRowAbove must be run on the Plan sheet.", _
               vbExclamation, "InsertPlanRowAbove"
        Exit Sub
    End If

    Dim selRow As Long
    selRow = ActiveCell.row
    If selRow < PLAN_FIRST_ROW Then
        MsgBox "Click into a middle-zone Plan row first.", vbExclamation, _
               "InsertPlanRowAbove"
        Exit Sub
    End If

    ' Check active cell is in middle zone
    Dim midFirstCol As Long, midLastCol As Long
    midFirstCol = Range(MID_COL_FIRST & "1").Column
    midLastCol = Range(MID_COL_LAST & "1").Column
    If ActiveCell.Column < midFirstCol Or ActiveCell.Column > midLastCol Then
        MsgBox "Active cell is not in the middle zone (Gimbal Plan).", _
               vbExclamation, "InsertPlanRowAbove"
        Exit Sub
    End If

    ' Find last populated row in middle zone
    Dim lastRow As Long
    lastRow = LastPopulatedMiddleRow(wsPlan)
    If lastRow >= PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1 Then
        MsgBox "Middle zone is full — cannot shift rows down.", _
               vbExclamation, "InsertPlanRowAbove"
        Exit Sub
    End If

    ' Shift rows down: copy [selRow .. lastRow] to [selRow+1 .. lastRow+1]
    ' Work upward so we don't overwrite source rows.
    Dim r As Long
    For r = lastRow To selRow Step -1
        CopyMiddleRow wsPlan, r, r + 1
    Next r

    ' Clear selRow contents (leave fills/borders so it still looks like a row)
    Dim c As Long
    For c = midFirstCol To midLastCol
        wsPlan.Cells(selRow, c).ClearContents
    Next c

    ' Re-seed empty inserted row with sensible blanks (same shape as AddBlank)
    WriteMiddleRow wsPlan, selRow, _
                   "WP", "WP01", "Approach", "", "", "", _
                   "Cinematic ease", 0, 0, "(computed)", "until next", _
                   "(inserted blank)"

    LogEventSafe "PLAN", "InsertPlanRowAbove: at row " & selRow
    Application.Goto wsPlan.Cells(selRow, 14), False

    Exit Sub
ErrHandler:
    LogEventSafe "PLAN", "InsertPlanRowAbove error: " & Err.Description
    MsgBox "Error: " & Err.Description, vbCritical, "InsertPlanRowAbove"
End Sub


' ============================================================
' Public — DeletePlanRow
' ============================================================
Public Sub DeletePlanRow()
    On Error GoTo ErrHandler
    Dim wsPlan As Worksheet
    Set wsPlan = ActiveSheet
    If LCase(wsPlan.Name) <> "plan" Then
        MsgBox "DeletePlanRow must be run on the Plan sheet.", _
               vbExclamation, "DeletePlanRow"
        Exit Sub
    End If

    Dim selRow As Long
    selRow = ActiveCell.row
    If selRow < PLAN_FIRST_ROW Then
        MsgBox "Click into a middle-zone Plan row first.", vbExclamation, _
               "DeletePlanRow"
        Exit Sub
    End If

    Dim midFirstCol As Long, midLastCol As Long
    midFirstCol = Range(MID_COL_FIRST & "1").Column
    midLastCol = Range(MID_COL_LAST & "1").Column
    If ActiveCell.Column < midFirstCol Or ActiveCell.Column > midLastCol Then
        MsgBox "Active cell is not in the middle zone (Gimbal Plan).", _
               vbExclamation, "DeletePlanRow"
        Exit Sub
    End If

    ' Confirm
    Dim resp As VbMsgBoxResult
    resp = MsgBox("Delete Plan row " & selRow & "?", _
                  vbYesNo + vbQuestion + vbDefaultButton2, "DeletePlanRow")
    If resp <> vbYes Then Exit Sub

    Dim lastRow As Long
    lastRow = LastPopulatedMiddleRow(wsPlan)

    ' Shift rows up: copy [selRow+1 .. lastRow] to [selRow .. lastRow-1]
    Dim r As Long
    For r = selRow To lastRow - 1
        CopyMiddleRow wsPlan, r + 1, r
    Next r

    ' Clear the now-empty last row
    Dim c As Long
    For c = midFirstCol To midLastCol
        wsPlan.Cells(lastRow, c).ClearContents
        wsPlan.Cells(lastRow, c).Interior.ColorIndex = xlNone
    Next c

    LogEventSafe "PLAN", "DeletePlanRow: row " & selRow & " removed"

    Exit Sub
ErrHandler:
    LogEventSafe "PLAN", "DeletePlanRow error: " & Err.Description
    MsgBox "Error: " & Err.Description, vbCritical, "DeletePlanRow"
End Sub


' ============================================================
' Public — RebuildAnchorDV
' ============================================================
' Called from Plan sheet's Worksheet_SelectionChange handler.
' Looks at Target cell's row, reads the Anchor type (col N), and
' rebuilds the data validation list on the AnchorRef cell (col O)
' to match. Snippet at bottom shows the event handler.
'
' Anchor type rules:
'   WP    -> list = WP1, WP2, ... from left zone col H (WP #)
'   ASTRO -> list = sunset, sunrise, moonrise, moonset, mwrise,
'                   mwmid, mwset (from Settings)
'   TIME  -> no dropdown; operator types HH:MM time directly
Public Sub RebuildAnchorDV(ByVal cellAnchorRef As Range)
    On Error GoTo ErrHandler

    If cellAnchorRef Is Nothing Then Exit Sub
    Dim ws As Worksheet
    Set ws = cellAnchorRef.Worksheet
    If LCase(ws.Name) <> "plan" Then Exit Sub
    If cellAnchorRef.Column <> Range(MID_COL_FIRST & "1").Column + 2 Then
        ' col O is M+2; bail if not Anchor ref column
        Exit Sub
    End If

    Dim r As Long: r = cellAnchorRef.row
    Dim anchorType As String
    anchorType = UCase(Trim(CStr(ws.Cells(r, 14).value)))   ' col N

    ' Clear any existing DV on this cell
    cellAnchorRef.Validation.Delete

    Select Case anchorType
        Case "WP"
            Dim wpList As String
            wpList = BuildWPList(ws)
            If wpList <> "" Then
                cellAnchorRef.Validation.Add Type:=xlValidateList, _
                    AlertStyle:=xlValidAlertStop, _
                    Operator:=xlBetween, _
                    Formula1:=wpList
                cellAnchorRef.Validation.ShowInput = True
                cellAnchorRef.Validation.ShowError = False  ' allow free text fallback
            End If
        Case "ASTRO"
            cellAnchorRef.Validation.Add Type:=xlValidateList, _
                AlertStyle:=xlValidAlertStop, _
                Operator:=xlBetween, _
                Formula1:="sunset,sunrise,moonrise,moonset,mwrise,mwmid,mwset"
            cellAnchorRef.Validation.ShowInput = True
            cellAnchorRef.Validation.ShowError = False
        Case "TIME"
            ' No dropdown — free text HH:MM. Validation cleared above.
        Case Else
            ' Unknown / blank — leave cleared
    End Select

    Exit Sub
ErrHandler:
    ' Silent — DV refresh failures shouldn't break authoring flow
End Sub


' ============================================================
' Private helpers
' ============================================================

' Find next free row in middle zone (col N blank = empty row)
Private Function NextFreeMiddleRow(ByVal ws As Worksheet) As Long
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If IsEmpty(ws.Cells(r, 14).value) Then     ' col N — Anchor type
            NextFreeMiddleRow = r
            Exit Function
        End If
    Next r
    NextFreeMiddleRow = 0
End Function

' Find last populated row in middle zone
Private Function LastPopulatedMiddleRow(ByVal ws As Worksheet) As Long
    Dim r As Long, last As Long
    last = PLAN_FIRST_ROW - 1
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Not IsEmpty(ws.Cells(r, 14).value) Then last = r
    Next r
    LastPopulatedMiddleRow = last
End Function

' Write a middle-zone row (cols M..AA)
' P6 column map:
'   13=M Step (formula)          18=R Action       23=W Dyaw
'   14=N AnchorType              19=S TargetType   24=X Dpitch
'   15=O AnchorRef               20=T TargetRef    25=Y MoveTime (derived)
'   16=P Offset (min)            21=U KF           26=Z EndAnchor
'   17=Q Fires at (formula)      22=V Rate         27=AA Note
' Cols P (16) and Q (17) are operator/formula territory — this helper
' does NOT write them; they're seeded by the mockup formula on row
' creation, or left blank for the operator to fill.
Private Sub WriteMiddleRow(ByVal ws As Worksheet, ByVal r As Long, _
                            ByVal anchorType As String, _
                            ByVal anchorRef As String, _
                            ByVal action As String, _
                            ByVal targetType As String, _
                            ByVal targetRef As String, _
                            ByVal kf As String, _
                            ByVal rate As String, _
                            ByVal dyaw As Variant, _
                            ByVal dpitch As Variant, _
                            ByVal moveTime As String, _
                            ByVal endAnchor As String, _
                            ByVal note As String)
    ' Col M = Step (formula)
    ws.Cells(r, 13).Formula = "=ROW()-" & (PLAN_FIRST_ROW - 1)
    ws.Cells(r, 13).Interior.Color = DERIVED_FILL_COLOR
    ws.Cells(r, 14).value = anchorType
    ws.Cells(r, 15).value = anchorRef
    ' Cols 16 (P=Offset) and 17 (Q=Fires at) intentionally not touched.
    ws.Cells(r, 18).value = action
    ws.Cells(r, 19).value = targetType
    ws.Cells(r, 20).value = targetRef
    ws.Cells(r, 21).value = kf
    ws.Cells(r, 22).value = rate
    ws.Cells(r, 23).value = dyaw
    ws.Cells(r, 24).value = dpitch
    ws.Cells(r, 25).value = moveTime
    ws.Cells(r, 25).Interior.Color = DERIVED_FILL_COLOR
    ws.Cells(r, 26).value = endAnchor
    ws.Cells(r, 27).value = note

    ' Apply seed fill to authored cells (skip derived Step + MoveTime,
    ' and skip Q = Fires at which is formula-territory)
    Dim c As Long
    For c = 14 To 27
        If c <> 25 And c <> 17 Then
            ws.Cells(r, c).Interior.Color = SEED_FILL_COLOR
        End If
    Next c
End Sub

' Copy one middle-zone row to another row.
' Special columns:
'   13 (M) Step — re-formula at new row, not copied
'   17 (Q) Fires at — re-formula at new row, not copied. The formula
'          references the same-row N/O/P, so a value-copy would freeze
'          the destination row to the source row's resolved time.
Private Sub CopyMiddleRow(ByVal ws As Worksheet, _
                          ByVal srcRow As Long, ByVal dstRow As Long)
    Dim midFirstCol As Long: midFirstCol = Range(MID_COL_FIRST & "1").Column
    Dim midLastCol As Long:  midLastCol = Range(MID_COL_LAST & "1").Column
    Dim c As Long
    For c = midFirstCol To midLastCol
        If c = 13 Then
            ' Step column — re-formula, not copy
            ws.Cells(dstRow, 13).Formula = "=ROW()-" & (PLAN_FIRST_ROW - 1)
        ElseIf c = 17 Then
            ' Fires at — copy the formula text verbatim. Excel updates
            ' relative refs (N/O/P) to the destination row automatically.
            ws.Cells(dstRow, 17).Formula = ws.Cells(srcRow, 17).Formula
        Else
            ws.Cells(dstRow, c).value = ws.Cells(srcRow, c).value
        End If
        ws.Cells(dstRow, c).Interior.Color = ws.Cells(srcRow, c).Interior.Color
    Next c
End Sub

' Build a comma-separated WP list from left zone col H.
' P6: col H now holds text strings "WP01", "WP02", ... directly.
' We pass them through verbatim. (Pre-P6 stored integers and we
' formatted "WP" & CLng(v) — that path is gone.)
Private Function BuildWPList(ByVal ws As Worksheet) As String
    Dim s As String: s = ""
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        Dim v As Variant
        v = ws.Cells(r, 8).value     ' col H — WP #
        If Not IsEmpty(v) Then
            Dim sv As String: sv = Trim(CStr(v))
            If Len(sv) > 0 Then
                If s <> "" Then s = s & ","
                s = s & sv
            End If
        End If
    Next r
    BuildWPList = s
End Function

' Log helper
Private Sub LogEventSafe(ByVal category As String, ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", category, msg
    On Error GoTo 0
End Sub


' ============================================================
' Sheet-module snippet — paste into the Plan sheet's code module
' ============================================================
' To enable the dynamic anchor-ref dropdowns (#5 in P5), paste
' this Worksheet_SelectionChange handler into the Plan sheet's
' code module (not into PlanAuthoring.bas — has to live in the
' sheet itself):
'
' --- Begin paste ---
' Private Sub Worksheet_SelectionChange(ByVal Target As Range)
'     ' Rebuild anchor-ref dropdown when operator clicks into
'     ' col O (Anchor ref) in the middle zone.
'     If Target.Cells.Count <> 1 Then Exit Sub
'     If Target.Column = Range("O1").Column And _
'        Target.Row >= 6 And Target.Row < 66 Then
'         PlanAuthoring.RebuildAnchorDV Target
'     End If
' End Sub
' --- End paste ---
