Attribute VB_Name = "Gimbal"
' ============================================================
' HyperLapse Cart - Gimbal Control Module
'
' PURPOSE
'   All DJI Ronin RS4 Pro gimbal control. The gimbal is driven by an
'   Arduino Uno R4 (sketch: DJI_Ronin_UnoR4_v2 v13) via the RS4''s SBUS
'   port; this module talks HTTP to that Arduino - it never speaks to
'   the gimbal directly.
'
'   Provides:
'     - GimbalPosition / GimbalHome - absolute moves with timed easing
'     - GimbalMoveAndWait - synchronous variant for setup/teardown
'     - GetGimbalStatus - polls Arduino /status and updates named ranges
'                         (yaw, roll, pitch, plus cart steering / voltage
'                         / speed / overdrive - all on one HTTP call)
'     - GimbalHeartbeat - keepalive ping during the shoot
'     - GetGimbalLog - fetches the high-speed waypoint log recorded by
'                      the Arduino during a recce or rehearsal pass
'
' COORDINATE CONVENTIONS
'   Yaw   - relative to cart heading. CUMULATIVE (unwrapped) - RS4 Pro
'           can wind through multiple rotations. Per-shoot envelope is
'           enforced by this module from Settings named ranges
'           gimbalYawEnvelopeMin / gimbalYawEnvelopeMax (default +/-225,
'           450 deg span). Cable budget = 450 deg; the operator edits the
'           envelope cells per shoot to position the span where the
'           plan needs it (e.g. -160 to +290). Cart firmware is dumb
'           on yaw and accepts whatever value Excel sends.
'   Pitch - relative to earth horizon (the RS4 Pro stabilises gravity),
'           +146 deg / -56 deg per RS4 Pro spec
'   Roll  - always 0 for timelapse work (+/-30 deg available if ever needed)
'
' FUTURE WORK - Gimbal log replay
'   The intent of GetGimbalLog is to capture high-speed gimbal motion
'   during a fast recce pass and then replay it in slow time during the
'   real overnight shoot. The pipeline (not yet built) is:
'     1. Recce pass: cart moves quickly, GimbalLog records waypoints.
'     2. Post-process: convert waypoints into a slow-time plan on a
'        sheet with rows of (Time, Yaw, Pitch).
'     3. Playback: an OnTime-driven loop (mirroring the Bug 5 cart
'        replay pattern in Sequence.bas) issues GimbalPosition calls
'        at the planned times alongside the photo loop.
'   UpdateGimbalDisplay_FUTURE is the parked seed of step 3''s display
'   refresh - see comment on that sub.
' ============================================================

Option Explicit

' -- Gimbal limits (RS4 Pro confirmed) ------------------------
' Yaw has NO hardcoded constant - it's cumulative, enforced per-shoot
' via Settings named ranges (see EnsureGimbalEnvelopeNamedRanges).
' Roll/pitch are mechanical-mount limits, hardcoded.
Public Const GIMBAL_PITCH_MIN   As Double = -56#
Public Const GIMBAL_PITCH_MAX   As Double = 146#
Public Const GIMBAL_ROLL_MIN    As Double = -30#
Public Const GIMBAL_ROLL_MAX    As Double = 30#

' Default yaw envelope (+/-225 deg, 450 deg span centred on cart-forward).
' Seeded into Settings cells on first call; operator edits per shoot.
Private Const DEFAULT_YAW_ENVELOPE_MIN As Double = -225#
Private Const DEFAULT_YAW_ENVELOPE_MAX As Double = 225#

' Default move time in seconds
Public Const GIMBAL_DEFAULT_TIME As Double = 2#

' ============================================================
' Core gimbal movement
' ============================================================

