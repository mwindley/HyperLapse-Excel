Attribute VB_Name = "Utils"
' ============================================================
' HyperLapse Cart — Utility Module
' Shared helpers used by all other modules:
'   - Sunrise/sunset time lookup (sunrise-sunset.org API)
'   - Phase timing calculations
'   - Interval calculation from shutter speed
'   - Shutter speed string to seconds conversion
'   - Seconds to shutter speed string conversion
'   - Monitor sheet update
'   - Arduino cart control helpers
' ============================================================

Option Explicit

' ============================================================
' Sunrise / Sunset API
' Free API — no key required
' https://api.sunrise-sunset.org/json?lat=&lng=&date=today&formatted=0
' Returns times in UTC — convert using dataUTCOffset named range
' ============================================================

' Get today's sunset time as Excel serial (local time)
Public Function GetSunsetTime() As Date
    On Error GoTo ErrHandler
    
    Dim lat       As Double
    Dim lng       As Double
    Dim utcOffset As Double
    lat       = Sheets("Settings").Range("dataLatitude").Value
    lng       = Sheets("Settings").Range("dataLongitude").Value
    utcOffset = Sheets("Settings").Range("dataUTCOffset").Value
    
    Dim url As String
    url = "https://api.sunrise-sunset.org/json?lat=" & lat & _
          "&lng=" & lng & "&date=today&formatted=0"
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", url, False
    http.Send
    
    If http.Status <> 200 Then
        LogEvent "UTILS", "GetSunsetTime HTTP " & http.Status
        GetSunsetTime = 0
        Exit Function
    End If
    
    ' Parse sunset from JSON
    ' Response: {"results":{"sunset":"2026-05-09T08:23:00+00:00",...},"status":"OK"}
    Dim response As String
    response = http.ResponseText
    Set http = Nothing
    
    Dim sunsetStr As String
    sunsetStr = ParseJsonField(response, "sunset")
    If sunsetStr = "" Then
        LogEvent "UTILS", "GetSunsetTime: could not parse sunset from response"
        GetSunsetTime = 0
        Exit Function
    End If
    
    ' Parse ISO 8601 UTC time and convert to local
    ' Format: "2026-05-09T08:23:00+00:00"
    Dim utcTime As Date
    utcTime = CDate(Left(sunsetStr, 19))  ' "2026-05-09 08:23:00"
    
    ' Convert UTC to local time
    Dim localTime As Date
    localTime = utcTime + (utcOffset / 24)
    
    ' Store in Settings sheet
    Sheets("Settings").Range("dataSunsetTime").Value = localTime
    
    LogEvent "UTILS", "Sunset today: " & Format(localTime, "HH:nn:ss") & " local"
    GetSunsetTime = localTime
    Exit Function
ErrHandler:
    LogEvent "UTILS", "GetSunsetTime error: " & Err.Description
    GetSunsetTime = 0
End Function

' Get today's sunrise time as Excel serial (local time)
Public Function GetSunriseTime() As Date
    On Error GoTo ErrHandler
    
    Dim lat       As Double
    Dim lng       As Double
    Dim utcOffset As Double
    lat       = Sheets("Settings").Range("dataLatitude").Value
    lng       = Sheets("Settings").Range("dataLongitude").Value
    utcOffset = Sheets("Settings").Range("dataUTCOffset").Value
    
    Dim url As String
    url = "https://api.sunrise-sunset.org/json?lat=" & lat & _
          "&lng=" & lng & "&date=today&formatted=0"
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", url, False
    http.Send
    
    If http.Status <> 200 Then
        GetSunriseTime = 0
        Exit Function
    End If
    
    Dim sunriseStr As String
    sunriseStr = ParseJsonField(http.ResponseText, "sunrise")
    Set http = Nothing
    
    Dim utcTime As Date
    utcTime = CDate(Left(sunriseStr, 19))
    Dim localTime As Date
    localTime = utcTime + (utcOffset / 24)
    
    Sheets("Settings").Range("dataSunriseTime").Value = localTime
    LogEvent "UTILS", "Sunrise today: " & Format(localTime, "HH:nn:ss") & " local"
    GetSunriseTime = localTime
    Exit Function
ErrHandler:
    LogEvent "UTILS", "GetSunriseTime error: " & Err.Description
    GetSunriseTime = 0
End Function

' ============================================================
' Shutter speed conversions
' ============================================================

' Convert shutter speed string to seconds as Double
' "1/5000" -> 0.0002,  "1/100" -> 0.01,  "1" -> 1.0,  "20" -> 20.0
Public Function TvToSeconds(ByVal tvStr As String) As Double
    On Error GoTo ErrHandler
    tvStr = Trim(tvStr)
    If InStr(tvStr, "/") > 0 Then
        ' Fractional — e.g. "1/5000"
        Dim parts() As String
        parts = Split(tvStr, "/")
        TvToSeconds = CDbl(parts(0)) / CDbl(parts(1))
    Else
        ' Whole seconds — e.g. "20"
        TvToSeconds = CDbl(tvStr)
    End If
    Exit Function
