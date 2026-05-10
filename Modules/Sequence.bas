Attribute VB_Name = "Sequence"
' ============================================================
' HyperLapse Cart — Sequence Control Module
'
' PURPOSE
'   Orchestrates the unattended overnight shoot. From 4pm one afternoon
'   through to the following morning, this module drives the camera and
'   gimbal through 5 phases that span daytime → sunset → astronomical
'   night → sunrise → daytime, automatically adjusting shutter speed,
'   ISO, and gimbal pointing as conditions change.
'
'   This module owns the master timing loop (SequenceLoop) and decides
'   "what should happen now"; it delegates the "how" to:
'     - Camera.bas — CCAPI calls to the Canon R3
'     - Gimbal.bas — HTTP calls to the Arduino driving the DJI RS4 Pro
'     - Astro.bas  — sun and Milky Way angle calculations
'     - Utils.bas  — shared timing, JSON, and Arduino cart helpers
'
' PHASES
'   Phase 1  — Daytime (cart moving, 1/5000 ISO100)
'   Phase 2a — Sunset transition (shutter slows 1/5000 → 20s)
'   Phase 2b — ISO ramp (ISO 100 → 1600, luminance controlled)
'   Phase 3  — Full night (20s ISO1600, gimbal tracks Milky Way)
'   Phase 4a — Pre-sunrise ISO reverse (ISO 1600 → 100)
'   Phase 4b — Shutter reverse (20s → 1/5000)
'   Phase 5  — Daytime again
'
' USAGE
'   1. Set location, IPs and cart heading on Settings sheet
'   2. Run InitShoot to fetch sunset/sunrise times and init camera
'   3. Run StartSequence at 4pm — runs unattended until morning
'   4. Run StopSequence to halt at any time
'
' ARCHITECTURE
'   The loop is non-blocking. SequenceLoop is invoked via Application.OnTime
'   at each desired shot interval. Inside one invocation we:
'     - update Monitor sheet and Arduino heartbeat
'     - detect phase transitions (OnPhaseEnter — Bug 3 fix, May 2026)
'     - check the camera is safe to talk to (WaitForCamera — Bug 1 fix)
'     - run the active phase handler, which sets g_nextShotTime
'     - reschedule ourselves for g_nextShotTime
'   Excel never blocks; the workbook stays interactive between shots.
'
' RECENT FIXES (May 2026)
'   Bug 1 — WaitForCamera is now a function; callers gate on its return.
'   Bug 2 — StopSequence cancels using g_scheduledTime (the exact value
'           given to OnTime), not g_nextShotTime which can drift.
'   Bug 3 — Phase-entry hook OnPhaseEnter wires the GimbalTo* transitions
'           into the loop (they were previously orphaned).
'   Bug 5 — RunCartReplay split into StartCartReplay + RunCartReplayStep
'           with OnTime-driven scheduling (no longer blocks Excel).
' ============================================================

Option Explicit

' ── Sequence state ───────────────────────────────────────────
Private g_running       As Boolean
Private g_lastShotTime  As Date
Private g_nextShotTime  As Date     ' the time the NEXT loop wants to fire
Private g_scheduledTime As Date     ' the time actually passed to OnTime (must match
                                    ' exactly when cancelling — see StopSequence)
Private g_lastPhase     As Integer  ' previous phase, for phase-change detection
Private g_replayRow     As Long     ' next row to execute in cart replay (Bug 5 fix)

' Phase 2a shutter transition table
' Each entry: [shutter_string, seconds_value]
' Progresses from 1/5000 toward 20s over ~45 minutes
Private g_phase2a_steps As Variant

' Phase 4b shutter reverse table (same steps, reversed)
Private g_phase4b_steps As Variant

' ============================================================
' Initialisation
' ============================================================

