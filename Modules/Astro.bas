Attribute VB_Name = "Astro"
' ============================================================
' HyperLapse Cart -- Astronomical Calculations Module
'
' Calculates:
'   1. Sun azimuth and altitude at any time/location
'      -> Used for sunset/sunrise gimbal pointing direction
'
'   2. Milky Way galactic centre azimuth and altitude
'      -> Used for gimbal tracking during Phase 3
'
' All calculations use standard spherical astronomy formulae.
' Location read from Settings sheet named ranges:
'   dataLatitude   (decimal degrees, negative = south)
'   dataLongitude  (decimal degrees, negative = west)
'   dataUTCOffset  (hours)
'
' Gimbal yaw is relative to cart heading -- operator must set
' dataCartHeading (compass bearing the cart is pointing) so
' world azimuth can be converted to gimbal-relative yaw.
'
' References:
'   Jean Meeus, "Astronomical Algorithms" 2nd ed.
'   Galactic centre: RA 17h 45m 40s, Dec -29  00' 28"
' ============================================================

Option Explicit

'                  Galactic centre coordinates (J2000)
Private Const GC_RA_DEG   As Double = 266.4167    ' 17h 45m 40s in degrees
Private Const GC_DEC_DEG  As Double = -29.0078    ' -29  00' 28"

'                  Constants
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
    
    GetSunGimbalAngles = (alt > -5)  ' True if sun within 5  of horizon
    
    LogEvent "ASTRO", "Sun at " & Format(atTime, "HH:nn:ss") & _
             ": az=" & Format(az, "0.0") & Chr(176) & _
             " alt=" & Format(alt, "0.0") & Chr(176) & _
             " -> yaw=" & Format(gimbalYaw, "0.0") & Chr(176) & _
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
             " -> yaw=" & Format(gimbalYaw, "0.0") & Chr(176) & _
             " pitch=" & Format(gimbalPitch, "0.0") & Chr(176)
End Function

' ============================================================
' GC Arch gimbal angles (rise / set). Mirror of GetGCGimbalAngles but
' for the arch perpendicular bearing. The arch is a horizon bearing
' (alt 0), so gimbalPitch comes back 0 and the held pitch is supplied
' by Rp on the Track-yaw GP - NOT by this function. Returns True
' whenever the bearing is defined (always), unlike the body evaluators
' which gate on alt>0, because the arch yaw aim is valid all night even
' though its nominal altitude is 0.
Public Function GetGCArchRiseGimbalAngles(ByVal atTime As Date, _
                                           ByVal cartHeading As Double, _
                                           ByRef gimbalYaw As Double, _
                                           ByRef gimbalPitch As Double) As Boolean
    Dim az As Double, alt As Double
    GetGCArchRiseAzAltAtTime atTime, az, alt
    gimbalYaw = AzimuthToGimbalYaw(az, cartHeading)
    gimbalPitch = alt                          ' 0; held pitch is Rp
    GetGCArchRiseGimbalAngles = True
End Function

Public Function GetGCArchSetGimbalAngles(ByVal atTime As Date, _
                                          ByVal cartHeading As Double, _
                                          ByRef gimbalYaw As Double, _
                                          ByRef gimbalPitch As Double) As Boolean
    Dim az As Double, alt As Double
    GetGCArchSetAzAltAtTime atTime, az, alt
    gimbalYaw = AzimuthToGimbalYaw(az, cartHeading)
    gimbalPitch = alt
    GetGCArchSetGimbalAngles = True
End Function

' ============================================================
' Day 17 additions -- Workfront #50 push astro
'
' Public wrappers around the private *Position subs. Use these
' when EARTH-frame azimuth + altitude are wanted (e.g. pushing
' astro positions to cart, which applies its own cart-heading
' correction at command time).
'
' For cart-frame yaw (cart-heading already subtracted), use the
' existing Get*GimbalAngles functions instead.
' ============================================================

' Get sun azimuth + altitude (earth frame) at any time.
Public Sub GetSunAzAltAtTime(ByVal atTime As Date, _
                              ByRef azimuth As Double, _
                              ByRef altitude As Double)
    GetSunPosition atTime, azimuth, altitude
End Sub

' Get galactic centre azimuth + altitude (earth frame) at any time.
Public Sub GetGCAzAltAtTime(ByVal atTime As Date, _
                             ByRef azimuth As Double, _
                             ByRef altitude As Double)
    GetGCPosition atTime, azimuth, altitude
End Sub

