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
Private g_shotCounter   As Long     ' loop counter — used to throttle luminance kickoff

' How often to kick off a fresh luminance measurement, in loop cycles.
' Session B finding (May 2026): at fast cadence (2-3s cycles) firing
' kickoff every cycle hammers the camera with CCAPI GETs while it's
' still writing the previous JPG, producing 503 retries and 3-6s
' cadence slips. The camera's buffer is fine; the chokepoint is the
' CCAPI being busy. Kicking off every Nth shot gives the camera N-1
' quiet cycles between thumbnail fetches.
'
' N=3 matches the real-world measurement cadence Mike used in earlier
' shoots. Staleness still tracked per shot — adjustments act on the
' freshest reading regardless of when it was taken.
Private Const LUM_KICKOFF_EVERY_N As Long = 3

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
    
    ' 5. Populate Tv lookup from camera's actual ability list.
    '    Must come AFTER InitCamera (needs HTTP working). Used by the
    '    feedback algorithm in RunShot to walk Tv one step at a time.
    InitTvLookup
    
    ' 6. Update Monitor sheet
    UpdateMonitor
    
    LogEvent "SEQ", "InitShoot complete. Sunset: " & _
             Format(Sheets("Settings").Range("dataSunsetTime").value, "HH:nn:ss")
    
    MsgBox "Shoot initialised." & Chr(10) & _
           "Sunset: " & Format(Sheets("Settings").Range("dataSunsetTime").value, "HH:nn:ss") & Chr(10) & _
           "Sunrise: " & Format(Sheets("Settings").Range("dataSunriseTime").value, "HH:nn:ss") & Chr(10) & Chr(10) & _
           "Run StartSequence at 4:00pm.", vbInformation
End Sub

' ============================================================
' Sequence start / stop
' ============================================================

Public Sub StartSequence()
    If g_running Then
        MsgBox "Sequence already running.", vbInformation
        Exit Sub
    End If
    
    g_running = True
    g_lastShotTime = Now()
    g_nextShotTime = Now()
    g_scheduledTime = Now()  ' Bug B anchor — first RunShot anchors next shot from this
    g_lastPhase = 0          ' 0 ≠ any real phase, so first loop fires OnPhaseEnter
    g_shotCounter = 0        ' Kickoff throttle counter (Session B finding)
    
    ResetPhotoTimer          ' first shot will show "int=-" rather than a stale value
    
    ' Reset non-blocking luminance state (Session A) — kills any orphan
    ' Python job from a previous run, clears g_lastLuminance to -1 so
    ' phase handlers know there's no measurement yet.
    ResetLuminanceState
    
    ' Validate operator luminance targets (Session A). Logs warnings if
    ' the named ranges are missing — code will fall back to defaults
    ' (60 sunset, 40 sunrise) per PROJECT_STATE provisional values.
    ValidateLuminanceSettings
    
    Sheets("Settings").Range("dataSequenceRunning").value = "RUNNING"
    LogEvent "SEQ", "=== Sequence STARTED ==="
    
    ' Warm-up: prod the camera and Arduino once before the first loop.
    ' BUG A FIX (May 2026, session 2): the first POST shutterbutton in the
    ' first iteration sometimes fails with "connection terminated
    ' abnormally" — the WiFi/TCP session hasn't fully woken up. A pre-loop
    ' GET forces the connection to be established cleanly before the
    ' time-sensitive shutter call.
    On Error Resume Next
    Dim warmup As String
    warmup = CameraGet("/ccapi/ver100/shooting/settings/tv")
    GetGimbalStatus
    On Error GoTo 0
    
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

' Public accessor for the private g_running flag.
' Added for Bench.bas (Session A benchmark phase) to gate against
' running benchmarks while a real sequence is live. Safe to keep in
' place after benchmarking is removed — harmless and useful.
Public Function IsSequenceRunning() As Boolean
    IsSequenceRunning = g_running
End Function

' ============================================================
' Main loop — fires at each shot interval
' ============================================================

