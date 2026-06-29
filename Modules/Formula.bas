Attribute VB_Name = "Formula"
' ============================================================
' HyperLapse Cart - Simple Fallback Formula Module
'
' PURPOSE
'   Excel-side implementation of the simple formula that
'   approximates the Old World Table (EXPOSURE_FALLBACK.md
'   Appendix A). Used as CCAPI fallback when live luminance
'   reads are unavailable.
'
'   This module is the Excel half of WORKFRONT #36 / #36a.
'   The matching cart firmware (#36b) does not yet exist;
'   PushFormulaToCart still POSTs the payload - the 404 from
'   the cart is acceptable and confirms the Excel side works.
'
' ARCHITECTURE
'   - FallbackFormula sheet holds parameters.
'     Column B = parameter name. Columns C, D, E... = branches
'     (default, bright, dull, ...).
'   - Branches added by inserting a new column at the right of
'     the parameter block.
'   - FormulaTv / FormulaISO are user-defined Excel functions
'     usable in any cell:
'       =FormulaTv(t_rel, "default", "Sunset")
'       =FormulaISO(t_rel, "default", "Sunrise")
'   - The live evaluator at the bottom of FallbackFormula uses
'     these UDFs so the operator can scrub a t_rel value AND
'     pick sun event (Sunset / Sunrise) and see (Tv, ISO) update.
'
' WORKFLOW
'   First time: run InitFallbackFormula to build the sheet
'   and seed the default column from Appendix A.
'
'   Per shoot:
'     - Operator picks branch via dataActiveBranch named range
'       (Settings sheet).
'     - Operator double-clicks "Push Formula" button to send
'       active branch parameters (both sunset and sunrise blocks)
'       to cart /exposure/load.
'
' PUBLIC ENTRY POINTS
'   InitFallbackFormula   - one-shot setup, builds the sheet
'   FormulaTv             - UDF: =FormulaTv(t_rel, branch, sunEvent)
'   FormulaISO            - UDF: =FormulaISO(t_rel, branch, sunEvent)
'   PushFormulaToCart     - POSTs active branch to /exposure/load
'   AddBranch             - copies an existing branch into a new column
'
' DESIGN NOTES
'   - Sunrise is stored independently of sunset (not mirrored).
'     Appendix A has different t_rel values for sunrise crossovers
'     than for sunset - sunrise is darker by operator design
'     (luminance target 40 vs sunset 60) to preserve blue/orange
'     contrast. See EXPOSURE_FALLBACK.md.
'   - sunEvent parameter is "Sunset" or "Sunrise" (case-insensitive).
'   - Tv ceiling (20s) and ISO ceiling (1600) are policy
'     choices; they appear as parameters in the sheet but are
'     NOT expected to be re-fitted (see WORKFRONTS #36a).
'   - The formula reproduces Appendix A exactly when default
'     parameters are in place - verify with the live evaluator.
' ============================================================

Option Explicit

Private Const SHEET_NAME As String = "FallbackFormula"

' Layout constants - rows on FallbackFormula sheet
' Day 9 late-late evening: sunrise block added below sunset block.
' Each event has its own Tv-crossover and ISO-ramp sections.
Private Const ROW_TITLE        As Long = 1
Private Const ROW_BRANCH_HDR   As Long = 3      ' "default" | "bright" | ...

' Sunset section
Private Const ROW_SS_TV_HDR    As Long = 5
Private Const ROW_SS_TV_FIRST  As Long = 6      ' first Tv crossover
Private Const ROW_SS_TV_LAST   As Long = 56     ' last (51 sunset Tv rows)

Private Const ROW_SS_ISO_HDR   As Long = 58
Private Const ROW_SS_ISO_FIRST As Long = 59
Private Const ROW_SS_ISO_LAST  As Long = 70     ' 12 sunset ISO ramp rows

' Sunrise section (starts with ISO ramp at deep-dark, then Tv ramp out)
Private Const ROW_SR_ISO_HDR   As Long = 73
Private Const ROW_SR_ISO_FIRST As Long = 74
Private Const ROW_SR_ISO_LAST  As Long = 87     ' 14 sunrise ISO ramp rows

Private Const ROW_SR_TV_HDR    As Long = 89
Private Const ROW_SR_TV_FIRST  As Long = 90
Private Const ROW_SR_TV_LAST   As Long = 138    ' 49 sunrise Tv rows

' Policy ceilings
Private Const ROW_POLICY_HDR   As Long = 141
Private Const ROW_TV_CEILING   As Long = 142
Private Const ROW_ISO_CEILING  As Long = 143
Private Const ROW_ISO_BASE     As Long = 144

' Live evaluator (operator scrubs t_rel + selects sun event)
Private Const ROW_LIVE_HDR     As Long = 146
Private Const ROW_LIVE_EVENT   As Long = 147    ' "Sunset" or "Sunrise"
Private Const ROW_LIVE_TREL    As Long = 148    ' operator scrubs this
Private Const ROW_LIVE_TV      As Long = 149
Private Const ROW_LIVE_ISO     As Long = 150
Private Const ROW_LIVE_BRANCH  As Long = 151    ' shows dataActiveBranch

Private Const COL_PARAM        As Long = 2      ' B
Private Const COL_DEFAULT      As Long = 3      ' C - first branch column

' ============================================================
' Public - one-shot setup
' ============================================================

