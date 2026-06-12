Attribute VB_Name = "GimbalPlanViewButton"
' HyperLapse - "Render Plan View" button.
'
' Saves the workbook, runs the Python renderer (gimbal_planview_v2.py) on
' it, and opens the resulting PNG. This is the last connective piece: edit
' plan -> press button -> see view -> adjust -> press again.
'
' One-time setup (top of this module): set PY_EXE and SCRIPT_PATH to where
' Python and the script live on this machine. Optional MAP_PATH for the
' north-up tile underlay (leave "" for none).
'
' Assign RenderPlanView to a Control-sheet button (Developer > Insert >
' Button, or right-click an existing shape > Assign Macro).
'
' Notes:
' - Runs GimbalSweepDir.FillSweepDirections first so col AC is populated
'   (blanks only - operator CW/CCW overrides are preserved).
' - Waits for the render to finish before opening the PNG (synchronous).
' - The renderer reads the .xlsm directly, so we save before shelling.

Option Explicit

' ---- EDIT THESE for this machine ----
Private Const PY_EXE As String = "python"                 ' or full path to python.exe
Private Const PY_SUBDIR As String = "Python"              ' script folder, relative to the workbook
Private Const SCRIPT_NAME As String = "gimbal_planview_v2.py"
Private Const MAP_PATH As String = ""                     ' full path to north-up tile PNG, or "" for none
' -------------------------------------

Public Sub RenderPlanView()
    On Error GoTo fail

    Dim base As String, pydir As String, script As String, xlsm As String, outPng As String
    base = ThisWorkbook.path
    If base = "" Then
        MsgBox "Save the workbook once before rendering.", vbExclamation
        Exit Sub
    End If

    xlsm = ThisWorkbook.FullName
    pydir = base & Application.PathSeparator & PY_SUBDIR
    script = pydir & Application.PathSeparator & SCRIPT_NAME
    outPng = pydir & Application.PathSeparator & "gimbal_planview_v2.png"

    If dir(script) = "" Then
        MsgBox "Renderer not found:" & vbCrLf & script & vbCrLf & _
               "Check PY_SUBDIR / SCRIPT_NAME at the top of GimbalPlanViewButton.", vbExclamation
        Exit Sub
    End If

    ' 1) fill sweep directions (blanks only; overrides preserved), then save
    On Error Resume Next
    Application.Run "GimbalSweepDir.FillSweepDirections", False
    On Error GoTo fail
    ThisWorkbook.Save

    ' 2) build the command and run it synchronously
    Dim cmd As String
    cmd = Q(PY_EXE) & " " & Q(script) & " " & Q(xlsm) & " " & Q(outPng)
    ' Map underlay: explicit MAP_PATH wins; otherwise auto-use Python\map.png
    ' if GimbalMapFetch has produced one.
    Dim mapUse As String
    mapUse = MAP_PATH
    If mapUse = "" Then
        Dim autoMap As String
        autoMap = pydir & Application.PathSeparator & "map.png"
        If dir(autoMap) <> "" Then mapUse = autoMap
    End If
    If mapUse <> "" Then cmd = cmd & " --map " & Q(mapUse)

    Dim logf As String, rc As Long
    logf = pydir & Application.PathSeparator & "render_log.txt"
    rc = RunAndWait(cmd, logf)
    If rc <> 0 Then
        ' Trace the FULL python output to the copyable event log (not a MsgBox),
        ' then propagate so BuildPlan/RunStep reports FAILED rather than ok.
        Dim ptail As String: ptail = TailFile(logf, 1500)
        LogEvent "PREP", "RenderPlanView FAILED rc=" & rc
        LogEvent "PREP", "py-tail: " & ptail
        On Error GoTo 0
        Err.Raise vbObjectError + 513, "RenderPlanView", _
            "Renderer exited code " & rc & " - see event log (py-tail traced)"
    End If

    ' 3) open the PNG with the default image viewer
    If dir(outPng) <> "" Then
        ThisWorkbook.FollowHyperlink outPng
    Else
        MsgBox "Render finished but PNG not found:" & vbCrLf & outPng, vbExclamation
    End If
    Exit Sub

fail:
    LogEvent "PREP", "RenderPlanView ERROR: " & Err.Description
    MsgBox "Render failed: " & Err.Description, vbExclamation
End Sub

' Run a command line, redirect stdout+stderr to logf, block until done; returns exit code.
Private Function RunAndWait(ByVal cmd As String, ByVal logf As String) As Long
    Dim sh As Object, full As String
    Set sh = CreateObject("WScript.Shell")
    ' Wrap the ENTIRE inner command in one outer pair of quotes, or cmd /c
    ' strips quotes from the multi-quoted path list and mangles the line.
    full = "cmd /c " & Chr$(34) & cmd & " > " & Q(logf) & " 2>&1" & Chr$(34)
    ' 0 = hidden window, True = wait for completion.
    RunAndWait = sh.Run(full, 0, True)
End Function

' Return the last maxChars characters of a text file (for error display).
Private Function TailFile(ByVal path As String, ByVal maxChars As Long) As String
    On Error Resume Next
    Dim f As Integer, s As String
    If dir(path) = "" Then TailFile = "(no log written - python may not have started)": Exit Function
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
