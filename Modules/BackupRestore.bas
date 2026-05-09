Attribute VB_Name = "BackupRestore"
' ============================================================
' HyperLapse Cart — Backup / Restore Module
'
' PURPOSE
'   Two macros to sync VBA code between this workbook and the GitHub
'   working copy on disk:
'
'     ExportModules — write every code module in this workbook out
'                     to .bas / .cls / .frm files in the GitHub folder.
'                     Run this after editing in the VBA IDE, before
'                     committing to GitHub.
'
'     ImportModules — replace every code module in this workbook with
'                     the version on disk. Run this after pulling from
'                     GitHub or after Claude has handed back patched
'                     .bas files.
'
' TARGET FOLDER
'   C:\Users\mauri\OneDrive\Documents\Github\HyperLapse-Excel\Modules
'   (override per-run via the constant below if needed)
'
' REQUIREMENT
'   File ▸ Options ▸ Trust Center ▸ Trust Center Settings ▸ Macro Settings
'     ▸ "Trust access to the VBA project object model"  must be ENABLED.
'   Without this, the VBComponents calls below will throw "Programmatic
'   access to Visual Basic Project is not trusted".
'
' SAFETY
'   - ExportModules confirms before overwriting existing files.
'   - ImportModules confirms before replacing in-workbook modules.
'   - Both skip this module itself (BackupRestore) — you can't safely
'     reimport a module while its code is the one currently running.
'   - Document modules (ThisWorkbook, Sheet1, etc.) are NOT exported
'     or imported, only standard modules / classes / userforms.
' ============================================================

Option Explicit

' ── Configuration ───────────────────────────────────────────
Private Const MODULE_FOLDER As String = _
    "C:\Users\mauri\OneDrive\Documents\Github\HyperLapse-Excel\Modules"

' This module's own name — skipped by both macros so it can't overwrite
' itself while running. If you ever rename this module, update this constant.
Private Const SELF_NAME As String = "BackupRestore"

' VBComponent type constants (avoid needing a reference to the VBE library)
Private Const vbext_ct_StdModule    As Long = 1
Private Const vbext_ct_ClassModule  As Long = 2
Private Const vbext_ct_MSForm       As Long = 3
Private Const vbext_ct_Document     As Long = 100

' ============================================================
' Public macros
' ============================================================

' Export every standard module, class module, and userform in this
' workbook to the configured Modules folder. Uses the appropriate
' extension for each component type (.bas / .cls / .frm).
Public Sub ExportModules()
    Dim folderPath As String
    folderPath = EnsureTrailingSlash(MODULE_FOLDER)
    
    If Not FolderExists(folderPath) Then
        MsgBox "Modules folder does not exist:" & vbCrLf & folderPath & vbCrLf & vbCrLf & _
               "Create it first or edit MODULE_FOLDER in BackupRestore.", vbCritical
        Exit Sub
    End If
    
    If Not VbaProjectAccessible() Then Exit Sub
    
    ' Build the list of components we'll export, so we can show a
    ' meaningful confirmation prompt before touching the disk.
    Dim toExport As Collection
    Set toExport = New Collection
    
    Dim comp As Object   ' VBComponent — late-bound to avoid reference dependency
    For Each comp In ThisWorkbook.VBProject.VBComponents
        If ShouldExport(comp) Then toExport.Add comp
    Next comp
    
    If toExport.Count = 0 Then
        MsgBox "No exportable modules found.", vbInformation
        Exit Sub
    End If
    
    Dim resp As VbMsgBoxResult
    resp = MsgBox("Export " & toExport.Count & " module(s) to:" & vbCrLf & _
                  folderPath & vbCrLf & vbCrLf & _
                  "Existing .bas / .cls / .frm files with the same names " & _
                  "will be OVERWRITTEN. Continue?", _
                  vbYesNo + vbQuestion, "Export Modules")
    If resp <> vbYes Then Exit Sub
    
    Dim okCount   As Long
    Dim failCount As Long
    Dim failList  As String
    
    For Each comp In toExport
        Dim ext      As String
        Dim filePath As String
        ext = ExtensionFor(comp)
        filePath = folderPath & comp.Name & ext
        
        On Error Resume Next
        Err.Clear
        comp.Export filePath
        If Err.Number <> 0 Then
            failCount = failCount + 1
            failList = failList & vbCrLf & "  " & comp.Name & " — " & Err.Description
            Err.Clear
        Else
            okCount = okCount + 1
        End If
        On Error GoTo 0
    Next comp
    
    Dim msg As String
    msg = "Export complete." & vbCrLf & vbCrLf & _
          "Exported: " & okCount & vbCrLf & _
          "Failed:   " & failCount & vbCrLf & vbCrLf & _
          "Folder: " & folderPath
    If failCount > 0 Then msg = msg & vbCrLf & vbCrLf & "Failures:" & failList
    
    MsgBox msg, IIf(failCount = 0, vbInformation, vbExclamation), "Export Modules"