' Main loop — fires once per shot interval via Application.OnTime.
'
' SESSION B REORDER (May 2026):
' The seven phase handlers have been retired. Exposure is now driven
' by pure luminance feedback in a single RunShot handler; phase boundaries
' survive only as gimbal-entry triggers and observational labels.
'
' Each iteration now does, in order:
'   1. POLL — harvest any ready luminance result (non-blocking).
'      Updates g_lastLuminance + dataLuminance if a fresh value arrived.
'   2. Housekeeping — Arduino status, Monitor sheet, gimbal heartbeat.
'   3. ENTRY HOOK — if the phase number just changed, fire OnPhaseEnter
'      to repoint the gimbal. This is the ONLY remaining role of the
'      phase number; it has no influence on exposure decisions.
'   4. SHOT — RunShot takes the photo, runs feedback (if applicable),
'      and calls ScheduleNextShot to set g_nextShotTime.
'   5. BUMP — increment luminance staleness counter.
'   6. KICK-OFF — fetch the last thumbnail and fire Python for next
'      iteration. Unconditional (no PhaseWantsLuminance gate any more);
'      saturated readings during daytime still cost only the kickoff time
'      and give us calibration data through the boundaries.
'   7. SCHEDULE — reschedule for g_nextShotTime.
'
' Photos are sacred. The luminance pipeline never blocks the photo loop.
' Adjustments may be 1-3 photo-cycles late relative to the reading they
' are based on. This is acceptable: luminance changes per-minute, not
' per-second.
Public Sub SequenceLoop()
    If Not g_running Then Exit Sub
    
    Dim phase As Integer
    Dim t0    As Double, t1 As Double
    Dim msPoll As Long, msStatus As Long, msMonitor As Long
    Dim msHeartbeat As Long, msShot As Long, msKickoff As Long
    
    phase = GetCurrentPhase()
    
    ' ── Step 1: harvest any ready luminance ──────────────────
    ' PollLuminanceCalc has side effects only — it updates g_lastLuminance
    ' and dataLuminance if a fresh value arrived. Return value is unused.
    '   LUM_BUSY (-2)         — still running, do nothing
    '   LUM_DONE_NORESULT (-1) — finished but failed (already logged)
    '   0..255                 — fresh value, stored in g_lastLuminance
    t0 = Timer
    PollLuminanceCalc
    t1 = Timer: msPoll = (t1 - t0) * 1000: t0 = t1
    
    ' ── Step 2: housekeeping ─────────────────────────────────
    GetGimbalStatus
    t1 = Timer: msStatus = (t1 - t0) * 1000: t0 = t1
    
    UpdateMonitor
    t1 = Timer: msMonitor = (t1 - t0) * 1000: t0 = t1
    
    GimbalHeartbeat
    t1 = Timer: msHeartbeat = (t1 - t0) * 1000: t0 = t1
    
    ' ── Step 3: gimbal entry hook (the only surviving role of phase) ─
    ' BUG 3 FIX: detect phase transitions and run entry hook once per change.
    If phase <> g_lastPhase Then
        OnPhaseEnter phase
        g_lastPhase = phase
    End If
    
    ' ── Step 4: kick off next luminance measurement (BEFORE TakePhoto) ──
    ' Session B finding (May 2026): kickoff used to run AFTER TakePhoto
    ' and hit the same camera-busy 503 problem the adjust call did. Fix:
    ' do the CCAPI thumbnail fetch in the idle gap BEFORE the photo. The
    ' thumbnail we get is the PREVIOUS shot's image — fine, because
    ' luminance feedback is already a few cycles stale anyway. One more
    ' cycle of staleness changes nothing.
    '
    ' Throttled to every Nth cycle (LUM_KICKOFF_EVERY_N) so we don't
    ' hammer the CCAPI; staleness still bumped per shot regardless.
    g_shotCounter = g_shotCounter + 1
    If (g_shotCounter Mod LUM_KICKOFF_EVERY_N) = 0 Then
        KickOffLuminanceFromLastThumb   ' returns immediately, fire-and-forget
    End If
    t1 = Timer: msKickoff = (t1 - t0) * 1000: t0 = t1
    
    ' ── Step 5: take the photo (and adjust for next cycle) ───
    RunShot
    t1 = Timer: msShot = (t1 - t0) * 1000: t0 = t1
    
    ' ── Step 6: bump staleness (one shot just happened) ──────
    BumpLuminanceStaleness
    
    ' Only log timing if total exceeds 500ms — skips the chatter when
    ' everything's fast, but flags every problem loop.
    If msPoll + msStatus + msMonitor + msHeartbeat + msShot + msKickoff > 500 Then
        LogEvent "TIMING", "poll=" & msPoll & "ms" & _
                 " status=" & msStatus & "ms" & _
                 " monitor=" & msMonitor & "ms" & _
                 " heartbeat=" & msHeartbeat & "ms" & _
                 " shot=" & msShot & "ms" & _
                 " kickoff=" & msKickoff & "ms"
    End If
    
    ' Schedule next loop. Capture g_scheduledTime so StopSequence can cancel it.
    If g_running Then
        g_scheduledTime = g_nextShotTime
        Application.OnTime g_scheduledTime, "SequenceLoop"
    End If
