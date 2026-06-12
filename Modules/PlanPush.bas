Attribute VB_Name = "PlanPush"
' ============================================================
' HyperLapse Cart - Plan Push (P7)
'
' Reads the middle-zone Gimbal Plan and pushes it to the cart
' as a sequence of plan segments + TrackIntervals + (optionally)
' cubic path coefficients.
'
' Public entry:
'   PushGimbalPlan - Stage 2. Reads dataPlanPushDryRun, runs
'                    Phase 1 validation, reports collected errors.
'                    No decomposition or push yet.
'
' Stages (per Session E P7 design):
'   1. Validate    - walk middle zone, collect errors, abort if any   [STAGE 2]
'   2. Prerequisite - ensure track_<obj> cubics are loaded            [STAGE 3]
'   3. Decompose   - each Plan row -> cart-side segments + intervals   [STAGE 3]
'   4. POST        - sequential GETs to cart endpoints                [STAGE 4]
'   5. Summary     - report counts, log to Log sheet                  [Stage 5]
'
' Dry-run mode (Settings!dataPlanPushDryRun = TRUE):
'   Phases 1-3 + 5 run. Phase 4 is skipped. Cart not contacted.
'   Use during plan authoring or while hardware is offline.
'
' Real push mode (Settings!dataPlanPushDryRun = FALSE):
'   Pings cart /status first; aborts cleanly if no response.
'   All five phases run. Tells operator what was pushed.
'
' Day 21 (Session F) - Stage 1 skeleton.
' Day 21 (Session F) - Stage 2 Phase 1 validation added.
' Day 21 (Session F) - workfront #67 Phase 1: IsAstroTarget
' accepts "gc" (new Plan token) and "mw" (cart wire protocol /
' back-compat).
' Day 21 (Session F) - Stage 3 Phase 3 decompose added. One Log
' line per row describing the cart-side artifact (segment or
' TrackInterval). Astro endpoints evaluated via Astro.bas in
' dry-run. Cubic coefficient computation deferred - Stage 3 emits
' only endpoint + duration summary, not the curve coefficients.
' ============================================================

Option Explicit

' Plan sheet middle-zone columns (Session E layout)
Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_MAX_ROWS  As Long = 60

' Middle-zone column numbers
' MIDDLE columns resolved by header name at run time via EnsureCols ->
' PlanCols.ResolveMiddleCols, so a column reorder in Excel cannot break this
' push. Populated at the top of each public entry point.
Private COL_STEP        As Long
Private COL_ANCHOR_TYPE As Long
Private COL_ANCHOR_REF  As Long
Private COL_OFFSET      As Long
Private COL_FIRES_AT    As Long
Private COL_TOTAL_DUR   As Long
Private COL_ACTION      As Long
Private COL_TARGET      As Long
Private COL_RATE        As Long
Private COL_RY          As Long
Private COL_RP          As Long
Private COL_DYAW        As Long
Private COL_DPITCH      As Long
Private COL_MOVE_T      As Long
Private COL_NOTE        As Long
Private Const LOG_CATEGORY As String = "P7"

' Cart-side track interval slot limit (sketch TRACK_PLAN_MAX,
' line ~951 on Giga v2). Plan validation warns if exceeded.
Private Const TRACK_PLAN_MAX As Long = 10
' Cart-side preview pose slot limit (sketch PREVIEW_PLAN_MAX).
Private Const PREVIEW_PLAN_MAX As Long = 20


' ============================================================
' Public - PushGimbalPlan
' Populate the module COL_* indices from the shared header-name resolver.
' Returns False (caller should abort) if a required header is missing.
Private Function EnsureCols(ByVal ws As Worksheet) As Boolean
    EnsureCols = False
    Dim cols As Object: Set cols = PlanCols.ResolveMiddleCols(ws)
    If cols Is Nothing Then Exit Function
    COL_STEP = cols("step"): COL_ANCHOR_TYPE = cols("anchortype")
    COL_ANCHOR_REF = cols("anchorref"): COL_OFFSET = cols("offset(min)")
    COL_FIRES_AT = cols("firesat"): COL_TOTAL_DUR = cols("stay(min)")
    COL_ACTION = cols("action"): COL_TARGET = cols("target")
    COL_RATE = cols("panspeed"): COL_RY = cols("ry"): COL_RP = cols("rp")
    COL_DYAW = cols("dyaw"): COL_DPITCH = cols("dpitch")
    COL_MOVE_T = cols("movet"): COL_NOTE = cols("note")
    EnsureCols = True
