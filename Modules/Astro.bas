Attribute VB_Name = "Astro"
' ============================================================
' HyperLapse Cart — Astronomical Calculations Module
'
' Calculates:
'   1. Sun azimuth and altitude at any time/location
'      → Used for sunset/sunrise gimbal pointing direction
'
'   2. Milky Way galactic centre azimuth and altitude
'      → Used for gimbal tracking during Phase 3
'
' All calculations use standard spherical astronomy formulae.
' Location read from Settings sheet named ranges:
'   dataLatitude   (decimal degrees, negative = south)
'   dataLongitude  (decimal degrees, negative = west)
'   dataUTCOffset  (hours)
'
' Gimbal yaw is relative to cart heading — operator must set
' dataCartHeading (compass bearing the cart is pointing) so
' world azimuth can be converted to gimbal-relative yaw.
'
' References:
'   Jean Meeus, "Astronomical Algorithms" 2nd ed.
'   Galactic centre: RA 17h 45m 40s, Dec -29° 00' 28"
' ============================================================

Option Explicit

' ── Galactic centre coordinates (J2000) ──────────────────────
Private Const GC_RA_DEG   As Double = 266.4167    ' 17h 45m 40s in degrees
Private Const GC_DEC_DEG  As Double = -29.0078    ' -29° 00' 28"

' ── Constants ────────────────────────────────────────────────
Private Const PI     As Double = 3.14159265358979
Private Const DEG2RAD As Double = PI / 180#
Private Const RAD2DEG As Double = 180# / PI

' ============================================================
' Public interface
' ============================================================

' Get sun azimuth (degrees from North, clockwise) at current time
Public Function GetSunAzimuth() As Double
    Dim az As Double, alt As Double
    GetSunPosition Now, az, alt
    GetSunAzimuth = az
End Function

' Get sun altitude (degrees above horizon) at current time
Public Function GetSunAltitude() As Double
    Dim az As Double, alt As Double
    GetSunPosition Now, az, alt
    GetSunAltitude = alt
End Function

' Get Milky Way galactic centre azimuth at current time
Public Function GetGCazimuth() As Double
    Dim az As Double, alt As Double
    GetGCPosition Now, az, alt
    GetGCazimuth = az
End Function

' Get Milky Way galactic centre altitude at current time
Public Function GetGCaltitude() As Double
    Dim az As Double, alt As Double
    GetGCPosition Now, az, alt
    GetGCaltitude = alt
End Function

' Convert world azimuth to gimbal yaw (relative to cart heading)
' cartHeading: compass bearing the cart is pointing (0-360, North=0)
' worldAzimuth: target azimuth in world frame
' Returns gimbal yaw in range -180 to +180
Public Function AzimuthToGimbalYaw(ByVal worldAzimuth As Double, _
                                    ByVal cartHeading As Double) As Double
    Dim yaw As Double
    yaw = worldAzimuth - cartHeading
    ' Normalise to -180..+180
    Do While yaw > 180
        yaw = yaw - 360
    Loop
    Do While yaw < -180
        yaw = yaw + 360
    Loop
    AzimuthToGimbalYaw = yaw
End Function

' Calculate gimbal yaw and pitch to point at sun at given time
' cartHeading: compass bearing the cart faces (degrees)
' Returns True if sun is above horizon
Public Function GetSunGimbalAngles(ByVal atTime As Date, _
                                    ByVal cartHeading As Double, _
                                    ByRef gimbalYaw As Double, _
                                    ByRef gimbalPitch As Double) As Boolean
    Dim az As Double, alt As Double
    GetSunPosition atTime, az, alt
    
    gimbalYaw = AzimuthToGimbalYaw(az, cartHeading)
    gimbalPitch = alt   ' pitch = altitude above horizon
    
    GetSunGimbalAngles = (alt > -5)  ' True if sun within 5° of horizon
    
    LogEvent "ASTRO", "Sun at " & Format(atTime, "HH:nn:ss") & _
             ": az=" & Format(az, "0.0") & Chr(176) & _
             " alt=" & Format(alt, "0.0") & Chr(176) & _
             " → yaw=" & Format(gimbalYaw, "0.0") & Chr(176) & _
             " pitch=" & Format(gimbalPitch, "0.0") & Chr(176)
End Function

' Calculate gimbal yaw and pitch to point at Milky Way galactic centre
' cartHeading: compass bearing the cart faces (degrees)
' Returns True if galactic centre is above horizon
Public Function GetGCGimbalAngles(ByVal atTime As Date, _
                                   ByVal cartHeading As Double, _
                                   ByRef gimbalYaw As Double, _
                                   ByRef gimbalPitch As Double) As Boolean
    Dim az As Double, alt As Double
    GetGCPosition atTime, az, alt
    
    gimbalYaw = AzimuthToGimbalYaw(az, cartHeading)
    gimbalPitch = alt
    
    GetGCGimbalAngles = (alt > 0)  ' True if above horizon
    
    LogEvent "ASTRO", "GC at " & Format(atTime, "HH:nn:ss") & _
             ": az=" & Format(az, "0.0") & Chr(176) & _
             " alt=" & Format(alt, "0.0") & Chr(176) & _
             " → yaw=" & Format(gimbalYaw, "0.0") & Chr(176) & _
             " pitch=" & Format(gimbalPitch, "0.0") & Chr(176)
