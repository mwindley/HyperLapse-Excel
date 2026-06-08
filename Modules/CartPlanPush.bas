Attribute VB_Name = "CartPlanPush"
' ============================================================
' HyperLapse Cart — Cart Plan Push (Day 24)
'
' Reads the LEFT-zone Cart Plan (DRIVE/STOP waypoint rows) on the
' Plan sheet and pushes it to the cart as /plan/load segments.
'
' This is the "ready half": cart motion only. The gimbal half
' (middle zone, cubics, TrackIntervals) is PlanPush.bas and is not
' yet push-capable (no Stage 4, cubics deferred).
'
' Public entry:
'   PushCartPlan — validate + build segments + (dry-run or real) push
'
' Cart segment CSV (from sketch planParseSegment):
'   TYPE,VAL,STEER,SPEED,END
'     TYPE  : m (move) | s (stop)
'     VAL   : dist_mm (move) | duration_ms (stop)
'     STEER : signed degrees (Turn col)
'     SPEED : m/hr
'     END   : d (dist) | t (duration) | o (operator)
'   Wrapper: /plan/load?n=N&s1=<csv>&s2=<csv>...
'
' Left-zone columns (Plan sheet, data from row 6):
'   B=Step  C=Action(DRIVE/STOP)  D=Dist(m)  E=Speed(m/hr)
'   F=Turn(deg)  G=Hold(s)
'
' Mapping:
'   DRIVE -> m, D*1000 mm, F steer, E m/hr, end=d
'   STOP  -> s, G*1000 ms,  0 steer, 0,      end=t
'
' Dry-run (Settings!dataPlanPushDryRun = TRUE): build + log the URL,
' do NOT contact cart. Real push: ping /status first, then GET.
' Transport pattern mirrors AstroPush.bas (WinHttp, GET, status 200).
' ============================================================

Option Explicit

Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_MAX_ROWS  As Long = 60

' Left-zone column numbers
Private Const COL_STEP   As Long = 2   ' B
Private Const COL_ACTION As Long = 3   ' C
Private Const COL_DIST   As Long = 4   ' D  (metres)
Private Const COL_SPEED  As Long = 5   ' E  (m/hr)
Private Const COL_TURN   As Long = 6   ' F  (deg, signed)
Private Const COL_HOLD   As Long = 7   ' G  (seconds)

' Cart-side cap (sketch PLAN_MAX_SEGMENTS). Warn if exceeded.
Private Const PLAN_SEG_MAX As Long = 32

Private Const LOG_CATEGORY As String = "CARTPUSH"


Public Sub PushCartPlan()
    On Error GoTo ErrHandler

    Dim dryRun As Boolean
    dryRun = ReadDryRunFlag()

    Dim mode As String
    mode = IIf(dryRun, "DRY RUN", "REAL PUSH")
    LogCP "--- PushCartPlan start (" & mode & ") ---"

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Plan")

    ' --- Build segments from the left zone ---
    Dim segs() As String
    ReDim segs(1 To PLAN_MAX_ROWS)
    Dim nSeg As Long: nSeg = 0
    Dim errCount As Long: errCount = 0

    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        Dim act As String
        act = UCase(Trim(CStr(ws.Cells(r, COL_ACTION).value)))
        If act = "" Then Exit For       ' first blank Action = end of plan

        Dim seg As String
        Dim rowErr As String
        seg = BuildSegment(ws, r, act, rowErr)

        If rowErr <> "" Then
            LogCP "  ROW " & r & " ERROR: " & rowErr
            errCount = errCount + 1
        ElseIf seg = "" Then
            LogCP "  " & CStr(ws.Cells(r, COL_STEP).value) & " -> (start marker, skipped)"
        Else
            nSeg = nSeg + 1
            segs(nSeg) = seg
            LogCP "  " & CStr(ws.Cells(r, COL_STEP).value) & " -> " & seg
        End If
    Next r

    If errCount > 0 Then
        LogCP "FAILED: " & errCount & " row error(s). Aborting."
        MsgBox "Cart plan has " & errCount & " row error(s)." & vbCrLf & _
               "See Log sheet. Fix and re-run.", vbExclamation, "PushCartPlan"
        Exit Sub
    End If

    If nSeg = 0 Then
        LogCP "FAILED: no cart segments found (left zone empty)."
        MsgBox "No cart plan rows found in the left zone.", vbExclamation, "PushCartPlan"
        Exit Sub
    End If

    If nSeg > PLAN_SEG_MAX Then
        LogCP "WARNING: " & nSeg & " segments exceeds cart PLAN_MAX_SEGMENTS=" & PLAN_SEG_MAX
    End If

    ' --- Assemble /plan/load URL ---
    Dim qs As String
    qs = "/plan/load?n=" & nSeg
    Dim i As Long
    For i = 1 To nSeg
        qs = qs & "&s" & i & "=" & segs(i)
    Next i

    LogCP "Assembled: " & qs & "  (" & nSeg & " segments)"

    ' --- Dry-run stops here ---
    If dryRun Then
        LogCP "--- PushCartPlan end (DRY RUN, not sent) ---"
        MsgBox "DRY RUN: " & nSeg & " segment(s) built, not sent." & vbCrLf & vbCrLf & _
               qs & vbCrLf & vbCrLf & "See Log sheet.", vbInformation, "PushCartPlan"
        Exit Sub
    End If

    ' --- Real push: ping /status, then GET /plan/load ---
    Dim arduinoIP As String
    arduinoIP = ReadArduinoIP()
    If arduinoIP = "" Then
        MsgBox "Cart IP not set in Settings.", vbExclamation, "PushCartPlan"
        Exit Sub
    End If

    If Not CartAlive(arduinoIP) Then
        LogCP "ABORT: cart /status did not respond at " & arduinoIP
        MsgBox "Cart not responding at " & arduinoIP & vbCrLf & _
               "(checked /status). Push aborted.", vbExclamation, "PushCartPlan"
        Exit Sub
    End If

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    Dim url As String
    url = arduinoIP & qs

    LogCP "GET " & url
    Dim sc As Long, respText As String
    On Error Resume Next
    http.Open "GET", url, False
    http.Send
    sc = http.Status
    respText = CStr(http.responseText)
    On Error GoTo ErrHandler

    If sc = 200 Then
        LogCP "OK " & respText
        MsgBox "Cart plan pushed: " & nSeg & " segment(s)." & vbCrLf & vbCrLf & _
               respText & vbCrLf & vbCrLf & _
               "Start with /plan/start when ready.", vbInformation, "PushCartPlan"
    Else
        LogCP "HTTP " & sc & " " & respText
        MsgBox "Push failed. HTTP " & sc & vbCrLf & respText, vbExclamation, "PushCartPlan"
    End If

    LogCP "--- PushCartPlan end (" & mode & ") ---"
    Exit Sub

