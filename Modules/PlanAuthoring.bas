Attribute VB_Name = "PlanAuthoring"
' ============================================================
' HyperLapse Cart - Plan Authoring Helpers (P5)
'
' Middle-zone row management for the Plan sheet.
'
' Public entries (assign to ribbon buttons or shapes):
'   AddPlanRowFromLog    - read selected right-zone row, append
'                          middle-zone row with sensible defaults
'   AddBlankPlanRow      - append empty middle-zone row
'   InsertPlanRowAbove   - operator selects a middle row;
'                          inserts blank row above it
'   DeletePlanRow        - operator selects a middle row;
'                          deletes it and shifts rows up
'   RebuildAnchorDV      - refresh the dynamic dropdowns on a
'                          single anchor-ref cell (called from
'                          the Plan sheet's Worksheet_SelectionChange
'                          event handler - see comment block at
'                          bottom for the snippet to paste into
'                          the Plan sheet's code module)
'
' Day 19 - initial P5 implementation.
' Day 20 - P6 column shift: middle zone now M..AA (was M..Y).
'          Two new columns inserted after Anchor ref (col O):
'            P = Offset (min)   - editable, blank=0
'            Q = Fires at       - derived formula (anchor resolver)
'          Old cols P..Y shifted +2 to R..AA. All Cells(r,c) column
'          numbers from 16 upward in this module bumped accordingly.
'          Right zone ALSO shifted +2 to AC..AL to avoid AA collision
'          with the new middle-zone end (Note). Right-zone reads in
'          AddPlanRowFromLog updated; gap at column AB.
'          WP # convention also tightened: H column and Anchor ref
'          both use WP01..WPNN text strings (was integer in H,
'          "WP<n>" in O). BuildWPList updated to read strings.
' Day 20 - Session E: significant vocabulary + layout refinement.
'          Middle zone expanded to M..AB (16 cols, was 15). Right zone
'          shifted one more column to AD..AM. Visual gutter at AC.
'          - Dropped: S (Target type), U (KF), Z (End anchor)
'          - Added:   R (Total dur - derived), V (Ry), W (Rp),
'                     Z (Ease)
'          - Action vocabulary refined to:
'              Pan Follow / Lock / Move / Track / Track-yaw / END
'            (Day-19 "Approach" word dropped - split into Move for
'             static targets and Track for moving astro targets.)
'          - Step column (M) is now text formula "GP01"/"GP02"/...
'            instead of numeric.
'          - Col H in left zone collapsed into col B; BuildWPList
'            now reads col B (2) instead of col H (8).
'          - Track-yaw mode: col W (Rp) carries operator-typed
'            absolute pitch (not a delta). Matches firmware GTM_YAW='Y'.
'          - Plans end with sentinel END row (Action=END) rather than
'            an End anchor column.
'
' Plan sheet middle-zone columns (Session E layout):
'   M=Step("GP01"), N=AnchorType, O=AnchorRef, P=Offset(min),
'   Q=Fires at(fml), R=Total dur(fml), S=Action, T=Target,
'   U=Rate, V=Ry, W=Rp, X=dyaw, Y=dpitch, Z=Ease, AA=Move t,
'   AB=Note
'
' Right zone (Session E: shifted +1 from P6):
'   AD=LogRow#, AE=Time, AF=Type, AG=AstroTgt, AH=KF, AI=Ry,
'   AJ=Pitch, AK=dyaw, AL=dpitch, AM=Label
'
' Day 20 - Session E patch (Session F day 21 import): em-dash
' string literals replaced with EmDash() helper returning
' ChrW(8212). VBE import had been mangling the literal "-" into
' "--"" (UTF-8-as-Win1252 reinterpretation). ChrW path is
' bullet-proof across export/import round-trips.
'
' Day 21 (Session F) - workfront #67 Phase 1: operator-facing
' rename mw -> gc. Anchor-ref DV list updated to gcrise/gctransit/
' gcset; AddPlanRowFromLog heuristic outputs "gc" (accepts either
' "gc" or "mw" on input for back-compat with pre-rename logs).
' Cart wire protocol stays "mw" - AstroPush.bas unchanged.
' ============================================================