End Function
' ============================================================
Public Sub PushGimbalPlan()
    On Error GoTo ErrHandler

    Dim dryRun As Boolean
    dryRun = ReadDryRunFlag()

    Dim mode As String
    If dryRun Then mode = "DRY RUN" Else mode = "REAL PUSH"

    ' Use "---" prefix not "===" since Utils.LogEvent on the Log
    ' sheet treats a leading "=" as a formula and silently fails.
    LogP7 "--- PushGimbalPlan start (" & mode & ") ---"

    Dim wsPlan As Worksheet
    Set wsPlan = ThisWorkbook.Sheets("Plan")
    If Not EnsureCols(wsPlan) Then Exit Sub   ' header-map (fail-loud)

    ' --- Phase 1: Validate ---
    Dim errCount As Long
    errCount = Phase1Validate(wsPlan)

    If errCount > 0 Then
        LogP7 "Phase 1 FAILED: " & errCount & " row(s) with errors. Aborting."
        LogP7 "--- PushGimbalPlan end (validation failed) ---"
        MsgBox "Validation failed: " & errCount & " row(s) have errors." & _
               vbCrLf & vbCrLf & "See Log sheet for per-row detail." & _
               vbCrLf & vbCrLf & "Fix the errors and re-run.", _
               vbExclamation, "PushGimbalPlan"
        Exit Sub
    End If

    LogP7 "Phase 1 OK: validation passed"

    ' --- Phase 3: Decompose ---
    ' (Phase 2 prerequisites - track_<obj> push - is moot in dry-run
    ' and will land with Stage 4 real-push.)
    Dim segCount As Long, intervalCount As Long
    Phase3Decompose wsPlan, segCount, intervalCount

    LogP7 "Phase 3 OK: " & segCount & " plan segment(s), " & _
          intervalCount & " TrackInterval(s)"

    If intervalCount > TRACK_PLAN_MAX Then
        LogP7 "WARNING: " & intervalCount & " TrackIntervals exceeds " & _
              "TRACK_PLAN_MAX=" & TRACK_PLAN_MAX & " on cart. " & _
              "Push would fail. Reduce Track rows."
    End If

    ' --- Phase 4: POST (Stage 4, not yet wired) ---
    If Not dryRun Then
        LogP7 "Phase 4: real push not yet implemented (Stage 4)."
    End If

    LogP7 "--- PushGimbalPlan end (" & mode & ", stage 3) ---"

    Dim doneMsg As String
    doneMsg = "PushGimbalPlan (" & mode & "): decomposition complete." & vbCrLf & vbCrLf & _
              segCount & " plan segment(s), " & intervalCount & " TrackInterval(s)." & _
              vbCrLf & vbCrLf & "See Log sheet for the per-row breakdown."
    If intervalCount > TRACK_PLAN_MAX Then
        doneMsg = doneMsg & vbCrLf & vbCrLf & "WARNING: exceeds cart's " & _
                  TRACK_PLAN_MAX & "-interval limit."
    End If
    MsgBox doneMsg, vbInformation, "PushGimbalPlan"

    Exit Sub

ErrHandler:
    LogP7 "ERROR: " & Err.Description
    MsgBox "Error in PushGimbalPlan:" & vbCrLf & vbCrLf & _
           Err.Description, vbCritical, "PushGimbalPlan"
End Sub


' ============================================================
' Phase 1 - Validate
' Walks middle zone, emits one Log line per row with errors,
' returns total count of rows that had at least one error.
'
' Plan-level checks (across rows):
'   - At least one populated row
'   - Last populated row's Action must be END
'   - No populated rows after the END row (END is the sentinel)
'
' Row-level checks (per populated row):
'   - Fires at (col Q) not blank/error  - anchor resolved
'   - Action (col S) is one of the 6 known values
'   - Target sensible for the Action
'   - Rate present where the Action needs one
'   - Ry / Rp populated where the Action needs them
' ============================================================
Private Function Phase1Validate(ByVal ws As Worksheet) As Long
    Dim rowsWithErrors As Long: rowsWithErrors = 0
    Dim populatedRows As Long: populatedRows = 0
    Dim lastPopRow As Long: lastPopRow = 0
    Dim endRowSeen As Long: endRowSeen = 0

    ' --- First pass: find populated rows, locate the END row ---
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Not IsEmpty(ws.Cells(r, COL_ANCHOR_TYPE).value) Then
            populatedRows = populatedRows + 1
            lastPopRow = r
            Dim act As String
            act = UCase(Trim(CStr(ws.Cells(r, COL_ACTION).value)))
            If act = "END" Then
                If endRowSeen = 0 Then endRowSeen = r
            End If
        End If
    Next r

    ' --- Plan-level checks ---
    If populatedRows = 0 Then
        LogP7 "Plan: EMPTY " & EmDash() & " no rows to push (write at least one row + END)"
        Phase1Validate = 1
        Exit Function
    End If

    If endRowSeen = 0 Then
        LogP7 "Plan: NO END ROW " & EmDash() & " last row must have Action=END"
        rowsWithErrors = rowsWithErrors + 1
    ElseIf endRowSeen < lastPopRow Then
        LogP7 "Plan: rows past END (row " & endRowSeen & " is END, " & _
              "but row " & lastPopRow & " is also populated). " & _
              "END must be the last row."
        rowsWithErrors = rowsWithErrors + 1
    End If

    ' --- Second pass: per-row checks ---
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Not IsEmpty(ws.Cells(r, COL_ANCHOR_TYPE).value) Then
            Dim rowErrs As String
            rowErrs = ValidateOneRow(ws, r)
            If rowErrs <> "" Then
                LogP7 "Row " & r & " (" & CStr(ws.Cells(r, COL_STEP).value) & _
                      "): " & rowErrs
                rowsWithErrors = rowsWithErrors + 1
            End If
        End If
    Next r

    Phase1Validate = rowsWithErrors
End Function