' Move gimbal to absolute yaw/roll/pitch over time (seconds)
' Yaw is cumulative (unwrapped), relative to cart heading.
' Pitch is relative to earth horizon (RS4 Pro stabilises).
' Roll is always 0 for timelapse.
'
' Yaw envelope: read from Settings named ranges gimbalYawEnvelopeMin /
' gimbalYawEnvelopeMax. Defaults +/-225 deg (450 deg span) are seeded on first
' call; operator edits cells per shoot. Commands outside the envelope
' are REFUSED (not clamped) - returns False, logs the violation. Cart
' firmware accepts whatever it receives; envelope enforcement is here.
' Roll/pitch keep mechanical clamps (mount can't exceed those).
Public Function GimbalPosition(ByVal myYaw As Double, _
                                ByVal myRoll As Double, _
                                ByVal myPitch As Double, _
                                Optional ByVal myTime As Double = GIMBAL_DEFAULT_TIME) As Boolean
    On Error GoTo ErrHandler

    ' Lazy-init the envelope cells/named ranges on first call
    EnsureGimbalEnvelopeNamedRanges

    ' Read current envelope from Settings
    Dim envMin As Double, envMax As Double
    envMin = CDbl(ThisWorkbook.names("gimbalYawEnvelopeMin").refersToRange.value)
    envMax = CDbl(ThisWorkbook.names("gimbalYawEnvelopeMax").refersToRange.value)

    ' Hard refuse if yaw outside envelope - Excel owns the cable budget
    If myYaw < envMin Or myYaw > envMax Then
        LogEvent "GIMBAL", "Move REFUSED - yaw=" & Format(myYaw, "0.0") & _
                           " outside envelope [" & Format(envMin, "0.0") & _
                           ", " & Format(envMax, "0.0") & "]"
        GimbalPosition = False
        Exit Function
    End If

    ' Roll/pitch keep mechanical clamps (mount limits, not plan envelope)
    myRoll = ClampDouble(myRoll, GIMBAL_ROLL_MIN, GIMBAL_ROLL_MAX)
    myPitch = ClampDouble(myPitch, GIMBAL_PITCH_MIN, GIMBAL_PITCH_MAX)

    Dim url As String
    url = ARDUINO_IP() & "/move?yaw=" & Format(myYaw, "0.0") & _
                              "&roll=" & Format(myRoll, "0.0") & _
                              "&pitch=" & Format(myPitch, "0.0") & _
                              "&time=" & Format(myTime, "0.0")
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", url, False
    http.Send
    
    GimbalPosition = (http.Status = 200)
    
    If GimbalPosition Then
        ' Update named ranges
        Range("dataGimbalTargetYaw").value = myYaw
        Range("dataGimbalTargetPitch").value = myPitch
        Range("dataGimbalTargetRoll").value = myRoll
        LogEvent "GIMBAL", "Move to Yaw=" & myYaw & " Pitch=" & myPitch & _
                           " Roll=" & myRoll & " Time=" & myTime & "s"
    Else
        LogEvent "GIMBAL", "Move failed - HTTP " & http.Status
    End If
    
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "GIMBAL", "GimbalPosition error: " & Err.Description
    GimbalPosition = False
End Function

' Move gimbal to home position (0, 0, 0)
Public Function GimbalHome() As Boolean
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/home", False
    http.Send
    GimbalHome = (http.Status = 200)
    If GimbalHome Then
        Range("dataGimbalTargetYaw").value = 0
        Range("dataGimbalTargetPitch").value = 0
        Range("dataGimbalTargetRoll").value = 0
        LogEvent "GIMBAL", "Home (0,0,0)"
    End If
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "GIMBAL", "GimbalHome error: " & Err.Description
    GimbalHome = False
End Function

' ============================================================
' Status and heartbeat
' ============================================================

' Send heartbeat to Arduino and update Monitor sheet
Public Sub GimbalHeartbeat()
    On Error Resume Next
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    
    ' Send heartbeat timestamp
    http.Open "GET", ARDUINO_IP() & "/heartbeat?msg=" & Format(Now(), "HH:nn:ss"), False
    http.Send
    
    Set http = Nothing
End Sub

' Get current gimbal position from Arduino /status
' Returns True if successful, updates named ranges
Public Function GetGimbalStatus() As Boolean
    On Error GoTo ErrHandler
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/status", False
    http.Send
    
    If http.Status = 200 Then
        Dim fields() As String
        fields = Split(http.responseText, ",")
        If UBound(fields) >= 2 Then
            Range("dataGimbalYaw").value = CDbl(Trim(fields(0)))
            Range("dataGimbalRoll").value = CDbl(Trim(fields(1)))
            Range("dataGimbalPitch").value = CDbl(Trim(fields(2)))
        End If
        ' Update cart status fields if present
        If UBound(fields) >= 7 Then
            Range("dataCartSteering").value = CDbl(Trim(fields(4)))
            Range("dataCartVoltage").value = CDbl(Trim(fields(5)))
            Range("dataCartSpeed").value = CDbl(Trim(fields(6)))
            Range("dataCartOverdrive").value = CDbl(Trim(fields(7)))
        End If
        GetGimbalStatus = True
    Else
        GetGimbalStatus = False
    End If
    
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "GIMBAL", "GetGimbalStatus error: " & Err.Description
    GetGimbalStatus = False
