Attribute VB_Name = "Cart"
' ============================================================
' HyperLapse Cart — Cart Log Processing Module
'
' Handles:
'   1. Cart log retrieval from Arduino (/cartlog endpoint)
'   2. Post-processing of scout run log into distance segments
'   3. Replay plan generation from operator speed inputs
'   4. Writing replay plan to Sequence sheet
'
' WORKFLOW:
'   Scout run (3pm, ~30 mins at 100 m/hr):
'     - Press btn19 (● Cart) on phone UI to start recording
'     - Drive path at 100 m/hr
'     - Press btn19 again to stop
'     - Run GetCartLog to retrieve events
'
'   Post-processing (3:30pm):
'     - Run ProcessCartLog to calculate distances
'     - Enter desired replay speed per segment on CartLog sheet
'     - Run GenerateReplayPlan to build timed plan on Sequence sheet
'
'   Replay (4pm onwards):
'     - Sequence module calls StartCartReplay which reads Sequence sheet
'       and steps through it via OnTime-driven RunCartReplayStep calls
'       (see "Replay plan execution" section in Sequence.bas).
' ============================================================

Option Explicit

' ============================================================
' Log retrieval
' ============================================================

' Retrieve cart log from Arduino and append to CartLog sheet
' Clears Arduino buffer after retrieval
' Call this repeatedly during/after scout run
Public Sub GetCartLog()
    On Error GoTo ErrHandler
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/cartlog", False
    http.Send
    
    If http.Status <> 200 Then
        LogEvent "CART", "GetCartLog HTTP " & http.Status
        Exit Sub
    End If
    
    Dim response As String
    response = Trim(http.ResponseText)
    Set http = Nothing
    
    If response = "" Or response = "EMPTY" Then
        LogEvent "CART", "GetCartLog: no new events"
        Exit Sub
    End If
    
    ' Append to CartLog sheet
    Dim ws As Worksheet
    Set ws = Sheets("CartLog")
    
    ' Add header if sheet is empty
    If ws.Cells(1, 1).value = "" Then
        ws.Cells(1, 1).value = "Timestamp"
        ws.Cells(1, 2).value = "Type"
        ws.Cells(1, 3).value = "Value"
        ws.Cells(1, 4).value = "Description"
    End If
    
    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.count, 1).End(xlUp).row + 1
    
    Dim lines() As String
    lines = Split(response, Chr(10))
    Dim i As Integer
    Dim newRows As Integer
    newRows = 0
    
    For i = 0 To UBound(lines)
        Dim line As String
        line = Trim(lines(i))
        If line <> "" Then
            Dim fields() As String
            fields = Split(line, ",")
            If UBound(fields) >= 2 Then
                ws.Cells(nextRow, 1).value = fields(0)   ' HH:MM:SS
                ws.Cells(nextRow, 2).value = fields(1)   ' S/T/X
                ws.Cells(nextRow, 3).value = CDbl(fields(2))  ' value
                ' Add human-readable description
                ws.Cells(nextRow, 4).value = EventDescription(fields(1), CDbl(fields(2)))
                nextRow = nextRow + 1
                newRows = newRows + 1
            End If
        End If
    Next i
    
    ' Format timestamp column
    ws.Columns(1).NumberFormat = "@"  ' Text — keep HH:MM:SS as string
    ws.Columns("A:D").AutoFit
    
    LogEvent "CART", "GetCartLog: " & newRows & " events retrieved"
    Exit Sub
ErrHandler:
    LogEvent "CART", "GetCartLog error: " & Err.Description
End Sub

' Human-readable description for log event
Private Function EventDescription(ByVal evtType As String, ByVal value As Double) As String
    Select Case UCase(Trim(evtType))
        Case "S"
            EventDescription = "Speed " & value & " m/hr"
        Case "T"
            Dim offset As Integer
            offset = CInt(value) - 98   ' 98 = CART_STEERING_CENTRE
            If offset > 0 Then
                EventDescription = "Steer right " & offset & Chr(176)
            ElseIf offset < 0 Then
                EventDescription = "Steer left " & Abs(offset) & Chr(176)
            Else
                EventDescription = "Steer centre"
            End If
        Case "X"
            EventDescription = "Stop"
        Case Else
            EventDescription = evtType & "=" & value
    End Select
End Function

' ============================================================
' Log post-processing — calculate distances
' ============================================================