End Sub

' Phase-entry hook — fires once when the active phase number changes.
' Position the gimbal for the upcoming phase and log the transition.
' BUG 3 FIX — wires the previously-orphaned GimbalTo* subs into the loop.
'
' Session B note: this is now the ONLY use of phase numbers in the loop.
' Exposure control is in RunShot, driven by luminance feedback and a
' two-mode rule (brighten before astro_dusk+30min, darken after).
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
' Shot handler (Session B, May 2026)
'
' One handler for every cycle. Exposure is controlled entirely by
' luminance feedback; phase boundaries no longer dictate Tv or ISO.
' Operator manually sets initial Tv/ISO before StartSequence; from there
' the algorithm walks one knob one step per cycle, in the direction
' allowed by the current mode.
'
' Two modes, switched once per shoot at dataAstroDusk + 30 minutes:
'
'   MODE 1 — Brightening (afternoon → night)
'     Active until astro_dusk + 30 min.
'     Adjustments only ever BRIGHTEN.
'     Walk: slow Tv toward 20" first (lower-noise knob); once Tv is
'     pinned at 20", raise ISO toward 1600.
'     Lum above target: do nothing. Post-production handles transient
'     over-bright frames.
'
'   MODE 2 — Darkening (night → morning)
'     Active from astro_dusk + 30 min onward.
'     Adjustments only ever DARKEN.
'     Walk: drop ISO toward 100 first (lower-noise knob); once ISO is
'     pinned at 100, speed Tv toward 1/5000.
'     Lum below target: do nothing. Same rationale.
'
' Both modes are monotone — once a knob has moved, it never moves back
' during the same mode. This eliminates oscillation as a failure mode.
' The two extreme cases (saturated daytime, pitch night) self-pin at
' the floors; no special-case code needed.
'
' PHOTO PRIMACY:
' AdjustExposureByLuminance fires BEFORE TakePhoto, with errors contained.
' Photo primacy is preserved via the error handler — if SetShutterSpeed
' or SetISO fail (or the whole adjust path explodes), we log it and take
' the photo at the existing settings anyway. The photo is sacred; the
' adjustment is best-effort.
'
' Why this order: TakePhoto returns ~150ms after the shutter trips, but
' the camera continues writing to the SD card for several hundred ms
' more. Issuing CCAPI PUT calls during that write window hits 503 Device
' Busy and the retry logic adds ~3s slip per adjusting cycle. Doing the
' adjust BEFORE the photo means the CCAPI calls land during the natural
' idle gap between cycles, when the camera has drained its buffer.
' (Session B finding, May 2026 — first ordering of this loop had adjust
' after TakePhoto for photo-primacy reasons, but the 503-on-write cost
' was worse than the abandoned alternative.)
'
' For the very first shot the camera is at the operator's chosen
' settings; the adjust runs but does nothing (no luminance reading yet,
' so AdjustExposureByLuminance skips). Subsequent shots: adjust based
' on the freshest luminance reading, then take the photo.
' ============================================================

Private Sub RunShot()
    Dim currentTv As String
    currentTv = Range("dataCurrentTv").value
    Dim currentTvSecs As Double
    currentTvSecs = TvToSeconds(currentTv)
    
    ' Gate on the camera being safe to talk to (previous exposure done +
    ' write buffer drained). If not, WaitForCamera has pushed g_nextShotTime
    ' out to the safe time; SequenceLoop's reschedule tail handles it.
    If Not WaitForCamera(currentTvSecs) Then Exit Sub
    
    ' ── Adjustment FIRST — runs during the natural idle gap, before
    '    the next photo. Errors contained so a CCAPI hiccup never blocks
    '    the photo. The photo is sacred; the adjustment is best-effort.
    On Error Resume Next
    AdjustExposureByLuminance GetActiveLumTarget(), GetLumMode()
    If Err.Number <> 0 Then
        LogEvent "LUMINANCE", "Adjust failed: " & Err.Description & " — continuing"
        Err.Clear
    End If
    On Error GoTo 0
    
    ' ── Take the photo. Whatever Tv/ISO are now on the camera (just-set
    '    or unchanged) are what this photo will use.
    TakePhoto
    
    ' Interval is computed from the (possibly just-updated) Tv. The new
    ' cadence rule: interval = ceiling(Tv + 1.5s). See CalcInterval in Utils.
    Dim newTv As String
    newTv = Range("dataCurrentTv").value
    ScheduleNextShot CalcInterval(newTv)
    
    LogEvent "SEQ", "Shot Tv=" & newTv & _
             " ISO=" & Range("dataCurrentISO").value & _
             " Lum=" & GetLatestLuminance() & _
             " mode=" & LumModeName(GetLumMode()) & _
             " shot=" & Range("dataShotCount").value
