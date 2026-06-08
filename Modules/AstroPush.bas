Attribute VB_Name = "AstroPush"
' ============================================================
' HyperLapse Cart                     AstroPush module (Day 17, Workfront #50)
'
' PURPOSE
'   Pushes today's astro keypoint positions to the cart's
'   /settings/astropos endpoint. The cart stores them and
'   serves them via /gimbal/showastro and /gimbal/snapvar
'   (Gimbal Recon screen).
'
' WHAT GETS PUSHED
'   Sun rise:  yaw/pitch (azimuth + altitude at dataSunriseTime)
'   Sun set:   yaw/pitch (azimuth + altitude at dataSunsetTime)
'   MW rise:   first moment in dark window where MW core alt > 0
'   MW mid:    time of max MW core altitude within dark window
'   MW end:    last moment in dark window where MW core alt > 0
'   Moon:      cubic fitted over the dark window (astroDusk..darkEnd),
'              same as MW (#55 closed Day 24 pt B). No horizon gating:
'              below-horizon stretches yield steep-down pitch the gimbal
'              clamps; preview shows it; operator owns shootability.
'
' FRAME
'   Yaw values pushed are EARTH FRAME (real-world azimuth, 0         =N).
'   Cart applies its own cart-heading correction at command time
'   (under Ry=Cy shortcut today; will use BNO offset post-#40).
'   This module does NOT subtract dataCartHeading.
'
' DARK WINDOW
'   Start = dataAstroDusk (astronomical dusk, sky truly dark)
'   End   = dataPhase4aStart (proxy for astronomical dawn until
'           Workfront #56 lands).
'   MW rise/mid/end are intersected with this window.
' ============================================================

Option Explicit

' Step size for MW dark-window scan (minutes).
' 5 minutes is fine-grained enough for ~1-degree yaw precision.
Private Const MW_SCAN_STEP_MIN As Double = 5

