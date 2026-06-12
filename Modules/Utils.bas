Attribute VB_Name = "Utils"
' ============================================================
' HyperLapse Cart  -  Utility Module
'
' PURPOSE
'   Shared helpers used by every other module. Roughly grouped:
'
'   ASTRONOMICAL TIMING
'     GetSunsetTime / GetSunriseTime  -  fetch from sunrise-sunset.org
'       and populate Settings named ranges (sunset, sunrise, civil dusk,
'       nautical dusk, astronomical dusk). One API call populates all.
'     CalculatePhaseTimes  -  convert sunset/sunrise into the 7 phase
'       boundary timestamps used by SequenceLoop.
'     GetCurrentPhase / PhaseLabel  -  runtime "what phase are we in?"
'
'   SHUTTER MATH
'     TvToSeconds / SecondsToTv  -  convert between CCAPI shutter strings
'       ("1/5000", "0.3", "20") and floating-point seconds.
'     CalcInterval  -  minimum safe interval between shots given a shutter.
'
'   CART ACTION HELPERS (called from Sequence.RunCartReplayStep)
'     CartButton, CartSetSpeed, CartSetSteering, CartStop, CartDecay
'     PollCartLog / StartCartLogPolling / StopCartLogPolling  -  pull the
'       Arduino''s high-speed cart event log into the CartLog sheet for
'       later post-processing into a replay plan.
'
'   SHARED PLUMBING
'     UpdateMonitor  -  refreshes the Monitor sheet from named ranges.
'     ParseJsonField  -  minimal JSON value extractor (used by Camera too).
'     LogEvent  -  append to the Log sheet. Called by every module.
' ============================================================

Option Explicit

' ============================================================
' Sunrise / Sunset API
' Free API  -  no key required
' https://api.sunrise-sunset.org/json?lat=&lng=&date=today&formatted=0
' Returns times in UTC  -  convert using dataUTCOffset named range
' ============================================================
' Module-level cache, populated by InitTvLookup
Private g_tvStrings()  As String   ' Canon-format strings, in camera's reported order
Private g_tvSeconds()  As Double   ' parallel array of float seconds for each
Private g_tvCount      As Long     ' number of valid entries
Private g_tvLoaded     As Boolean

' Get today's sunset time as Excel serial (local time).
'
' Day 18 (Workfront #55)  -  rewritten:
'   - Sun rise/set + all twilight phases computed LOCALLY via
'     Astro.bas FindSunCrossing.
'   - Moon rise/set times computed LOCALLY via Astro.bas
'     FindMoonCrossing. Validated against timeanddate.com to
'     within 2 minutes; api.sunrisesunset.io was 64 min off
'     and rejected.
'   - Zero internet dependency for either sun or moon. Operator
'     can prepare a shoot offline (closes part of #57).
'   - Same named ranges as before so downstream code unchanged.
'     Adds dataMoonriseTime / dataMoonsetTime.
'
' Returns sunset time on success, 0 on failure (e.g. polar
' regions on solstice where sun never crosses the target).
' ============================================================
' Shared dated-fire-time helper (single source of truth).
'
' The Plan's "Fires at" and "Commences" cells store TIME-OF-DAY only
' (no date). Every consumer must attach the shoot date the SAME way or
' the overnight timeline diverges. This is that one way:
'   baseDate  = the date on dataSunsetTime (the shoot-night anchor)
'   dayAnchor = earliest of the sunset clock and the plan-start clock
'   any clock earlier than dayAnchor belongs to the NEXT calendar day
'     (post-midnight fires + the end-of-shoot sunrise)
' Falls back to today's date if sun times are unset.
'
' planStartRaw: the first GP/WP clock value (used to widen dayAnchor so a
' plan that itself starts before sunset still anchors correctly). Pass 0
' if not known; sunset clock is then the sole anchor.
' ============================================================
Public Function DatedFireSerial(ByVal clockRaw As Double, _
                                 ByVal planStartRaw As Double) As Double
    Dim ss As Worksheet: Set ss = ThisWorkbook.Sheets("Settings")
    Dim sunsetRaw As Double: sunsetRaw = DateSerialOf(ss.Range("dataSunsetTime").value)
    Dim clk As Double: clk = clockRaw - Int(clockRaw)
    If sunsetRaw <= 0 Then
        DatedFireSerial = Int(Date) + clk          ' no shoot date: today
        Exit Function
    End If
    Dim baseDate As Double: baseDate = Int(sunsetRaw)
    Dim sunsetClock As Double: sunsetClock = sunsetRaw - Int(sunsetRaw)
    Dim dayAnchor As Double: dayAnchor = sunsetClock
    If planStartRaw > 0 Then
        Dim startClock As Double: startClock = planStartRaw - Int(planStartRaw)
        If startClock < dayAnchor Then dayAnchor = startClock
    End If
    DatedFireSerial = baseDate + clk
    If clk < dayAnchor Then DatedFireSerial = DatedFireSerial + 1#
