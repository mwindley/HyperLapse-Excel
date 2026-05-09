Attribute VB_Name = "Buttons"
' ============================================================
' HyperLapse Cart — Buttons Module
'
' PURPOSE
'   Shared helpers for the "double-click a cell to run a macro"
'   pattern used on the Control sheet. Provides:
'
'     RunButton         — orange → action → blue / yellow colour
'                         cycle wrapper. Called from the
'                         Worksheet_BeforeDoubleClick handler on
'                         the Control sheet.
'     CellFormat        — apply one of a small palette of named
'                         styles to a cell (Blue, Orange, Yellow,
'                         Green, Grey, etc.). Carried over from
'                         prior projects.
'     AllBorder         — uniform thin border on all four edges
'                         and the inside grid.
'     BuildControlSheet — one-shot setup: create the Control sheet,
'                         lay out the button cells, name them, and
'                         apply the default Blue style. Run once
'                         after importing this module.
' ============================================================

Option Explicit

' ============================================================
' Public — called from sheet double-click handlers
' ============================================================

' Run a macro on behalf of a "button" cell, with the visual feedback
' cycle: orange while running, blue on success, yellow on error.
'
' Target  — the cell that was double-clicked (becomes the button face)
' macroName — name of a Public Sub callable via Application.Run
' Cancel  — pass through the Cancel ByRef arg from the event handler;
'           we set it True so Excel doesn't put the cell into edit mode.
Public Sub RunButton(ByVal Target As Range, _
                     ByVal macroName As String, _
                     ByRef Cancel As Boolean)
    Cancel = True
    
    Call CellFormat(Target, "FormatOrange")
    DoEvents                          ' force the orange paint to render
    
    Dim okFlag As Boolean
    okFlag = True
    
    On Error Resume Next
    Application.Run macroName
    If Err.Number <> 0 Then
        okFlag = False
        LogEvent "BTN", "RunButton " & macroName & " failed: " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0
    
    If okFlag Then
        Call CellFormat(Target, "FormatBlue")
    Else
        Call CellFormat(Target, "FormatYellow")
    End If
End Sub

' ============================================================
' Cell formatting — port from prior projects
' ============================================================

' Apply uniform thin borders on all edges + interior of a range.
' colorIdx — Excel colour index (0 = automatic, 2 = white, etc.)
Public Sub AllBorder(ByVal myCell As Range, ByVal colorIdx As Integer)
    myCell.Borders(xlDiagonalDown).LineStyle = xlNone
    myCell.Borders(xlDiagonalUp).LineStyle = xlNone
    
    Dim sides As Variant
    sides = Array(xlEdgeLeft, xlEdgeTop, xlEdgeBottom, xlEdgeRight, _
                  xlInsideVertical, xlInsideHorizontal)
    
    Dim i As Long
    For i = LBound(sides) To UBound(sides)
        With myCell.Borders(sides(i))
            .LineStyle = xlContinuous
            .ColorIndex = colorIdx
            .TintAndShade = 0
            .Weight = xlThin
        End With
    Next i
End Sub

' Apply one of a fixed set of named styles to a range. Each style is
' a (fill colour, font colour index, border colour index) triple.
' The names are kept verbose ("FormatBlue" not "Blue") to match the
' convention used in the original sample.
Public Sub CellFormat(ByVal myCell As Range, ByVal myFormat As String)
    Dim myFill   As Long
    Dim myFont   As Integer
    Dim myBorder As Integer
    
    Select Case myFormat
        Case "FormatBlue"
            myFill = 6373376:   myFont = 2: myBorder = 0
        Case "FormatGrey"
            myFill = 10727581:  myFont = 0: myBorder = 2
        Case "FormatYellow"
            myFill = 65535:     myFont = 0: myBorder = 0
        Case "FormatOrange"
            myFill = 48127:     myFont = 0: myBorder = 0
        Case "FormatPurple"
            myFill = 4260146:   myFont = 2: myBorder = 0
        Case "FormatBrown"
            myFill = 68929:     myFont = 2: myBorder = 0
        Case "FormatGreen"
            myFill = 2375937:   myFont = 2: myBorder = 0
        Case "FormatMuck"
            myFill = 82231:     myFont = 2: myBorder = 0
        Case "FormatWhite"
            myFill = 16777215:  myFont = 0: myBorder = 0
        Case Else
            ' Unknown style — leave cell alone
            Exit Sub
    End Select
    
    myCell.Interior.Color = myFill
    myCell.Font.ColorIndex = myFont
    Call AllBorder(myCell, myBorder)
