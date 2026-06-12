Attribute VB_Name = "CableStripPush"
' ============================================================
' HyperLapse Cart - Cable Strip Author (view #3, cart side)
'
' Authors the gimbal yaw SWEEP as a 1-D strip SVG and pushes it CHUNKED
' to the cart, the same way ChartPush authors the yaw/pitch chart. The
' cart stores + serves it on the Cable screen and animates the live
' marker over it ("Excel authors, Giga moves the marker").
'
' WHAT IT SHOWS: each GP's CART-FRAME yaw (gimbal relative to the cart
' body, the quantity cables actually tangle on), UNWRAPPED leg-by-leg in
' the direction set in Plan col AC (CW/CCW; blank = shortest), plotted
' against the 450 deg span limit. min yaw at the left, min+450 (cables-
' break ceiling) at the right. Matches the dial's cable wind because it
' uses the SAME resolver rule: cf = world - heading(anchor), i.e. dyaw for
' chassis GPs (the cart's own per-WP turning is removed, not counted).
'
' SCOPE: chassis/marker Move, Lock, Pan Follow (same scope as ChartPush).
' Astro Track/Track-yaw rows are skipped for now (their yaw sweeps over
' time; charting them is the same deferred extension ChartPush notes).
'
' COORDINATE CONTRACT (matches ChartPush / the cart):
'   viewBox 0 0 355 90 ;  x = (yaw - yaw_min)/450 * 355
'   strip band centred at y=45. The cart's marker uses the same x mapping,
'   so the live marker rides the strip = current wind position.
'
' ENDPOINT: defaults to /settings/cablesvg (its own slot, for the new
' Cable screen). To PREVIEW on the existing Execution screen before the
' Cable-screen firmware exists, set ENDPOINT = "/settings/chartsvg" (this
' replaces the yaw/pitch chart while testing).
'
' Run: PushCableStripToCart. Honours Settings!dataPlanPushDryRun.
' ============================================================
Option Explicit

Private Const LOG_CATEGORY   As String = "CABLEPUSH"
Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_MAX_ROWS  As Long = 60

' Plan columns (match ChartPush / resolve)
Private Const COL_WPID   As Long = 2    ' B  (WP rows: "WP..")
Private Const COL_HEAD   As Long = 8    ' H  (WP heading)
' MIDDLE columns resolved by header name at run time (PlanCols.ResolveMiddleCols),
' so a column reorder in Excel does not break the cable-strip push. (COL_WPID /
' COL_HEAD above are cart-WP block columns, not MIDDLE, so they stay fixed.)

' Contract
Private Const VB_W      As Double = 355
Private Const VB_H      As Double = 90
Private Const YAW_SPAN  As Double = 450
Private Const Y_MID     As Double = 45
Private Const Y_HALF    As Double = 13
Private Const CHUNK_RAW As Long = 150

Private Const ENDPOINT  As String = "/settings/cablesvg"   ' or "/settings/chartsvg" to preview