Option Explicit

Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_MAX_ROWS  As Long = 60

Private Const MID_COL_FIRST As String = "M"
Private Const MID_COL_LAST  As String = "AB"

Private Const RIGHT_COL_FIRST As String = "AD"
Private Const RIGHT_COL_LAST  As String = "AM"

' Seed fill colour matches P1 mockup (pale yellow)
Private Const SEED_FILL_COLOR As Long = &HFFFFEE
Private Const DERIVED_FILL_COLOR As Long = &HF5F5F5


' ============================================================
' Public - AddPlanRowFromLog
' ============================================================
' Reads the right-zone row containing the active cell; appends
' a new middle-zone row at the bottom with sensible defaults
' derived from the log row's Type (Session E vocabulary):
'   Type=marker -> Move with target = log label, Ry/Rp auto-fill
'   Type=astro  -> Move with astro object target, anchor=astro event,
'                  dyaw/dpitch copied from capture
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

    ' Verify selection is in right zone - col AA or later
    If ActiveCell.Column < Range(RIGHT_COL_FIRST & "1").Column Then
        MsgBox "Active cell is not in the right zone (GimbalLog " & _
               "reference). Click into a right-zone row first.", _
               vbExclamation, "AddPlanRowFromLog"
        Exit Sub
    End If

    ' Read right-zone row (Session E: right zone shifted +1 from P6 to AD..AM)
    Dim logType As String
    Dim logAstroTgt As String, logKF As String, logLabel As String
    Dim logRy As Variant, logPitch As Variant
    Dim logDyaw As Variant, logDpitch As Variant
    logType = LCase(Trim(CStr(wsPlan.Cells(selRow, 32).value)))  ' AF Type
    logAstroTgt = CStr(wsPlan.Cells(selRow, 33).value)            ' AG AstroTgt
    logKF = CStr(wsPlan.Cells(selRow, 34).value)                  ' AH KF
    logRy = wsPlan.Cells(selRow, 35).value                        ' AI Ry
    logPitch = wsPlan.Cells(selRow, 36).value                     ' AJ Pitch
    logDyaw = wsPlan.Cells(selRow, 37).value                      ' AK Dyaw
    logDpitch = wsPlan.Cells(selRow, 38).value                    ' AL Dpitch
    logLabel = CStr(wsPlan.Cells(selRow, 39).value)               ' AM Label

    ' Find next free middle-zone row
    Dim newRow As Long
    newRow = NextFreeMiddleRow(wsPlan)
    If newRow = 0 Then
        MsgBox "Middle zone is full (max " & PLAN_MAX_ROWS & " rows).", _
               vbExclamation, "AddPlanRowFromLog"
        Exit Sub
    End If

    ' Seed defaults based on log row type.
    ' Session E vocabulary: Move (static target) / Track (moving astro).
    ' marker -> Move; astro framing -> Move with astro target + d (the row
    ' fires at the astro event anchor, target=sun/moon/gc resolves to
    ' that object's position at fire time).
    Dim defAction As String:     defAction = "Move"
    Dim defAnchorType As String: defAnchorType = "WP"
    Dim defAnchorRef As String:  defAnchorRef = "WP01"
    Dim defTarget As String
    Dim defRate As String:       defRate = "Cinematic ease"
    Dim defRy As Variant:        defRy = EmDash()     ' formula-fills if marker target
    Dim defRp As Variant:        defRp = EmDash()
    Dim defDyaw As Variant:      defDyaw = 0
    Dim defDpitch As Variant:    defDpitch = 0
    Dim defEase As String:       defEase = "Comfortable"
    Dim defNote As String

    Select Case logType
        Case "marker"
            ' Move to a recon marker (Tree, Harbour, ...). Target = label.
            ' Ry/Rp will be auto-populated by the mockup's V/W formula via
            ' lookup of label in right-zone Label column.
            defTarget = logLabel
            defNote = "Move to " & logLabel & " (from GimbalLog row " & _
                      wsPlan.Cells(selRow, 30).value & ")"
        Case "astro"
            ' Astro framing - operator captured dyaw/dpitch from a predicted
            ' astro position. In Session E vocabulary the row is a Move to
            ' the astro object (target = sun/moon/gc) anchored on the astro
            ' event (sunset/sunrise/etc.) with the captured d.
            defAnchorType = "ASTRO"
            ' If AstroTgt names an event (sunset, moonrise, etc.) use it as
            ' the anchor; otherwise fall back to sunset placeholder.
            If logAstroTgt <> "" Then
                defAnchorRef = LCase(logAstroTgt)
            Else
                defAnchorRef = "sunset"
            End If
            ' Target is the object the astro event names. Heuristic:
            '   sunset/sunrise          -> sun
            '   moonrise/moonset        -> moon
            '   gcrise/gctransit/gcset  -> gc (Galactic Centre - Milky Way core)
            ' We also accept the legacy "mw*" tokens since the firmware
            ' protocol still uses "mw" and any pre-rename GimbalLog rows
            ' will have "mw*" anchor refs. Workfront #67.
            Dim t As String: t = LCase(logAstroTgt)
            If InStr(t, "sun") > 0 Then
                defTarget = "sun"
            ElseIf InStr(t, "moon") > 0 Then
                defTarget = "moon"
            ElseIf InStr(t, "gc") > 0 Or InStr(t, "mw") > 0 Then
                defTarget = "gc"
            Else
                defTarget = "sun"  ' fallback
            End If
            If Not IsEmpty(logDyaw) And IsNumeric(logDyaw) Then defDyaw = logDyaw
            If Not IsEmpty(logDpitch) And IsNumeric(logDpitch) Then defDpitch = logDpitch
            defNote = "Move to " & defTarget & " at " & defAnchorRef & _
                      IIf(logKF <> "", " " & logKF, "") & _
                      " (from GimbalLog row " & wsPlan.Cells(selRow, 30).value & ")"
        Case Else
            MsgBox "GimbalLog row type '" & logType & _
                   "' not recognised (expected 'marker' or 'astro').", _
                   vbExclamation, "AddPlanRowFromLog"
            Exit Sub
    End Select

    ' Write the new row (Session E signature: target, rate, ry, rp, dyaw,
    ' dpitch, ease, moveTime, note - no targetType/kf/endAnchor params)
    WriteMiddleRow wsPlan, newRow, _
                   defAnchorType, defAnchorRef, _
                   defAction, defTarget, defRate, _
                   defRy, defRp, defDyaw, defDpitch, _
                   defEase, "(computed)", defNote

    LogEventSafe "PLAN", "AddPlanRowFromLog: row " & newRow & " from " & _
                          "log row " & selRow & " (" & logType & ")"

    Application.GoTo wsPlan.Cells(newRow, 14), False   ' jump to new row, col N

    Exit Sub
