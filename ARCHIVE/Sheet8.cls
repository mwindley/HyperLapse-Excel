Attribute VB_Name = "Sheet8"
Attribute VB_Base = "0{00020820-0000-0000-C000-000000000046}"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
Attribute VB_TemplateDerived = False
Attribute VB_Customizable = True
' ============================================================
' HyperLapse Cart — Control sheet code module
'
' DROP-IN INSTRUCTIONS
'   This code lives on the Control SHEET'S code module, NOT in a
'   regular module. To install:
'     1. Run BuildControlSheet (in module Buttons) once — it creates
'        the Control sheet, lays out the buttons, names them, and
'        formats them.
'     2. In the VBA editor, double-click "Control" under
'        "Microsoft Excel Objects" in the project tree to open its
'        code module.
'     3. Paste the contents of this file there.
'
' WHAT IT DOES
'   Double-clicking any "button" cell on the Control sheet runs the
'   matching macro with an orange (working) ? blue (done) /
'   yellow (error) colour cycle, mirroring the pattern from prior
'   projects. The cell?macro mapping is by named range (btn*).
'
' ADDING A NEW BUTTON
'   1. Add the button cell + named range in BuildControlSheet.
'   2. Add one line below in the dispatcher:
'         If Not Intersect(Target, Range("btnYourMacro")) Is Nothing _
'             Then RunButton Target, "YourMacro", Cancel: Exit Sub
' ============================================================

Option Explicit

Private Sub Worksheet_BeforeDoubleClick(ByVal Target As Range, Cancel As Boolean)
    ' Single-cell selections only — ignore double-clicks on multi-cell ranges
    If Target.Cells.count > 1 Then Exit Sub
    
    ' Each button: if the double-clicked cell is inside this named range,
    ' run the matching macro through RunButton and exit. RunButton handles
    ' the orange?action?blue/yellow colour cycle and sets Cancel = True
    ' so the cell doesn't drop into edit mode after the macro finishes.
    
    If Not Intersect(Target, Range("btnSystemCheck")) Is Nothing _
        Then RunButton Target, "SystemCheck", Cancel: Exit Sub
    
    If Not Intersect(Target, Range("btnInitShoot")) Is Nothing _
        Then RunButton Target, "InitShoot", Cancel: Exit Sub
    
    If Not Intersect(Target, Range("btnStartSequence")) Is Nothing _
        Then RunButton Target, "StartSequence", Cancel: Exit Sub
    
    If Not Intersect(Target, Range("btnStopSequence")) Is Nothing _
        Then RunButton Target, "StopSequence", Cancel: Exit Sub
    
    If Not Intersect(Target, Range("btnGetSunsetTime")) Is Nothing _
        Then RunButton Target, "GetSunsetTime", Cancel: Exit Sub
    
    If Not Intersect(Target, Range("btnGenerateGCTable")) Is Nothing _
        Then RunButton Target, "GenerateGCTable", Cancel: Exit Sub
    
    If Not Intersect(Target, Range("btnExportModules")) Is Nothing _
        Then RunButton Target, "ExportModules", Cancel: Exit Sub
    
    If Not Intersect(Target, Range("btnImportModules")) Is Nothing _
        Then RunButton Target, "ImportModules", Cancel: Exit Sub
        
    If Not Intersect(Target, Range("btnIntegrateBicycle")) Is Nothing _
        Then RunButton Target, "IntegrateBicycle", Cancel: Exit Sub

    If Not Intersect(Target, Range("btnInitFallbackFormula")) Is Nothing _
        Then RunButton Target, "InitFallbackFormula", Cancel: Exit Sub

    If Not Intersect(Target, Range("btnPushFormula")) Is Nothing _
        Then RunButton Target, "PushFormulaToCart", Cancel: Exit Sub

    If Not Intersect(Target, Range("btnInitCalibration")) Is Nothing _
           Then RunButton Target, "InitCalibrationSheet", Cancel: Exit Sub
       If Not Intersect(Target, Range("btnMatchWaypoints")) Is Nothing _
           Then RunButton Target, "MatchWaypointsToLog", Cancel: Exit Sub

    If Not Intersect(Target, Range("btnPushAstro")) Is Nothing _
        Then RunButton Target, "PushAstroToCart", Cancel: Exit Sub

    If Not Intersect(Target, Range("btnPushTrack")) Is Nothing _
        Then RunButton Target, "PushTrackPathsToCart", Cancel: Exit Sub

End Sub