Public Sub PushCableStripToCart()
    On Error GoTo Fail
    Dim dry As Boolean: dry = ReadDryRun()
    LogEvent LOG_CATEGORY, "--- PushCableStripToCart start (" & IIf(dry, "DRY RUN", "REAL PUSH") & ") ---"

    Dim ws As Worksheet: Set ws = ThisWorkbook.Sheets("Plan")

    Dim cols As Object: Set cols = PlanCols.ResolveMiddleCols(ws)
    If cols Is Nothing Then Exit Sub                 ' header missing -> abort

    ' WP -> heading lookup (col B starts "WP", heading col H)
    Dim hdg As Object: Set hdg = CreateObject("Scripting.Dictionary")
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        Dim wid As String: wid = Trim(CStr(ws.Cells(r, COL_WPID).value))
        If Left$(UCase(wid), 2) = "WP" Then
            hdg(wid) = SafeNum(ws.Cells(r, COL_HEAD).value)
        End If
    Next r

    ' Collect per-GP CART-FRAME yaw (gimbal relative to cart body) + direction.
    ' Cable tangle is cart-frame, NOT world: the cart's per-WP heading must be
    ' removed or its own turning falsely counts as gimbal wind. Matches the dial
    ' resolver: cf = world - heading(anchor), where world = Ry+dyaw (earth) or
    ' heading+dyaw (chassis); so chassis reduces to cf = dyaw.
    Dim cf() As Double, dir() As String, lab() As String
    ReDim cf(0 To PLAN_MAX_ROWS): ReDim dir(0 To PLAN_MAX_ROWS): ReDim lab(0 To PLAN_MAX_ROWS)
    Dim n As Long: n = 0

    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        Dim act As String: act = UCase(Trim(CStr(ws.Cells(r, cols("action")).value)))
        If act = "" Then Exit For
        If act = "END" Then GoTo NextRow

        Dim tgt As String: tgt = LCase(Trim(CStr(ws.Cells(r, cols("target")).value)))
        If tgt = "sun" Or tgt = "moon" Or tgt = "mw" Or tgt = "sunrise" Or tgt = "sunset" Then
            LogEvent LOG_CATEGORY, "  NOTE row " & r & ": astro '" & tgt & "' - skipped (deferred)"
            GoTo NextRow
        End If
        If act <> "MOVE" And act <> "LOCK" And act <> "PAN FOLLOW" Then
            LogEvent LOG_CATEGORY, "  NOTE row " & r & ": action '" & act & "' - skipped"
            GoTo NextRow
        End If

        ' cart-frame cf = world - heading(anchor)   [matches gimbal_planview_v2 resolver]
        '   Ry present : cf = (Ry + dyaw) - heading
        '   chassis    : cf = dyaw            (heading cancels)
        Dim dyaw As Double: dyaw = SafeNum(ws.Cells(r, cols("dyaw")).value)
        Dim anc As String: anc = Trim(CStr(ws.Cells(r, cols("anchorref")).value))
        Dim h As Double: h = 0#
        If hdg.Exists(anc) Then h = hdg(anc)
        Dim w As Double
        If IsNumeric(ws.Cells(r, cols("ry")).value) And Trim(CStr(ws.Cells(r, cols("ry")).value)) <> "" Then
            w = SafeNum(ws.Cells(r, cols("ry")).value) + dyaw - h
        Else
            w = dyaw
        End If
        w = w - 360# * Int((w + 180#) / 360#)      ' wrap to [-180,180), VBA Int=floor (matches resolver)

        Dim d As String: d = UCase(Trim(CStr(ws.Cells(r, cols("dir(cw/ccw)")).value)))
        If d <> "CW" And d <> "CCW" Then d = ""

        cf(n) = w: dir(n) = d
        lab(n) = Left$(CStr(ws.Cells(r, cols("step")).value), 11)
        n = n + 1