' ============================================================
' Phase 3 - Decompose
' Walks middle-zone rows in order, emits one Log line per row
' describing the cart-side artifact(s) that would be pushed.
' Increments segCount / intervalCount as it goes.
'
' Per Session E decomposition table:
'   Pan Follow     -> PANFOLLOW segment, ts..te
'   Lock           -> HOLD segment at current pose, ts..te
'   Move (marker)  -> CUBIC slew to (Ry+-yaw, Rp+-pitch), ts..te
'   Move (astro)   -> CUBIC slew to (yaw, pitch) from astro eval, ts..te
'   Track full     -> TrackInterval mode=F, ts..te, obj, offY, offP
'   Track-yaw      -> TrackInterval mode=Y, ts..te, obj, offY, Rp(abs)
'   END            -> no segment (provides te for previous row)
'
' Dry-run notes:
'   - Astro endpoint preview uses Astro.bas direct astronomy
'     (small residual vs. cart's fitted-cubic eval; ~7px at 14mm
'     per WORKFRONTS #58, below visible threshold).
'   - Cubic coefficients NOT computed in Stage 3 (deferred - needs
'     ease-band -> frames -> seconds conversion which isn't built).
'     Each CUBIC line just states endpoint + duration.
' ============================================================
Private Sub Phase3Decompose(ByVal ws As Worksheet, _
                             ByRef segCount As Long, _
                             ByRef intervalCount As Long)
    segCount = 0
    intervalCount = 0

    ' Read cart heading once - used by every astro-target eval
    Dim cartHeading As Double
    cartHeading = ReadCartHeading()

    ' Collect populated row indices in order so we can look ahead
    ' to "next row's Fires-at" for the te of each segment.
    Dim rows() As Long
    ReDim rows(0 To PLAN_MAX_ROWS)
    Dim nRows As Long: nRows = 0
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Not IsEmpty(ws.Cells(r, COL_ANCHOR_TYPE).value) Then
            rows(nRows) = r
            nRows = nRows + 1
        End If
    Next r

    Dim i As Long
    For i = 0 To nRows - 1
        Dim rowIdx As Long: rowIdx = rows(i)
        Dim stepLabel As String: stepLabel = CStr(ws.Cells(rowIdx, COL_STEP).value)
        Dim action As String
        action = UCase(Trim(CStr(ws.Cells(rowIdx, COL_ACTION).value)))

        Dim ts As Variant: ts = ws.Cells(rowIdx, COL_FIRES_AT).value
        Dim te As Variant
        If i < nRows - 1 Then
            te = ws.Cells(rows(i + 1), COL_FIRES_AT).value
        Else
            ' Last row (should be END) has no successor; use empty
            te = Empty
        End If

        Dim tsStr As String, teStr As String
        tsStr = FmtTime(ts)
        teStr = FmtTime(te)

        Select Case action
            Case "END"
                LogP7 "  " & stepLabel & " END: plan ends at " & tsStr & _
                      " (provides hold-tail end for previous row)"

            Case "PAN FOLLOW"
                LogP7 "  " & stepLabel & " PANFOLLOW seg, " & _
                      "ts=" & tsStr & " te=" & teStr
                segCount = segCount + 1

            Case "LOCK"
                LogP7 "  " & stepLabel & " HOLD seg @ current pose, " & _
                      "ts=" & tsStr & " te=" & teStr
                segCount = segCount + 1

            Case "MOVE"
                Dim target As String
                target = LCase(Trim(CStr(ws.Cells(rowIdx, COL_TARGET).value)))

                Dim endYaw As Double, endPitch As Double
                Dim endNote As String

                If IsAstroTarget(target) Then
                    ' Astro snapshot - evaluate at ts (Fires-at)
                    Dim okAstro As Boolean
                    okAstro = EvalAstro(target, CDbl(ts), cartHeading, _
                                        endYaw, endPitch)
                    Dim dyaw As Double, dpitch As Double
                    dyaw = SafeDouble(ws.Cells(rowIdx, COL_DYAW).value)
                    dpitch = SafeDouble(ws.Cells(rowIdx, COL_DPITCH).value)
                    endYaw = endYaw + dyaw
                    endPitch = endPitch + dpitch
                    If okAstro Then
                        endNote = "[astro " & target & " @ " & tsStr & "+delta]"
                    Else
                        endNote = "[astro " & target & " BELOW HORIZON]"
                    End If
                Else
                    ' Marker - use authored Ry/Rp + deltas
                    Dim ry As Double, rp As Double
                    ry = SafeDouble(ws.Cells(rowIdx, COL_RY).value)
                    rp = SafeDouble(ws.Cells(rowIdx, COL_RP).value)
                    endYaw = ry + SafeDouble(ws.Cells(rowIdx, COL_DYAW).value)
                    endPitch = rp + SafeDouble(ws.Cells(rowIdx, COL_DPITCH).value)
                    endNote = "[marker " & target & "]"
                End If

                LogP7 "  " & stepLabel & " CUBIC slew to (" & _
                      Format(endYaw, "0.0") & ChrW(176) & ", " & _
                      Format(endPitch, "0.0") & ChrW(176) & ") " & endNote & _
                      ", ts=" & tsStr & " te=" & teStr
                segCount = segCount + 1

            Case "TRACK"
                Dim tgtT As String
                tgtT = LCase(Trim(CStr(ws.Cells(rowIdx, COL_TARGET).value)))
                Dim oyT As Double, opT As Double
                oyT = SafeDouble(ws.Cells(rowIdx, COL_DYAW).value)
                opT = SafeDouble(ws.Cells(rowIdx, COL_DPITCH).value)
                LogP7 "  " & stepLabel & " TrackInterval mode=F obj=" & tgtT & _
                      " offY=" & Format(oyT, "0.0") & _
                      " offP=" & Format(opT, "0.0") & _
                      ", ts=" & tsStr & " te=" & teStr
                intervalCount = intervalCount + 1

            Case "TRACK-YAW"
                Dim tgtY As String
                tgtY = LCase(Trim(CStr(ws.Cells(rowIdx, COL_TARGET).value)))
                Dim oyY As Double, rpAbs As Double
                oyY = SafeDouble(ws.Cells(rowIdx, COL_DYAW).value)
                rpAbs = SafeDouble(ws.Cells(rowIdx, COL_RP).value)
                LogP7 "  " & stepLabel & " TrackInterval mode=Y obj=" & tgtY & _
                      " offY=" & Format(oyY, "0.0") & _
                      " pitchAbs=" & Format(rpAbs, "0.0") & _
                      ", ts=" & tsStr & " te=" & teStr
                intervalCount = intervalCount + 1

            Case Else
                LogP7 "  " & stepLabel & " UNHANDLED action '" & action & _
                      "' (validation should have caught this)"
        End Select
    Next i
