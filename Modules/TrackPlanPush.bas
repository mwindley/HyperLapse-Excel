Attribute VB_Name = "TrackPlanPush"
' ============================================================
' HyperLapse Cart - Track Plan Push (Day 24)
'
' Reads the middle-zone Gimbal Plan, finds Track / Track-yaw / Pan Follow
' / Move GPs, and pushes them to the cart as TrackIntervals via
'   /settings/trackplan?idx=N&ts=&te=&obj=S|M|W|N&mode=F|Y|P|M&offy=&offp=&acquire=&awp=&offms=
'
' mode P (Pan Follow): cart eases ONCE to offy (goto-yaw) then goes
'   silent so the Ronin's own Pan Follow takes over. obj=N (unused).
' mode M (Move): offy/offp are the ABSOLUTE endpoint pose (astro ->
'   EvalAstro(fire)+d, marker -> Ry/Rp+d). Cart eases (S-curve) to it
'   then HOLDS. obj=N (unused). Needs PlanPush.EvalAstro (Public).
'
' This is the interval TABLE push (which object to follow, when).
' It pairs with the proven cart-side track executor (#5a) and
' AstroPush.PushTrackPathsToCart (which pushes the cubic PATHS).
' Run order at execution: push cubics (AstroPush) -> push intervals
' (this) -> /track/start.
'
' Time model: cart interval windows are ms-from-shoot-start. Shoot
' t=0 = the FIRST GP's Fires-at (col Q). Each interval ts/te is
' converted (excel_time - plan_start) * 86400 * 1000 ms. (Cart
' evaluates the astro CUBIC at real time per Model B; the interval
' WINDOW stays shoot-relative - cart runs whenever.)
'
' Public entry:
'   PushTrackPlanToCart - validate-light, build intervals, dry-run
'                         or real push. Mirrors CartPlanPush style.
'
' Cart cap: TRACK_PLAN_MAX = 10 intervals.
'
' Day 28 - ease/sunset fix. Two faults stopped Phase-A ease working:
'   (a) the sun-time cells are date-typed; SafeNum() gated on IsNumeric(),
'       which is False for a date, so sunset/sunrise read 0 -> cadence 0
'       -> ease forced to snap. Now read via CellSerial() (IsDate-aware).
'   (b) Fires-at is stored time-of-day only while sun times carry a date.
'       All fire times and sun-event times are now placed on ONE dated
'       timeline anchored at the shoot evening, with sunrise rolled to the
'       end-of-shoot morning, so the overnight (evening->past midnight->
'       next morning) windows and the sunrise-branch cadence are correct.
'   GetSunsetTime is NOT touched - this is read-time normalisation only.
' ============================================================

Option Explicit

Private Const PLAN_FIRST_ROW  As Long = 6
Private Const PLAN_MAX_ROWS   As Long = 60

' Middle-zone columns (mirror PlanPush.bas)
Private Const COL_ANCHOR_TYPE As Long = 14  ' N
Private Const COL_ANCHOR_REF  As Long = 15  ' O  (WP id / astro / time ref)
Private Const COL_OFFSET_MIN  As Long = 16  ' P  (offset in MINUTES; col Q uses P/1440)
Private Const COL_FIRES_AT    As Long = 17  ' Q
Private Const COL_ACTION      As Long = 19  ' S
Private Const COL_TARGET      As Long = 20  ' T
Private Const COL_RY          As Long = 22  ' V  (ref yaw, for marker Move)
Private Const COL_RP          As Long = 23  ' W
Private Const COL_DYAW        As Long = 24  ' X
Private Const COL_DPITCH      As Long = 25  ' Y
Private Const COL_EASE        As Long = 26  ' Z  (ease band name)

Private Const TRACK_PLAN_MAX  As Long = 10
Private Const LOG_CATEGORY    As String = "TRACKPLAN"