ErrHandler:
    LogEvent "UTILS", "TvToSeconds error: [" & tvStr & "] " & Err.Description
    TvToSeconds = 0
End Function

' Convert seconds to nearest CCAPI TV string
' 0.0002 -> "1/5000",  0.01 -> "1/100",  1.0 -> "1",  20.0 -> "20"
Public Function SecondsToTv(ByVal secs As Double) As String
    ' Full list of valid TV values for R3 in Manual mode
    Dim tvValues As Variant
    tvValues = Array("1/8000", "1/6400", "1/5000", "1/4000", "1/3200", _
                     "1/2500", "1/2000", "1/1600", "1/1250", "1/1000", _
                     "1/800",  "1/640",  "1/500",  "1/400",  "1/320", _
                     "1/250",  "1/200",  "1/160",  "1/125",  "1/100", _
                     "1/80",   "1/60",   "1/50",   "1/40",   "1/30", _
                     "1/25",   "1/20",   "1/15",   "1/13",   "1/10", _
                     "1/8",    "1/6",    "1/5",    "1/4",    "0.3", _
                     "0.4",    "0.5",    "0.6",    "0.8",    "1", _
                     "1.3",    "1.6",    "2",      "2.5",    "3", _
                     "4",      "5",      "6",      "8",      "10", _
                     "13",     "15",     "20",     "25",     "30")
    
    ' Find closest match
    Dim bestMatch  As String
    Dim bestDelta  As Double
    bestDelta = 999999
    bestMatch = "1/5000"
    
    Dim i As Integer
    For i = 0 To UBound(tvValues)
        Dim tvSecs As Double
        tvSecs = TvToSeconds(CStr(tvValues(i)))
        Dim delta As Double
        delta = Abs(tvSecs - secs)
        If delta < bestDelta Then
            bestDelta = delta
            bestMatch = CStr(tvValues(i))
        End If
    Next i
    
    SecondsToTv = bestMatch
End Function

' ============================================================
' Interval calculation
' ============================================================

' Calculate shooting interval from shutter speed
' interval = max(2.0, shutter_seconds + 2.0)
Public Function CalcInterval(ByVal tvStr As String) As Double
    Dim shutterSecs As Double
    shutterSecs = TvToSeconds(tvStr)
    If shutterSecs <= 0.5 Then
        CalcInterval = 2.0
    Else
        CalcInterval = shutterSecs + 2.0
    End If
End Function

' ============================================================
' Phase timing — all times relative to sunset
' ============================================================

' Calculate phase start/end times from sunset time
' Offsets in minutes relative to sunset (negative = before sunset)
Public Sub CalculatePhaseTimes()
    Dim sunsetTime As Date
    sunsetTime = Sheets("Settings").Range("dataSunsetTime").Value
    
    If sunsetTime = 0 Then
        MsgBox "Sunset time not set — run GetSunsetTime() first", vbExclamation
        Exit Sub
    End If
    
    Dim ws As Worksheet
    Set ws = Sheets("Settings")
    
    ' Phase 1 start — fixed at 16:00
    ws.Range("dataPhase1Start").Value = CDate(Int(Now()) + TimeValue("16:00:00"))
    
    ' Phase 2a — sunset minus 45 minutes (shutter starts slowing)
    ws.Range("dataPhase2aStart").Value = sunsetTime - (45 / 1440)
    
    ' Phase 2b — sunset plus 20 minutes (ISO starts climbing)
    ws.Range("dataPhase2bStart").Value = sunsetTime + (20 / 1440)
    
    ' Phase 3 — sunset plus 60 minutes (full night settings)
    ws.Range("dataPhase3Start").Value = sunsetTime + (60 / 1440)
    
    ' Phase 4a — get tomorrow's sunrise minus 90 minutes
    Dim sunriseTime As Date
    sunriseTime = Sheets("Settings").Range("dataSunriseTime").Value
    ws.Range("dataPhase4aStart").Value = sunriseTime - (90 / 1440)
    
    ' Phase 4b — sunrise minus 45 minutes
    ws.Range("dataPhase4bStart").Value = sunriseTime - (45 / 1440)
    
    ' Phase 5 — sunrise time
    ws.Range("dataPhase5Start").Value = sunriseTime
    
    LogEvent "UTILS", "Phase times calculated from sunset " & Format(sunsetTime, "HH:nn:ss")
End Sub

