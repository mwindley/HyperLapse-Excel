Attribute VB_Name = "MWToGCRenamer"
' ============================================================
' HyperLapse Cart — One-shot rename macro: MW -> GC
'
' Per workfront #67 Phase 1 (Excel-side operator-facing rename).
' Cart wire protocol stays "mw" — AstroPush.bas still sends
' obj="mw" to the cart. This macro only touches Excel-facing
' operator surfaces.
'
' Public entry:
'   RenameMWToGC — runs all the swaps below, reports a summary
'
' What this macro does:
'   1. Renames three named ranges:
'        dataMWRiseTime    -> dataGCRiseTime
'        dataMWTransitTime -> dataGCTransitTime
'        dataMWSetTime     -> dataGCSetTime
'   2. Updates the labels in col B of the cells those names point at
'      ("MW core rise" -> "GC rise", etc.).
'   3. Walks Plan!Q6:Q20 anchor-resolver formulas, replacing all
'      references to dataMW* with dataGC* and string literals
'      "mwrise"/"mwtransit"/"mwset" with "gcrise"/"gctransit"/"gcset".
'
' What this macro does NOT do (handled in updated .bas files
' that the operator re-imports separately):
'   - PlanAuthoring.bas heuristic + DV string literal
'   - PlanPush.bas IsAstroTarget case
'   - AstroPush.bas variable names (internal; deferred to #67 Phase 2)
'   - Sketch-side track_mw identifier (deferred to v2 port)
'
' Idempotent: if a rename has already happened the macro skips it.
' Safe to re-run.
' ============================================================

Option Explicit

Public Sub RenameMWToGC()
    On Error GoTo ErrHandler

    Dim summary As String
    summary = "Rename MW -> GC summary:" & vbCrLf & vbCrLf

    ' --- Step 1: rename the three named ranges ---
    summary = summary & "Step 1 — Named ranges:" & vbCrLf
    summary = summary & RenameOne("dataMWRiseTime", "dataGCRiseTime", _
                                  "GC rise (was MW core rise)")
    summary = summary & RenameOne("dataMWTransitTime", "dataGCTransitTime", _
                                  "GC transit (was MW core transit)")
    summary = summary & RenameOne("dataMWSetTime", "dataGCSetTime", _
                                  "GC set (was MW core set)")

    ' --- Step 2: update the Q-column formulas on the Plan sheet ---
    summary = summary & vbCrLf & "Step 2 — Plan Q-column formulas:" & vbCrLf
    summary = summary & RewriteAnchorFormulas()

    ' --- Step 3: update Settings section header label if present ---
    summary = summary & vbCrLf & "Step 3 — Settings labels:" & vbCrLf
    summary = summary & RewriteSettingsHeader()

    MsgBox summary, vbInformation, "RenameMWToGC"

    On Error Resume Next
    Application.Run "Utils.LogEvent", "PLAN", "RenameMWToGC: complete"
    On Error GoTo 0
    Exit Sub

ErrHandler:
    MsgBox "Error in RenameMWToGC:" & vbCrLf & vbCrLf & _
           Err.Description, vbCritical, "RenameMWToGC"
End Sub