Public Sub PushTrackPlanToCart()
    On Error GoTo ErrHandler

    Dim dryRun As Boolean
    dryRun = ReadDryRunFlag()
    Dim mode As String
    mode = IIf(dryRun, "DRY RUN", "REAL PUSH")
    LogTP "--- PushTrackPlanToCart start (" & mode & ") ---"
    LogTP "  (build: Day28 dated-timeline ease fix)"
    LogTP "  (build: Day29 Phase-1 WP-event binding -- tail tokens awp/offms)"

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Plan")

    ' --- Collect populated GP rows in order; find shoot t=0 ---
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

    If nRows = 0 Then
        LogTP "FAILED: no gimbal plan rows."
        MsgBox "No gimbal plan rows found.", vbExclamation, "PushTrackPlanToCart"
        Exit Sub
    End If

    ' --- Shoot timeline + cadence context for Phase-A acquire (acquire_ms =
    ' ease_frames x cadence_sec). Cadence comes from the design's own exposure
    ' model (FormulaTv -> CalcInterval at each GP's fire time). Event times are
    ' cached in Settings by Get Sunset Time; if absent, cadence resolves 0 and
    ' acquire_ms is pushed as 0 (cart falls back to no-ease snap).
    '
    ' Day 28: read the event times date-tolerantly (CellSerial, not SafeNum -
    ' the cells are date-typed and IsNumeric() rejects a date) and build ONE
    ' dated timeline so the overnight shoot is consistent. baseDate = the
    ' shoot's start date (the date stored on the sunset cell). dayAnchor = the
    ' earliest of shoot-start and sunset clock; any clock time earlier than
    ' that is rolled to the next calendar day (early-morning fires, and the
    ' end-of-shoot sunrise). That gives fireTime - sunriseT the negative sign
    ' FormulaTv's sunrise branch expects in deep night. ---
    Dim branch As String
    Dim sunsetRaw As Double, sunriseRaw As Double, duskRaw As Double
    On Error Resume Next
    branch = CStr(ThisWorkbook.Sheets("Settings").Range("dataActiveBranch").value)
    sunsetRaw = CellSerial(ThisWorkbook.Sheets("Settings").Range("dataSunsetTime").value)
    sunriseRaw = CellSerial(ThisWorkbook.Sheets("Settings").Range("dataSunriseTime").value)
    duskRaw = CellSerial(ThisWorkbook.Sheets("Settings").Range("dataAstroDusk").value)
    On Error GoTo ErrHandler
    If Trim(branch) = "" Then branch = "default"

    Dim planStartRaw As Double
    planStartRaw = CellSerial(ws.Cells(rows(0), COL_FIRES_AT).value)

    ' Dated timeline. datesOK gates it; if sun times are missing we fall back
    ' to the old time-of-day behaviour (baseDate/dayAnchor stay 0, so the
    ' StampClock calls return plain time-of-day and cadence resolves 0).
    Dim datesOK As Boolean
    Dim baseDate As Double, dayAnchor As Double
    Dim sunsetT As Double, sunriseT As Double, astroDuskT As Double
    datesOK = (sunsetRaw > 0 And sunriseRaw > 0)
    If datesOK Then
        baseDate = Int(sunsetRaw)
        Dim sunsetClock As Double: sunsetClock = sunsetRaw - Int(sunsetRaw)
        Dim startClock As Double:  startClock = planStartRaw - Int(planStartRaw)
        dayAnchor = sunsetClock
        If startClock < dayAnchor Then dayAnchor = startClock
        sunsetT = baseDate + sunsetClock
        astroDuskT = StampClock(duskRaw - Int(duskRaw), baseDate, dayAnchor)
        sunriseT = StampClock(sunriseRaw - Int(sunriseRaw), baseDate, dayAnchor)
    Else
        LogTP "  NOTE: sunset/sunrise times not set -- acquire_ms will push 0 (no ease). Run Get Sunset Time to enable Phase-A ease."
    End If

    Dim planStart As Double
    planStart = StampClock(planStartRaw - Int(planStartRaw), baseDate, dayAnchor)

    ' Cart heading for absolute astro Move endpoints (EvalAstro needs it).
    Dim cartHeading As Double
    On Error Resume Next
    cartHeading = SafeNum(ThisWorkbook.Sheets("Settings").Range("dataCartHeading").value)
    On Error GoTo ErrHandler

    ' --- Build interval records from Track / Track-yaw rows ---
    Dim ivIdx() As Long, ivTs() As Double, ivTe() As Double
    Dim ivObj() As String, ivMode() As String, ivOffY() As Double, ivOffP() As Double
    ReDim ivIdx(0 To TRACK_PLAN_MAX): ReDim ivTs(0 To TRACK_PLAN_MAX)
    ReDim ivTe(0 To TRACK_PLAN_MAX): ReDim ivObj(0 To TRACK_PLAN_MAX)
    ReDim ivMode(0 To TRACK_PLAN_MAX): ReDim ivOffY(0 To TRACK_PLAN_MAX)
    ReDim ivOffP(0 To TRACK_PLAN_MAX)
    Dim ivAcq() As Double: ReDim ivAcq(0 To TRACK_PLAN_MAX)  ' Phase-A ease ms
    ' Phase-1 WP-event binding: carry the anchor WP number + offset(ms) so the
    ' cart can fire each GP off the cart's ACTUAL WP arrival, not the pushed
    ' clock. awp = 0 means "not WP-anchored" (TIME/ASTRO) -> cart uses ts/te.
    Dim ivAwp() As Long:   ReDim ivAwp(0 To TRACK_PLAN_MAX)
    Dim ivOffMs() As Double: ReDim ivOffMs(0 To TRACK_PLAN_MAX)
    ' #40 1a: expected cart heading (Plan col H, deg CW+) per earth-frame GP.
    ' ivHasEh gates the &eh= token; 0 is a valid heading (North) so a
    ' separate "has" flag, not a sentinel value, marks "no expected heading".
    Dim ivEh() As Double:     ReDim ivEh(0 To TRACK_PLAN_MAX)
    Dim ivHasEh() As Boolean: ReDim ivHasEh(0 To TRACK_PLAN_MAX)
    Dim n As Long: n = 0
    Dim errCount As Long: errCount = 0

    Dim i As Long
    For i = 0 To nRows - 1
        Dim rowIdx As Long: rowIdx = rows(i)
        Dim act As String
        act = UCase(Trim(CStr(ws.Cells(rowIdx, COL_ACTION).value)))

        If act = "TRACK" Or act = "TRACK-YAW" Or act = "PAN FOLLOW" Or act = "MOVE" Then
            If n >= TRACK_PLAN_MAX Then
                LogTP "  ERROR row " & rowIdx & ": exceeds TRACK_PLAN_MAX=" & TRACK_PLAN_MAX
                errCount = errCount + 1
            Else
                ' ts = this row's Fires-at; te = next row's Fires-at.
                ' Both stamped onto the dated shoot timeline (Day 28) so the
                ' relative ms windows and the cadence lookup stay correct
                ' across midnight.
                Dim ts As Double, te As Double
                Dim rawTs As Double, rawTe As Double
                rawTs = CellSerial(ws.Cells(rowIdx, COL_FIRES_AT).value)
                ts = StampClock(rawTs - Int(rawTs), baseDate, dayAnchor)
                If i < nRows - 1 Then
                    rawTe = CellSerial(ws.Cells(rows(i + 1), COL_FIRES_AT).value)
                    te = StampClock(rawTe - Int(rawTe), baseDate, dayAnchor)
                Else
                    LogTP "  ERROR row " & rowIdx & ": " & act & " is last row (no END to bound te)"
                    errCount = errCount + 1
                    GoTo NextRow
                End If

                ' Pan Follow and Move carry no astro object on the cart (mode
                ' P ignores obj; mode M holds an absolute endpoint computed
                ' here) -> 'N' placeholder. Track/Track-yaw resolve a real
                ' object from the Target column for the cart's cubic.
                Dim objChar As String
                If act = "PAN FOLLOW" Or act = "MOVE" Then
                    objChar = "N"
                Else
                    objChar = ObjToChar(LCase(Trim(CStr(ws.Cells(rowIdx, COL_TARGET).value))))
                    If objChar = "" Then
                        LogTP "  ERROR row " & rowIdx & ": bad target '" & _
                              CStr(ws.Cells(rowIdx, COL_TARGET).value) & "'"
                        errCount = errCount + 1
                        GoTo NextRow
                    End If
                End If

                ivIdx(n) = n
                ivTs(n) = (ts - planStart) * 86400# * 1000#       ' ms from start
                ivTe(n) = (te - planStart) * 86400# * 1000#
                ivObj(n) = objChar
                Select Case act
                    Case "TRACK"
                        ivMode(n) = "F"
                        ivOffY(n) = SafeNum(ws.Cells(rowIdx, COL_DYAW).value)
                        ivOffP(n) = SafeNum(ws.Cells(rowIdx, COL_DPITCH).value)
                    Case "TRACK-YAW"
                        ivMode(n) = "Y"
                        ivOffY(n) = SafeNum(ws.Cells(rowIdx, COL_DYAW).value)
                        ivOffP(n) = SafeNum(ws.Cells(rowIdx, COL_RP).value)   ' fixed pitch
                    Case "PAN FOLLOW"
                        ivMode(n) = "P"
                        ivOffY(n) = SafeNum(ws.Cells(rowIdx, COL_DYAW).value)  ' goto-yaw (offset)
                        ivOffP(n) = SafeNum(ws.Cells(rowIdx, COL_DPITCH).value)
                    Case Else                                                 ' MOVE
                        ' Absolute endpoint: astro -> EvalAstro(fire)+d (cart
                        ' has no cubic to add to for a Move); marker -> Ry/Rp+d.
                        ivMode(n) = "M"
                        Dim mtgt As String
                        mtgt = LCase(Trim(CStr(ws.Cells(rowIdx, COL_TARGET).value)))
                        Dim my As Double, mp As Double
                        If PlanPush.IsAstroTarget(mtgt) Then
                            If Not PlanPush.EvalAstro(mtgt, ts, cartHeading, my, mp) Then _
                                LogTP "  NOTE row " & rowIdx & ": astro '" & mtgt & "' below horizon at fire time"
                            ivOffY(n) = my + SafeNum(ws.Cells(rowIdx, COL_DYAW).value)
                            ivOffP(n) = mp + SafeNum(ws.Cells(rowIdx, COL_DPITCH).value)
                        Else
                            ivOffY(n) = SafeNum(ws.Cells(rowIdx, COL_RY).value) + SafeNum(ws.Cells(rowIdx, COL_DYAW).value)
                            ivOffP(n) = SafeNum(ws.Cells(rowIdx, COL_RP).value) + SafeNum(ws.Cells(rowIdx, COL_DPITCH).value)
                        End If
                End Select

                ' Phase-A acquire: ease_frames (ease band, col Z) x cadence
                ' at this GP's fire time. acquire_ms = 0 when ease is none/--
                ' or cadence unavailable -> cart falls back to no-ease snap.
                Dim easeName As String
                easeName = CStr(ws.Cells(rowIdx, COL_EASE).value)
                Dim eFrames As Long: eFrames = EaseFrames(easeName)
                Dim cadSec As Double: cadSec = CadenceSecAt(ts, sunsetT, sunriseT, astroDuskT, branch)
                ivAcq(n) = eFrames * cadSec * 1000#
                If eFrames > 0 And cadSec = 0 Then _
                    LogTP "    WARNING: ease '" & easeName & "' set but cadence unavailable -> acquire_ms=0 (snap)"

                ' Phase-1 WP-event binding. Only WP-anchored rows carry a real
                ' awp; TIME/ASTRO rows keep awp=0 so the cart falls back to the
                ' pushed ts/te. Offset (col P) is in MINUTES -> ms here.
                Dim aType As String
                aType = UCase(Trim(CStr(ws.Cells(rowIdx, COL_ANCHOR_TYPE).value)))
                If aType = "WP" Then
                    ivAwp(n) = ParseWpNum(CStr(ws.Cells(rowIdx, COL_ANCHOR_REF).value))
                Else
                    ivAwp(n) = 0
                End If
                ivOffMs(n) = SafeNum(ws.Cells(rowIdx, COL_OFFSET_MIN).value) * 60000#

                ' #40 1a: expected cart heading for EARTH-FRAME GPs only (mode
                ' F/Y - matches the cart's earth flag). Looked up by anchor WP
                ' from the left-zone Plan col H (PlanBuilder writes it there per
                ' WP). Verbatim - col H is already CW-positive, no sign flip.
                ' Omitted (no &eh=) for relative/move rows, non-WP-anchored
                ' rows, or a WP with no col-H entry -> cart stores NAN -> null.
                ivHasEh(n) = False
                If (ivMode(n) = "F" Or ivMode(n) = "Y") And ivAwp(n) > 0 Then
                    Dim ehVal As Variant
                    ehVal = LookupExpectedHeading(ws, ivAwp(n))
                    If Not IsEmpty(ehVal) Then
                        ivEh(n) = CDbl(ehVal)
                        ivHasEh(n) = True
                    End If
                End If

                LogTP "  idx=" & n & " obj=" & objChar & " mode=" & ivMode(n) & _
                      " ts=" & Format(ivTs(n), "0") & "ms te=" & Format(ivTe(n), "0") & "ms" & _
                      " offy=" & Format(ivOffY(n), "0.0") & " offp=" & Format(ivOffP(n), "0.0")
                LogTP "    bind: awp=" & ivAwp(n) & " offms=" & Format(ivOffMs(n), "0") & _
                      IIf(ivAwp(n) = 0, " (not WP-anchored -> cart uses ts/te)", "")
                LogTP "    eh: " & IIf(ivHasEh(n), _
                      Format(ivEh(n), "0.0") & " deg (earth WP" & ivAwp(n) & ", from col H)", _
                      "(none -> NAN: " & IIf(ivMode(n) = "F" Or ivMode(n) = "Y", _
                      IIf(ivAwp(n) > 0, "no col-H for WP" & ivAwp(n), "not WP-anchored"), _
                      "relative/move row") & ")")
                LogTP "    acquire: ease='" & easeName & "' frames=" & eFrames & _
                      " cadence=" & Format(cadSec, "0.0") & "s -> acquire_ms=" & Format(ivAcq(n), "0")
                n = n + 1
            End If
        End If
