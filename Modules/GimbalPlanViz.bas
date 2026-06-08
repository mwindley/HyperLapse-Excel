Attribute VB_Name = "GimbalPlanViz_v3"
'==============================================================================
' GimbalPlanViz  -  Gimbal Plan VALIDATION chart (native Excel)
'------------------------------------------------------------------------------
' PURPOSE (workfront #11): validate the assembled gimbal Plan before bake.
' It does NOT author geometry and does NOT make up for bad gimbal recon -
' recon is ground truth. This just lets you SEE the plan and catch problems:
'   (a) is the path sane          -> cumulative-yaw x pitch trajectory chart
'   (b) is there a fast yaw        -> big step-to-step yaw jump flagged red
'   (c) near a limit               -> pitch>80 line; cumulative yaw vs +/-450
'
' HOW IT RESOLVES ABSOLUTE POSITIONS (the plan-walk), per Gimbal Plan row:
'   - If Ry (col V) is numeric  -> ABSOLUTE anchor:  yaw  = Ry + dyaw
'                                   (recon'd / astro absolute pose + offset)
'   - else (Move rows, Ry="-")  -> CUMULATIVE pan:   yaw  = prev_yaw + dyaw
'   - pitch follows the same rule using Rp (col W) + dpitch.
'   END / Lock / PF with zero deltas naturally hold the previous pose.
' All as live FORMULAS into a helper sheet "GimbalViz", so editing the Plan and
' recalculating updates the chart. Re-run this macro after ADDING/REMOVING plan
' rows (it re-detects the row count and rebuilds the chart range).
'
' SCOPE NOTE: this v1 places Move rows (cumulative) and rows that carry an
' absolute Ry/Rp (recon'd astro/marker pose). Astro-TYPED plan rows that carry
' only Target+keyframe (no absolute Ry/Rp) would need an AstroTable (target,KF)
' lookup - documented follow-up; put the recon'd absolute into Ry/Rp to place
' them now (recon is ground truth anyway).
'
' Pure ASCII throughout (no degree symbol / Greek) to avoid mojibake.
'==============================================================================
Option Explicit

Private mStage As String   ' diagnostic: last operation attempted (shown on error)

Private Const PLAN_SHEET    As String = "Plan"
Private Const VIZ_SHEET     As String = "GimbalViz"
Private Const HDR_SCAN_MAX  As Long = 12     ' scan first N rows of Plan for the "Step" header
Private Const DEF_FASTYAW   As Double = 90#  ' default fast-yaw threshold (deg/step)
Private Const PITCH_LIMIT   As Double = 80#  ' gimbal struggles past this (deg)
Private Const YAW_CABLE     As Double = 450# ' cumulative yaw cable limit (+/- deg)