End Sub


' ============================================================
' Evaluate astro object position at given time, in gimbal frame.
' Returns True if above horizon (per Astro.bas convention).
' Maps Plan-side target names to Astro.bas function names:
'   sun  -> GetSunGimbalAngles
'   moon -> GetMoonGimbalAngles
'   gc   -> GetGCGimbalAngles    (workfront #67)
'   mw   -> GetGCGimbalAngles    (back-compat per #67 Phase 1)
' ============================================================
' Public so the interval pusher (TrackPlanPush) can compute absolute
' astro Move endpoints - a Move to an astro point needs the object's
' pose at the fire time, same evaluator the preview/decompose use.
Public Function EvalAstro(ByVal target As String, ByVal atTime As Double, _
                            ByVal cartHeading As Double, _
                            ByRef yaw As Double, ByRef pitch As Double) As Boolean
    ' Direct call (not Application.Run) so ByRef yaw/pitch propagate
    ' back to caller. Day 21 bug: Application.Run copies args by value
    ' across the Run boundary, so the function's writes never reach
    ' EvalAstro's caller. Direct call binds correctly at compile time.
    Dim t As String: t = LCase(Trim(target))
    Dim ok As Boolean: ok = False
    Select Case t
        Case "sun"
            ok = Astro.GetSunGimbalAngles(CDate(atTime), cartHeading, yaw, pitch)
        Case "moon"
            ok = Astro.GetMoonGimbalAngles(CDate(atTime), cartHeading, yaw, pitch)
        Case "gc", "mw"
            ok = Astro.GetGCGimbalAngles(CDate(atTime), cartHeading, yaw, pitch)
        ' Event-locked targets: aim at the body's position AT THE EVENT TIME,
        ' independent of the row's fire-time (atTime is ignored here). The
        ' event times are the same workbook named ranges the Fires-at formula
        ' uses (full date-time serials).
        Case "sunset"
            ok = EvalAstroAtEvent("sun", "dataSunsetTime", cartHeading, yaw, pitch)
        Case "sunrise"
            ok = EvalAstroAtEvent("sun", "dataSunriseTime", cartHeading, yaw, pitch)
        Case "moonrise"
            ok = EvalAstroAtEvent("moon", "dataMoonriseTime", cartHeading, yaw, pitch)
        Case "moonset"
            ok = EvalAstroAtEvent("moon", "dataMoonsetTime", cartHeading, yaw, pitch)
        Case "gcrise"
            ok = EvalAstroAtEvent("gc", "dataGCRiseTime", cartHeading, yaw, pitch)
        Case "gcset"
            ok = EvalAstroAtEvent("gc", "dataGCSetTime", cartHeading, yaw, pitch)
    End Select
    EvalAstro = ok
End Function

' ============================================================
' Event-locked astro resolution. An event word (sunset, sunrise,
' moonrise, moonset, gcrise, gcset) aims at the body's position AT THE
' NAMED EVENT TIME, not at the row's fire-time. Reuses the same
' Astro.bas evaluators (single source of truth for the ephemeris).
' Reads the event time from the workbook named range - the same names
' the Fires-at formula uses, each a full date-time serial. Returns False
' if the name is missing/empty/non-date or the body is below the horizon.
' ============================================================
Private Function EvalAstroAtEvent(ByVal body As String, ByVal nm As String, _
                                  ByVal cartHeading As Double, _
                                  ByRef yaw As Double, ByRef pitch As Double) As Boolean
    On Error GoTo fail
    Dim v As Variant
    v = ThisWorkbook.names(nm).RefersToRange.value
    If Not IsDate(v) Then GoTo fail
    Dim et As Date: et = CDate(v)
    Select Case body
        Case "sun"
            EvalAstroAtEvent = Astro.GetSunGimbalAngles(et, cartHeading, yaw, pitch)
        Case "moon"
            EvalAstroAtEvent = Astro.GetMoonGimbalAngles(et, cartHeading, yaw, pitch)
        Case "gc"
            EvalAstroAtEvent = Astro.GetGCGimbalAngles(et, cartHeading, yaw, pitch)
    End Select
    Exit Function