' Build the FallbackFormula sheet and seed the default column
' from EXPOSURE_FALLBACK.md Appendix A. Safe to run multiple
' times: prompts before rebuilding if sheet already exists.
Public Sub InitFallbackFormula()
    Dim ws As Worksheet
    Set ws = Nothing
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)
    On Error GoTo 0

    If Not ws Is Nothing Then
        Dim resp As VbMsgBoxResult
        resp = MsgBox("'" & SHEET_NAME & "' sheet already exists." & vbCrLf & _
                      "Rebuild it? Any branches other than 'default' will be lost.", _
                      vbYesNo + vbQuestion, "Init Fallback Formula")
        If resp <> vbYes Then Exit Sub
        Application.DisplayAlerts = False
        ws.Delete
        Application.DisplayAlerts = True
        Set ws = Nothing
    End If

    Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.count))
    ws.Name = SHEET_NAME

    ' Title
    ws.Cells(ROW_TITLE, COL_PARAM).value = "Fallback Formula Parameters"
    ws.Cells(ROW_TITLE, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_TITLE, COL_PARAM).Font.Size = 14

    ' Branch header row
    ws.Cells(ROW_BRANCH_HDR, COL_PARAM).value = "Parameter"
    ws.Cells(ROW_BRANCH_HDR, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_BRANCH_HDR, COL_DEFAULT).value = "default"
    ws.Cells(ROW_BRANCH_HDR, COL_DEFAULT).Font.Bold = True
    Call CellFormat(ws.Cells(ROW_BRANCH_HDR, COL_DEFAULT), "FormatBlue")

    ' --- Sunset section ---
    ws.Cells(ROW_SS_TV_HDR, COL_PARAM).value = "-- Sunset Tv crossovers (t_rel sec) --"
    ws.Cells(ROW_SS_TV_HDR, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_SS_TV_HDR, COL_PARAM).Font.Italic = True

    Dim sunsetTvRows As Variant
    sunsetTvRows = SunsetTvDefaults()
    Dim i As Long
    For i = 0 To UBound(sunsetTvRows, 1)
        ws.Cells(ROW_SS_TV_FIRST + i, COL_PARAM).value = _
            "Tv=" & sunsetTvRows(i, 1) & " (ISO " & sunsetTvRows(i, 2) & ")"
        ws.Cells(ROW_SS_TV_FIRST + i, COL_DEFAULT).value = sunsetTvRows(i, 0)
    Next i

    ws.Cells(ROW_SS_ISO_HDR, COL_PARAM).value = "-- Sunset ISO ramp (Tv pinned at ceiling) --"
    ws.Cells(ROW_SS_ISO_HDR, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_SS_ISO_HDR, COL_PARAM).Font.Italic = True

    Dim sunsetIsoRows As Variant
    sunsetIsoRows = SunsetIsoDefaults()
    For i = 0 To UBound(sunsetIsoRows, 1)
        ws.Cells(ROW_SS_ISO_FIRST + i, COL_PARAM).value = _
            "ISO=" & sunsetIsoRows(i, 1) & " at t_rel (sec)"
        ws.Cells(ROW_SS_ISO_FIRST + i, COL_DEFAULT).value = sunsetIsoRows(i, 0)
    Next i

    ' --- Sunrise section ---
    ' Sunrise STARTS in ISO-ramped deep dark (Tv pinned at ceiling),
    ' then walks Tv down to fast as sun rises. So we lay out ISO ramp
    ' first (most negative t_rel), then Tv crossovers.
    ws.Cells(ROW_SR_ISO_HDR, COL_PARAM).value = "-- Sunrise ISO ramp (deep dark to ISO base) --"
    ws.Cells(ROW_SR_ISO_HDR, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_SR_ISO_HDR, COL_PARAM).Font.Italic = True

    Dim sunriseIsoRows As Variant
    sunriseIsoRows = SunriseIsoDefaults()
    For i = 0 To UBound(sunriseIsoRows, 1)
        ws.Cells(ROW_SR_ISO_FIRST + i, COL_PARAM).value = _
            "ISO=" & sunriseIsoRows(i, 1) & " at t_rel (sec)"
        ws.Cells(ROW_SR_ISO_FIRST + i, COL_DEFAULT).value = sunriseIsoRows(i, 0)
    Next i

    ws.Cells(ROW_SR_TV_HDR, COL_PARAM).value = "-- Sunrise Tv crossovers (t_rel sec) --"
    ws.Cells(ROW_SR_TV_HDR, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_SR_TV_HDR, COL_PARAM).Font.Italic = True

    Dim sunriseTvRows As Variant
    sunriseTvRows = SunriseTvDefaults()
    For i = 0 To UBound(sunriseTvRows, 1)
        ws.Cells(ROW_SR_TV_FIRST + i, COL_PARAM).value = _
            "Tv=" & sunriseTvRows(i, 1) & " (ISO " & sunriseTvRows(i, 2) & ")"
        ws.Cells(ROW_SR_TV_FIRST + i, COL_DEFAULT).value = sunriseTvRows(i, 0)
    Next i

    ' Policy ceilings block
    ws.Cells(ROW_POLICY_HDR, COL_PARAM).value = "-- Policy ceilings (fixed, not refit) --"
    ws.Cells(ROW_POLICY_HDR, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_POLICY_HDR, COL_PARAM).Font.Italic = True
    ws.Cells(ROW_TV_CEILING, COL_PARAM).value = "Tv ceiling (sec)"
    ws.Cells(ROW_TV_CEILING, COL_DEFAULT).value = 20
    ws.Cells(ROW_ISO_CEILING, COL_PARAM).value = "ISO ceiling"
    ws.Cells(ROW_ISO_CEILING, COL_DEFAULT).value = 1600
    ws.Cells(ROW_ISO_BASE, COL_PARAM).value = "ISO base (Tv-only phase)"
    ws.Cells(ROW_ISO_BASE, COL_DEFAULT).value = 100

    ' Live evaluator block (operator picks event + scrubs t_rel)
    ws.Cells(ROW_LIVE_HDR, COL_PARAM).value = "-- Live evaluator (pick event, scrub t_rel) --"
    ws.Cells(ROW_LIVE_HDR, COL_PARAM).Font.Bold = True
    ws.Cells(ROW_LIVE_HDR, COL_PARAM).Font.Italic = True

    ws.Cells(ROW_LIVE_EVENT, COL_PARAM).value = "Sun event"
    ws.Cells(ROW_LIVE_EVENT, COL_DEFAULT).value = "Sunset"
    Call CellFormat(ws.Cells(ROW_LIVE_EVENT, COL_DEFAULT), "FormatYellow")

    ws.Cells(ROW_LIVE_TREL, COL_PARAM).value = "t_rel (sec)"
    ws.Cells(ROW_LIVE_TREL, COL_DEFAULT).value = 0
    Call CellFormat(ws.Cells(ROW_LIVE_TREL, COL_DEFAULT), "FormatYellow")

    ' Build the live formulas. Branch comes from dataActiveBranch,
    ' event from the yellow cell above.
    Dim trelAddr As String
    Dim evtAddr As String
    Dim branchExpr As String
    trelAddr = ws.Cells(ROW_LIVE_TREL, COL_DEFAULT).Address
    evtAddr = ws.Cells(ROW_LIVE_EVENT, COL_DEFAULT).Address
    branchExpr = "dataActiveBranch"

    ws.Cells(ROW_LIVE_TV, COL_PARAM).value = "Tv"
    ws.Cells(ROW_LIVE_TV, COL_DEFAULT).Formula = _
        "=FormulaTv(" & trelAddr & "," & branchExpr & "," & evtAddr & ")"

    ws.Cells(ROW_LIVE_ISO, COL_PARAM).value = "ISO"
    ws.Cells(ROW_LIVE_ISO, COL_DEFAULT).Formula = _
        "=FormulaISO(" & trelAddr & "," & branchExpr & "," & evtAddr & ")"

    ws.Cells(ROW_LIVE_BRANCH, COL_PARAM).value = "Branch in use"
    ws.Cells(ROW_LIVE_BRANCH, COL_DEFAULT).Formula = "=dataActiveBranch"

    ' Column widths
    ws.Columns(COL_PARAM).ColumnWidth = 36
    ws.Columns(COL_DEFAULT).ColumnWidth = 12

    ' Create / refresh dataActiveBranch named range on Settings sheet
    Call EnsureActiveBranchNamedRange

    ws.Activate
    ws.Cells(1, 1).Select

    LogEvent "FORMULA", "InitFallbackFormula complete; default column seeded from Appendix A"

    MsgBox "FallbackFormula sheet ready." & vbCrLf & vbCrLf & _
           "Default column is seeded from Old World Table (Appendix A)." & vbCrLf & _
           "Set dataActiveBranch on Settings sheet to a branch name." & vbCrLf & _
           "Scrub the t_rel cell to verify the formula.", _
           vbInformation, "Init Fallback Formula"
