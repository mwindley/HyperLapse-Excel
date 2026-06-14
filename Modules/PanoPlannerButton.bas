Attribute VB_Name = "PanoPlannerButton"
' HyperLapse - "Pano Planner" button.
'
' Saves the workbook, runs Python\pano_planner.py on it, opens the PNG. Same
' pattern + robust cmd /c quoting as GimbalPlanViewButton / GimbalCableStripButton.
'
' The image is the DESIGN-TIME exploration aid for the two PANO config blocks:
' it shows each config's frames, virgin-distorted edges, overlap, time buckets,
' and the FINAL VIDEO length at the sheet's shoot-duration + FPS. Run it while
' tuning a config (once per lens); the PANO sheet formulas remain the contract.
'
' Setup: PY_EXE as for the other render buttons. Script auto-located at
' <workbook>\Python\pano_planner.py. Assign RenderPanoPlanner to a button.

Option Explicit

Private Const PY_EXE As String = "python"
Private Const PY_SUBDIR As String = "Python"
Private Const SCRIPT_NAME As String = "pano_planner.py"

Public Sub RenderPanoPlanner()
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
    outPng = pydir & Application.PathSeparator & "pano_planner.png"

    If dir(script) = "" Then
        MsgBox "Pano planner renderer not found:" & vbCrLf & script, vbExclamation
        Exit Sub
    End If

    ' Save so the renderer reads the latest config inputs.
    Application.DisplayAlerts = False
    ThisWorkbook.Save
    Application.DisplayAlerts = True

    ' cmd /c "" "py" "script" "xlsm" "out" "" - robust quoting (matches the other buttons)
    Dim cmd As String
    cmd = "cmd /c """"" & PY_EXE & """ """ & script & """ """ & xlsm & """ """ & outPng & """"""

    Dim sh As Object: Set sh = CreateObject("WScript.Shell")
    Dim rc As Long
    rc = sh.Run(cmd, 0, True)   ' hidden window, wait

    If rc <> 0 Then
        MsgBox "Pano planner renderer exited with code " & rc & "." & vbCrLf & _
               "Check Python is on PATH and openpyxl/matplotlib are installed.", vbExclamation
        Exit Sub
    End If

    If dir(outPng) = "" Then
        MsgBox "Renderer ran but no PNG was produced:" & vbCrLf & outPng, vbExclamation
        Exit Sub
    End If

    ' Open the PNG in the default viewer.
    sh.Run """" & outPng & """", 1, False
    Exit Sub

fail:
    MsgBox "RenderPanoPlanner error " & Err.Number & ": " & Err.Description, vbExclamation
End Sub
