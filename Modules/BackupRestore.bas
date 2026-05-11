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
                  "OVERWRITTEN IN PLACE:" & summary & vbCrLf & vbCrLf & _
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
        
        ' Don't try to overwrite ourselves while we're running.
        If StrComp(modName, SELF_NAME, vbTextCompare) = 0 Then
            skipCount = skipCount + 1
            failList = failList & vbCrLf & "  " & modName & _
                       " (skipped — that's me, currently running)"
            GoTo NextFile
        End If
        
        On Error Resume Next
        Err.Clear
        
        Dim existing As Object
        Set existing = Nothing
        Set existing = ThisWorkbook.VBProject.VBComponents(modName)
        Err.Clear   ' "not found" is fine, handled below
        On Error GoTo 0
        
        If existing Is Nothing Then
            ' New module — no collision possible. Use VBComponents.Import,
            ' which preserves the file's Attribute VB_Name as the new
            ' component's name.
            On Error Resume Next
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
        Else
            ' Existing module — overwrite in place.
            '
            ' Why not Remove + Import: VBComponents.Remove is deferred —
            ' the component doesn't actually disappear until VBA returns
            ' to idle. A subsequent .Import in the same run sees the name
            ' as still taken and silently renames the incoming module to
            ' "Camera1" / "Utils1" / etc. This was the source of the
            ' rename-on-import bug that had been creeping in for ages.
            '
            ' In-place overwrite avoids the problem entirely: the
            ' VBComponent stays put, we just replace its code.
            
            ' Document modules (ThisWorkbook, Sheet1...) can have their
            ' code overwritten but it's not what this workflow is for.
            ' Skip them.
            If existing.Type = vbext_ct_Document Then
                skipCount = skipCount + 1
                failList = failList & vbCrLf & "  " & modName & _
                           " (skipped — document module)"
                GoTo NextFile
            End If
            
            Dim fileText As String
            fileText = ReadFileStripAttributes(CStr(fPath))
            If LenB(fileText) = 0 Then
                failCount = failCount + 1
                failList = failList & vbCrLf & "  " & modName & _
                           " (read failed or file empty)"
                GoTo NextFile
            End If
            
            On Error Resume Next
            With existing.CodeModule
                If .CountOfLines > 0 Then .DeleteLines 1, .CountOfLines
                .AddFromString fileText
            End With
            If Err.Number <> 0 Then
                failCount = failCount + 1
                failList = failList & vbCrLf & "  " & modName & _
                           " (overwrite failed: " & Err.Description & ")"
                Err.Clear
            Else
                okCount = okCount + 1
            End If
            On Error GoTo 0
        End If
        
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

' Read a .bas / .cls file and return its contents with the leading
' Attribute lines stripped.
'
' A .bas file from VBA starts with:
'     Attribute VB_Name = "Camera"
' A .cls file starts with a longer header:
'     VERSION 1.0 CLASS
'     BEGIN
'       MultiUse = -1  'True
'     END
'     Attribute VB_Name = "MyClass"
'     Attribute VB_GlobalNameSpace = False
'     ...etc
'
' Those lines are how VBA persists module metadata to disk, but when
' inserting code via CodeModule.AddFromString into an EXISTING component,
' the metadata is already set and re-inserting the Attribute lines either
' fails or creates duplicates that show up as syntax errors in the IDE.
'
' Strategy: skip every leading line that is blank, starts with "Attribute",
' "VERSION", "BEGIN", "END", or is inside a BEGIN..END block. As soon as
' we hit anything else (typically "Option Explicit" or a comment), we
' take the rest verbatim.
Private Function ReadFileStripAttributes(ByVal filePath As String) As String
    On Error GoTo ErrHandler
    
    Dim fNum As Integer
    fNum = FreeFile
    Open filePath For Input As #fNum
    
    Dim allText As String
    Do While Not EOF(fNum)
        Dim line As String
        Line Input #fNum, line
        allText = allText & line & vbCrLf
    Loop
    Close #fNum
    
    ' Split, scan past the header, rejoin.
    Dim lines() As String
    lines = Split(allText, vbCrLf)
    
    Dim i As Long
    Dim inBeginBlock As Boolean
    inBeginBlock = False
    
    For i = 0 To UBound(lines)
        Dim t As String
        t = Trim$(lines(i))
        
        If inBeginBlock Then
            If StrComp(t, "END", vbTextCompare) = 0 Then inBeginBlock = False
            ' otherwise still inside the BEGIN..END block; skip
        ElseIf LenB(t) = 0 Then
            ' blank — keep scanning past the header
        ElseIf StrComp(t, "BEGIN", vbTextCompare) = 0 Then
            inBeginBlock = True
        ElseIf Left$(t, 7) = "VERSION" Then
            ' header line, skip
        ElseIf Left$(t, 9) = "Attribute" Then
            ' header line, skip
        Else
            ' First content line — take from here.
            Exit For
        End If
    Next i
    
    Dim out As String
    Dim j As Long
    For j = i To UBound(lines)
        out = out & lines(j) & vbCrLf
    Next j
    
    ReadFileStripAttributes = out
    Exit Function
    
ErrHandler:
    On Error Resume Next
    Close #fNum
    ReadFileStripAttributes = ""
End Function