End Function

' Generate a table of Milky Way galactic centre positions
' for the night, written to a new sheet or range for planning
Public Sub GenerateGCTable()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = Sheets("AstroTable")
    If ws Is Nothing Then
        Set ws = Sheets.Add
        ws.Name = "AstroTable"
    End If
    On Error GoTo 0
    
    ws.Cells.Clear
    ws.Cells(1, 1).value = "Time"
    ws.Cells(1, 2).value = "GC Az (°)"
    ws.Cells(1, 3).value = "GC Alt (°)"
    ws.Cells(1, 4).value = "Sun Az (°)"
    ws.Cells(1, 5).value = "Sun Alt (°)"
    ws.Cells(1, 6).value = "GC above horizon"
    
    Dim cartHeading As Double
    cartHeading = Sheets("Settings").Range("dataCartHeading").value
    
    ' Table from 4pm today to 8am tomorrow, every 15 minutes
    Dim startTime As Date
    startTime = CDate(Int(Now()) + TimeValue("16:00:00"))
    
    Dim row As Integer
    row = 2
    Dim t As Date
    For t = startTime To startTime + 1 Step (15 / 1440)   ' 15 minute steps
        Dim gcAz As Double, gcAlt As Double
        Dim sunAz As Double, sunAlt As Double
        Dim gcYaw As Double, gcPitch As Double
        
        GetGCPosition t, gcAz, gcAlt
        GetSunPosition t, sunAz, sunAlt
        
        ws.Cells(row, 1).value = Format(t, "HH:nn")
        ws.Cells(row, 2).value = Round(gcAz, 1)
        ws.Cells(row, 3).value = Round(gcAlt, 1)
        ws.Cells(row, 4).value = Round(sunAz, 1)
        ws.Cells(row, 5).value = Round(sunAlt, 1)
        ws.Cells(row, 6).value = IIf(gcAlt > 0, "YES", "no")
        row = row + 1
    Next t
    
    ' Format
    ws.Columns(1).NumberFormat = "hh:mm"
    ws.Columns("A:F").AutoFit
    
    LogEvent "ASTRO", "GC table generated — " & (row - 2) & " rows"
    MsgBox "Astro table generated on AstroTable sheet.", vbInformation
End Sub

' ============================================================
' Sun position calculation
' Based on Jean Meeus "Astronomical Algorithms"
' Accurate to within ~1° for dates 2000-2100
' ============================================================

Private Sub GetSunPosition(ByVal atTime As Date, _
                            ByRef azimuth As Double, _
                            ByRef altitude As Double)
    
    Dim lat As Double
    Dim lng As Double
    Dim utcOffset As Double
    lat = Sheets("Settings").Range("dataLatitude").value
    lng = Sheets("Settings").Range("dataLongitude").value
    utcOffset = Sheets("Settings").Range("dataUTCOffset").value
    
    ' Convert local time to UTC
    Dim utcTime As Date
    utcTime = atTime - (utcOffset / 24)
    
    ' Julian Day Number
    Dim jd As Double
    jd = DateToJulian(utcTime)
    
    ' Days since J2000.0
    Dim n As Double
    n = jd - 2451545#
    
    ' Mean longitude (degrees)
    Dim L As Double
    L = NormalizeDeg(280.46 + 0.9856474 * n)
    
    ' Mean anomaly (degrees)
    Dim g As Double
    g = NormalizeDeg(357.528 + 0.9856003 * n)
    
    ' Ecliptic longitude (degrees)
    Dim lambda As Double
    lambda = NormalizeDeg(L + 1.915 * Sin(g * DEG2RAD) + 0.02 * Sin(2 * g * DEG2RAD))
    
    ' Obliquity of ecliptic
    Dim epsilon As Double
    epsilon = 23.439 - 0.0000004 * n
    
    ' Right ascension and declination
    Dim ra As Double     ' degrees
    Dim dec As Double    ' degrees
    ra = RAD2DEG * Atn2(Cos(epsilon * DEG2RAD) * Sin(lambda * DEG2RAD), _
                         Cos(lambda * DEG2RAD))
    ra = NormalizeDeg(ra)
    dec = RAD2DEG * Asin(Sin(epsilon * DEG2RAD) * Sin(lambda * DEG2RAD))
    
    ' Greenwich Mean Sidereal Time (degrees)
    Dim gmst As Double
    gmst = NormalizeDeg(280.46061837 + 360.98564736629 * n)
    
    ' Local Sidereal Time
    Dim lst As Double
    lst = NormalizeDeg(gmst + lng)
    
    ' Hour angle
    Dim ha As Double
    ha = NormalizeDeg(lst - ra)
    ' Adjust to -180..+180
    If ha > 180 Then ha = ha - 360
    
    ' Altitude and azimuth
    RADecToAltAz ha, dec, lat, altitude, azimuth
