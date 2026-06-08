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

' ============================================================
' Three-phase prep. Run rhythm:
'   1 PrepSession - once. Fixed-for-the-day astro + location map.
'                   Knows nothing about the day's plans.
'   2 BuildPlan   - iterate. Render the day's gimbal plan + cable
'                   strip to SVG/PNG for review. No cart, no push.
'   3 PushToCart  - once (maybe twice). Set the UTC anchor and push
'                   all artifacts to the cart.
' Each reuses RunStep (logs + report line + soft/hard handling).
' ============================================================

' --- Phase 1: fixed session settings (astro + map). Run once. ---
Public Sub PrepSession()
    Dim rpt As String
    rpt = "Prep Session  " & Format(Now, "yyyy-mm-dd HH:nn") & vbCrLf & String(34, "-") & vbCrLf
    LogEvent "PREP", "--- PrepSession start ---"

    If Not RunStep("GetSunsetTime", "Get Sunset Time", rpt) Then GoTo Done
    If Not RunStep("Astro.UpdateGCTimes", "Update GC Times", rpt) Then GoTo Done
    If Not RunStep("InitShoot", "Init Shoot", rpt) Then GoTo Done
    If Not RunStep("GenerateGCTable", "Generate GC Table", rpt) Then GoTo Done

    ' Map: conditional (only if missing, or REFRESH_MAP). Soft.
    Dim mapPng As String
    mapPng = ThisWorkbook.path & Application.PathSeparator & "Python" & _
             Application.PathSeparator & "map.png"
    If REFRESH_MAP Or dir(mapPng) = "" Then
        RunStep "FetchGimbalMap", "Fetch Gimbal Map", rpt
    Else
        rpt = rpt & Pad("Fetch Gimbal Map") & ": skipped (map.png present)" & vbCrLf
        LogEvent "PREP", "Fetch Gimbal Map skipped (map.png present)"
    End If

Done:
    LogEvent "PREP", "--- PrepSession end ---"
    MsgBox rpt, vbInformation, "Prep Session"
End Sub

' --- Phase 2: render the day's plan for review. Iterate. No cart. ---
Public Sub BuildPlan()
    Dim rpt As String
    rpt = "Build Plan  " & Format(Now, "yyyy-mm-dd HH:nn") & vbCrLf & String(34, "-") & vbCrLf
    LogEvent "PREP", "--- BuildPlan start ---"

    ' Plan view first - the cable strip depends on the rendered gimbal plan.
    If Not RunStep("RenderPlanView", "Render Plan View", rpt) Then GoTo Done
    If Not RunStep("RenderCableStrip", "Render Cable Strip", rpt) Then GoTo Done

Done:
    LogEvent "PREP", "--- BuildPlan end ---"
    MsgBox rpt, vbInformation, "Build Plan"
End Sub

' --- Phase 3: push artifacts to the cart. Once, maybe twice. ---
' Re-run this right before arming: SetRealtimeAnchor must precede
' /track/start (track/start re-stamps the gimbal anchor), and the
' anchor + plans are not part of the cart's reload.
Public Sub PushToCart()
    Dim rpt As String, ok As Boolean
    rpt = "Push To Cart  " & Format(Now, "yyyy-mm-dd HH:nn") & vbCrLf & String(34, "-") & vbCrLf
    LogEvent "PREP", "--- PushToCart start ---"

    ' UTC realtime anchor first (cubic + anchor share one clock).
    ok = RunStep("AstroPush.SetRealtimeAnchor", "Set Realtime Anchor", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done

    ok = RunStep("PushCartPlan", "Push Cart Plan", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done
    ok = RunStep("PushTrackPlanToCart", "Push Track Plan", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done
    ok = RunStep("PushTrackPathsToCart", "Push Track Paths", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done
    ok = RunStep("PushChartToCart", "Push Chart", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done
    ok = RunStep("PushCableStripToCart", "Push Cable Strip", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo Done

Done:
    LogEvent "PREP", "--- PushToCart end ---"
    MsgBox rpt, vbInformation, "Push To Cart"
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
