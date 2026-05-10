Attribute VB_Name = "Utils"
' ============================================================
' HyperLapse Cart — Utility Module
'
' PURPOSE
'   Shared helpers used by every other module. Roughly grouped:
'
'   ASTRONOMICAL TIMING
'     GetSunsetTime / GetSunriseTime — fetch from sunrise-sunset.org
'       and populate Settings named ranges (sunset, sunrise, civil dusk,
'       nautical dusk, astronomical dusk). One API call populates all.
'     CalculatePhaseTimes — convert sunset/sunrise into the 7 phase
'       boundary timestamps used by SequenceLoop.
'     GetCurrentPhase / PhaseLabel — runtime "what phase are we in?"
'
'   SHUTTER MATH
'     TvToSeconds / SecondsToTv — convert between CCAPI shutter strings
'       ("1/5000", "0.3", "20") and floating-point seconds.
'     CalcInterval — minimum safe interval between shots given a shutter.
'
'   CART ACTION HELPERS (called from Sequence.RunCartReplayStep)
'     CartButton, CartSetSpeed, CartSetSteering, CartStop, CartDecay
'     PollCartLog / StartCartLogPolling / StopCartLogPolling — pull the
'       Arduino''s high-speed cart event log into the CartLog sheet for
'       later post-processing into a replay plan.
'
'   SHARED PLUMBING
'     UpdateMonitor — refreshes the Monitor sheet from named ranges.
'     ParseJsonField — minimal JSON value extractor (used by Camera too).
'     LogEvent — append to the Log sheet. Called by every module.
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
    lat = Sheets("Settings").Range("dataLatitude").value
    lng = Sheets("Settings").Range("dataLongitude").value
    utcOffset = Sheets("Settings").Range("dataUTCOffset").value
    
    Dim url As String
    Dim dateStr As String
    dateStr = Year(Now()) & "-" & Right("0" & Month(Now()), 2) & "-" & Right("0" & Day(Now()), 2)
    url = "https://api.sunrise-sunset.org/json?lat=" & lat & _
          "&lng=" & lng & "&date=" & dateStr & "&formatted=0"
    
    Dim http As Object
    'Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    'http.Open "GET", url, False
    'http.Send
    
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    'http.SetAutoProxySetting 1   ' use IE/system proxy settings
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
    'utcTime = CDate(Left(sunsetStr, 19))  ' "2026-05-09 08:23:00"
    utcTime = CDate(Replace(Left(sunsetStr, 19), "T", " "))
    
    ' Convert UTC to local time
    Dim localTime As Date
    localTime = utcTime + (utcOffset / 24)
    
    ' Store sunset
    Sheets("Settings").Range("dataSunsetTime").value = localTime
    
    ' Parse and store all twilight phases from same response
    Dim ws As Worksheet
    Set ws = Sheets("Settings")
    
    Dim fields(5) As String
    Dim names(5) As String
    fields(0) = "sunrise"
    fields(1) = "civil_twilight_begin"
    fields(2) = "civil_twilight_end"
    fields(3) = "nautical_twilight_end"
    fields(4) = "astronomical_twilight_end"
    names(0) = "dataSunriseTime"
    names(1) = "dataCivilDawn"
    names(2) = "dataCivilDusk"
    names(3) = "dataNauticalDusk"
    names(4) = "dataAstroDusk"
    
    Dim k As Integer
    For k = 0 To 4
        Dim fStr As String
        fStr = ParseJsonField(response, fields(k))
        If fStr <> "" Then
            Dim fUTC As Date
            fUTC = CDate(Replace(Left(fStr, 19), "T", " "))
            Dim fLocal As Date
            fLocal = fUTC + (utcOffset / 24)
            ws.Range(names(k)).value = fLocal
        End If
    Next k
    
    LogEvent "UTILS", "Sunset: " & Format(localTime, "HH:nn:ss") & _
             " Civil dusk: " & Format(ws.Range("dataCivilDusk").value, "HH:nn:ss") & _
             " Astro dark: " & Format(ws.Range("dataAstroDusk").value, "HH:nn:ss")
    GetSunsetTime = localTime
    Exit Function
ErrHandler:
    MsgBox "GetSunsetTime error: " & Err.Description
    LogEvent "UTILS", "GetSunsetTime error: " & Err.Description
    
    GetSunsetTime = 0
End Function

' Get today's sunrise time as Excel serial (local time)
Public Function GetSunriseTime() As Date
    ' Sunrise is now populated by GetSunsetTime() from the same API call
    ' Just read from named range
    Dim t As Date
    t = Sheets("Settings").Range("dataSunriseTime").value
    If t = 0 Then
        ' Not set yet - call GetSunsetTime which populates all times
        GetSunsetTime
        t = Sheets("Settings").Range("dataSunriseTime").value
    End If
    GetSunriseTime = t
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
                     "1/800", "1/640", "1/500", "1/400", "1/320", _
                     "1/250", "1/200", "1/160", "1/125", "1/100", _
                     "1/80", "1/60", "1/50", "1/40", "1/30", _
                     "1/25", "1/20", "1/15", "1/13", "1/10", _
                     "1/8", "1/6", "1/5", "1/4", "0.3", _
                     "0.4", "0.5", "0.6", "0.8", "1", _
                     "1.3", "1.6", "2", "2.5", "3", _
                     "4", "5", "6", "8", "10", _
                     "13", "15", "20", "25", "30")
    
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
        CalcInterval = 2#
    Else
        CalcInterval = shutterSecs + 2#
    End If