End Function

Public Function DateSerialOf(ByVal v As Variant) As Double
    If IsDate(v) Then
        DateSerialOf = CDbl(CDate(v))
    ElseIf IsNumeric(v) Then
        DateSerialOf = CDbl(v)
    Else
        DateSerialOf = 0
    End If
End Function

Public Function GetSunsetTime() As Date
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = Sheets("Settings")

    ' Anchor date for the shoot. Future workfront #57 will read
    ' dataShootDate; for now default to today.
    Dim shootDate As Date
    shootDate = CDate(Int(Now()))    ' midnight today, local

    ' -"--"--"- Sun events  -  local computation -"--"--"--"--"--"--"--"--"--"--"--"--"--"--"--"--"--"--"--"--"--"-
    ' Standard altitudes:
    '   sunrise/sunset      -0.833- deg (atmospheric refraction)
    '   civil twilight      -6- deg
    '   nautical twilight   -12- deg
    '   astronomical twi.   -18- deg
    Dim sunriseT     As Date
    Dim sunsetT      As Date
    Dim civilDawn    As Date
    Dim civilDusk    As Date
    Dim nauticalDawn As Date
    Dim nauticalDusk As Date
    Dim astroDawn    As Date
    Dim astroDusk    As Date

    ' Evening (setting, dir=-1) events are TONIGHT (shootDate). Morning (rising,
    ' dir=+1) events - sunrise + the dawns - belong to the NEXT morning of the
    ' overnight shoot, so scan from tomorrow. Without this the morning values come
    ' back as TODAY's already-passed sunrise, which makes the dark window run
    ' backward and hangs the MW keypoint scan.
    Dim morningDate As Date
    morningDate = shootDate + 1#       ' tomorrow midnight (overnight shoot ends next morning)

    sunriseT = FindSunCrossing(morningDate, -0.833, 1)
    sunsetT = FindSunCrossing(shootDate, -0.833, -1)
    civilDawn = FindSunCrossing(morningDate, -6#, 1)
    civilDusk = FindSunCrossing(shootDate, -6#, -1)
    nauticalDawn = FindSunCrossing(morningDate, -12#, 1)
    nauticalDusk = FindSunCrossing(shootDate, -12#, -1)
    astroDawn = FindSunCrossing(morningDate, -18#, 1)
    astroDusk = FindSunCrossing(shootDate, -18#, -1)

    ws.Range("dataSunsetTime").value = sunsetT
    ws.Range("dataSunriseTime").value = sunriseT
    ws.Range("dataCivilDawn").value = civilDawn
    ws.Range("dataCivilDusk").value = civilDusk
    ws.Range("dataNauticalDusk").value = nauticalDusk
    ws.Range("dataAstroDusk").value = astroDusk

    LogEvent "UTILS", "Sun (local): rise=" & Format(sunriseT, "HH:nn") & _
             " set=" & Format(sunsetT, "HH:nn") & _
             " civDusk=" & Format(civilDusk, "HH:nn") & _
             " astroDusk=" & Format(astroDusk, "HH:nn")

    ' -"--"--"- Moon events  -  .io API (one or two calls) -"--"--"--"--"--"--"--"--"--"--"--"--"-
    FetchMoonTimesForNight shootDate

    GetSunsetTime = sunsetT
    Exit Function
ErrHandler:
    MsgBox "GetSunsetTime error: " & Err.Description
    LogEvent "UTILS", "GetSunsetTime error: " & Err.Description
    GetSunsetTime = 0
End Function

' ============================================================
' FetchMoonTimesForNight  (Day 18, fully local  -  no internet)
'
' Computes moonrise / moonset times for tonight's shoot envelope
' using Astro.bas FindMoonCrossing on the local Schlyter
' ephemeris. Validated Day 18 against timeanddate.com  -  local
' maths agreed within 2 minutes (1:07 vs 1:09 for Adelaide
' 25-May-2026), whereas api.sunrisesunset.io disagreed by 64
' minutes for the same instant. Local maths wins on accuracy
' AND removes the internet dependency.
'
' Scans the shoot envelope [sunsetTime, sunriseTime+1] for
' altitude-zero crossings:
'   moonrise = first rising crossing inside envelope
'   moonset  = first setting crossing AFTER moonrise (or after
'              sunset if moon was already up at sunset)
'
' Stores results in dataMoonriseTime / dataMoonsetTime. Either
' may be 0 if no crossing exists in the envelope.
' ============================================================
Public Sub FetchMoonTimesForNight(ByVal shootDate As Date)
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = Sheets("Settings")

    ' Read the shoot envelope set by sun events above
    Dim shootSunset As Date, shootSunrise As Date
    shootSunset = ws.Range("dataSunsetTime").value
    shootSunrise = ws.Range("dataSunriseTime").value
    ' If sunrise < sunset (typical: shoot crosses midnight), shift +24h
    If shootSunrise < shootSunset Then shootSunrise = shootSunrise + 1#

    ' Use altitude -0.5- deg as the horizon definition (matches the
    ' convention timeanddate.com and most almanacs use  -  moon's
    ' upper limb on the horizon, no refraction applied).
    Const MOON_HORIZON As Double = -0.5

    ' Find moonrise inside the shoot envelope.
    ' Scan starts at shootSunset, extends to shootSunrise.
    Dim chosenRise As Date
    chosenRise = FindMoonCrossing(shootSunset, MOON_HORIZON, 1)
    ' FindMoonCrossing scans 24h from its start  -  clamp to envelope
    If chosenRise > shootSunrise Then chosenRise = 0

    ' Find moonset. Start the scan from chosenRise if we got one,
    ' or from shootSunset if moon was already up (no rise in window).
    Dim setScanStart As Date
    If chosenRise > 0 Then
        setScanStart = chosenRise
    Else
        setScanStart = shootSunset
    End If

    Dim chosenSet As Date
    chosenSet = FindMoonCrossing(setScanStart, MOON_HORIZON, -1)
    ' Clamp: only accept moonset within reasonable window of envelope
    If chosenSet > shootSunrise + 0.5 Then chosenSet = 0

    ws.Range("dataMoonriseTime").value = chosenRise
    ws.Range("dataMoonsetTime").value = chosenSet

    LogEvent "UTILS", "Moon (local): rise=" & _
             IIf(chosenRise = 0, "(none in window)", Format(chosenRise, "HH:nn")) & _
             " set=" & _
             IIf(chosenSet = 0, "(none in window)", Format(chosenSet, "HH:nn"))
    Exit Sub
ErrHandler:
    LogEvent "UTILS", "FetchMoonTimesForNight error: " & Err.Description
End Sub

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
'   "1/5000")  -  that part was always correct. But >= 0.3 second
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
'   accepted shutter list there  -  anything in that list is guaranteed
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
    arr = mid$(resp, openPos, closePos - openPos)
    
    ' Each item in the array looks like  "1\/5000"  or  "20\""  or  "0\"5".
    ' Strategy: split on commas FIRST, then process each item:
    '   1. Trim whitespace
    '   2. Strip the outer wrapping quotes (the first and last char of each item
    '      are JSON's wrapping quotes, after Trim)
    '   3. Decode the JSON escapes (\/ -> /, \" -> ")
    ' This order matters  -  if we decode \" before stripping the wrappers, we
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
            s = mid$(s, 2, Len(s) - 2)
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
    ' Camera unreachable or unparseable response  -  fall back to the
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
    
    ' Canon seconds form  -  replace the embedded/trailing " with "."
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

' Public conversion API  -  drop-in replacement for the previous
' TvToSeconds. Accepts whatever Canon format the camera reported,
' returns float seconds.
Public Function TvToSeconds(ByVal tvStr As String) As Double
    TvToSeconds = ParseCanonTv(tvStr)
End Function

' Public conversion API  -  return the Canon-format string nearest to
' the requested exposure in seconds. Picks from the lookup populated
' at startup. If InitTvLookup hasn't been called yet, calls it now
' (lazy init) so callers don't need to think about ordering.
Public Function SecondsToTv(ByVal secs As Double) As String
    If Not g_tvLoaded Then InitTvLookup
    
    If g_tvCount = 0 Then
        ' Total failure  -  return something the camera will at least accept
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
' g_tvStrings is in the camera's reported order, which is slow --' fast
' (e.g. "30""", "25""", "20""", ..., "1/4000", "1/5000", ...). Therefore:
'   direction = +1  --'  one step SLOWER (more light, brighter exposure)
'   direction = -1  --'  one step FASTER (less light, darker exposure)
'
' Returns the new Tv string, or "" if at the wall in the requested
' direction. Callers use the empty-string return to detect "knob pinned,
' switch to the other knob"  -  see AdjustExposureByLuminance in Camera.bas.
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
        ' currentTv not in the ability list  -  find the closest by seconds.
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
    ' g_tvStrings is ordered slow --' fast (e.g. 30", 25", ..., 1/4000, 1/5000).
    ' To go SLOWER (direction = +1) we move to an EARLIER index;
    ' to go FASTER (direction = -1) we move to a LATER index.
    ' Subtract, don't add  -  the natural reading of "+1 = next array slot"
    ' gives the wrong physical direction here. Caught in Session B
    ' validation run, May 2026: Tv was walking 1/5000 --' 1/6400 --' 1/8000 ...
    ' (getting faster) when feedback wanted slower for an under-exposed
    ' indoor frame.
    newIdx = idx - direction
    If newIdx < 0 Or newIdx > g_tvCount - 1 Then
        NextTv = ""             ' at the wall  -  caller switches knobs
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
'   Tv 1/5000  (0.0002s) --' ceiling(0.0002 + 1.5) = ceiling(1.5)  = 2s
'   Tv 1/8     (0.125s)  --' ceiling(0.125 + 1.5)  = ceiling(1.625) = 2s
'   Tv 1"      (1.0s)    --' ceiling(1.0 + 1.5)    = ceiling(2.5)   = 3s
'   Tv 17"     (17s)     --' ceiling(17 + 1.5)     = ceiling(18.5)  = 19s
'   Tv 20"     (20s)     --' ceiling(20 + 1.5)     = ceiling(21.5)  = 22s
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
' Phase timing  -  all times relative to sunset
' ============================================================

' Calculate phase start/end times from sunset time
' Offsets in minutes relative to sunset (negative = before sunset)
Public Sub CalculatePhaseTimes()
    Dim sunsetTime As Date
    sunsetTime = Sheets("Settings").Range("dataSunsetTime").value
    
    If sunsetTime = 0 Then
        MsgBox "Sunset time not set - run GetSunsetTime() first", vbExclamation
        Exit Sub
    End If
    
    Dim ws As Worksheet
    Set ws = Sheets("Settings")
    
    ' Phase 1 start  -  fixed at 16:00
    ws.Range("dataPhase1Start").value = CDate(Int(Now()) + TimeValue("16:00:00"))
    
    ' Phase 2a  -  sunset minus 45 minutes (shutter starts slowing)
    ws.Range("dataPhase2aStart").value = sunsetTime - (45 / 1440)
    
    ' Phase 2b  -  sunset plus 20 minutes (ISO starts climbing)
    ws.Range("dataPhase2bStart").value = sunsetTime + (20 / 1440)
    
    ' Phase 3  -  sunset plus 60 minutes (full night settings)
    ws.Range("dataPhase3Start").value = sunsetTime + (60 / 1440)
    
    ' Phase 4a  -  get tomorrow's sunrise minus 90 minutes
    Dim sunriseTime As Date
    sunriseTime = Sheets("Settings").Range("dataSunriseTime").value
    ws.Range("dataPhase4aStart").value = sunriseTime - (90 / 1440)
    
    ' Phase 4b  -  sunrise minus 45 minutes
    ws.Range("dataPhase4bStart").value = sunriseTime - (45 / 1440)
    
    ' Phase 5  -  sunrise time
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
        Case 1:  PhaseLabel = "Phase 1  -  Daytime"
        Case 22: PhaseLabel = "Phase 2a  -  Shutter transition"
        Case 23: PhaseLabel = "Phase 2b  -  ISO ramp"
        Case 3:  PhaseLabel = "Phase 3  -  Full night"
        Case 4:  PhaseLabel = "Phase 4  -  Pre-sunrise"
        Case 5:  PhaseLabel = "Phase 5  -  Daytime"
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
    response = Trim(http.responseText)
    Set http = Nothing
    
    If response = "" Or response = "EMPTY" Then Exit Sub
    
    Dim ws As Worksheet
    Set ws = Sheets("CartLog")
    Dim NextRow As Long
    NextRow = ws.Cells(ws.rows.count, 1).End(xlUp).row + 1
    
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
                ws.Cells(NextRow, 1).value = fields(0)  ' HH:MM:SS
                ws.Cells(NextRow, 2).value = fields(1)  ' S/T/X
                ws.Cells(NextRow, 3).value = fields(2)  ' value
                NextRow = NextRow + 1
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
' JSON helpers (shared  -  also used by Camera module)
' ============================================================

' Escape a value for safe inclusion inside a JSON string literal.
' Required for Canon's seconds-symbol Tv values (e.g. "20""" / "0""5")
' which contain literal " characters that must be \"-escaped before
' going into a request body.
Public Function JsonEscape(ByVal s As String) As String
    Dim out As String
    out = Replace(s, "\", "\\")          ' must come first  -  escapes existing backslashes
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
    Do While mid(json, pos, 1) = " "
        pos = pos + 1
    Loop
    If mid(json, pos, 1) = """" Then
        pos = pos + 1
        Dim endPos As Long
        endPos = InStr(pos, json, """")
        ParseJsonField = mid(json, pos, endPos - pos)
    ElseIf mid(json, pos, 1) = "[" Then
        Dim arrEnd As Long
        arrEnd = InStr(pos, json, "]")
        ParseJsonField = mid(json, pos, arrEnd - pos + 1)
    Else
        Dim valEnd As Long
        valEnd = pos
        Do While valEnd <= Len(json) And InStr(",}", mid(json, valEnd, 1)) = 0
            valEnd = valEnd + 1
        Loop
        ParseJsonField = Trim(mid(json, pos, valEnd - pos))
    End If
    Exit Function
ErrHandler:
    ParseJsonField = ""
End Function

' ============================================================
' Logging (shared  -  called by all modules)
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

    ' Force columns 1-3 to Text BEFORE writing so a message starting with
    ' =, +, - or @ cannot parse as a formula and throw 1004 (build-lesson 2).
    ws.Columns(1).NumberFormat = "@"
    ws.Columns(2).NumberFormat = "@"
    ws.Columns(3).NumberFormat = "@"

    Dim NextRow As Long
    NextRow = ws.Cells(ws.rows.count, 1).End(xlUp).row + 1
    ws.Cells(NextRow, 1).value = Format(Now(), "yyyy-mm-dd hh:nn:ss")
    ws.Cells(NextRow, 2).value = category
    ws.Cells(NextRow, 3).value = message

    ' Never leak a swallowed write error to the caller (Err=1004 was being
    ' read by RunButton/RunStep as a macro failure).
    Err.Clear
    On Error GoTo 0
End Sub