End Sub

' Ensure dataActiveBranch named range exists on Settings sheet
' (or create it). Initial value = "default".
Private Sub EnsureActiveBranchNamedRange()
    Dim wsSet As Worksheet
    Set wsSet = ThisWorkbook.Sheets("Settings")

    ' Try to find an unused cell; convention: put it near the camera state block
    ' If named range already exists, leave it alone.
    Dim nm As Name
    Dim NameExists As Boolean
    NameExists = False
    For Each nm In ThisWorkbook.names
        If nm.Name = "dataActiveBranch" Then
            NameExists = True
            Exit For
        End If
    Next nm

    If NameExists Then Exit Sub

    ' Place it in an empty cell on Settings - row 44 (below current content)
    Dim addr As String
    addr = "$C$44"
    wsSet.Range(addr).value = "default"
    wsSet.Cells(44, 2).value = "Active branch"
    wsSet.Cells(44, 2).Font.Italic = True

    ThisWorkbook.names.Add Name:="dataActiveBranch", _
                           refersTo:="=Settings!" & addr
End Sub

' ============================================================
' UDFs - usable in any cell
' ============================================================

' Return Tv string for a given t_rel, branch, and sun event.
'
' sunEvent: "Sunset" or "Sunrise" (case-insensitive). Determines
' which block of rows the formula walks.
'
' t_rel sign convention (matches Appendix A):
'   Sunset:  -ve = before sunset (daylight),  +ve = after sunset (twilight)
'   Sunrise: -ve = before sunrise (twilight), +ve = after sunrise (daylight)
'
' Logic differs between events:
'
' SUNSET:
'   Walk the sunset Tv rows in t_rel-ascending order. First row whose
'   t_rel >= input t gives the Tv label for this interval. Past the
'   last row (deep twilight), Tv pinned at ceiling and ISO is ramping.
'
' SUNRISE:
'   At very negative t (deep dark), we're in the ISO ramp zone with
'   Tv pinned at ceiling. As t increases toward 0, we cross into the
'   Tv-walk zone with ISO at base. Walk sunrise Tv rows the same way;
'   when t is below the first Tv row's t_rel, return Tv ceiling.
Public Function FormulaTv(ByVal t_rel As Variant, _
                          ByVal branch As Variant, _
                          ByVal sunEvent As Variant) As Variant
    Application.Volatile False
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)

    Dim branchCol As Long
    branchCol = FindBranchColumn(CStr(branch))
    If branchCol = 0 Then
        FormulaTv = "#BRANCH?"
        Exit Function
    End If

    Dim t As Double
    t = CDbl(t_rel)

    Dim tvCeiling As Double
    tvCeiling = CDbl(ws.Cells(ROW_TV_CEILING, branchCol).value)

    Dim evt As String
    evt = LCase(CStr(sunEvent))

    Dim tvFirst As Long, tvLast As Long, isoBoundaryRow As Long
    Dim sunriseSide As Boolean
    If evt = "sunset" Then
        tvFirst = ROW_SS_TV_FIRST
        tvLast = ROW_SS_TV_LAST
        isoBoundaryRow = ROW_SS_ISO_FIRST
        sunriseSide = False
    ElseIf evt = "sunrise" Then
        tvFirst = ROW_SR_TV_FIRST
        tvLast = ROW_SR_TV_LAST
        isoBoundaryRow = ROW_SR_TV_FIRST
        sunriseSide = True
    Else
        FormulaTv = "#EVENT?"
        Exit Function
    End If

    ' Bulk-read t_rel column AND param name column in two Range reads.
    ' This collapses N COM calls into 2, fixing the responsiveness issue.
    Dim trelRange As Range
    Dim paramRange As Range
    Set trelRange = ws.Range(ws.Cells(tvFirst, branchCol), ws.Cells(tvLast, branchCol))
    Set paramRange = ws.Range(ws.Cells(tvFirst, COL_PARAM), ws.Cells(tvLast, COL_PARAM))

    Dim trelVals As Variant, paramVals As Variant
    trelVals = trelRange.value     ' 2D array (rows x 1)
    paramVals = paramRange.value

    ' Boundary check - read once, not per row.
    Dim boundaryTrel As Double
    boundaryTrel = CDbl(ws.Cells(isoBoundaryRow, branchCol).value)

    If Not sunriseSide Then
        If t >= boundaryTrel Then
            FormulaTv = SecondsToTv(tvCeiling)
            Exit Function
        End If
    Else
        If t < boundaryTrel Then
            FormulaTv = SecondsToTv(tvCeiling)
            Exit Function
        End If
    End If

    ' Walk the in-memory arrays, not the sheet.
    Dim n As Long, i As Long
    n = UBound(trelVals, 1)
    For i = 1 To n
        If IsNumeric(trelVals(i, 1)) Then
            If CDbl(trelVals(i, 1)) >= t Then
                FormulaTv = ExtractTvFromParamName(CStr(paramVals(i, 1)))
                Exit Function
            End If
        End If
    Next i

    FormulaTv = SecondsToTv(tvCeiling)
    Exit Function

