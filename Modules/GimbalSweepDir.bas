Attribute VB_Name = "GimbalSweepDir"
' HyperLapse - auto-fill gimbal sweep direction (CW/CCW) into Plan col AC.
'
' Computes, per leg GP(i)->GP(i+1), the SHORTEST cart-frame rotation and
' writes "CW" or "CCW" onto the destination GP row, col AC. The plan-view
' renderer (gimbal_planview_v2.py) READS this column literally and never
' recomputes - so an operator override survives.
'
' Model (must match the renderer):
'   cart-frame yaw  cf = (base - heading) + dyaw
'      base = Ry (col V) when numeric  -> earth-frame world anchor
'           = expected_cart_heading    -> chassis-frame (cart-nose offset)
'   leg step = norm180( cf(i+1) - cf(i) ) ;  >=0 -> CW (positive), else CCW
'   heading  = the GP's anchor WP heading (cart section col H, matched by
'              WP id in col B against the GP's Anchor ref in col O).
'
' CW convention = positive cart-frame rotation (increasing yaw), matching
' the renderer's CW (diff forced positive) and cable (+step).
'
' Run: GimbalSweepDir.FillSweepDirections
'   - fills ONLY blank AC cells by default (preserves manual CW/CCW).
'   - to re-auto a leg, clear its AC cell and re-run.
'   - FillSweepDirections True  forces overwrite of all legs.
'
' BUILD-LESSON 12 guard: helpers take args ByVal (the col-zeroing 1004 bug).

Option Explicit

' (DIR_OFFSET removed - columns now resolved by header name via PlanCols.)

Public Sub FillSweepDirections(Optional ByVal forceAll As Boolean = False)
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Worksheets("Plan")

    ' --- resolve columns BY HEADER NAME (reorder-safe). Replaces the old
    ' fixed-offset-from-Step math, which wrote Dir to the wrong column once
    ' the MIDDLE columns were reordered. ---
    Dim cols As Object: Set cols = PlanCols.ResolveMiddleCols(ws)
    If cols Is Nothing Then Exit Sub
    Dim hdrRow As Long, stepCol As Long
    If Not FindStepHeader(ws, hdrRow, stepCol) Then
        MsgBox "Could not find the gimbal 'Step' header on the Plan sheet.", vbExclamation
        Exit Sub
    End If
    Dim colAnchor As Long, colRy As Long, colDyaw As Long, colDir As Long, colAction As Long
    colAnchor = cols("anchorref")
    colRy = cols("ry")
    colDyaw = cols("dyaw")
    colDir = cols("dir(cw/ccw)")
    colAction = cols("action")

    ' --- walk the GP rows, build cf() and remember each row ---
    Dim r As Long, n As Long
    Dim cf() As Double, rowOf() As Long
    ReDim cf(1 To 200): ReDim rowOf(1 To 200)
    r = hdrRow + 1
    Do While Trim$(CStr(ws.Cells(r, stepCol).value)) <> ""
        Dim act As String
        act = UCase$(Trim$(CStr(ws.Cells(r, colAction).value)))   ' Action (by name)
        If act = "END" Then Exit Do

        Dim anchor As String, heading As Double, ryV As Variant, dyaw As Double, base As Double
        anchor = Trim$(CStr(ws.Cells(r, colAnchor).value))
        heading = LookupWPHeading(ws, anchor)
        ryV = ws.Cells(r, colRy).value
        dyaw = SafeNum(ws.Cells(r, colDyaw).value)
        If IsNumeric(ryV) And Trim$(CStr(ryV)) <> "" Then
            base = CDbl(ryV)            ' earth-frame world anchor
        Else
            base = heading              ' chassis-frame (offset from cart nose)
        End If

        n = n + 1
        cf(n) = Norm180((base - heading) + dyaw)
        rowOf(n) = r
        r = r + 1
    Loop

    If n < 2 Then Exit Sub

    ' --- per leg: shortest cart-frame step -> CW/CCW on destination row ---
    Dim i As Long, d As Double, lbl As String, cur As String
    For i = 2 To n
        d = Norm180(cf(i) - cf(i - 1))
        If d >= 0 Then lbl = "CW" Else lbl = "CCW"
        cur = UCase$(Trim$(CStr(ws.Cells(rowOf(i), colDir).value)))
        If forceAll Or cur = "" Then
            ws.Cells(rowOf(i), colDir).value = lbl
        End If
        ' GP1 has no incoming leg -> leave its Dir blank
    Next i

    MsgBox "Sweep directions filled (" & (n - 1) & " legs)." & _
           IIf(forceAll, " [forced]", " [blanks only - overrides kept]"), vbInformation
End Sub

' ---- helpers (all ByVal) ----

Private Function FindStepHeader(ByVal ws As Worksheet, ByRef hdrRow As Long, _
                                ByRef stepCol As Long) As Boolean
    Dim rr As Long, cc As Long
    For rr = 1 To 40
        For cc = 1 To 40
            If Trim$(CStr(ws.Cells(rr, cc).value)) = "Step" Then
                hdrRow = rr: stepCol = cc: FindStepHeader = True: Exit Function
            End If
        Next cc
    Next rr
    FindStepHeader = False
End Function

' WP id (col B) -> heading (col H), searched on the Plan sheet cart section.
Private Function LookupWPHeading(ByVal ws As Worksheet, ByVal wpId As String) As Double
    Dim rr As Long
    LookupWPHeading = 0#
    If wpId = "" Then Exit Function
    For rr = 1 To 200
        If UCase$(Trim$(CStr(ws.Cells(rr, 2).value))) = UCase$(wpId) Then   ' col B
            LookupWPHeading = SafeNum(ws.Cells(rr, 8).value)                ' col H
            Exit Function
        End If
    Next rr
End Function

Private Function Norm180(ByVal a As Double) As Double
    Dim x As Double
    x = a - 360# * Int((a + 180#) / 360#)
    Norm180 = x
End Function

Private Function SafeNum(ByVal v As Variant) As Double
    If IsNumeric(v) And Trim$(CStr(v)) <> "" Then SafeNum = CDbl(v) Else SafeNum = 0#
End Function