End Function

' ============================================================
' Gimbal log retrieval
' ============================================================

' Retrieve gimbal waypoint log from Arduino and append to GimbalLog sheet
' Each row: Timestamp | Yaw | Pitch
Public Sub GetGimbalLog()
    On Error GoTo ErrHandler

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/gimballog", False
    http.Send

    If http.Status <> 200 Then
        LogEvent "GIMBAL", "GetGimbalLog HTTP " & http.Status
        Exit Sub
    End If

    Dim response As String
    response = Trim(http.responseText)
    Set http = Nothing

    If response = "" Or response = "EMPTY" Then
        LogEvent "GIMBAL", "GetGimbalLog: no events"
        Exit Sub
    End If

    ' Cart serves a rich CSV per row, 11 fields (append-only; the cart
    ' /gimballog read is retrieve-and-clear):
    '   0 time  1 yaw  2 pitch  3 type  4 kf  5 frame  6 obj  7 mode
    '   8 dyaw  9 dpitch  10 label
    ' All but frame are carried into the GimbalLog sheet. Sheet layout:
    '   A Time B Type C Yaw D Pitch E Obj F Mode G KF H dyaw I dpitch J Label
    Dim ws As Worksheet
    Set ws = Sheets("GimbalLog")

    ' Write the rich header EVERY fetch - overwrite any stale legacy header.
    ' A leftover row-1 (e.g. Timestamp|Yaw|Pitch|Notes) silently forces the
    ' puller down the legacy path, so the meaning is pinned here each time.
    ws.Cells(1, 1).value = "Time"
    ws.Cells(1, 2).value = "Type"
    ws.Cells(1, 3).value = "Yaw"
    ws.Cells(1, 4).value = "Pitch"
    ws.Cells(1, 5).value = "Obj"
    ws.Cells(1, 6).value = "Mode"
    ws.Cells(1, 7).value = "KF"
    ws.Cells(1, 8).value = "dyaw"
    ws.Cells(1, 9).value = "dpitch"
    ws.Cells(1, 10).value = "Label"

    Dim NextRow As Long
    NextRow = ws.Cells(ws.rows.count, 1).End(xlUp).row + 1
    If NextRow < 2 Then NextRow = 2

    Dim lines() As String, i As Long, n As Long
    lines = Split(response, Chr(10))
    n = 0
    For i = 0 To UBound(lines)
        Dim line As String
        line = Trim(lines(i))
        If line <> "" Then
            Dim f() As String
            f = Split(line, ",")
            ' Need through dpitch (index 9); label (10) optional.
            If UBound(f) >= 9 Then
                Dim lbl As String
                If UBound(f) >= 10 Then lbl = f(10) Else lbl = ""
                ' Cart may send empty label as the literal two-char pair;
                ' strip a surrounding quote pair so empty stays truly blank.
                lbl = Trim(lbl)
                If Len(lbl) >= 2 Then
                    If Left(lbl, 1) = Chr(34) And Right(lbl, 1) = Chr(34) Then
                        lbl = Mid(lbl, 2, Len(lbl) - 2)
                    End If
                End If
                ws.Cells(NextRow, 1).value = f(0)
                ws.Cells(NextRow, 2).value = f(3)
                ws.Cells(NextRow, 3).value = CDbl(f(1))
                ws.Cells(NextRow, 4).value = CDbl(f(2))
                ws.Cells(NextRow, 5).value = f(6)
                ws.Cells(NextRow, 6).value = f(7)
                ws.Cells(NextRow, 7).value = f(4)
                ws.Cells(NextRow, 8).value = CDbl(f(8))
                ws.Cells(NextRow, 9).value = CDbl(f(9))
                ws.Cells(NextRow, 10).value = lbl
                NextRow = NextRow + 1
                n = n + 1
            End If
        End If
    Next i

    LogEvent "GIMBAL", "GimbalLog retrieved - " & n & " row(s)"
    Exit Sub