ErrHandler:
    FormulaTv = "#ERR:" & Err.Description
End Function

' Return ISO integer for a given t_rel, branch, and sun event.
'
' SUNSET ISO logic:
'   - t < first sunset ISO-ramp row -> ISO = base (typically 100)
'   - else -> walk sunset ISO rows; first row whose t_rel >= t gives ISO
'   - past the last -> ISO ceiling
'
' SUNRISE ISO logic (reversed):
'   - t < first sunrise ISO-ramp row -> ISO = ceiling (still deep dark)
'   - t in ISO ramp range -> walk sunrise ISO rows; first row whose
'     t_rel >= t gives ISO (ramping DOWN from ceiling to base)
'   - t past last ISO ramp row -> ISO = base (Tv-walk zone has ISO=base)
Public Function FormulaISO(ByVal t_rel As Variant, _
                           ByVal branch As Variant, _
                           ByVal sunEvent As Variant) As Variant
    Application.Volatile False
    On Error GoTo ErrHandler

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)

    Dim branchCol As Long
    branchCol = FindBranchColumn(CStr(branch))
    If branchCol = 0 Then
        FormulaISO = "#BRANCH?"
        Exit Function
    End If

    Dim t As Double
    t = CDbl(t_rel)

    Dim isoBase As Long
    Dim isoCeiling As Long
    isoBase = CLng(ws.Cells(ROW_ISO_BASE, branchCol).value)
    isoCeiling = CLng(ws.Cells(ROW_ISO_CEILING, branchCol).value)

    Dim evt As String
    evt = LCase(CStr(sunEvent))

    Dim isoFirst As Long, isoLast As Long
    Dim sunriseSide As Boolean
    If evt = "sunset" Then
        isoFirst = ROW_SS_ISO_FIRST
        isoLast = ROW_SS_ISO_LAST
        sunriseSide = False
    ElseIf evt = "sunrise" Then
        isoFirst = ROW_SR_ISO_FIRST
        isoLast = ROW_SR_ISO_LAST
        sunriseSide = True
    Else
        FormulaISO = "#EVENT?"
        Exit Function
    End If

    ' Bulk-read t_rel and param-name columns once.
    Dim trelVals As Variant, paramVals As Variant
    trelVals = ws.Range(ws.Cells(isoFirst, branchCol), ws.Cells(isoLast, branchCol)).value
    paramVals = ws.Range(ws.Cells(isoFirst, COL_PARAM), ws.Cells(isoLast, COL_PARAM)).value

    ' Boundary read once.
    Dim firstTrel As Double
    firstTrel = CDbl(trelVals(1, 1))
    Dim lastTrel As Double
    lastTrel = CDbl(trelVals(UBound(trelVals, 1), 1))

    If Not sunriseSide Then
        ' Sunset: before ramp -> base; after last -> ceiling
        If t < firstTrel Then
            FormulaISO = isoBase
            Exit Function
        End If
    Else
        ' Sunrise: after ramp end -> base (Tv-walk zone)
        If t > lastTrel Then
            FormulaISO = isoBase
            Exit Function
        End If
    End If

    ' Walk in-memory arrays.
    Dim n As Long, i As Long
    n = UBound(trelVals, 1)
    For i = 1 To n
        If IsNumeric(trelVals(i, 1)) Then
            If CDbl(trelVals(i, 1)) >= t Then
                FormulaISO = ExtractIsoFromParamName(CStr(paramVals(i, 1)))
                Exit Function
            End If
        End If
    Next i

    ' Past last row in ramp block
    If Not sunriseSide Then
        FormulaISO = isoCeiling
    Else
        FormulaISO = isoBase
    End If
    Exit Function

ErrHandler:
    FormulaISO = "#ERR:" & Err.Description
End Function

' ============================================================
' Push to cart
' ============================================================