' Process CartLog sheet into distance segments
' Reads events, calculates time between events, derives distances
' Writes processed segments to CartLog sheet columns E onwards
Public Sub ProcessCartLog()
    On Error GoTo ErrHandler
    
    Dim ws As Worksheet
    Set ws = Sheets("CartLog")
    
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.count, 1).End(xlUp).row
    
    If lastRow < 2 Then
        MsgBox "CartLog sheet is empty — retrieve log first.", vbExclamation
        Exit Sub
    End If
    
    ' Clear previous processing
    ws.Range("E1:K" & lastRow).Clear
    
    ' Add segment headers
    ws.Cells(1, 5).value = "Duration (s)"
    ws.Cells(1, 6).value = "Scout speed"
    ws.Cells(1, 7).value = "Distance (m)"
    ws.Cells(1, 8).value = "Replay speed"
    ws.Cells(1, 9).value = "Replay time (s)"
    ws.Cells(1, 10).value = "Replay start"
    ws.Cells(1, 11).value = "Replay end"
    
    ' Parse events and calculate segments
    Dim currentSpeed As Double
    currentSpeed = 0
    Dim currentSteering As Integer
    currentSteering = 0   ' offset from centre
    
    Dim segmentStart As String
    segmentStart = ""
    
    Dim i As Long
    For i = 2 To lastRow
        Dim evtTime   As String
        Dim evtType   As String
        Dim evtValue  As Double
        evtTime = CStr(ws.Cells(i, 1).value)
        evtType = CStr(ws.Cells(i, 2).value)
        evtValue = CDbl(ws.Cells(i, 3).value)
        
        ' Calculate duration since last event
        If segmentStart <> "" And i > 2 Then
            Dim prevTime As String
            prevTime = CStr(ws.Cells(i - 1, 1).value)
            Dim durationSecs As Double
            durationSecs = TimestampDiff(prevTime, evtTime)
            
            ' Distance = speed * time (speed in m/hr, time in seconds)
            Dim distanceM As Double
            distanceM = currentSpeed * (durationSecs / 3600)
            
            ws.Cells(i - 1, 5).value = Round(durationSecs, 1)
            ws.Cells(i - 1, 6).value = currentSpeed
            ws.Cells(i - 1, 7).value = Round(distanceM, 2)
        End If
        
        ' Update current state
        Select Case UCase(Trim(evtType))
            Case "S"
                currentSpeed = evtValue
            Case "X"
                currentSpeed = 0
        End Select
        
        If segmentStart = "" Then segmentStart = evtTime
    Next i
    
    ' Format
    ws.Columns("E:K").AutoFit
    ws.Range("H2:H" & lastRow).Interior.Color = RGB(255, 255, 204)  ' Yellow — operator fills these
    
    LogEvent "CART", "ProcessCartLog: " & (lastRow - 1) & " events processed"
    
    MsgBox "Cart log processed." & Chr(10) & Chr(10) & _
           "Now fill in the yellow 'Replay speed' column (col H)" & Chr(10) & _
           "for each segment, then run GenerateReplayPlan.", vbInformation
    Exit Sub
ErrHandler:
    LogEvent "CART", "ProcessCartLog error: " & Err.Description
End Sub

' ============================================================
' Replay plan generation
' ============================================================

