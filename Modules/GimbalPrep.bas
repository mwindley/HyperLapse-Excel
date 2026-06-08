Attribute VB_Name = "GimbalPrep"
' HyperLapse - "Prep" button. One press runs the whole nightly prep
' sequence in dependency order, then lands you on the Plan View dial.
'
' Order (see SESSION_SUMMARY_AND_PREP.md):
'   1 Get Sunset Time       (local)   - hard: must pass
'   2 Init Shoot            (local)   - hard  (camera/CCAPI absence is OK,
'                                              Tv fallback covers it; this
'                                              step can take ~50s waiting
'                                              on an absent camera)
'   3 Generate GC Table     (local)   - hard
'   4 Push Astro to Cart    (cart)    - soft: warn+continue if cart down
'   5 Push Track Paths      (cart)    - soft
'   6 Fetch Gimbal Map      (network) - conditional: only if map.png is
'                                       missing (or REFRESH_MAP=True), soft
'   7 Render Plan View      (local)   - hard: ends on the dial
'
' "soft" = a failure (e.g. GIGA not connected during planning) is logged
' and reported but does NOT abort prep - you still get the table + dial.
' "hard" = a failure stops prep (no point rendering a plan with no table).
'
' Each underlying macro still shows its own dialog, so a Prep press = click
' OK through those, then a final summary. Idempotent: every step recomputes
' and overwrites, so pressing Prep twice is harmless.
'
' Assign PrepShoot to a Control-sheet button. (If the button row is full,
' the Day/night control can move to the execution UI to make room.)

Option Explicit

' ---- behaviour toggles ----
Private Const STOP_ON_CART_FAIL As Boolean = False   ' True = abort if a cart push fails
Private Const REFRESH_MAP As Boolean = False         ' True = always re-fetch the map tile
' ---------------------------

Public Sub PrepShoot()
    Dim rpt As String, ok As Boolean
    rpt = "Prep Shoot  " & Format(Now, "yyyy-mm-dd HH:nn") & vbCrLf & String(34, "-") & vbCrLf
    LogEvent "PREP", "=== PrepShoot start ==="

    ' --- Phase 1: local astro (hard) ---
    If Not RunStep("GetSunsetTime", "Get Sunset Time", rpt) Then GoTo Done
    If Not RunStep("InitShoot", "Init Shoot", rpt) Then GoTo Done
    If Not RunStep("GenerateGCTable", "Generate GC Table", rpt) Then GoTo Done

    ' --- Phase 2: cart pushes (soft unless STOP_ON_CART_FAIL) ---
    ok = RunStep("PushAstroToCart", "Push Astro to Cart", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done
    ok = RunStep("PushTrackPathsToCart", "Push Track Paths", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done

    ' --- Phase 3: map (conditional, soft) ---
    Dim mapPng As String
    mapPng = ThisWorkbook.Path & Application.PathSeparator & "Python" & _
             Application.PathSeparator & "map.png"
    If REFRESH_MAP Or Dir(mapPng) = "" Then
        RunStep "FetchGimbalMap", "Fetch Gimbal Map", rpt
    Else
        rpt = rpt & Pad("Fetch Gimbal Map") & ": skipped (map.png present)" & vbCrLf
        LogEvent "PREP", "Fetch Gimbal Map skipped (map.png present)"
    End If

    ' --- Phase 4: render (hard, ends on the dial) ---
    If Not RunStep("RenderPlanView", "Render Plan View", rpt) Then GoTo Done

Done:
    LogEvent "PREP", "=== PrepShoot end ==="
    MsgBox rpt, vbInformation, "Prep Shoot"
End Sub

' Run one macro by name, log + append a report line, return success.
Private Function RunStep(ByVal macroName As String, _
                         ByVal label As String, _
                         ByRef rpt As String) As Boolean
    Dim okFlag As Boolean
    okFlag = True
    On Error Resume Next
    Application.Run macroName
    If Err.Number <> 0 Then
        okFlag = False
        rpt = rpt & Pad(label) & ": FAILED - " & Err.Description & vbCrLf
        LogEvent "PREP", macroName & " FAILED: " & Err.Description
        Err.Clear
    Else
        rpt = rpt & Pad(label) & ": ok" & vbCrLf
        LogEvent "PREP", macroName & " ok"
    End If
    On Error GoTo 0
    RunStep = okFlag
End Function

' Left-justify a label to a fixed width for tidy report columns.
Private Function Pad(ByVal s As String) As String
    Const w As Integer = 18
    If Len(s) >= w Then
        Pad = s
    Else
        Pad = s & Space(w - Len(s))
    End If
End Function