End Sub

' ============================================================
' One-shot setup — build the Control sheet
' ============================================================

' Create the Control sheet, lay out the 8 button cells, name them,
' and apply the default Blue (idle) style. Safe to run multiple times:
' if the sheet already exists, you'll be asked whether to rebuild it.
Public Sub BuildControlSheet()
    Const SHEET_NAME As String = "Control"
    
    ' Button definitions: label text + named-range name.
    ' Order here = vertical layout order on the sheet.
    Dim btns(0 To 7, 0 To 1) As String
    btns(0, 0) = "System Check":      btns(0, 1) = "btnSystemCheck"
    btns(1, 0) = "Init Shoot":        btns(1, 1) = "btnInitShoot"
    btns(2, 0) = "Start Sequence":    btns(2, 1) = "btnStartSequence"
    btns(3, 0) = "Stop Sequence":     btns(3, 1) = "btnStopSequence"
    btns(4, 0) = "Get Sunset Time":   btns(4, 1) = "btnGetSunsetTime"
    btns(5, 0) = "Generate GC Table": btns(5, 1) = "btnGenerateGCTable"
    btns(6, 0) = "Export Modules":    btns(6, 1) = "btnExportModules"
    btns(7, 0) = "Import Modules":    btns(7, 1) = "btnImportModules"
    
    ' Find or (re)create the sheet
    Dim ws As Worksheet
    Set ws = Nothing
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)
    On Error GoTo 0
    
    If Not ws Is Nothing Then
        Dim resp As VbMsgBoxResult
        resp = MsgBox("'" & SHEET_NAME & "' sheet already exists." & vbCrLf & _
                      "Rebuild it? (existing button cells will be reformatted; " & _
                      "any other content on the sheet will be left alone.)", _
                      vbYesNo + vbQuestion, "Build Control Sheet")
        If resp <> vbYes Then Exit Sub
    Else
        Application.DisplayAlerts = False
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.count))
        ws.Name = SHEET_NAME
        Application.DisplayAlerts = True
    End If
    
    ' Lay out the buttons in column C, rows 3..3+N
    Const FIRST_ROW As Long = 3
    Const BTN_COL   As Long = 3   ' column C
    
    ' Title
    With ws.Cells(1, BTN_COL)
        .value = "HyperLapse Control"
        .Font.Bold = True
        .Font.Size = 14
    End With
    
    ws.Columns(BTN_COL).ColumnWidth = 28
    
    Dim i As Long
    For i = 0 To UBound(btns, 1)
        Dim cell As Range
        Set cell = ws.Cells(FIRST_ROW + i, BTN_COL)
        
        ' Label
        cell.value = btns(i, 0)
        cell.HorizontalAlignment = xlCenter
        cell.VerticalAlignment = xlCenter
        cell.Font.Bold = True
        cell.RowHeight = 24
        
        ' Apply Blue (idle) style
        Call CellFormat(cell, "FormatBlue")
        
        ' (Re)create the named range scoped to the workbook so the sheet
        ' code module can reference it by simple name.
        Dim nm As String
        nm = btns(i, 1)
        On Error Resume Next
        ThisWorkbook.names(nm).Delete
        On Error GoTo 0
        ThisWorkbook.names.Add Name:=nm, _
                               RefersTo:="=" & SHEET_NAME & "!" & cell.Address
    Next i
    
    ' Helpful hint cell
    With ws.Cells(FIRST_ROW + UBound(btns, 1) + 2, BTN_COL)
        .value = "Double-click any button to run."
        .Font.Italic = True
        .HorizontalAlignment = xlCenter
    End With
    
    ws.Activate
    ws.Cells(1, 1).Select
    
    MsgBox "Control sheet ready." & vbCrLf & vbCrLf & _
           "Final step: paste the Worksheet_BeforeDoubleClick handler " & _
           "into the Control sheet's code module (see Control_SheetCode.txt).", _
           vbInformation, "Build Control Sheet"
End Sub