' Generate timed replay plan from processed CartLog
' Operator must have filled in Replay speed (col H) for each segment
' Writes plan to Sequence sheet starting at row 2
' Replay starts at dataReplayStart time (named range, default 16:00)
Public Sub GenerateReplayPlan()
    On Error GoTo ErrHandler
    
    Dim wsSrc As Worksheet  ' CartLog
    Dim wsDst As Worksheet  ' Sequence
    Set wsSrc = Sheets("CartLog")
    Set wsDst = Sheets("Sequence")
    
    Dim lastRow As Long
    lastRow = wsSrc.Cells(wsSrc.Rows.count, 1).End(xlUp).row
    
    If lastRow < 2 Then
        MsgBox "CartLog is empty.", vbExclamation
        Exit Sub
    End If
    
    ' Get replay start time
    Dim replayStart As Date
    replayStart = Sheets("Settings").Range("dataReplayStart").value
    If replayStart = 0 Then
        replayStart = CDate(Int(Now()) + TimeValue("16:00:00"))
    End If
    
    ' Clear existing plan
    wsDst.Range("A2:G1000").Clear
    
    ' Write headers if needed
    If wsDst.Cells(1, 1).value = "" Then
        wsDst.Cells(1, 1).value = "Replay Time"
        wsDst.Cells(1, 2).value = "Action"
        wsDst.Cells(1, 3).value = "Value"
        wsDst.Cells(1, 4).value = "Notes"
        wsDst.Cells(1, 5).value = "Duration (s)"
        wsDst.Cells(1, 6).value = "Distance (m)"
        wsDst.Cells(1, 7).value = "Segment end time"
    End If
    
    Dim currentTime As Date
    currentTime = replayStart
    Dim dstRow As Long
    dstRow = 2
    
    ' Initial energise and speed=0
    wsDst.Cells(dstRow, 1).value = currentTime
    wsDst.Cells(dstRow, 2).value = "ENERGISE"
    wsDst.Cells(dstRow, 3).value = 0
    wsDst.Cells(dstRow, 4).value = "Energise motors"
    dstRow = dstRow + 1
    
    Dim totalDistance As Double
    totalDistance = 0
    
    Dim i As Long
    For i = 2 To lastRow
        Dim evtType    As String
        Dim evtValue   As Double
        Dim distance   As Double
        Dim replaySpd  As Double
        Dim duration   As Double
        
        evtType = CStr(wsSrc.Cells(i, 2).value)
        evtValue = CDbl(wsSrc.Cells(i, 3).value)
        distance = 0
        
        ' Get distance and replay speed for speed segments
        If wsSrc.Cells(i, 7).value <> "" Then distance = CDbl(wsSrc.Cells(i, 7).value)
        If wsSrc.Cells(i, 8).value <> "" Then replaySpd = CDbl(wsSrc.Cells(i, 8).value)
        
        Select Case UCase(Trim(evtType))
            Case "S"
                If evtValue > 0 And distance > 0 Then
                    ' Calculate replay duration from distance / replay speed
                    If replaySpd > 0 Then
                        duration = (distance / replaySpd) * 3600  ' seconds
                    Else
                        ' Default — use same speed as scout run
                        duration = (distance / evtValue) * 3600
                    End If
                    
                    ' Write speed command
                    wsDst.Cells(dstRow, 1).value = currentTime
                    wsDst.Cells(dstRow, 2).value = "SPEED"
                    wsDst.Cells(dstRow, 3).value = IIf(replaySpd > 0, replaySpd, evtValue)
                    wsDst.Cells(dstRow, 4).value = "Segment " & (i - 1) & _
                                                   " — " & Round(distance, 1) & "m"
                    wsDst.Cells(dstRow, 5).value = Round(duration, 0)
                    wsDst.Cells(dstRow, 6).value = Round(distance, 2)
                    
                    ' Advance time by segment duration
                    currentTime = currentTime + (duration / 86400#)
                    wsDst.Cells(dstRow, 7).value = currentTime
                    
                    totalDistance = totalDistance + distance
                    dstRow = dstRow + 1
                End If
                
            Case "T"
                ' Steering change — insert at current time
                Dim steerOffset As Integer
                steerOffset = CInt(evtValue) - 98
                wsDst.Cells(dstRow, 1).value = currentTime
                wsDst.Cells(dstRow, 2).value = "STEER"
                wsDst.Cells(dstRow, 3).value = steerOffset
                wsDst.Cells(dstRow, 4).value = "Steer " & IIf(steerOffset >= 0, "+" & steerOffset, steerOffset) & Chr(176)
                dstRow = dstRow + 1
                
            Case "X"
                ' Stop
                wsDst.Cells(dstRow, 1).value = currentTime
                wsDst.Cells(dstRow, 2).value = "STOP"
                wsDst.Cells(dstRow, 3).value = 0
                wsDst.Cells(dstRow, 4).value = "Cart stop"
                dstRow = dstRow + 1
        End Select
    Next i
    
    ' Format
    wsDst.Columns(1).NumberFormat = "HH:nn:ss"
    wsDst.Columns(7).NumberFormat = "HH:nn:ss"
    wsDst.Columns("A:G").AutoFit
    
    LogEvent "CART", "GenerateReplayPlan: " & (dstRow - 2) & " replay steps, " & _
             Round(totalDistance, 1) & "m total, finishes " & Format(currentTime, "HH:nn:ss")
    
    MsgBox "Replay plan generated." & Chr(10) & Chr(10) & _
           "Total distance: " & Round(totalDistance, 1) & "m" & Chr(10) & _
           "Cart stops at: " & Format(currentTime, "HH:nn:ss") & Chr(10) & Chr(10) & _
           "Review the Sequence sheet then run StartSequence.", vbInformation
    Exit Sub
ErrHandler:
    LogEvent "CART", "GenerateReplayPlan error: " & Err.Description
End Sub

' ============================================================
' Gimbal log processing
' ============================================================

' Retrieve gimbal waypoint log and append to GimbalLog sheet
Public Sub GetGimbalLogToSheet()
    On Error GoTo ErrHandler
    
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/gimballog", False
    http.Send
    
    If http.Status <> 200 Then
        LogEvent "CART", "GetGimbalLog HTTP " & http.Status
        Exit Sub
    End If
    
    Dim response As String
    response = Trim(http.ResponseText)
    Set http = Nothing
    
    If response = "" Or response = "EMPTY" Then
        LogEvent "CART", "GetGimbalLog: no waypoints"
        Exit Sub
    End If
    
    Dim ws As Worksheet
    Set ws = Sheets("GimbalLog")
    
    ' Add headers if empty
    If ws.Cells(1, 1).value = "" Then
        ws.Cells(1, 1).value = "Timestamp"
        ws.Cells(1, 2).value = "Yaw (°)"
        ws.Cells(1, 3).value = "Pitch (°)"
        ws.Cells(1, 4).value = "Notes"
    End If
    
    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.count, 1).End(xlUp).row + 1
    
    Dim lines() As String
    lines = Split(response, Chr(10))
    Dim i As Integer
    Dim newRows As Integer
    newRows = 0
    
    For i = 0 To UBound(lines)
        Dim line As String
        line = Trim(lines(i))
        If line <> "" Then
            Dim fields() As String
            fields = Split(line, ",")
            If UBound(fields) >= 2 Then
                ws.Cells(nextRow, 1).value = fields(0)         ' HH:MM:SS
                ws.Cells(nextRow, 2).value = CDbl(fields(1))   ' Yaw
                ws.Cells(nextRow, 3).value = CDbl(fields(2))   ' Pitch
                nextRow = nextRow + 1
                newRows = newRows + 1
            End If
        End If
    Next i
    
    ws.Columns("A:D").AutoFit
    LogEvent "CART", "GetGimbalLog: " & newRows & " waypoints retrieved"
    Exit Sub
