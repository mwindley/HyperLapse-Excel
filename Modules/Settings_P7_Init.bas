Attribute VB_Name = "Settings_P7_Init"
' ============================================================
' HyperLapse Cart - Settings P7 Init
'
' One-shot setup macro: adds the 7 named ranges Session E
' introduced that are still missing from HyperLapse.xlsm.
'
' Public entry:
'   InitSettingsP7 - checks each of the 7 names; for any missing,
'                    writes label + seed value + number format,
'                    then defines the workbook-level name pointing
'                    at the seed cell. Idempotent: re-running won't
'                    duplicate anything.
'
' New names (with seed values matching the Plan_mockup_P7 mockup):
'   dataShootStart           15:42:00   wall-clock cart start
'   dataMWRiseTime           22:30:00   MW core rises
'   dataMWTransitTime        02:15:00   MW core transit
'   dataMWSetTime            06:00:00   MW core sets
'   dataEaseJustPerceptible  3          frames (60fps)
'   dataEaseComfortable      10         frames
'   dataEaseCinematic        30         frames
'
' Layout: appends a labeled block to Settings starting at row 48
' (Settings currently ends at row 46). One section header row
' per group; cells in col B/C/D mirror the existing Settings
' convention (label B, value C, comment D).
'
' Session E (Day 20). One-shot - delete this module after running
' if you like, the named ranges live on in the workbook regardless.
' ============================================================

Option Explicit

' Append-block starts at this row (after the existing last-used row 46
' plus a one-row gutter).
Private Const START_ROW As Long = 48

Public Sub InitSettingsP7()
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Settings")

    Dim r As Long: r = START_ROW
    Dim added As Long: added = 0
    Dim skipped As Long: skipped = 0
    Dim report As String: report = ""

    ' --- Section 1: Shoot start anchor ---------------------------------
    ws.Cells(r, 2).value = "Plan authoring (Session E)"
    ws.Cells(r, 2).Font.Bold = True
    r = r + 1
    ' #57/exposure-phase-rework: dataShootStart is now a FULL DATE-TIME (the
    ' single source of truth for the shoot). The operator enters the shoot
    ' START as date+time; GetSunsetTime derives the night from its date. Seed
    ' with tonight 19:42 as a sensible default the operator overwrites.
    If AddNamedDateTime(ws, r, "dataShootStart", "Shoot start (date + time)", _
                    CDbl(Int(Now())) + TimeSerial(19, 42, 0), _
                    "FULL date+time. Operator enters the shoot START here. The night " & _
                    "(dusk/dawn) and plan times are all computed from this. Not in the past.", _
                    added, skipped, report) Then r = r + 1

    ' --- Section 2: Milky Way times ------------------------------------
    r = r + 1
    ws.Cells(r, 2).value = "Milky Way times (placeholders; push from Astro.bas)"
    ws.Cells(r, 2).Font.Italic = True
    r = r + 1
    If AddNamedTime(ws, r, "dataMWRiseTime", "MW core rise", _
                    TimeSerial(22, 30, 0), _
                    "Location-dependent; placeholder", _
                    added, skipped, report) Then r = r + 1
    If AddNamedTime(ws, r, "dataMWTransitTime", "MW core transit", _
                    TimeSerial(2, 15, 0), _
                    "Location-dependent; placeholder", _
                    added, skipped, report) Then r = r + 1
    If AddNamedTime(ws, r, "dataMWSetTime", "MW core set", _
                    TimeSerial(6, 0, 0), _
                    "Location-dependent; placeholder", _
                    added, skipped, report) Then r = r + 1

    ' --- Section 3: Ease band frames -----------------------------------
    r = r + 1
    ws.Cells(r, 2).value = "Ease band durations (audience frames at 60fps)"
    ws.Cells(r, 2).Font.Italic = True
    r = r + 1
    If AddNamedInt(ws, r, "dataEaseJustPerceptible", "Ease: Just-perceptible", _
                   3, "Frames; ~3 = abrupt but noticed", _
                   added, skipped, report) Then r = r + 1
    If AddNamedInt(ws, r, "dataEaseComfortable", "Ease: Comfortable", _
                   10, "Frames; comfortable cinematic", _
                   added, skipped, report) Then r = r + 1
    If AddNamedInt(ws, r, "dataEaseCinematic", "Ease: Cinematic", _
                   30, "Frames; slow, deliberate", _
                   added, skipped, report) Then r = r + 1

    ' --- Footnote ------------------------------------------------------
    r = r + 1
    ws.Cells(r, 2).value = "NB: ease duration = frames x cadence_sec (cadence from Tv at fire time)"
    ws.Cells(r, 2).Font.Italic = True

    ' --- Report --------------------------------------------------------
    Dim summary As String
    summary = "InitSettingsP7 complete." & vbCrLf & vbCrLf & _
              "Added:   " & added & vbCrLf & _
              "Skipped: " & skipped & "  (already defined)" & vbCrLf & vbCrLf & _
              report
    MsgBox summary, vbInformation, "InitSettingsP7"

    On Error Resume Next
    Application.Run "Utils.LogEvent", "PLAN", _
        "InitSettingsP7: added=" & added & " skipped=" & skipped
    On Error GoTo 0

    Exit Sub

