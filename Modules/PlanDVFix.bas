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
'   Col T (Target):   set list = sun, moon, gc  (allow blank = a marker
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
Private Const COL_FIRES_AT As Long = 17   ' Q
Private Const COL_ACTION   As Long = 19   ' S
Private Const COL_TARGET   As Long = 20   ' T

Public Sub FixPlanValidations()
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Plan")

    Dim r1 As Long, r2 As Long
    r1 = PLAN_FIRST_ROW
    r2 = PLAN_LAST_ROW

    ' Col T (Target): astro objects + allow-blank for marker Moves.
    SetListValidation ColRange(ws, COL_TARGET, r1, r2), "sun,moon,gc"

    ' Col S (Action): production list (clears prototype rise,mid,end).
    SetListValidation ColRange(ws, COL_ACTION, r1, r2), _
                      "Pan Follow,Lock,Move,Track,Track-yaw,END"

    ' Col Q (Fires-at): computed -> no dropdown.
    ClearValidation ColRange(ws, COL_FIRES_AT, r1, r2)

    MsgBox "Plan validations fixed (rows " & r1 & "-" & r2 & "):" & vbCrLf & _
           "  T (Target)   = sun, moon, gc  (+ blank for marker Moves)" & vbCrLf & _
           "  S (Action)   = reset; prototype rise/mid/end duplicate removed" & vbCrLf & _
           "  Q (Fires-at) = dropdown removed (computed value)" & vbCrLf & vbCrLf & _
           "Left untouched: N, U, Z (correct); O, P, C (out of scope).", _
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

Private Sub ClearValidation(ByVal rng As Range)
    rng.Validation.Delete
End Sub
