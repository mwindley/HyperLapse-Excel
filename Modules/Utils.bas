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
' Module-level cache, populated by InitTvLookup
Private g_tvStrings()  As String   ' Canon-format strings, in camera's reported order
Private g_tvSeconds()  As Double   ' parallel array of float seconds for each
Private g_tvCount      As Long     ' number of valid entries
Private g_tvLoaded     As Boolean

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
'
' BUG FIX (May 2026, session 2):
'   The R3's CCAPI uses Canon's display-format strings for shutter
'   values, not plain decimals. Sub-second exposures use "1/N" (e.g.
'   "1/5000") — that part was always correct. But >= 0.3 second
'   exposures use Canon's seconds-symbol notation, with a literal
'   double-quote standing for "seconds":
'
'       0.3 sec  ->  "0\"3"     (i.e. the 5-character string  0 " 3)
'       0.5 sec  ->  "0\"5"
'       1.0 sec  ->  "1\""
'       1.6 sec  ->  "1\"6"
'       4.0 sec  ->  "4\""
'       20  sec  ->  "20\""
'
'   Our previous code sent decimals like "0.5" and "20", which the
'   camera silently rejected with HTTP 400 Invalid Param. The shutter
'   stayed at the last accepted value (typically 1/6) all night, so
'   Phases 2b, 3, 4a all ran with wildly wrong exposure.
'
' APPROACH:
'   Rather than hard-code the format (fragile across Canon bodies),
'   query /ccapi/ver100/shooting/settings/tv at startup, parse the
'   "ability" array, and build a lookup. The R3 reports its full
'   accepted shutter list there — anything in that list is guaranteed
'   to work. InitTvLookup is called once from InitShoot. After that,
'   SecondsToTv picks the closest entry; TvToSeconds parses Canon's
'   format back to a Double for math.
' ============================================================