Public Sub PushAstroToCart()
    LogEvent "ASTROPUSH", "=== PushAstroToCart ==="

    ' --- 1. Read required Settings -----------------------------------------
    Dim setSheet As Worksheet
    Set setSheet = ThisWorkbook.Sheets("Settings")

    Dim sunriseTime As Date, sunsetTime As Date
    Dim astroDusk As Date, darkEnd As Date
    Dim arduinoIP As String

    sunriseTime = setSheet.Range("dataSunriseTime").value
    sunsetTime = setSheet.Range("dataSunsetTime").value
    astroDusk = setSheet.Range("dataAstroDusk").value
    darkEnd = setSheet.Range("dataPhase4aStart").value
    arduinoIP = CStr(setSheet.Range("dataArduinoIP").value)

    ' Workaround for #57 (shoot-date anchor not yet implemented).
    If darkEnd < astroDusk Then
        darkEnd = darkEnd + 1#
        LogEvent "ASTROPUSH", "darkEnd shifted +24h (workaround #57)"
    End If

    If sunriseTime = 0 Or sunsetTime = 0 Then
        LogEvent "ASTROPUSH", "Sun times missing - run Get Sunset Time first"
        MsgBox "Sunset/sunrise times not set. Click 'Get Sunset Time' first.", _
               vbExclamation
        Exit Sub
    End If
    If astroDusk = 0 Or darkEnd = 0 Then
        LogEvent "ASTROPUSH", "Astro dusk or phase 4a missing - run Init Shoot first"
        MsgBox "Astronomical dusk / phase 4a not set. Run Init Shoot first.", _
               vbExclamation
        Exit Sub
    End If

    Dim deg As String
    deg = Chr(176)

    ' --- 2. Sun rise / sun set positions -----------------------------------
    Dim sunRiseAz As Double, sunRiseAlt As Double
    Dim sunSetAz As Double, sunSetAlt As Double
    GetSunAzAltAtTime sunriseTime, sunRiseAz, sunRiseAlt
    GetSunAzAltAtTime sunsetTime, sunSetAz, sunSetAlt
    LogEvent "ASTROPUSH", "Sun rise  yaw=" & Format(sunRiseAz, "0.0") & _
             " pitch=" & Format(sunRiseAlt, "0.0")
    LogEvent "ASTROPUSH", "Sun set   yaw=" & Format(sunSetAz, "0.0") & _
             " pitch=" & Format(sunSetAlt, "0.0")

    ' --- 3. MW rise / mid / end within dark window -------------------------
    Dim mwRiseTime As Date, mwMidTime As Date, mwEndTime As Date
    Dim mwRiseAz As Double, mwRiseAlt As Double
    Dim mwMidAz As Double, mwMidAlt As Double
    Dim mwEndAz As Double, mwEndAlt As Double
    Dim mwOK As Boolean
    mwOK = FindMWKeypoints(astroDusk, darkEnd, _
                            mwRiseTime, mwRiseAz, mwRiseAlt, _
                            mwMidTime, mwMidAz, mwMidAlt, _
                            mwEndTime, mwEndAz, mwEndAlt)

    If Not mwOK Then
        LogEvent "ASTROPUSH", "MW core never above horizon in dark window"
        MsgBox "Warning: MW core never above horizon in tonight's dark " & _
               "window. Sun keypoints will be pushed; MW slots will be " & _
               "left empty.", vbExclamation
    Else
        LogEvent "ASTROPUSH", "MW rise " & Format(mwRiseTime, "HH:nn") & _
                 " yaw=" & Format(mwRiseAz, "0.0") & " pitch=" & Format(mwRiseAlt, "0.0")
        LogEvent "ASTROPUSH", "MW mid  " & Format(mwMidTime, "HH:nn") & _
                 " yaw=" & Format(mwMidAz, "0.0") & " pitch=" & Format(mwMidAlt, "0.0")
        LogEvent "ASTROPUSH", "MW end  " & Format(mwEndTime, "HH:nn") & _
                 " yaw=" & Format(mwEndAz, "0.0") & " pitch=" & Format(mwEndAlt, "0.0")
    End If

    ' --- 3b. Moon rise / set within the shoot envelope ---------------------
    ' FetchMoonTimesForNight stores dataMoonriseTime / dataMoonsetTime
    ' (0 = no such crossing in the window). Push only the ones that exist.
    FetchMoonTimesForNight Int(Now())
    Dim moonRiseTime As Date, moonSetTime As Date
    moonRiseTime = setSheet.Range("dataMoonriseTime").value
    moonSetTime = setSheet.Range("dataMoonsetTime").value

    Dim moonRiseAz As Double, moonRiseAlt As Double
    Dim moonSetAz As Double, moonSetAlt As Double
    Dim haveMoonRise As Boolean, haveMoonSet As Boolean
    haveMoonRise = (moonRiseTime > 0)
    haveMoonSet = (moonSetTime > 0)

    If haveMoonRise Then
        GetMoonAzAltAtTime moonRiseTime, moonRiseAz, moonRiseAlt
        LogEvent "ASTROPUSH", "Moon rise " & Format(moonRiseTime, "HH:nn") & _
                 " yaw=" & Format(moonRiseAz, "0.0") & " pitch=" & Format(moonRiseAlt, "0.0")
    Else
        LogEvent "ASTROPUSH", "Moon rise: none in window"
    End If
    If haveMoonSet Then
        GetMoonAzAltAtTime moonSetTime, moonSetAz, moonSetAlt
        LogEvent "ASTROPUSH", "Moon set  " & Format(moonSetTime, "HH:nn") & _
                 " yaw=" & Format(moonSetAz, "0.0") & " pitch=" & Format(moonSetAlt, "0.0")
    Else
        LogEvent "ASTROPUSH", "Moon set: none in window"
    End If

    ' --- 4. Build URL ------------------------------------------------------
    Dim qs As String
    qs = "?sry=" & Format(sunRiseAz, "0.00") & _
         "&srp=" & Format(sunRiseAlt, "0.00") & _
         "&ssy=" & Format(sunSetAz, "0.00") & _
         "&ssp=" & Format(sunSetAlt, "0.00")
    If mwOK Then
        qs = qs & _
             "&mry=" & Format(mwRiseAz, "0.00") & _
             "&mrp=" & Format(mwRiseAlt, "0.00") & _
             "&mmy=" & Format(mwMidAz, "0.00") & _
             "&mmp=" & Format(mwMidAlt, "0.00") & _
             "&mey=" & Format(mwEndAz, "0.00") & _
             "&mep=" & Format(mwEndAlt, "0.00")
    End If
    If haveMoonRise Then
        qs = qs & "&mnry=" & Format(moonRiseAz, "0.00") & _
                  "&mnrp=" & Format(moonRiseAlt, "0.00")
    End If
    If haveMoonSet Then
        qs = qs & "&mnsy=" & Format(moonSetAz, "0.00") & _
                  "&mnsp=" & Format(moonSetAlt, "0.00")
    End If

    ' --- 5. HTTP push ------------------------------------------------------
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    Dim url As String
    url = arduinoIP & "/settings/astropos" & qs

    LogEvent "ASTROPUSH", "GET " & url

    On Error Resume Next
    http.Open "GET", url, False
    http.Send
    Dim sc As Long, respText As String
    sc = http.Status
    respText = CStr(http.responseText)
    On Error GoTo 0

    If sc = 200 Then
        LogEvent "ASTROPUSH", "OK " & respText
        Dim moonMsg As String
        If haveMoonRise Then moonMsg = moonMsg & "Moon rise: " & _
            Format(moonRiseAz, "0.0") & deg & " / " & Format(moonRiseAlt, "0.0") & deg & vbCrLf
        If haveMoonSet Then moonMsg = moonMsg & "Moon set:  " & _
            Format(moonSetAz, "0.0") & deg & " / " & Format(moonSetAlt, "0.0") & deg & vbCrLf
        If moonMsg = "" Then moonMsg = "Moon: no rise/set in tonight's window" & vbCrLf

        MsgBox "Astro pushed to cart." & vbCrLf & vbCrLf & _
               "Sun rise:  " & Format(sunRiseAz, "0.0") & deg & " / " & Format(sunRiseAlt, "0.0") & deg & vbCrLf & _
               "Sun set:   " & Format(sunSetAz, "0.0") & deg & " / " & Format(sunSetAlt, "0.0") & deg & vbCrLf & _
               IIf(mwOK, _
                  "MW rise:   " & Format(mwRiseAz, "0.0") & deg & " / " & Format(mwRiseAlt, "0.0") & deg & vbCrLf & _
                  "MW mid:    " & Format(mwMidAz, "0.0") & deg & " / " & Format(mwMidAlt, "0.0") & deg & vbCrLf & _
                  "MW end:    " & Format(mwEndAz, "0.0") & deg & " / " & Format(mwEndAlt, "0.0") & deg & vbCrLf, _
                  "MW: not above horizon in dark window" & vbCrLf) & _
               moonMsg, _
               vbInformation, "Push Astro to Cart"
    Else
        LogEvent "ASTROPUSH", "HTTP " & sc & " " & respText
        MsgBox "Push failed. HTTP " & sc & vbCrLf & respText, vbExclamation
    End If