NextRow:
    Next r

    If n < 1 Then
        MsgBox "No chassis/Lock/Pan-Follow GPs to chart.", vbExclamation, "PushCableStripToCart"
        Exit Sub
    End If

    ' Unwrap cart-frame yaw leg-by-leg honouring col AC (cumulative cable wind)
    Dim u() As Double: ReDim u(0 To n - 1)
    Dim i As Long
    u(0) = cf(0)
    For i = 1 To n - 1
        Dim dd As Double, shrt As Double, step As Double
        dd = cf(i) - cf(i - 1)
        shrt = dd - 360# * Int((dd + 180#) / 360#)   ' float-exact wrap to [-180,180), VBA Int = floor
        If dir(i) = "CW" Then
            step = IIf(shrt >= 0, shrt, shrt + 360#)
        ElseIf dir(i) = "CCW" Then
            step = IIf(shrt <= 0, shrt, shrt - 360#)
        Else
            step = shrt
        End If
        u(i) = u(i - 1) + step
    Next i

    ' min / max / headroom
    Dim umin As Double, umax As Double: umin = u(0): umax = u(0)
    For i = 1 To n - 1
        If u(i) < umin Then umin = u(i)
        If u(i) > umax Then umax = u(i)
    Next i
    Dim used As Double: used = umax - umin
    Dim headroom As Double: headroom = YAW_SPAN - used
    LogEvent LOG_CATEGORY, "  min=" & Format(umin, "0.0") & " max=" & Format(umax, "0.0") & _
             " used=" & Format(used, "0.0") & " headroom=" & Format(headroom, "0.0")
    If used > YAW_SPAN Then LogEvent LOG_CATEGORY, "  WARNING: used span exceeds " & YAW_SPAN & " - cables would bind"

    ' ---- build strip SVG (inner fragment) ----
    Dim svg As String: svg = ""
    Dim yT As String: yT = Format(Y_MID - Y_HALF, "0.0")
    Dim hBand As String: hBand = Format(2 * Y_HALF, "0.0")
    ' full 450 track
    svg = svg & "<rect x='0' y='" & yT & "' width='" & Format(VB_W, "0.0") & _
          "' height='" & hBand & "' fill='#0d141f' stroke='#2b3340'/>"
    ' used span fill
    svg = svg & "<rect x='" & Format(XOf(umin, umin), "0.0") & "' y='" & yT & _
          "' width='" & Format(XOf(umax, umin) - XOf(umin, umin), "0.0") & _
          "' height='" & hBand & "' fill='#3b82f6' fill-opacity='0.45'/>"
    ' span-limit line (right edge) + min tick
    svg = svg & Line2(VB_W, Y_MID - 22, VB_W, Y_MID + 22, "#ff5470", "")
    svg = svg & Line2(0, Y_MID - 22, 0, Y_MID + 22, "#5b6675", "")

    ' sweep-order arcs: green forward (x increasing), red reverse (x decreasing).
    ' Quadratic arc bowing above the band so direction reads at a glance.
    For i = 0 To n - 2
        Dim x1 As Double, x2 As Double, xm As Double
        x1 = XOf(u(i), umin): x2 = XOf(u(i + 1), umin): xm = (x1 + x2) / 2#
        Dim acol As String: acol = IIf(u(i + 1) >= u(i), "#3fb950", "#ff5470")
        svg = svg & "<path d='M" & Format(x1, "0.0") & " " & Format(Y_MID, "0.0") & _
              " Q" & Format(xm, "0.0") & " " & Format(Y_MID - 18, "0.0") & " " & _
              Format(x2, "0.0") & " " & Format(Y_MID, "0.0") & _
              "' fill='none' stroke='" & acol & "' stroke-width='1.6' opacity='0.9'/>"
    Next i

    ' label side by x-order so near-coincident GPs don't overlap
    Dim side() As Boolean: ReDim side(0 To n - 1)
    Dim ord() As Long: ReDim ord(0 To n - 1)
    For i = 0 To n - 1: ord(i) = i: Next i
    Dim a As Long, b As Long, tmp As Long
    For a = 0 To n - 2
        For b = 0 To n - 2 - a
            If u(ord(b)) > u(ord(b + 1)) Then tmp = ord(b): ord(b) = ord(b + 1): ord(b + 1) = tmp
        Next b
    Next a
    For a = 0 To n - 1: side(ord(a)) = (a Mod 2 = 0): Next a   ' True = id label above

    ' GP dots + labels (id above/below per x-order; cart-frame yaw below)
    For i = 0 To n - 1
        Dim col As String: col = IIf(u(i) = umax, "#ff5470", "#c9d4e3")
        Dim gx As Double: gx = XOf(u(i), umin)
        svg = svg & "<circle cx='" & Format(gx, "0.0") & "' cy='" & Format(Y_MID, "0.0") & _
              "' r='3.2' fill='" & col & "'/>"
        Dim ly As Double: ly = IIf(side(i), Y_MID - 20, Y_MID - 11)   ' two id-label heights
        svg = svg & "<text x='" & Format(gx, "0.0") & "' y='" & Format(ly, "0.0") & _
              "' font-size='7' fill='" & col & "' text-anchor='middle'>" & lab(i) & _
              IIf(u(i) = umax, " max", "") & "</text>"
        Dim by As Double: by = IIf(side(i), Y_MID + 27, Y_MID + 35)   ' two bearing heights
        svg = svg & "<text x='" & Format(gx, "0.0") & "' y='" & Format(by, "0.0") & _
              "' font-size='7' fill='#8b98a8' text-anchor='middle'>" & Format(u(i), "0") & "</text>"
    Next i
    ' limit degree tick (right). Left min is GP01's own bearing, so no separate tick.
    svg = svg & "<text x='" & Format(VB_W - 2, "0.0") & "' y='" & Format(Y_MID + 27, "0.0") & _
          "' font-size='7' fill='#ff5470' text-anchor='end'>" & Format(umin + YAW_SPAN, "0") & " lim</text>"

    LogEvent LOG_CATEGORY, "  points=" & n & " svg_len=" & Len(svg)

    If dry Then
        LogEvent LOG_CATEGORY, "  DRY RUN svg: " & svg
        MsgBox "DRY RUN: cable strip SVG built (" & Len(svg) & " chars, " & n & " GPs)." & vbCrLf & _
               "min " & Format(umin, "0") & "  max " & Format(umax, "0") & _
               "  used " & Format(used, "0") & "  headroom " & Format(headroom, "0") & vbCrLf & _
               "Set dataPlanPushDryRun = FALSE to push.", vbInformation, "PushCableStripToCart"
        Exit Sub
    End If

    ' ---- chunked push ----
    Dim ip As String: ip = ReadArduinoIP()
    If ip = "" Then MsgBox "dataArduinoIP not set.", vbExclamation, "PushCableStripToCart": Exit Sub

    ' per-GP strip x (0..355), index-aligned to the charted GPs, for the
    ' cart's index-driven marker (cable_gp_x[]). For a chassis-only plan
    ' this order matches the preview poses 1:1; see workfront note re astro.
    Dim gpx As String: gpx = ""
    For i = 0 To n - 1
        If i > 0 Then gpx = gpx & ","
        gpx = gpx & Format(XOf(u(i), umin), "0.0")
    Next i

    Dim http As Object: Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    Dim pos As Long, idx As Long, okAll As Boolean
    pos = 1: idx = 0: okAll = True
    Do While pos <= Len(svg)
        Dim raw As String: raw = mid$(svg, pos, CHUNK_RAW)
        pos = pos + CHUNK_RAW
        Dim isLast As Long: isLast = IIf(pos > Len(svg), 1, 0)
        Dim url As String
        url = ip & ENDPOINT & "?idx=" & idx
        If idx = 0 Then url = url & "&yawmin=" & Format(umin, "0.0") & "&gpx=" & gpx
        url = url & "&last=" & isLast & "&d=" & UrlEnc(raw)
        LogEvent LOG_CATEGORY, "  GET " & ENDPOINT & " idx=" & idx & " last=" & isLast & " (" & Len(raw) & " chars)"
        On Error Resume Next
        http.Open "GET", url, False
        http.Send
        Dim sc As Long: sc = http.Status
        On Error GoTo Fail
        If sc <> 200 Then LogEvent LOG_CATEGORY, "    HTTP " & sc: okAll = False: Exit Do
        idx = idx + 1
    Loop

    If okAll Then
        LogEvent LOG_CATEGORY, "--- end (REAL PUSH, " & idx & " chunk(s)) ---"
        MsgBox "Cable strip pushed (" & idx & " chunk(s), " & n & " GPs)." & vbCrLf & _
               "used " & Format(used, "0") & " deg, headroom " & Format(headroom, "0") & " deg." & vbCrLf & _
               "Open the Cable screen to view.", vbInformation, "PushCableStripToCart"
    Else
        MsgBox "Cable strip push failed mid-way. See Log.", vbExclamation, "PushCableStripToCart"
    End If
    Exit Sub

Fail:
    MsgBox "PushCableStripToCart error: " & Err.Description, vbExclamation
End Sub

' ---- coordinate mapping (the contract) ----
Private Function XOf(ByVal yaw As Double, ByVal yawMin As Double) As Double
    Dim x As Double: x = (yaw - yawMin) / YAW_SPAN * VB_W
    If x < 0 Then x = 0
    If x > VB_W Then x = VB_W
    XOf = x
End Function

Private Function Line2(ByVal x1 As Double, ByVal y1 As Double, _
                       ByVal x2 As Double, ByVal y2 As Double, _
                       ByVal col As String, ByVal dash As String) As String
    Dim s As String
    s = "<line x1='" & Format(x1, "0.0") & "' y1='" & Format(y1, "0.0") & _
        "' x2='" & Format(x2, "0.0") & "' y2='" & Format(y2, "0.0") & "' stroke='" & col & "'"
    If dash <> "" Then s = s & " stroke-dasharray='" & dash & "'"
    Line2 = s & "/>"
End Function

' ---- self-contained helpers (no dependence on other modules' privates) ----
Private Function SafeNum(ByVal v As Variant) As Double
    If IsNumeric(v) Then SafeNum = CDbl(v) Else SafeNum = 0#
End Function

Private Function ReadDryRun() As Boolean
    On Error Resume Next
    ReadDryRun = (UCase(CStr(ThisWorkbook.Sheets("Settings").Range("dataPlanPushDryRun").value)) = "TRUE")
    On Error GoTo 0
End Function

Private Function ReadArduinoIP() As String
    On Error Resume Next
    ReadArduinoIP = CStr(ThisWorkbook.Sheets("Settings").Range("dataArduinoIP").value)
    On Error GoTo 0
End Function

Private Function UrlEnc(ByVal s As String) As String
    Dim i As Long, c As String, o As String, code As Integer
    For i = 1 To Len(s)
        c = mid$(s, i, 1): code = Asc(c)
        If (code >= 48 And code <= 57) Or (code >= 65 And code <= 90) Or _
           (code >= 97 And code <= 122) Or InStr("-_.~", c) > 0 Then
            o = o & c
        Else
            o = o & "%" & Right$("0" & Hex$(code), 2)
        End If
    Next i
    UrlEnc = o
End Function
