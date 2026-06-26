Attribute VB_Name = "PanoSheet"
' HyperLapse - PANO sheet builder.
'
' Lays out the PANO worksheet: two pano CONFIG BLOCKS (landscape + portrait),
' each a self-contained "manual with formula" definition. The operator TYPES
' the design inputs (lens label, focal, shots, subject span, edge framing, Tv,
' slew, settle); FORMULAS derive the contract values the rest of the workbook
' reads (FOV, step, overlap, the 8 offset cells, cadence). Designed ONCE per
' lens then left stable - nobody re-derives a pano config in the field.
'
' The lens label is INFORMATIONAL ONLY (no logic) - it rides into plan view so
' the operator gets the "oh, that's the 14mm config" moment during checks. It
' does not enforce which lens is mounted (grab the 16mm tonight if you like;
' if the 14mm config is wrong for it, that is an operator problem caught by eye).
'
' Offsets are a FIXED MAX of 8 cells (unused blank when shots<8) so the rest of
' Excel references a stable range regardless of shot count.
'
' Named ranges (the contract):
'   panoL_*  landscape block   panoP_*  portrait block
'   *_lens *_focal *_orient *_shots *_rows *_span *_edge *_tv *_slew *_settle (inputs)
'   *_fov *_vfov *_rowstep *_step *_overlap *_overlapPct *_coverage *_cadence  (outputs)
'   *_offsets (the 8-cell offset row)
'
' Run BuildPanoSheet once (or after changing the layout). The renderer button
' (RenderPanoPlanner) reads these same cells for the exploration image.

Option Explicit

Private Const SHEET_NAME As String = "PANO"
Private Const MAX_SHOTS As Long = 8
Private Const FF_LONG As String = "36"      ' full-frame long edge mm
Private Const FF_SHORT As String = "24"     ' full-frame short edge mm
Private Const POST_SHUTTER_MS As String = "500"
Private Const SLEW_MIN_MS As String = "500"

Public Sub BuildPanoSheet()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(SHEET_NAME)
    On Error GoTo 0
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add
        ws.Name = SHEET_NAME
    End If

    Application.ScreenUpdating = False
    ws.Cells.Clear
    ClearPanoNames

    ws.Range("A1").value = "Pano configs"
    ws.Range("A1").Font.Bold = True
    ws.Range("A1").Font.Size = 14
    ws.Range("A2").value = "Design once per lens. Type the inputs (blue); formulas derive the contract the rest of the workbook reads. " _
        & "Run the planner button to see edges/overlap/buckets/final-video before committing."

    ' Two blocks side by side. Each offset row is 8 cells wide starting at the
    ' value column, so the blocks must be >=10 columns apart or landscape's
    ' offsets (C..J) collide with portrait. Landscape value=C (offsets C..J);
    ' portrait value=M (offsets M..T) - clear gap.
    BuildBlock ws, "L", "PanoCentre", "landscape", 4, 1, "B", "C"
    BuildBlock ws, "P", "PanoCycle", "landscape", 4, 2, "L", "M"

    ' Shared planner inputs (final-video cost) - read by the renderer, not part
    ' of the per-block contract. Placed below the blocks.
    ws.Range("B26").value = "Planner: final-video cost (shared inputs)"
    ws.Range("B26").Font.Bold = True
    WriteInput ws, 27, "B", "C", "Shoot duration (hr)", "12", "pano_dur_hr", False
    WriteInput ws, 28, "B", "C", "Playback FPS", "60", "pano_fps", False

    ' Column widths
    ws.Columns("A").ColumnWidth = 2
    ws.Columns("B").ColumnWidth = 20
    ws.Columns("C").ColumnWidth = 12
    ws.Columns("K").ColumnWidth = 2
    ws.Columns("L").ColumnWidth = 20
    ws.Columns("M").ColumnWidth = 12

    Application.ScreenUpdating = True
    ws.Activate
    ws.Range("A1").Select
    MsgBox "PANO sheet built. Two config blocks (landscape + portrait), manual with formula." & vbCrLf & _
           "Type the blue inputs; the offsets/cadence/overlap fill automatically. Lens label is informational.", _
           vbInformation, "PANO"