End Sub

' ============================================================
' Galactic centre position calculation
' ============================================================

Private Sub GetGCPosition(ByVal atTime As Date, _
                           ByRef azimuth As Double, _
                           ByRef altitude As Double)
    
    Dim lat As Double
    Dim lng As Double
    Dim utcOffset As Double
    lat = Sheets("Settings").Range("dataLatitude").value
    lng = Sheets("Settings").Range("dataLongitude").value
    utcOffset = Sheets("Settings").Range("dataUTCOffset").value
    
    ' Convert local time to UTC
    Dim utcTime As Date
    utcTime = atTime - (utcOffset / 24)
    
    ' Julian Day Number
    Dim jd As Double
    jd = DateToJulian(utcTime)
    
    ' Days since J2000.0
    Dim n As Double
    n = jd - 2451545#
    
    ' Greenwich Mean Sidereal Time (degrees)
    Dim gmst As Double
    gmst = NormalizeDeg(280.46061837 + 360.98564736629 * n)
    
    ' Local Sidereal Time
    Dim lst As Double
    lst = NormalizeDeg(gmst + lng)
    
    ' Hour angle of galactic centre
    Dim ha As Double
    ha = NormalizeDeg(lst - GC_RA_DEG)
    If ha > 180 Then ha = ha - 360
    
    ' Convert to altitude/azimuth
    RADecToAltAz ha, GC_DEC_DEG, lat, altitude, azimuth
End Sub

' ============================================================
' Coordinate conversion helpers
' ============================================================

' Convert RA/Dec (hour angle + declination) to Alt/Az
Private Sub RADecToAltAz(ByVal ha As Double, _
                          ByVal dec As Double, _
                          ByVal lat As Double, _
                          ByRef alt As Double, _
                          ByRef az As Double)
    Dim haRad  As Double
    Dim decRad As Double
    Dim latRad As Double
    haRad = ha * DEG2RAD
    decRad = dec * DEG2RAD
    latRad = lat * DEG2RAD
    
    ' Altitude
    Dim sinAlt As Double
    sinAlt = Sin(decRad) * Sin(latRad) + Cos(decRad) * Cos(latRad) * Cos(haRad)
    alt = RAD2DEG * Asin(sinAlt)
    
    ' Azimuth (from North, clockwise)
    Dim cosAz As Double
    cosAz = (Sin(decRad) - Sin(alt * DEG2RAD) * Sin(latRad)) / _
            (Cos(alt * DEG2RAD) * Cos(latRad))
    ' Clamp for floating point errors
    If cosAz > 1 Then cosAz = 1
    If cosAz < -1 Then cosAz = -1
    az = RAD2DEG * Acos(cosAz)
    
    ' Adjust quadrant based on hour angle
    If Sin(haRad) > 0 Then az = 360 - az
End Sub

' Convert Excel date/time to Julian Day Number
Private Function DateToJulian(ByVal dt As Date) As Double
    Dim y As Integer, M As Integer, D As Integer
    Dim hr As Double, mn As Double, sc As Double
    y = Year(dt)
    M = Month(dt)
    D = Day(dt)
    hr = Hour(dt)
    mn = Minute(dt)
    sc = Second(dt)
    
    If M <= 2 Then
        y = y - 1
        M = M + 12
    End If
    
    Dim A As Long, B As Long
    A = Int(y / 100)
    B = 2 - A + Int(A / 4)
    
    DateToJulian = Int(365.25 * (y + 4716)) + _
                   Int(30.6001 * (M + 1)) + _
                   D + B - 1524.5 + _
                   (hr + mn / 60# + sc / 3600#) / 24#
End Function

' Normalise angle to 0-360 range
Private Function NormalizeDeg(ByVal deg As Double) As Double
    NormalizeDeg = deg - 360# * Int(deg / 360#)
    If NormalizeDeg < 0 Then NormalizeDeg = NormalizeDeg + 360#
End Function

' VBA Asin — not built in
Private Function Asin(ByVal x As Double) As Double
    If Abs(x) = 1 Then
        Asin = PI / 2 * Sgn(x)
    Else
        Asin = Atn(x / Sqr(1 - x * x))
    End If
End Function

' VBA Acos — not built in
Private Function Acos(ByVal x As Double) As Double
    If Abs(x) = 1 Then
        Acos = (1 - x) * PI / 2
    Else
        Acos = PI / 2 - Atn(x / Sqr(1 - x * x))
    End If
End Function

' VBA Atan2 — not built in
Private Function Atn2(ByVal y As Double, ByVal x As Double) As Double
    If x > 0 Then
        Atn2 = Atn(y / x)
    ElseIf x < 0 And y >= 0 Then
        Atn2 = Atn(y / x) + PI
    ElseIf x < 0 And y < 0 Then
        Atn2 = Atn(y / x) - PI
    ElseIf x = 0 And y > 0 Then
        Atn2 = PI / 2
    ElseIf x = 0 And y < 0 Then
        Atn2 = -PI / 2
    Else
        Atn2 = 0
    End If
End Function