' Verify that every module-level Public/Private declaration sits in the
' header block (above the first Sub/Function/Property). Flags any that
' have drifted into the body of the module.
'
' Procedure-local Dim statements are NOT checked — they are legitimate
' anywhere within their procedure. This rule only governs MODULE-level
' declarations: Public/Private variables, constants, types, and Declares.
'
' Output: a popup listing every offence as "Module:line  >>  text".
' If the project is clean, says so.
Public Sub CheckDeclarationStyle()
    If Not VbaProjectAccessible() Then Exit Sub
    
    Dim report   As String
    Dim totalBad As Long
    
    Dim comp As Object
    For Each comp In ThisWorkbook.VBProject.VBComponents
        ' Only check standard modules and class modules. Document modules
        ' (sheets, ThisWorkbook) and userforms have their own structure.
        If comp.Type <> vbext_ct_StdModule And comp.Type <> vbext_ct_ClassModule Then
            ' skip
        Else
            Dim modBad As String
            modBad = CheckOneModule(comp)
            If LenB(modBad) > 0 Then
                report = report & vbCrLf & "── " & comp.Name & " ──" & vbCrLf & modBad
                ' count newlines as a proxy for offence count
                Dim p As Long, c As Long
                c = 0
                p = 1
                Do
                    p = InStr(p, modBad, vbCrLf)
                    If p = 0 Then Exit Do
                    c = c + 1
                    p = p + 1
                Loop
                totalBad = totalBad + c
            End If
        End If
    Next comp
    
    If totalBad = 0 Then
        MsgBox "All module-level declarations are in the header block." & vbCrLf & vbCrLf & _
               "Procedure-local Dim statements are not checked.", _
               vbInformation, "Declaration Style Check"
    Else
        MsgBox "Found " & totalBad & " misplaced module-level declaration(s):" & vbCrLf & _
               report & vbCrLf & vbCrLf & _
               "Move these to the top of their module, under Option Explicit.", _
               vbExclamation, "Declaration Style Check"
    End If
End Sub

' Scan one VBComponent for misplaced module-level declarations.
' Returns a multi-line report of offending lines, or "" if clean.
Private Function CheckOneModule(ByVal comp As Object) As String
    Dim cm As Object
    Set cm = comp.CodeModule
    
    Dim totalLines As Long
    totalLines = cm.CountOfLines
    If totalLines = 0 Then Exit Function
    
    Dim seenProcedure As Boolean
    Dim insideProc    As Boolean
    Dim report        As String
    
    Dim ln As Long
    For ln = 1 To totalLines
        Dim raw As String
        raw = cm.Lines(ln, 1)
        
        Dim trimmed As String
        trimmed = Trim$(raw)
        
        ' Track whether we're inside a Sub/Function/Property body.
        If StartsProcedure(trimmed) Then
            seenProcedure = True
            insideProc = True
        ElseIf EndsProcedure(trimmed) Then
            insideProc = False
        End If
        
        ' Only inspect lines AFTER the first procedure has appeared,
        ' AND only when we're not currently inside a procedure body.
        If seenProcedure And Not insideProc Then
            If IsModuleLevelDeclaration(trimmed) Then
                report = report & "  line " & ln & ":  " & trimmed & vbCrLf
            End If
        End If
    Next ln
    
    CheckOneModule = report
End Function

' Does this line begin a procedure (Sub/Function/Property)?
Private Function StartsProcedure(ByVal s As String) As Boolean
    Dim u As String
    u = UCase$(s)
    StartsProcedure = (u Like "SUB *") Or (u Like "FUNCTION *") Or _
                      (u Like "PUBLIC SUB *") Or (u Like "PUBLIC FUNCTION *") Or _
                      (u Like "PRIVATE SUB *") Or (u Like "PRIVATE FUNCTION *") Or _
                      (u Like "FRIEND SUB *") Or (u Like "FRIEND FUNCTION *") Or _
                      (u Like "PUBLIC PROPERTY *") Or (u Like "PRIVATE PROPERTY *") Or _
                      (u Like "PROPERTY *")
End Function

Private Function EndsProcedure(ByVal s As String) As Boolean
    Dim u As String
    u = UCase$(s)
    EndsProcedure = (u = "END SUB") Or (u = "END FUNCTION") Or (u = "END PROPERTY")
End Function

' Does this line look like a module-level Public/Private declaration of
' a variable, constant, type, or Declare? We deliberately ignore the
' procedure starters (caught by StartsProcedure already).
Private Function IsModuleLevelDeclaration(ByVal s As String) As Boolean
    Dim u As String
    u = UCase$(s)
    
    ' Procedure declarations are handled separately
    If StartsProcedure(s) Then
        IsModuleLevelDeclaration = False
        Exit Function
    End If
    
    ' Module-level Public/Private declarations
    IsModuleLevelDeclaration = _
        (u Like "PUBLIC * AS *") Or (u Like "PRIVATE * AS *") Or _
        (u Like "PUBLIC CONST *") Or (u Like "PRIVATE CONST *") Or _
        (u Like "PUBLIC TYPE *") Or (u Like "PRIVATE TYPE *") Or _
        (u Like "PUBLIC ENUM *") Or (u Like "PRIVATE ENUM *") Or _
        (u Like "PUBLIC DECLARE *") Or (u Like "PRIVATE DECLARE *")
End Function



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