' Run once before the shoot — fetches times, inits camera, calculates phases
Public Sub InitShoot()
    LogEvent "SEQ", "=== InitShoot ==="
    
    ' 1. Get sunrise/sunset times from API
    Dim sunsetTime As Date
    sunsetTime = GetSunsetTime()
    If sunsetTime = 0 Then
        MsgBox "Could not get sunset time — check internet connection." & Chr(10) & _
               "Set dataSunsetTime manually on Settings sheet.", vbExclamation
    End If
    
    Dim sunriseTime As Date
    sunriseTime = GetSunriseTime()
    
    ' 2. Calculate phase start times
    CalculatePhaseTimes
    
    ' 3. Generate astro table for planning
    GenerateGCTable
    
    ' 4. Initialise camera
    InitCamera
    
    ' 5. Build phase 2a shutter transition steps
    BuildPhase2aSteps
    
    ' 6. Update Monitor sheet
    UpdateMonitor
    
    LogEvent "SEQ", "InitShoot complete. Sunset: " & _
             Format(Sheets("Settings").Range("dataSunsetTime").value, "HH:nn:ss")
    
    MsgBox "Shoot initialised." & Chr(10) & _
           "Sunset: " & Format(Sheets("Settings").Range("dataSunsetTime").value, "HH:nn:ss") & Chr(10) & _
           "Sunrise: " & Format(Sheets("Settings").Range("dataSunriseTime").value, "HH:nn:ss") & Chr(10) & Chr(10) & _
           "Run StartSequence at 4:00pm.", vbInformation
End Sub

' Build the Phase 2a shutter transition steps
' Shutter progresses from 1/5000 to 20s over ~45 minutes
' Steps chosen to be valid CCAPI TV values
Private Sub BuildPhase2aSteps()
    g_phase2a_steps = Array( _
        "1/5000", "1/4000", "1/3200", "1/2500", "1/2000", _
        "1/1600", "1/1250", "1/1000", "1/800", "1/640", _
        "1/500", "1/400", "1/320", "1/250", "1/200", _
        "1/160", "1/125", "1/100", "1/80", "1/60", _
        "1/50", "1/40", "1/30", "1/25", "1/20", _
        "1/15", "1/13", "1/10", "1/8", "1/6", _
        "1/5", "1/4", "0.3", "0.5", "0.8", _
        "1", "1.3", "1.6", "2", "2.5", _
        "3", "4", "5", "6", "8", _
        "10", "13", "15", "20")
    
    ' Reverse for phase 4b
    Dim n As Integer
    n = UBound(g_phase2a_steps)
    ReDim g_phase4b_steps(n)
    Dim i As Integer
    For i = 0 To n
        g_phase4b_steps(i) = g_phase2a_steps(n - i)
    Next i
End Sub

' ============================================================
' Sequence start / stop
' ============================================================

Public Sub StartSequence()
    If g_running Then
        MsgBox "Sequence already running.", vbInformation
        Exit Sub
    End If
    
    If Not IsArray(g_phase2a_steps) Then BuildPhase2aSteps
    
    g_running = True
    g_lastShotTime = Now()
    g_nextShotTime = Now()
    g_lastPhase = 0          ' 0 ≠ any real phase, so first loop fires OnPhaseEnter
    
    Sheets("Settings").Range("dataSequenceRunning").value = "RUNNING"
    LogEvent "SEQ", "=== Sequence STARTED ==="
    
    ' Kick off the loop
    SequenceLoop
End Sub

' Stop the running sequence.
' BUG 2 FIX: Application.OnTime cancellation requires the EXACT same time value
' that was passed when the call was scheduled. We must therefore track that
' value in g_scheduledTime — g_nextShotTime can be mutated by phase handlers
' or WaitForCamera between schedule and cancel, breaking the cancel.
Public Sub StopSequence()
    g_running = False
    Sheets("Settings").Range("dataSequenceRunning").value = "STOPPED"
    LogEvent "SEQ", "=== Sequence STOPPED ==="
    
    ' Cancel the pending OnTime using the exact scheduled time.
    ' If no call is pending or the time has passed, this throws — swallow it.
    If g_scheduledTime <> 0 Then
        On Error Resume Next
        Application.OnTime g_scheduledTime, "SequenceLoop", , False
        On Error GoTo 0
    End If
End Sub

' ============================================================
' Main loop — fires at each shot interval
' ============================================================