fail:
    EvalAstroAtEvent = False
End Function


' Read cart heading from Settings (degrees, 0=North). Falls back
' to 0 if name missing. Per Day-21 discussion: this is the
' shoot-start heading, set by operator, not live telemetry -
' Excel has no return channel from the cart.
Private Function ReadCartHeading() As Double
    On Error GoTo Defaulting
    Dim v As Variant
    v = ThisWorkbook.Sheets("Settings").Range("dataCartHeading").value
    If IsNumeric(v) Then
        ReadCartHeading = CDbl(v)
    Else
        ReadCartHeading = 0
    End If
    Exit Function
Defaulting:
    ReadCartHeading = 0
End Function


' Format a Fires-at value (Excel time serial) as HH:MM. Blanks
' and non-numerics render as "(blank)".
Private Function FmtTime(ByVal v As Variant) As String
    If IsEmpty(v) Then FmtTime = "(blank)": Exit Function
    If Not IsNumeric(v) Then FmtTime = "(blank)": Exit Function
    FmtTime = Format(CDate(v), "HH:nn")
End Function


' Safe Double parse - 0 for blank/non-numeric.
Private Function SafeDouble(ByVal v As Variant) As Double
    If IsEmpty(v) Then SafeDouble = 0: Exit Function
    If IsNumeric(v) Then SafeDouble = CDbl(v) Else SafeDouble = 0
End Function


' ============================================================
' Validate one row. Returns "" if clean, else a semicolon-
' separated string of error descriptions.
' ============================================================
Private Function ValidateOneRow(ByVal ws As Worksheet, ByVal r As Long) As String
    Dim errs As String: errs = ""

    Dim firesAt As Variant
    firesAt = ws.Cells(r, COL_FIRES_AT).value

    Dim action As String
    action = UCase(Trim(CStr(ws.Cells(r, COL_ACTION).value)))

    Dim target As String
    target = LCase(Trim(CStr(ws.Cells(r, COL_TARGET).value)))

    Dim rate As String
    rate = Trim(CStr(ws.Cells(r, COL_RATE).value))

    Dim ry As Variant: ry = ws.Cells(r, COL_RY).value
    Dim rp As Variant: rp = ws.Cells(r, COL_RP).value

    ' --- Check 1: Fires at resolved ---
    ' Could be blank, "" from the IF formula's else branch, or an
    ' Excel error value. All mean "anchor didn't resolve."
    If Not IsNumeric(firesAt) Then
        errs = AppendErr(errs, "anchor unresolved (Fires at blank/error)")
    End If

    ' --- Check 2: Action recognised ---
    Select Case action
        Case "PAN FOLLOW", "LOCK", "MOVE", "TRACK", "TRACK-YAW", "END"
            ' OK
        Case ""
            errs = AppendErr(errs, "Action blank")
        Case Else
            errs = AppendErr(errs, "Action '" & _
                CStr(ws.Cells(r, COL_ACTION).value) & "' not recognised " & _
                "(expected: Pan Follow, Lock, Move, Track, Track-yaw, END)")
    End Select

    ' --- Action-specific checks ---
    Select Case action
        Case "PAN FOLLOW"
            If Not IsTargetBlank(target) Then
                errs = AppendErr(errs, "Pan Follow: Target should be blank/" & EmDash())
            End If
            ' Rate is informational only; no requirement.

        Case "LOCK"
            If Not IsTargetBlank(target) Then
                errs = AppendErr(errs, "Lock: Target should be blank/" & EmDash())
            End If

        Case "MOVE"
            If IsTargetBlank(target) Then
                errs = AppendErr(errs, "Move: Target required (marker or astro)")
            End If
            If Not IsRateValid(rate) Then
                errs = AppendErr(errs, "Move: Rate required " & _
                    "(use a band name or 'Computed')")
            End If
            ' Ry/Rp: marker target needs both; astro target computes from track_<obj>
            If Not IsAstroTarget(target) And Not IsTargetBlank(target) Then
                If Not IsAngleValid(ry) Then
                    errs = AppendErr(errs, "Move (marker): Ry blank")
                End If
                If Not IsAngleValid(rp) Then
                    errs = AppendErr(errs, "Move (marker): Rp blank")
                End If
            End If

        Case "TRACK"
            If Not IsAstroTarget(target) Then
                errs = AppendErr(errs, "Track: Target must be sun/moon/mw")
            End If
            If Not IsRateValid(rate) Then
                errs = AppendErr(errs, "Track: Rate required")
            End If

        Case "TRACK-YAW"
            If Not IsAstroTarget(target) Then
                errs = AppendErr(errs, "Track-yaw: Target must be sun/moon/mw")
            End If
            If Not IsRateValid(rate) Then
                errs = AppendErr(errs, "Track-yaw: Rate required")
            End If
            If Not IsAngleValid(rp) Then
                errs = AppendErr(errs, "Track-yaw: Rp required (held pitch)")
            End If

        Case "END"
            If Not IsTargetBlank(target) Then
                errs = AppendErr(errs, "END: Target should be blank/" & EmDash())
            End If
    End Select

    ValidateOneRow = errs
End Function


' ============================================================
' Helpers - predicates
' ============================================================