' Populate the Tv lookup from the camera. Call once from InitShoot,
' before any photo is taken. Falls back to a hard-coded list if the
' camera is unreachable, so the workbook still opens cleanly offline.
Public Sub InitTvLookup()
    On Error GoTo Fallback
    
    Dim resp As String
    resp = CameraGet("/ccapi/ver100/shooting/settings/tv")
    If LenB(resp) = 0 Then GoTo Fallback
    
    ' Find the ability array: ..."ability":[ ... ]
    Dim openPos As Long, closePos As Long
    openPos = InStr(resp, """ability"":[")
    If openPos = 0 Then GoTo Fallback
    openPos = openPos + Len("""ability"":[")
    closePos = InStr(openPos, resp, "]")
    If closePos = 0 Then GoTo Fallback
    
    Dim arr As String
    arr = Mid$(resp, openPos, closePos - openPos)
    
    ' Each item in the array looks like  "1\/5000"  or  "20\""  or  "0\"5".
    ' Strategy: split on commas FIRST, then process each item:
    '   1. Trim whitespace
    '   2. Strip the outer wrapping quotes (the first and last char of each item
    '      are JSON's wrapping quotes, after Trim)
    '   3. Decode the JSON escapes (\/ -> /, \" -> ")
    ' This order matters — if we decode \" before stripping the wrappers, we
    ' lose track of which " is structural and which is the seconds symbol.
    Dim items() As String
    items = Split(arr, ",")
    
    ReDim g_tvStrings(0 To UBound(items))
    ReDim g_tvSeconds(0 To UBound(items))
    
    Dim i As Long, n As Long
    n = 0
    For i = 0 To UBound(items)
        Dim s As String
        s = Trim$(items(i))
        
        ' Strip exactly one wrapping quote pair, if present
        If Len(s) >= 2 And Left$(s, 1) = Chr(34) And Right$(s, 1) = Chr(34) Then
            s = Mid$(s, 2, Len(s) - 2)
        End If
        
        ' Now decode JSON escapes inside the value
        s = Replace(s, "\/", "/")
        s = Replace(s, "\""", Chr(34))   ' \" -> "
        
        If LenB(s) > 0 And LCase$(s) <> "bulb" Then
            g_tvStrings(n) = s
            g_tvSeconds(n) = ParseCanonTv(s)
            n = n + 1
        End If
    Next i
    
    If n = 0 Then GoTo Fallback
    
    g_tvCount = n
    ReDim Preserve g_tvStrings(0 To n - 1)
    ReDim Preserve g_tvSeconds(0 To n - 1)
    g_tvLoaded = True
    
    LogEvent "UTILS", "Tv lookup populated from camera: " & n & " values"
    Exit Sub
    
Fallback:
    ' Camera unreachable or unparseable response — fall back to the
    ' hard-coded R3 list verified May 2026.
    BuildTvLookupFallback
    LogEvent "UTILS", "Tv lookup fallback used (" & g_tvCount & " values)"
End Sub

' Hard-coded R3 ability list captured 10 May 2026 from a real camera.
' Used only when the live query fails.
Private Sub BuildTvLookupFallback()
    Dim raw As Variant
    raw = Array( _
        "30""", "25""", "20""", "15""", "13""", "10""", "8""", "6""", _
        "5""", "4""", "3""2", "2""5", "2""", "1""6", "1""3", "1""", _
        "0""8", "0""6", "0""5", "0""4", "0""3", _
        "1/4", "1/5", "1/6", "1/8", "1/10", "1/13", "1/15", "1/20", _
        "1/25", "1/30", "1/40", "1/50", "1/60", "1/80", "1/100", _
        "1/125", "1/160", "1/200", "1/250", "1/320", "1/400", "1/500", _
        "1/640", "1/800", "1/1000", "1/1250", "1/1600", "1/2000", _
        "1/2500", "1/3200", "1/4000", "1/5000", "1/6400", "1/8000", _
        "1/10000", "1/12800", "1/16000", "1/32000", "1/64000")
    
    Dim n As Long
    n = UBound(raw) - LBound(raw) + 1
    ReDim g_tvStrings(0 To n - 1)
    ReDim g_tvSeconds(0 To n - 1)
    
    Dim i As Long
    For i = 0 To n - 1
        g_tvStrings(i) = CStr(raw(i + LBound(raw)))
        g_tvSeconds(i) = ParseCanonTv(g_tvStrings(i))
    Next i
    
    g_tvCount = n
    g_tvLoaded = True
End Sub

' Parse a Canon-format Tv string to seconds.
' Handles all three forms:
'   "1/5000"  -> 0.0002         (fractional)
'   "20"""    -> 20.0           (whole seconds; trailing " is the symbol)
'   "1""6"    -> 1.6            (decimal seconds; the " sits BETWEEN integer
'                                and decimal parts, e.g. "1"6" = "1.6")
Private Function ParseCanonTv(ByVal tvStr As String) As Double
    On Error GoTo BadInput
    Dim s As String
    s = Trim$(tvStr)
    
    If LenB(s) = 0 Then ParseCanonTv = 0: Exit Function
    
    ' Fractional form
    If InStr(s, "/") > 0 Then
        Dim parts() As String
        parts = Split(s, "/")
        ParseCanonTv = CDbl(parts(0)) / CDbl(parts(1))
        Exit Function
    End If
    
    ' Canon seconds form — replace the embedded/trailing " with "."
    ' "20""    -> "20."  -> 20.0
    ' "1""6"   -> "1.6"  -> 1.6
    ' "0""5"   -> "0.5"  -> 0.5
    Dim withDot As String
    withDot = Replace(s, Chr(34), ".")
    
    ' Trim trailing dot (from whole-seconds case)
    If Right$(withDot, 1) = "." Then withDot = Left$(withDot, Len(withDot) - 1)
    
    ParseCanonTv = CDbl(withDot)
    Exit Function
    
BadInput:
    LogEvent "UTILS", "ParseCanonTv: bad input [" & tvStr & "] " & Err.Description
    ParseCanonTv = 0
End Function

' Public conversion API — drop-in replacement for the previous
' TvToSeconds. Accepts whatever Canon format the camera reported,
' returns float seconds.
Public Function TvToSeconds(ByVal tvStr As String) As Double
    TvToSeconds = ParseCanonTv(tvStr)
End Function

' Public conversion API — return the Canon-format string nearest to
' the requested exposure in seconds. Picks from the lookup populated
' at startup. If InitTvLookup hasn't been called yet, calls it now
' (lazy init) so callers don't need to think about ordering.
Public Function SecondsToTv(ByVal secs As Double) As String
    If Not g_tvLoaded Then InitTvLookup
    
    If g_tvCount = 0 Then
        ' Total failure — return something the camera will at least accept
        SecondsToTv = "1/5000"
        Exit Function
    End If
    
    Dim bestIdx   As Long
    Dim bestDelta As Double
    bestDelta = 1E+18
    bestIdx = 0
    
    Dim i As Long
    For i = 0 To g_tvCount - 1
        Dim delta As Double
        delta = Abs(g_tvSeconds(i) - secs)
        If delta < bestDelta Then
            bestDelta = delta
            bestIdx = i
        End If
    Next i
    
    SecondsToTv = g_tvStrings(bestIdx)
End Function

' Walk one step through the camera's Tv ability list.
'
' g_tvStrings is in the camera's reported order, which is slow → fast
' (e.g. "30""", "25""", "20""", ..., "1/4000", "1/5000", ...). Therefore:
'   direction = +1  →  one step SLOWER (more light, brighter exposure)
'   direction = -1  →  one step FASTER (less light, darker exposure)
'
' Returns the new Tv string, or "" if at the wall in the requested
' direction. Callers use the empty-string return to detect "knob pinned,
' switch to the other knob" — see AdjustExposureByLuminance in Camera.bas.
'
' Session B helper (May 2026). Replaces the predictive g_phase2a_steps /
' g_phase4b_steps tables; feedback walks one camera-Tv-step at a time.
Public Function NextTv(ByVal currentTv As String, ByVal direction As Integer) As String
    If Not g_tvLoaded Then InitTvLookup
    If g_tvCount = 0 Then NextTv = "": Exit Function
    
    Dim idx As Long: idx = -1
    Dim i As Long
    For i = 0 To g_tvCount - 1
        If g_tvStrings(i) = currentTv Then idx = i: Exit For
    Next i
    
    If idx < 0 Then
        ' currentTv not in the ability list — find the closest by seconds.
        ' This can happen if the operator set Tv to something the camera
        ' accepts but our cached list doesn't have an exact-string match
        ' for (e.g. case differences, whitespace).
        Dim secs As Double
        secs = TvToSeconds(currentTv)
        Dim bestDelta As Double: bestDelta = 1E+18
        For i = 0 To g_tvCount - 1
            Dim d As Double: d = Abs(g_tvSeconds(i) - secs)
            If d < bestDelta Then bestDelta = d: idx = i
        Next i
        If idx < 0 Then NextTv = "": Exit Function
    End If
    
    Dim newIdx As Long
    ' g_tvStrings is ordered slow → fast (e.g. 30", 25", ..., 1/4000, 1/5000).
    ' To go SLOWER (direction = +1) we move to an EARLIER index;
    ' to go FASTER (direction = -1) we move to a LATER index.
    ' Subtract, don't add — the natural reading of "+1 = next array slot"
    ' gives the wrong physical direction here. Caught in Session B
    ' validation run, May 2026: Tv was walking 1/5000 → 1/6400 → 1/8000 ...
    ' (getting faster) when feedback wanted slower for an under-exposed
    ' indoor frame.
    newIdx = idx - direction
    If newIdx < 0 Or newIdx > g_tvCount - 1 Then
        NextTv = ""             ' at the wall — caller switches knobs
    Else
        NextTv = g_tvStrings(newIdx)
    End If
End Function

' ============================================================
' Interval calculation
' ============================================================

' Calculate shooting interval from shutter speed.
'
' SESSION B RULE (May 2026): interval = ceiling(Tv + 1.5 seconds).
' The +1.5s budget covers read-out + write-buffer + CCAPI roundtrip + a
' small margin. ceiling() rounds up to the next whole second because
' Application.OnTime's resolution is effectively whole seconds anyway.
'
' Examples:
'   Tv 1/5000  (0.0002s) → ceiling(0.0002 + 1.5) = ceiling(1.5)  = 2s
'   Tv 1/8     (0.125s)  → ceiling(0.125 + 1.5)  = ceiling(1.625) = 2s
'   Tv 1"      (1.0s)    → ceiling(1.0 + 1.5)    = ceiling(2.5)   = 3s
'   Tv 17"     (17s)     → ceiling(17 + 1.5)     = ceiling(18.5)  = 19s
'   Tv 20"     (20s)     → ceiling(20 + 1.5)     = ceiling(21.5)  = 22s
'
' Replaces the previous "max(2.0, shutter+2.0)" rule. The new rule
' produces faster cadence in the short-exposure tail (2s for everything
' under 0.5s, was the same; 2s for 0.125s, was 2s; 3s for 1s, was 3s)
' and is more honest about the actual time needed for longer exposures.
'
' Ceiling implemented as -Int(-x) to avoid pulling in WorksheetFunction.
Public Function CalcInterval(ByVal tvStr As String) As Double
    Dim shutterSecs As Double
    shutterSecs = TvToSeconds(tvStr)
    CalcInterval = -Int(-(shutterSecs + 1.5))
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
    nextRow = ws.Cells(ws.Rows.count, 1).End(xlUp).row + 1
    
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
' JSON helpers (shared — also used by Camera module)
' ============================================================

' Escape a value for safe inclusion inside a JSON string literal.
' Required for Canon's seconds-symbol Tv values (e.g. "20""" / "0""5")
' which contain literal " characters that must be \"-escaped before
' going into a request body.
Public Function JsonEscape(ByVal s As String) As String
    Dim out As String
    out = Replace(s, "\", "\\")          ' must come first — escapes existing backslashes
    out = Replace(out, Chr(34), "\""")   ' " -> \"
    out = Replace(out, vbTab, "\t")
    out = Replace(out, vbCr, "\r")
    out = Replace(out, vbLf, "\n")
    JsonEscape = out
End Function

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

' Append a row to the Log sheet.
'
' Each row: timestamp | category | message.
'
' BUG FIX (May 2026, session 2): the timestamp was being stored as the
' string "YYYY-MM-DD HH:nn:ss" but Excel auto-detected it as a date and
' reformatted it according to the user's locale (e.g. "10/05/2026 11:50",
' losing the seconds). We now force column A to text format so Excel
' stores exactly what we write. Set once per call (cheap; Excel doesn't
' do anything if it's already correct).
Public Sub LogEvent(ByVal category As String, ByVal message As String)
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = Sheets("Log")
    
    ws.Columns(1).NumberFormat = "@"   ' force text — preserve seconds
    
    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.count, 1).End(xlUp).row + 1
    ws.Cells(nextRow, 1).value = Format(Now(), "yyyy-mm-dd hh:nn:ss")
    ws.Cells(nextRow, 2).value = category
    ws.Cells(nextRow, 3).value = message
End Sub