' Main loop — fires once per shot interval via Application.OnTime.
'
' Each iteration:
'   1. Polls Arduino status, updates Monitor sheet, sends gimbal heartbeat.
'   2. Detects phase transitions and runs OnPhaseEnter once per change
'      (BUG 3 FIX — previously the GimbalToSunset/MilkyWay/Sunrise transitions
'      were defined but never called from anywhere).
'   3. Dispatches to the active phase handler.
'   4. Reschedules itself for g_nextShotTime — which the phase handler
'      (or WaitForCamera, Bug 1) has set to the desired next firing time.
Public Sub SequenceLoop()
    If Not g_running Then Exit Sub
    
    Dim phase As Integer
    phase = GetCurrentPhase()
    
    ' Update Monitor and send heartbeat every loop
    GetGimbalStatus
    UpdateMonitor
    GimbalHeartbeat
    
    ' BUG 3 FIX: detect phase transitions and run entry hook once per change.
    ' g_lastPhase is reset to 0 in StartSequence so the first loop always fires
    ' the entry hook for whatever phase we're starting in.
    If phase <> g_lastPhase Then
        OnPhaseEnter phase
        g_lastPhase = phase
    End If
    
    ' Execute current phase logic
    Select Case phase
        Case 1:  RunPhase1
        Case 22: RunPhase2a
        Case 23: RunPhase2b
        Case 3:  RunPhase3
        Case 4:  RunPhase4
        Case 5:  RunPhase5
    End Select
    
    ' Schedule next loop. Capture g_scheduledTime so StopSequence can cancel it.
    If g_running Then
        g_scheduledTime = g_nextShotTime
        Application.OnTime g_scheduledTime, "SequenceLoop"
    End If
End Sub

' Phase-entry hook — fires once when the active phase number changes.
' Position the gimbal for the upcoming phase and log the transition.
' BUG 3 FIX — wires the previously-orphaned GimbalTo* subs into the loop.
Private Sub OnPhaseEnter(ByVal newPhase As Integer)
    LogEvent "SEQ", "=== Entering " & PhaseLabel(newPhase) & " ==="
    Select Case newPhase
        Case 22                       ' Phase 2a — point at the setting sun
            GimbalToSunset
        Case 3                        ' Phase 3 — track the Milky Way galactic centre
            GimbalToMilkyWay
        Case 4                        ' Phase 4 — point at where the sun will rise
            GimbalToSunrise
        ' Phases 1, 23, and 5 don't need a gimbal repoint — they inherit
        ' the position set by the preceding entry.
    End Select
End Sub

' ============================================================
' Phase handlers
' ============================================================