ErrHandler:
    LogCP "ERROR: " & Err.Description
    MsgBox "Error in PushCartPlan:" & vbCrLf & vbCrLf & Err.Description, _
           vbCritical, "PushCartPlan"
End Sub


' ============================================================
' Build one segment CSV from a left-zone row. Sets rowErr non-empty
' on problem. Returns "" on error.
' ============================================================
Private Function BuildSegment(ByVal ws As Worksheet, ByVal r As Long, _
                              ByVal act As String, ByRef rowErr As String) As String
    rowErr = ""

    If act = "DRIVE" Then
        Dim distM As Variant, speed As Variant, turn As Variant
        distM = ws.Cells(r, COL_DIST).value
        speed = ws.Cells(r, COL_SPEED).value
        turn = ws.Cells(r, COL_TURN).value

        ' Seed / start-marker row: DRIVE with no distance or no speed
        ' (e.g. WP01 at Dist Sigma 0). Not a real move — skip silently,
        ' as in the earlier working cart-plan test. Signalled by
        ' rowErr="" AND return "".
        If (Not IsNumeric(distM)) Or (Not IsNumeric(speed)) Then
            BuildSegment = "": Exit Function
        End If
        If CDbl(distM) <= 0 Or CDbl(speed) <= 0 Then
            BuildSegment = "": Exit Function
        End If

        Dim distMM As Long
        distMM = CLng(CDbl(distM) * 1000#)

        Dim steer As Long
        steer = IIf(IsNumeric(turn), CLng(CDbl(turn)), 0)

        ' m,VAL(mm),STEER,SPEED(m/hr),END=d
        BuildSegment = "m," & distMM & "," & steer & "," & CLng(CDbl(speed)) & ",d"

    ElseIf act = "STOP" Then
        Dim holdS As Variant
        holdS = ws.Cells(r, COL_HOLD).value
        Dim holdMS As Long
        holdMS = IIf(IsNumeric(holdS), CLng(CDbl(holdS) * 1000#), 0)
        If holdMS < 0 Then rowErr = "STOP: Hold negative": Exit Function

        ' s,VAL(ms),0,0,END=t  (END=o for operator-hold if Hold=0)
        Dim endCond As String
        endCond = IIf(holdMS = 0, "o", "t")
        BuildSegment = "s," & holdMS & ",0,0," & endCond

    Else
        rowErr = "Unknown Action '" & act & "' (expected DRIVE or STOP)"
    End If
End Function


' ============================================================
' Helpers — mirror AstroPush.bas Settings reads and transport.
' ============================================================
Private Function ReadDryRunFlag() As Boolean
    On Error GoTo Defaulting
    Dim v As Variant
    v = ThisWorkbook.Sheets("Settings").Range("dataPlanPushDryRun").value
    If IsEmpty(v) Then ReadDryRunFlag = True: Exit Function
    ReadDryRunFlag = CBool(v)
    Exit Function
Defaulting:
    ReadDryRunFlag = True   ' safe default: never surprise-push
End Function

Private Function ReadArduinoIP() As String
    On Error Resume Next
    Dim ip As String
    ip = Trim(CStr(ThisWorkbook.Sheets("Settings").Range("dataArduinoIP").value))
    On Error GoTo 0
    If ip = "" Then
        ReadArduinoIP = ""
    Else
        If LCase(Left(ip, 7)) <> "http://" Then ip = "http://" & ip
        ReadArduinoIP = ip
    End If
End Function

Private Function CartAlive(ByVal arduinoIP As String) As Boolean
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    On Error Resume Next
    http.Open "GET", arduinoIP & "/status", False
    http.Send
    CartAlive = (http.Status = 200)
    On Error GoTo 0
End Function

Private Sub LogCP(ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", LOG_CATEGORY, msg
    On Error GoTo 0
End Sub
