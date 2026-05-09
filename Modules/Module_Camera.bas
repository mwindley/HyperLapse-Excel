Attribute VB_Name = "Camera"
' ============================================================
' Canon R3 CCAPI — Camera Control Module
' Camera IP:   set in Settings sheet named range dataCameraIP
' Arduino IP:  set in Settings sheet named range dataArduinoIP
' All endpoints confirmed from CCAPI Reference v1.4.0
' ParseJsonField and LogEvent are in Module_Utils
' ============================================================

Option Explicit

' -- Constants ------------------------------------------------
' IPs read from named ranges on Settings sheet
Public Const CCAPI_VER As String = "ver100"

Public Function CAMERA_IP() As String
    CAMERA_IP = Sheets("Settings").Range("dataCameraIP").Value
End Function

Public Function ARDUINO_IP() As String
    ARDUINO_IP = Sheets("Settings").Range("dataArduinoIP").Value
End Function

' ISO steps for Phase 2b luminance-based adjustment
Public Const ISO_STEPS As String = "100,125,160,200,250,320,400,500,640,800,1000,1250,1600"

' HTTP response codes
Private Const HTTP_OK          As Integer = 200
Private Const HTTP_BAD_REQUEST As Integer = 400
Private Const HTTP_DEVICE_BUSY As Integer = 503

' ============================================================
' Core HTTP helpers
' ============================================================

Public Function CameraGet(ByVal endpoint As String) As String
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", CAMERA_IP() & endpoint, False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send
    Select Case http.Status
        Case HTTP_OK
            CameraGet = http.ResponseText
        Case HTTP_DEVICE_BUSY
            LogEvent "CAMERA", "GET " & endpoint & " - Device busy (503)"
            CameraGet = ""
        Case Else
            LogEvent "CAMERA", "GET " & endpoint & " - HTTP " & http.Status
            CameraGet = ""
    End Select
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "GET " & endpoint & " - Connection failed: " & Err.Description
    CameraGet = ""
End Function

Public Function CameraPut(ByVal endpoint As String, ByVal jsonBody As String) As Boolean
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "PUT", CAMERA_IP() & endpoint, False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send jsonBody
    Select Case http.Status
        Case HTTP_OK
            CameraPut = True
        Case HTTP_DEVICE_BUSY
            LogEvent "CAMERA", "PUT " & endpoint & " - Device busy, retrying"
            Application.Wait Now + TimeValue("00:00:03")
            http.Open "PUT", CAMERA_IP() & endpoint, False
            http.SetRequestHeader "Content-Type", "application/json"
            http.Send jsonBody
            CameraPut = (http.Status = HTTP_OK)
            If Not CameraPut Then LogEvent "CAMERA", "PUT retry failed: " & http.Status
        Case HTTP_BAD_REQUEST
            LogEvent "CAMERA", "PUT " & endpoint & " - Invalid param. Body: " & jsonBody
            CameraPut = False
        Case Else
            LogEvent "CAMERA", "PUT " & endpoint & " - HTTP " & http.Status
            CameraPut = False
    End Select
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "PUT " & endpoint & " - Connection failed: " & Err.Description
    CameraPut = False
End Function

Public Function CameraPost(ByVal endpoint As String, ByVal jsonBody As String) As Boolean
    On Error GoTo ErrHandler
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "POST", CAMERA_IP() & endpoint, False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send jsonBody
    Select Case http.Status
        Case HTTP_OK
            CameraPost = True
        Case HTTP_DEVICE_BUSY
            LogEvent "CAMERA", "POST " & endpoint & " - Device busy (503)"
            CameraPost = False
        Case Else
            LogEvent "CAMERA", "POST " & endpoint & " - HTTP " & http.Status
            CameraPost = False
    End Select
    Set http = Nothing
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "POST " & endpoint & " - Connection failed: " & Err.Description
    CameraPost = False
End Function

' ============================================================
' Camera setting functions
' ============================================================