ErrHandler:
    LogEvent "CART", "GetGimbalLog error: " & Err.Description
End Sub

' ============================================================
' Utility
' ============================================================

' Calculate seconds between two HH:MM:SS timestamp strings
Private Function TimestampDiff(ByVal t1 As String, ByVal t2 As String) As Double
    On Error GoTo ErrHandler
    Dim d1 As Date
    Dim d2 As Date
    d1 = CDate("00:00:00 " & t1)
    d2 = CDate("00:00:00 " & t2)
    ' Handle midnight crossing
    Dim diff As Double
    diff = (d2 - d1) * 86400#
    If diff < 0 Then diff = diff + 86400#
    TimestampDiff = diff
    Exit Function
ErrHandler:
    TimestampDiff = 0
End Function

' Clear CartLog sheet (before a new scout run)
Public Sub ClearCartLog()
    If MsgBox("Clear all cart log data?", vbYesNo + vbQuestion) = vbYes Then
        Sheets("CartLog").Cells.Clear
        LogEvent "CART", "CartLog cleared"
    End If
End Sub

' Clear GimbalLog sheet (before a new session)
Public Sub ClearGimbalLog()
    If MsgBox("Clear all gimbal log data?", vbYesNo + vbQuestion) = vbYes Then
        Sheets("GimbalLog").Cells.Clear
        LogEvent "CART", "GimbalLog cleared"
    End If
End Sub

' Show summary of CartLog — total distance, segments, duration
Public Sub CartLogSummary()
    Dim ws As Worksheet
    Set ws = Sheets("CartLog")
    
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.count, 1).End(xlUp).row
    
    If lastRow < 2 Then
        MsgBox "CartLog is empty.", vbInformation
        Exit Sub
    End If
    
    Dim totalDist  As Double
    Dim speedCount As Integer
    Dim steerCount As Integer
    Dim stopCount  As Integer
    
    Dim i As Long
    For i = 2 To lastRow
        Select Case UCase(Trim(CStr(ws.Cells(i, 2).value)))
            Case "S": speedCount = speedCount + 1
            Case "T": steerCount = steerCount + 1
            Case "X": stopCount = stopCount + 1
        End Select
        If ws.Cells(i, 7).value <> "" Then
            totalDist = totalDist + CDbl(ws.Cells(i, 7).value)
        End If
    Next i
    
    MsgBox "Cart Log Summary" & Chr(10) & Chr(10) & _
           "Events: " & (lastRow - 1) & Chr(10) & _
           "Speed changes: " & speedCount & Chr(10) & _
           "Steering changes: " & steerCount & Chr(10) & _
           "Stops: " & stopCount & Chr(10) & _
           "Total distance: " & Round(totalDist, 1) & "m", _
           vbInformation, "CartLog Summary"
End Sub