End Sub

' Import every .bas / .cls / .frm file from the configured Modules folder,
' replacing any in-workbook module with the same name. Modules that exist
' in the workbook but NOT on disk are left alone (this is a one-way
' "disk wins" import — it does not delete extras).
Public Sub ImportModules()
    Dim folderPath As String
    folderPath = EnsureTrailingSlash(MODULE_FOLDER)
    
    If Not FolderExists(folderPath) Then
        MsgBox "Modules folder does not exist:" & vbCrLf & folderPath, vbCritical
        Exit Sub
    End If
    
    If Not VbaProjectAccessible() Then Exit Sub
    
    ' Enumerate files we plan to import so we can show a confirmation.
    Dim toImport As Collection
    Set toImport = ListImportableFiles(folderPath)
    
    If toImport.Count = 0 Then
        MsgBox "No .bas / .cls / .frm files found in:" & vbCrLf & folderPath, _
               vbInformation
        Exit Sub
    End If
    
    Dim summary As String
    Dim fPath   As Variant
    For Each fPath In toImport
        summary = summary & vbCrLf & "  " & FileNameOnly(CStr(fPath))
    Next fPath
    
    Dim resp As VbMsgBoxResult
    resp = MsgBox("Import " & toImport.Count & " module(s) from:" & vbCrLf & _
                  folderPath & vbCrLf & vbCrLf & _
                  "Any in-workbook modules with the same names will be " & _
                  "REPLACED:" & summary & vbCrLf & vbCrLf & _
                  "Continue?", _
                  vbYesNo + vbQuestion, "Import Modules")
    If resp <> vbYes Then Exit Sub
    
    Dim okCount   As Long
    Dim skipCount As Long
    Dim failCount As Long
    Dim failList  As String
    
    For Each fPath In toImport
        Dim modName As String
        modName = ModuleNameFromPath(CStr(fPath))
        
        ' Don't try to import over ourselves while we're running.
        If StrComp(modName, SELF_NAME, vbTextCompare) = 0 Then
            skipCount = skipCount + 1
            failList = failList & vbCrLf & "  " & modName & _
                       " (skipped — that's me, currently running)"
            GoTo NextFile
        End If
        
        ' Remove existing component if present, then re-import from disk.
        On Error Resume Next
        Err.Clear
        
        Dim existing As Object
        Set existing = Nothing
        Set existing = ThisWorkbook.VBProject.VBComponents(modName)
        If Err.Number <> 0 Then
            ' Not found — that's fine, we'll just import.
            Err.Clear
        End If
        
        If Not existing Is Nothing Then
            ' Document modules (ThisWorkbook, Sheet1...) can't be removed —
            ' you can only overwrite their code. Skip those here; they're
            ' not what this workflow is for.
            If existing.Type = vbext_ct_Document Then
                skipCount = skipCount + 1
                failList = failList & vbCrLf & "  " & modName & _
                           " (skipped — document module)"
                GoTo NextFile
            End If
            ThisWorkbook.VBProject.VBComponents.Remove existing
            If Err.Number <> 0 Then
                failCount = failCount + 1
                failList = failList & vbCrLf & "  " & modName & _
                           " (remove failed: " & Err.Description & ")"
                Err.Clear
                GoTo NextFile
            End If
        End If
        
        ThisWorkbook.VBProject.VBComponents.Import CStr(fPath)
        If Err.Number <> 0 Then
            failCount = failCount + 1
            failList = failList & vbCrLf & "  " & modName & _
                       " (import failed: " & Err.Description & ")"
            Err.Clear
        Else
            okCount = okCount + 1
        End If
        On Error GoTo 0
        
