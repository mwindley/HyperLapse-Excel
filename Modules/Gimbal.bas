Attribute VB_Name = "Gimbal"
' ============================================================
' DJI Ronin RS4 Pro — Gimbal Control Module
' Arduino IP: read from Settings sheet named range dataArduinoIP
' All commands sent via Arduino HTTP endpoints
' ============================================================

Option Explicit

' ── Gimbal limits (RS4 Pro confirmed) ────────────────────────
Public Const GIMBAL_YAW_MIN     As Double = -180#
Public Const GIMBAL_YAW_MAX     As Double = 180#
Public Const GIMBAL_PITCH_MIN   As Double = -56#
Public Const GIMBAL_PITCH_MAX   As Double = 146#
Public Const GIMBAL_ROLL_MIN    As Double = -30#
Public Const GIMBAL_ROLL_MAX    As Double = 30#

' Default move time in seconds
Public Const GIMBAL_DEFAULT_TIME As Double = 2#

' ============================================================
' Core gimbal movement
' ============================================================

' Move gimbal to absolute yaw/roll/pitch over time (seconds)
' Yaw is relative to cart heading
' Pitch is relative to earth horizon (RS4 Pro stabilises)
' Roll is always 0 for timelapse
Public Function GimbalPosition(ByVal myYaw As Double, _
                                ByVal myRoll As Double, _
                                ByVal myPitch As Double, _
                                Optional ByVal myTime As Double = GIMBAL_DEFAULT_TIME) As Boolean
    On Error GoTo ErrHandler
    
    ' Clamp to RS4 Pro limits
    myYaw = ClampDouble(myYaw, GIMBAL_YAW_MIN, GIMBAL_YAW_MAX)
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
        LogEvent "GIMBAL", "Move failed — HTTP " & http.Status
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
        fields = Split(http.ResponseText, ",")
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
    response = Trim(http.ResponseText)
    Set http = Nothing
    
    If response = "" Or response = "EMPTY" Then
        LogEvent "GIMBAL", "GetGimbalLog: no events"
        Exit Sub
    End If
    
    ' Append to GimbalLog sheet
    Dim ws As Worksheet
    Set ws = Sheets("GimbalLog")
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
                ws.Cells(nextRow, 2).value = CDbl(fields(1))  ' Yaw
                ws.Cells(nextRow, 3).value = CDbl(fields(2))  ' Pitch
                nextRow = nextRow + 1
            End If
        End If
    Next i
    
    LogEvent "GIMBAL", "GimbalLog retrieved — " & (nextRow - 2) & " waypoints"
    Exit Sub
ErrHandler:
    LogEvent "GIMBAL", "GetGimbalLog error: " & Err.Description
End Sub

' ============================================================
' Sequence helper — smooth move with wait
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

' Send current camera settings to Arduino web UI camera bar
' Called after any camera setting change
' (Wrapper here so Gimbal module can call it without circular reference)
Public Sub UpdateGimbalDisplay()
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