ErrHandler:
    LogEventSafe "PLAN", "AddPlanRowFromLog error: " & Err.Description
    MsgBox "Error: " & Err.Description, vbCritical, "AddPlanRowFromLog"
End Sub


' ============================================================
' Public - AddBlankPlanRow
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

    ' Write a minimal seed - Session E signature
    WriteMiddleRow wsPlan, newRow, _
                   "WP", "WP01", _
                   "Move", "", "Cinematic ease", _
                   EmDash(), EmDash(), 0, 0, _
                   "none", "(computed)", _
                   "(blank row)"

    LogEventSafe "PLAN", "AddBlankPlanRow: row " & newRow
    Application.GoTo wsPlan.Cells(newRow, 14), False

    Exit Sub
ErrHandler:
    LogEventSafe "PLAN", "AddBlankPlanRow error: " & Err.Description
    MsgBox "Error: " & Err.Description, vbCritical, "AddBlankPlanRow"
End Sub


' ============================================================
' Public - InsertPlanRowAbove
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
        MsgBox "Middle zone is full - cannot shift rows down.", _
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

    ' Re-seed empty inserted row with sensible blanks (Session E signature)
    WriteMiddleRow wsPlan, selRow, _
                   "WP", "WP01", "Move", "", "Cinematic ease", _
                   EmDash(), EmDash(), 0, 0, "none", "(computed)", _
                   "(inserted blank)"

    LogEventSafe "PLAN", "InsertPlanRowAbove: at row " & selRow
    Application.GoTo wsPlan.Cells(selRow, 14), False

    Exit Sub