' Get current phase number (1-5) based on current time
Public Function GetCurrentPhase() As Integer
    Dim ws As Worksheet
    Set ws = Sheets("Settings")
    Dim t As Date
    t = Now()
    
    If t >= ws.Range("dataPhase5Start").Value Then
        GetCurrentPhase = 5
    ElseIf t >= ws.Range("dataPhase4bStart").Value Then
        GetCurrentPhase = 4   ' 4b
    ElseIf t >= ws.Range("dataPhase4aStart").Value Then
        GetCurrentPhase = 4   ' 4a
    ElseIf t >= ws.Range("dataPhase3Start").Value Then
        GetCurrentPhase = 3
    ElseIf t >= ws.Range("dataPhase2bStart").Value Then
        GetCurrentPhase = 23  ' 2b (23 = phase 2, sub b)
    ElseIf t >= ws.Range("dataPhase2aStart").Value Then
        GetCurrentPhase = 22  ' 2a (22 = phase 2, sub a)
    Else
        GetCurrentPhase = 1
    End If
End Function

' ============================================================
' Monitor sheet update
' ============================================================

' Update the Monitor sheet with current status
Public Sub UpdateMonitor()
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = Sheets("Monitor")
    
    ' Current time and phase
    ws.Range("monTime").Value     = Format(Now(), "HH:nn:ss")
    ws.Range("monPhase").Value    = PhaseLabel(GetCurrentPhase())
    
    ' Camera settings
    ws.Range("monTv").Value       = Sheets("Settings").Range("dataCurrentTv").Value
    ws.Range("monISO").Value      = Sheets("Settings").Range("dataCurrentISO").Value
    ws.Range("monAv").Value       = Sheets("Settings").Range("dataCurrentAv").Value
    ws.Range("monLuminance").Value = Sheets("Settings").Range("dataLuminance").Value
    ws.Range("monShotCount").Value = Sheets("Settings").Range("dataShotCount").Value
    
    ' Gimbal
    ws.Range("monGimbalYaw").Value   = Sheets("Settings").Range("dataGimbalYaw").Value
    ws.Range("monGimbalPitch").Value = Sheets("Settings").Range("dataGimbalPitch").Value
    
    ' Cart
    ws.Range("monCartSpeed").Value    = Sheets("Settings").Range("dataCartSpeed").Value
    ws.Range("monCartSteering").Value = Sheets("Settings").Range("dataCartSteering").Value
    ws.Range("monCartVoltage").Value  = Sheets("Settings").Range("dataCartVoltage").Value
    
    ' Interval
    Dim tvStr As String
    tvStr = Sheets("Settings").Range("dataCurrentTv").Value
    ws.Range("monInterval").Value = Format(CalcInterval(tvStr), "0.0") & "s"
End Sub

' Return human-readable phase label
Public Function PhaseLabel(ByVal phase As Integer) As String
    Select Case phase
        Case 1:  PhaseLabel = "Phase 1 — Daytime"
        Case 22: PhaseLabel = "Phase 2a — Shutter transition"
        Case 23: PhaseLabel = "Phase 2b — ISO ramp"
        Case 3:  PhaseLabel = "Phase 3 — Full night"
        Case 4:  PhaseLabel = "Phase 4 — Pre-sunrise"
        Case 5:  PhaseLabel = "Phase 5 — Daytime"
        Case Else: PhaseLabel = "Unknown"
    End Select
End Function

' ============================================================
' Arduino cart control helpers
' Called from Sequence module for replay plan execution
' ============================================================

' Send a cart button command to Arduino
Public Function CartButton(ByVal btnNum As Integer) As Boolean
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/btn" & btnNum, False
    http.Send
    CartButton = (http.Status = 200)
    Set http = Nothing
    Exit Function
ErrHandler:
    CartButton = False
End Function

' Set cart speed via Arduino btn commands
' Adjusts from current speed to target speed in steps
Public Sub CartSetSpeed(ByVal targetSpeed As Double)
    Dim currentSpeed As Double
    currentSpeed = Sheets("Settings").Range("dataCartSpeed").Value
    
    Dim delta As Double
    delta = targetSpeed - currentSpeed
    
    ' Use +10/-10 for large steps, +1/-1 for fine tuning
    Do While Abs(delta) >= 10
        If delta > 0 Then
            CartButton 10  ' +10 m/hr
            delta = delta - 10
        Else
            CartButton 6   ' -10 m/hr
            delta = delta + 10
        End If
        Application.Wait Now + 0.0001
    Loop
    
    Do While Abs(delta) >= 1
        If delta > 0 Then
            CartButton 9   ' +1 m/hr
            delta = delta - 1
        Else
            CartButton 7   ' -1 m/hr
            delta = delta + 1
        End If
        Application.Wait Now + 0.0001
    Loop
    
    LogEvent "CART", "Speed set to " & targetSpeed & " m/hr"
End Sub