End Sub

' Read the active luminance mode from the clock.
' MODE_BRIGHTEN until astro_dusk + 30 min, MODE_DARKEN thereafter.
' Hardcoded 30 min offset — exposed as a named range later if operators
' want to tune it (Session B PROJECT_STATE note).
Public Function GetLumMode() As Integer
    Const SWITCH_OFFSET_MINUTES As Double = 30#
    Dim astroDusk As Date
    On Error GoTo Fallback
    astroDusk = Sheets("Settings").Range("dataAstroDusk").value
    If astroDusk = 0 Then GoTo Fallback
    
    If Now() < astroDusk + (SWITCH_OFFSET_MINUTES / 1440#) Then
        GetLumMode = LUM_MODE_BRIGHTEN
    Else
        GetLumMode = LUM_MODE_DARKEN
    End If
    Exit Function
Fallback:
    ' dataAstroDusk missing or zero — fall back to time-of-day heuristic.
    ' Afternoon/evening: brighten. Past midnight or morning: darken.
    If Hour(Now()) >= 12 Then
        GetLumMode = LUM_MODE_BRIGHTEN
    Else
        GetLumMode = LUM_MODE_DARKEN
    End If
End Function

Public Function LumModeName(ByVal mode As Integer) As String
    Select Case mode
        Case LUM_MODE_BRIGHTEN: LumModeName = "brighten"
        Case LUM_MODE_DARKEN:   LumModeName = "darken"
        Case Else:               LumModeName = "?"
    End Select
End Function

' Pick the operator-set target appropriate to the current mode.
' Mode 1 (brighten) uses dataLumTargetSunset (default 60).
' Mode 2 (darken) uses dataLumTargetSunrise (default 40).
Public Function GetActiveLumTarget() As Integer
    If GetLumMode() = LUM_MODE_BRIGHTEN Then
        GetActiveLumTarget = GetSunsetLumTarget()
    Else
        GetActiveLumTarget = GetSunriseLumTarget()
    End If
End Function

' Schedule the next shot.
'
' BUG B FIX (Session B, May 2026): the next-shot anchor is now
' g_scheduledTime (the time THIS loop was scheduled for by the previous
' OnTime call), NOT Now() after housekeeping has eaten variable seconds.
' Anchoring off Now() let the cadence slip forward by however long the
' previous cycle ran long, and the slip compounded — eventually
' g_nextShotTime sat in the past for many cycles in a row, OnTime fired
' immediately, and a burst of fast photos played out until real time
' caught up.
'
' Phase 5 fast-forward test (Session A) showed exactly this: 22 consecutive
' shots at 20-21s intervals against a 2s target, then a sudden catch-up.
'
' Clamp behaviour: if g_scheduledTime + interval is already in the past,
' we're behind schedule. Resync to Now() + interval and log a TIMING line
' showing the slip magnitude. Bursting photos to catch up would produce
' irregular intervals in the timelapse output — unacceptable for video.
' Output cadence consistency is the goal; recovering the original schedule
' is not. The log line is the diagnostic data for finding the slip cause.
Private Sub ScheduleNextShot(ByVal intervalSecs As Double)
    g_lastShotTime = Now()                                      ' diagnostic — when shutter actually fired
    g_nextShotTime = g_scheduledTime + (intervalSecs / 86400#)
    
    If g_nextShotTime <= Now() Then
        Dim slipSecs As Double
        slipSecs = (Now() - g_nextShotTime) * 86400#
        g_nextShotTime = Now() + (intervalSecs / 86400#)
        LogEvent "TIMING", "Cadence slip " & Format(slipSecs, "0.0") & _
                 "s — resynced (interval=" & Format(intervalSecs, "0.0") & "s)"
    End If
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
        ' BUG A FIX (Session A, May 2026): the previous code popped a
        ' modal MsgBox here that blocked the photo loop for as long as
        ' the operator took to dismiss it. Observed cost: 18s of dead
        ' loop time during a Session A validation run when the GC was
        ' below the horizon (test ran in daytime; Phase 3 fired anyway).
        ' Now: log the warning and continue. The gimbal simply doesn't
        ' move for this phase entry. Operator can read the log later if
        ' the framing was wrong.
        LogEvent "SEQ", "WARNING: Galactic centre below horizon at this time — Phase 3 entered without gimbal repoint"
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
    lastRow = ws.Cells(ws.Rows.count, 1).End(xlUp).row
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



