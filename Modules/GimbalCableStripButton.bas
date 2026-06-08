Attribute VB_Name = "GimbalCableStripButton"
' HyperLapse - "Cable Strip" button (view #3).
'
' Fills col AC sweep directions (blanks only; operator overrides kept),
' saves, runs gimbal_cablestrip.py on the workbook, opens the PNG. Same
' pattern + robust cmd /c quoting as GimbalPlanViewButton.
'
' The strip reuses the dial's resolver, so it always matches the dial.
' It SHOWS the operator's col-AC sweep against the 450 deg span limit;
' it does not choose direction.
'
' Setup: PY_EXE as for the plan-view button. Script auto-located at
' <workbook>\Python\gimbal_cablestrip.py. Assign RenderCableStrip to a
' Control-sheet button.

Option Explicit

Private Const PY_EXE As String = "python"
Private Const PY_SUBDIR As String = "Python"
Private Const SCRIPT_NAME As String = "gimbal_cablestrip.py"
Private Const SPAN_LIMIT As String = "450"          ' degrees, min->max ceiling

Public Sub RenderCableStrip()
    On Error GoTo Fail

    Dim base As String, pydir As String, script As String, xlsm As String, outPng As String
    base = ThisWorkbook.Path
    If base = "" Then
        MsgBox "Save the workbook once before rendering.", vbExclamation
        Exit Sub
    End If
    xlsm = ThisWorkbook.FullName
    pydir = base & Application.PathSeparator & PY_SUBDIR
    script = pydir & Application.PathSeparator & SCRIPT_NAME
    outPng = pydir & Application.PathSeparator & "gimbal_cablestrip.png"

    If Dir(script) = "" Then
        MsgBox "Cable strip renderer not found:" & vbCrLf & script, vbExclamation
        Exit Sub
    End If

    ' fill sweep directions (blanks only; overrides preserved), then save
    On Error Resume Next
    Application.Run "GimbalSweepDir.FillSweepDirections", False
    On Error GoTo Fail
    ThisWorkbook.Save

    Dim cmd As String
    cmd = Q(PY_EXE) & " " & Q(script) & " " & Q(xlsm) & " " & Q(outPng) & _
          " --limit " & SPAN_LIMIT

    Dim logf As String, rc As Long
    logf = pydir & Application.PathSeparator & "cablestrip_log.txt"
    rc = RunAndWait(cmd, logf)
    If rc <> 0 Then
        MsgBox "Cable strip renderer exited with code " & rc & "." & vbCrLf & vbCrLf & _
               "--- last output ---" & vbCrLf & TailFile(logf, 1500), vbExclamation
        Exit Sub
    End If

    If Dir(outPng) <> "" Then
        ThisWorkbook.FollowHyperlink outPng
    Else
        MsgBox "Render finished but PNG not found:" & vbCrLf & outPng, vbExclamation
    End If
    Exit Sub

Fail:
    MsgBox "Cable strip render failed: " & Err.Description, vbExclamation
End Sub

Private Function RunAndWait(ByVal cmd As String, ByVal logf As String) As Long
    Dim sh As Object, full As String
    Set sh = CreateObject("WScript.Shell")
    full = "cmd /c " & Chr$(34) & cmd & " > " & Q(logf) & " 2>&1" & Chr$(34)
    RunAndWait = sh.Run(full, 0, True)
End Function

Private Function TailFile(ByVal path As String, ByVal maxChars As Long) As String
    On Error Resume Next
    Dim f As Integer, s As String
    If Dir(path) = "" Then TailFile = "(no log written)": Exit Function
    f = FreeFile
    Open path For Input As #f
    s = Input$(LOF(f), f)
    Close #f
    If Len(s) > maxChars Then s = Right$(s, maxChars)
    TailFile = s
End Function

Private Function Q(ByVal s As String) As String
    Q = Chr$(34) & s & Chr$(34)
End Function