Public Sub BuildGimbalPlanViz()
    Dim wsP As Worksheet, wsV As Worksheet
    Dim stepCol As Long, n As Long, r As Long, hdrRow As Long, firstData As Long
    Dim cV As String, cW As String, cX As String, cY As String, cM As String, cS As String

    On Error GoTo fail
    Application.ScreenUpdating = False

    mStage = "open Plan sheet"
    Set wsP = ThisWorkbook.Worksheets(PLAN_SHEET)

    ' 1) Anchor the Gimbal Plan section by finding "Step" anywhere in the top
    '    rows (inlined - no helper, so no chance of a cross-module name clash).
    mStage = "find Step header"
    Dim sr As Long, sc As Long, lastC As Long, hv As Variant
    hdrRow = 0: stepCol = 0
    For sr = 1 To HDR_SCAN_MAX
        lastC = wsP.Cells(sr, wsP.Columns.Count).End(xlToLeft).Column
        If lastC < 1 Then lastC = 1
        For sc = 1 To lastC
            hv = wsP.Cells(sr, sc).Value2
            If Not IsError(hv) Then
                If Trim$(hv & "") = "Step" Then
                    hdrRow = sr: stepCol = sc: Exit For
                End If
            End If
        Next sc
        If stepCol > 0 Then Exit For
    Next sr
    If stepCol = 0 Then Err.Raise 1000, , _
        "Could not find a 'Step' header in the first " & HDR_SCAN_MAX & " rows of the Plan sheet."
    firstData = hdrRow + 1
    ' Fixed section offsets from Step (M): Action=+6(S) Ry=+9(V) Rp=+10(W) dyaw=+11(X) dpitch=+12(Y)
    cM = ColLetter(stepCol)
    cS = ColLetter(stepCol + 6)
    cV = ColLetter(stepCol + 9)
    cW = ColLetter(stepCol + 10)
    cX = ColLetter(stepCol + 11)
    cY = ColLetter(stepCol + 12)

    ' 2) Count gimbal plan rows (Step column non-empty from firstData down).
    '    Bounded + error-tolerant: never overflow the sheet; stop at first blank
    '    or error cell; if 300+ rows have no blank we are on the wrong column.
    mStage = "count plan rows"
    Dim v As Variant
    n = 0
    r = firstData
    Do
        v = wsP.Cells(r, stepCol).Value2
        If IsError(v) Then Exit Do
        If Len(Trim$(v & "")) = 0 Then Exit Do
        n = n + 1: r = r + 1
        If n > 300 Then Err.Raise 1002, , _
            "Step column (col " & cM & ") has 300+ rows from row " & firstData & _
            " with no blank - probably the wrong column. " & _
            "Found 'Step' at " & cM & hdrRow & "; expected the Gimbal Plan section."
    Loop
    If n = 0 Then Err.Raise 1001, , "No Gimbal Plan rows found (Plan!" & cM & firstData & " down is empty)."

    ' 3) Fresh GimbalViz sheet.
    mStage = "prepare GimbalViz sheet"
    Set wsV = EnsureSheet(VIZ_SHEET)
    KillCharts wsV
    wsV.Cells.Clear

    ' 4) Title + tunable inputs (blue = you can change).
    mStage = "write header/inputs"
    With wsV
        .Range("A1").Value = "Gimbal Plan - validation"
        .Range("A1").Font.Bold = True: .Range("A1").Font.Size = 13
        .Range("A2").Value = "Cumulative yaw vs pitch. Re-run after adding/removing plan rows."

        .Range("A4").Value = "Fast-yaw threshold (deg/step)"
        .Range("B4").Value = DEF_FASTYAW
        .Range("A5").Value = "Pitch limit (deg)"
        .Range("B5").Value = PITCH_LIMIT
        .Range("A6").Value = "Yaw cable limit (+/- deg)"
        .Range("B6").Value = YAW_CABLE
        .Range("B4:B6").Font.Color = RGB(0, 0, 255)
        .Range("B4:B6").Interior.Color = RGB(255, 255, 204)
        .Range("A4:A6").Font.Italic = True

        ' Live summary (computed below once data range known).
        .Range("A8").Value = "Max |cumulative yaw| (deg)"
        .Range("A9").Value = "Yaw cable headroom (deg)"
        .Range("A10").Value = "Max pitch (deg)"
        .Range("A11").Value = "Fast-yaw steps flagged"
        .Range("A8:A11").Font.Italic = True
    End With

    ' 5) Trajectory table. Headers on row 14, data 15..(15+n-1).
    Dim h As Long: h = 14
    Dim d0 As Long: d0 = h + 1
    Dim d1 As Long: d1 = d0 + n - 1
    With wsV
        .Cells(h, 1).Value = "Step"
        .Cells(h, 2).Value = "Action"
        .Cells(h, 3).Value = "Cum yaw (deg)"
        .Cells(h, 4).Value = "Pitch (deg)"
        .Cells(h, 5).Value = "Yaw step (deg)"
        .Cells(h, 6).Value = "Fast?"
        .Cells(h, 7).Value = "Fast pitch"     ' red-series Y (NA when not fast)
        .Range(.Cells(h, 1), .Cells(h, 7)).Font.Bold = True
        .Range(.Cells(h, 1), .Cells(h, 7)).Borders(xlEdgeBottom).LineStyle = xlContinuous
    End With

    ' 6) Write live formulas (one table row per plan row).
    mStage = "write trajectory formulas"
    Dim i As Long, pr As Long, vr As Long
    For i = 0 To n - 1
        pr = firstData + i           ' Plan data row
        vr = d0 + i                  ' Viz table row
        wsV.Cells(vr, 1).Formula = "=" & PLAN_SHEET & "!" & cM & pr           ' Step
        wsV.Cells(vr, 2).Formula = "=" & PLAN_SHEET & "!" & cS & pr           ' Action
        ' Cum yaw: absolute anchor (Ry numeric) else previous + dyaw
        If i = 0 Then
            wsV.Cells(vr, 3).Formula = _
                "=IF(ISNUMBER(" & PLAN_SHEET & "!" & cV & pr & ")," & PLAN_SHEET & "!" & cV & pr & _
                ",0)+IFERROR(VALUE(" & PLAN_SHEET & "!" & cX & pr & "),0)"
            wsV.Cells(vr, 4).Formula = _
                "=IF(ISNUMBER(" & PLAN_SHEET & "!" & cW & pr & ")," & PLAN_SHEET & "!" & cW & pr & _
                ",0)+IFERROR(VALUE(" & PLAN_SHEET & "!" & cY & pr & "),0)"
            wsV.Cells(vr, 5).Value = 0                                         ' first: no prior, no jump
        Else
            wsV.Cells(vr, 3).Formula = _
                "=IF(ISNUMBER(" & PLAN_SHEET & "!" & cV & pr & ")," & PLAN_SHEET & "!" & cV & pr & _
                ",C" & (vr - 1) & ")+IFERROR(VALUE(" & PLAN_SHEET & "!" & cX & pr & "),0)"
            wsV.Cells(vr, 4).Formula = _
                "=IF(ISNUMBER(" & PLAN_SHEET & "!" & cW & pr & ")," & PLAN_SHEET & "!" & cW & pr & _
                ",D" & (vr - 1) & ")+IFERROR(VALUE(" & PLAN_SHEET & "!" & cY & pr & "),0)"
            wsV.Cells(vr, 5).Formula = "=C" & vr & "-C" & (vr - 1)             ' step-to-step yaw jump
        End If
        wsV.Cells(vr, 6).Formula = "=ABS(E" & vr & ")>$B$4"                    ' Fast?
        wsV.Cells(vr, 7).Formula = "=IF(F" & vr & ",D" & vr & ",NA())"         ' red series Y
    Next i

    ' 7) Pitch-limit reference line (2 points spanning the yaw range) in I:J.
    mStage = "write limit-line helper"
    wsV.Range("I14").Value = "limX": wsV.Range("J14").Value = "limY"
    wsV.Range("I15").Formula = "=MIN(C" & d0 & ":C" & d1 & ")"
    wsV.Range("I16").Formula = "=MAX(C" & d0 & ":C" & d1 & ")"
    wsV.Range("J15").Formula = "=$B$5"
    wsV.Range("J16").Formula = "=$B$5"

    ' 8) Live summary values.
    mStage = "write summary + conditional formats"
    wsV.Range("B8").Formula = "=MAX(ABS(MIN(C" & d0 & ":C" & d1 & ")),ABS(MAX(C" & d0 & ":C" & d1 & ")))"
    wsV.Range("B9").Formula = "=$B$6-B8"
    wsV.Range("B10").Formula = "=MAX(D" & d0 & ":D" & d1 & ")"
    wsV.Range("B11").Formula = "=SUMPRODUCT(--(F" & d0 & ":F" & d1 & "))"
    ' red flags if a limit is breached
    wsV.Range("B9").FormatConditions.Delete
    wsV.Range("B9").FormatConditions.Add Type:=xlCellValue, Operator:=xlLess, Formula1:="=0"
    wsV.Range("B9").FormatConditions(1).Font.Color = RGB(192, 0, 0)
    wsV.Range("B10").FormatConditions.Delete
    wsV.Range("B10").FormatConditions.Add Type:=xlCellValue, Operator:=xlGreater, Formula1:="=$B$5"
    wsV.Range("B10").FormatConditions(1).Font.Color = RGB(192, 0, 0)
    wsV.Range("B11").FormatConditions.Delete
    wsV.Range("B11").FormatConditions.Add Type:=xlCellValue, Operator:=xlGreater, Formula1:="=0"
    wsV.Range("B11").FormatConditions(1).Font.Color = RGB(192, 0, 0)

    wsV.Columns("A").ColumnWidth = 28
    wsV.Columns("B:G").ColumnWidth = 13

    ' 9) Build the chart.
    mStage = "build chart"
    BuildChart wsV, d0, d1

    Application.ScreenUpdating = True
    wsV.Activate: wsV.Range("A1").Select
    MsgBox "Gimbal Plan viz built: " & n & " steps." & vbCrLf & _
           "Path = cumulative yaw vs pitch; red dots = fast yaw (> " & DEF_FASTYAW & " deg/step);" & vbCrLf & _
           "dashed line = pitch limit " & PITCH_LIMIT & " deg. Check the summary block (A8:B11).", _
           vbInformation, "GimbalViz"
    Exit Sub