NextRow:
    Next i

    If errCount > 0 Then
        LogTP "FAILED: " & errCount & " error(s). Aborting."
        MsgBox errCount & " track-interval error(s). See Log.", vbExclamation, "PushTrackPlanToCart"
        Exit Sub
    End If
    If n = 0 Then
        LogTP "No Track intervals in plan (nothing to push)."
        MsgBox "No Track GPs found in the gimbal plan.", vbInformation, "PushTrackPlanToCart"
        Exit Sub
    End If

    LogTP "Built " & n & " TrackInterval(s)."

    ' --- Dry-run stops here ---
    If dryRun Then
        LogTP "--- PushTrackPlanToCart end (DRY RUN, not sent) ---"
        MsgBox "DRY RUN: " & n & " interval(s) built, not sent." & vbCrLf & _
               "See Log sheet for the per-interval breakdown.", vbInformation, "PushTrackPlanToCart"
        Exit Sub
    End If

    ' --- Real push: ping /status, then one GET per interval ---
    Dim arduinoIP As String
    arduinoIP = ReadArduinoIP()
    If arduinoIP = "" Then
        MsgBox "Cart IP not set in Settings.", vbExclamation, "PushTrackPlanToCart"
        Exit Sub
    End If
    If Not CartAlive(arduinoIP) Then
        LogTP "ABORT: cart /status no response at " & arduinoIP
        MsgBox "Cart not responding at " & arduinoIP & ". Push aborted.", _
               vbExclamation, "PushTrackPlanToCart"
        Exit Sub
    End If

    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    Dim k As Long, okAll As Boolean: okAll = True
    For k = 0 To n - 1
        Dim url As String
        url = arduinoIP & "/settings/trackplan?idx=" & ivIdx(k) & _
              "&ts=" & Format(ivTs(k), "0") & _
              "&te=" & Format(ivTe(k), "0") & _
              "&obj=" & ivObj(k) & "&mode=" & ivMode(k) & _
              "&offy=" & Format(ivOffY(k), "0.00") & _
              "&offp=" & Format(ivOffP(k), "0.00") & _
              "&acquire=" & Format(ivAcq(k), "0") & _
              "&awp=" & ivAwp(k) & _
              "&offms=" & Format(ivOffMs(k), "0")
        ' #40 1a: earth-frame GPs carry the expected heading; others omit it
        ' (append-only -> cart NAN -> feed null). Verbatim, CW+ (no flip).
        If ivHasEh(k) Then url = url & "&eh=" & Format(ivEh(k), "0.00")
        LogTP "GET " & url
        Dim sc As Long, resp As String
        On Error Resume Next
        http.Open "GET", url, False
        http.Send
        sc = http.Status
        resp = CStr(http.responseText)
        On Error GoTo ErrHandler
        If sc = 200 Then
            LogTP "  OK " & resp
        Else
            LogTP "  HTTP " & sc & " " & resp
            okAll = False
            Exit For
        End If
    Next k

    If okAll Then
        LogTP "--- PushTrackPlanToCart end (REAL PUSH, " & n & " intervals) ---"
        MsgBox n & " TrackInterval(s) pushed to cart." & vbCrLf & vbCrLf & _
               "Push cubics (AstroPush) too, then /track/start.", _
               vbInformation, "PushTrackPlanToCart"
    Else
        MsgBox "Push failed mid-way. See Log.", vbExclamation, "PushTrackPlanToCart"
    End If
    Exit Sub

