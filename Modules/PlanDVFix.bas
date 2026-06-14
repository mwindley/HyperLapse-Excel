Attribute VB_Name = "PlanDVFix"
' ============================================================
' HyperLapse Cart -- One-shot Plan-sheet data-validation fix.
'
' The Plan sheet was copied from a standalone prototype and carries
' two conflicting generations of data validation. This macro corrects
' the gimbal-plan dropdowns IN PLACE -- no new sheet, so every formula,
' named range, conditional format, and worksheet code-behind (the
' buttons, AddPlanRowFromLog, etc.) stays intact. Idempotent: safe to
' re-run; it sets each target column to a known-good state regardless
' of what was there.
'
' Public entry: FixPlanValidations
'
' Scope (rows 6..60, the gimbal-plan authoring block):
'   Col T (Target):   set list = sun, moon, gc, + event words sunset/
'                     sunrise/moonrise/moonset/gcrise/gcset  (allow blank = a marker
'                     Move that uses the Ry/Rp ref pose). This REPLACES
'                     the wrong rate list the prototype left on T.
'   Col S (Action):   reset list = Pan Follow, Lock, Move, Track,
'                     Track-yaw, END. Overwriting the whole range clears
'                     the prototype "rise,mid,end" duplicate that
'                     overlapped S.
'   Col Q (Fires-at): remove validation entirely -- Q is a COMPUTED
'                     value; the old dropdown is dead prototype cruft.
'
' Deliberately NOT touched:
'   Col N (anchor type WP/TIME/ASTRO), Col U (Rate), Col Z (Ease) --
'   already-correct production lists.
'   Col O (anchor-ref), Col P, Col C -- left as-is. If their dropdowns
'   also need review, that's a separate, explicit decision (this macro
'   only fixes the three confirmed problems).
'
' Method note: rather than try to delete one of two overlapping
' validations by guessing which generation it is, this clears the
' validation on each target column outright and re-adds the correct
' one. Last-write-wins, no ambiguity, can't half-clobber a good list.
' ============================================================
Option Explicit

Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_LAST_ROW  As Long = 60

' Gimbal-plan columns (mirror PlanPush.bas COL_* constants)
' MIDDLE columns resolved by header name (PlanCols.ResolveMiddleCols).
Private COL_FIRES_AT As Long
Private COL_ACTION   As Long
Private COL_TARGET   As Long

Public Sub FixPlanValidations()
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Plan")
    Dim cols As Object: Set cols = PlanCols.ResolveMiddleCols(ws)
    If cols Is Nothing Then Exit Sub
    COL_ACTION = cols("action"): COL_TARGET = cols("target")

    Dim r1 As Long, r2 As Long
    r1 = PLAN_FIRST_ROW: r2 = PLAN_LAST_ROW

    ' Reorder-safe: clear ALL data validations across the MIDDLE block first
    ' (removes stale ranges anchored to old column letters - e.g. a Target
    ' list bleeding onto the Dir column), then reapply each list to its
    ' header-resolved column. Free-entry / computed columns get no dropdown.
    Dim cFirst As Long, cLast As Long
    cFirst = cols("step"): cLast = cols("note")
    ClearValidation ws.Range(ws.Cells(r1, cFirst), ws.Cells(r2, cLast))

    ' dropdown columns -> their lists, by resolved position
    SetListValidation ColRange(ws, cols("anchortype"), r1, r2), "WP,TIME,ASTRO"
    SetListSuggestion ColRange(ws, cols("anchorref"), r1, r2), _
                      "sunset,sunrise,moonrise,moonset,gcrise,gctransit,gcset"
    SetListValidation ColRange(ws, cols("action"), r1, r2), _
                      "Pan Follow,Lock,Move,Track,Track-yaw,END"
    SetListValidation ColRange(ws, cols("target"), r1, r2), _
                      "sun,moon,gc,arch_rise,arch_set,sunset,sunrise,moonrise,moonset,gcrise,gcset"
    SetListValidation ColRange(ws, cols("dir(cw/ccw)"), r1, r2), "CW,CCW"
    SetListValidation ColRange(ws, cols("panspeed"), r1, r2), _
                      "Slow,Mid,Fast"

    MsgBox "Plan validations rebuilt for current column order (rows " & r1 & "-" & r2 & ")." & vbCrLf & _
           "Lists: Anchor type, Action, Target, Dir (CW/CCW), Pan Speed." & vbCrLf & _
           "Suggest (non-binding): Anchor ref = astro events." & vbCrLf & _
           "Cleared on: Offset, Fires-at, Total-dur, Ry, Rp, dyaw, dpitch, Move t, Note.", _
           vbInformation, "FixPlanValidations"
    Exit Sub

ErrHandler:
    MsgBox "Error in FixPlanValidations:" & vbCrLf & vbCrLf & Err.Description, _
           vbCritical, "FixPlanValidations"
End Sub

Private Function ColRange(ByVal ws As Worksheet, ByVal col As Long, _
                          ByVal r1 As Long, ByVal r2 As Long) As Range
    Set ColRange = ws.Range(ws.Cells(r1, col), ws.Cells(r2, col))
End Function

Private Sub SetListValidation(ByVal rng As Range, ByVal listCsv As String)
    With rng.Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, _
             Operator:=xlBetween, Formula1:=listCsv
        .IgnoreBlank = True
        .InCellDropdown = True
        .ShowError = True
    End With
End Sub

' Non-binding dropdown: shows the list as a quick-pick but does NOT reject
' other entries. Used on Anchor ref, whose valid value depends on Anchor
' type (WP name / clock / astro event) -- the astro names are offered as a
' convenience while clock/WP refs are still typed freely.
Private Sub SetListSuggestion(ByVal rng As Range, ByVal listCsv As String)
    With rng.Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertInformation, _
             Operator:=xlBetween, Formula1:=listCsv
        .IgnoreBlank = True
        .InCellDropdown = True
        .ShowError = False
    End With
End Sub

Private Sub ClearValidation(ByVal rng As Range)
    rng.Validation.Delete
End Sub