Public Function SetShootingMode(ByVal myMode As String) As Boolean
    SetShootingMode = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/shootingmode", _
                                "{""value"":""" & myMode & """}")
    If SetShootingMode Then
        Range("dataCurrentMode").Value = myMode
        LogEvent "CAMERA", "Mode set to " & myMode
    End If
End Function

Public Function SetAperture(ByVal myAv As String) As Boolean
    SetAperture = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/av", _
                            "{""value"":""" & myAv & """}")
    If SetAperture Then
        Range("dataCurrentAv").Value = myAv
        LogEvent "CAMERA", "Av set to " & myAv
        UpdateArduinoDisplay
    End If
End Function

Public Function SetShutterSpeed(ByVal myTv As String) As Boolean
    SetShutterSpeed = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/tv", _
                                "{""value"":""" & myTv & """}")
    If SetShutterSpeed Then
        Range("dataCurrentTv").Value = myTv
        LogEvent "CAMERA", "Tv set to " & myTv
        UpdateArduinoDisplay
    End If
End Function

Public Function SetISO(ByVal myISO As String) As Boolean
    SetISO = CameraPut("/ccapi/" & CCAPI_VER & "/shooting/settings/iso", _
                       "{""value"":""" & myISO & """}")
    If SetISO Then
        Range("dataCurrentISO").Value = myISO
        LogEvent "CAMERA", "ISO set to " & myISO
        UpdateArduinoDisplay
    End If
End Function

Public Function TakePhoto() As Boolean
    TakePhoto = CameraPost("/ccapi/" & CCAPI_VER & "/shooting/control/shutterbutton", _
                           "{""af"":false}")
    If TakePhoto Then
        Range("dataShotCount").Value = Range("dataShotCount").Value + 1
        LogEvent "CAMERA", "Photo taken - shot " & Range("dataShotCount").Value
    End If
End Function

Public Function GetCurrentISO() As String
    Dim response As String
    response = CameraGet("/ccapi/" & CCAPI_VER & "/shooting/settings/iso")
    If response = "" Then GetCurrentISO = "" : Exit Function
    GetCurrentISO = ParseJsonField(response, "value")
End Function

Public Function GetCurrentTv() As String
    Dim response As String
    response = CameraGet("/ccapi/" & CCAPI_VER & "/shooting/settings/tv")
    If response = "" Then GetCurrentTv = "" : Exit Function
    GetCurrentTv = ParseJsonField(response, "value")
End Function

Public Function GetISOAbility() As String
    Dim response As String
    response = CameraGet("/ccapi/" & CCAPI_VER & "/shooting/settings/iso")
    If response = "" Then GetISOAbility = "" : Exit Function
    GetISOAbility = ParseJsonField(response, "ability")
End Function

' ============================================================
' Phase 2b - Luminance-based ISO adjustment
' ============================================================

Public Function AdjustExposureByLuminance() As String
    Const TARGET_LOW  As Integer = 95
    Const TARGET_HIGH As Integer = 135

    Dim lum As Integer
    lum = GetLastThumbnailLuminance()
    If lum >= 0 Then Range("dataLuminance").Value = lum
    LogEvent "LUMINANCE", "lum=" & lum & " ISO=" & Range("dataCurrentISO").Value & _
             " Tv=" & Range("dataCurrentTv").Value

    If lum < 0 Then
        Range("dataCommCameraCheck").Value = "Lum error " & Format(Now(), "HH:nn:ss")
        AdjustExposureByLuminance = ""
        Exit Function
    End If

    Dim isoSteps() As String
    isoSteps = Split(ISO_STEPS, ",")
    Dim currentISO As String
    currentISO = Range("dataCurrentISO").Value

    Dim idx As Integer : idx = -1
    Dim i As Integer
    For i = 0 To UBound(isoSteps)
        If isoSteps(i) = currentISO Then idx = i : Exit For
    Next i

    If idx < 0 Then
        LogEvent "CAMERA", "AdjustExposure: unknown ISO " & currentISO
        AdjustExposureByLuminance = ""
        Exit Function
    End If

    Dim newISO As String : newISO = ""
    If lum < TARGET_LOW And idx < UBound(isoSteps) Then
        newISO = isoSteps(idx + 1)
        SetISO newISO
        Range("dataCommCameraCheck").Value = "Lum:" & lum & " ISO up->" & newISO & " " & Format(Now(), "HH:nn:ss")
    ElseIf lum > TARGET_HIGH And idx > 0 Then
        newISO = isoSteps(idx - 1)
        SetISO newISO
        Range("dataCommCameraCheck").Value = "Lum:" & lum & " ISO dn->" & newISO & " " & Format(Now(), "HH:nn:ss")
    Else
        Range("dataCommCameraCheck").Value = "Lum:" & lum & " ISO OK " & Format(Now(), "HH:nn:ss")
    End If
    AdjustExposureByLuminance = newISO
End Function

' ============================================================
' Thumbnail luminance
' ============================================================

Public Function GetLastThumbnailLuminance() As Integer
    On Error GoTo ErrHandler
    Dim dirResponse As String
    dirResponse = CameraGet("/ccapi/ver110/devicestatus/currentdirectory")
    If dirResponse = "" Then GetLastThumbnailLuminance = -1 : Exit Function

    Dim myPath As String
    Dim startPos As Long, endPos As Long
    startPos = InStr(dirResponse, """path"":""") + 8
    endPos = InStr(startPos, dirResponse, """}")
    myPath = Replace(Mid(dirResponse, startPos, endPos - startPos + 1), "\\", "/")
    myPath = Replace(myPath, "\", "/")

    Dim pageResponse As String
    pageResponse = CameraGet(myPath & "?type=jpeg&kind=number")
    If pageResponse = "" Then GetLastThumbnailLuminance = -1 : Exit Function
    startPos = InStr(pageResponse, """pagenumber"":") + 13
    endPos = InStr(startPos, pageResponse, "}")
    Dim pageNum As String
    pageNum = Trim(Mid(pageResponse, startPos, endPos - startPos))

    Dim listResponse As String
    listResponse = CameraGet(myPath & "?type=jpeg&kind=list&page=" & pageNum)
    If listResponse = "" Then GetLastThumbnailLuminance = -1 : Exit Function

    Dim lastFile As String : lastFile = ""
    Dim lines() As String
    lines = Split(listResponse, Chr(10))
    Dim j As Integer
    For j = UBound(lines) To 0 Step -1
        Dim line As String : line = Trim(lines(j))
        If InStr(UCase(line), ".JPG") > 0 Then
            Dim fnEnd As Long : fnEnd = InStr(UCase(line), ".JPG")
            Dim fnStart As Long : fnStart = InStrRev(line, "/") + 1
            If fnStart = 0 Then fnStart = 1
            lastFile = Mid(line, fnStart, fnEnd - fnStart + 4)
            Exit For
        End If
    Next j

    If lastFile = "" Then
        LogEvent "CAMERA", "GetLastThumbnail: no JPG found"
        GetLastThumbnailLuminance = -1
        Exit Function
    End If

    Dim savePath As String
    savePath = Environ("USERPROFILE") & "\Downloads\LastThumb.jpg"
    Dim thumbURL As String
    thumbURL = CAMERA_IP() & myPath & "/" & lastFile & "?kind=thumbnail"
    If Not DownloadBinary(thumbURL, savePath) Then
        GetLastThumbnailLuminance = -1
        Exit Function
    End If
    GetLastThumbnailLuminance = CalcLuminance(savePath)
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "GetLastThumbnailLuminance error: " & Err.Description
    GetLastThumbnailLuminance = -1
End Function

Public Function DownloadBinary(ByVal url As String, ByVal savePath As String) As Boolean
    On Error GoTo ErrHandler
    Dim http As Object, stream As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", url, False
    http.Send
    If http.Status = HTTP_OK Then
        Set stream = CreateObject("ADODB.Stream")
        stream.Open
        stream.Type = 1
        stream.Write http.responseBody
        stream.SaveToFile savePath, 2
        stream.Close
        Set stream = Nothing
        DownloadBinary = True
    Else
        LogEvent "CAMERA", "DownloadBinary HTTP " & http.Status
        DownloadBinary = False
    End If
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "DownloadBinary error: " & Err.Description
    DownloadBinary = False
End Function

Public Function CalcLuminance(ByVal jpegPath As String) As Integer
    On Error GoTo ErrHandler
    Dim scriptPath As String
    scriptPath = Environ("USERPROFILE") & "\Documents\luminance.py"
    If Dir(scriptPath) = "" Then
        LogEvent "CAMERA", "luminance.py not found at " & scriptPath
        CalcLuminance = -1
        Exit Function
    End If
    Dim shell As Object
    Set shell = CreateObject("WScript.Shell")
    Dim exec As Object
    Set exec = shell.Exec("python """ & scriptPath & """ """ & jpegPath & """")
    Dim timeout As Long : timeout = 0
    Do While exec.Status = 0 And timeout < 100
        Application.Wait Now + TimeValue("00:00:00") + 0.0001
        timeout = timeout + 1
        DoEvents
    Loop
    If exec.Status = 0 Then
        LogEvent "CAMERA", "CalcLuminance: Python timeout"
        CalcLuminance = -1
        Exit Function
    End If
    Dim result As String
    result = Trim(exec.StdOut.ReadAll())
    CalcLuminance = IIf(IsNumeric(result), CInt(result), -1)
    Exit Function
ErrHandler:
    LogEvent "CAMERA", "CalcLuminance error: " & Err.Description
    CalcLuminance = -1
End Function

' ============================================================
' Arduino communication
' ============================================================

Public Sub SendHeartbeat()
    On Error Resume Next
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/heartbeat?msg=" & Format(Now(), "HH:nn:ss"), False
    http.Send
    Set http = Nothing
End Sub

Public Sub UpdateArduinoDisplay()
    On Error Resume Next
    Dim msg As String
    msg = "M|" & Range("dataCurrentAv").Value & "|" & _
          Range("dataCurrentTv").Value & "|ISO" & Range("dataCurrentISO").Value
    msg = Replace(msg, "|", "%7C")
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", ARDUINO_IP() & "/cameramsg?msg=" & msg, False
    http.Send
    Set http = Nothing
End Sub

' ============================================================
' Camera initialisation
' ============================================================

Public Sub InitCamera()
    LogEvent "CAMERA", "=== Camera initialisation ==="
    If Not SetShootingMode("m") Then
        MsgBox "Failed to set Manual mode - check camera is on and connected", vbExclamation
        Exit Sub
    End If
    If Not SetAperture("f1.8") Then
        MsgBox "Failed to set aperture f/1.8", vbExclamation
        Exit Sub
    End If
    If Not SetISO("100") Then
        MsgBox "Failed to set ISO 100", vbExclamation
        Exit Sub
    End If
    If Not SetShutterSpeed("1/5000") Then
        MsgBox "Failed to set shutter 1/5000", vbExclamation
        Exit Sub
    End If
    Range("dataShotCount").Value = 0
    LogEvent "CAMERA", "Camera initialised: M f1.8 ISO100 1/5000"
    Range("dataCommCameraCheck").Value = "Init OK " & Format(Now(), "HH:nn:ss")
End Sub