' ============================================================
' Rename one workbook-level named range.
'   - If new name already exists: skip (idempotent)
'   - If old name exists: read its RefersTo, delete old, add new at
'     same RefersTo, update the label in col B of that cell
'   - If neither exists: warn
' Returns a line of text describing what happened.
' ============================================================
Private Function RenameOne(ByVal oldName As String, ByVal newName As String, _
                            ByVal newLabel As String) As String
    Dim msg As String

    If NameExists(newName) Then
        RenameOne = "  " & oldName & " -> " & newName & ": already done" & vbCrLf
        Exit Function
    End If

    If Not NameExists(oldName) Then
        RenameOne = "  " & oldName & " -> " & newName & _
                    ": SKIPPED (old name not found)" & vbCrLf
        Exit Function
    End If

    Dim refersTo As String
    refersTo = ThisWorkbook.Names(oldName).refersTo

    ' Get the cell so we can rewrite the label in col B of the same row
    Dim targetCell As Range
    On Error Resume Next
    Set targetCell = ThisWorkbook.Names(oldName).refersToRange
    On Error GoTo 0

    ThisWorkbook.Names(oldName).Delete
    ThisWorkbook.Names.Add Name:=newName, refersTo:=refersTo

    If Not targetCell Is Nothing Then
        Dim labelCell As Range
        Set labelCell = targetCell.Worksheet.Cells(targetCell.row, 2)  ' col B
        labelCell.value = newLabel
    End If

    RenameOne = "  " & oldName & " -> " & newName & ": renamed (" & refersTo & ")" & vbCrLf
End Function


' ============================================================
' Walk Plan!Q6:Q20 and rewrite formulas to swap MW->GC.
' Returns a multi-line description of what was changed.
' ============================================================
Private Function RewriteAnchorFormulas() As String
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Plan")

    Dim changedRows As String: changedRows = ""
    Dim alreadyDoneRows As Long: alreadyDoneRows = 0
    Dim emptyRows As Long: emptyRows = 0

    Dim r As Long
    For r = 6 To 20
        Dim cell As Range
        Set cell = ws.Cells(r, 17)   ' col Q

        Dim f As String
        f = cell.Formula
        If Len(f) = 0 Then
            emptyRows = emptyRows + 1
        Else
            Dim before As String: before = f
            f = Replace(f, "dataMWRiseTime", "dataGCRiseTime")
            f = Replace(f, "dataMWTransitTime", "dataGCTransitTime")
            f = Replace(f, "dataMWSetTime", "dataGCSetTime")
            f = Replace(f, """mwrise""", """gcrise""")
            f = Replace(f, """mwtransit""", """gctransit""")
            f = Replace(f, """mwset""", """gcset""")

            If f <> before Then
                cell.Formula = f
                If changedRows = "" Then
                    changedRows = CStr(r)
                Else
                    changedRows = changedRows & "," & CStr(r)
                End If
            Else
                alreadyDoneRows = alreadyDoneRows + 1
            End If
        End If
    Next r

    Dim msg As String
    If changedRows <> "" Then
        msg = "  Rewrote rows: " & changedRows & vbCrLf
    End If
    If alreadyDoneRows > 0 Then
        msg = msg & "  Already-GC rows: " & alreadyDoneRows & vbCrLf
    End If
    If emptyRows > 0 Then
        msg = msg & "  Empty rows in Q6:Q20: " & emptyRows & vbCrLf
    End If
    If msg = "" Then msg = "  (no Q-column formulas found)" & vbCrLf
    RewriteAnchorFormulas = msg
End Function


' ============================================================
' Update the "Milky Way times..." section header label in
' Settings if it's still in the old phrasing.
' ============================================================
Private Function RewriteSettingsHeader() As String
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Settings")

    Dim r As Long
    For r = 40 To 80
        Dim v As Variant
        v = ws.Cells(r, 2).value
        If Not IsEmpty(v) Then
            Dim s As String
            s = CStr(v)
            If InStr(s, "Milky Way times") > 0 Then
                ws.Cells(r, 2).value = Replace(s, "Milky Way times", _
                    "GC (Galactic Centre) times")
                RewriteSettingsHeader = "  Updated header at B" & r & vbCrLf
                Exit Function
            End If
        End If
    Next r
    RewriteSettingsHeader = "  (no MW header label found to update)" & vbCrLf
End Function


' ============================================================
' Check whether a workbook-level name already exists.
' ============================================================
Private Function NameExists(ByVal nm As String) As Boolean
    Dim n As Name
    On Error Resume Next
    Set n = ThisWorkbook.Names(nm)
    On Error GoTo 0
    NameExists = Not (n Is Nothing)
End Function