End Function

' ============================================================
' Phase timing — all times relative to sunset
' ============================================================

' Calculate phase start/end times from sunset time
' Offsets in minutes relative to sunset (negative = before sunset)
Public Sub CalculatePhaseTimes()
    Dim sunsetTime As Date
    sunsetTime = Sheets("Settings").Range("dataSunsetTime").value
    
    If sunsetTime = 0 Then
        MsgBox "Sunset time not set — run GetSunsetTime() first", vbExclamation
        Exit Sub
    End If
    
    Dim ws As Worksheet
    Set ws = Sheets("Settings")
    
    ' Phase 1 start — fixed at 16:00
    ws.Range("dataPhase1Start").value = CDate(Int(Now()) + TimeValue("16:00:00"))
    
    ' Phase 2a — sunset minus 45 minutes (shutter starts slowing)
    ws.Range("dataPhase2aStart").value = sunsetTime - (45 / 1440)
    
    ' Phase 2b — sunset plus 20 minutes (ISO starts climbing)
    ws.Range("dataPhase2bStart").value = sunsetTime + (20 / 1440)
    
    ' Phase 3 — sunset plus 60 minutes (full night settings)
    ws.Range("dataPhase3Start").value = sunsetTime + (60 / 1440)
    
    ' Phase 4a — get tomorrow's sunrise minus 90 minutes
    Dim sunriseTime As Date
    sunriseTime = Sheets("Settings").Range("dataSunriseTime").value
    ws.Range("dataPhase4aStart").value = sunriseTime - (90 / 1440)
    
    ' Phase 4b — sunrise minus 45 minutes
    ws.Range("dataPhase4bStart").value = sunriseTime - (45 / 1440)
    
    ' Phase 5 — sunrise time
    ws.Range("dataPhase5Start").value = sunriseTime
    
    LogEvent "UTILS", "Phase times calculated from sunset " & Format(sunsetTime, "HH:nn:ss")
End Sub

' Get current phase number (1-5) based on current time
Public Function GetCurrentPhase() As Integer
    Dim ws As Worksheet
    Set ws = Sheets("Settings")
    Dim t As Date
    t = Now()
    
    If t >= ws.Range("dataPhase5Start").value Then
        GetCurrentPhase = 5
    ElseIf t >= ws.Range("dataPhase4bStart").value Then
        GetCurrentPhase = 4   ' 4b
    ElseIf t >= ws.Range("dataPhase4aStart").value Then
        GetCurrentPhase = 4   ' 4a
    ElseIf t >= ws.Range("dataPhase3Start").value Then
        GetCurrentPhase = 3
    ElseIf t >= ws.Range("dataPhase2bStart").value Then
        GetCurrentPhase = 23  ' 2b (23 = phase 2, sub b)
    ElseIf t >= ws.Range("dataPhase2aStart").value Then
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
    ws.Range("monTime").value = Format(Now(), "HH:nn:ss")
    ws.Range("monPhase").value = PhaseLabel(GetCurrentPhase())
    
    ' Camera settings
    'ws.Range("monTv").value = Sheets("Settings").Range("dataCurrentTv").value
    ws.Range("monTv").NumberFormat = "@"
    ws.Range("monTv").value = "'" & Sheets("Settings").Range("dataCurrentTv").value
    
    ws.Range("monISO").value = Sheets("Settings").Range("dataCurrentISO").value
    ws.Range("monAv").value = Sheets("Settings").Range("dataCurrentAv").value
    ws.Range("monLuminance").value = Sheets("Settings").Range("dataLuminance").value
    ws.Range("monShotCount").value = Sheets("Settings").Range("dataShotCount").value
    
    ' Gimbal
    ws.Range("monGimbalYaw").value = Sheets("Settings").Range("dataGimbalYaw").value
    ws.Range("monGimbalPitch").value = Sheets("Settings").Range("dataGimbalPitch").value
    
    ' Cart
    ws.Range("monCartSpeed").value = Sheets("Settings").Range("dataCartSpeed").value
    ws.Range("monCartSteering").value = Sheets("Settings").Range("dataCartSteering").value
    ws.Range("monCartVoltage").value = Sheets("Settings").Range("dataCartVoltage").value
    
    ' Interval
    Dim tvStr As String
    tvStr = Sheets("Settings").Range("dataCurrentTv").value
    ws.Range("monInterval").value = Format(CalcInterval(tvStr), "0.0") & "s"
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
    currentSpeed = Sheets("Settings").Range("dataCartSpeed").value
    
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
    currentOffset = CInt(Sheets("Settings").Range("dataCartSteering").value)
    
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
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).row + 1
    
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
                ws.Cells(nextRow, 1).value = fields(0)  ' HH:MM:SS
                ws.Cells(nextRow, 2).value = fields(1)  ' S/T/X
                ws.Cells(nextRow, 3).value = fields(2)  ' value
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
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).row + 1
    ws.Cells(nextRow, 1).value = Format(Now(), "YYYY-MM-DD HH:nn:ss")
    ws.Cells(nextRow, 2).value = category
    ws.Cells(nextRow, 3).value = message
End Sub