' PushFormulaToCart - push the night's LUM facts to the cart.
' Wired for double-click via Buttons.RunButton - bind to a button
' cell on Control sheet named btnPushFormula. Called by PushToCart
' (Prep Cart) in the three-button flow.
'
' #item2 (28Jun) NEW CONTRACT - the cart owns the phase decision:
'   /exposure/epochs?dusk=<epoch_ms>&dawn=<epoch_ms>  (absolute UTC ms)
'   /exposure/target?ss=<60>&sr=<40>                  (the two style targets)
' The cart (firmware v255 lumPhaseSelect) compares its OWN clock to the
' two epochs and picks the active target: now<dusk -> sunset(ss),
' else -> sunrise(sr). Flip is at TRUE DARK (astro dusk/dawn) where the
' walk is pinned at the night rail, so it is consequence-free. One push
' covers the whole shoot; operator never re-pushes mid-shoot.
'
' SUPERSEDES the old /exposure/load TABLE-fallback push (the four cubic
' ladders sstv/ssiso/srtv/sriso + relative t0ss/t0sr/cross). That fed the
' cart TABLE walk removed in firmware v253/254 - all dead now.
'
' Reads dataAstroDusk + dataAstroDawn (populated by GetSunsetTime for the
' shoot night) and dataLumTargetSunset/Sunrise (style targets, 60/40).
' Local Excel date-serials are converted to absolute UTC epoch-ms via
' ExcelLocalToEpochMs (UTC+9.5 Adelaide, or dataUTCOffset, Settings C10).
Public Sub PushFormulaToCart()
    ' #item2 (28Jun): REWRITTEN. The cart now owns the LUM phase decision - it
    ' compares its OWN clock to two absolute astro epochs (dusk, dawn) and picks
    ' the sunset/sunrise target itself (firmware v255 lumPhaseSelect). Excel's job
    ' is only to PROVIDE the night's facts:
    '   /exposure/epochs?dusk=<epoch_ms>&dawn=<epoch_ms>   (absolute UTC ms)
    '   /exposure/target?ss=<60>&sr=<40>                   (the two style targets)
    ' The old push (TABLE fallback) is GONE: the four cubic ladders sstv/ssiso/
    ' srtv/sriso, the relative t0ss/t0sr/cross seconds, and the /exposure/load GET
    ' all fed the removed cart TABLE walk (firmware v253/254) - dead weight.
    Dim setSheet As Worksheet
    Set setSheet = ThisWorkbook.Sheets("Settings")

    ' Astro boundaries computed by GetSunsetTime for the shoot night. Item 2 flips
    ' at TRUE DARK (astro dusk / astro dawn), not civil sun events - the walk is
    ' pinned at the night rail there so the target flip is consequence-free.
    Dim astroDusk As Date, astroDawn As Date
    astroDusk = setSheet.Range("dataAstroDusk").value
    On Error Resume Next
    astroDawn = setSheet.Range("dataAstroDawn").value
    On Error GoTo 0

    If astroDusk = 0 Or astroDawn = 0 Then
        LogEvent "FORMULA", "PushFormulaToCart: astro dusk/dawn not set - run Prep Session (Get Sunset Time) first"
        MsgBox "Astro dusk/dawn not set. Run Prep Session (Get Sunset Time) first.", vbExclamation
        Exit Sub
    End If

    ' Convert the local Excel date-serials to absolute UTC epoch-ms. The shoot
    ' location's UTC offset is dataUTCOffset (Settings C10, e.g. 9.5 for Adelaide).
    Dim utcOffHours As Double
    utcOffHours = 9.5
    Dim vOff As Variant
    On Error Resume Next
    vOff = setSheet.Range("dataUTCOffset").value
    On Error GoTo 0
    If IsNumeric(vOff) Then utcOffHours = CDbl(vOff)

    Dim duskMs As Double, dawnMs As Double
    duskMs = ExcelLocalToEpochMs(astroDusk, utcOffHours)
    dawnMs = ExcelLocalToEpochMs(astroDawn, utcOffHours)

    Dim arduinoIP As String
    arduinoIP = CStr(setSheet.Range("dataArduinoIP").value)

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")

    ' --- Push the two astro epochs (absolute UTC ms) ---
    Dim epUrl As String
    epUrl = arduinoIP & "/exposure/epochs?dusk=" & Format(duskMs, "0") & _
            "&dawn=" & Format(dawnMs, "0")
    Dim esc As Long, eResp As String
    On Error Resume Next
    http.Open "GET", epUrl, False
    http.Send
    esc = http.Status
    eResp = CStr(http.responseText)
    On Error GoTo 0
    If esc = 200 Then
        LogEvent "FORMULA", "GET /exposure/epochs dusk=" & Format(duskMs, "0") & _
                 " dawn=" & Format(dawnMs, "0") & " OK " & eResp
    Else
        LogEvent "FORMULA", "GET /exposure/epochs HTTP " & esc & " " & eResp
    End If

    ' --- Push the phase-aware luminance target pair. ss = sunset target, sr =
    ' sunrise target; the cart selects the active one by clock vs the epochs. ---
    Dim ssT As Long, srT As Long
    ssT = 60: srT = 40
    Dim vss As Variant, vsr As Variant
    vss = setSheet.Range("dataLumTargetSunset").value
    vsr = setSheet.Range("dataLumTargetSunrise").value
    If IsNumeric(vss) Then ssT = CLng(vss)
    If IsNumeric(vsr) Then srT = CLng(vsr)

    Dim tgtUrl As String
    tgtUrl = arduinoIP & "/exposure/target?ss=" & ssT & "&sr=" & srT
    Dim tsc As Long, tResp As String
    On Error Resume Next
    http.Open "GET", tgtUrl, False
    http.Send
    tsc = http.Status
    tResp = CStr(http.responseText)
    On Error GoTo 0
    If tsc = 200 Then
        LogEvent "FORMULA", "GET /exposure/target ss=" & ssT & " sr=" & srT & " OK " & tResp
    Else
        LogEvent "FORMULA", "GET /exposure/target ss=" & ssT & " sr=" & srT & " HTTP " & tsc
    End If
End Sub