ErrHandler:
    MsgBox "Error in InitSettingsP7:" & vbCrLf & vbCrLf & _
           Err.Description, vbCritical, "InitSettingsP7"
End Sub


' ============================================================
' AddPlanPushDryRunFlag - appends the dataPlanPushDryRun
' named range to Settings. Stage-1 follow-up to InitSettingsP7.
'
' Lives in its own sub so re-running InitSettingsP7 doesn't paint
' "(already defined)" rows over the original labels. Picks the
' first empty row past the existing Plan-authoring block.
'
' Idempotent: skips silently if the name already exists.
' ============================================================
Public Sub AddPlanPushDryRunFlag()
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Settings")

    If NameExists("dataPlanPushDryRun") Then
        MsgBox "dataPlanPushDryRun already defined. Nothing to do.", _
               vbInformation, "AddPlanPushDryRunFlag"
        Exit Sub
    End If

    ' Find first empty row past row 60 (existing block ends at ~row 61
    ' with the ease-duration footnote). Look for two consecutive blanks
    ' to be sure we're past any trailing labels.
    Dim r As Long: r = 62
    Do While Not IsEmpty(ws.Cells(r, 2).value) Or _
             Not IsEmpty(ws.Cells(r, 3).value)
        r = r + 1
        If r > 200 Then Exit Do  ' safety
    Loop

    ' Header row + value row
    ws.Cells(r, 2).value = "P7 Plan push"
    ws.Cells(r, 2).Font.Italic = True
    r = r + 1
    ws.Cells(r, 2).value = "Plan push dry-run"
    ws.Cells(r, 3).value = True

    ws.Cells(r, 4).value = "TRUE = validate + decompose only, no POST. FALSE = real push (pings cart first)."
    ThisWorkbook.names.Add Name:="dataPlanPushDryRun", _
                           refersTo:="=Settings!$C$" & r

    MsgBox "Added dataPlanPushDryRun at Settings!$C$" & r & " (default TRUE).", _
           vbInformation, "AddPlanPushDryRunFlag"

    On Error Resume Next
    Application.Run "Utils.LogEvent", "PLAN", _
        "AddPlanPushDryRunFlag: added at C" & r
    On Error GoTo 0

    Exit Sub

ErrHandler:
    MsgBox "Error in AddPlanPushDryRunFlag:" & vbCrLf & vbCrLf & _
           Err.Description, vbCritical, "AddPlanPushDryRunFlag"
End Sub


