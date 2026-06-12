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
    Dim cols As Object
    Dim cV As String, cW As String, cx As String, cy As String, cM As String, cS As String, cU As String

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
        lastC = wsP.Cells(sr, wsP.Columns.count).End(xlToLeft).Column
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
    ' Resolve MIDDLE columns by header name (shared PlanCols resolver) so a
    ' column reorder in Excel cannot break this module - matches the push/
    ' cable/chart modules. stepCol (from the scan above) = cols("step").
    Set cols = PlanCols.ResolveMiddleCols(wsP)
    If cols Is Nothing Then Err.Raise 1002, , "MIDDLE header resolve failed (renamed/missing header)."
    cM = ColLetter(stepCol)
    cS = ColLetter(cols("action"))
    cV = ColLetter(cols("ry"))
    cW = ColLetter(cols("rp"))
    cx = ColLetter(cols("dyaw"))
    cy = ColLetter(cols("dpitch"))
    cU = ColLetter(cols("dir(cw/ccw)"))      ' Dir

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
        .Range("A1").value = "Gimbal Plan - validation"
        .Range("A1").Font.Bold = True: .Range("A1").Font.Size = 13
        .Range("A2").value = "Cumulative yaw vs pitch. Re-run after adding/removing plan rows."

        .Range("A4").value = "Fast-yaw threshold (deg/step)"
        .Range("B4").value = DEF_FASTYAW
        .Range("A5").value = "Pitch limit (deg)"
        .Range("B5").value = PITCH_LIMIT
        .Range("A6").value = "Yaw cable limit (+/- deg)"
        .Range("B6").value = YAW_CABLE
        .Range("B4:B6").Font.Color = RGB(0, 0, 255)
        .Range("B4:B6").Interior.Color = RGB(255, 255, 204)
        .Range("A4:A6").Font.Italic = True

        ' Live summary (computed below once data range known).
        .Range("A8").value = "Max |cumulative yaw| (deg)"
        .Range("A9").value = "Yaw cable headroom (deg)"
        .Range("A10").value = "Max pitch (deg)"
        .Range("A11").value = "Fast-yaw steps flagged"
        .Range("A8:A11").Font.Italic = True
    End With

    ' 5) Trajectory table. Headers on row 14, data 15..(15+n-1).
    Dim h As Long: h = 14
    Dim d0 As Long: d0 = h + 1
    Dim d1 As Long: d1 = d0 + n - 1
    With wsV
        .Cells(h, 1).value = "Step"
        .Cells(h, 2).value = "Action"
        .Cells(h, 3).value = "Cum yaw (deg)"
        .Cells(h, 4).value = "Pitch (deg)"
        .Cells(h, 5).value = "Yaw step (deg)"
        .Cells(h, 6).value = "Fast?"
        .Cells(h, 7).value = "Fast pitch"     ' red-series Y (NA when not fast)
        .Cells(h, 8).value = "Slow Y"          ' speed-band series: pitch when Pan Speed=Slow else NA
        .Cells(h, 9).value = "Mid Y"           ' pitch when Pan Speed=Mid else NA
        .Cells(h, 10).value = "Fast Y"         ' pitch when Pan Speed=Fast else NA
        .Cells(h, 16).value = "Sun Y"          ' track-object series: pitch when Track sun else NA
        .Cells(h, 17).value = "Moon Y"         ' pitch when Track moon else NA
        .Cells(h, 18).value = "GC Y"           ' pitch when Track gc else NA
        .Cells(h, 12).value = "Astro yaw"     ' internal: astro base @ BuildPlan
        .Cells(h, 13).value = "Astro pitch"   ' internal: astro base @ BuildPlan
        .Cells(h, 14).value = "Aim"           ' internal: absolute aim (base+dyaw)
        .Cells(h, 15).value = "Short"         ' internal: shortest Dir (CW/CCW)
        .Range(.Cells(h, 1), .Cells(h, 7)).Font.Bold = True
        .Range(.Cells(h, 1), .Cells(h, 7)).Borders(xlEdgeBottom).LineStyle = xlContinuous
    End With

    ' 6) Write live formulas (one table row per plan row).
    ' Heal the order-fragile static Fires-at formula (header-resolved cols)
    ' before reading fire times below.
    mStage = "rebuild Fires-at"
    RebuildFiresAt wsP, cols, firstData, n

    mStage = "write trajectory formulas"
    Dim i As Long, pr As Long, vr As Long
    Dim dq As String: dq = Chr(34)        ' double-quote for in-formula strings
    For i = 0 To n - 1
        pr = firstData + i           ' Plan data row
        vr = d0 + i                  ' Viz table row
        wsV.Cells(vr, 1).Formula = "=" & PLAN_SHEET & "!" & cM & pr           ' Step
        wsV.Cells(vr, 2).Formula = "=" & PLAN_SHEET & "!" & cS & pr           ' Action
        ' Astro base (truthful by construction): same EvalAstro + expected
        ' heading the push uses, written as VALUES to L/M. Blank for non-astro
        ' rows so the cum formula falls back to Ry/relative. Refreshes on
        ' BuildPlan; live tweaks (dyaw, Ry, Pan Speed) stay live formulas.
        Dim abY As Double, abP As Double
        If AstroBaseForRow(wsP, pr, cols, abY, abP) Then
            wsV.Cells(vr, 12).value = abY
            wsV.Cells(vr, 13).value = abP
            LogEvent "VIZ", "row " & pr & " (viz " & vr & ") ASTRO base yaw=" & Format(abY, "0.0") & " pitch=" & Format(abP, "0.0") & " -> wrote L" & vr & "/M" & vr
        Else
            wsV.Cells(vr, 12).value = ""
            wsV.Cells(vr, 13).value = ""
            LogEvent "VIZ", "row " & pr & " (viz " & vr & ") not-astro/False -> L" & vr & "/M" & vr & " blank"
        End If

        ' Aim (N): absolute target = astro base L (or marker Ry) + dyaw. Blank
        ' when neither is present -> a relative (Pan Follow) leg. Directed swing
        ' and the Shortest hint both read this.
        wsV.Cells(vr, 14).Formula = _
            "=IF(OR(ISNUMBER(L" & vr & "),ISNUMBER(" & PLAN_SHEET & "!" & cV & pr & "))," _
            & "IF(ISNUMBER(L" & vr & "),L" & vr & "," & PLAN_SHEET & "!" & cV & pr & ")+IFERROR(VALUE(" & PLAN_SHEET & "!" & cx & pr & "),0)," _
            & dq & dq & ")"

        ' Cum yaw (C): DIRECTED + UNWRAPPED. An absolute leg winds from the
        ' previous cum to the Aim the Dir way (CW = +, CCW = -, the long way if
        ' Dir says so); a relative leg just adds dyaw. Blank Dir defaults to the
        ' shortest path (and is red-flagged). Cumulative (not wrapped to +/-180)
        ' so the +/-450 cable limit is meaningful. prev = 0 first leg else C-1.
        Dim pv As String
        If i = 0 Then pv = "0" Else pv = "C" & (vr - 1)
        wsV.Cells(vr, 3).Formula = _
            "=IF(N" & vr & "=" & dq & dq & "," & pv & "+IFERROR(VALUE(" & PLAN_SHEET & "!" & cx & pr & "),0)," _
            & pv & "+MOD(N" & vr & "-" & pv & ",360)-IF(OR(" & PLAN_SHEET & "!" & cU & pr & "=" & dq & "CCW" & dq _
            & ",AND(" & PLAN_SHEET & "!" & cU & pr & "<>" & dq & "CW" & dq & ",MOD(N" & vr & "-" & pv & ",360)>180)),360,0))"
        ' Shortest (O): which Dir is the short path (drives the not-shortest paint).
        wsV.Cells(vr, 15).Formula = _
            "=IF(N" & vr & "=" & dq & dq & "," & dq & dq & ",IF(MOD(N" & vr & "-" & pv & ",360)<=180," & dq & "CW" & dq & "," & dq & "CCW" & dq & "))"

        ' Pitch (D): unchanged - astro M (or marker Rp) else carry; +dpitch.
        If i = 0 Then
            wsV.Cells(vr, 4).Formula = _
                "=IF(ISNUMBER(M" & vr & "),M" & vr & ",IF(ISNUMBER(" & PLAN_SHEET & "!" & cW & pr & ")," & PLAN_SHEET & "!" & cW & pr & _
                ",0))+IFERROR(VALUE(" & PLAN_SHEET & "!" & cy & pr & "),0)"
            wsV.Cells(vr, 5).value = 0
        Else
            wsV.Cells(vr, 4).Formula = _
                "=IF(ISNUMBER(M" & vr & "),M" & vr & ",IF(ISNUMBER(" & PLAN_SHEET & "!" & cW & pr & ")," & PLAN_SHEET & "!" & cW & pr & _
                ",D" & (vr - 1) & "))+IFERROR(VALUE(" & PLAN_SHEET & "!" & cy & pr & "),0)"
            wsV.Cells(vr, 5).Formula = "=C" & vr & "-C" & (vr - 1)
        End If
        wsV.Cells(vr, 6).Formula = "=ABS(E" & vr & ")>$B$4"                    ' Fast?
        wsV.Cells(vr, 7).Formula = "=IF(F" & vr & ",D" & vr & ",NA())"         ' red series Y
    Next i

    ' 6b) Pan Time (Plan col AB) on EVERY gimbal row + "< For" validation.
    '     Pan Time = swing (GimbalViz Yaw step) / rate (Pan Speed) in minutes -
    '     the get-there time. Written here so it lives on all rows (the template
    '     only seeded one) and reads the now-astro-aware swing. Colour flags fit:
    '       red   = Pan Time >= Actual (does NOT fit the real window - Nok)
    '       amber = 60-100% of Actual (eats most of the window)
    '     Validates against Actual (derived window), not Stay (operator intent).
    mStage = "write Pan Time + validation on Plan"
    Dim cO As String, cZ As String, cAB As String
    Dim cAT As String, cFA As String, cActual As String
    cO = ColLetter(cols("stay(min)"))     ' Stay (min)
    cZ = ColLetter(cols("panspeed"))      ' Pan Speed
    Dim cTgt As String: cTgt = ColLetter(cols("target"))   ' Target (for track-object colour)
    cAB = ColLetter(cols("pantime"))      ' Pan Time
    cAT = ColLetter(cols("anchortype"))   ' Anchor type (next row decides window)
    cFA = ColLetter(cols("firesat"))      ' Fires at
    cActual = ColLetter(cols("actual(mins)")) ' Actual (mins) - derived window
    Dim q As String: q = Chr(34)     ' double-quote for in-formula strings
    For i = 0 To n - 1
        pr = firstData + i
        wsP.Cells(pr, cols("pantime")).Formula = _
            "=IF($" & cZ & pr & "=" & q & q & "," & q & q & _
            ",IFERROR(ABS(INDEX(GimbalViz!$E:$E,MATCH($" & cM & pr & _
            ",GimbalViz!$A:$A,0)))/IF($" & cZ & pr & "=" & q & "Slow" & q & _
            ",3,IF($" & cZ & pr & "=" & q & "Mid" & q & ",6,IF($" & cZ & pr & _
            "=" & q & "Fast" & q & ",12,1)))," & q & q & "))"
        ' Speed-band chart Y values: the pitch (col D) on rows whose Pan Speed
        ' matches each band, NA() elsewhere -> three coloured marker series
        ' (Slow=blue, Mid=green, Fast=orange) so the operator SEES the swing
        ' speed they set per leg. vr = the GimbalViz table row for this plan row.
        Dim vrB As Long: vrB = d0 + i
        wsV.Cells(vrB, 8).Formula = "=IF($" & cZ & pr & "=" & q & "Slow" & q & ",D" & vrB & ",NA())"
        wsV.Cells(vrB, 9).Formula = "=IF($" & cZ & pr & "=" & q & "Mid" & q & ",D" & vrB & ",NA())"
        wsV.Cells(vrB, 10).Formula = "=IF($" & cZ & pr & "=" & q & "Fast" & q & ",D" & vrB & ",NA())"
        ' Track-object chart Y values: the pitch on Track rows, coloured by the
        ' object being tracked (Sun=yellow, Moon=grey, GC=white). Keyed on
        ' Action=Track AND Target; NA() on non-track rows. cS=Action, cTgt=Target.
        wsV.Cells(vrB, 16).Formula = "=IF(AND(LOWER($" & cS & pr & ")=" & q & "track" & q & ",LOWER($" & cTgt & pr & ")=" & q & "sun" & q & "),D" & vrB & ",NA())"
        wsV.Cells(vrB, 17).Formula = "=IF(AND(LOWER($" & cS & pr & ")=" & q & "track" & q & ",LOWER($" & cTgt & pr & ")=" & q & "moon" & q & "),D" & vrB & ",NA())"
        wsV.Cells(vrB, 18).Formula = "=IF(AND(LOWER($" & cS & pr & ")=" & q & "track" & q & ",LOWER($" & cTgt & pr & ")=" & q & "gc" & q & "),D" & vrB & ",NA())"
        ' Actual (mins) = real window. Next GP anchored (Anchor type non-blank)
        ' -> next Fires-at minus this Fires-at; next carries (blank) -> Stay.
        ' Both reduce to the true duration; the operator never types this.
        wsP.Cells(pr, cols("actual(mins)")).Formula = _
            "=IFERROR(IF($" & cAT & (pr + 1) & "<>" & q & q & _
            ",MOD($" & cFA & (pr + 1) & "-$" & cFA & pr & ",1)*1440,$" & cO & pr & ")," & q & q & ")"
    Next i

    ' Conditional formatting on the Pan Time column (mutually exclusive rules).
    Dim ptRng As Range
    Set ptRng = wsP.Range(wsP.Cells(firstData, cols("pantime")), _
                          wsP.Cells(firstData + n - 1, cols("pantime")))
    ptRng.FormatConditions.Delete
    With ptRng.FormatConditions.Add(Type:=xlExpression, _
            Formula1:="=AND(ISNUMBER($" & cAB & firstData & "),$" & cAB & firstData & ">=$" & cActual & firstData & ")")
        .Interior.Color = RGB(255, 150, 150)        ' red - does not fit
    End With
    With ptRng.FormatConditions.Add(Type:=xlExpression, _
            Formula1:="=AND(ISNUMBER($" & cAB & firstData & "),$" & cAB & firstData & ">=0.6*$" & cActual & firstData & ",$" & cAB & firstData & "<$" & cActual & firstData & ")")
        .Interior.Color = RGB(255, 230, 150)        ' amber - eats most of the window
    End With

    ' 7) Pitch-limit reference line (2 points spanning the yaw range) in I:J.
    mStage = "write limit-line helper"
    wsV.Range("I14").value = "limX": wsV.Range("J14").value = "limY"
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

    ' 8b) Dir (CW/CCW): mandatory dropdown + not-shortest paint. Macro-laid
    '     every build (NOT conditional formatting - that fragments when users
    '     insert/copy/drag; a rebuild heals plain fill + validation). Reads the
    '     computed Shortest (col O) so force a recalc first - which also settles
    '     the astro base / cum formulas (the first-paint blank watch item).
    mStage = "Dir validation + not-shortest paint"
    Application.Calculate
    Dim dcell As Range, shrt As String, dirv As String
    For i = 0 To n - 1
        pr = firstData + i
        Set dcell = wsP.Cells(pr, cols("dir(cw/ccw)"))
        dcell.Validation.Delete
        dcell.Validation.Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, Formula1:="CW,CCW"
        shrt = UCase(Trim(CStr(wsV.Cells(d0 + i, 15).value)))     ' Shortest
        dirv = UCase(Trim(CStr(dcell.value)))
        If Len(shrt) = 0 Then
            dcell.Interior.ColorIndex = xlNone                     ' relative leg - Dir N/A
        ElseIf Len(dirv) = 0 Then
            dcell.Interior.Color = RGB(255, 150, 150)              ' red - mandatory, missing
        ElseIf dirv = shrt Then
            dcell.Interior.ColorIndex = xlNone                     ' on the short path - clear
        Else
            dcell.Interior.Color = RGB(255, 220, 130)              ' amber - long way (deliberate)
        End If
    Next i

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
    s.values = ws.Range("D" & d0 & ":D" & d1)
    s.MarkerStyle = xlMarkerStyleCircle: s.MarkerSize = 5
    s.MarkerBackgroundColor = RGB(50, 102, 173)
    s.MarkerForegroundColor = RGB(50, 102, 173)
    s.Border.Color = RGB(50, 102, 173)
    s.Border.LineStyle = xlContinuous: s.Border.Weight = xlMedium

    ' Series 2a/2b/2c: speed-band markers (blue=Slow, green=Mid, orange=Fast),
    ' no connecting line. Each plots pitch only on rows matching that Pan Speed
    ' (NA elsewhere) so the operator sees the swing speed set per leg. Replaces
    ' the old binary red fast-yaw flag (cadence-blind 90 deg/step).
    mStage = "chart: speed-band series"
    Dim bandName(2) As String, bandCol(2) As Long, bandRGB(2) As Long
    bandName(0) = "Slow": bandCol(0) = 8:  bandRGB(0) = RGB(50, 102, 173)   ' blue
    bandName(1) = "Mid":  bandCol(1) = 9:  bandRGB(1) = RGB(60, 160, 90)    ' green
    bandName(2) = "Fast": bandCol(2) = 10: bandRGB(2) = RGB(230, 145, 40)   ' orange
    Dim bi As Long
    For bi = 0 To 2
        Set s = ch.SeriesCollection.NewSeries
        s.Name = bandName(bi)
        s.XValues = ws.Range("C" & d0 & ":C" & d1)
        s.values = ws.Range(ColLetter(bandCol(bi)) & d0 & ":" & ColLetter(bandCol(bi)) & d1)
        s.MarkerStyle = xlMarkerStyleCircle: s.MarkerSize = 8
        s.MarkerBackgroundColor = bandRGB(bi)
        s.MarkerForegroundColor = bandRGB(bi)
        s.Border.LineStyle = xlNone
    Next bi

    ' Series 2d/2e/2f: track-object markers (Sun=yellow, Moon=grey, GC=white),
    ' no connecting line. Pitch on Track rows only, coloured by the object being
    ' tracked. Distinct from the get-there swing bands (blue/green/orange).
    mStage = "chart: track-object series"
    Dim objName(2) As String, objCol(2) As Long, objRGB(2) As Long
    objName(0) = "Sun track":  objCol(0) = 16: objRGB(0) = RGB(255, 200, 40)    ' yellow
    objName(1) = "Moon track": objCol(1) = 17: objRGB(1) = RGB(150, 150, 150)   ' grey
    objName(2) = "GC track":   objCol(2) = 18: objRGB(2) = RGB(245, 245, 245)   ' white
    Dim oi As Long
    For oi = 0 To 2
        Set s = ch.SeriesCollection.NewSeries
        s.Name = objName(oi)
        s.XValues = ws.Range("C" & d0 & ":C" & d1)
        s.values = ws.Range(ColLetter(objCol(oi)) & d0 & ":" & ColLetter(objCol(oi)) & d1)
        s.MarkerStyle = xlMarkerStyleCircle: s.MarkerSize = 8
        s.MarkerBackgroundColor = objRGB(oi)
        s.MarkerForegroundColor = objRGB(oi)
        s.Border.LineStyle = xlNone
    Next oi

    ' Series 3: pitch-limit line (dashed grey, no markers)
    mStage = "chart: limit series"
    Set s = ch.SeriesCollection.NewSeries
    s.Name = "Pitch limit"
    s.XValues = ws.Range("I15:I16")
    s.values = ws.Range("J15:J16")
    s.MarkerStyle = xlNone
    s.Border.Color = RGB(140, 140, 140)
    s.Border.LineStyle = xlDash

    mStage = "chart: titles + axes"
    ch.HasTitle = True
    ch.ChartTitle.tExt = "Gimbal Plan - validation (cumulative yaw vs pitch)"
    With ch.Axes(xlValue)
        .HasTitle = True: .AxisTitle.tExt = "Pitch (deg)"
        .MinimumScale = 0: .MajorUnit = 10   ' max auto-fits so a >80 breach stays visible
    End With
    With ch.Axes(xlCategory)
        .HasTitle = True: .AxisTitle.tExt = "Cumulative yaw (deg)"
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
        Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.count))
        ws.Name = nm
    End If
    Set EnsureSheet = ws