NextFile:
    Next fPath
    
    Dim msg As String
    msg = "Import complete." & vbCrLf & vbCrLf & _
          "Imported: " & okCount & vbCrLf & _
          "Skipped:  " & skipCount & vbCrLf & _
          "Failed:   " & failCount
    If LenB(failList) > 0 Then msg = msg & vbCrLf & vbCrLf & "Details:" & failList
    
    MsgBox msg, IIf(failCount = 0, vbInformation, vbExclamation), "Import Modules"
End Sub

' ============================================================
' Helpers
' ============================================================

' Decide whether a VBComponent should be exported.
' Excludes document modules (sheets, ThisWorkbook) and excludes this module.
Private Function ShouldExport(ByVal comp As Object) As Boolean
    If comp.Type = vbext_ct_Document Then
        ShouldExport = False
        Exit Function
    End If
    If StrComp(comp.Name, SELF_NAME, vbTextCompare) = 0 Then
        ShouldExport = False
        Exit Function
    End If
    ShouldExport = True
End Function

' Pick the right file extension for a VBComponent based on its type.
Private Function ExtensionFor(ByVal comp As Object) As String
    Select Case comp.Type
        Case vbext_ct_StdModule:   ExtensionFor = ".bas"
        Case vbext_ct_ClassModule: ExtensionFor = ".cls"
        Case vbext_ct_MSForm:      ExtensionFor = ".frm"
        Case Else:                 ExtensionFor = ".bas"
    End Select
End Function

' Enumerate .bas / .cls / .frm files in a folder using Dir().
' Returns a Collection of full paths.
Private Function ListImportableFiles(ByVal folderPath As String) As Collection
    Dim col As Collection
    Set col = New Collection
    
    Dim exts(2) As String
    exts(0) = "*.bas"
    exts(1) = "*.cls"
    exts(2) = "*.frm"
    
    Dim i As Integer
    For i = 0 To 2
        Dim f As String
        f = Dir(folderPath & exts(i))
        Do While LenB(f) > 0
            col.Add folderPath & f
            f = Dir()
        Loop
    Next i
    
    Set ListImportableFiles = col
End Function

' Strip folder and extension from a path: "C:\foo\Camera.bas" → "Camera"
Private Function ModuleNameFromPath(ByVal filePath As String) As String
    Dim base As String
    base = FileNameOnly(filePath)
    Dim dotPos As Long
    dotPos = InStrRev(base, ".")
    If dotPos > 0 Then base = Left$(base, dotPos - 1)
    ModuleNameFromPath = base
End Function

' Strip folder portion of a path: "C:\foo\Camera.bas" → "Camera.bas"
Private Function FileNameOnly(ByVal filePath As String) As String
    Dim slashPos As Long
    slashPos = InStrRev(filePath, "\")
    If slashPos > 0 Then
        FileNameOnly = Mid$(filePath, slashPos + 1)
    Else
        FileNameOnly = filePath
    End If
End Function

' Append a trailing backslash if missing.
Private Function EnsureTrailingSlash(ByVal folderPath As String) As String
    If Right$(folderPath, 1) = "\" Then
        EnsureTrailingSlash = folderPath
    Else
        EnsureTrailingSlash = folderPath & "\"
    End If
End Function

Private Function FolderExists(ByVal folderPath As String) As Boolean
    On Error Resume Next
    FolderExists = (LenB(Dir(folderPath, vbDirectory)) > 0)
    On Error GoTo 0
End Function

' Verify that "Trust access to the VBA project object model" is enabled
' before either macro touches the project. Returns True if accessible;
' False (with a guidance MsgBox) if not.
Private Function VbaProjectAccessible() As Boolean
    On Error Resume Next
    Dim count As Long
    count = ThisWorkbook.VBProject.VBComponents.Count
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        MsgBox "Cannot access the VBA project." & vbCrLf & vbCrLf & _
               "Enable: File > Options > Trust Center > Trust Center " & _
               "Settings > Macro Settings > " & vbCrLf & _
               """Trust access to the VBA project object model""", _
               vbCritical, "VBA project access required"
        VbaProjectAccessible = False
        Exit Function
    End If
    On Error GoTo 0
    VbaProjectAccessible = True
End Function