' #item2: convert a LOCAL Excel date-serial to absolute UTC epoch-milliseconds.
' Excel serial 25569 = 1970-01-01. Subtract the UTC offset to get UTC, then to ms.
Private Function ExcelLocalToEpochMs(ByVal localSerial As Double, ByVal utcOffHours As Double) As Double
    Dim utcSerial As Double
    utcSerial = localSerial - (utcOffHours / 24#)
    ExcelLocalToEpochMs = (utcSerial - 25569#) * 86400000#
End Function


' Build a Tv block string "t1:tv1,t2:tv2,..." from a row range.
' Returns empty string if no numeric t_rel rows found.
Private Function BuildTvBlock(ByVal ws As Worksheet, _
                              ByVal rowFirst As Long, _
                              ByVal rowLast As Long, _
                              ByVal branchCol As Long) As String
    Dim block As String
    block = ""
    Dim i As Long
    Dim first As Boolean
    Dim rowTrel As Variant
    Dim tvStr As String
    first = True
    For i = rowFirst To rowLast
        rowTrel = ws.Cells(i, branchCol).value
        If IsNumeric(rowTrel) Then
            tvStr = ExtractTvFromParamName(CStr(ws.Cells(i, COL_PARAM).value))
            If Not first Then block = block & ","
            block = block & rowTrel & ":" & tvStr
            first = False
        End If
    Next i
    BuildTvBlock = block
End Function


' Build an ISO block string "t1:iso1,t2:iso2,..." from a row range.
Private Function BuildIsoBlock(ByVal ws As Worksheet, _
                               ByVal rowFirst As Long, _
                               ByVal rowLast As Long, _
                               ByVal branchCol As Long) As String
    Dim block As String
    block = ""
    Dim i As Long
    Dim first As Boolean
    Dim rowTrel As Variant
    Dim isoVal As Long
    first = True
    For i = rowFirst To rowLast
        rowTrel = ws.Cells(i, branchCol).value
        If IsNumeric(rowTrel) Then
            isoVal = ExtractIsoFromParamName(CStr(ws.Cells(i, COL_PARAM).value))
            If Not first Then block = block & ","
            block = block & rowTrel & ":" & isoVal
            first = False
        End If
    Next i
    BuildIsoBlock = block
End Function

' ============================================================
' Branch management
' ============================================================

' Add a new branch by copying an existing branch's column.
' Usage: AddBranch "bright", "default" - copies default into a new
' rightmost column labelled "bright".
Public Sub AddBranch(ByVal newBranchName As String, _
                     ByVal copyFromBranch As String)
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)

    ' Verify source exists
    Dim srcCol As Long
    srcCol = FindBranchColumn(copyFromBranch)
    If srcCol = 0 Then
        MsgBox "Source branch '" & copyFromBranch & "' not found", vbExclamation
        Exit Sub
    End If

    ' Verify target doesn't exist
    If FindBranchColumn(newBranchName) > 0 Then
        MsgBox "Branch '" & newBranchName & "' already exists", vbExclamation
        Exit Sub
    End If

    ' Find rightmost branch column
    Dim destCol As Long
    destCol = LastBranchColumn() + 1

    ' Copy source column into dest column (all the data rows; not the live evaluator)
    ws.Cells(ROW_BRANCH_HDR, destCol).value = newBranchName
    ws.Cells(ROW_BRANCH_HDR, destCol).Font.Bold = True
    Call CellFormat(ws.Cells(ROW_BRANCH_HDR, destCol), "FormatBlue")

    Dim r As Long
    ' Copy all data rows: sunset Tv, sunset ISO, sunrise ISO, sunrise Tv, policies.
    ' Row range covers the entire parameter block from first sunset Tv row
    ' through to ISO base row (which is the last policy row).
    For r = ROW_SS_TV_FIRST To ROW_ISO_BASE
        ws.Cells(r, destCol).value = ws.Cells(r, srcCol).value
    Next r

    LogEvent "FORMULA", "AddBranch '" & newBranchName & "' copied from '" & copyFromBranch & "'"
End Sub

' ============================================================
' Internals
' ============================================================

' Find the column number for a branch name (searching the header row).
' Returns 0 if not found.
' Uses a single bulk read of the header row to avoid per-column COM
' overhead (matters because UDFs call this on every recalc).
Private Function FindBranchColumn(ByVal branchName As String) As Long
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)

    ' Bulk-read columns C..Z of the header row in one COM call
    Dim hdrVals As Variant
    hdrVals = ws.Range(ws.Cells(ROW_BRANCH_HDR, COL_DEFAULT), _
                       ws.Cells(ROW_BRANCH_HDR, 26)).value

    Dim c As Long
    For c = 1 To UBound(hdrVals, 2)
        If CStr(hdrVals(1, c)) = branchName Then
            FindBranchColumn = COL_DEFAULT + c - 1
            Exit Function
        End If
    Next c
    FindBranchColumn = 0
End Function

' Rightmost column with a branch header populated.
Private Function LastBranchColumn() As Long
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)
    Dim c As Long
    Dim last As Long
    last = COL_DEFAULT - 1
    For c = COL_DEFAULT To 26
        If CStr(ws.Cells(ROW_BRANCH_HDR, c).value) <> "" Then last = c
    Next c
    LastBranchColumn = last
End Function

' Param names look like "Tv=1/5000 (ISO 100)" - extract Tv string.
Private Function ExtractTvFromParamName(ByVal paramName As String) As String
    Dim eqPos As Long, spcPos As Long
    eqPos = InStr(paramName, "Tv=")
    If eqPos = 0 Then
        ExtractTvFromParamName = ""
        Exit Function
    End If
    Dim rest As String
    rest = mid(paramName, eqPos + 3)
    spcPos = InStr(rest, " ")
    If spcPos > 0 Then
        ExtractTvFromParamName = Left(rest, spcPos - 1)
    Else
        ExtractTvFromParamName = rest
    End If
End Function

' Param names look like "ISO=125 at t_rel (sec)" or "Tv=... (ISO 100)" -
' extract the ISO integer.
Private Function ExtractIsoFromParamName(ByVal paramName As String) As Long
    Dim eqPos As Long
    eqPos = InStr(paramName, "ISO=")
    If eqPos > 0 Then
        Dim rest As String
        rest = mid(paramName, eqPos + 4)
        Dim spcPos As Long
        spcPos = InStr(rest, " ")
        If spcPos > 0 Then
            ExtractIsoFromParamName = CLng(Left(rest, spcPos - 1))
        Else
            ExtractIsoFromParamName = CLng(rest)
        End If
        Exit Function
    End If
    ' Try parenthesised form: "Tv=1/5000 (ISO 100)"
    Dim parenPos As Long
    parenPos = InStr(paramName, "(ISO ")
    If parenPos > 0 Then
        Dim closePos As Long
        Dim isoStart As Long
        isoStart = parenPos + 5
        closePos = InStr(isoStart, paramName, ")")
        If closePos > 0 Then
            ExtractIsoFromParamName = CLng(mid(paramName, isoStart, closePos - isoStart))
            Exit Function
        End If
    End If
    ExtractIsoFromParamName = 0
End Function

' ============================================================
' Old World Table defaults (Appendix A) for seeding the default branch
' ============================================================