' Set cart steering offset via Arduino btn commands
' steeringOffset: degrees from centre (-ve = left, +ve = right)
Public Sub CartSetSteering(ByVal targetOffset As Integer)
    Dim currentOffset As Integer
    currentOffset = CInt(Sheets("Settings").Range("dataCartSteering").Value)
    
    Dim delta As Integer
    delta = targetOffset - currentOffset
    
    ' Use L5/R5 for large steps, L1/R1 for fine
    Do While Abs(delta) >= 5
        If delta > 0 Then
            CartButton 5   ' R5
            delta = delta - 5
        Else
            CartButton 1   ' L5
            delta = delta + 5
        End If
        Application.Wait Now + 1.1  ' wait for gradual servo step
    Loop
    
    Do While Abs(delta) >= 1
        If delta > 0 Then
            CartButton 4   ' R1
            delta = delta - 1
        Else
            CartButton 2   ' L1
            delta = delta + 1
        End If
        Application.Wait Now + 1.1
    Loop
    
    LogEvent "CART", "Steering set to offset " & targetOffset & Chr(176)
End Sub

' Stop cart gracefully
Public Sub CartStop()
    CartButton 11
    LogEvent "CART", "Cart stopped"
End Sub

' Start cart decay
Public Sub CartDecay()
    CartButton 8
    LogEvent "CART", "Cart decay started"
End Sub

' ============================================================
' Cart log retrieval
' ============================================================

' Poll /cartlog and append events to CartLog sheet
Public Sub PollCartLog()
    On Error GoTo ErrHandler
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/cartlog", False
    http.Send
    
    If http.Status <> 200 Then
        Exit Sub
    End If
    
    Dim response As String
    response = Trim(http.ResponseText)
    Set http = Nothing
    
    If response = "" Or response = "EMPTY" Then Exit Sub
    
    Dim ws As Worksheet
    Set ws = Sheets("CartLog")
    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1
    
    Dim lines() As String
    lines = Split(response, Chr(10))
    Dim i As Integer
    For i = 0 To UBound(lines)
        Dim line As String
        line = Trim(lines(i))
        If line <> "" Then
            Dim fields() As String
            fields = Split(line, ",")
            If UBound(fields) >= 2 Then
                ws.Cells(nextRow, 1).Value = fields(0)  ' HH:MM:SS
                ws.Cells(nextRow, 2).Value = fields(1)  ' S/T/X
                ws.Cells(nextRow, 3).Value = fields(2)  ' value
                nextRow = nextRow + 1
            End If
        End If
    Next i
    Exit Sub
ErrHandler:
    LogEvent "UTILS", "PollCartLog error: " & Err.Description
End Sub

' Start continuous cart log polling (every 10 seconds)
Public Sub StartCartLogPolling()
    PollCartLog
    Application.OnTime Now + TimeValue("00:00:10"), "StartCartLogPolling"
End Sub

' Stop cart log polling
Public Sub StopCartLogPolling()
    On Error Resume Next
    Application.OnTime Now + TimeValue("00:00:10"), "StartCartLogPolling", , False
End Sub

' ============================================================
' JSON helper (shared — also used by Camera module)
' ============================================================

' Parse a single field value from simple JSON
Public Function ParseJsonField(ByVal json As String, ByVal field As String) As String
    On Error GoTo ErrHandler
    Dim searchStr As String
    searchStr = """" & field & """:"
    Dim pos As Long
    pos = InStr(json, searchStr)
    If pos = 0 Then
        ParseJsonField = ""
        Exit Function
    End If
    pos = pos + Len(searchStr)
    Do While Mid(json, pos, 1) = " "
        pos = pos + 1
    Loop
    If Mid(json, pos, 1) = """" Then
        pos = pos + 1
        Dim endPos As Long
        endPos = InStr(pos, json, """")
        ParseJsonField = Mid(json, pos, endPos - pos)
    ElseIf Mid(json, pos, 1) = "[" Then
        Dim arrEnd As Long
        arrEnd = InStr(pos, json, "]")
        ParseJsonField = Mid(json, pos, arrEnd - pos + 1)
    Else
        Dim valEnd As Long
        valEnd = pos
        Do While valEnd <= Len(json) And InStr(",}", Mid(json, valEnd, 1)) = 0
            valEnd = valEnd + 1
        Loop
        ParseJsonField = Trim(Mid(json, pos, valEnd - pos))
    End If
    Exit Function
ErrHandler:
    ParseJsonField = ""
End Function

' ============================================================
' Logging (shared — called by all modules)
' ============================================================

Public Sub LogEvent(ByVal category As String, ByVal message As String)
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = Sheets("Log")
    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1
    ws.Cells(nextRow, 1).Value = Format(Now(), "YYYY-MM-DD HH:nn:ss")
    ws.Cells(nextRow, 2).Value = category
    ws.Cells(nextRow, 3).Value = message
End Sub