End Sub
' ============================================================
' Push tracking paths (cubic polynomials) to cart
'
' Fits a single cubic polynomial y = a0 + a1*t + a2*t^2 + a3*t^3
' (and same for pitch) over the tracking window for each object,
' POSTs to /settings/trackpath?obj=<name>&ay0=...&ay3=...&ap0=...&ap3=...
'
' Time origin t=0 is the moment of push (cart records millis() at
' receipt). VBA fits with t in seconds from Now() at the start of
' this sub                     by the time HTTP arrives at cart, "now" has advanced
' ~50ms which is negligible.
'
' Windows:
'   sun:  sunset                     sunrise (next day if needed)
'   mw:   astroDusk                     darkEnd (next day if needed)
'   moon: astroDusk -> darkEnd (same window as mw)
' ============================================================
Public Sub PushTrackPathsToCart()
    LogEvent "TRACKPUSH", "=== PushTrackPathsToCart ==="

    Dim setSheet As Worksheet
    Set setSheet = ThisWorkbook.Sheets("Settings")

    Dim arduinoIP As String
    arduinoIP = CStr(setSheet.Range("dataArduinoIP").value)

    Dim sunsetTime As Date, sunriseTime As Date
    Dim astroDusk As Date, darkEnd As Date
    sunsetTime = setSheet.Range("dataSunsetTime").value
    sunriseTime = setSheet.Range("dataSunriseTime").value
    astroDusk = setSheet.Range("dataAstroDusk").value
    darkEnd = setSheet.Range("dataPhase4aStart").value

    If sunsetTime = 0 Or sunriseTime = 0 Or astroDusk = 0 Or darkEnd = 0 Then
        MsgBox "Sun / dusk / phase times not set. Run Init Shoot first.", vbExclamation
        Exit Sub
    End If

    ' Workaround #57: if end of window is before start, shift +24h.
    If sunriseTime < sunsetTime Then sunriseTime = sunriseTime + 1#
    If darkEnd < astroDusk Then darkEnd = darkEnd + 1#

    Dim t0 As Date
    t0 = Now()

    ' Sun: fit cubic over sunset                     sunrise window
    Dim sunOK As Boolean
    sunOK = FitAndPushTrackPath("sun", t0, sunsetTime, sunriseTime, arduinoIP)

    ' MW: fit cubic over dark window
    Dim mwOK As Boolean
    mwOK = FitAndPushTrackPath("mw", t0, astroDusk, darkEnd, arduinoIP)

    ' Moon: fit cubic over the SAME dark window as MW (#55 closed Day 24
    ' pt B). No horizon gating: if the moon is below the horizon for part
    ' or all of the window the cubic simply asks for a steep-down pitch,
    ' which the gimbal's own pitch limit clamps and preview makes visible.
    ' Operator owns plan shootability.
    Dim moonOK As Boolean
    moonOK = FitAndPushTrackPath("moon", t0, astroDusk, darkEnd, arduinoIP)

    Dim summary As String
    summary = "Sun:  " & IIf(sunOK, "pushed", "FAILED") & vbCrLf & _
              "MW:   " & IIf(mwOK, "pushed", "FAILED") & vbCrLf & _
              "Moon: " & IIf(moonOK, "pushed", "FAILED")
    MsgBox summary, vbInformation, "Push Track Paths to Cart"
End Sub