ErrHandler:
    LogEventSafe "PLAN", "InsertPlanRowAbove error: " & Err.Description
    MsgBox "Error: " & Err.Description, vbCritical, "InsertPlanRowAbove"
End Sub


' ============================================================
' Public - DeletePlanRow
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
' Public - RebuildAnchorDV
' ============================================================
' Called from Plan sheet's Worksheet_SelectionChange handler.
' Looks at Target cell's row, reads the Anchor type (col N), and
' rebuilds the data validation list on the AnchorRef cell (col O)
' to match. Snippet at bottom shows the event handler.
'
' Anchor type rules:
'   WP    -> list = WP1, WP2, ... from left zone col H (WP #)
'   ASTRO -> list = sunset, sunrise, moonrise, moonset, gcrise,
'                   gctransit, gcset (from Settings)
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
                Formula1:="sunset,sunrise,moonrise,moonset,gcrise,gctransit,gcset"
            cellAnchorRef.Validation.ShowInput = True
            cellAnchorRef.Validation.ShowError = False
        Case "TIME"
            ' No dropdown - free text HH:MM. Validation cleared above.
        Case Else
            ' Unknown / blank - leave cleared
    End Select

    Exit Sub
ErrHandler:
    ' Silent - DV refresh failures shouldn't break authoring flow
End Sub


' ============================================================
' Private helpers
' ============================================================

' Find next free row in middle zone (col N blank = empty row)
Private Function NextFreeMiddleRow(ByVal ws As Worksheet) As Long
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If IsEmpty(ws.Cells(r, 14).value) Then     ' col N - Anchor type
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

' Write a middle-zone row (cols M..AB, Session E layout).
'
' Session E column map:
'   13=M Step (text formula "GP01")          22=V Ry
'   14=N AnchorType                           23=W Rp
'   15=O AnchorRef                            24=X Dyaw
'   16=P Offset (min)         [skipped]       25=Y Dpitch
'   17=Q Fires at (formula)   [skipped]       26=Z Ease
'   18=R Total dur (formula)  [skipped]       27=AA Move t (derived)
'   19=S Action                               28=AB Note
'   20=T Target
'   21=U Rate
'
' Cols P (Offset), Q (Fires at), R (Total dur) are operator/formula
' territory - this helper does NOT write them; Offset is operator-
' filled, Fires-at and Total-dur are seeded by formula on row creation
' (the mockup pre-fills the formula; this helper assumes it's there).
Private Sub WriteMiddleRow(ByVal ws As Worksheet, ByVal r As Long, _
                            ByVal anchorType As String, _
                            ByVal anchorRef As String, _
                            ByVal action As String, _
                            ByVal target As String, _
                            ByVal rate As String, _
                            ByVal ry As Variant, _
                            ByVal rp As Variant, _
                            ByVal dyaw As Variant, _
                            ByVal dpitch As Variant, _
                            ByVal ease As String, _
                            ByVal moveTime As String, _
                            ByVal note As String)
    ' Col M = Step (text formula "GP01"/"GP02"/...)
    ws.Cells(r, 13).Formula = "=""GP"" & TEXT(ROW()-" & (PLAN_FIRST_ROW - 1) & ",""00"")"
    ws.Cells(r, 13).Interior.Color = DERIVED_FILL_COLOR
    ws.Cells(r, 14).value = anchorType
    ws.Cells(r, 15).value = anchorRef
    ' Cols 16 (P=Offset), 17 (Q=Fires at), 18 (R=Total dur) intentionally
    ' not touched.
    ws.Cells(r, 19).value = action
    ws.Cells(r, 20).value = target
    ws.Cells(r, 21).value = rate
    ws.Cells(r, 22).value = ry
    ws.Cells(r, 23).value = rp
    ws.Cells(r, 24).value = dyaw
    ws.Cells(r, 25).value = dpitch
    ws.Cells(r, 26).value = ease
    ws.Cells(r, 27).value = moveTime
    ws.Cells(r, 27).Interior.Color = DERIVED_FILL_COLOR
    ws.Cells(r, 28).value = note

    ' Apply seed fill to authored cells. Skip derived/formula cols:
    '   13 = Step (formula)
    '   17 = Fires at (formula)
    '   18 = Total dur (formula)
    '   27 = Move t (derived placeholder)
    Dim c As Long
    For c = 14 To 28
        If c <> 17 And c <> 18 And c <> 27 Then
            ws.Cells(r, c).Interior.Color = SEED_FILL_COLOR
        End If
    Next c
