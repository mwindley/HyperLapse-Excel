Attribute VB_Name = "Camera"
' ============================================================
' HyperLapse Cart — Camera Control Module
'
' PURPOSE
'   All Canon R3 camera control over Wi-Fi via the CCAPI. Provides:
'     - Core HTTP helpers (CameraGet / CameraPut / CameraPost) with
'       error handling and retry-on-busy (see Bug 7 below)
'     - Setting wrappers (mode, aperture, shutter, ISO) that update
'       both the camera and the matching named ranges on Settings
'     - TakePhoto — the only call that should ever fire the shutter
'     - Phase 2b/4a luminance feedback loop:
'         GetLastThumbnailLuminance reads the most recent JPG thumbnail
'         from the camera and pipes it through luminance.py to compute
'         a 0–255 brightness value; AdjustExposureByLuminance steps ISO
'         up or down to keep the frame within a target band.
'     - Arduino display helpers (UpdateArduinoDisplay, SendHeartbeat)
'   Camera IP and Arduino IP are read from named ranges on Settings.
'
' PROTOCOL NOTES
'   All endpoints confirmed against Canon CCAPI Reference v1.4.0.
'   The R3 returns 503 Device Busy any time the shutter is open or the
'   SD card is still being written. Phase 3 fires 20s exposures all
'   night, so retry-on-503 is essential — see Bug 7 fix in CameraPut.
'
' DEPENDENCIES
'   ParseJsonField and LogEvent are in Utils.bas
'   luminance.py is located by FindLuminanceScript searching standard
'   locations (repo Python folder, OneDrive, USERPROFILE Documents).
'
' RECENT FIXES (May 2026)
'   Bug 7 — CameraPut now retries up to 5 times with growing backoff
'           on 503, instead of a single 3s retry that couldn''t cover
'           a 20s Phase 3 exposure.
' ============================================================

Option Explicit

' -- Constants ------------------------------------------------
' IPs read from named ranges on Settings sheet
Public Const CCAPI_VER As String = "ver100"
' ISO steps for Phase 2b luminance-based adjustment
Public Const ISO_STEPS As String = "100,125,160,200,250,320,400,500,640,800,1000,1250,1600"

' HTTP response codes
Private Const HTTP_OK          As Integer = 200
Private Const HTTP_BAD_REQUEST As Integer = 400
Private Const HTTP_DEVICE_BUSY As Integer = 503

' -- Module state ---------------------------------------------
' Track the moment the previous shutter trigger succeeded, used to
' compute the interval-since-last-shot in the photo log line. This
' is intentionally separate from Sequence.g_lastShotTime — that one
' drives camera-busy timing decisions; this one is purely diagnostic
' and captures the real shutter event, not the loop's intent.
' Reset by ResetPhotoTimer at the start of each new sequence.
Private g_lastPhotoTime As Date

' Cached luminance.py path. Populated by FindLuminanceScript on first
' call. Special value "(notfound)" means we searched and failed; don't
' search again this session. Cleared automatically when workbook reopens.
Private g_luminanceScriptPath As String

' ── Non-blocking luminance state (Session A, May 2026) ──────────
' SequenceLoop schedules a Python luminance calculation per cycle when
' the phase wants luminance. The Python process runs concurrently with
' the photo cycle; we poll it next iteration. The most recent
' successful result lives in g_lastLuminance and is consumed by the
' phase handlers' calls to AdjustExposureByLuminance.
'
' g_lumExec — the running WScript.Shell.Exec object, or Nothing when
'             no job is in flight. Checked by PollLuminanceCalc.
' g_lumJobJpeg — path of the JPEG the current job is processing (log only)
' g_lumJobStarted — when the job was kicked off (for soft timeout)
' g_lastLuminance — most recent successful value (0-255), or -1 if never
' g_lumStaleness — shots elapsed since g_lastLuminance was updated.
'                  Incremented per shot by BumpLuminanceStaleness, reset
'                  to 0 by a successful PollLuminanceCalc result.
'                  Failed measurements (DONE_NORESULT) do NOT reset it —
'                  a failed measurement is not a measurement.
Private g_lumExec       As Object
Private g_lumJobJpeg    As String
Private g_lumJobStarted As Date
Private g_lastLuminance As Integer
Private g_lumStaleness  As Long

' PollLuminanceCalc return code sentinels
Public Const LUM_BUSY         As Integer = -2
Public Const LUM_DONE_NORESULT As Integer = -1
' (Values 0..255 returned directly as the luminance reading)

' Soft timeout on a running Python job. If a job hasn't completed
' within this many seconds we terminate it and return DONE_NORESULT.
' The old blocking CalcLuminance used a 5s budget — non-blocking can
' afford to be more generous because waiting doesn't cost the photo.
Private Const LUM_TIMEOUT_SECS As Double = 15#

Public Function CAMERA_IP() As String
    CAMERA_IP = Sheets("Settings").Range("dataCameraIP").value
End Function

Public Function ARDUINO_IP() As String
    ARDUINO_IP = Sheets("Settings").Range("dataArduinoIP").value
End Function



' ============================================================
' Core HTTP helpers
' ============================================================