' Fit cubic + push for one object. Returns True if all segments pushed OK.
' Splits window into N segments, fits a cubic to each, pushes each as
' seg=0..N-1 (seg=0 resets the cart's per-object state).
Private Function FitAndPushTrackPath(ByVal objName As String, _
                                      ByVal t0 As Date, _
                                      ByVal winStart As Date, _
                                      ByVal winEnd As Date, _
                                      ByVal arduinoIP As String) As Boolean

    ' Number of segments per object. 4 is the cart's SRAM-imposed limit
    ' (TRACK_SEGS_MAX in firmware). With 3-hour segments over a 12-hour
    ' window the cubic still struggles near MW zenith          accuracy may
    ' degrade there; verify with CheckTrackFitResiduals.
    Const N_SEGMENTS As Long = 2

    ' Sample resolution within each segment.
    Const STEP_MIN As Double = 5
    Dim stepDays As Double
    stepDays = STEP_MIN / 1440#

    Dim winSpanDays As Double
    winSpanDays = winEnd - winStart
    Dim segSpanDays As Double
    segSpanDays = winSpanDays / N_SEGMENTS

    Dim allOK As Boolean
    allOK = True

    Dim segIdx As Long
    For segIdx = 0 To N_SEGMENTS - 1
        Dim segStart As Date, segEnd As Date
        segStart = winStart + segIdx * segSpanDays
        segEnd = winStart + (segIdx + 1) * segSpanDays

        ' Sample this segment
        Dim nSamples As Long
        nSamples = 0
        Dim t As Date
        For t = segStart To segEnd Step stepDays
            nSamples = nSamples + 1
        Next t
        If nSamples < 6 Then
            LogEvent "TRACKPUSH", objName & " seg " & segIdx & " too few samples"
            allOK = False
            Exit For
        End If

        ReDim ti(0 To nSamples - 1) As Double
        ReDim yi(0 To nSamples - 1) As Double
        ReDim PI(0 To nSamples - 1) As Double

        Dim i As Long, az As Double, alt As Double
        i = 0
        For t = segStart To segEnd Step stepDays
            ti(i) = (t - t0) * 86400#
            If objName = "sun" Then
                GetSunAzAltAtTime t, az, alt
            ElseIf objName = "mw" Then
                GetGCAzAltAtTime t, az, alt
            ElseIf objName = "moon" Then
                GetMoonAzAltAtTime t, az, alt
            Else
                FitAndPushTrackPath = False
                Exit Function
            End If
            yi(i) = az
            PI(i) = alt
            i = i + 1
        Next t

        ' Unwrap yaw within segment
        Dim k As Long
        For k = 1 To nSamples - 1
            Do While yi(k) - yi(k - 1) > 180
                yi(k) = yi(k) - 360
            Loop
            Do While yi(k) - yi(k - 1) < -180
                yi(k) = yi(k) + 360
            Loop
        Next k

        ' Freeze-yaw detection: if any sample in this segment has
        ' pitch > FREEZE_PITCH_THRESHOLD, the segment contains the
        ' zenith pass. Yaw becomes geometrically ill-defined there
        ' (large yaw motion for small sky motion). Use a constant
        ' yaw cubic (yaw_at_first_freeze_sample, 0, 0, 0) instead
        ' of fitting through the nonsense. Pitch cubic stays normal.
        Const FREEZE_PITCH_THRESHOLD As Double = 80
        Dim hasFreeze As Boolean
        Dim freezeYaw As Double
        hasFreeze = False
        Dim fk As Long
        For fk = 0 To nSamples - 1
            If PI(fk) > FREEZE_PITCH_THRESHOLD Then
                hasFreeze = True
                freezeYaw = yi(fk)
                Exit For
            End If
        Next fk

        ' Fit cubic
        Dim ay(0 To 3) As Double, ap(0 To 3) As Double
        If hasFreeze Then
            ay(0) = freezeYaw: ay(1) = 0: ay(2) = 0: ay(3) = 0
            LogEvent "TRACKPUSH", objName & " seg " & segIdx & _
                     " FREEZE yaw=" & Format(freezeYaw, "0.0")
        Else
            If Not FitCubic(ti, yi, ay) Then
                LogEvent "TRACKPUSH", objName & " seg " & segIdx & " yaw fit failed"
                allOK = False
                Exit For
            End If
        End If
        If Not FitCubic(ti, PI, ap) Then
            LogEvent "TRACKPUSH", objName & " seg " & segIdx & " pitch fit failed"
            allOK = False
            Exit For
        End If

        ' Push
        Dim ts As Double, te As Double
        ts = (segStart - t0) * 86400#
        te = (segEnd - t0) * 86400#
        Dim qs As String
        qs = "?obj=" & objName & "&seg=" & segIdx & _
             "&ts=" & ts & "&te=" & te & _
             "&ay0=" & ay(0) & "&ay1=" & ay(1) & "&ay2=" & ay(2) & "&ay3=" & ay(3) & _
             "&ap0=" & ap(0) & "&ap1=" & ap(1) & "&ap2=" & ap(2) & "&ap3=" & ap(3)
        ' Model B: on seg=0, send rt0 = the cubic's real-time t0 as
        ' epoch-ms. Cart evaluates the cubic at (real_now - rt0). MUST
        ' use the SAME epoch reference (UTC ms) as the /settings/realtime
        ' anchor the Execution UI hands in, or astro pointing will be off.
        If segIdx = 0 Then
            qs = qs & "&rt0=" & Format(DateToEpochMs(t0), "0")
        End If

        Dim http As Object
        Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
        Dim url As String
        url = arduinoIP & "/settings/trackpath" & qs

        On Error Resume Next
        http.Open "GET", url, False
        http.Send
        Dim sc As Long
        sc = http.Status
        On Error GoTo 0

        If sc <> 200 Then
            LogEvent "TRACKPUSH", objName & " seg " & segIdx & " HTTP " & sc
            allOK = False
            Exit For
        End If
        LogEvent "TRACKPUSH", objName & " seg " & segIdx & " pushed (ts=" & _
                 Format(ts, "0") & " te=" & Format(te, "0") & ")"
    Next segIdx

    FitAndPushTrackPath = allOK
End Function