' Treats "", "-", and various dash characters as blank.
' Hardcoding em-dash by ChrW since literal "-" doesn't survive
' .bas round-trips (Day 21 lesson, fixed in PlanAuthoring too).
Private Function IsTargetBlank(ByVal target As String) As Boolean
    Dim t As String: t = Trim(target)
    If t = "" Then IsTargetBlank = True: Exit Function
    If t = "-" Then IsTargetBlank = True: Exit Function
    If t = ChrW(8212) Then IsTargetBlank = True: Exit Function   ' em-dash
    If t = ChrW(8211) Then IsTargetBlank = True: Exit Function   ' en-dash
    IsTargetBlank = False
End Function

' Astro target = the three named objects the cart's track_<obj>
' arrays support (sketch line ~950 TRACK_SEGS_MAX). Anything
' else is treated as a marker.
'
' Plan-side token is "gc" (workfront #67 Phase 1). We also accept
' "mw" defensively - the cart wire protocol still uses "mw", and
' a pre-rename plan or copy-paste from older notes might carry it.
Public Function IsAstroTarget(ByVal target As String) As Boolean
    ' Event-locked words (sunset/sunrise/moonrise/moonset/gcrise/gcset) are
    ' also astro targets - they resolve to the body's position at that event
    ' time (see EvalAstro / EvalAstroAtEvent), not at the row's fire-time.
    Select Case LCase(Trim(target))
        Case "sun", "moon", "gc", "mw", _
             "sunset", "sunrise", "moonrise", "moonset", "gcrise", "gcset"
            IsAstroTarget = True
        Case Else
            IsAstroTarget = False
    End Select
End Function

' Rate cell - non-blank string. Don't enforce band-name membership
' here (operator may use a custom value); just non-blank, non-dash.
Private Function IsRateValid(ByVal rate As String) As Boolean
    Dim t As String: t = Trim(rate)
    If t = "" Then IsRateValid = False: Exit Function
    If t = "-" Then IsRateValid = False: Exit Function
    If t = ChrW(8212) Then IsRateValid = False: Exit Function
    IsRateValid = True
End Function

' Angle cell (Ry, Rp). Must be a number; blank or dash = invalid.
Private Function IsAngleValid(ByVal v As Variant) As Boolean
    If IsEmpty(v) Then IsAngleValid = False: Exit Function
    If IsNumeric(v) Then IsAngleValid = True: Exit Function
    IsAngleValid = False
End Function

' Append an error message to the row's error string,
' semicolon-separated.
Private Function AppendErr(ByVal cur As String, ByVal msg As String) As String
    If cur = "" Then
        AppendErr = msg
    Else
        AppendErr = cur & "; " & msg
    End If
End Function

' Em-dash returned via ChrW so the .bas source stays ASCII -
' avoids encoding loss during VBE export/import round-trips.
' Same pattern used in PlanAuthoring.bas (Day 21 lesson).
Private Function EmDash() As String
    EmDash = ChrW(8212)
End Function


' ============================================================
' Read the dry-run flag from Settings. Defaults to TRUE
' (the safer choice) if the name is missing or unreadable -
' no scenario where missing-name should surprise the operator
' with a real cart push.
' ============================================================
Private Function ReadDryRunFlag() As Boolean
    On Error GoTo Defaulting

    Dim v As Variant
    v = ThisWorkbook.Sheets("Settings").Range("dataPlanPushDryRun").value

    If IsEmpty(v) Then
        ReadDryRunFlag = True
        Exit Function
    End If

    ReadDryRunFlag = CBool(v)
    Exit Function

Defaulting:
    ReadDryRunFlag = True
End Function


