Attribute VB_Name = "ChartPush"
' ============================================================
' HyperLapse Cart - Execution Chart Author (Day 30)
'
' Authors the gimbal-plan path as an inner SVG fragment and pushes
' it CHUNKED to the cart at /settings/chartsvg. The cart stores +
' serves it on the Execution screen and only animates the live
' camera icon over it ("Excel authors, Giga moves the icon").
'
' SCOPE (this build): Move / Pan Follow plans with marker targets
' (the relative-pan plan). Each GP is a target point (Ry+dyaw,
' Rp+dpitch); the path is the polyline through them with dots.
' Move/ease transitions are BLUE per GIMBAL_VIZ section 7.
' Astro Track curves (sampled cubic, velocity-banded green/amber/
' red) are a later extension of this same author - they need the
' col-H planned heading to map earth azimuth -> gimbal yaw, and a
' daylight session to verify. Track/Track-yaw rows are skipped here
' with a note.
'
' COORDINATE CONTRACT (must match the cart, soak-v43):
'   viewBox 0 0 355 90
'   x = (yaw   - yaw_min) / 450 * 355
'   y = 90 - (pitch - 20) / 60  * 90        (pitch 20 bottom .. 80 top)
'   dashed mechanical-limit reminder at pitch 80 (y = 0)
'
' Run: PushChartToCart. Honours dataPlanPushDryRun (TRUE = build +
' log the SVG, do not send).
' ============================================================
Option Explicit

Private Const LOG_CATEGORY    As String = "CHARTPUSH"
Private Const PLAN_FIRST_ROW  As Long = 6
Private Const PLAN_MAX_ROWS   As Long = 60

' Plan middle-zone columns (match TrackPlanPush)
Private Const COL_ACTION      As Long = 19  ' S
Private Const COL_TARGET      As Long = 20  ' T
Private Const COL_RY          As Long = 22  ' V
Private Const COL_RP          As Long = 23  ' W
Private Const COL_DYAW        As Long = 24  ' X
Private Const COL_DPITCH      As Long = 25  ' Y

' Chart contract
Private Const VB_W            As Double = 355
Private Const VB_H            As Double = 90
Private Const YAW_SPAN        As Double = 450
Private Const PITCH_LO        As Double = 20
Private Const PITCH_HI        As Double = 80

Private Const CHUNK_RAW       As Long = 150   ' raw SVG chars per push chunk

Public Sub PushChartToCart()
    LogCH "--- PushChartToCart start" & IIf(ReadDryRunFlag(), " (DRY RUN)", " (REAL PUSH)") & " ---"

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Plan")

    ' Collect Move / Pan Follow marker targets in plan order.
    Dim yaw() As Double, pit() As Double
    ReDim yaw(0 To PLAN_MAX_ROWS)
    ReDim pit(0 To PLAN_MAX_ROWS)
    Dim n As Long: n = 0

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
               tgt = "sunrise" Or tgt = "sunset" Then
                LogCH "  NOTE row " & r & ": astro target '" & tgt & "' - skipped (astro charting deferred)"
                GoTo NextRow
            End If
            yaw(n) = SafeNum(ws.Cells(r, COL_RY).value) + SafeNum(ws.Cells(r, COL_DYAW).value)
            pit(n) = SafeNum(ws.Cells(r, COL_RP).value) + SafeNum(ws.Cells(r, COL_DPITCH).value)
            LogCH "  GP point " & n & ": yaw=" & Format(yaw(n), "0.0") & " pitch=" & Format(pit(n), "0.0")
            n = n + 1
        ElseIf act = "TRACK" Or act = "TRACK-YAW" Then
            LogCH "  NOTE row " & r & ": " & act & " (astro) - charting deferred, skipped"
        End If
NextRow:
    Next r

    If n < 1 Then
        LogCH "  no chartable points found"
        MsgBox "No Move/Pan-Follow points to chart.", vbExclamation, "PushChartToCart"
        Exit Sub
    End If

    ' yaw_min for the axis (left edge). Warn if the plan exceeds the span.
    Dim yawMin As Double, yawMax As Double
    yawMin = yaw(0): yawMax = yaw(0)
    Dim i As Long
    For i = 1 To n - 1
        If yaw(i) < yawMin Then yawMin = yaw(i)
        If yaw(i) > yawMax Then yawMax = yaw(i)
    Next i
    If (yawMax - yawMin) > YAW_SPAN Then
        LogCH "  WARNING: yaw range " & Format(yawMax - yawMin, "0") & _
              " deg exceeds the " & Format(YAW_SPAN, "0") & " deg chart span - path will clip"
    End If

    ' Build the inner SVG (axes + dashed 80deg + blue polyline + dots).
    Dim svg As String
    svg = ""
    ' faint gridlines: pitch 20 (bottom), 50 (mid)
    svg = svg & Line2(0, YOf(20), VB_W, YOf(20), "#0001", "")
    svg = svg & Line2(0, YOf(50), VB_W, YOf(50), "#0001", "")
    ' dashed mechanical-limit reminder at pitch 80 (top)
    svg = svg & Line2(0, YOf(80), VB_W, YOf(80), "#0001", "3 3")

    ' blue polyline through the targets (Move/ease = blue per GIMBAL_VIZ)
    Dim pts As String: pts = ""
    For i = 0 To n - 1
        pts = pts & Format(XOf(yaw(i), yawMin), "0.0") & "," & Format(YOf(pit(i)), "0.0") & " "
    Next i
    svg = svg & "<polyline points='" & Trim(pts) & "' fill='none' stroke='#7a8aa0' stroke-width='2'/>"

    ' waypoint dots
    For i = 0 To n - 1
        svg = svg & "<circle cx='" & Format(XOf(yaw(i), yawMin), "0.0") & _
              "' cy='" & Format(YOf(pit(i)), "0.0") & "' r='3' fill='#333'/>"
    Next i

    LogCH "  yaw_min=" & Format(yawMin, "0.0") & " points=" & n & " svg_len=" & Len(svg)

    If ReadDryRunFlag() Then
        LogCH "  DRY RUN svg: " & svg
        LogCH "--- PushChartToCart end (DRY RUN, not sent) ---"
        MsgBox "Dry run: chart SVG built (" & Len(svg) & " chars, " & n & " points)." & vbCrLf & _
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
        raw = Mid$(svg, pos, CHUNK_RAW)
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
        MsgBox "Chart pushed (" & idx & " chunk(s), " & n & " points)." & vbCrLf & _
               "Open the Execution screen to view.", vbInformation, "PushChartToCart"
    Else
        MsgBox "Chart push failed mid-way. See Log.", vbExclamation, "PushChartToCart"
    End If
End Sub

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
        c = Mid$(s, i, 1)
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