fail:
    Application.ScreenUpdating = True
    MsgBox "GimbalPlanViz error " & Err.Number & " at stage: [" & mStage & "]" & vbCrLf & _
           Err.Description, vbExclamation
End Sub

'------------------------------------------------------------------------------
Private Sub BuildChart(ws As Worksheet, d0 As Long, d1 As Long)
    Dim co As ChartObject, ch As Chart, s As Series
    mStage = "chart: add object"
    Set co = ws.ChartObjects.Add(Left:=ws.Range("I2").Left, Top:=ws.Range("I2").Top, _
                                 Width:=560, Height:=360)
    co.Name = "GimbalPlanChart"
    Set ch = co.Chart
    ch.ChartType = xlXYScatterLines

    ' Series 1: the path (cum yaw X, pitch Y) - line + circle markers
    mStage = "chart: path series"
    Set s = ch.SeriesCollection.NewSeries
    s.Name = "Path"
    s.XValues = ws.Range("C" & d0 & ":C" & d1)
    s.Values = ws.Range("D" & d0 & ":D" & d1)
    s.MarkerStyle = xlMarkerStyleCircle: s.MarkerSize = 5
    s.MarkerBackgroundColor = RGB(50, 102, 173)
    s.MarkerForegroundColor = RGB(50, 102, 173)
    s.Border.Color = RGB(50, 102, 173)
    s.Border.LineStyle = xlContinuous: s.Border.Weight = xlMedium

    ' Series 2: fast-yaw points (red markers, no connecting line)
    mStage = "chart: fast series"
    Set s = ch.SeriesCollection.NewSeries
    s.Name = "Fast yaw"
    s.XValues = ws.Range("C" & d0 & ":C" & d1)
    s.Values = ws.Range("G" & d0 & ":G" & d1)   ' NA() except fast rows
    s.MarkerStyle = xlMarkerStyleCircle: s.MarkerSize = 9
    s.MarkerBackgroundColor = RGB(220, 30, 30)
    s.MarkerForegroundColor = RGB(220, 30, 30)
    s.Border.LineStyle = xlNone

    ' Series 3: pitch-limit line (dashed grey, no markers)
    mStage = "chart: limit series"
    Set s = ch.SeriesCollection.NewSeries
    s.Name = "Pitch limit"
    s.XValues = ws.Range("I15:I16")
    s.Values = ws.Range("J15:J16")
    s.MarkerStyle = xlNone
    s.Border.Color = RGB(140, 140, 140)
    s.Border.LineStyle = xlDash

    mStage = "chart: titles + axes"
    ch.HasTitle = True
    ch.ChartTitle.Text = "Gimbal Plan - validation (cumulative yaw vs pitch)"
    With ch.Axes(xlValue)
        .HasTitle = True: .AxisTitle.Text = "Pitch (deg)"
        .MinimumScale = 0: .MajorUnit = 10   ' max auto-fits so a >80 breach stays visible
    End With
    With ch.Axes(xlCategory)
        .HasTitle = True: .AxisTitle.Text = "Cumulative yaw (deg)"
    End With
    ch.HasLegend = True
End Sub

'------------------------------------------------------------------------------
Private Function ColLetter(ByVal n As Long) As String
    Dim s As String, m As Long
    Do While n > 0
        m = (n - 1) Mod 26
        s = Chr$(65 + m) & s
        n = (n - 1) \ 26
    Loop
    ColLetter = s
End Function

Private Function EnsureSheet(nm As String) As Worksheet
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(nm)
    On Error GoTo 0
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        ws.Name = nm
    End If
    Set EnsureSheet = ws
End Function

Private Sub KillCharts(ws As Worksheet)
    Do While ws.ChartObjects.Count > 0
        ws.ChartObjects(1).Delete
    Loop
End Sub