End Function

Private Sub KillCharts(ws As Worksheet)
    Do While ws.ChartObjects.count > 0
        ws.ChartObjects(1).Delete
    Loop
End Sub

'------------------------------------------------------------------------------
' AstroBaseForRow - absolute astro base (yaw,pitch) for a gimbal row, computed
' the SAME way the push does: PlanPush.EvalAstro with the row's expected heading.
' Returns False for non-astro rows so the caller falls back to Ry/relative.
' Fire time = today + Fires-at clock time (day precision is enough for a swing
' INDICATION; sidereal drift ~1 deg/day). Heading = the cart's per-WP
' expected heading where the cart is parked at the fire time (no global
' heading). Undefined position -> blank base, so the plan flags the gap.
'------------------------------------------------------------------------------
' ============================================================
' Rebuild the Fires-at formula on every gimbal row from HEADER-
' RESOLVED columns. Fires-at is a static sheet formula (not the
' header-mapped macros), so a column reorder shifts its hard refs
' out from under it. Re-laying it here with cols("...") letters
' makes it reorder-safe and heals any prior breakage. Logic is
' unchanged: anchor (type/ref) + Offset -> fire time; blank anchor
' carries prev fire-at + prev For. Cart refs ($B/$J) are the fixed
' waypoint block, left literal.
' ============================================================
Private Sub RebuildFiresAt(ByVal wsP As Worksheet, ByVal cols As Object, _
                           ByVal firstData As Long, ByVal n As Long)
    Dim q As String: q = Chr(34)
    Dim cAT As String, cAR As String, cOFF As String, cFOR As String, cFA As String
    cAT = ColLetter(cols("anchortype"))
    cAR = ColLetter(cols("anchorref"))
    cOFF = ColLetter(cols("offset(min)"))
    cFOR = ColLetter(cols("stay(min)"))
    cFA = ColLetter(cols("firesat"))
    Dim i As Long, r As Long
    For i = 0 To n - 1
        r = firstData + i
        wsP.Cells(r, cols("firesat")).Formula = _
            "=IF(" & cAT & r & "=" & q & q & ",IF(ISNUMBER(" & cFA & (r - 1) & ")," & cFA & (r - 1) & _
            "+IFERROR(" & cFOR & (r - 1) & ",0)/1440," & q & q & "),IF(" & cAT & r & "=" & q & "WP" & q & _
            ",INDEX($J$6:$J$20,MATCH(" & cAR & r & ",$B$6:$B$20,0))+IFERROR(" & cOFF & r & ",0)/1440,IF(" & _
            cAT & r & "=" & q & "TIME" & q & ",IF(ISNUMBER(" & cAR & r & "),MOD(" & cAR & r & ",1),IFERROR(TIMEVALUE(" & cAR & r & ")," & q & q & "))+IFERROR(" & _
            cOFF & r & ",0)/1440,IF(" & cAT & r & "=" & q & "ASTRO" & q & ",IF(" & cAR & r & "=" & q & "sunset" & q & _
            ",dataSunsetTime,IF(" & cAR & r & "=" & q & "sunrise" & q & ",dataSunriseTime,IF(" & cAR & r & "=" & q & "moonrise" & q & _
            ",dataMoonriseTime,IF(" & cAR & r & "=" & q & "moonset" & q & ",dataMoonsetTime,IF(" & cAR & r & "=" & q & "gcrise" & q & _
            ",dataGCRiseTime,IF(" & cAR & r & "=" & q & "gctransit" & q & ",dataGCTransitTime,IF(" & cAR & r & "=" & q & "gcset" & q & _
            ",dataGCSetTime," & q & q & ")))))))+IFERROR(" & cOFF & r & ",0)/1440," & q & q & "))))"
    Next i