' Phase 1 — Daytime: 1/5000, ISO 100, 2s interval, cart moving
Private Sub RunPhase1()
    ' Ensure correct camera settings (in case of restart)
    If Range("dataCurrentTv").value <> "1/5000" Then SetShutterSpeed "1/5000"
    If Range("dataCurrentISO").value <> "100" Then SetISO "100"
    
    ' Take photo
    TakePhoto
    g_lastShotTime = Now()
    
    ' Next shot in 2 seconds
    g_nextShotTime = Now() + (2# / 86400#)
    
    LogEvent "SEQ", "Ph1 shot " & Range("dataShotCount").value
End Sub

' Phase 2a — Shutter transition: 1/5000 → 20s, ISO stays 100
' Shutter advances one step every N shots based on phase duration
Private Sub RunPhase2a()
    Dim phase2aStart As Date
    Dim phase2bStart As Date
    phase2aStart = Sheets("Settings").Range("dataPhase2aStart").value
    phase2bStart = Sheets("Settings").Range("dataPhase2bStart").value
    
    ' How far through Phase 2a are we? (0.0 to 1.0)
    Dim elapsed As Double
    Dim total   As Double
    elapsed = (Now() - phase2aStart) * 86400#   ' seconds
    total = (phase2bStart - phase2aStart) * 86400#
    Dim progress As Double
    progress = elapsed / total
    If progress > 1 Then progress = 1
    If progress < 0 Then progress = 0
    
    ' Target step index in phase2a_steps array
    Dim targetIdx As Integer
    targetIdx = CInt(progress * UBound(g_phase2a_steps))
    If targetIdx > UBound(g_phase2a_steps) Then targetIdx = UBound(g_phase2a_steps)
    
    Dim targetTv As String
    targetTv = CStr(g_phase2a_steps(targetIdx))
    
    ' Set shutter if changed
    If Range("dataCurrentTv").value <> targetTv Then
        SetShutterSpeed targetTv
    End If
    
    ' ISO stays 100 throughout 2a
    If Range("dataCurrentISO").value <> "100" Then SetISO "100"
    
    ' Take photo
    ' Wait until camera is safe to query (exposure + write buffer).
    ' If not safe, WaitForCamera has already pushed g_nextShotTime out;
    ' bail out and let SequenceLoop reschedule us.
    Dim shutterSecs As Double
    shutterSecs = TvToSeconds(targetTv)
    If Not WaitForCamera(shutterSecs) Then Exit Sub
    
    TakePhoto
    g_lastShotTime = Now()
    
    ' Calculate next interval
    Dim interval As Double
    interval = CalcInterval(targetTv)
    g_nextShotTime = g_lastShotTime + (interval / 86400#)
    
    LogEvent "SEQ", "Ph2a Tv=" & targetTv & " interval=" & Format(interval, "0.0") & _
             "s shot=" & Range("dataShotCount").value
End Sub

' Phase 2b — ISO ramp: shutter fixed at 20s, ISO 100→1600 via luminance
Private Sub RunPhase2b()
    ' Ensure shutter is at 20s
    If Range("dataCurrentTv").value <> "20" Then SetShutterSpeed "20"
    
    ' Wait for camera to finish exposure before any CCAPI queries.
    ' If not safe, bail and let SequenceLoop reschedule.
    If Not WaitForCamera(20#) Then Exit Sub
    
    ' Get luminance of last shot and adjust ISO if needed
    AdjustExposureByLuminance
    
    ' Take next photo
    TakePhoto
    g_lastShotTime = Now()
    
    ' Fixed 22s interval
    g_nextShotTime = g_lastShotTime + (22# / 86400#)
    
    LogEvent "SEQ", "Ph2b ISO=" & Range("dataCurrentISO").value & _
             " Lum=" & Range("dataLuminance").value & _
             " shot=" & Range("dataShotCount").value
End Sub

' Phase 3 — Full night: 20s ISO1600, gimbal tracks Milky Way
Private Sub RunPhase3()
    ' Ensure max night settings
    If Range("dataCurrentTv").value <> "20" Then SetShutterSpeed "20"
    If Range("dataCurrentISO").value <> "1600" Then SetISO "1600"
    
    ' Wait for camera. Bail if previous 20s exposure isn't done yet.
    If Not WaitForCamera(20#) Then Exit Sub
    
    ' Update gimbal to track galactic centre
    Dim cartHeading As Double
    cartHeading = Sheets("Settings").Range("dataCartHeading").value
    
    Dim gcYaw As Double, gcPitch As Double
    If GetGCGimbalAngles(Now(), cartHeading, gcYaw, gcPitch) Then
        ' GC is above horizon — track it
        ' Move slowly — only if more than 0.1° change needed
        Dim currentYaw   As Double
        Dim currentPitch As Double
        currentYaw = Sheets("Settings").Range("dataGimbalYaw").value
        currentPitch = Sheets("Settings").Range("dataGimbalPitch").value
        
        If Abs(gcYaw - currentYaw) > 0.1 Or Abs(gcPitch - currentPitch) > 0.1 Then
            ' Move over the interval period so camera doesn't catch movement
            GimbalPosition gcYaw, 0#, gcPitch, 20#
        End If
    End If
    
    ' Take photo
    TakePhoto
    g_lastShotTime = Now()
    g_nextShotTime = g_lastShotTime + (22# / 86400#)
    
    LogEvent "SEQ", "Ph3 GC yaw=" & Format(gcYaw, "0.1") & _
             " pitch=" & Format(gcPitch, "0.1") & _
             " shot=" & Range("dataShotCount").value
End Sub

' Phase 4 — Pre-sunrise: ISO reverse then shutter reverse
Private Sub RunPhase4()
    Dim phase4aStart As Date
    Dim phase4bStart As Date
    phase4aStart = Sheets("Settings").Range("dataPhase4aStart").value
    phase4bStart = Sheets("Settings").Range("dataPhase4bStart").value
    
    If Now() < phase4bStart Then
        ' Phase 4a — ISO reverse: 1600 → 100, shutter stays 20s
        RunPhase4a
    Else
        ' Phase 4b — Shutter reverse: 20s → 1/5000
        RunPhase4b
    End If
End Sub

Private Sub RunPhase4a()
    ' Shutter fixed at 20s
    If Range("dataCurrentTv").value <> "20" Then SetShutterSpeed "20"
    
    If Not WaitForCamera(20#) Then Exit Sub
    
    ' Use luminance to step ISO down (same as 2b but in reverse)
    ' Luminance will be higher as dawn approaches — ISO will step down naturally
    AdjustExposureByLuminance
    
    TakePhoto
    g_lastShotTime = Now()
    g_nextShotTime = g_lastShotTime + (22# / 86400#)
    
    LogEvent "SEQ", "Ph4a ISO=" & Range("dataCurrentISO").value & _
             " Lum=" & Range("dataLuminance").value & _
             " shot=" & Range("dataShotCount").value
End Sub

Private Sub RunPhase4b()
    ' ISO should be at 100 by now
    If Range("dataCurrentISO").value <> "100" Then SetISO "100"
    
    ' Mirror of Phase 2a — shutter speeds back up using reverse step table
    Dim phase4bStart As Date
    Dim phase5Start  As Date
    phase4bStart = Sheets("Settings").Range("dataPhase4bStart").value
    phase5Start = Sheets("Settings").Range("dataPhase5Start").value
    
    Dim elapsed  As Double
    Dim total    As Double
    elapsed = (Now() - phase4bStart) * 86400#
    total = (phase5Start - phase4bStart) * 86400#
    Dim progress As Double
    progress = elapsed / total
    If progress > 1 Then progress = 1
    If progress < 0 Then progress = 0
    
    Dim targetIdx As Integer
    targetIdx = CInt(progress * UBound(g_phase4b_steps))
    If targetIdx > UBound(g_phase4b_steps) Then targetIdx = UBound(g_phase4b_steps)
    
    Dim targetTv As String
    targetTv = CStr(g_phase4b_steps(targetIdx))
    
    If Range("dataCurrentTv").value <> targetTv Then
        SetShutterSpeed targetTv
    End If
    
    Dim shutterSecs As Double
    shutterSecs = TvToSeconds(targetTv)
    If Not WaitForCamera(shutterSecs) Then Exit Sub
    
    TakePhoto
    g_lastShotTime = Now()
    
    Dim interval As Double
    interval = CalcInterval(targetTv)
    g_nextShotTime = g_lastShotTime + (interval / 86400#)
    
    LogEvent "SEQ", "Ph4b Tv=" & targetTv & " interval=" & Format(interval, "0.0") & _
             "s shot=" & Range("dataShotCount").value
End Sub

' Phase 5 — Daytime again: back to 1/5000 ISO100
Private Sub RunPhase5()
    If Range("dataCurrentTv").value <> "1/5000" Then SetShutterSpeed "1/5000"
    If Range("dataCurrentISO").value <> "100" Then SetISO "100"
    
    TakePhoto
    g_lastShotTime = Now()
    g_nextShotTime = g_lastShotTime + (2# / 86400#)
    
    LogEvent "SEQ", "Ph5 shot " & Range("dataShotCount").value
End Sub

' ============================================================
' Camera timing safety
' ============================================================

' Returns True when it is safe to send CCAPI commands to the camera, i.e.
'   now() >= last_shot_time + exposure_seconds + write_buffer
' Returns False if not yet safe — and as a side effect pushes g_nextShotTime
' out to the safe time so SequenceLoop's tail will reschedule us correctly.
'
' BUG 1 FIX: this used to be a Sub that mutated g_nextShotTime but had no way
' to tell the caller the camera wasn't ready. Callers ran TakePhoto regardless,
' triggering the shutter mid-write and producing 503 Device Busy errors and
' lost frames during long exposures. Now phase handlers MUST gate on the
' return value:
'
'     If Not WaitForCamera(20#) Then Exit Sub
'
' SequenceLoop's reschedule tail then fires us again at the safe time.
Private Function WaitForCamera(ByVal exposureSecs As Double) As Boolean
    Const WRITE_BUFFER As Double = 2#   ' seconds for SD card write to finish
    
    Dim safeTime As Date
    safeTime = g_lastShotTime + ((exposureSecs + WRITE_BUFFER) / 86400#)
    
    If Now() < safeTime Then
        ' Not safe — push next loop out to the safe time and tell the caller
        ' to bail out of this iteration.
        g_nextShotTime = safeTime
        WaitForCamera = False
    Else
        WaitForCamera = True
    End If
End Function

' ============================================================
' Gimbal transition helpers
' ============================================================

' Move gimbal to sunset direction at start of Phase 2a
Public Sub GimbalToSunset()
    Dim cartHeading As Double
    cartHeading = Sheets("Settings").Range("dataCartHeading").value
    
    Dim yaw As Double, pitch As Double
    GetSunGimbalAngles Now(), cartHeading, yaw, pitch
    
    ' Move slowly to not disturb camera
    GimbalPosition yaw, 0#, pitch, 10#
    LogEvent "SEQ", "Gimbal moved to sunset: yaw=" & Format(yaw, "0.1") & _
             " pitch=" & Format(pitch, "0.1")
End Sub

' Move gimbal to Milky Way galactic centre at start of Phase 3
Public Sub GimbalToMilkyWay()
    Dim cartHeading As Double
    cartHeading = Sheets("Settings").Range("dataCartHeading").value
    
    Dim yaw As Double, pitch As Double
    If GetGCGimbalAngles(Now(), cartHeading, yaw, pitch) Then
        ' Move over 30 seconds — between shots
        GimbalPosition yaw, 0#, pitch, 30#
        LogEvent "SEQ", "Gimbal moved to Milky Way: yaw=" & Format(yaw, "0.1") & _
                 " pitch=" & Format(pitch, "0.1")
    Else
        LogEvent "SEQ", "WARNING: Galactic centre below horizon at this time"
        MsgBox "Galactic centre is below the horizon. Check AstroTable for rise time.", vbExclamation
    End If
End Sub

' Move gimbal to sunrise direction at start of Phase 4
Public Sub GimbalToSunrise()
    Dim cartHeading As Double
    cartHeading = Sheets("Settings").Range("dataCartHeading").value
    
    ' Get tomorrow's sunrise position
    Dim sunriseTime As Date
    sunriseTime = Sheets("Settings").Range("dataSunriseTime").value
    
    Dim yaw As Double, pitch As Double
    GetSunGimbalAngles sunriseTime, cartHeading, yaw, pitch
    
    GimbalPosition yaw, 0#, pitch, 30#
    LogEvent "SEQ", "Gimbal moved to sunrise: yaw=" & Format(yaw, "0.1") & _
             " pitch=" & Format(pitch, "0.1")
End Sub

' ============================================================
' Replay plan execution (from CartLog post-processing)
'
' Plans live on the "Sequence" sheet, columns:
'   A: Time (when to execute)
'   B: Action (SPEED / STEER / STOP / DECAY / HOME / GIMBAL)
'   C: Value (m/hr, degrees, "yaw,pitch", etc.)
'   D: Duration (currently unused)
'
' These plans are produced by post-processing the high-speed Arduino
' CartLog and GimbalLog into a slow-time replay schedule that the cart
' will execute during the actual shoot. See the "future work" note in
' Gimbal.bas for the planned playback pipeline.
' ============================================================

' Start a cart replay. Schedules itself row-by-row via Application.OnTime
' so Excel stays responsive and SequenceLoop can interleave with photos.
'
' BUG 5 FIX: this used to be a single Sub with Do/While/Application.Wait that
' blocked Excel for the entire duration of the plan. SequenceLoop's OnTime
' calls would queue but couldn't fire, so photos were late. Now each row is
' an independent OnTime-driven step; the plan runs concurrently with the
' photo loop without blocking either one.
Public Sub StartCartReplay()
    g_replayRow = 2  ' row 1 = headers
    LogEvent "CART", "=== Cart replay started ==="
    RunCartReplayStep
End Sub

' Stop a running cart replay. Cancels any pending OnTime step.
Public Sub StopCartReplay()
    g_replayRow = 0
    On Error Resume Next
    Application.OnTime Now() + (1# / 86400#), "RunCartReplayStep", , False
    On Error GoTo 0
    LogEvent "CART", "=== Cart replay stopped ==="
End Sub

' Execute the current replay row, then schedule the next one.
' Public so Application.OnTime can find it.
Public Sub RunCartReplayStep()
    If g_replayRow < 2 Then Exit Sub      ' replay was stopped
    
    Dim ws As Worksheet
    Set ws = Sheets("Sequence")
    
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).row
    If g_replayRow > lastRow Then
        g_replayRow = 0
        LogEvent "CART", "=== Cart replay complete ==="
        Exit Sub
    End If
    
    Dim replayTime As Date
    Dim action     As String
    Dim value      As Double
    
    replayTime = ws.Cells(g_replayRow, 1).value
    action = Trim(ws.Cells(g_replayRow, 2).value)
    value = ws.Cells(g_replayRow, 3).value
    
    ' If the row's time hasn't arrived yet, reschedule ourselves for that
    ' time and bail. SequenceLoop is free to fire in the gap.
    If Now() < replayTime Then
        Application.OnTime replayTime, "RunCartReplayStep"
        Exit Sub
    End If
    
    ' Time is reached — execute the action.
    Select Case UCase(action)
        Case "SPEED"
            CartSetSpeed value
        Case "STEER"
            CartSetSteering CInt(value)
        Case "STOP"
            CartStop
        Case "DECAY"
            CartDecay
        Case "HOME"
            GimbalHome
        Case "GIMBAL"
            ' Format: "yaw,pitch" in value column
            Dim parts() As String
            parts = Split(CStr(ws.Cells(g_replayRow, 3).value), ",")
            If UBound(parts) >= 1 Then
                GimbalPosition CDbl(parts(0)), 0#, CDbl(parts(1)), 5#
            End If
    End Select
    
    LogEvent "CART", "Replay: " & Format(replayTime, "HH:nn:ss") & _
             " " & action & "=" & value
    
    ' Advance and schedule the next step immediately — RunCartReplayStep
    ' will defer itself if that row's time hasn't arrived.
    g_replayRow = g_replayRow + 1
    Application.OnTime Now() + (1# / 86400#), "RunCartReplayStep"
End Sub

' ============================================================
' Utility
' ============================================================

' Check if camera is reachable before starting sequence
Public Function CameraReachable() As Boolean
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", CAMERA_IP() & "/ccapi/" & CCAPI_VER & "/shooting/settings/shootingmode", False
    http.SetTimeouts 3000, 3000, 3000, 3000
    http.Send
    CameraReachable = (http.Status = 200)
    Set http = Nothing
    Exit Function
ErrHandler:
    CameraReachable = False
End Function

' Check if Arduino is reachable
Public Function ArduinoReachable() As Boolean
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/status", False
    http.SetTimeouts 3000, 3000, 3000, 3000
    http.Send
    ArduinoReachable = (http.Status = 200)
    Set http = Nothing
    Exit Function
ErrHandler:
    ArduinoReachable = False
End Function

' System check — run before starting shoot
Public Sub SystemCheck()
    Dim msg As String
    msg = "=== System Check ===" & Chr(10)
    
    If CameraReachable() Then
        msg = msg & "✓ Canon R3 reachable at " & CAMERA_IP() & Chr(10)
    Else
        msg = msg & "✗ Canon R3 NOT reachable at " & CAMERA_IP() & Chr(10)
    End If
    
    If ArduinoReachable() Then
        msg = msg & "✓ Arduino reachable at " & ARDUINO_IP() & Chr(10)
    Else
        msg = msg & "✗ Arduino NOT reachable at " & ARDUINO_IP() & Chr(10)
    End If
    
    Dim sunsetTime As Date
    sunsetTime = Sheets("Settings").Range("dataSunsetTime").value
    If sunsetTime <> 0 Then
        msg = msg & "✓ Sunset time: " & Format(sunsetTime, "HH:nn:ss") & Chr(10)
    Else
        msg = msg & "✗ Sunset time not set — run InitShoot" & Chr(10)
    End If
    
    MsgBox msg, vbInformation, "System Check"
    LogEvent "SEQ", msg
End Sub
