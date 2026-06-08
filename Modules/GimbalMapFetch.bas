Attribute VB_Name = "GimbalMapFetch"
' HyperLapse - fetch a north-up satellite map for the gimbal Plan View
' underlay (map v2). Pulls a square image centred on Settings lat/lon,
' SPAN_KM across, and saves it to <workbook>\Python\map.png so the
' renderer's --map can use it.
'
' Source: Esri ArcGIS World_Imagery MapServer "export" - NO API KEY.
' bbox is built in Web Mercator (3857) as a SQUARE so the image is
' north-up and undistorted (degree bbox would stretch E-W at this lat).
'
' Run: GimbalMapFetch.FetchGimbalMap
' Then point the Render button at it: in GimbalPlanViewButton set
'   MAP_PATH = <workbook>\Python\map.png   (or use the auto-detect tweak).
'
' NOTE on terms: the keyless export is fine for personal/light use but is
' subject to Esri's terms (attribution / rate limits). For heavy or
' commercial use, get an Esri token or switch SERVICE/host to a provider
' you have a key for (Google Static Maps is the obvious alternative).

Option Explicit

' ---- tuneables ----
Private Const SPAN_KM As Double = 60#       ' image is SPAN_KM across (centre +/- 30 km)
Private Const PX As Long = 1024             ' output pixels (square)
Private Const SERVICE As String = "World_Imagery"  ' or World_Topo_Map / World_Street_Map
Private Const HOST As String = "https://services.arcgisonline.com/arcgis/rest/services/"
' -------------------

Public Sub FetchGimbalMap()
    On Error GoTo Fail

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Settings")
    Dim lat As Double, lon As Double
    lat = ws.Range("dataLatitude").value
    lon = ws.Range("dataLongitude").value

    ' --- centre lat/lon -> Web Mercator (3857) metres ---
    Const R As Double = 6378137#
    Dim rad As Double: rad = (4# * Atn(1#)) / 180#     ' deg -> rad
    Dim cx As Double, cy As Double
    cx = R * lon * rad
    cy = R * Log(Tan((90# + lat) * rad / 2#))          ' Log = natural log in VBA

    ' --- square bbox, half-span in metres ---
    Dim half As Double
    half = (SPAN_KM * 1000#) / 2#
    Dim xmin As Double, ymin As Double, xmax As Double, ymax As Double
    xmin = cx - half: xmax = cx + half
    ymin = cy - half: ymax = cy + half

    ' --- build export URL ---
    Dim bbox As String
    bbox = Format(xmin, "0.0") & "," & Format(ymin, "0.0") & "," & _
           Format(xmax, "0.0") & "," & Format(ymax, "0.0")
    Dim url As String
    url = HOST & SERVICE & "/MapServer/export" & _
          "?bbox=" & bbox & _
          "&bboxSR=3857&imageSR=3857" & _
          "&size=" & PX & "," & PX & _
          "&format=png&transparent=false&f=image"

    ' --- destination: <workbook>\Python\map.png ---
    Dim base As String, outPng As String
    base = ThisWorkbook.Path
    If base = "" Then
        MsgBox "Save the workbook once before fetching the map.", vbExclamation
        Exit Sub
    End If
    outPng = base & Application.PathSeparator & "Python" & _
             Application.PathSeparator & "map.png"

    ' --- HTTP GET (binary) ---
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", url, False
    http.Send
    If http.Status <> 200 Then
        MsgBox "Map fetch failed. HTTP " & http.Status & vbCrLf & url, vbExclamation
        Exit Sub
    End If

    Dim body() As Byte
    body = http.responseBody
    If (UBound(body) - LBound(body) + 1) < 2000 Then
        ' too small to be a real image - likely an error response
        MsgBox "Map fetch returned a suspiciously small file (" & _
               (UBound(body) - LBound(body) + 1) & " bytes). " & _
               "The service may have returned an error. URL:" & vbCrLf & url, _
               vbExclamation
        Exit Sub
    End If

    ' --- write bytes to PNG (ADODB.Stream, binary) ---
    Dim st As Object
    Set st = CreateObject("ADODB.Stream")
    st.Type = 1                ' adTypeBinary
    st.Open
    st.Write body
    st.SaveToFile outPng, 2    ' adSaveCreateOverWrite
    st.Close

    MsgBox "Map saved (" & SPAN_KM & " km, " & PX & "x" & PX & "):" & vbCrLf & _
           outPng & vbCrLf & vbCrLf & _
           "Set MAP_PATH in GimbalPlanViewButton to this path, then Render.", _
           vbInformation, "Fetch Gimbal Map"
    Exit Sub

Fail:
    MsgBox "Map fetch error: " & Err.Description, vbExclamation
End Sub
