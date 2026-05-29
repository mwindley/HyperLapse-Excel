Attribute VB_Name = "PlanPush"
' ============================================================
' HyperLapse Cart — Plan Push (P7)
'
' Reads the middle-zone Gimbal Plan and pushes it to the cart
' as a sequence of plan segments + TrackIntervals + (optionally)
' cubic path coefficients.
'
' Public entry:
'   PushGimbalPlan — Stage 2. Reads dataPlanPushDryRun, runs
'                    Phase 1 validation, reports collected errors.
'                    No decomposition or push yet.
'
' Stages (per Session E P7 design):
'   1. Validate    — walk middle zone, collect errors, abort if any   [STAGE 2]
'   2. Prerequisite — ensure track_<obj> cubics are loaded            [STAGE 3]
'   3. Decompose   — each Plan row → cart-side segments + intervals   [STAGE 3]
'   4. POST        — sequential GETs to cart endpoints                [STAGE 4]
'   5. Summary     — report counts, log to Log sheet                  [Stage 5]
'
' Dry-run mode (Settings!dataPlanPushDryRun = TRUE):
'   Phases 1-3 + 5 run. Phase 4 is skipped. Cart not contacted.
'   Use during plan authoring or while hardware is offline.
'
' Real push mode (Settings!dataPlanPushDryRun = FALSE):
'   Pings cart /status first; aborts cleanly if no response.
'   All five phases run. Tells operator what was pushed.
'
' Day 21 (Session F) — Stage 1 skeleton.
' Day 21 (Session F) — Stage 2 Phase 1 validation added.
' Day 21 (Session F) — workfront #67 Phase 1: IsAstroTarget
' accepts "gc" (new Plan token) and "mw" (cart wire protocol /
' back-compat).
' Day 21 (Session F) — Stage 3 Phase 3 decompose added. One Log
' line per row describing the cart-side artifact (segment or
' TrackInterval). Astro endpoints evaluated via Astro.bas in
' dry-run. Cubic coefficient computation deferred — Stage 3 emits
' only endpoint + duration summary, not the curve coefficients.
' ============================================================

Option Explicit

' Plan sheet middle-zone columns (Session E layout)
Private Const PLAN_FIRST_ROW As Long = 6
Private Const PLAN_MAX_ROWS  As Long = 60

' Middle-zone column numbers
Private Const COL_STEP        As Long = 13  ' M
Private Const COL_ANCHOR_TYPE As Long = 14  ' N
Private Const COL_ANCHOR_REF  As Long = 15  ' O
Private Const COL_OFFSET      As Long = 16  ' P
Private Const COL_FIRES_AT    As Long = 17  ' Q
Private Const COL_TOTAL_DUR   As Long = 18  ' R
Private Const COL_ACTION      As Long = 19  ' S
Private Const COL_TARGET      As Long = 20  ' T
Private Const COL_RATE        As Long = 21  ' U
Private Const COL_RY          As Long = 22  ' V
Private Const COL_RP          As Long = 23  ' W
Private Const COL_DYAW        As Long = 24  ' X
Private Const COL_DPITCH      As Long = 25  ' Y
Private Const COL_EASE        As Long = 26  ' Z
Private Const COL_MOVE_T      As Long = 27  ' AA
Private Const COL_NOTE        As Long = 28  ' AB

Private Const LOG_CATEGORY As String = "P7"

' Cart-side track interval slot limit (sketch TRACK_PLAN_MAX,
' line ~951 on Giga v2). Plan validation warns if exceeded.
Private Const TRACK_PLAN_MAX As Long = 10


' ============================================================
' Public — PushGimbalPlan
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
    ' (Phase 2 prerequisites — track_<obj> push — is moot in dry-run
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
' Phase 1 — Validate
' Walks middle zone, emits one Log line per row with errors,
' returns total count of rows that had at least one error.
'
' Plan-level checks (across rows):
'   - At least one populated row
'   - Last populated row's Action must be END
'   - No populated rows after the END row (END is the sentinel)
'
' Row-level checks (per populated row):
'   - Fires at (col Q) not blank/error  — anchor resolved
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
' Phase 3 — Decompose
' Walks middle-zone rows in order, emits one Log line per row
' describing the cart-side artifact(s) that would be pushed.
' Increments segCount / intervalCount as it goes.
'
' Per Session E decomposition table:
'   Pan Follow     -> PANFOLLOW segment, ts..te
'   Lock           -> HOLD segment at current pose, ts..te
'   Move (marker)  -> CUBIC slew to (Ry+Δyaw, Rp+Δpitch), ts..te
'   Move (astro)   -> CUBIC slew to (yaw, pitch) from astro eval, ts..te
'   Track full     -> TrackInterval mode=F, ts..te, obj, offY, offP
'   Track-yaw      -> TrackInterval mode=Y, ts..te, obj, offY, Rp(abs)
'   END            -> no segment (provides te for previous row)
'
' Dry-run notes:
'   - Astro endpoint preview uses Astro.bas direct astronomy
'     (small residual vs. cart's fitted-cubic eval; ~7px at 14mm
'     per WORKFRONTS #58, below visible threshold).
'   - Cubic coefficients NOT computed in Stage 3 (deferred — needs
'     ease-band -> frames -> seconds conversion which isn't built).
'     Each CUBIC line just states endpoint + duration.
' ============================================================
Private Sub Phase3Decompose(ByVal ws As Worksheet, _
                             ByRef segCount As Long, _
                             ByRef intervalCount As Long)
    segCount = 0
    intervalCount = 0

    ' Read cart heading once — used by every astro-target eval
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
                    ' Astro snapshot — evaluate at ts (Fires-at)
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
                    ' Marker — use authored Ry/Rp + deltas
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
Private Function EvalAstro(ByVal target As String, ByVal atTime As Double, _
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
    End Select
    EvalAstro = ok
End Function


' Read cart heading from Settings (degrees, 0=North). Falls back
' to 0 if name missing. Per Day-21 discussion: this is the
' shoot-start heading, set by operator, not live telemetry —
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


' Safe Double parse — 0 for blank/non-numeric.
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
' Helpers — predicates
' ============================================================

' Treats "", "-", and various dash characters as blank.
' Hardcoding em-dash by ChrW since literal "—" doesn't survive
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
' "mw" defensively — the cart wire protocol still uses "mw", and
' a pre-rename plan or copy-paste from older notes might carry it.
Private Function IsAstroTarget(ByVal target As String) As Boolean
    Select Case LCase(Trim(target))
        Case "sun", "moon", "gc", "mw"
            IsAstroTarget = True
        Case Else
            IsAstroTarget = False
    End Select
End Function

' Rate cell — non-blank string. Don't enforce band-name membership
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

' Em-dash returned via ChrW so the .bas source stays ASCII —
' avoids encoding loss during VBE export/import round-trips.
' Same pattern used in PlanAuthoring.bas (Day 21 lesson).
Private Function EmDash() As String
    EmDash = ChrW(8212)
End Function


' ============================================================
' Read the dry-run flag from Settings. Defaults to TRUE
' (the safer choice) if the name is missing or unreadable —
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
' Log helper — writes to the Log sheet via Utils.LogEvent.
' Silent if Utils isn't loaded.
' ============================================================
Private Sub LogP7(ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", LOG_CATEGORY, msg
    On Error GoTo 0
End Sub
