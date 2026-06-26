Attribute VB_Name = "Watcher"
'==============================================================================
' Watcher.bas - launch / stop the laptop-side alarm watcher (#49)
'
' The watcher is a standalone Python process that polls the cart's /exec/feed
' and raises an ack-to-silence alarm independent of any browser tab. It is
' started two ways:
'   AUTO   - StartWatcherAuto is called from the START push chain so it arms
'            with the shoot.
'   MANUAL - btnStartWatcher / btnStopWatcher buttons (run early during recon
'            to catch link/batt before the shoot).
' The watcher itself holds a single-instance pidfile lock, so a second launch
' (e.g. AUTO firing when MANUAL already started one) is a harmless no-op.
'
' Pure ASCII. LF line endings. Module-qualified Application.Run not needed here
' (no cross-module macro calls). Path is the one fixed site value.
'==============================================================================
Option Explicit

' --- The one site-specific value: where the watcher script lives. -----------
Private Const WATCHER_DIR As String = "C:\Github\HyperLapse-Excel\Python"
Private Const WATCHER_PY As String = "hyperlapse_watcher.py"

' pythonw.exe runs with no console window. If pythonw is not on PATH, set the
' full path here (e.g. "C:\Python312\pythonw.exe").
Private Const PYTHONW As String = "pythonw"

'------------------------------------------------------------------------------
' Build the full command. Quoted so spaces in the path are safe.
'------------------------------------------------------------------------------
Private Function WatcherCmd() As String
    ' Pass the CURRENT cart IP (Settings dataArduinoIP) to the watcher so it
    ' polls the right address instead of a value baked into the .py. If the name
    ' is missing/blank the arg is omitted and the watcher uses its own default.
    Dim ip As String
    ip = ""
    On Error Resume Next
    ip = Trim(CStr(ThisWorkbook.Sheets("Settings").Range("dataArduinoIP").value))
    On Error GoTo 0
    WatcherCmd = PYTHONW & " """ & WATCHER_DIR & "\" & WATCHER_PY & """"
    If ip <> "" Then WatcherCmd = WatcherCmd & " " & ip
End Function

'------------------------------------------------------------------------------
' Launch the watcher. Safe to call repeatedly - the watcher's pidfile lock
' makes a duplicate launch a no-op. vbHide because pythonw has no window and the
' watcher draws its own Tk status window.
'------------------------------------------------------------------------------
Public Sub StartWatcher()
    On Error GoTo Fail
    Shell WatcherCmd(), vbNormalFocus
    Exit Sub
Fail:
    MsgBox "Could not start the alarm watcher." & vbCrLf & _
           "Command: " & WatcherCmd() & vbCrLf & _
           "Check that Python (pythonw) is installed and on PATH, and that" & vbCrLf & _
           WATCHER_DIR & "\" & WATCHER_PY & " exists.", _
           vbExclamation, "HyperLapse watcher"
End Sub

'------------------------------------------------------------------------------
' AUTO entry - call this from the START push chain. Identical to StartWatcher;
' named separately so the START code reads clearly and so behaviour can diverge
' later if needed.
'------------------------------------------------------------------------------
Public Sub StartWatcherAuto()
    StartWatcher
End Sub

'------------------------------------------------------------------------------
' Stop the watcher. The watcher writes its own PID to a lockfile on start; read
' that PID and taskkill it exactly. This avoids WMIC (deprecated/removed on
' current Windows 11) and avoids guessing by window title (pythonw has none).
' Killing the process ends EVERYTHING - polling, sound, and the Tk window - so
' the window vanishing is the operator's confirmation that it stopped.
'------------------------------------------------------------------------------
Public Sub StopWatcher()
    Dim lockPath As String
    Dim pid As String
    Dim ff As Integer
    Dim line As String

    lockPath = Environ$("TEMP") & "\hyperlapse_watcher.lock"

    If Len(Dir$(lockPath)) = 0 Then
        MsgBox "No running watcher found (no lockfile)." & vbCrLf & _
               "If a window is still open, close it directly.", _
               vbInformation, "HyperLapse watcher"
        Exit Sub
    End If

    On Error Resume Next
    ff = FreeFile
    Open lockPath For Input As #ff
    Line Input #ff, line
    Close #ff
    On Error GoTo 0

    pid = Trim$(line)
    If Len(pid) = 0 Or Not IsNumeric(pid) Then
        MsgBox "Lockfile present but PID unreadable (" & lockPath & ")." & vbCrLf & _
               "Close the watcher window directly.", _
               vbExclamation, "HyperLapse watcher"
        Exit Sub
    End If

    ' /F force, /T also kills any child processes. The watcher deletes its own
    ' lockfile on exit; remove it here too in case the kill pre-empts that.
    Shell "taskkill /PID " & pid & " /F /T", vbHide
    On Error Resume Next
    Kill lockPath
    On Error GoTo 0

    MsgBox "Watcher stopped (PID " & pid & ").", vbInformation, "HyperLapse watcher"
End Sub

'------------------------------------------------------------------------------
' Button wrappers (assign these to the Start/Stop Watcher buttons).
'------------------------------------------------------------------------------
Public Sub btnStartWatcher()
    StartWatcher
End Sub

Public Sub btnStopWatcher()
    StopWatcher
End Sub