' Sunset Tv crossovers - 51 rows from Appendix A.
' Returns a 2D variant array: rows = Tv crossovers, columns = (t_rel, Tv_str, ISO).
Private Function SunsetTvDefaults() As Variant
    Const n As Long = 51
    Dim out() As Variant
    ReDim out(0 To n - 1, 0 To 2)

    out(0, 0) = -4800: out(0, 1) = "1/5000": out(0, 2) = 100
    out(1, 0) = -4020: out(1, 1) = "1/4000": out(1, 2) = 100
    out(2, 0) = -3240: out(2, 1) = "1/3200": out(2, 2) = 100
    out(3, 0) = -2520: out(3, 1) = "1/2500": out(3, 2) = 100
    out(4, 0) = -1920: out(4, 1) = "1/2000": out(4, 2) = 100
    out(5, 0) = -1440: out(5, 1) = "1/1600": out(5, 2) = 100
    out(6, 0) = -1020: out(6, 1) = "1/1250": out(6, 2) = 100
    out(7, 0) = -840:  out(7, 1) = "1/1000": out(7, 2) = 100
    out(8, 0) = -660:  out(8, 1) = "1/800":  out(8, 2) = 100
    out(9, 0) = -480:  out(9, 1) = "1/640":  out(9, 2) = 100
    out(10, 0) = -300: out(10, 1) = "1/500": out(10, 2) = 100
    out(11, 0) = -120: out(11, 1) = "1/400": out(11, 2) = 100
    out(12, 0) = 60:   out(12, 1) = "1/320": out(12, 2) = 100
    out(13, 0) = 240:  out(13, 1) = "1/250": out(13, 2) = 100
    out(14, 0) = 360:  out(14, 1) = "1/200": out(14, 2) = 100
    out(15, 0) = 540:  out(15, 1) = "1/160": out(15, 2) = 100
    out(16, 0) = 660:  out(16, 1) = "1/125": out(16, 2) = 100
    out(17, 0) = 720:  out(17, 1) = "1/100": out(17, 2) = 100
    out(18, 0) = 780:  out(18, 1) = "1/80":  out(18, 2) = 100
    out(19, 0) = 900:  out(19, 1) = "1/60":  out(19, 2) = 100
    out(20, 0) = 1020: out(20, 1) = "1/50":  out(20, 2) = 100
    out(21, 0) = 1080: out(21, 1) = "1/40":  out(21, 2) = 100
    out(22, 0) = 1140: out(22, 1) = "1/30":  out(22, 2) = 100
    out(23, 0) = 1260: out(23, 1) = "1/25":  out(23, 2) = 100
    out(24, 0) = 1380: out(24, 1) = "1/20":  out(24, 2) = 100
    out(25, 0) = 1440: out(25, 1) = "1/15":  out(25, 2) = 100
    out(26, 0) = 1500: out(26, 1) = "1/13":  out(26, 2) = 100
    out(27, 0) = 1560: out(27, 1) = "1/10":  out(27, 2) = 100
    out(28, 0) = 1620: out(28, 1) = "1/8":   out(28, 2) = 100
    out(29, 0) = 1680: out(29, 1) = "1/6":   out(29, 2) = 100
    out(30, 0) = 1800: out(30, 1) = "1/5":   out(30, 2) = 100
    out(31, 0) = 1860: out(31, 1) = "1/4":   out(31, 2) = 100
    out(32, 0) = 1920: out(32, 1) = "0.3":   out(32, 2) = 100
    out(33, 0) = 1980: out(33, 1) = "0.4":   out(33, 2) = 100
    out(34, 0) = 2040: out(34, 1) = "0.5":   out(34, 2) = 100
    out(35, 0) = 2100: out(35, 1) = "0.6":   out(35, 2) = 100
    out(36, 0) = 2160: out(36, 1) = "0.8":   out(36, 2) = 100
    out(37, 0) = 2220: out(37, 1) = "1":     out(37, 2) = 100
    out(38, 0) = 2280: out(38, 1) = "1.3":   out(38, 2) = 100
    out(39, 0) = 2340: out(39, 1) = "1.6":   out(39, 2) = 100
    out(40, 0) = 2460: out(40, 1) = "2":     out(40, 2) = 100
    out(41, 0) = 2520: out(41, 1) = "2.5":   out(41, 2) = 100
    out(42, 0) = 2580: out(42, 1) = "3.2":   out(42, 2) = 100
    out(43, 0) = 2640: out(43, 1) = "4":     out(43, 2) = 100
    out(44, 0) = 2760: out(44, 1) = "5":     out(44, 2) = 100
    out(45, 0) = 2820: out(45, 1) = "6":     out(45, 2) = 100
    out(46, 0) = 2940: out(46, 1) = "8":     out(46, 2) = 100
    out(47, 0) = 3000: out(47, 1) = "10":    out(47, 2) = 100
    out(48, 0) = 3120: out(48, 1) = "13":    out(48, 2) = 100
    out(49, 0) = 3180: out(49, 1) = "15":    out(49, 2) = 100
    out(50, 0) = 3300: out(50, 1) = "20":    out(50, 2) = 100

    SunsetTvDefaults = out
End Function

' Sunset ISO ramp - 12 rows from Appendix A (Tv pinned at 20s ceiling).
Private Function SunsetIsoDefaults() As Variant
    Const n As Long = 12
    Dim out() As Variant
    ReDim out(0 To n - 1, 0 To 1)

    out(0, 0) = 3360:  out(0, 1) = 125
    out(1, 0) = 3420:  out(1, 1) = 160
    out(2, 0) = 3480:  out(2, 1) = 200
    out(3, 0) = 3540:  out(3, 1) = 250
    out(4, 0) = 3600:  out(4, 1) = 320
    out(5, 0) = 3660:  out(5, 1) = 400
    out(6, 0) = 3720:  out(6, 1) = 500
    out(7, 0) = 3840:  out(7, 1) = 640
    out(8, 0) = 3960:  out(8, 1) = 800
    out(9, 0) = 4080:  out(9, 1) = 1000
    out(10, 0) = 4260: out(10, 1) = 1250
    out(11, 0) = 4440: out(11, 1) = 1600

    SunsetIsoDefaults = out
End Function

