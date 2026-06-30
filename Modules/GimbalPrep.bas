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

' #watchonce: arm the laptop alarm watcher at most ONCE per Excel session.
' Repeated Prep Cart runs were each relaunching it (the Python pidfile dedup
' is not holding), stacking watcher windows + extra /exec/feed pollers that
' add :80 load to the very runs being measured. Module-level = persists for
' the life of the project. Manual Start Watcher button is NOT affected.
Private m_watcherArmed As Boolean

' ---- behaviour toggles ----
Private Const STOP_ON_CART_FAIL As Boolean = False   ' True = abort if a cart push fails
Private Const REFRESH_MAP As Boolean = False         ' True = always re-fetch the map tile
' #pace: inter-step delay (ms) between cart pushes in PushToCart. The push
' steps used to be separated by the per-step MsgBoxes; suppressing those
' removed the recovery gaps the cart's :80 relied on, letting ~20 GETs fire
' back-to-back and tipping the cable-strip chunk handler into a multi-second
' stall. This restores a controlled gap. EXPERIMENT KNOB: 0 = back-to-back
' (reproduce the stall); raise until the stall vanishes. Local-only PrepSession
' and BuildPlan are NOT paced - only the cart pushes below.
' LIVE KNOB: the pace (ms) is read at run time from Control!E23 (the cell to
' the right of the Prep Cart button) so 300 <-> 0 A/B testing needs no module
' re-import - just type the value in that cell. If E23 is blank or non-numeric,
' PACE_DEFAULT_MS below is used. 0 = back-to-back (reproduce the stall);
' raise until the stall vanishes.
Private Const PACE_DEFAULT_MS As Long = 300           ' fallback when Control!E23 is blank/non-numeric
Private Const PACE_CELL       As String = "E23"       ' live pace knob, beside the Prep Cart button
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
'
    Call RenewLanLease
    
    If Not RunStep("GetSunsetTime", "Get Sunset Time", rpt) Then GoTo done
    If Not RunStep("Astro.UpdateGCTimes", "Update GC Times", rpt) Then GoTo done
    If Not RunStep("InitShoot", "Init Shoot", rpt) Then GoTo done
    If Not RunStep("GenerateGCTable", "Generate GC Table", rpt) Then GoTo done

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

done:
    LogEvent "PREP", "--- PrepSession end ---"
    ' MsgBox rpt, vbInformation, "Prep Session"   ' popup removed: success now silent, detail is in Log; pops only on error
End Sub

' --- Phase 2: render the day's plan for review. Iterate. No cart. ---
Public Sub BuildPlan()
    Dim rpt As String
    rpt = "Build Plan  " & Format(Now, "yyyy-mm-dd HH:nn") & vbCrLf & String(34, "-") & vbCrLf
    LogEvent "PREP", "--- BuildPlan start ---"

    ' Past-shoot warning (moved here from Prep Session / GetSunsetTime, 29Jun): the
    ' operator is actively building the plan now, so this is where a stale shoot
    ' date should be flagged. Non-blocking - warn and continue (the operator may be
    ' intentionally rebuilding an old plan for inspection); the astro compute itself
    ' aborts silently for a past night, and Prep Cart's own guards remain.
    Dim pastDawn As Date
    If Utils.ShootAlreadyOver(pastDawn) Then
        MsgBox "That shoot is already over (its dawn " & Format(pastDawn, "yyyy-mm-dd HH:nn") & _
               " has passed). Enter a current/future shoot start in Settings dataShootStart, " & _
               "then re-run Prep Session before building.", _
               vbExclamation, "Shoot already past"
        LogEvent "PREP", "BuildPlan: shoot already over (dawn " & _
                 Format(pastDawn, "yyyy-mm-dd HH:nn") & ") - warned"
    End If

    ' Native gimbal-plan validation FIRST: it re-lays the GimbalViz sweep table
    ' plus the Fires-at / Actual / Pan Time / Dir formulas. Everything downstream
    ' (Pan Time, the acquire_ms the push reads, the renderers) depends on this
    ' being current, so it must run before the renderers or those read a stale
    ' sweep from a previous plan.
    If Not RunStep("BuildGimbalPlanViz", "Build Gimbal Plan + Validation", rpt) Then GoTo done

    ' Plan view next - the cable strip depends on the rendered gimbal plan.
    If Not RunStep("RenderPlanView", "Render Plan View", rpt) Then GoTo done
    If Not RunStep("RenderCableStrip", "Render Cable Strip", rpt) Then GoTo done

    ' Pano planner image (soft - exploration aid, not load-bearing). Shows the
    ' landscape/portrait pano configs: edges, overlap, buckets, final-video cost.
    RunStep "RenderPanoPlanner", "Render Pano Planner", rpt

    ' Cable-span guard: detect + alert (does not block). Prep Cart enforces it.
    RunStep "CableSpan.DetectCableSpan", "Check Cable Span", rpt

