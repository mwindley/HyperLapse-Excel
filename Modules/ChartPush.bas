Attribute VB_Name = "ChartPush"
' ============================================================
' HyperLapse Cart - Execution Chart Author (Day 30, pano overlay Day 35)
'
' Authors the gimbal-plan path as an inner SVG fragment and pushes
' it CHUNKED to the cart at /settings/chartsvg. The cart stores +
' serves it on the Execution screen and only animates the live
' camera icon over it ("Excel authors, Giga moves the icon").
'
' SCOPE:
'   - Move / Pan Follow marker targets: polyline + dots (blue).
'   - FULL astro Track (sun/moon/gc/mw): sampled centre curve (dots).
'   - arch Track-yaw (PanoCycle): the pano overlay - the rows x cols
'     cell dots at the GP-START centre, firing-order arrows, and a
'     "planned sweep" band from the start cluster out to where the
'     leading yaw column reaches at the GP-window END (the cubic's
'     end centre + max offset). Uncluttered: dots + arrows + 1 band.
'     PanoCentre (landscape) is operator-triggered at runtime, not a
'     plan row, so it is not authored here (only the live icon shows).
'
' The pano grid is read from the PANO sheet portrait block
' (panoP_shots = yaw columns, panoP_offsets, panoP_rows, panoP_rowstep)
' - the SAME source PanoConfigPush sends to the cart, so chart and
' cart agree. Grid is variable (rows x cols come from the plan).
'
' COORDINATE CONTRACT (must match the cart, soak-v43):
'   viewBox 0 0 355 90
'   x = (yaw   - yaw_min) / 450 * 355
'   y = 90 - (pitch - 0) / 80  * 90        (pitch 0 bottom .. 80 top)
'   dashed mechanical-limit reminder at pitch 80 (y = 0)
'   sweep band fill uses the cart theme var --xsweep (gray Day /
'   light-red Night); cell dots use --xtext; arrows use --xtext-mute.
'
' Run: PushChartToCart. Honours dataPlanPushDryRun (TRUE = build +
' log the SVG, do not send).
' ============================================================
Option Explicit

Private Const LOG_CATEGORY    As String = "CHARTPUSH"
Private Const PLAN_FIRST_ROW  As Long = 6
Private Const PLAN_MAX_ROWS   As Long = 60

' Plan middle-zone columns (match TrackPlanPush)
' MIDDLE columns resolved by header name (PlanCols.ResolveMiddleCols) at the
' top of PushChartToCart, so a column reorder cannot break the chart push.
Private COL_ACTION As Long
Private COL_TARGET As Long
Private COL_RY     As Long
Private COL_RP     As Long
Private COL_DYAW   As Long
Private COL_DPITCH As Long
Private COL_FIRESAT As Long
Private COL_ACTUAL  As Long

' Astro track sampling: points across a Track GP's window (yaw,pitch path).
Private Const TRACK_NSAMP As Long = 12

' Pano grid cap (matches cart PANO_MAX_PHOTOS).
Private Const PANO_MAXCELL As Long = 8

' Chart contract
Private Const VB_W            As Double = 355
Private Const VB_H            As Double = 90
Private Const YAW_SPAN        As Double = 450
Private Const PITCH_LO        As Double = 0
Private Const PITCH_HI        As Double = 80

Private Const CHUNK_RAW       As Long = 150   ' raw SVG chars per push chunk