End Sub

' Copy one middle-zone row to another row.
' Special columns (Session E):
'   13 (M) Step - re-formula at new row, not copied
'   17 (Q) Fires at - re-formula at new row. References same-row N/O/P
'          so a value-copy would freeze the destination to the source's
'          resolved time.
'   18 (R) Total dur - re-formula at new row. References same-row Q
'          and next-row Q; value-copy would freeze incorrectly.
Private Sub CopyMiddleRow(ByVal ws As Worksheet, _
                          ByVal srcRow As Long, ByVal dstRow As Long)
    Dim midFirstCol As Long: midFirstCol = Range(MID_COL_FIRST & "1").Column
    Dim midLastCol As Long:  midLastCol = Range(MID_COL_LAST & "1").Column
    Dim c As Long
    For c = midFirstCol To midLastCol
        If c = 13 Then
            ' Step column - re-formula, not copy
            ws.Cells(dstRow, 13).Formula = _
                "=""GP"" & TEXT(ROW()-" & (PLAN_FIRST_ROW - 1) & ",""00"")"
        ElseIf c = 17 Or c = 18 Then
            ' Fires at / Total dur - copy the formula text verbatim.
            ' Excel updates relative refs to the destination row automatically.
            ws.Cells(dstRow, c).Formula = ws.Cells(srcRow, c).Formula
        Else
            ws.Cells(dstRow, c).value = ws.Cells(srcRow, c).value
        End If
        ws.Cells(dstRow, c).Interior.Color = ws.Cells(srcRow, c).Interior.Color
    Next c
End Sub

' Build a comma-separated WP list from left zone col B (WP label).
' Session E: col B IS the WP label ("WP01" text). Col H was dropped
' (it carried the WP label in P6, redundant with B once both became
' text). Reads strings directly through to the dropdown.
Private Function BuildWPList(ByVal ws As Worksheet) As String
    Dim s As String: s = ""
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        Dim v As Variant
        v = ws.Cells(r, 2).value     ' col B - WP label
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

' Em-dash returned via ChrW so the .bas source stays ASCII -
' avoids encoding loss during VBE export/import round-trips. The
' VBE writes .bas files in Windows-1252; em-dash (Unicode U+2014)
' round-trips cleanly through that path, but external editors and
' some Git operations can mangle it. ChrW() is bullet-proof.
Private Function EmDash() As String
    EmDash = ChrW(8212)
End Function

' Log helper
Private Sub LogEventSafe(ByVal category As String, ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", category, msg
    On Error GoTo 0
End Sub


' ============================================================
' Sheet-module snippet - paste into the Plan sheet's code module
' ============================================================
' To enable the dynamic anchor-ref dropdowns (#5 in P5), paste
' this Worksheet_SelectionChange handler into the Plan sheet's
' code module (not into PlanAuthoring.bas - has to live in the
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