' ============================================================
' Cubic least-squares fitter
'
' Solves min || y - (a0 + a1*t + a2*t^2 + a3*t^3) ||^2
' via the 4x4 normal equations:
'   [n      St    St2   St3 ] [a0]   [Sy   ]
'   [St     St2   St3   St4 ] [a1] = [Sty  ]
'   [St2    St3   St4   St5 ] [a2]   [St2y ]
'   [St3    St4   St5   St6 ] [a3]   [St3y ]
' Solved by Gaussian elimination with partial pivoting.
'
' Returns True on success, False if matrix is singular.
' ============================================================
Private Function FitCubic(ByRef ti() As Double, _
                           ByRef yi() As Double, _
                           ByRef coeff() As Double) As Boolean
    Dim n As Long
    n = UBound(ti) - LBound(ti) + 1
    If n < 4 Then
        FitCubic = False
        Exit Function
    End If

    ' Compute sums
    Dim S0 As Double, S1 As Double, S2 As Double, S3 As Double
    Dim S4 As Double, S5 As Double, S6 As Double
    Dim Sy As Double, Sty As Double, St2y As Double, St3y As Double
    Dim t As Double, y As Double, t2 As Double, t3 As Double
    Dim i As Long
    S0 = 0: S1 = 0: S2 = 0: S3 = 0: S4 = 0: S5 = 0: S6 = 0
    Sy = 0: Sty = 0: St2y = 0: St3y = 0
    For i = LBound(ti) To UBound(ti)
        t = ti(i)
        y = yi(i)
        t2 = t * t
        t3 = t2 * t
        S0 = S0 + 1
        S1 = S1 + t
        S2 = S2 + t2
        S3 = S3 + t3
        S4 = S4 + t2 * t2
        S5 = S5 + t3 * t2
        S6 = S6 + t3 * t3
        Sy = Sy + y
        Sty = Sty + t * y
        St2y = St2y + t2 * y
        St3y = St3y + t3 * y
    Next i

    ' Assemble augmented 4x5 matrix [M | b]
    Dim m(0 To 3, 0 To 4) As Double
    m(0, 0) = S0: m(0, 1) = S1: m(0, 2) = S2: m(0, 3) = S3: m(0, 4) = Sy
    m(1, 0) = S1: m(1, 1) = S2: m(1, 2) = S3: m(1, 3) = S4: m(1, 4) = Sty
    m(2, 0) = S2: m(2, 1) = S3: m(2, 2) = S4: m(2, 3) = S5: m(2, 4) = St2y
    m(3, 0) = S3: m(3, 1) = S4: m(3, 2) = S5: m(3, 3) = S6: m(3, 4) = St3y

    ' Gaussian elimination with partial pivoting
    Dim p As Long, k As Long, j As Long, maxAbs As Double, swap As Double
    Dim factor As Double
    For p = 0 To 3
        ' Find pivot row
        maxAbs = Abs(m(p, p))
        Dim pivotRow As Long
        pivotRow = p
        For k = p + 1 To 3
            If Abs(m(k, p)) > maxAbs Then
                maxAbs = Abs(m(k, p))
                pivotRow = k
            End If
        Next k
        If maxAbs < 0.0000000001 Then
            FitCubic = False
            Exit Function
        End If
        ' Swap rows if needed
        If pivotRow <> p Then
            For j = 0 To 4
                swap = m(p, j)
                m(p, j) = m(pivotRow, j)
                m(pivotRow, j) = swap
            Next j
        End If
        ' Eliminate below
        For k = p + 1 To 3
            factor = m(k, p) / m(p, p)
            For j = p To 4
                m(k, j) = m(k, j) - factor * m(p, j)
            Next j
        Next k
    Next p

    ' Back-substitute into caller's pre-sized array (no ReDim          caller
    ' passes fixed-size array, ReDim on that fires error 10).
    For p = 3 To 0 Step -1
        Dim s As Double
        s = m(p, 4)
        For j = p + 1 To 3
            s = s - m(p, j) * coeff(j)
        Next j
        coeff(p) = s / m(p, p)
    Next p

    FitCubic = True
End Function

' ============================================================
' MW core keypoint finder
'
' Walks dark window in MW_SCAN_STEP_MIN steps, records altitude
' at each sample. Returns rise = first sample with alt > 0,
' mid = sample with max alt, end = last sample with alt > 0.
'
' Yaw/pitch values returned are taken AT THE SAMPLE TIME, so
' MW rise pitch may be slightly positive (the first sample after
' the geometric horizon crossing) rather than exactly 0.
' Acceptable at 14mm wide-angle.
'
' Returns False if MW core never exceeds 0          within the window.
' ============================================================
Private Function FindMWKeypoints(ByVal darkStart As Date, _
                                  ByVal darkEnd As Date, _
                                  ByRef riseTime As Date, _
                                  ByRef riseAz As Double, _
                                  ByRef riseAlt As Double, _
                                  ByRef midTime As Date, _
                                  ByRef midAz As Double, _
                                  ByRef midAlt As Double, _
                                  ByRef endTime As Date, _
                                  ByRef endAz As Double, _
                                  ByRef endAlt As Double) As Boolean

    Dim stepDays As Double
    stepDays = MW_SCAN_STEP_MIN / 1440#   ' minutes to Excel-date fraction

    Dim t As Date, az As Double, alt As Double
    Dim haveRise As Boolean, haveAny As Boolean
    Dim maxAlt As Double
    haveRise = False
    haveAny = False
    maxAlt = -999#

    For t = darkStart To darkEnd Step stepDays
        GetGCAzAltAtTime t, az, alt
        If alt > 0 Then
            haveAny = True
            ' First above-horizon sample = rise
            If Not haveRise Then
                riseTime = t
                riseAz = az
                riseAlt = alt
                haveRise = True
            End If
            ' Track culmination
            If alt > maxAlt Then
                maxAlt = alt
                midTime = t
                midAz = az
                midAlt = alt
            End If
            ' Always update end                     last above-horizon sample
            endTime = t
            endAz = az
            endAlt = alt
        End If
    Next t

    FindMWKeypoints = haveAny
End Function

' ============================================================
' Diagnostic: dump cubic-fit residuals for piecewise fit
'
' Re-runs the same sampling + fitting as PushTrackPathsToCart
' (per-segment cubic) but instead of pushing, prints worst
' residual per segment, plus full sample dump.
'
' Usage from Immediate: CheckTrackFitResiduals "mw"  or  "sun"  or  "moon"
' ============================================================
Public Sub CheckTrackFitResiduals(ByVal objName As String)
    Const N_SEGMENTS As Long = 2
    Const STEP_MIN As Double = 5

    Dim setSheet As Worksheet
    Set setSheet = ThisWorkbook.Sheets("Settings")

    Dim sunsetTime As Date, sunriseTime As Date
    Dim astroDusk As Date, darkEnd As Date
    sunsetTime = setSheet.Range("dataSunsetTime").value
    sunriseTime = setSheet.Range("dataSunriseTime").value
    astroDusk = setSheet.Range("dataAstroDusk").value
    darkEnd = setSheet.Range("dataPhase4aStart").value

    If sunriseTime < sunsetTime Then sunriseTime = sunriseTime + 1#
    If darkEnd < astroDusk Then darkEnd = darkEnd + 1#

    Dim winStart As Date, winEnd As Date
    If objName = "sun" Then
        winStart = sunsetTime
        winEnd = sunriseTime
    ElseIf objName = "mw" Then
        winStart = astroDusk
        winEnd = darkEnd
    ElseIf objName = "moon" Then
        winStart = astroDusk
        winEnd = darkEnd
    Else
        Debug.Print "bad obj"
        Exit Sub
    End If

    Dim t0 As Date
    t0 = Now()
    Dim stepDays As Double
    stepDays = STEP_MIN / 1440#
    Dim winSpanDays As Double
    winSpanDays = winEnd - winStart
    Dim segSpanDays As Double
    segSpanDays = winSpanDays / N_SEGMENTS

    Debug.Print "=== Piecewise fit residuals for " & objName & " (N=" & N_SEGMENTS & ") ==="
    Debug.Print "Window: " & Format(winStart, "HH:nn") & " -> " & Format(winEnd, "HH:nn") & _
                " (" & Format(winSpanDays * 24, "0.0") & " hrs)"
    Debug.Print "Seg size: " & Format(segSpanDays * 24 * 60, "0") & " min"
    Debug.Print ""

    Dim segIdx As Long
    Dim globalWorstY As Double, globalWorstP As Double
    globalWorstY = 0: globalWorstP = 0

    For segIdx = 0 To N_SEGMENTS - 1
        Dim segStart As Date, segEnd As Date
        segStart = winStart + segIdx * segSpanDays
        segEnd = winStart + (segIdx + 1) * segSpanDays

        Dim nSamples As Long
        nSamples = 0
        Dim t As Date
        For t = segStart To segEnd Step stepDays
            nSamples = nSamples + 1
        Next t

        ReDim ti(0 To nSamples - 1) As Double
        ReDim yi(0 To nSamples - 1) As Double
        ReDim PI(0 To nSamples - 1) As Double

        Dim i As Long, az As Double, alt As Double
        i = 0
        For t = segStart To segEnd Step stepDays
            ti(i) = (t - t0) * 86400#
            If objName = "sun" Then
                GetSunAzAltAtTime t, az, alt
            ElseIf objName = "mw" Then
                GetGCAzAltAtTime t, az, alt
            ElseIf objName = "moon" Then
                GetMoonAzAltAtTime t, az, alt
            End If
            yi(i) = az
            PI(i) = alt
            i = i + 1
        Next t

        Dim k As Long
        For k = 1 To nSamples - 1
            Do While yi(k) - yi(k - 1) > 180
                yi(k) = yi(k) - 360
            Loop
            Do While yi(k) - yi(k - 1) < -180
                yi(k) = yi(k) + 360
            Loop
        Next k

        Dim ay(0 To 3) As Double, ap(0 To 3) As Double
        If Not FitCubic(ti, yi, ay) Then Debug.Print "  seg " & segIdx & " yaw fail": GoTo NextSeg
        If Not FitCubic(ti, PI, ap) Then Debug.Print "  seg " & segIdx & " pit fail": GoTo NextSeg

        Dim worstY As Double, worstP As Double
        worstY = 0: worstP = 0
        For i = 0 To nSamples - 1
            Dim t2 As Double, t3 As Double, fy As Double, fp As Double
            t2 = ti(i) * ti(i)
            t3 = t2 * ti(i)
            fy = ay(0) + ay(1) * ti(i) + ay(2) * t2 + ay(3) * t3
            fp = ap(0) + ap(1) * ti(i) + ap(2) * t2 + ap(3) * t3
            Dim dy As Double, dp As Double
            dy = yi(i) - fy
            dp = PI(i) - fp
            If Abs(dy) > Abs(worstY) Then worstY = dy
            If Abs(dp) > Abs(worstP) Then worstP = dp
        Next i
        Debug.Print "  seg " & segIdx & " " & Format(segStart, "HH:nn") & "-" & _
                    Format(segEnd, "HH:nn") & "  worstY=" & Format(worstY, "0.00") & _
                    "           worstP=" & Format(worstP, "0.00") & "         "
        If Abs(worstY) > Abs(globalWorstY) Then globalWorstY = worstY
        If Abs(worstP) > Abs(globalWorstP) Then globalWorstP = worstP
NextSeg:
    Next segIdx

    Debug.Print ""
    Debug.Print "GLOBAL worst yaw:   " & Format(globalWorstY, "0.00") & "         "
    Debug.Print "GLOBAL worst pitch: " & Format(globalWorstP, "0.00") & "         "
End Sub

' ============================================================
' Diagnostic: dump per-sample yaw RATE (deg/sec) for one object
'
' For each 5-min sample in the dark window (MW) or sunset-sunrise
' window (sun), prints time, pitch, yaw, and yaw rate = (yaw[i+1]
' - yaw[i]) / (t[i+1] - t[i]).
'
' Helps see when yaw goes nonsensically fast (zenith pass).
'
' Usage: CheckTrackYawRate "mw"
' ============================================================
Public Sub CheckTrackYawRate(ByVal objName As String)
    Const STEP_MIN As Double = 5

    Dim setSheet As Worksheet
    Set setSheet = ThisWorkbook.Sheets("Settings")

    Dim sunsetTime As Date, sunriseTime As Date
    Dim astroDusk As Date, darkEnd As Date
    sunsetTime = setSheet.Range("dataSunsetTime").value
    sunriseTime = setSheet.Range("dataSunriseTime").value
    astroDusk = setSheet.Range("dataAstroDusk").value
    darkEnd = setSheet.Range("dataPhase4aStart").value
    If sunriseTime < sunsetTime Then sunriseTime = sunriseTime + 1#
    If darkEnd < astroDusk Then darkEnd = darkEnd + 1#

    Dim winStart As Date, winEnd As Date
    If objName = "sun" Then
        winStart = sunsetTime: winEnd = sunriseTime
    ElseIf objName = "mw" Then
        winStart = astroDusk: winEnd = darkEnd
    Else
        Debug.Print "bad obj": Exit Sub
    End If

    Dim stepDays As Double
    stepDays = STEP_MIN / 1440#

    Debug.Print "=== Yaw rate dump for " & objName & " ==="
    Debug.Print "time      pitch  yaw     yaw_rate_deg_per_sec  yaw_rate_deg_per_min"
    Debug.Print "------------------------------------------------------------"

    Dim prevYaw As Double, prevTime As Date, havePrev As Boolean
    havePrev = False
    Dim t As Date, az As Double, alt As Double
    For t = winStart To winEnd Step stepDays
        If objName = "sun" Then
            GetSunAzAltAtTime t, az, alt
        Else
            GetGCAzAltAtTime t, az, alt
        End If
        ' Unwrap relative to previous yaw
        If havePrev Then
            Do While az - prevYaw > 180
                az = az - 360
            Loop
            Do While az - prevYaw < -180
                az = az + 360
            Loop
            Dim dt As Double
            dt = (t - prevTime) * 86400#
            Dim rate As Double
            rate = (az - prevYaw) / dt
            Debug.Print Format(t, "HH:nn") & "  " & _
                        Format(alt, "0.0") & "  " & _
                        Format(az, "0.0") & "  " & _
                        Format(rate, "0.0000") & "  " & _
                        Format(rate * 60, "0.00")
        Else
            Debug.Print Format(t, "HH:nn") & "  " & _
                        Format(alt, "0.0") & "  " & _
                        Format(az, "0.0") & "  --  --"
        End If
        prevYaw = az
        prevTime = t
        havePrev = True
    Next t
End Sub

' ============================================================
' Diagnostic: try single-cubic-with-freeze fit
'
' Excludes samples where pitch > pitchThreshold (e.g. 80    ) from
' the yaw fit. Fits one cubic to the remaining yaw samples and
' a separate cubic to all pitch samples. Reports worst residual
' on the non-freeze samples for yaw, and on all samples for pitch.
'
' Usage: CheckTrackFreezeFit "mw", 80
' ============================================================
Public Sub CheckTrackFreezeFit(ByVal objName As String, _
                                ByVal pitchThreshold As Double)
    Const STEP_MIN As Double = 5

    Dim setSheet As Worksheet
    Set setSheet = ThisWorkbook.Sheets("Settings")
    Dim sunsetTime As Date, sunriseTime As Date
    Dim astroDusk As Date, darkEnd As Date
    sunsetTime = setSheet.Range("dataSunsetTime").value
    sunriseTime = setSheet.Range("dataSunriseTime").value
    astroDusk = setSheet.Range("dataAstroDusk").value
    darkEnd = setSheet.Range("dataPhase4aStart").value
    If sunriseTime < sunsetTime Then sunriseTime = sunriseTime + 1#
    If darkEnd < astroDusk Then darkEnd = darkEnd + 1#

    Dim winStart As Date, winEnd As Date
    If objName = "sun" Then
        winStart = sunsetTime: winEnd = sunriseTime
    ElseIf objName = "mw" Then
        winStart = astroDusk: winEnd = darkEnd
    Else
        Debug.Print "bad obj": Exit Sub
    End If

    Dim t0 As Date
    t0 = Now()
    Dim stepDays As Double
    stepDays = STEP_MIN / 1440#

    ' Pre-count samples
    Dim nAll As Long, nNonFreeze As Long
    nAll = 0: nNonFreeze = 0
    Dim t As Date, az As Double, alt As Double
    For t = winStart To winEnd Step stepDays
        If objName = "sun" Then
            GetSunAzAltAtTime t, az, alt
        Else
            GetGCAzAltAtTime t, az, alt
        End If
        nAll = nAll + 1
        If alt <= pitchThreshold Then nNonFreeze = nNonFreeze + 1
    Next t

    If nNonFreeze < 6 Then
        Debug.Print "Too few non-freeze samples (" & nNonFreeze & ")"
        Exit Sub
    End If

    ' Sample arrays
    ReDim tiAll(0 To nAll - 1) As Double
    ReDim yiAll(0 To nAll - 1) As Double
    ReDim piAll(0 To nAll - 1) As Double
    ReDim tiYaw(0 To nNonFreeze - 1) As Double
    ReDim yiYaw(0 To nNonFreeze - 1) As Double

    Dim iA As Long, iY As Long
    iA = 0: iY = 0
    Dim freezeStart As Date, freezeEnd As Date, haveFreeze As Boolean
    haveFreeze = False
    For t = winStart To winEnd Step stepDays
        If objName = "sun" Then
            GetSunAzAltAtTime t, az, alt
        Else
            GetGCAzAltAtTime t, az, alt
        End If
        tiAll(iA) = (t - t0) * 86400#
        yiAll(iA) = az
        piAll(iA) = alt
        If alt <= pitchThreshold Then
            tiYaw(iY) = tiAll(iA)
            yiYaw(iY) = az
            iY = iY + 1
        Else
            If Not haveFreeze Then
                freezeStart = t
                haveFreeze = True
            End If
            freezeEnd = t
        End If
        iA = iA + 1
    Next t

    ' Unwrap yaw across non-freeze samples          but since these may be
    ' disjoint with a gap, unwrap independently within each contiguous
    ' chunk. Simpler: walk all non-freeze, unwrap relative to previous.
    Dim k As Long
    For k = 1 To nNonFreeze - 1
        Do While yiYaw(k) - yiYaw(k - 1) > 180
            yiYaw(k) = yiYaw(k) - 360
        Loop
        Do While yiYaw(k) - yiYaw(k - 1) < -180
            yiYaw(k) = yiYaw(k) + 360
        Loop
    Next k

    ' Fit yaw cubic on non-freeze samples
    Dim ay(0 To 3) As Double
    If Not FitCubic(tiYaw, yiYaw, ay) Then
        Debug.Print "yaw fit fail": Exit Sub
    End If

    ' Fit pitch cubic on ALL samples (pitch behaves smoothly)
    Dim ap(0 To 3) As Double
    If Not FitCubic(tiAll, piAll, ap) Then
        Debug.Print "pitch fit fail": Exit Sub
    End If

    ' Compute worst residual on non-freeze yaw and on all pitch
    Dim worstY As Double, worstP As Double
    worstY = 0: worstP = 0
    Dim i As Long
    For i = 0 To nNonFreeze - 1
        Dim t2 As Double, t3 As Double, fy As Double, dy As Double
        t2 = tiYaw(i) * tiYaw(i)
        t3 = t2 * tiYaw(i)
        fy = ay(0) + ay(1) * tiYaw(i) + ay(2) * t2 + ay(3) * t3
        dy = yiYaw(i) - fy
        If Abs(dy) > Abs(worstY) Then worstY = dy
    Next i
    For i = 0 To nAll - 1
        Dim tp2 As Double, tp3 As Double, fp As Double, dp As Double
        tp2 = tiAll(i) * tiAll(i)
        tp3 = tp2 * tiAll(i)
        fp = ap(0) + ap(1) * tiAll(i) + ap(2) * tp2 + ap(3) * tp3
        dp = piAll(i) - fp
        If Abs(dp) > Abs(worstP) Then worstP = dp
    Next i

    Debug.Print "=== Single cubic + freeze for " & objName & " ==="
    Debug.Print "Window: " & Format(winStart, "HH:nn") & " -> " & Format(winEnd, "HH:nn")
    Debug.Print "Pitch threshold: " & pitchThreshold & "         "
    If haveFreeze Then
        Debug.Print "Freeze region: " & Format(freezeStart, "HH:nn") & " -> " & _
                    Format(freezeEnd, "HH:nn")
    Else
        Debug.Print "No freeze region (pitch never exceeded threshold)"
    End If
    Debug.Print "Samples: " & nAll & " total, " & nNonFreeze & " used for yaw fit"
    Debug.Print "Worst yaw residual (non-freeze): " & Format(worstY, "0.00") & "         "
    Debug.Print "Worst pitch residual (all):      " & Format(worstP, "0.00") & "         "
End Sub

' ============================================================
' Convert a VBA Date to epoch-ms (milliseconds since 1970-01-01).
'
' Model B (#57): rt0 sent to the cart must use the SAME epoch
' reference as the /settings/realtime anchor handed in by the
' Execution UI. Both should be UTC epoch-ms. This helper treats the
' Date as UTC: if the realtime anchor is also fed UTC epoch-ms, they
' agree and astro pointing is correct.
'
' NOTE: VBA Now()/Date is LOCAL time. If the realtime anchor is fed
' LOCAL epoch-ms instead, change BOTH consistently. The only hard
' requirement is that rt0 and the anchor share one convention          the
' cart just subtracts them, so a constant offset cancels as long as
' it's the same on both. (Kept simple: serial-date * day-ms.)
' ============================================================
Private Function DateToEpochMs(ByVal d As Date) As Double
    ' VBA serial date 0 = 1899-12-30. Unix epoch = 1970-01-01 =
    ' serial 25569. ms = (serial - 25569) * 86400 * 1000.
    DateToEpochMs = (CDbl(d) - 25569#) * 86400# * 1000#
End Function