Public Sub PushChartToCart()
    LogCH "--- PushChartToCart start" & IIf(ReadDryRunFlag(), " (DRY RUN)", " (REAL PUSH)") & " ---"

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Plan")
    Dim cols As Object: Set cols = PlanCols.ResolveMiddleCols(ws)
    If cols Is Nothing Then Exit Sub                 ' header missing -> abort
    COL_ACTION = cols("action"): COL_TARGET = cols("target")
    COL_RY = cols("ry"): COL_RP = cols("rp")
    COL_DYAW = cols("dyaw"): COL_DPITCH = cols("dpitch")
    COL_FIRESAT = cols("firesat"): COL_ACTUAL = cols("actual(mins)")

    ' Collect Move / Pan Follow marker targets (+ FULL track samples) in plan order.
    Dim yaw() As Double, pit() As Double
    ReDim yaw(0 To PLAN_MAX_ROWS * 16)
    ReDim pit(0 To PLAN_MAX_ROWS * 16)
    Dim n As Long: n = 0

    ' Pano GPs (arch Track-yaw -> PanoCycle): store start + end centre yaw and the
    ' row-0 centre pitch. The grid config (cols/offsets/rows/rowstep) is one shared
    ' portrait block, read once.
    Dim pgStartY() As Double, pgEndY() As Double, pgPitch() As Double
    ReDim pgStartY(0 To PLAN_MAX_ROWS)
    ReDim pgEndY(0 To PLAN_MAX_ROWS)
    ReDim pgPitch(0 To PLAN_MAX_ROWS)
    Dim pgN As Long: pgN = 0
    Dim pCols As Long, pRows As Long
    Dim pRowstep As Double
    Dim pOff(0 To PANO_MAXCELL - 1) As Double
    Dim pCfgOK As Boolean: pCfgOK = False

    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        Dim act As String
        act = UCase(Trim(CStr(ws.Cells(r, COL_ACTION).value)))
        If act = "" Then Exit For
        If act = "END" Then GoTo NextRow

        If act = "MOVE" Or act = "PAN FOLLOW" Then
            Dim tgt As String
            tgt = LCase(Trim(CStr(ws.Cells(r, COL_TARGET).value)))
            ' A real astro target is one of these words; anything else
            ' (blank, "-", em-dash, etc.) is a marker Move -> chartable.
            ' Tested by content (ASCII) to avoid any non-ASCII dash literal.
            If tgt = "sun" Or tgt = "moon" Or tgt = "mw" Or _
               tgt = "arch_rise" Or tgt = "arch_set" Or _
               tgt = "sunrise" Or tgt = "sunset" Then
                LogCH "  NOTE row " & r & ": astro target '" & tgt & "' - skipped (astro charting deferred)"
                GoTo NextRow
            End If
            yaw(n) = SafeNum(ws.Cells(r, COL_RY).value) + SafeNum(ws.Cells(r, COL_DYAW).value)
            pit(n) = SafeNum(ws.Cells(r, COL_RP).value) + SafeNum(ws.Cells(r, COL_DPITCH).value)
            LogCH "  GP point " & n & ": yaw=" & Format(yaw(n), "0.0") & " pitch=" & Format(pit(n), "0.0")
            n = n + 1
        ElseIf act = "TRACK" Or act = "TRACK-YAW" Then
            Dim ttgt As String
            ttgt = LCase(Trim(CStr(ws.Cells(r, COL_TARGET).value)))
            Dim rawF As Variant: rawF = ws.Cells(r, COL_FIRESAT).value
            Dim winV As Variant: winV = ws.Cells(r, COL_ACTUAL).value
            Dim isArch As Boolean
            isArch = (act = "TRACK-YAW") And (ttgt = "arch_rise" Or ttgt = "arch_set")

            If isArch And IsNumeric(rawF) And IsNumeric(winV) Then
                If CDbl(winV) > 0 Then
                    ' arch PanoCycle: capture START + END centre yaw and the centre
                    ' pitch (= Rp + dpitch, the firmware's fixed row-0 pitch). The
                    ' pano overlay (dots + band) is drawn from these + the grid cfg.
                    If Not pCfgOK Then pCfgOK = ReadPanoPortrait(pCols, pRows, pRowstep, pOff)
                    Dim afStart As Double: afStart = Utils.DateSerialOf(ThisWorkbook.Sheets("Plan").Cells(PLAN_FIRST_ROW, COL_FIRESAT).value)
                    Dim afT As Double: afT = Utils.DatedFireSerial(CDbl(rawF), afStart)
                    Dim aWin As Double: aWin = CDbl(winV)
                    Dim aDyw As Double: aDyw = SafeNum(ws.Cells(r, COL_DYAW).value)
                    Dim aDpt As Double: aDpt = SafeNum(ws.Cells(r, COL_DPITCH).value)
                    Dim aRp As Double:  aRp = SafeNum(ws.Cells(r, COL_RP).value)

                    Dim ch0 As Double, sy0 As Double, sp0 As Double
                    Dim chE As Double, syE As Double, spE As Double
                    Dim ttEnd As Double: ttEnd = afT + (aWin / 1440#)
                    ch0 = CartHeadingAtChart(ws, afT)
                    chE = CartHeadingAtChart(ws, ttEnd)
                    Dim okS As Boolean, okE As Boolean
                    okS = PlanPush.EvalAstro(ttgt, afT, ch0, sy0, sp0)   ' arch: yaw is a bearing,
                    okE = PlanPush.EvalAstro(ttgt, ttEnd, chE, syE, spE) ' valid regardless of ok

                    pgStartY(pgN) = sy0 + aDyw
                    ' Seat the END centre onto the START's 360 branch: EvalAstro may
                    ' return start and end on different +-360 copies (e.g. 245 vs -115),
                    ' which would inflate the sweep band to ~270deg and stretch the axis.
                    ' The arch drifts only a few deg over a GP window, so wrap the drift
                    ' to +-180 (shortest) and rebuild end from start + that drift.
                    Dim dEnd As Double: dEnd = (syE + aDyw) - pgStartY(pgN)
                    Do While dEnd > 180#: dEnd = dEnd - 360#: Loop
                    Do While dEnd < -180#: dEnd = dEnd + 360#: Loop
                    pgEndY(pgN) = pgStartY(pgN) + dEnd
                    pgPitch(pgN) = aRp + aDpt
                    LogCH "  GP pano " & ttgt & ": startYaw=" & Format(pgStartY(pgN), "0.0") & _
                          " endYaw=" & Format(pgEndY(pgN), "0.0") & " centrePitch=" & Format(pgPitch(pgN), "0.0")
                    pgN = pgN + 1
                End If

            ElseIf (ttgt = "sun" Or ttgt = "moon" Or ttgt = "gc" Or ttgt = "mw") _
                   And IsNumeric(rawF) And IsNumeric(winV) Then
                ' FULL astro track: sample the centre yaw/pitch across its window
                ' (unchanged - these GPs fire single frames, no pano).
              If CDbl(winV) > 0 Then
                Dim fStartRaw As Double: fStartRaw = Utils.DateSerialOf(ThisWorkbook.Sheets("Plan").Cells(PLAN_FIRST_ROW, COL_FIRESAT).value)
                Dim fT As Double: fT = Utils.DatedFireSerial(CDbl(rawF), fStartRaw)
                Dim winMin As Double: winMin = CDbl(winV)
                Dim dyw As Double, dpt As Double
                dyw = SafeNum(ws.Cells(r, COL_DYAW).value)
                dpt = SafeNum(ws.Cells(r, COL_DPITCH).value)
                Dim k As Long, sy As Double, sp As Double, ch As Double, tt As Double
                Dim added As Long: added = 0
                For k = 0 To TRACK_NSAMP
                    tt = fT + (winMin / 1440#) * (CDbl(k) / CDbl(TRACK_NSAMP))
                    ch = CartHeadingAtChart(ws, tt)
                    Dim okEval As Boolean
                    okEval = PlanPush.EvalAstro(ttgt, tt, ch, sy, sp)
                    ' EvalAstro writes sy/sp BEFORE its below-horizon gate returns
                    ' False, so a rising/setting body's yaw is valid even when
                    ' ok=False - keep it and clamp pitch to 0 (rim), matching the
                    ' plan view and the firmware R7 rim-hold.
                    If okEval Then
                        yaw(n) = sy + dyw: pit(n) = sp + dpt
                        n = n + 1: added = added + 1
                        If n > UBound(yaw) Then Exit For
                    Else
                        yaw(n) = sy + dyw: pit(n) = 0#      ' below horizon -> rim
                        n = n + 1: added = added + 1
                        If n > UBound(yaw) Then Exit For
                    End If
                Next k
                LogCH "  GP track " & ttgt & ": " & added & " pts over " & Format(winMin, "0") & " min"
              End If
            Else
                LogCH "  NOTE row " & r & ": " & act & " '" & ttgt & "' - not sampleable, skipped"
            End If
        End If
NextRow:
    Next r

    If n < 1 And pgN < 1 Then
        LogCH "  no chartable points found"
        MsgBox "No Move/Pan-Follow points or pano GPs to chart.", vbExclamation, "PushChartToCart"
        Exit Sub
    End If

    ' max abs yaw offset across the active columns = the pano fan half-width.
    Dim maxOff As Double: maxOff = 0
    If pCfgOK Then
        Dim cc As Long
        For cc = 0 To pCols - 1
            If Abs(pOff(cc)) > maxOff Then maxOff = Abs(pOff(cc))
        Next cc
    End If

    ' yaw_min/yaw_max for the axis (left edge). Fold in Move/track points AND the
    ' full pano sweep (start/end centre +- fan) so the axis frames the whole thing.
    Dim haveX As Boolean: haveX = False
    Dim yawMin As Double, yawMax As Double
    Dim i As Long
    For i = 0 To n - 1
        If Not haveX Then yawMin = yaw(i): yawMax = yaw(i): haveX = True
        If yaw(i) < yawMin Then yawMin = yaw(i)
        If yaw(i) > yawMax Then yawMax = yaw(i)
    Next i
    Dim g As Long
    For g = 0 To pgN - 1
        Dim loY As Double, hiY As Double
        loY = IIf(pgStartY(g) < pgEndY(g), pgStartY(g), pgEndY(g)) - maxOff
        hiY = IIf(pgStartY(g) > pgEndY(g), pgStartY(g), pgEndY(g)) + maxOff
        If Not haveX Then yawMin = loY: yawMax = hiY: haveX = True
        If loY < yawMin Then yawMin = loY
        If hiY > yawMax Then yawMax = hiY
    Next g

    If (yawMax - yawMin) > YAW_SPAN Then
        LogCH "  WARNING: yaw range " & Format(yawMax - yawMin, "0") & _
              " deg exceeds the " & Format(YAW_SPAN, "0") & " deg chart span - path will clip"
    End If

    ' Build the inner SVG (axes + dashed 80deg + Move polyline/dots + pano overlay).
    Dim svg As String
    svg = ""
    ' faint gridlines: pitch 0 (bottom), 40 (mid)
    svg = svg & Line2(0, YOf(0), VB_W, YOf(0), "#0001", "")
    svg = svg & Line2(0, YOf(40), VB_W, YOf(40), "#0001", "")
    ' dashed mechanical-limit reminder at pitch 80 (top)
    svg = svg & Line2(0, YOf(80), VB_W, YOf(80), "#0001", "3 3")

    ' Move / Pan Follow + FULL track path: blue polyline + dots (only if present).
    If n >= 1 Then
        Dim pts As String: pts = ""
        For i = 0 To n - 1
            pts = pts & Format(XOf(yaw(i), yawMin), "0.0") & "," & Format(YOf(pit(i)), "0.0") & " "
        Next i
        svg = svg & "<polyline points='" & Trim(pts) & "' fill='none' stroke='#7a8aa0' stroke-width='2'/>"
        For i = 0 To n - 1
            svg = svg & "<circle cx='" & Format(XOf(yaw(i), yawMin), "0.0") & _
                  "' cy='" & Format(YOf(pit(i)), "0.0") & "' r='1.2' fill='#333'/>"
        Next i
    End If

    ' Pano overlay: per arch PanoCycle GP, the planned-sweep band + firing arrows +
    ' the rows x cols start-cluster dots. Drawn after the Move path so dots sit on top.
    If pgN >= 1 Then
        svg = svg & "<defs><marker id='pfa' markerWidth='5' markerHeight='5' refX='4' refY='2.5' orient='auto'>" & _
              "<path d='M0,0 L5,2.5 L0,5 z' fill='var(--xtext-mute)'/></marker></defs>"
        For g = 0 To pgN - 1
            ' planned-sweep band: the leading column (+maxOff if the centre drifts
            ' right, else -maxOff) from its GP-start position to its GP-end position.
            Dim drift As Double: drift = pgEndY(g) - pgStartY(g)
            Dim leadOff As Double: leadOff = IIf(drift >= 0, maxOff, -maxOff)
            Dim bx1 As Double, bx2 As Double
            bx1 = XOf(pgStartY(g) + leadOff, yawMin)
            bx2 = XOf(pgEndY(g) + leadOff, yawMin)
            Dim bLo As Double, bHi As Double
            bLo = IIf(bx1 < bx2, bx1, bx2): bHi = IIf(bx1 > bx2, bx1, bx2)
            Dim pTop As Double: pTop = pgPitch(g) + CDbl(pRows - 1) * pRowstep
            Dim yT As Double, yB As Double
            yT = YOf(pTop): yB = YOf(pgPitch(g))
            If (bHi - bLo) > 0.3 Then
                svg = svg & "<rect x='" & Format(bLo, "0.0") & "' y='" & Format(yT, "0.0") & _
                      "' width='" & Format(bHi - bLo, "0.0") & "' height='" & Format(yB - yT, "0.0") & _
                      "' fill='var(--xsweep)' fill-opacity='0.45'/>"
            End If

            ' firing arrows (raster: row 0 cols 0..C-1, then row 1, ...) + cell dots.
            Dim rr As Long, ccx As Long
            Dim prevx As Double, prevy As Double, first As Boolean
            first = True
            Dim dotsvg As String: dotsvg = ""
            For rr = 0 To pRows - 1
                For ccx = 0 To pCols - 1
                    Dim cyaw As Double, cpit As Double, cx As Double, cy As Double
                    cyaw = pgStartY(g) + pOff(ccx)
                    cpit = pgPitch(g) + CDbl(rr) * pRowstep
                    cx = XOf(cyaw, yawMin): cy = YOf(cpit)
                    If Not first Then
                        svg = svg & "<line x1='" & Format(prevx, "0.0") & "' y1='" & Format(prevy, "0.0") & _
                              "' x2='" & Format(cx, "0.0") & "' y2='" & Format(cy, "0.0") & _
                              "' stroke='var(--xtext-mute)' stroke-width='0.8' marker-end='url(#pfa)'/>"
                    End If
                    dotsvg = dotsvg & "<circle cx='" & Format(cx, "0.0") & "' cy='" & Format(cy, "0.0") & _
                             "' r='2' fill='var(--xtext)'/>"
                    prevx = cx: prevy = cy: first = False
                Next ccx
            Next rr
            svg = svg & dotsvg
        Next g
    End If

    LogCH "  yaw_min=" & Format(yawMin, "0.0") & " movepts=" & n & " panoGPs=" & pgN & " svg_len=" & Len(svg)

    If ReadDryRunFlag() Then
        LogCH "  DRY RUN svg: " & svg
        LogCH "--- PushChartToCart end (DRY RUN, not sent) ---"
        MsgBox "Dry run: chart SVG built (" & Len(svg) & " chars, " & n & " move pts, " & pgN & " pano GP(s))." & vbCrLf & _
               "See Log. Set dataPlanPushDryRun = FALSE to push.", vbInformation, "PushChartToCart"
        Exit Sub
    End If

    ' Push chunked to /settings/chartsvg
    Dim arduinoIP As String: arduinoIP = ReadArduinoIP()
    If arduinoIP = "" Then
        MsgBox "dataArduinoIP not set in Settings.", vbExclamation, "PushChartToCart"
        Exit Sub
    End If

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")

    Dim pos As Long, idx As Long, okAll As Boolean
    pos = 1: idx = 0: okAll = True
    Do While pos <= Len(svg)
        Dim raw As String
        raw = mid$(svg, pos, CHUNK_RAW)
        pos = pos + CHUNK_RAW
        Dim isLast As Long
        isLast = IIf(pos > Len(svg), 1, 0)

        Dim url As String
        url = arduinoIP & "/settings/chartsvg?idx=" & idx
        If idx = 0 Then url = url & "&yawmin=" & Format(yawMin, "0.0")
        url = url & "&last=" & isLast & "&d=" & UrlEncode(raw)

        LogCH "  GET chartsvg idx=" & idx & " last=" & isLast & " (" & Len(raw) & " raw chars)"
        On Error Resume Next
        http.Open "GET", url, False
        http.Send
        Dim sc As Long: sc = http.Status
        Dim resp As String: resp = CStr(http.responseText)
        On Error GoTo 0
        If sc = 200 Then
            LogCH "    OK " & resp
        Else
            LogCH "    HTTP " & sc & " " & resp
            okAll = False
            Exit Do
        End If
        idx = idx + 1
    Loop

    If okAll Then
        LogCH "--- PushChartToCart end (REAL PUSH, " & idx & " chunk(s)) ---"
        ' MsgBox "Chart pushed (" & idx & " chunk(s), " & n & " move pts, " & pgN & " pano GP(s))." & vbCrLf & _   ' real-push success popup removed: silent on success, detail in Log; DRY RUN + errors kept
               ' "Open the Execution screen to view.", vbInformation, "PushChartToCart"
    Else
        MsgBox "Chart push failed mid-way. See Log.", vbExclamation, "PushChartToCart"
    End If
End Sub

' Read the PANO sheet portrait block (the SAME named ranges PanoConfigPush sends):
'   panoP_shots  -> yaw column count (cols)
'   panoP_offsets-> yaw offsets (first cols used)
'   panoP_rows   -> pitch rows (default 1)
'   panoP_rowstep-> pitch step deg (default 0)
' Returns False (graceful: caller treats as no overlay) if the block is missing.
Private Function ReadPanoPortrait(ByRef cols As Long, ByRef rows As Long, _
                                  ByRef rowstep As Double, ByRef off() As Double) As Boolean
    On Error GoTo fail
    cols = CLng(ThisWorkbook.names("panoP_shots").RefersToRange.value)
    If cols < 1 Then cols = 1
    If cols > PANO_MAXCELL Then cols = PANO_MAXCELL

    rows = 1: rowstep = 0
    On Error Resume Next
    rows = CLng(ThisWorkbook.names("panoP_rows").RefersToRange.value)
    rowstep = CDbl(ThisWorkbook.names("panoP_rowstep").RefersToRange.value)
    On Error GoTo fail
    If rows < 1 Then rows = 1
    If rows > PANO_MAXCELL Then rows = PANO_MAXCELL

    Dim offRng As Range: Set offRng = ThisWorkbook.names("panoP_offsets").RefersToRange
    Dim c As Range, k As Long: k = 0
    For Each c In offRng
        If k >= cols Then Exit For
        If IsNumeric(c.value) And Trim(CStr(c.value)) <> "" Then off(k) = CDbl(c.value) Else off(k) = 0
        k = k + 1
    Next c
    Do While k < cols
        off(k) = 0: k = k + 1
    Loop
    ReadPanoPortrait = True
    Exit Function
fail:
    ReadPanoPortrait = False
End Function

' ---- coordinate mapping (the contract) ----
Private Function XOf(ByVal yaw As Double, ByVal yawMin As Double) As Double
    Dim x As Double
    x = (yaw - yawMin) / YAW_SPAN * VB_W
    If x < 0 Then x = 0
    If x > VB_W Then x = VB_W
    XOf = x
End Function

Private Function YOf(ByVal pitch As Double) As Double
    Dim y As Double
    y = VB_H - (pitch - PITCH_LO) / (PITCH_HI - PITCH_LO) * VB_H
    If y < 0 Then y = 0
    If y > VB_H Then y = VB_H
    YOf = y
End Function

Private Function Line2(ByVal x1 As Double, ByVal y1 As Double, _
                       ByVal x2 As Double, ByVal y2 As Double, _
                       ByVal col As String, ByVal dash As String) As String
    Dim s As String
    s = "<line x1='" & Format(x1, "0.0") & "' y1='" & Format(y1, "0.0") & _
        "' x2='" & Format(x2, "0.0") & "' y2='" & Format(y2, "0.0") & _
        "' stroke='" & col & "'"
    If dash <> "" Then s = s & " stroke-dasharray='" & dash & "'"
    Line2 = s & "/>"
End Function

' ---- helpers ----
Private Function CartHeadingAtChart(ByVal ws As Worksheet, ByVal t As Double) As Double
    ' Cart's expected heading where it is PARKED at time t = the latest cart WP
    ' (col B id "WP..") whose Commence (col J) <= t. Same rule as CartHeadingAtTime
    ' and the python cart_heading_at. Cart block is fixed B..K: B=2,H=8,J=10.
    Dim r As Long, tod As Double
    Dim bestC As Double, bestH As Double, haveBest As Boolean
    Dim firstH As Double, haveFirst As Boolean
    tod = t - Int(t)                              ' time-of-day fraction
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        Dim idv As String: idv = Trim(CStr(ws.Cells(r, 2).value))
        If Len(idv) = 0 Then Exit For
        If UCase(Left$(idv, 2)) = "WP" And IsNumeric(ws.Cells(r, 8).value) Then
            Dim hd As Double: hd = CDbl(ws.Cells(r, 8).value)
            If Not haveFirst Then firstH = hd: haveFirst = True
            Dim cmv As Variant: cmv = ws.Cells(r, 10).value
            If IsNumeric(cmv) Then
                Dim cmd As Double: cmd = CDbl(cmv) - Int(CDbl(cmv))
                If cmd <= tod Then
                    If (Not haveBest) Or (cmd >= bestC) Then bestC = cmd: bestH = hd: haveBest = True
                End If
            End If
        End If
    Next r
    If haveBest Then
        CartHeadingAtChart = bestH
    ElseIf haveFirst Then
        CartHeadingAtChart = firstH
    Else
        CartHeadingAtChart = 0#
    End If
End Function

Private Function SafeNum(ByVal v As Variant) As Double
    If IsNumeric(v) Then SafeNum = CDbl(v) Else SafeNum = 0
End Function

' Percent-encode everything except unreserved [A-Za-z0-9-_.~] so the cart's
' urlDecode reverses it exactly. Chunking is on RAW chars (caller), each chunk
' encoded whole, so no %XX escape is ever split.
Private Function UrlEncode(ByVal s As String) As String
    Dim o As String, i As Long, c As String, a As Integer
    o = ""
    For i = 1 To Len(s)
        c = mid$(s, i, 1)
        a = Asc(c)
        If (a >= 48 And a <= 57) Or (a >= 65 And a <= 90) Or _
           (a >= 97 And a <= 122) Or c = "-" Or c = "_" Or c = "." Or c = "~" Then
            o = o & c
        Else
            o = o & "%" & Right$("0" & Hex$(a), 2)
        End If
    Next i
    UrlEncode = o
End Function

Private Function ReadDryRunFlag() As Boolean
    On Error GoTo Defaulting
    Dim v As Variant
    v = ThisWorkbook.Sheets("Settings").Range("dataPlanPushDryRun").value
    If IsEmpty(v) Then ReadDryRunFlag = True: Exit Function
    ReadDryRunFlag = CBool(v)
    Exit Function
Defaulting:
    ReadDryRunFlag = True
End Function

Private Function ReadArduinoIP() As String
    On Error Resume Next
    Dim ip As String
    ip = Trim(CStr(ThisWorkbook.Sheets("Settings").Range("dataArduinoIP").value))
    On Error GoTo 0
    If ip = "" Then
        ReadArduinoIP = ""
    Else
        If LCase(Left(ip, 7)) <> "http://" Then ip = "http://" & ip
        ReadArduinoIP = ip
    End If
End Function

Private Sub LogCH(ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", LOG_CATEGORY, msg
    On Error GoTo 0
End Sub