ErrHandler:
    LogEvent "GIMBAL", "GetGimbalLog error: " & Err.Description
End Sub

' ============================================================
' Sequence helper - smooth move with wait
' ============================================================

' Move gimbal and wait for the move to complete before returning
' Use in sequence macros where next action depends on gimbal arriving
Public Sub GimbalMoveAndWait(ByVal myYaw As Double, _
                              ByVal myPitch As Double, _
                              Optional ByVal myTime As Double = GIMBAL_DEFAULT_TIME)
    GimbalPosition myYaw, 0#, myPitch, myTime
    ' Wait for move to complete plus small buffer
    Application.Wait Now + (myTime + 0.5) / 86400#
End Sub

' Send current camera settings to the Arduino's gimbal-mounted display.
'
' NOTE - currently a near-duplicate of Camera.UpdateArduinoDisplay and not
' wired into the live shoot. It is preserved here as the seed of a future
' gimbal-log-replay capability:
'
'   - Arduino's GimbalLog records actual yaw/pitch waypoints at high speed
'     during a recce or rehearsal pass.
'   - A post-processing step (TBD) converts that log into a slow-time
'     replay plan on the "Sequence" sheet (or a new "GimbalPlan" sheet).
'   - During the real shoot, this routine will be the per-frame display
'     update that runs from inside the gimbal-replay step, alongside the
'     existing camera-settings display update - letting the on-cart screen
'     show "where the gimbal is heading next" as well as exposure data.
'
' Until that pipeline lands, this is parked and unused. Do NOT delete:
' it documents the contract for the future replay step. See also the
' "Replay plan execution" section in Sequence.bas (Bug 5 fix) which now
' uses the same pattern for cart actions.
Public Sub UpdateGimbalDisplay_FUTURE()
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
' Utility
' ============================================================

Private Function ClampDouble(ByVal val As Double, _
                              ByVal minVal As Double, _
                              ByVal maxVal As Double) As Double
    If val < minVal Then
        ClampDouble = minVal
    ElseIf val > maxVal Then
        ClampDouble = maxVal
    Else
        ClampDouble = val
    End If
End Function


' Ensure gimbalYawEnvelopeMin / gimbalYawEnvelopeMax named ranges exist
' on the Settings sheet. Seeds defaults (+/-225 deg = 450 deg span) on first
' creation. Idempotent - if either name already exists, leaves both
' alone. Pattern mirrors Formula.bas's EnsureActiveBranchNamedRange.
Private Sub EnsureGimbalEnvelopeNamedRanges()
    Dim nm As Name
    Dim minExists As Boolean, maxExists As Boolean
    minExists = False
    maxExists = False
    For Each nm In ThisWorkbook.names
        If nm.Name = "gimbalYawEnvelopeMin" Then minExists = True
        If nm.Name = "gimbalYawEnvelopeMax" Then maxExists = True
    Next nm

    If minExists And maxExists Then Exit Sub

    Dim wsSet As Worksheet
    Set wsSet = ThisWorkbook.Sheets("Settings")

    ' Place at rows 45-46 on Settings (immediately below dataActiveBranch
    ' at row 44). Label in column B (italic), value in column C.
    If Not minExists Then
        wsSet.Range("$C$45").value = DEFAULT_YAW_ENVELOPE_MIN
        wsSet.Cells(45, 2).value = "Gimbal yaw envelope min ( deg)"
        wsSet.Cells(45, 2).Font.Italic = True
        ThisWorkbook.names.Add Name:="gimbalYawEnvelopeMin", _
                               refersTo:="=Settings!$C$45"
    End If

    If Not maxExists Then
        wsSet.Range("$C$46").value = DEFAULT_YAW_ENVELOPE_MAX
        wsSet.Cells(46, 2).value = "Gimbal yaw envelope max ( deg)"
        wsSet.Cells(46, 2).Font.Italic = True
        ThisWorkbook.names.Add Name:="gimbalYawEnvelopeMax", _
                               refersTo:="=Settings!$C$46"
    End If
End Sub