ErrHandler:
    LogTP "ERROR: " & Err.Description
    MsgBox "Error in PushTrackPlanToCart:" & vbCrLf & vbCrLf & Err.Description, _
           vbCritical, "PushTrackPlanToCart"
End Sub


' ============================================================
' Helpers
' ============================================================
' Plan target token -> cart obj char. sun->S, moon->M, gc/mw->W.
Private Function ObjToChar(ByVal t As String) As String
    Select Case t
        Case "sun":          ObjToChar = "S"
        Case "moon":         ObjToChar = "M"
        Case "gc", "mw":     ObjToChar = "W"
        Case Else:           ObjToChar = ""
    End Select
End Function

Private Function SafeNum(ByVal v As Variant) As Double
    If IsNumeric(v) Then SafeNum = CDbl(v) Else SafeNum = 0
End Function

' #40 1a: expected cart heading (Plan col H, deg CW+) for a waypoint number.
' PlanBuilder writes col H per WP on the left-zone DRIVE rows, with col B =
' the label "WPnn". Scan the left zone for that label; return col H if
' numeric, else Empty so the caller omits the &eh= token (cart stores NAN).
' Verbatim - col H is already CW-positive (HEADING_CONVENTION), no conversion.
Private Function LookupExpectedHeading(ByVal ws As Worksheet, _
                                       ByVal wpNum As Long) As Variant
    LookupExpectedHeading = Empty
    Dim wantLabel As String
    wantLabel = "WP" & Format(wpNum, "00")
    Dim r As Long
    For r = PLAN_FIRST_ROW To PLAN_FIRST_ROW + PLAN_MAX_ROWS - 1
        If Trim(CStr(ws.Cells(r, 2).value)) = wantLabel Then   ' col B = WP label
            Dim hv As Variant
            hv = ws.Cells(r, 8).value                          ' col H = heading
            If IsNumeric(hv) Then LookupExpectedHeading = CDbl(hv)
            Exit Function
        End If
    Next r