' Sunrise ISO ramp - 14 rows from Appendix A.
' Sunrise STARTS in deep dark with ISO at ceiling (1600), Tv at ceiling (20s).
' ISO walks down to base (100) as t_rel becomes less negative.
' Last two rows are the "held at ISO 100 / Tv 20s" period before Tv begins
' walking out.
Private Function SunriseIsoDefaults() As Variant
    Const n As Long = 14
    Dim out() As Variant
    ReDim out(0 To n - 1, 0 To 1)

    out(0, 0) = -5940:  out(0, 1) = 1600
    out(1, 0) = -5760:  out(1, 1) = 1250
    out(2, 0) = -5580:  out(2, 1) = 1000
    out(3, 0) = -5460:  out(3, 1) = 800
    out(4, 0) = -5340:  out(4, 1) = 640
    out(5, 0) = -5220:  out(5, 1) = 500
    out(6, 0) = -5160:  out(6, 1) = 400
    out(7, 0) = -5100:  out(7, 1) = 300
    out(8, 0) = -5040:  out(8, 1) = 250
    out(9, 0) = -4980:  out(9, 1) = 200
    out(10, 0) = -4920: out(10, 1) = 160
    out(11, 0) = -4860: out(11, 1) = 125
    out(12, 0) = -4800: out(12, 1) = 100
    out(13, 0) = -4440: out(13, 1) = 100

    SunriseIsoDefaults = out
End Function

' Sunrise Tv crossovers - 49 rows from Appendix A.
' Tv walks from 20s (ceiling) down through to 1/5000 as t_rel goes from
' -4380 (just after ISO ramp ends) to +60 (one minute past sunrise).
Private Function SunriseTvDefaults() As Variant
    Const n As Long = 49
    Dim out() As Variant
    ReDim out(0 To n - 1, 0 To 2)

    out(0, 0) = -4380:  out(0, 1) = "15":     out(0, 2) = 100
    out(1, 0) = -4320:  out(1, 1) = "13":     out(1, 2) = 100
    out(2, 0) = -4260:  out(2, 1) = "10":     out(2, 2) = 100
    out(3, 0) = -4140:  out(3, 1) = "8":      out(3, 2) = 100
    out(4, 0) = -4020:  out(4, 1) = "6":      out(4, 2) = 100
    out(5, 0) = -3960:  out(5, 1) = "5":      out(5, 2) = 100
    out(6, 0) = -3840:  out(6, 1) = "4":      out(6, 2) = 100
    out(7, 0) = -3780:  out(7, 1) = "3":      out(7, 2) = 100
    out(8, 0) = -3720:  out(8, 1) = "2.5":    out(8, 2) = 100
    out(9, 0) = -3600:  out(9, 1) = "2":      out(9, 2) = 100
    out(10, 0) = -3540: out(10, 1) = "1.6":   out(10, 2) = 100
    out(11, 0) = -3480: out(11, 1) = "1.3":   out(11, 2) = 100
    out(12, 0) = -3420: out(12, 1) = "1":     out(12, 2) = 100
    out(13, 0) = -3300: out(13, 1) = "0.8":   out(13, 2) = 100
    out(14, 0) = -3180: out(14, 1) = "0.6":   out(14, 2) = 100
    out(15, 0) = -3060: out(15, 1) = "0.5":   out(15, 2) = 100
    out(16, 0) = -3000: out(16, 1) = "0.3":   out(16, 2) = 100
    out(17, 0) = -2880: out(17, 1) = "1/4":   out(17, 2) = 100
    out(18, 0) = -2820: out(18, 1) = "1/5":   out(18, 2) = 100
    out(19, 0) = -2700: out(19, 1) = "1/6":   out(19, 2) = 100
    out(20, 0) = -2640: out(20, 1) = "1/8":   out(20, 2) = 100
    out(21, 0) = -2520: out(21, 1) = "1/10":  out(21, 2) = 100
    out(22, 0) = -2460: out(22, 1) = "1/13":  out(22, 2) = 100
    out(23, 0) = -2400: out(23, 1) = "1/15":  out(23, 2) = 100
    out(24, 0) = -2340: out(24, 1) = "1/20":  out(24, 2) = 100
    out(25, 0) = -2280: out(25, 1) = "1/25":  out(25, 2) = 100
    out(26, 0) = -2220: out(26, 1) = "1/30":  out(26, 2) = 100
    out(27, 0) = -2160: out(27, 1) = "1/40":  out(27, 2) = 100
    out(28, 0) = -2100: out(28, 1) = "1/50":  out(28, 2) = 100
    out(29, 0) = -2040: out(29, 1) = "1/60":  out(29, 2) = 100
    out(30, 0) = -1980: out(30, 1) = "1/80":  out(30, 2) = 100
    out(31, 0) = -1860: out(31, 1) = "1/100": out(31, 2) = 100
    out(32, 0) = -1800: out(32, 1) = "1/125": out(32, 2) = 100
    out(33, 0) = -1740: out(33, 1) = "1/160": out(33, 2) = 100
    out(34, 0) = -1620: out(34, 1) = "1/200": out(34, 2) = 100
    out(35, 0) = -1560: out(35, 1) = "1/250": out(35, 2) = 100
    out(36, 0) = -1440: out(36, 1) = "1/320": out(36, 2) = 100
    out(37, 0) = -1320: out(37, 1) = "1/400": out(37, 2) = 100
    out(38, 0) = -1200: out(38, 1) = "1/500": out(38, 2) = 100
    out(39, 0) = -1080: out(39, 1) = "1/640": out(39, 2) = 100
    out(40, 0) = -960:  out(40, 1) = "1/800": out(40, 2) = 100
    out(41, 0) = -780:  out(41, 1) = "1/1000": out(41, 2) = 100
    out(42, 0) = -660:  out(42, 1) = "1/1250": out(42, 2) = 100
    out(43, 0) = -540:  out(43, 1) = "1/1600": out(43, 2) = 100
    out(44, 0) = -420:  out(44, 1) = "1/2000": out(44, 2) = 100
    out(45, 0) = -300:  out(45, 1) = "1/2500": out(45, 2) = 100
    out(46, 0) = -180:  out(46, 1) = "1/3200": out(46, 2) = 100
    out(47, 0) = -60:   out(47, 1) = "1/4000": out(47, 2) = 100
    out(48, 0) = 60:    out(48, 1) = "1/5000": out(48, 2) = 100

    SunriseTvDefaults = out
End Function