' ============================================================
' Add a Time-typed named range. Returns True if a row was used
' (either added or skipped - the label row is written either way
' so the operator can see what's already defined). Returns False
' only on unrecoverable error.
' ============================================================
Private Function AddNamedTime(ByVal ws As Worksheet, ByVal r As Long, _
                              ByVal nm As String, ByVal label As String, _
                              ByVal seedVal As Double, ByVal comment As String, _
                              ByRef added As Long, ByRef skipped As Long, _
                              ByRef report As String) As Boolean
    If NameExists(nm) Then
        ws.Cells(r, 2).value = label & "  (already defined)"
        ws.Cells(r, 2).Font.Color = RGB(128, 128, 128)
        ws.Cells(r, 4).value = "skipped - name already exists"
        ws.Cells(r, 4).Font.Color = RGB(128, 128, 128)
        skipped = skipped + 1
        report = report & "  - " & nm & ": SKIPPED" & vbCrLf
    Else
        ws.Cells(r, 2).value = label
        ws.Cells(r, 3).value = seedVal
        ws.Cells(r, 3).NumberFormat = "hh:mm:ss"
        ws.Cells(r, 4).value = comment
        ThisWorkbook.names.Add Name:=nm, refersTo:="=Settings!$C$" & r
        added = added + 1
        report = report & "  - " & nm & ": added at C" & r & vbCrLf
    End If
    AddNamedTime = True
End Function

' #57/exposure-phase-rework: sibling of AddNamedTime that seeds + formats a
' FULL DATE-TIME (not time-only). Used for dataShootStart so the operator
' enters the shoot start as date+time, the single source of truth for the night.
Private Function AddNamedDateTime(ByVal ws As Worksheet, ByVal r As Long, _
                              ByVal nm As String, ByVal label As String, _
                              ByVal seedVal As Double, ByVal comment As String, _
                              ByRef added As Long, ByRef skipped As Long, _
                              ByRef report As String) As Boolean
    If NameExists(nm) Then
        ws.Cells(r, 2).value = label & "  (already defined)"
        ws.Cells(r, 2).Font.Color = RGB(128, 128, 128)
        ws.Cells(r, 4).value = "skipped - name already exists"
        ws.Cells(r, 4).Font.Color = RGB(128, 128, 128)
        skipped = skipped + 1
        report = report & "  - " & nm & ": SKIPPED" & vbCrLf
    Else
        ws.Cells(r, 2).value = label
        ws.Cells(r, 3).value = seedVal
        ws.Cells(r, 3).NumberFormat = "yyyy-mm-dd hh:mm"
        ws.Cells(r, 4).value = comment
        ThisWorkbook.names.Add Name:=nm, refersTo:="=Settings!$C$" & r
        added = added + 1
        report = report & "  - " & nm & ": added at C" & r & vbCrLf
    End If
    AddNamedDateTime = True
End Function


' ============================================================
' Add an Integer-typed named range.
' ============================================================
Private Function AddNamedInt(ByVal ws As Worksheet, ByVal r As Long, _
                             ByVal nm As String, ByVal label As String, _
                             ByVal seedVal As Long, ByVal comment As String, _
                             ByRef added As Long, ByRef skipped As Long, _
                             ByRef report As String) As Boolean
    If NameExists(nm) Then
        ws.Cells(r, 2).value = label & "  (already defined)"
        ws.Cells(r, 2).Font.Color = RGB(128, 128, 128)
        ws.Cells(r, 4).value = "skipped - name already exists"
        ws.Cells(r, 4).Font.Color = RGB(128, 128, 128)
        skipped = skipped + 1
        report = report & "  - " & nm & ": SKIPPED" & vbCrLf
    Else
        ws.Cells(r, 2).value = label
        ws.Cells(r, 3).value = seedVal
        ws.Cells(r, 3).NumberFormat = "0"
        ws.Cells(r, 4).value = comment
        ThisWorkbook.names.Add Name:=nm, refersTo:="=Settings!$C$" & r
        added = added + 1
        report = report & "  - " & nm & ": added at C" & r & vbCrLf
    End If
    AddNamedInt = True
End Function


' ============================================================
' Check whether a workbook-level name already exists.
' Trapping NameExists via On Error is the canonical VBA idiom -
' Names("foo") raises a runtime error if not found.
' ============================================================
Private Function NameExists(ByVal nm As String) As Boolean
    Dim n As Name
    On Error Resume Next
    Set n = ThisWorkbook.names(nm)
    On Error GoTo 0
    NameExists = Not (n Is Nothing)
End Function