End Function

' "WP01" / "wp 1" / "WP12" -> 1 / 1 / 12. Strips all non-digits. Returns 0 if
' no digits (caller treats 0 as 'not WP-anchored'). Used for the Phase-1 awp
' tail token so the cart can index wp_arrival_ms by WP number.
Private Function ParseWpNum(ByVal s As String) As Long
    Dim i As Long, ch As String, digits As String
    For i = 1 To Len(s)
        ch = mid$(s, i, 1)
        If ch >= "0" And ch <= "9" Then digits = digits & ch
    Next i
    If Len(digits) = 0 Then ParseWpNum = 0 Else ParseWpNum = CLng(digits)
End Function

' Date-tolerant numeric read (Day 28). A cell formatted as a date or time
' returns a Date-typed Variant from .Value, and VBA's IsNumeric() reports
' a Date as NON-numeric -- which is exactly what was zeroing the sun-time
' cells when read through SafeNum(). IsDate() identifies the Date case;
' CDbl(CDate()) then yields its serial. Plain numbers still pass; anything
' else returns 0.
Private Function CellSerial(ByVal v As Variant) As Double
    If IsDate(v) Then
        CellSerial = CDbl(CDate(v))
    ElseIf IsNumeric(v) Then
        CellSerial = CDbl(v)
    Else
        CellSerial = 0
    End If