Public Function CameraGet(ByVal endpoint As String) As String
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", CAMERA_IP() & endpoint, False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send
    Select Case http.Status
        Case HTTP_OK
            CameraGet = http.ResponseText
        Case HTTP_DEVICE_BUSY
            LogEvent "CAMERA", "GET " & endpoint & " - Device busy (503)"
            CameraGet = ""
        Case Else
            LogEvent "CAMERA", "GET " & endpoint & " - HTTP " & http.Status
            CameraGet = ""
    End Select
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "GET " & endpoint & " - Connection failed: " & Err.Description
    CameraGet = ""
End Function

' Send a JSON PUT to the camera CCAPI.
'
' BUG 7 FIX: 503 Device Busy is common during long exposures (Phase 3 fires
' 20 second exposures all night). The camera will reject any setting change
' that lands while the shutter is open or the SD card is still being written.
' We now retry up to MAX_BUSY_RETRIES times with growing backoff, instead of
' giving up after a single 3-second retry — which was never enough to cover
' a 20s Phase 3 exposure.
Public Function CameraPut(ByVal endpoint As String, ByVal jsonBody As String) As Boolean
    Const MAX_BUSY_RETRIES As Integer = 5
    Const INITIAL_BACKOFF_SECS As Double = 3#
    
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    
    Dim attempt   As Integer
    Dim backoff   As Double
    backoff = INITIAL_BACKOFF_SECS
    
    For attempt = 0 To MAX_BUSY_RETRIES
        http.Open "PUT", CAMERA_IP() & endpoint, False
        http.SetRequestHeader "Content-Type", "application/json"
        http.Send jsonBody
        
        Select Case http.Status
            Case HTTP_OK
                CameraPut = True
                Set http = Nothing
                Exit Function
            Case HTTP_DEVICE_BUSY
                If attempt < MAX_BUSY_RETRIES Then
                    LogEvent "CAMERA", "PUT " & endpoint & " - 503 busy, retry " & _
                             (attempt + 1) & "/" & MAX_BUSY_RETRIES & _
                             " in " & backoff & "s"
                    Application.Wait Now + (backoff / 86400#)
                    backoff = backoff * 1.5   ' gentle exponential backoff
                Else
                    LogEvent "CAMERA", "PUT " & endpoint & " - 503 after " & _
                             MAX_BUSY_RETRIES & " retries, giving up"
                    CameraPut = False
                    Set http = Nothing
                    Exit Function
                End If
            Case HTTP_BAD_REQUEST
                LogEvent "CAMERA", "PUT " & endpoint & " - Invalid param. Body: " & jsonBody
                CameraPut = False
                Set http = Nothing
                Exit Function
            Case Else
                LogEvent "CAMERA", "PUT " & endpoint & " - HTTP " & http.Status
                CameraPut = False
                Set http = Nothing
                Exit Function
        End Select
    Next attempt
    
    ' Should be unreachable, but be safe
    CameraPut = False
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "PUT " & endpoint & " - Connection failed: " & Err.Description
    CameraPut = False
End Function

Public Function CameraPost(ByVal endpoint As String, ByVal jsonBody As String) As Boolean
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "POST", CAMERA_IP() & endpoint, False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send jsonBody
    Select Case http.Status
        Case HTTP_OK
            CameraPost = True
        Case HTTP_DEVICE_BUSY
            LogEvent "CAMERA", "POST " & endpoint & " - Device busy (503)"
            CameraPost = False
        Case Else
            LogEvent "CAMERA", "POST " & endpoint & " - HTTP " & http.Status
            CameraPost = False
    End Select
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "POST " & endpoint & " - Connection failed: " & Err.Description
    CameraPost = False
End Function

' ============================================================
' Camera setting functions
' ============================================================

Public Function SetShootingMode(ByVal myMode As String) As Boolean
    SetShootingMode = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/shootingmode", _
                                "{""value"":""" & myMode & """}")
    If SetShootingMode Then
        Range("dataCurrentMode").value = myMode
        LogEvent "CAMERA", "Mode set to " & myMode
    End If
End Function

Public Function SetAperture(ByVal myAv As String) As Boolean
    SetAperture = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/av", _
                            "{""value"":""" & myAv & """}")
    If SetAperture Then
        Range("dataCurrentAv").NumberFormat = "@"

        Range("dataCurrentAv").value = myAv
        LogEvent "CAMERA", "Av set to " & myAv
        UpdateArduinoDisplay
    End If
End Function

Public Function SetShutterSpeed(ByVal myTv As String) As Boolean
    ' BUG FIX (May 2026, session 2): myTv may contain Canon's seconds-symbol
    ' " (e.g. "20""", "0""5"). That " must be JSON-escaped to \" before
    ' embedding in the request body, otherwise the body becomes invalid
    ' JSON like {"value":"0"8"} and the camera rejects it.
    SetShutterSpeed = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/tv", _
                                "{""value"":""" & JsonEscape(myTv) & """}")
    If SetShutterSpeed Then
        Range("dataCurrentTv").NumberFormat = "@"
        Range("dataCurrentTv").value = myTv
        LogEvent "CAMERA", "Tv set to " & myTv
        UpdateArduinoDisplay
    End If
End Function

Public Function SetISO(ByVal myISO As String) As Boolean
    SetISO = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/iso", _
                       "{""value"":""" & myISO & """}")
    If SetISO Then
        Range("dataCurrentISO").value = myISO
        LogEvent "CAMERA", "ISO set to " & myISO
        UpdateArduinoDisplay
    End If
End Function

' Reset the photo-interval tracker. Called from Sequence.StartSequence so
' the first shot of a fresh sequence shows "int=-" rather than carrying
' an interval from a previous run.
Public Sub ResetPhotoTimer()
    g_lastPhotoTime = 0
End Sub

Public Function TakePhoto() As Boolean
    TakePhoto = CameraPost("/ccapi/" & CCAPI_VER & "/shooting/control/shutterbutton", _
                           "{""af"":false}")
    If TakePhoto Then
        Range("dataShotCount").value = Range("dataShotCount").value + 1
        LogPhotoLine
        g_lastPhotoTime = Now()
    End If
End Function

' Compose the diagnostic photo log line. Format:
'   shot=N Av=fX Tv=Y ISO=Z int=Ws
'
' "int" (interval) is the elapsed seconds since the previous successful
' shutter trigger — '-' for the first shot of a session, since
' g_lastPhotoTime is 0 then. This is the key field for spotting timing
' drift: if we asked for a 2-second interval but shots are landing at
' 4 seconds, we know the camera (or the network, or the macro itself)
' is blocking longer than expected and we may be dropping photos.
Private Sub LogPhotoLine()
    Dim shot   As String
    Dim avStr  As String
    Dim tvStr  As String
    Dim isoStr As String
    Dim intStr As String
    
    shot = CStr(Range("dataShotCount").value)
    avStr = CStr(Range("dataCurrentAv").value)
    tvStr = CStr(Range("dataCurrentTv").value)
    isoStr = CStr(Range("dataCurrentISO").value)
    
    If g_lastPhotoTime = 0 Then
        intStr = "-"
    Else
        intStr = Format((Now() - g_lastPhotoTime) * 86400#, "0.0") & "s"
    End If
    
    LogEvent "CAMERA", "shot=" & shot & _
                       " Av=" & avStr & _
                       " Tv=" & tvStr & _
                       " ISO=" & isoStr & _
                       " int=" & intStr
End Sub

Public Function GetCurrentISO() As String
    Dim response As String
    response = CameraGet("/ccapi/" & CCAPI_VER & "/shooting/settings/iso")
    If response = "" Then GetCurrentISO = "": Exit Function
    GetCurrentISO = ParseJsonField(response, "value")
End Function

Public Function GetCurrentTv() As String
    Dim response As String
    response = CameraGet("/ccapi/" & CCAPI_VER & "/shooting/settings/tv")
    If response = "" Then GetCurrentTv = "": Exit Function
    GetCurrentTv = ParseJsonField(response, "value")
End Function

Public Function GetISOAbility() As String
    Dim response As String
    response = CameraGet("/ccapi/" & CCAPI_VER & "/shooting/settings/iso")
    If response = "" Then GetISOAbility = "": Exit Function
    GetISOAbility = ParseJsonField(response, "ability")
End Function

' ============================================================
' Phase 2b / Phase 4a — Luminance-based ISO adjustment
' ============================================================

' Adjust ISO toward the target luminance using the most recently
' captured value (g_lastLuminance). NON-BLOCKING — does not trigger
' a new measurement; consumes whatever the most recent kick-off
' has produced via PollLuminanceCalc.
'
' SESSION A CHANGES (May 2026):
'   - Target is now a PARAMETER (caller picks sunset vs sunrise target
'     from named ranges dataLumTargetSunset / dataLumTargetSunrise).
'   - Source is g_lastLuminance (module state), not a fresh blocking
'     fetch. If no measurement has succeeded yet (-1) we skip silently
'     so the photo loop is never gated on a luminance result.
'   - Band width ±15 around target. Old code used absolute thresholds
'     95/135 (a band of 40 centred on 115) — same shape, parametric.
Public Function AdjustExposureByLuminance(ByVal targetLum As Integer) As String
    Const BAND_HALF_WIDTH As Integer = 15
    
    Dim lum As Integer
    lum = g_lastLuminance
    
    If lum < 0 Then
        ' No measurement yet this session, or last measurement failed.
        ' Don't act; phase handlers will retry next cycle.
        LogEvent "LUMINANCE", "AdjustExposure: no luminance available (-1), skipping"
        Range("dataCommCameraCheck").value = "Lum n/a " & Format(Now(), "HH:nn:ss")
        AdjustExposureByLuminance = ""
        Exit Function
    End If
    
    Dim targetLow  As Integer
    Dim targetHigh As Integer
    targetLow = targetLum - BAND_HALF_WIDTH
    targetHigh = targetLum + BAND_HALF_WIDTH
    
    LogEvent "LUMINANCE", "lum=" & lum & " target=" & targetLum & _
             " band=[" & targetLow & "," & targetHigh & "]" & _
             " stale=" & g_lumStaleness & _
             " ISO=" & Range("dataCurrentISO").value & _
             " Tv=" & Range("dataCurrentTv").value
    
    Dim isoSteps() As String
    isoSteps = Split(ISO_STEPS, ",")
    Dim currentISO As String
    currentISO = Range("dataCurrentISO").value
    
    Dim idx As Integer: idx = -1
    Dim i As Integer
    For i = 0 To UBound(isoSteps)
        If isoSteps(i) = currentISO Then idx = i: Exit For
    Next i
    
    If idx < 0 Then
        LogEvent "CAMERA", "AdjustExposure: unknown ISO " & currentISO
        AdjustExposureByLuminance = ""
        Exit Function
    End If
    
    Dim newISO As String: newISO = ""
    If lum < targetLow And idx < UBound(isoSteps) Then
        newISO = isoSteps(idx + 1)
        SetISO newISO
        Range("dataCommCameraCheck").value = "Lum:" & lum & " ISO up->" & newISO & " " & Format(Now(), "HH:nn:ss")
    ElseIf lum > targetHigh And idx > 0 Then
        newISO = isoSteps(idx - 1)
        SetISO newISO
        Range("dataCommCameraCheck").value = "Lum:" & lum & " ISO dn->" & newISO & " " & Format(Now(), "HH:nn:ss")
    Else
        Range("dataCommCameraCheck").value = "Lum:" & lum & " ISO OK " & Format(Now(), "HH:nn:ss")
    End If
    AdjustExposureByLuminance = newISO
End Function

' ============================================================
' Non-blocking luminance primitives (Session A, May 2026)
'
' The pipeline has two halves:
'   1. CCAPI dance — fetch the last JPG thumbnail from the camera and
'      save it locally as LastThumb.jpg. Done synchronously by
'      KickOffLuminanceFromLastThumb (and previously by the inline
'      logic in GetLastThumbnailLuminance). The CCAPI calls fit
'      comfortably inside a 22s photo cycle — see Bench results,
'      May 2026.
'   2. Python subprocess — runs luminance.py against the local JPG.
'      Used to block for up to 5s. Now fires-and-returns; the result
'      is harvested next loop iteration by PollLuminanceCalc.
'
' SequenceLoop's life with these:
'   - top of loop: PollLuminanceCalc() — harvest a ready result
'   - phase handler: AdjustExposureByLuminance reads g_lastLuminance
'   - bottom of loop: if phase wants luminance and no job running,
'                     call KickOffLuminanceFromLastThumb()
'
' Per the architectural decision: photos are sacred. The luminance
' pipeline NEVER blocks the photo loop. Adjustments may be 1–3 photo
' cycles late relative to the reading they're based on; this is
' acceptable because luminance changes per-minute, not per-second.
' ============================================================

' Kick off a Python luminance job on an already-saved JPEG.
' Returns True if the job was started, False if a job is already
' running (caller should not have called us — we log it) or if the
' Python script can't be found.
'
' This is the LOW-LEVEL primitive. Most callers will use
' KickOffLuminanceFromLastThumb instead, which does the CCAPI dance
' first.
Public Function KickOffLuminanceCalc(ByVal jpegPath As String) As Boolean
    On Error GoTo ErrHandler
    
    If Not (g_lumExec Is Nothing) Then
        LogEvent "LUMINANCE", "KickOff called while job already running — ignoring"
        KickOffLuminanceCalc = False
        Exit Function
    End If
    
    Dim scriptPath As String
    scriptPath = FindLuminanceScript()
    If LenB(scriptPath) = 0 Then
        ' FindLuminanceScript has already logged the full search list
        KickOffLuminanceCalc = False
        Exit Function
    End If
    
    Dim shell As Object
    Set shell = CreateObject("WScript.Shell")
    Set g_lumExec = shell.exec("python """ & scriptPath & """ """ & jpegPath & """")
    g_lumJobJpeg = jpegPath
    g_lumJobStarted = Now()
    
    KickOffLuminanceCalc = True
    Exit Function
ErrHandler:
    LogEvent "LUMINANCE", "KickOffLuminanceCalc error: " & Err.Description
    Set g_lumExec = Nothing
    KickOffLuminanceCalc = False
End Function

' Convenience: do the CCAPI thumbnail dance and immediately kick off
' Python. The CCAPI half is unavoidably synchronous (WinHttp has no
' async mode in VBA) but fits inside the photo cycle. The Python half
' runs concurrently.
'
' Returns True if a job was launched, False if the CCAPI part failed
' or a job is already in flight.
Public Function KickOffLuminanceFromLastThumb() As Boolean
    On Error GoTo ErrHandler
    
    If Not (g_lumExec Is Nothing) Then
        ' Don't log — this can happen legitimately if a previous job is
        ' still running. Caller will skip kick-off; nothing to fix.
        KickOffLuminanceFromLastThumb = False
        Exit Function
    End If
    
    Dim savePath As String
    savePath = FetchLastThumbnailToDisk()
    If LenB(savePath) = 0 Then
        ' FetchLastThumbnailToDisk has already logged the failure
        KickOffLuminanceFromLastThumb = False
        Exit Function
    End If
    
    KickOffLuminanceFromLastThumb = KickOffLuminanceCalc(savePath)
    Exit Function
ErrHandler:
    LogEvent "LUMINANCE", "KickOffLuminanceFromLastThumb error: " & Err.Description
    KickOffLuminanceFromLastThumb = False
End Function

' Poll a running Python job. Three possible returns:
'   LUM_BUSY (-2) — still running, nothing to do
'   LUM_DONE_NORESULT (-1) — finished but Python failed or returned
'                            non-numeric. stderr logged. g_lastLuminance
'                            untouched. g_lumStaleness NOT reset (per
'                            Session A decision: failed measurement is
'                            not a measurement).
'   0..255 — finished with a valid value. g_lastLuminance updated.
'            g_lumStaleness reset to 0. dataLuminance updated so
'            Monitor sheet stays live.
'
' Also handles soft timeout: if the job is STILL RUNNING after
' LUM_TIMEOUT_SECS, terminate it and return DONE_NORESULT.
'
' BUG FIX (Session A, May 2026): the original implementation checked
' the timeout BEFORE checking process status, which terminated
' already-finished Python jobs that hadn't been polled yet. In Phase
' 4a steady-state (22s between polls), every kicked-off job would sit
' dormant for 22s before being polled, hit the 15s timeout, and be
' killed even though Python had finished in <3s. Observed in the
' 11:03 validation run: zero successful luminance readings across
' 6 iterations. Fix: check Status first; only apply the timeout if
' the job is genuinely still running.
Public Function PollLuminanceCalc() As Integer
    On Error GoTo ErrHandler
    
    If g_lumExec Is Nothing Then
        PollLuminanceCalc = LUM_DONE_NORESULT
        Exit Function
    End If
    
    ' Status 0 = still running per WScript.Shell.Exec documentation.
    ' If the job is still running, NOW apply the soft timeout.
    ' If it has finished, harvest the result regardless of elapsed
    ' wall-clock time since kick-off — Python may have finished
    ' seconds ago and we're only just getting around to polling.
    If g_lumExec.Status = 0 Then
        Dim elapsedSecs As Double
        elapsedSecs = (Now() - g_lumJobStarted) * 86400#
        If elapsedSecs > LUM_TIMEOUT_SECS Then
            LogEvent "LUMINANCE", "Poll: job still running after " & _
                     Format(elapsedSecs, "0.0") & "s — terminating"
            On Error Resume Next
            g_lumExec.Terminate
            On Error GoTo 0
            Set g_lumExec = Nothing
            g_lumJobJpeg = ""
            PollLuminanceCalc = LUM_DONE_NORESULT
            Exit Function
        End If
        PollLuminanceCalc = LUM_BUSY
        Exit Function
    End If
    
    ' Job finished — harvest stdout/stderr
    Dim result   As String
    Dim errorMsg As String
    result = Trim(g_lumExec.StdOut.ReadAll())
    errorMsg = Trim(g_lumExec.StdErr.ReadAll())
    
    Set g_lumExec = Nothing
    g_lumJobJpeg = ""
    
    If IsNumeric(result) Then
        Dim lumVal As Integer
        lumVal = CInt(result)
        If lumVal >= 0 And lumVal <= 255 Then
            g_lastLuminance = lumVal
            g_lumStaleness = 0
            Range("dataLuminance").value = lumVal
            PollLuminanceCalc = lumVal
            Exit Function
        End If
        LogEvent "LUMINANCE", "Poll: out-of-range result " & lumVal
    Else
        LogEvent "LUMINANCE", "Poll: non-numeric result. " & _
                 "stdout=[" & Left(result, 100) & "] " & _
                 "stderr=[" & Left(errorMsg, 200) & "]"
    End If
    
    PollLuminanceCalc = LUM_DONE_NORESULT
    Exit Function
ErrHandler:
    LogEvent "LUMINANCE", "PollLuminanceCalc error: " & Err.Description
    On Error Resume Next
    Set g_lumExec = Nothing
    On Error GoTo 0
    PollLuminanceCalc = LUM_DONE_NORESULT
End Function

' Accessor for phase handlers / monitor. Returns most recent successful
' luminance, or -1 if no measurement has ever succeeded.
Public Function GetLatestLuminance() As Integer
    GetLatestLuminance = g_lastLuminance
End Function

' Accessor for phase handlers / monitor. Returns shots elapsed since
' g_lastLuminance was updated. Reset to 0 by a successful poll.
Public Function GetLuminanceStaleness() As Long
    GetLuminanceStaleness = g_lumStaleness
End Function

' Called once per shot by SequenceLoop after TakePhoto. Increments the
' staleness counter so phase handlers can tell how old the current
' g_lastLuminance reading is.
Public Sub BumpLuminanceStaleness()
    g_lumStaleness = g_lumStaleness + 1
End Sub

' Reset luminance state at the start of a new sequence. Called from
' Sequence.StartSequence so a previous shoot's stale reading doesn't
' bleed into the new one.
Public Sub ResetLuminanceState()
    If Not (g_lumExec Is Nothing) Then
        ' Defensive — kill any orphan job from a previous run
        On Error Resume Next
        g_lumExec.Terminate
        On Error GoTo 0
        Set g_lumExec = Nothing
    End If
    g_lumJobJpeg = ""
    g_lastLuminance = -1
    g_lumStaleness = 0
End Sub

' Read operator target luminance values from Settings named ranges.
' Falls back to sensible defaults (per PROJECT_STATE provisional
' values) with a logged warning if either range is missing or
' non-numeric. Called from Sequence.StartSequence so any
' configuration problems show in the log before the shoot starts,
' not silently mid-shoot.
Public Sub ValidateLuminanceSettings()
    Dim sunsetVal As Variant, sunriseVal As Variant
    
    On Error Resume Next
    sunsetVal = Sheets("Settings").Range("dataLumTargetSunset").value
    sunriseVal = Sheets("Settings").Range("dataLumTargetSunrise").value
    On Error GoTo 0
    
    If Not IsNumeric(sunsetVal) Or sunsetVal = "" Then
        LogEvent "LUMINANCE", "WARNING: dataLumTargetSunset missing/non-numeric, " & _
                 "default 60 will be used. Add named range to Settings sheet."
    Else
        LogEvent "LUMINANCE", "Sunset target: " & sunsetVal
    End If
    
    If Not IsNumeric(sunriseVal) Or sunriseVal = "" Then
        LogEvent "LUMINANCE", "WARNING: dataLumTargetSunrise missing/non-numeric, " & _
                 "default 40 will be used. Add named range to Settings sheet."
    Else
        LogEvent "LUMINANCE", "Sunrise target: " & sunriseVal
    End If
End Sub

' Read sunset target with default fallback. Used by phase handlers
' so a missing named range doesn't crash the shoot mid-loop.
Public Function GetSunsetLumTarget() As Integer
    Const DEFAULT_SUNSET As Integer = 60
    On Error GoTo Fallback
    Dim v As Variant
    v = Sheets("Settings").Range("dataLumTargetSunset").value
    If IsNumeric(v) And v <> "" Then
        GetSunsetLumTarget = CInt(v)
        Exit Function
    End If
Fallback:
    GetSunsetLumTarget = DEFAULT_SUNSET
End Function

Public Function GetSunriseLumTarget() As Integer
    Const DEFAULT_SUNRISE As Integer = 40
    On Error GoTo Fallback
    Dim v As Variant
    v = Sheets("Settings").Range("dataLumTargetSunrise").value
    If IsNumeric(v) And v <> "" Then
        GetSunriseLumTarget = CInt(v)
        Exit Function
    End If
Fallback:
    GetSunriseLumTarget = DEFAULT_SUNRISE
End Function


' ============================================================
' Thumbnail luminance
' ============================================================

' Fetch the most recently captured JPG thumbnail from the camera and
' save it to the user's Downloads folder as LastThumb.jpg. Returns
' the local save path on success, or "" on failure (with the failure
' already logged).
'
' Extracted from the previous monolithic GetLastThumbnailLuminance
' so KickOffLuminanceFromLastThumb can use just the CCAPI half
' without the Python part.
'
' BUG FIX (May 2026, session 2): the original parser had two off-by-one
' errors that produced URLs like
'   //ccapi//ver110//contents//cfex//102EOSR3"?type=jpeg&kind=number
'
'   1) Path extraction included the trailing closing-quote (the "
'      stayed in the path).
'   2) The "\\" -> "/" replace did nothing (JSON has \/ , not \\), and
'      the subsequent "\" -> "/" replace converted each \/ to // by
'      operating on a string that already had / from the original.
'      Net effect: every / in the path became //.
'
' New logic: use the existing ParseJsonField helper (which already
' returns the un-quoted value), then JSON-unescape \/ -> / .
'
' BUG B FIX (May 2026, session 2): the camera returns a JSON object
' with a "path" array, not newline-separated text. Old code
' Split(listResponse, Chr(10)) found nothing. New approach: find the
' LAST occurrence of ".JPG" in the response, back up to the preceding
' "/" to find the filename start.
Public Function FetchLastThumbnailToDisk() As String
    On Error GoTo ErrHandler
    Dim dirResponse As String
    dirResponse = CameraGet("/ccapi/ver110/devicestatus/currentdirectory")
    If dirResponse = "" Then FetchLastThumbnailToDisk = "": Exit Function
    
    Dim myPath As String
    myPath = ParseJsonField(dirResponse, "path")
    myPath = Replace(myPath, "\/", "/")
    If LenB(myPath) = 0 Then
        LogEvent "CAMERA", "FetchThumbnail: couldn't parse path from " & dirResponse
        FetchLastThumbnailToDisk = ""
        Exit Function
    End If
    
    Dim pageResponse As String
    pageResponse = CameraGet(myPath & "?type=jpeg&kind=number")
    If pageResponse = "" Then FetchLastThumbnailToDisk = "": Exit Function
    
    ' Use ParseJsonField for robustness — it handles missing fields
    ' cleanly. Previous code used raw InStr/Mid arithmetic that could
    ' produce a negative Length argument when the camera returned an
    ' error response instead of the expected JSON, throwing
    ' "Invalid procedure call or argument" mid-function.
    Dim pageNum As String
    pageNum = Trim(ParseJsonField(pageResponse, "pagenumber"))
    If LenB(pageNum) = 0 Then
        LogEvent "CAMERA", "FetchThumbnail: no pagenumber in " & Left(pageResponse, 200)
        FetchLastThumbnailToDisk = ""
        Exit Function
    End If
    
    Dim listResponse As String
    listResponse = CameraGet(myPath & "?type=jpeg&kind=list&page=" & pageNum)
    If listResponse = "" Then FetchLastThumbnailToDisk = "": Exit Function
    
    Dim lastFile As String: lastFile = ""
    Dim upper    As String
    upper = UCase$(listResponse)
    
    Dim jpgEnd As Long
    jpgEnd = InStrRev(upper, ".JPG")
    If jpgEnd > 0 Then
        Dim slashStart As Long
        slashStart = InStrRev(listResponse, "/", jpgEnd) + 1
        If slashStart > 1 And jpgEnd + 4 > slashStart Then
            lastFile = Mid$(listResponse, slashStart, (jpgEnd + 4) - slashStart)
        End If
    End If
    
    If lastFile = "" Then
        LogEvent "CAMERA", "FetchThumbnail: no JPG found in: " & _
                 Left(listResponse, 300)
        FetchLastThumbnailToDisk = ""
        Exit Function
    End If
    
    Dim savePath As String
    savePath = Environ("USERPROFILE") & "\Downloads\LastThumb.jpg"
    Dim thumbURL As String
    thumbURL = CAMERA_IP() & myPath & "/" & lastFile & "?kind=thumbnail"
    If Not DownloadBinary(thumbURL, savePath) Then
        FetchLastThumbnailToDisk = ""
        Exit Function
    End If
    
    FetchLastThumbnailToDisk = savePath
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "FetchLastThumbnailToDisk error: " & Err.Description
    FetchLastThumbnailToDisk = ""
End Function

' Synchronous wrapper retained for backwards compatibility. Internally
' rides on the new kick-off/poll primitives so there's one code path
' for actual measurement. Used only by callers that explicitly want
' to block (test code, manual diagnostics). The production photo loop
' uses the non-blocking primitives directly.
Public Function GetLastThumbnailLuminance() As Integer
    On Error GoTo ErrHandler
    
    ' If a job is already in flight, don't stomp on it
    If Not (g_lumExec Is Nothing) Then
        LogEvent "LUMINANCE", "GetLastThumbnailLuminance: existing job in flight, waiting"
        Dim waitResult As Integer
        waitResult = SyncWaitForLuminance()
        GetLastThumbnailLuminance = waitResult
        Exit Function
    End If
    
    If Not KickOffLuminanceFromLastThumb() Then
        GetLastThumbnailLuminance = -1
        Exit Function
    End If
    
    GetLastThumbnailLuminance = SyncWaitForLuminance()
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "GetLastThumbnailLuminance error: " & Err.Description
    GetLastThumbnailLuminance = -1
End Function

' Helper for the sync wrapper. Polls until the in-flight job
' completes or times out. Uses Timer-based polling (no
' Application.Wait — same fix as the old CalcLuminance Bug 6).
Private Function SyncWaitForLuminance() As Integer
    Const POLL_INTERVAL_MS As Long = 100
    Const TOTAL_BUDGET_MS  As Long = 8000   ' 8s, generous for sync path
    
    Dim startTime As Double
    startTime = Timer
    
    Do
        Dim r As Integer
        r = PollLuminanceCalc()
        If r <> LUM_BUSY Then
            SyncWaitForLuminance = r
            Exit Function
        End If
        
        ' Sleep ~100ms with DoEvents to keep Excel responsive
        Dim sleepUntil As Double
        sleepUntil = Timer + (POLL_INTERVAL_MS / 1000#)
        Do While Timer < sleepUntil
            DoEvents
        Loop
        
        If (Timer - startTime) * 1000# > TOTAL_BUDGET_MS Then
            SyncWaitForLuminance = LUM_DONE_NORESULT
            Exit Function
        End If
    Loop
End Function


Public Function DownloadBinary(ByVal url As String, ByVal savePath As String) As Boolean
    On Error GoTo ErrHandler
    Dim http As Object, stream As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", url, False
    http.Send
    If http.Status = HTTP_OK Then
        Set stream = CreateObject("ADODB.Stream")
        stream.Open
        stream.Type = 1
        stream.Write http.responseBody
        stream.SaveToFile savePath, 2
        stream.Close
        Set stream = Nothing
        DownloadBinary = True
    Else
        LogEvent "CAMERA", "DownloadBinary HTTP " & http.Status
        DownloadBinary = False
    End If
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "DownloadBinary error: " & Err.Description
    DownloadBinary = False
End Function

' LEGACY synchronous luminance calculation. Blocks Excel for up to 5s
' waiting for Python. Retained for ad-hoc diagnostics; production code
' uses KickOffLuminanceCalc + PollLuminanceCalc instead. See module
' header for the non-blocking pipeline overview.
Public Function CalcLuminance(ByVal jpegPath As String) As Integer
    On Error GoTo ErrHandler
    
    Dim scriptPath As String
    scriptPath = FindLuminanceScript()
    If LenB(scriptPath) = 0 Then
        ' Path was already logged with full search list by FindLuminanceScript
        CalcLuminance = -1
        Exit Function
    End If
    
    Dim shell As Object
    Set shell = CreateObject("WScript.Shell")
    Dim exec As Object
    Set exec = shell.exec("python """ & scriptPath & """ """ & jpegPath & """")
    
    ' BUG 6 FIX (May 2026, session 2): the previous loop used
    '   Application.Wait Now + TimeValue("00:00:00") + 0.0001
    ' where 0.0001 of a day is 8.6 seconds. So each "iteration" of
    ' the polling loop waited 8.6s. Python finishing in 0.3s still
    ' incurred at least one full iteration — adding 9 seconds per
    ' luminance call. That was the cause of the Phase 2b/3/4a 9-second
    ' phase= overhead.
    '
    ' New approach: poll roughly every 100ms using Timer, with a
    ' total budget of 5 seconds (well above typical Python+PIL startup
    ' time of 0.3-0.8s). DoEvents keeps Excel responsive between polls.
    Const POLL_INTERVAL_MS  As Long = 100
    Const TOTAL_TIMEOUT_MS  As Long = 5000
    
    Dim startTime As Double
    startTime = Timer
    
    Do While exec.Status = 0
        DoEvents
        ' Sleep ~100ms without bringing Excel to its knees
        Dim sleepUntil As Double
        sleepUntil = Timer + (POLL_INTERVAL_MS / 1000#)
        Do While Timer < sleepUntil
            DoEvents
        Loop
        
        If (Timer - startTime) * 1000# > TOTAL_TIMEOUT_MS Then Exit Do
    Loop
    
    If exec.Status = 0 Then
        LogEvent "CAMERA", "CalcLuminance: Python timeout after " & TOTAL_TIMEOUT_MS & "ms"
        On Error Resume Next
        exec.Terminate   ' don't leave a zombie python.exe behind
        On Error GoTo 0
        CalcLuminance = -1
        Exit Function
    End If
    
    Dim result   As String
    Dim errorMsg As String
    result = Trim(exec.StdOut.ReadAll())
    errorMsg = Trim(exec.StdErr.ReadAll())
    
    If IsNumeric(result) Then
        CalcLuminance = CInt(result)
    Else
        ' Python ran but didn't return a number. Log stderr to find
        ' out why (missing PIL, bad jpeg, etc.). One-time diagnostic;
        ' once we know the Python issue we'll see the same fix in
        ' luminance.py and not need this verbose log.
        LogEvent "CAMERA", "CalcLuminance: Python returned non-numeric. " & _
                 "stdout=[" & Left(result, 100) & "] " & _
                 "stderr=[" & Left(errorMsg, 200) & "]"
        CalcLuminance = -1
    End If
    Exit Function
    
ErrHandler:
    LogEvent "CAMERA", "CalcLuminance error: " & Err.Description
    CalcLuminance = -1
End Function

' Locate luminance.py by checking a list of standard locations. The path
' is cached after the first successful lookup (g_luminanceScriptPath at
' module top) so subsequent shots skip the file-system scan.
'
' Search order:
'   1. Cached value (if previously found)
'   2. Repo's Python/ folder, alongside the workbook  ← preferred location
'   3. ThisWorkbook.Path \ Python \ luminance.py
'   4. ThisWorkbook.Path \ luminance.py             (legacy)
'   5. Environ("USERPROFILE") \ OneDrive \ Documents \ luminance.py
'   6. Environ("USERPROFILE") \ Documents \ luminance.py
'
' Returns "" if nothing found, after logging the full search list once.
' That single failure log replaces the per-shot "luminance.py not found"
' rows we used to see.
Private Function FindLuminanceScript() As String
    ' Cached "found" path: return immediately
    If LenB(g_luminanceScriptPath) > 0 And g_luminanceScriptPath <> "(notfound)" Then
        FindLuminanceScript = g_luminanceScriptPath
        Exit Function
    End If
    
    ' Cached "not found" sentinel: don't keep searching every shot
    If g_luminanceScriptPath = "(notfound)" Then
        FindLuminanceScript = ""
        Exit Function
    End If
    
    Dim candidates As Variant
    candidates = Array( _
        ThisWorkbook.Path & "\Python\luminance.py", _
        ThisWorkbook.Path & "\luminance.py", _
        Environ("USERPROFILE") & "\OneDrive\Documents\Github\HyperLapse-Excel\Python\luminance.py", _
        Environ("USERPROFILE") & "\OneDrive\Documents\luminance.py", _
        Environ("USERPROFILE") & "\Documents\luminance.py")
    
    Dim i As Long
    For i = 0 To UBound(candidates)
        If Len(Dir(CStr(candidates(i)))) > 0 Then
            g_luminanceScriptPath = CStr(candidates(i))
            LogEvent "CAMERA", "luminance.py found at " & g_luminanceScriptPath
            FindLuminanceScript = g_luminanceScriptPath
            Exit Function
        End If
    Next i
    
    ' Not found — log all the places we looked, once
    Dim msg As String
    msg = "luminance.py NOT found. Searched: "
    For i = 0 To UBound(candidates)
        msg = msg & vbCrLf & "  " & candidates(i)
    Next i
    LogEvent "CAMERA", msg
    
    g_luminanceScriptPath = "(notfound)"   ' sentinel — don't search again this session
    FindLuminanceScript = ""
End Function

' ============================================================
' Arduino communication
' ============================================================

Public Sub SendHeartbeat()
    On Error Resume Next
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/heartbeat?msg=" & Format(Now(), "HH:nn:ss"), False
    http.Send
    Set http = Nothing
End Sub

Public Sub UpdateArduinoDisplay()
    On Error Resume Next
    Dim msg As String
    msg = "M|" & Range("dataCurrentAv").value & "|" & _
          Range("dataCurrentTv").value & "|ISO" & Range("dataCurrentISO").value
    msg = Replace(msg, "|", "%7C")
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/cameramsg?msg=" & msg, False
    http.Send
    Set http = Nothing
End Sub

' ============================================================
' Camera initialisation
' ============================================================

Public Sub InitCamera()
    LogEvent "CAMERA", "=== Camera initialisation ==="
    If Not SetShootingMode("m") Then
        MsgBox "Failed to set Manual mode - check camera is on and connected", vbExclamation
        Exit Sub
    End If
    If Not SetAperture("f1.8") Then
        MsgBox "Failed to set aperture f/1.8", vbExclamation
        Exit Sub
    End If
    If Not SetISO("100") Then
        MsgBox "Failed to set ISO 100", vbExclamation
        Exit Sub
    End If
    If Not SetShutterSpeed("1/5000") Then
        MsgBox "Failed to set shutter 1/5000", vbExclamation
        Exit Sub
    End If
    Range("dataShotCount").value = 0
    LogEvent "CAMERA", "Camera initialised: M f1.8 ISO100 1/5000"
    Range("dataCommCameraCheck").value = "Init OK " & Format(Now(), "HH:nn:ss")
End Sub
