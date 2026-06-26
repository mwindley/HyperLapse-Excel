Attribute VB_Name = "PanoConfigPush"
' HyperLapse - push the two pano configs to the cart.
'
' Reads the PANO sheet's landscape + portrait config blocks (the panoL_*/panoP_*
' named ranges) and sends each to the cart's /settings/panocfg endpoint, so the
' cart holds BOTH resident. Whatever triggers a pano on the cart selects which
' (manual/landscape = PanoCentre; arch track = PanoCycle/portrait).
'
' What crosses to the cart: yaw-column count (n), mode (0=Centre out-and-back,
' 1=Cycle walk-through), the two-row grid (rows + rowstep, deg), and the yaw
' offset list. Cadence is NOT pushed - the sketch
' runs the pano flat-out at its slew/settle limits and the real cadence emerges;
' the PANO sheet's cadence is an operator-side estimate only.
'
' Offsets are rounded to whole degrees for the wire (the Ronin SDK position
' command is 0.1 deg fixed-point anyway; whole-degree offsets are plenty).
'
' Call PushPanoConfigs from Prep Cart (after astropos / trackplan) or standalone.

Option Explicit

Private Const PANO_SHEET As String = "PANO"
Private Const LOG_CAT As String = "PANOPUSH"

Public Sub PushPanoConfigs()
    Dim arduinoIP As String
    On Error Resume Next
    arduinoIP = CStr(ThisWorkbook.Worksheets("Settings").Range("dataArduinoIP").value)
    On Error GoTo 0
    If arduinoIP = "" Then
        LogEvent LOG_CAT, "no dataArduinoIP - skipped"
        Exit Sub
    End If

    PushOne arduinoIP, "L", "panoL_shots", "panoL_offsets", "landscape"
    PushOne arduinoIP, "P", "panoP_shots", "panoP_offsets", "portrait"
End Sub

' Push one config block. cfgLetter = "L"/"P"; mode is derived from orientation
' convention: landscape = Centre (0), portrait = Cycle (1). (If you ever want a
' portrait Centre or landscape Cycle, add a mode cell to the block and read it
' here instead of inferring.)
Private Sub PushOne(ByVal arduinoIP As String, ByVal cfgLetter As String, _
                    ByVal shotsName As String, ByVal offsetsName As String, _
                    ByVal label As String)
    Dim n As Long, modeVal As Long
    On Error GoTo fail

    n = CLng(ThisWorkbook.names(shotsName).RefersToRange.value)
    If n < 1 Then n = 1
    If n > 8 Then n = 8

    ' mode: landscape -> Centre (0), portrait -> Cycle (1)
    modeVal = IIf(cfgLetter = "P", 1, 0)

    ' rows + rowstep (the two-row grid): PanoCycle pushes rows=2 + the pitch step
    ' (deg) so the cart fans the yaw columns over two pitch rows; PanoCentre rows=1.
    ' Read from the same block by prefix; default to single-row if the cells predate
    ' a sheet rebuild (graceful - no crash, cart just runs one row).
    Dim nmPfx As String: nmPfx = "pano" & cfgLetter & "_"
    Dim rowsVal As Long: rowsVal = 1
    Dim rowstepVal As Long: rowstepVal = 0
    On Error Resume Next
    rowsVal = CLng(ThisWorkbook.names(nmPfx & "rows").RefersToRange.value)
    rowstepVal = CLng(Round(CDbl(ThisWorkbook.names(nmPfx & "rowstep").RefersToRange.value), 0))
    On Error GoTo fail
    If rowsVal < 1 Then rowsVal = 1
    If rowsVal > 8 Then rowsVal = 8

    Dim qs As String
    qs = "?cfg=" & cfgLetter & "&n=" & n & "&mode=" & modeVal & _
         "&rows=" & rowsVal & "&rowstep=" & rowstepVal

    ' offsets: read the 8-cell named row, round to whole deg, send the first n.
    Dim offRng As Range: Set offRng = ThisWorkbook.names(offsetsName).RefersToRange
    Dim i As Long, c As Range, k As Long
    k = 0
    For Each c In offRng
        If k >= n Then Exit For
        Dim ov As Double
        If IsNumeric(c.value) And Trim(CStr(c.value)) <> "" Then
            ov = CDbl(c.value)
            qs = qs & "&o" & k & "=" & Format(Round(ov, 0), "0")
        End If
        k = k + 1
    Next c

    Dim url As String
    url = arduinoIP & "/settings/panocfg" & qs
    LogEvent LOG_CAT, "GET " & url

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", url, False
    http.SetTimeouts 5000, 5000, 5000, 8000
    http.Send
    Dim sc As Long
    sc = http.Status
    If sc = 200 Then
        LogEvent LOG_CAT, label & " OK " & CStr(http.responseText)
    Else
        LogEvent LOG_CAT, label & " HTTP " & sc
    End If
    Exit Sub

fail:
    LogEvent LOG_CAT, label & " error " & Err.Number & ": " & Err.Description
End Sub