End Function

' Place a clock time-of-day (fraction 0..1) onto the dated shoot timeline
' (Day 28). baseDate is the shoot's start date; dayAnchor is the evening
' anchor (earliest of shoot-start and sunset). A clock time earlier than
' the anchor belongs to the next calendar day (after-midnight fires and the
' end-of-shoot sunrise). With baseDate = 0 and dayAnchor = 0 (sun times
' missing) this returns the plain time-of-day, preserving old behaviour.
Private Function StampClock(ByVal clk As Double, _
                            ByVal baseDate As Double, _
                            ByVal dayAnchor As Double) As Double
    StampClock = baseDate + clk
    If clk < dayAnchor Then StampClock = StampClock + 1#
End Function

' Ease band name (col Z) -> audience frames, from Settings named ranges.
' none / em-dash / blank / unknown -> 0 (cart pushes acquire=0 = no ease).
Private Function EaseFrames(ByVal easeName As String) As Long
    Select Case LCase(Trim(easeName))
        Case "just-perceptible": EaseFrames = ReadSettingInt("dataEaseJustPerceptible", 3)
        Case "comfortable":      EaseFrames = ReadSettingInt("dataEaseComfortable", 10)
        Case "cinematic":        EaseFrames = ReadSettingInt("dataEaseCinematic", 30)
        Case Else:               EaseFrames = 0
    End Select