' ============================================================
' GC ARCH - virtual point: the perpendicular to the line joining
' the two horizon "feet" of the Milky Way band (the band modelled
' as the galactic equator, b=0, a great circle). That bearing
' equals the band APEX azimuth and follows the arch continuously
' (no whip - it is a horizon-feet bearing, not an overhead point).
' Altitude returned 0 (feet on the horizon).
'
' rise / set both return this SAME continuous bearing - they do NOT
' differ by hemisphere. They differ only by the time window the
' operator authors:
'  - "rise" -> authored BEFORE the overhead pass (apex climbing).
'  - "set"  -> authored AFTER the overhead pass (apex descending).
' The 180 deg difference between the two windows is the real fact
' that the arch went over the top; an operator Move bridges that
' overhead gap. The `side` string is carried for logging/clarity
' only - the geometry is identical (apex-nearest bearing).
'
' The rise/set targets are authored as Track-yaw GPs at a fixed
' foreground pitch (Rp = offP on the cart); the held pitch comes
' from Rp, not from this solver (which returns altitude 0).
' ============================================================
Public Sub GetGCArchAzAltAtTime(ByVal atTime As Date, _
                                 ByRef azimuth As Double, _
                                 ByRef altitude As Double)
    GetGCArchPosition atTime, "apex", azimuth, altitude
End Sub

Public Sub GetGCArchRiseAzAltAtTime(ByVal atTime As Date, _
                                     ByRef azimuth As Double, _
                                     ByRef altitude As Double)
    GetGCArchPosition atTime, "rise", azimuth, altitude
End Sub

Public Sub GetGCArchSetAzAltAtTime(ByVal atTime As Date, _
                                    ByRef azimuth As Double, _
                                    ByRef altitude As Double)
    GetGCArchPosition atTime, "set", azimuth, altitude
End Sub

' Generate a table of Milky Way galactic centre positions
' for the night, written to a new sheet or range for planning
'Public Sub GenerateGCTable()" to its "End Sub", and paste this over it.
'
' Change vs the original: adds Moon Az (col G), Moon Alt (col H), and
' Moon above horizon (col I), filled from the private GetMoonPosition
' exactly as GC/Sun are filled. AutoFit range widened A:F -> A:I.
' Everything else is unchanged.
' =====================================================================

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
    ws.Cells(1, 2).value = "GC Az (" & Chr(176) & ")"
    ws.Cells(1, 3).value = "GC Alt (" & Chr(176) & ")"
    ws.Cells(1, 4).value = "Sun Az (" & Chr(176) & ")"
    ws.Cells(1, 5).value = "Sun Alt (" & Chr(176) & ")"
    ws.Cells(1, 6).value = "GC above horizon"
    ws.Cells(1, 7).value = "Moon Az (" & Chr(176) & ")"
    ws.Cells(1, 8).value = "Moon Alt (" & Chr(176) & ")"
    ws.Cells(1, 9).value = "Moon above horizon"

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
        Dim moonAz As Double, moonAlt As Double

        GetGCPosition t, gcAz, gcAlt
        GetSunPosition t, sunAz, sunAlt
        GetMoonPosition t, moonAz, moonAlt

        ws.Cells(row, 1).value = Format(t, "HH:nn")
        ws.Cells(row, 2).value = Round(gcAz, 1)
        ws.Cells(row, 3).value = Round(gcAlt, 1)
        ws.Cells(row, 4).value = Round(sunAz, 1)
        ws.Cells(row, 5).value = Round(sunAlt, 1)
        ws.Cells(row, 6).value = IIf(gcAlt > 0, "YES", "no")
        ws.Cells(row, 7).value = Round(moonAz, 1)
        ws.Cells(row, 8).value = Round(moonAlt, 1)
        ws.Cells(row, 9).value = IIf(moonAlt > 0, "YES", "no")
        row = row + 1
    Next t

    ' Format
    ws.Columns(1).NumberFormat = "hh:mm"
    ws.Columns("A:I").AutoFit

    LogEvent "ASTRO", "GC table generated -- " & (row - 2) & " rows"
    MsgBox "Astro table generated on AstroTable sheet.", vbInformation