done:
    LogEvent "PREP", "--- BuildPlan end ---"
    ' MsgBox rpt, vbInformation, "Build Plan"   ' popup removed: success now silent, detail is in Log; pops only on error
End Sub

' --- Phase 3: push artifacts to the cart. Once, maybe twice. ---
' Re-run this right before arming: SetRealtimeAnchor must precede
' /track/start (track/start re-stamps the gimbal anchor), and the
' anchor + plans are not part of the cart's reload.
Public Sub PushToCart()
    Dim rpt As String, ok As Boolean
    rpt = "Push To Cart  " & Format(Now, "yyyy-mm-dd HH:nn") & vbCrLf & String(34, "-") & vbCrLf
    LogEvent "PREP", "--- PushToCart start ---"

    ' Cable-span hard stop: refuse to push a plan that over-winds the gimbal.
    If Not CableSpan.CableSpanOK() Then
        LogEvent "PREP", "PushToCart ABORTED: cable span over 450 limit"
        rpt = rpt & "ABORTED: cable span exceeds 450 deg - fix plan, re-run Prep Plan." & vbCrLf
        MsgBox rpt, vbCritical, "Push To Cart - BLOCKED"
        Exit Sub
    End If

    ' UTC realtime anchor first (cubic + anchor share one clock).
    ok = RunStep("AstroPush.SetRealtimeAnchor", "Set Realtime Anchor", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace

    ok = RunStep("PushCartPlan", "Push Cart Plan", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ' Exposure ramp (sunset->sunrise Tv/ISO crossovers + ceilings -> /exposure/load).
    ' The cart's LUM walk ramps from these overnight; was a separate button, so a
    ' plan pushed without it ran the camera off the bare baseline with no planned
    ' night ramp. Folded in here so one Push To Cart sends everything.
    ok = RunStep("PushFormulaToCart", "Push Exposure Formula", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ' Astro keyframe positions (sun/moon/MW rise/set/mid -> /settings/astropos).
    ' These populate the cart's keyframe slots (Show astro, snapvar). They were
    ' NOT in the push chain, so the slots read empty after every reboot.
    ok = RunStep("AstroPush.PushAstroToCart", "Push Astro Positions", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ' #49 Cart battery low-V threshold (Settings!dataCartBattLow -> /settings/battlow).
    ' Echoed in /exec/feed as "battlow"; the laptop watcher reads it and compares.
    ok = RunStep("AstroPush.PushBattLowToCart", "Push Cart Batt Low", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ok = RunStep("PushTrackPlanToCart", "Push Track Plan", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ok = RunStep("PushTrackPathsToCart", "Push Track Paths", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ' Pano configs (landscape + portrait) - cart holds both; trigger picks which.
    ok = RunStep("PanoConfigPush.PushPanoConfigs", "Push Pano Configs", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ok = RunStep("PushChartToCart", "Push Chart", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace
    ok = RunStep("PushCableStripToCart", "Push Cable Strip", rpt)
    If Not ok And STOP_ON_CART_FAIL Then GoTo done
    Pace

done:
    ' #49/#watchonce Arm the laptop alarm watcher with the prep, but only the
    ' FIRST Prep Cart of the session - later runs skip it so windows/pollers
    ' don't stack. Guarded so a launch hiccup never blocks the prep report.
    ' (If you killed the watcher mid-session, relaunch it with the Start
    ' Watcher button.)
    If Not m_watcherArmed Then
        On Error Resume Next
        StartWatcherAuto
        m_watcherArmed = True
        On Error GoTo 0
    End If
    LogEvent "PREP", "--- PushToCart end ---"
    ' MsgBox rpt, vbInformation, "Push To Cart"   ' popup removed: success now silent, detail is in Log; pops only on error
End Sub

' #pace: effective pace in ms. Live override from Control!PACE_CELL when it
' holds a number >= 0; otherwise PACE_DEFAULT_MS. Any read error -> default.
Private Function PaceMs() As Long
    On Error GoTo fallback
    Dim v As Variant
    v = ThisWorkbook.Sheets("Control").Range(PACE_CELL).value
    If IsNumeric(v) Then
        If v >= 0 Then PaceMs = CLng(v): Exit Function
    End If
fallback:
    PaceMs = PACE_DEFAULT_MS
End Function

' #pace: yield-friendly inter-step gap between cart pushes. Timer-based (sub-
' second), DoEvents keeps Excel responsive, no API declare (locked-down laptop
' safe). Guards the midnight Timer rollover. No-op when the pace is <= 0.
Private Sub Pace()
    Dim ms As Long
    ms = PaceMs()
    If ms <= 0 Then Exit Sub
    Dim t0 As Double
    t0 = Timer
    Do
        DoEvents
        If Timer < t0 Then Exit Do          ' crossed midnight - bail rather than wait ~24h
    Loop While (Timer - t0) * 1000# < ms
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