End Sub

Private Function AstroBaseForRow(ByVal wsP As Worksheet, ByVal rowIdx As Long, _
                                 ByVal cols As Object, _
                                 ByRef baseYaw As Double, ByRef basePitch As Double) As Boolean
    AstroBaseForRow = False
    Dim tgt As String
    tgt = LCase(Trim(CStr(wsP.Cells(rowIdx, cols("target")).value)))   ' Target
    If Len(tgt) = 0 Then Exit Function
    If Not PlanPush.IsAstroTarget(tgt) Then Exit Function

    ' Fire time: today + Fires-at clock time (Step+1).
    Dim rawFire As Variant: rawFire = wsP.Cells(rowIdx, cols("firesat")).value
    Dim fireT As Double
    If IsNumeric(rawFire) Then
        fireT = Utils.DatedFireSerial(CDbl(rawFire), 0#)   ' shoot-dated (shared helper); was Int(Date)+time
    Else
        fireT = Now()
    End If

    ' Heading = the cart's expected heading WHERE IT IS PARKED at the fire time
    ' (cart per-WP heading is the only source - no global/Settings heading). If
    ' the cart position at fireT is unknown, the heading is undefined, so leave
    ' the astro base blank (the plan flags the gap) rather than invent a number.
    Dim eh As Variant: eh = CartHeadingAtTime(wsP, fireT)
    If Not IsNumeric(eh) Then Exit Function
    Dim expHead As Double: expHead = CDbl(eh)

    Dim y As Double, p As Double
    If PlanPush.EvalAstro(tgt, fireT, expHead, y, p) Then
        baseYaw = y: basePitch = p
        AstroBaseForRow = True
    End If
End Function

' Cart heading at a time = the expected heading (cart col H) of the WP the cart
' is parked at when the event fires: the latest cart WP whose Commences <= fireT.
' The cart per-WP expected heading is the ONLY heading source - there is no
' global/Settings heading (no "270"). Returns Empty if no WP qualifies (cart
' position unknown -> caller blanks the row). Cart block B/H/J are fixed columns.
Private Function CartHeadingAtTime(ByVal wsP As Worksheet, ByVal fireT As Double) As Variant
    Const CART_FIRST As Long = 6, CART_LAST As Long = 20
    Const C_WP As Long = 2, C_HEAD As Long = 8, C_COMM As Long = 10
    Dim r As Long, bestT As Double
    bestT = -1
    CartHeadingAtTime = Empty
    For r = CART_FIRST To CART_LAST
        If Len(Trim(CStr(wsP.Cells(r, C_WP).value))) = 0 Then Exit For
        Dim cv As Variant: cv = wsP.Cells(r, C_COMM).value
        If IsNumeric(cv) Then
            Dim cvn As Double: cvn = Utils.DatedFireSerial(CDbl(cv), 0#)   ' shoot-dated (shared helper); was Int(Date)+time
            If cvn <= fireT And cvn >= bestT Then
                Dim hv As Variant: hv = wsP.Cells(r, C_HEAD).value
                If IsNumeric(hv) Then
                    bestT = cvn
                    CartHeadingAtTime = CDbl(hv)
                End If
            End If
        End If
    Next r
End Function