End Sub
' ============================================================
' Sun position calculation
' Based on Jean Meeus "Astronomical Algorithms"
' Accurate to within ~1  for dates 2000-2100
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
' GC Arch position - bisector azimuth of the two horizon feet
' of the galactic-equator great circle (b=0).
' Method (matches the validated prototype):
'   1. For LST at this time, sample the b=0 circle (galactic long
'      0..360) -> equatorial (gal->eq rotation) -> alt/az.
'   2. Find the two horizon crossings (alt sign change) -> feet az.
'   3. Track the max-alt sample -> apex az (the arch side).
'   4. Bisect the two feet (circular, short-way midpoint); of the
'      two candidates 180 apart, return the one nearer the apex az.
' azimuth = arch bisector bearing; altitude = 0 (feet on horizon).
' If fewer than two feet are above-horizon transitions (band fully
' up or fully down in the sample), fall back to the apex azimuth.
' ============================================================
Private Sub GetGCArchPosition(ByVal atTime As Date, _
                               ByVal side As String, _
                               ByRef azimuth As Double, _
                               ByRef altitude As Double)

    ' The perpendicular to the line joining the band's two horizon feet is,
    ' exactly, the AZIMUTH OF THE GALACTIC POLE (the pole of the b=0 great
    ' circle). So the arch bearing = the galactic north pole's azimuth, computed
    ' directly - no feet scan, no candidate pick, no carry-state, and (because
    ' the pole never goes near the zenith from this latitude, max alt ~27 deg)
    ' NO whip and NO flip: it is smooth across the whole GC rise->set window.
    '   side "rise" -> galactic NORTH pole azimuth (the east-side one at GC rise)
    '   side "set"  -> + 180 deg (= galactic SOUTH pole azimuth)
    ' Both are defined and continuous the entire night; the operator chooses when
    ' to Move from rise to set purely for composition. Altitude returned 0 (the
    ' tracked point is a horizon bearing; the held pitch comes from Rp / offP on
    ' the Track-yaw GP, not from this solver).
    Const GNP_RA  As Double = 192.85948      ' galactic north pole RA  (J2000)
    Const GNP_DEC As Double = 27.12825       ' galactic north pole Dec (J2000)

    Dim lat As Double, lng As Double, utcOffset As Double
    lat = Sheets("Settings").Range("dataLatitude").value
    lng = Sheets("Settings").Range("dataLongitude").value
    utcOffset = Sheets("Settings").Range("dataUTCOffset").value

    Dim utcTime As Date
    utcTime = atTime - (utcOffset / 24)
    Dim jd As Double
    jd = DateToJulian(utcTime)
    Dim nDays As Double
    nDays = jd - 2451545#
    Dim gmst As Double
    gmst = NormalizeDeg(280.46061837 + 360.98564736629 * nDays)
    Dim lst As Double
    lst = NormalizeDeg(gmst + lng)

    Dim ha As Double
    ha = NormalizeDeg(lst - GNP_RA)
    If ha > 180 Then ha = ha - 360

    Dim poleAlt As Double, poleAz As Double
    RADecToAltAz ha, GNP_DEC, lat, poleAlt, poleAz   ' -> alt, az

    altitude = 0#
    ' arch_rise must point AT the arch at the start of the window (the apex is on
    ' the SOUTH side as the GC rises), which is the galactic SOUTH pole azimuth
    ' = north pole az + 180. arch_set is the opposite perpendicular (north pole
    ' az). Both are continuous all night; the operator chooses when to Move.
    If LCase$(side) = "set" Then
        azimuth = NormalizeDeg(poleAz)               ' north pole az (opposite side)
    Else
        azimuth = NormalizeDeg(poleAz + 180#)        ' rise: south pole az (arch side at start)
    End If
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
    Dim y As Integer, m As Integer, d As Integer
    Dim hr As Double, mn As Double, sc As Double
    y = Year(dt)
    m = Month(dt)
    d = Day(dt)
    hr = Hour(dt)
    mn = Minute(dt)
    sc = Second(dt)
    
    If m <= 2 Then
        y = y - 1
        m = m + 12
    End If
    
    Dim a As Long, b As Long
    a = Int(y / 100)
    b = 2 - a + Int(a / 4)
    
    DateToJulian = Int(365.25 * (y + 4716)) + _
                   Int(30.6001 * (m + 1)) + _
                   d + b - 1524.5 + _
                   (hr + mn / 60# + sc / 3600#) / 24#
End Function

' Normalise angle to 0-360 range
Private Function NormalizeDeg(ByVal deg As Double) As Double
    NormalizeDeg = deg - 360# * Int(deg / 360#)
    If NormalizeDeg < 0 Then NormalizeDeg = NormalizeDeg + 360#
End Function

' VBA Asin -- not built in
Private Function Asin(ByVal x As Double) As Double
    If Abs(x) = 1 Then
        Asin = PI / 2 * Sgn(x)
    Else
        Asin = Atn(x / Sqr(1 - x * x))
    End If
End Function

' VBA Acos -- not built in
Private Function Acos(ByVal x As Double) As Double
    If Abs(x) = 1 Then
        Acos = (1 - x) * PI / 2
    Else
        Acos = PI / 2 - Atn(x / Sqr(1 - x * x))
    End If
End Function

' VBA Atan2 -- not built in
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


' ============================================================
' MOON POSITION  (Day 18, Workfront #55)
'
' Schlyter low-precision lunar formulae. Accurate to ~1-2 deg
' which is well inside the 14mm lens FOV tolerance for this
' rig. Public domain, well-documented.
'
' Reference: Paul Schlyter, "How to compute planetary positions"
' http://www.stjarnhimlen.se/comp/ppcomp.html
'
' Computes ecliptic (geocentric) lon/lat/distance of the moon
' from its orbital elements at the given UTC moment, then
' converts to equatorial (RA, Dec), then to local (az, alt) via
' the existing RADecToAltAz helper.
' ============================================================

' Public wrappers     match the GetSun* pattern
Public Function GetMoonAzimuth() As Double
    Dim az As Double, alt As Double
    GetMoonPosition Now, az, alt
    GetMoonAzimuth = az
End Function

Public Function GetMoonAltitude() As Double
    Dim az As Double, alt As Double
    GetMoonPosition Now, az, alt
    GetMoonAltitude = alt
End Function

Public Sub GetMoonAzAltAtTime(ByVal atTime As Date, _
                               ByRef az As Double, _
                               ByRef alt As Double)
    GetMoonPosition atTime, az, alt
End Sub

' Calculate gimbal yaw and pitch to point at moon at given time
' cartHeading: compass bearing the cart faces (degrees)
' Returns True if moon is above horizon
Public Function GetMoonGimbalAngles(ByVal atTime As Date, _
                                     ByVal cartHeading As Double, _
                                     ByRef gimbalYaw As Double, _
                                     ByRef gimbalPitch As Double) As Boolean
    Dim az As Double, alt As Double
    GetMoonPosition atTime, az, alt

    gimbalYaw = AzimuthToGimbalYaw(az, cartHeading)
    gimbalPitch = alt

    GetMoonGimbalAngles = (alt > -5)  ' True if moon within 5  of horizon

    LogEvent "ASTRO", "Moon at " & Format(atTime, "HH:nn:ss") & _
             ": az=" & Format(az, "0.0") & Chr(176) & _
             " alt=" & Format(alt, "0.0") & Chr(176) & _
             " -> yaw=" & Format(gimbalYaw, "0.0") & Chr(176) & _
             " pitch=" & Format(gimbalPitch, "0.0") & Chr(176)
End Function

'           Moon position core
' Returns local-sky azimuth (deg from N clockwise) and altitude
' (deg above horizon) at the given local time. Below horizon
' returns negative altitude     caller's responsibility to decide
' what to do with it.
Private Sub GetMoonPosition(ByVal atTime As Date, _
                             ByRef azimuth As Double, _
                             ByRef altitude As Double)

    Dim lat As Double, lng As Double, utcOffset As Double
    lat = Sheets("Settings").Range("dataLatitude").value
    lng = Sheets("Settings").Range("dataLongitude").value
    utcOffset = Sheets("Settings").Range("dataUTCOffset").value

    ' Convert local time to UTC
    Dim utcTime As Date
    utcTime = atTime - (utcOffset / 24)

    ' "d" in Schlyter's notation: days since 2000 Jan 0.0 UT
    ' (i.e. midnight at end of 1999 Dec 31). JD 2451543.5 = d=0.
    Dim jd As Double, d As Double
    jd = DateToJulian(utcTime)
    d = jd - 2451543.5

    ' Moon orbital elements at time d (degrees)
    Dim NN As Double    ' Longitude of ascending node
    Dim ii As Double    ' Inclination
    Dim w  As Double    ' Argument of perigee
    Dim a  As Double    ' Mean distance (Earth radii)
    Dim e  As Double    ' Eccentricity
    Dim m  As Double    ' Mean anomaly
    NN = NormalizeDeg(125.1228 - 0.0529538083 * d)
    ii = 5.1454
    w = NormalizeDeg(318.0634 + 0.1643573223 * d)
    a = 60.2666
    e = 0.0549
    m = NormalizeDeg(115.3654 + 13.0649929509 * d)

    ' Solve Kepler (1st-order, sufficient for moon's small e)
    Dim E1 As Double
    E1 = m + RAD2DEG * e * Sin(m * DEG2RAD) * (1 + e * Cos(m * DEG2RAD))
    Dim E0 As Double
    Dim iter As Integer
    For iter = 1 To 10
        E0 = E1
        E1 = E0 - (E0 - RAD2DEG * e * Sin(E0 * DEG2RAD) - m) / _
                  (1 - e * Cos(E0 * DEG2RAD))
        If Abs(E1 - E0) < 0.001 Then Exit For
    Next iter

    ' Moon's position in orbital plane (Earth radii)
    Dim xv As Double, yv As Double
    xv = a * (Cos(E1 * DEG2RAD) - e)
    yv = a * Sqr(1 - e * e) * Sin(E1 * DEG2RAD)

    ' True anomaly and orbital-plane distance
    Dim v As Double, r As Double
    v = RAD2DEG * Atn2(yv, xv)
    r = Sqr(xv * xv + yv * yv)

    ' Heliocentric (well, geocentric for moon) ecliptic position
    Dim NRad As Double, wvRad As Double, iRad As Double
    NRad = NN * DEG2RAD
    wvRad = (w + v) * DEG2RAD
    iRad = ii * DEG2RAD

    Dim xeclip As Double, yeclip As Double, zeclip As Double
    xeclip = r * (Cos(NRad) * Cos(wvRad) - Sin(NRad) * Sin(wvRad) * Cos(iRad))
    yeclip = r * (Sin(NRad) * Cos(wvRad) + Cos(NRad) * Sin(wvRad) * Cos(iRad))
    zeclip = r * Sin(wvRad) * Sin(iRad)

    ' Geocentric ecliptic lon/lat
    Dim eclLon As Double, eclLat As Double
    eclLon = NormalizeDeg(RAD2DEG * Atn2(yeclip, xeclip))
    eclLat = RAD2DEG * Atn2(zeclip, Sqr(xeclip * xeclip + yeclip * yeclip))

    ' --- Perturbations (Schlyter's main moon terms) ---
    ' Sun's mean anomaly + longitude (we need them as offsets)
    Dim ws_ As Double, ms As Double, Ls As Double, Lm As Double
    ws_ = NormalizeDeg(282.9404 + 0.0000470935 * d)
    ms = NormalizeDeg(356.047 + 0.9856002585 * d)
    Ls = NormalizeDeg(ws_ + ms)                       ' Sun mean longitude
    Lm = NormalizeDeg(NN + w + m)                      ' Moon mean longitude

    Dim Mm As Double, Dm As Double, f As Double
    Mm = m                                              ' Moon mean anomaly
    Dm = NormalizeDeg(Lm - Ls)                          ' Mean elongation
    f = NormalizeDeg(Lm - NN)                          ' Argument of latitude

    ' Longitude perturbations (degrees)     only the largest terms
    Dim dLon As Double
    dLon = -1.274 * Sin((Mm - 2 * Dm) * DEG2RAD) _
         + 0.658 * Sin(2 * Dm * DEG2RAD) _
         - 0.186 * Sin(ms * DEG2RAD) _
         - 0.059 * Sin((2 * Mm - 2 * Dm) * DEG2RAD) _
         - 0.057 * Sin((Mm - 2 * Dm + ms) * DEG2RAD) _
         + 0.053 * Sin((Mm + 2 * Dm) * DEG2RAD) _
         + 0.046 * Sin((2 * Dm - ms) * DEG2RAD) _
         + 0.041 * Sin((Mm - ms) * DEG2RAD) _
         - 0.035 * Sin(Dm * DEG2RAD) _
         - 0.031 * Sin((Mm + ms) * DEG2RAD)
    eclLon = NormalizeDeg(eclLon + dLon)

    ' Latitude perturbations (degrees)     largest terms
    Dim dLat As Double
    dLat = -0.173 * Sin((f - 2 * Dm) * DEG2RAD) _
         - 0.055 * Sin((Mm - f - 2 * Dm) * DEG2RAD) _
         - 0.046 * Sin((Mm + f - 2 * Dm) * DEG2RAD) _
         + 0.033 * Sin((f + 2 * Dm) * DEG2RAD) _
         + 0.017 * Sin((2 * Mm + f) * DEG2RAD)
    eclLat = eclLat + dLat

    ' Convert ecliptic lon/lat to equatorial RA/Dec
    Dim epsilon As Double
    epsilon = 23.4393 - 0.0000003563 * d   ' Obliquity at time d

    Dim xe As Double, yE As Double, ze As Double
    xe = Cos(eclLon * DEG2RAD) * Cos(eclLat * DEG2RAD)
    yE = Sin(eclLon * DEG2RAD) * Cos(eclLat * DEG2RAD) * Cos(epsilon * DEG2RAD) _
       - Sin(eclLat * DEG2RAD) * Sin(epsilon * DEG2RAD)
    ze = Sin(eclLon * DEG2RAD) * Cos(eclLat * DEG2RAD) * Sin(epsilon * DEG2RAD) _
       + Sin(eclLat * DEG2RAD) * Cos(epsilon * DEG2RAD)

    Dim ra As Double, dec As Double
    ra = NormalizeDeg(RAD2DEG * Atn2(yE, xe))
    dec = RAD2DEG * Atn2(ze, Sqr(xe * xe + yE * yE))

    ' Greenwich Sidereal Time     Local Sidereal Time
    ' Use the same formula as GetSunPosition for consistency.
    Dim N_d As Double
    N_d = jd - 2451545#                ' Days since J2000.0
    Dim gmst As Double, lst As Double
    gmst = NormalizeDeg(280.46061837 + 360.98564736629 * N_d)
    lst = NormalizeDeg(gmst + lng)

    ' Hour angle
    Dim ha As Double
    ha = NormalizeDeg(lst - ra)
    If ha > 180 Then ha = ha - 360

    ' Reduce equatorial to topocentric (parallax correction).
    ' Moon's parallax is ~1 degree max     non-trivial for our
    ' tolerance. Schlyter eq for topocentric correction:
    '   mpar = asin(1/r) where r is distance in Earth radii.
    Dim mpar As Double
    mpar = RAD2DEG * Asin(1# / r)

    ' Geocentric     topocentric via simple correction:
    '   alt_topo = alt - mpar*cos(alt)
    ' We'll apply this AFTER converting to alt/az, since the
    ' correction is in altitude.
    RADecToAltAz ha, dec, lat, altitude, azimuth

    ' Parallax correction in altitude (Schlyter   16)
    altitude = altitude - mpar * Cos(altitude * DEG2RAD)
End Sub


' ============================================================
' SUN ALTITUDE ROOT FINDER  (Day 18, supports offline shoot prep)
'
' Returns the local time at which the sun's altitude crosses
' targetAltitude going in `direction` (+1 = rising past target,
' -1 = setting past target) within the day starting at dayStart.
'
' Used to compute, without internet:
'   Sunrise/Sunset          targetAltitude = -0.833 (refraction)
'   Civil dawn/dusk         targetAltitude = -6
'   Nautical dawn/dusk      targetAltitude = -12
'   Astro dawn/dusk         targetAltitude = -18
'
' direction = +1 means "rising past target" (alt < target     alt > target)
' direction = -1 means "setting past target" (alt > target     alt < target)
'
' Returns 0 (= zero date) if no crossing exists in the day
' (e.g. polar night for astro twilight).
' ============================================================
Public Function FindSunCrossing(ByVal dayStart As Date, _
                                 ByVal targetAltitude As Double, _
                                 ByVal direction As Integer) As Date
    Const SCAN_STEP_MIN As Double = 5
    Dim stepDays As Double
    stepDays = SCAN_STEP_MIN / 1440#

    Dim t As Date, prevT As Date
    Dim alt As Double, prevAlt As Double, azIgnore As Double
    Dim havePrev As Boolean
    havePrev = False

    Dim dayEnd As Date
    dayEnd = dayStart + 1#       ' 24h scan window

    For t = dayStart To dayEnd Step stepDays
        GetSunPosition t, azIgnore, alt
        If havePrev Then
            ' Detect sign change relative to target
            Dim prevDiff As Double, curDiff As Double
            prevDiff = prevAlt - targetAltitude
            curDiff = alt - targetAltitude
            If direction > 0 And prevDiff < 0 And curDiff >= 0 Then
                ' Rising crossing     bisect between prevT and t
                FindSunCrossing = BisectSunAltitude(prevT, t, targetAltitude)
                Exit Function
            ElseIf direction < 0 And prevDiff > 0 And curDiff <= 0 Then
                ' Setting crossing     bisect
                FindSunCrossing = BisectSunAltitude(prevT, t, targetAltitude)
                Exit Function
            End If
        End If
        prevT = t
        prevAlt = alt
        havePrev = True
    Next t

    ' No crossing found
    FindSunCrossing = 0
End Function

' Bisect to find the moment of crossing within tolerance
Private Function BisectSunAltitude(ByVal t1 As Date, _
                                    ByVal t2 As Date, _
                                    ByVal targetAlt As Double) As Date
    Const TOL_SEC As Double = 30      ' 30-second precision
    Const TOL_DAYS As Double = TOL_SEC / 86400#

    Dim lo As Date, hi As Date, mid As Date
    Dim altLo As Double, altMid As Double, azIgnore As Double
    lo = t1
    hi = t2
    GetSunPosition lo, azIgnore, altLo

    Do While (hi - lo) > TOL_DAYS
        mid = lo + (hi - lo) / 2#
        GetSunPosition mid, azIgnore, altMid
        ' Same-side test
        If Sgn(altLo - targetAlt) = Sgn(altMid - targetAlt) Then
            lo = mid
            altLo = altMid
        Else
            hi = mid
        End If
    Loop
    BisectSunAltitude = lo + (hi - lo) / 2#
End Function


' ============================================================
' MOON ALTITUDE ROOT FINDER  (Day 18, for moon track endpoints)
'
' Same shape as FindSunCrossing but using GetMoonPosition.
' Used to find moonrise / moonset times locally as a sanity-
' check on the sunrisesunset.io API values, AND to bound the
' track-cubic window when the API doesn't return values for
' the relevant calendar day.
'
' targetAltitude = -0.5 for standard moon-horizon (no refraction
' applied; matches what most almanacs use to within minutes).
'
' Returns 0 if no crossing found.
' ============================================================
Public Function FindMoonCrossing(ByVal dayStart As Date, _
                                  ByVal targetAltitude As Double, _
                                  ByVal direction As Integer) As Date
    Const SCAN_STEP_MIN As Double = 5
    Dim stepDays As Double
    stepDays = SCAN_STEP_MIN / 1440#

    Dim t As Date, prevT As Date
    Dim alt As Double, prevAlt As Double, azIgnore As Double
    Dim havePrev As Boolean
    havePrev = False

    Dim dayEnd As Date
    dayEnd = dayStart + 1#

    For t = dayStart To dayEnd Step stepDays
        GetMoonPosition t, azIgnore, alt
        If havePrev Then
            Dim prevDiff As Double, curDiff As Double
            prevDiff = prevAlt - targetAltitude
            curDiff = alt - targetAltitude
            If direction > 0 And prevDiff < 0 And curDiff >= 0 Then
                FindMoonCrossing = BisectMoonAltitude(prevT, t, targetAltitude)
                Exit Function
            ElseIf direction < 0 And prevDiff > 0 And curDiff <= 0 Then
                FindMoonCrossing = BisectMoonAltitude(prevT, t, targetAltitude)
                Exit Function
            End If
        End If
        prevT = t
        prevAlt = alt
        havePrev = True
    Next t

    FindMoonCrossing = 0
End Function

Private Function BisectMoonAltitude(ByVal t1 As Date, _
                                     ByVal t2 As Date, _
                                     ByVal targetAlt As Double) As Date
    Const TOL_SEC As Double = 30
    Const TOL_DAYS As Double = TOL_SEC / 86400#

    Dim lo As Date, hi As Date, mid As Date
    Dim altLo As Double, altMid As Double, azIgnore As Double
    lo = t1
    hi = t2
    GetMoonPosition lo, azIgnore, altLo

    Do While (hi - lo) > TOL_DAYS
        mid = lo + (hi - lo) / 2#
        GetMoonPosition mid, azIgnore, altMid
        If Sgn(altLo - targetAlt) = Sgn(altMid - targetAlt) Then
            lo = mid
            altLo = altMid
        Else
            hi = mid
        End If
    Loop
    BisectMoonAltitude = lo + (hi - lo) / 2#
End Function

' ============================================================
' Galactic Centre rise / transit / set solver (mirrors the moon
' crossing pattern, uses GetGCPosition). alt=0 = geometric horizon;
' operator decides shootability. GC is up across midnight, so the
' scan runs a full 24h from dayStart.
' ============================================================
Public Function FindGCCrossing(ByVal dayStart As Date, _
                                ByVal targetAltitude As Double, _
                                ByVal direction As Integer) As Date
    Const SCAN_STEP_MIN As Double = 5
    Dim stepDays As Double
    stepDays = SCAN_STEP_MIN / 1440#
    Dim t As Date, prevT As Date
    Dim alt As Double, prevAlt As Double, azIgnore As Double
    Dim havePrev As Boolean
    havePrev = False
    Dim dayEnd As Date
    dayEnd = dayStart + 1#
    For t = dayStart To dayEnd Step stepDays
        GetGCPosition t, azIgnore, alt
        If havePrev Then
            Dim prevDiff As Double, curDiff As Double
            prevDiff = prevAlt - targetAltitude
            curDiff = alt - targetAltitude
            If direction > 0 And prevDiff < 0 And curDiff >= 0 Then
                FindGCCrossing = BisectGCAltitude(prevT, t, targetAltitude)
                Exit Function
            ElseIf direction < 0 And prevDiff > 0 And curDiff <= 0 Then
                FindGCCrossing = BisectGCAltitude(prevT, t, targetAltitude)
                Exit Function
            End If
        End If
        prevT = t
        prevAlt = alt
        havePrev = True
    Next t
    FindGCCrossing = 0
End Function

Private Function BisectGCAltitude(ByVal t1 As Date, _
                                   ByVal t2 As Date, _
                                   ByVal targetAlt As Double) As Date
    Const TOL_SEC As Double = 30
    Const TOL_DAYS As Double = TOL_SEC / 86400#
    Dim lo As Date, hi As Date, mid As Date
    Dim altLo As Double, altMid As Double, azIgnore As Double
    lo = t1
    hi = t2
    GetGCPosition lo, azIgnore, altLo
    Do While (hi - lo) > TOL_DAYS
        mid = lo + (hi - lo) / 2#
        GetGCPosition mid, azIgnore, altMid
        If Sgn(altLo - targetAlt) = Sgn(altMid - targetAlt) Then
            lo = mid
            altLo = altMid
        Else
            hi = mid
        End If
    Loop
    BisectGCAltitude = lo + (hi - lo) / 2#
End Function

' Transit = time of maximum altitude between rise and set.
Public Function FindGCTransit(ByVal fromTime As Date, _
                               ByVal toTime As Date) As Date
    Const SCAN_STEP_MIN As Double = 5
    Dim stepDays As Double
    stepDays = SCAN_STEP_MIN / 1440#
    Dim t As Date, alt As Double, azIgnore As Double
    Dim bestT As Date, bestAlt As Double
    bestAlt = -999#
    For t = fromTime To toTime Step stepDays
        GetGCPosition t, azIgnore, alt
        If alt > bestAlt Then
            bestAlt = alt
            bestT = t
        End If
    Next t
    FindGCTransit = bestT
End Function



' ============================================================
' Driver: compute tonight's GC rise / transit / set and write to
' dataGCRiseTime / dataGCTransitTime / dataGCSetTime. Scan starts at
' local noon today so an evening rise and next-morning set are both
' inside the 24h window.
' ============================================================
Public Sub UpdateGCTimes()
    Dim setSheet As Worksheet
    Set setSheet = ThisWorkbook.Sheets("Settings")
    Dim scanStart As Date
    scanStart = Int(Now()) + (12# / 24#)
    Dim gcRise As Date, gcSet As Date, gcTransit As Date
    gcRise = FindGCCrossing(scanStart, 0#, 1)
    If gcRise = 0 Then
        MsgBox "GC rise not found in the 24h scan window.", vbExclamation, "UpdateGCTimes"
        Exit Sub
    End If
    gcSet = FindGCCrossing(gcRise, 0#, -1)
    If gcSet = 0 Then
        MsgBox "GC set not found after rise.", vbExclamation, "UpdateGCTimes"
        Exit Sub
    End If
    gcTransit = FindGCTransit(gcRise, gcSet)
    setSheet.Range("dataGCRiseTime").value = gcRise
    setSheet.Range("dataGCTransitTime").value = gcTransit
    setSheet.Range("dataGCSetTime").value = gcSet
    LogEvent "ASTRO", "GC times: rise=" & Format(gcRise, "yyyy-mm-dd HH:nn") & _
             " transit=" & Format(gcTransit, "HH:nn") & " set=" & Format(gcSet, "yyyy-mm-dd HH:nn")
    MsgBox "GC times updated:" & vbCrLf & _
           "Rise:    " & Format(gcRise, "ddd HH:nn") & vbCrLf & _
           "Transit: " & Format(gcTransit, "ddd HH:nn") & vbCrLf & _
           "Set:     " & Format(gcSet, "ddd HH:nn"), vbInformation, "UpdateGCTimes"
End Sub