' ============================================================
' Log helper - writes to the Log sheet via Utils.LogEvent.
' Silent if Utils isn't loaded.
' ============================================================
Private Sub LogP7(ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", LOG_CATEGORY, msg
    On Error GoTo 0
End Sub


' ============================================================
' PushPreviewPlanToCart - preview-pose pusher (Step-1 leftover)
'
' Walks the gimbal plan and pushes ONE representative preview pose per
' GP to /settings/previewplan, in order. The operator steps these on
' demand (PREV/NEXT by GP) to verify start/Ry-Cy geometry and to route
' cables against the actual rotations.
'
' Per-GP pose mapping (confirmed Day 24 pt B):
'   Move (marker)  -> Ry+dyaw, Rp+dpitch                (GP-start)
'   Move (astro)   -> EvalAstro(target, fire) + d       (GP-start)
'   Track          -> EvalAstro(target, ts) + d         (GP-start)
'                  +  EvalAstro(target, te) + d         (continuation)
'   Track-yaw      -> EvalAstro(target, ts).yaw+dyaw, pitch=Rp (GP-start)
'                  +  EvalAstro(target, te).yaw+dyaw, pitch=Rp (continuation)
'   Pan Follow     -> dyaw, dpitch  (goto-yaw at current heading) (GP-start)
'   Lock           -> Ry+dyaw, Rp+dpitch  (held bearing)          (GP-start)
'   END            -> previous pose, held                          (GP-start)
'
' A Track GP emits TWO entries (start + end) so the operator sees the
' whole sweep the track will make. Continuations carry &start=0 so the
' future Execution-UI PREV/NEXT hops by GP and steps through them.
'
' Cart contract: /settings/previewplan?idx=N&yaw=&pitch=&label=&start=1|0
'   idx=0 resets; idx must == current count (sequential). Cap = 20.
' Dry-run via Settings!dataPlanPushDryRun, like CartPlanPush/TrackPlanPush.
' ============================================================
Public Sub PushPreviewPlanToCart()
    On Error GoTo ErrHandler

    Dim dryRun As Boolean: dryRun = ReadDryRunFlag()
    Dim mode As String: mode = IIf(dryRun, "DRY RUN", "REAL PUSH")
    LogP7 "--- PushPreviewPlanToCart start (" & mode & ") ---"

    Dim ws As Worksheet: Set ws = ThisWorkbook.Sheets("Plan")
    If Not EnsureCols(ws) Then Exit Sub   ' header-map (fail-loud)
    Dim cartHeading As Double: cartHeading = ReadCartHeading()

    ' Collect populated GP rows in order (for te look-ahead).
    Dim rows() As Long: ReDim rows(0 To PLAN_MAX_ROWS)
    Dim nRows As Long: nRows = 0
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Not IsEmpty(ws.Cells(r, COL_ANCHOR_TYPE).value) Then
            rows(nRows) = r: nRows = nRows + 1
        End If
    Next r
    If nRows = 0 Then
        LogP7 "FAILED: no gimbal plan rows."
        MsgBox "No gimbal plan rows found.", vbExclamation, "PushPreviewPlanToCart"
        Exit Sub
    End If

    ' Build flat preview-pose list (yaw, pitch, label, gp_start).
    Dim pYaw() As Double, pPitch() As Double, pLabel() As String, pStart() As Boolean
    ReDim pYaw(0 To PREVIEW_PLAN_MAX): ReDim pPitch(0 To PREVIEW_PLAN_MAX)
    ReDim pLabel(0 To PREVIEW_PLAN_MAX): ReDim pStart(0 To PREVIEW_PLAN_MAX)
    Dim n As Long: n = 0
    Dim lastY As Double, lastP As Double          ' for END (held) + safety
    Dim errCount As Long: errCount = 0

    Dim i As Long
    For i = 0 To nRows - 1
        Dim rowIdx As Long: rowIdx = rows(i)
        Dim act As String: act = UCase(Trim(CStr(ws.Cells(rowIdx, COL_ACTION).value)))
        Dim lbl As String: lbl = Left$(CStr(ws.Cells(rowIdx, COL_STEP).value), 11)
        Dim tgt As String: tgt = LCase(Trim(CStr(ws.Cells(rowIdx, COL_TARGET).value)))
        Dim dyaw As Double: dyaw = SafeDouble(ws.Cells(rowIdx, COL_DYAW).value)
        Dim dpit As Double: dpit = SafeDouble(ws.Cells(rowIdx, COL_DPITCH).value)
        Dim ts As Double: ts = SafeDouble(ws.Cells(rowIdx, COL_FIRES_AT).value)
        Dim te As Double
        If i < nRows - 1 Then te = SafeDouble(ws.Cells(rows(i + 1), COL_FIRES_AT).value) Else te = ts

        Dim y As Double, p As Double, y2 As Double, p2 As Double
        Dim hasCont As Boolean: hasCont = False

        Select Case act
            Case "MOVE"
                If IsAstroTarget(tgt) Then
                    If Not EvalAstro(tgt, ts, cartHeading, y, p) Then _
                        LogP7 "  NOTE " & lbl & ": astro '" & tgt & "' below horizon at fire time"
                    y = y + dyaw: p = p + dpit
                Else
                    y = SafeDouble(ws.Cells(rowIdx, COL_RY).value) + dyaw
                    p = SafeDouble(ws.Cells(rowIdx, COL_RP).value) + dpit
                End If

            Case "TRACK"
                If Not EvalAstro(tgt, ts, cartHeading, y, p) Then _
                    LogP7 "  NOTE " & lbl & ": astro '" & tgt & "' below horizon at ts"
                y = y + dyaw: p = p + dpit
                If Not EvalAstro(tgt, te, cartHeading, y2, p2) Then _
                    LogP7 "  NOTE " & lbl & ": astro '" & tgt & "' below horizon at te"
                y2 = y2 + dyaw: p2 = p2 + dpit
                hasCont = True

            Case "TRACK-YAW"
                Dim rp As Double: rp = SafeDouble(ws.Cells(rowIdx, COL_RP).value)
                If Not EvalAstro(tgt, ts, cartHeading, y, p) Then _
                    LogP7 "  NOTE " & lbl & ": astro '" & tgt & "' below horizon at ts"
                y = y + dyaw: p = rp
                If Not EvalAstro(tgt, te, cartHeading, y2, p2) Then _
                    LogP7 "  NOTE " & lbl & ": astro '" & tgt & "' below horizon at te"
                y2 = y2 + dyaw: p2 = rp
                hasCont = True

            Case "PAN FOLLOW"
                y = dyaw: p = dpit          ' goto-yaw at current heading

            Case "LOCK"
                y = SafeDouble(ws.Cells(rowIdx, COL_RY).value) + dyaw
                p = SafeDouble(ws.Cells(rowIdx, COL_RP).value) + dpit

            Case "END"
                y = lastY: p = lastP        ' held = previous pose

            Case Else
                LogP7 "  skip " & lbl & ": action '" & act & "' has no preview pose"
                GoTo NextRow
        End Select

        ' Emit GP-start entry.
        If n > PREVIEW_PLAN_MAX - 1 Then
            LogP7 "  ERROR: preview poses exceed PREVIEW_PLAN_MAX=" & PREVIEW_PLAN_MAX
            errCount = errCount + 1
            GoTo DonePruning
        End If
        pYaw(n) = y: pPitch(n) = p: pLabel(n) = lbl: pStart(n) = True
        lastY = y: lastP = p
        LogP7 "  GP-start " & lbl & " (" & act & ") yaw=" & Format(y, "0.0") & _
              " pitch=" & Format(p, "0.0")
        n = n + 1

        ' Emit continuation entry for Track GPs (end-of-sweep pose).
        If hasCont Then
            If n > PREVIEW_PLAN_MAX - 1 Then
                LogP7 "  ERROR: preview poses exceed PREVIEW_PLAN_MAX=" & PREVIEW_PLAN_MAX
                errCount = errCount + 1
                GoTo DonePruning
            End If
            pYaw(n) = y2: pPitch(n) = p2: pLabel(n) = Left$(lbl & "e", 11): pStart(n) = False
            lastY = y2: lastP = p2
            LogP7 "    continuation " & pLabel(n) & " yaw=" & Format(y2, "0.0") & _
                  " pitch=" & Format(p2, "0.0")
            n = n + 1
        End If
NextRow:
    Next i

DonePruning:
    If errCount > 0 Then
        LogP7 "FAILED: " & errCount & " error(s). Aborting."
        MsgBox errCount & " preview error(s). See Log.", vbExclamation, "PushPreviewPlanToCart"
        Exit Sub
    End If
    If n = 0 Then
        LogP7 "No preview poses built."
        MsgBox "No preview poses built from the plan.", vbInformation, "PushPreviewPlanToCart"
        Exit Sub
    End If
    LogP7 "Built " & n & " preview pose(s)."

    If dryRun Then
        LogP7 "--- PushPreviewPlanToCart end (DRY RUN, not sent) ---"
        MsgBox "DRY RUN: " & n & " preview pose(s) built, not sent." & vbCrLf & _
               "See Log for the per-pose breakdown.", vbInformation, "PushPreviewPlanToCart"
        Exit Sub
    End If

    Dim arduinoIP As String: arduinoIP = ReadArduinoIPPP()
    If arduinoIP = "" Then
        MsgBox "Cart IP not set in Settings.", vbExclamation, "PushPreviewPlanToCart": Exit Sub
    End If
    If Not CartAlivePP(arduinoIP) Then
        LogP7 "ABORT: cart /status no response at " & arduinoIP
        MsgBox "Cart not responding at " & arduinoIP & ". Push aborted.", _
               vbExclamation, "PushPreviewPlanToCart": Exit Sub
    End If

    Dim http As Object: Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    Dim k As Long, okAll As Boolean: okAll = True
    For k = 0 To n - 1
        Dim url As String
        url = arduinoIP & "/settings/previewplan?idx=" & k & _
              "&yaw=" & Format(pYaw(k), "0.00") & _
              "&pitch=" & Format(pPitch(k), "0.00") & _
              "&label=" & pLabel(k) & _
              "&start=" & IIf(pStart(k), "1", "0")
        LogP7 "GET " & url
        Dim sc As Long, resp As String
        On Error Resume Next
        http.Open "GET", url, False
        http.Send
        sc = http.Status
        resp = CStr(http.responseText)
        On Error GoTo ErrHandler
        If sc = 200 Then
            LogP7 "  OK " & resp
        Else
            LogP7 "  HTTP " & sc & " " & resp: okAll = False: Exit For
        End If
    Next k

    If okAll Then
        LogP7 "--- PushPreviewPlanToCart end (REAL PUSH, " & n & " poses) ---"
        MsgBox n & " preview pose(s) pushed. Step with PREV/NEXT (or /preview/step).", _
               vbInformation, "PushPreviewPlanToCart"
    Else
        MsgBox "Preview push failed mid-way. See Log.", vbExclamation, "PushPreviewPlanToCart"
    End If
    Exit Sub

ErrHandler:
    LogP7 "ERROR: " & Err.Description
    MsgBox "Error in PushPreviewPlanToCart:" & vbCrLf & vbCrLf & Err.Description, _
           vbCritical, "PushPreviewPlanToCart"
End Sub

' Transport (preview pusher) - PlanPush had no Phase-4 transport; these
' mirror CartPlanPush/TrackPlanPush. Suffixed PP to avoid clashing with
' any same-named privates if modules are later merged.
Private Function ReadArduinoIPPP() As String
    On Error Resume Next
    Dim ip As String
    ip = Trim(CStr(ThisWorkbook.Sheets("Settings").Range("dataArduinoIP").value))
    On Error GoTo 0
    If ip = "" Then
        ReadArduinoIPPP = ""
    Else
        If LCase(Left(ip, 7)) <> "http://" Then ip = "http://" & ip
        ReadArduinoIPPP = ip
    End If
End Function

Private Function CartAlivePP(ByVal arduinoIP As String) As Boolean
    Dim http As Object: Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    On Error Resume Next
    http.Open "GET", arduinoIP & "/status", False
    http.Send
    CartAlivePP = (http.Status = 200)
    On Error GoTo 0
End Function