End Sub

' Build one config block. pfx = "L"/"P" (name prefix), orientDefault label,
' shotsDefault, lblCol = label column letter, valCol = value column letter.
Private Sub BuildBlock(ws As Worksheet, ByVal pfx As String, ByVal blockTitle As String, _
                       ByVal orientDefault As String, ByVal shotsDefault As Long, _
                       ByVal rowsDefault As Long, ByVal lblCol As String, ByVal valCol As String)
    Dim r As Long: r = 4
    Dim nm As String: nm = "pano" & pfx & "_"
    Dim vc As String: vc = valCol

    ws.Range(lblCol & r).value = blockTitle & " pano config"
    ws.Range(lblCol & r).Font.Bold = True
    r = r + 1

    ' ---- typed inputs (blue) ----
    r = WriteInput(ws, r, lblCol, vc, "Lens label", IIf(pfx = "L", "Sigma 14mm", "Sigma 14mm"), nm & "lens", True)
    r = WriteInput(ws, r, lblCol, vc, "Orientation", orientDefault, nm & "orient", True)
    r = WriteInput(ws, r, lblCol, vc, "Focal length (mm)", "14", nm & "focal", False)
    r = WriteInput(ws, r, lblCol, vc, "Yaw columns (shots)", CStr(shotsDefault), nm & "shots", False)
    r = WriteInput(ws, r, lblCol, vc, "Pitch rows (1=Centre, 2=Cycle)", CStr(rowsDefault), nm & "rows", False)
    r = WriteInput(ws, r, lblCol, vc, "Subject span (deg)", "180", nm & "span", False)
    r = WriteInput(ws, r, lblCol, vc, "Edge framing / side (deg)", "40", nm & "edge", False)
    r = WriteInput(ws, r, lblCol, vc, "Exposure Tv (s)", "20", nm & "tv", False)
    r = WriteInput(ws, r, lblCol, vc, "Slew rate (deg/s)", "20", nm & "slew", False)
    r = WriteInput(ws, r, lblCol, vc, "Settle (ms)", "800", nm & "settle", False)

    r = r + 1
    ws.Range(lblCol & r).value = "--- derived (contract) ---"
    ws.Range(lblCol & r).Font.Italic = True
    r = r + 1

    ' ---- formula outputs ----
    Dim cFocal As String: cFocal = vc & RowOfName(ws, nm & "focal")
    Dim cOrient As String: cOrient = vc & RowOfName(ws, nm & "orient")
    Dim cShots As String: cShots = vc & RowOfName(ws, nm & "shots")
    Dim cSpan As String: cSpan = vc & RowOfName(ws, nm & "span")
    Dim cEdge As String: cEdge = vc & RowOfName(ws, nm & "edge")
    Dim cTv As String: cTv = vc & RowOfName(ws, nm & "tv")
    Dim cSlew As String: cSlew = vc & RowOfName(ws, nm & "slew")
    Dim cSettle As String: cSettle = vc & RowOfName(ws, nm & "settle")

    ' FOV: 2*ATAN(dim/(2*focal)) in degrees; dim depends on orientation.
    ' yaw FOV uses long edge in landscape, short edge in portrait.
    Dim fovF As String
    fovF = "=DEGREES(2*ATAN(IF(LOWER(" & cOrient & ")=""landscape""," & FF_LONG & "," & FF_SHORT & ")/(2*" & cFocal & ")))"
    r = WriteFormula(ws, r, lblCol, vc, "FOV yaw (deg)", fovF, nm & "fov")
    Dim cFov As String: cFov = vc & RowOfName(ws, nm & "fov")

    ' Vertical FOV: the PERPENDICULAR edge to the yaw FOV. Landscape yaw uses the
    ' long edge, so vertical uses the short edge (and vice versa) - dims swapped.
    Dim vfovF As String
    vfovF = "=DEGREES(2*ATAN(IF(LOWER(" & cOrient & ")=""landscape""," & FF_SHORT & "," & FF_LONG & ")/(2*" & cFocal & ")))"
    r = WriteFormula(ws, r, lblCol, vc, "FOV vertical (deg)", vfovF, nm & "vfov")
    Dim cVfov As String: cVfov = vc & RowOfName(ws, nm & "vfov")

    ' Row step = vertical FOV / 2 -> 50% vertical overlap between the two pitch
    ' rows (PanoCycle). On the cart, row 1 pitch = centre + rowstep. rows=1 ignores it.
    r = WriteFormula(ws, r, lblCol, vc, "Row step (deg)", "=" & cVfov & "/2", nm & "rowstep")

    ' coverage needed = span + 2*edge
    r = WriteFormula(ws, r, lblCol, vc, "Coverage needed (deg)", "=" & cSpan & "+2*" & cEdge, nm & "need")
    Dim cNeed As String: cNeed = vc & RowOfName(ws, nm & "need")

    ' step = (need - fov)/(shots-1); guard shots=1 -> 0
    r = WriteFormula(ws, r, lblCol, vc, "Step (deg)", _
        "=IF(" & cShots & "<=1,0,(" & cNeed & "-" & cFov & ")/(" & cShots & "-1))", nm & "step")
    Dim cStep As String: cStep = vc & RowOfName(ws, nm & "step")

    ' overlap = fov - step ; overlap %
    r = WriteFormula(ws, r, lblCol, vc, "Overlap (deg)", "=" & cFov & "-" & cStep, nm & "overlap")
    r = WriteFormula(ws, r, lblCol, vc, "Overlap (%)", "=IF(" & cFov & "=0,0,(" & cFov & "-" & cStep & ")/" & cFov & "*100)", nm & "overlapPct")

    ' actual coverage = fov + (shots-1)*step
    r = WriteFormula(ws, r, lblCol, vc, "Coverage actual (deg)", "=" & cFov & "+(" & cShots & "-1)*" & cStep, nm & "coverage")

    ' ---- offsets: 8 fixed cells, symmetric, blank when index >= shots ----
    r = r + 1
    ws.Range(lblCol & r).value = "Offsets (deg), max 8"
    ws.Range(lblCol & r).Font.Italic = True
    Dim offRow As Long: offRow = r
    Dim i As Long
    For i = 0 To MAX_SHOTS - 1
        Dim oc As String: oc = ws.Cells(offRow, ws.Range(vc & "1").Column + i).Address(False, False)
        ' offset[i] = -(shots-1)*step/2 + i*step  when i < shots else blank
        ws.Cells(offRow, ws.Range(vc & "1").Column + i).Formula = _
            "=IF(" & i & "<" & cShots & ",-(" & cShots & "-1)*" & cStep & "/2+" & i & "*" & cStep & ","""")"
    Next i
    ' name the 8-cell offsets range
    Dim offFirst As String, offLast As String
    offFirst = ws.Cells(offRow, ws.Range(vc & "1").Column).Address(True, True)
    offLast = ws.Cells(offRow, ws.Range(vc & "1").Column + MAX_SHOTS - 1).Address(True, True)
    ThisWorkbook.names.Add Name:=nm & "offsets", refersTo:="=" & SHEET_NAME & "!" & offFirst & ":" & offLast
    r = offRow + 1

    ' ---- cadence (s): photo + non-photo, mirrors firmware ----
    ' photo = shots*Tv
    ' slews: centre->off0, between consecutive offsets, off(last)->centre; each
    '        floored to SLEW_MIN_MS; |swing|/slew*1000 ms.
    ' settle = shots*settle ; post = shots*POST_SHUTTER_MS
    ' Offsets are symmetric so |off0| = |offlast| = (shots-1)*step/2, and each
    ' inter-shot gap = step. So total slew travel = 2*|off0| + (shots-1)*step
    ' BUT each leg is independently floored at SLEW_MIN, so compute leg-wise.
    ' Simplify with the symmetric structure: outer legs = (shots-1)*step/2 each,
    ' inner legs = step each (shots-1 of them).
    Dim cadF As String
    Dim outerLeg As String, innerLeg As String
    outerLeg = "MAX(ABS((" & cShots & "-1)*" & cStep & "/2)/" & cSlew & "*1000," & SLEW_MIN_MS & ")"
    innerLeg = "(" & cShots & "-1)*MAX(ABS(" & cStep & ")/" & cSlew & "*1000," & SLEW_MIN_MS & ")"
    cadF = "=(" & cShots & "*" & cTv & "*1000" _
         & "+2*" & outerLeg _
         & "+" & innerLeg _
         & "+" & cShots & "*" & cSettle _
         & "+" & cShots & "*" & POST_SHUTTER_MS & ")/1000"
    r = WriteFormula(ws, r, lblCol, vc, "Cadence / pano (s)", cadF, nm & "cadence")
    Dim cCad As String: cCad = vc & RowOfName(ws, nm & "cadence")

    ' Final video (s) under THIS block: panos over the night / fps. Uses this
    ' block's own cadence + the shared planner inputs (pano_dur_hr, pano_fps).
    ' Planning estimate only - cadence is "about this", give the interval margin.
    Dim vidF As String
    vidF = "=IF(" & cCad & "=0,0,INT(pano_dur_hr*3600/" & cCad & ")/pano_fps)"
    r = WriteFormula(ws, r, lblCol, vc, "Final video (s)", vidF, nm & "video")

    ' light styling on the block title row
    ws.Range(lblCol & "4").Interior.Color = RGB(220, 230, 245)
End Sub

' Write a typed-input row: label + value, value cell blue+named. asText forces text.
Private Function WriteInput(ws As Worksheet, ByVal r As Long, ByVal lblCol As String, _
                            ByVal vc As String, ByVal label As String, ByVal dflt As String, _
                            ByVal nm As String, ByVal asText As Boolean) As Long
    ws.Range(lblCol & r).value = label
    If asText Then
        ws.Range(vc & r).NumberFormat = "@"
        ws.Range(vc & r).value = dflt
    Else
        ws.Range(vc & r).value = val(dflt)
    End If
    ws.Range(vc & r).Font.Color = RGB(0, 0, 255)
    ws.Range(vc & r).Interior.Color = RGB(255, 255, 204)
    ThisWorkbook.names.Add Name:=nm, refersTo:="=" & SHEET_NAME & "!" & ws.Range(vc & r).Address(True, True)
    WriteInput = r + 1
End Function

' Write a formula-output row: label + formula, named.
Private Function WriteFormula(ws As Worksheet, ByVal r As Long, ByVal lblCol As String, _
                              ByVal vc As String, ByVal label As String, ByVal f As String, _
                              ByVal nm As String) As Long
    ws.Range(lblCol & r).value = label
    ws.Range(vc & r).Formula = f
    ThisWorkbook.names.Add Name:=nm, refersTo:="=" & SHEET_NAME & "!" & ws.Range(vc & r).Address(True, True)
    WriteFormula = r + 1
End Function

' Find the row a named single-cell range sits on (for building dependent formulas).
Private Function RowOfName(ws As Worksheet, ByVal nm As String) As Long
    On Error Resume Next
    RowOfName = ThisWorkbook.names(nm).RefersToRange.row
    On Error GoTo 0
End Function

' Remove all pano* names so a rebuild is clean.
Private Sub ClearPanoNames()
    Dim n As Name
    For Each n In ThisWorkbook.names
        If Left(n.Name, 5) = "panoL" Or Left(n.Name, 5) = "panoP" _
           Or Left(n.Name, 5) = "pano_" Then n.Delete
    Next n
End Sub