End Function

Private Function ReadSettingInt(ByVal nm As String, ByVal dflt As Long) As Long
    On Error GoTo Defaulting
    Dim v As Variant
    v = ThisWorkbook.Sheets("Settings").Range(nm).value
    If IsNumeric(v) Then ReadSettingInt = CLng(v) Else ReadSettingInt = dflt
    Exit Function
Defaulting:
    ReadSettingInt = dflt
End Function

' Cadence (seconds between photos) at an absolute fire time, from the
' design's own exposure model: FormulaTv (the Tv curve pushed to the cart
' as the WiFi-loss TABLE fallback) -> CalcInterval (ceil(Tv+1.5)). Mirrors
' PushFormulaToCart's sunset->sunrise swap at astronomical dusk. Returns 0
' if event times/branch unavailable or Tv unresolved -> caller pushes
' acquire=0 (cart no-ease snap), never a fabricated cadence.
Private Function CadenceSecAt(ByVal fireTime As Double, _
                              ByVal sunsetT As Double, _
                              ByVal sunriseT As Double, _
                              ByVal astroDuskT As Double, _
                              ByVal branch As String) As Double
    CadenceSecAt = 0
    If sunsetT = 0 Or sunriseT = 0 Then Exit Function

    Dim sunEvt As String, tRel As Double
    If astroDuskT > 0 And fireTime >= astroDuskT Then
        sunEvt = "Sunrise": tRel = (fireTime - sunriseT) * 86400#
    Else
        sunEvt = "Sunset":  tRel = (fireTime - sunsetT) * 86400#
    End If

    Dim tvStr As Variant
    On Error GoTo Bail
    tvStr = FormulaTv(tRel, branch, sunEvt)        ' Public UDF in Formula module
    If VarType(tvStr) <> vbString Then Exit Function
    If Left$(CStr(tvStr), 1) = "#" Then Exit Function   ' #BRANCH? / #EVENT?
    CadenceSecAt = CalcInterval(CStr(tvStr))       ' Public fn in Utils module
    Exit Function
Bail:
    CadenceSecAt = 0
End Function

Private Function ReadDryRunFlag() As Boolean
    On Error GoTo Defaulting
    Dim v As Variant
    v = ThisWorkbook.Sheets("Settings").Range("dataPlanPushDryRun").value
    If IsEmpty(v) Then ReadDryRunFlag = True: Exit Function
    ReadDryRunFlag = CBool(v)
    Exit Function
Defaulting:
    ReadDryRunFlag = True
End Function

Private Function ReadArduinoIP() As String
    On Error Resume Next
    Dim ip As String
    ip = Trim(CStr(ThisWorkbook.Sheets("Settings").Range("dataArduinoIP").value))
    On Error GoTo 0
    If ip = "" Then
        ReadArduinoIP = ""
    Else
        If LCase(Left(ip, 7)) <> "http://" Then ip = "http://" & ip
        ReadArduinoIP = ip
    End If
End Function

Private Function CartAlive(ByVal arduinoIP As String) As Boolean
    Dim http As Object
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    On Error Resume Next
    http.Open "GET", arduinoIP & "/status", False
    http.Send
    CartAlive = (http.Status = 200)
    On Error GoTo 0
End Function

Private Sub LogTP(ByVal msg As String)
    On Error Resume Next
    Application.Run "Utils.LogEvent", LOG_CATEGORY, msg
    On Error GoTo 0
End Sub
