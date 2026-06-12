Attribute VB_Name = "CableSpan"
' ============================================================
' HyperLapse Cart - Cable-span guard (450 deg limit).
'
' SINGLE SOURCE OF TRUTH: the cable-strip renderer (gimbal_cablestrip.py)
' computes the swept CART-FRAME yaw span - the quantity that actually winds
' the gimbal's cables around the cart body - and writes it to a sidecar file
' "cablestrip_span.txt" (one line: "span headroom limit", degrees). This guard
' READS that number; it does not recompute, so the alert, the cable-strip
' chart, and the push gate can never disagree.
'
' Button rhythm:
'   Prep Plan  (BuildPlan)  -> RenderCableStrip writes the sidecar;
'                              DetectCableSpan reads it, alerts if over limit
'                              (does NOT block - operator can see + fix).
'   Prep Cart  (PushToCart) -> CableSpanOK reads it; if over limit, REFUSE
'                              to push (cart protected). Dry-run inspect is
'                              unaffected (the gate is in the Prep sequence,
'                              not in the individual dry-run push macros).
' ============================================================
Option Explicit

Private Const SPAN_LIMIT As Double = 450#
Private Const PY_SUBDIR  As String = "Python"
Private Const SIDECAR    As String = "cablestrip_span.txt"
Private Const LOG_CATEGORY As String = "CABLESPAN"

' Read the renderer's sidecar. Returns True on success and fills span/headroom.
Private Function ReadSpan(ByRef span As Double, ByRef headroom As Double) As Boolean
    ReadSpan = False
    Dim base As String: base = ThisWorkbook.path
    If base = "" Then Exit Function
    Dim f As String
    f = base & Application.PathSeparator & PY_SUBDIR & Application.PathSeparator & SIDECAR
    If dir(f) = "" Then Exit Function

    Dim h As Integer: h = FreeFile
    Dim line As String
    On Error GoTo done
    Open f For Input As #h
    Line Input #h, line
    Close #h
    Dim parts() As String: parts = Split(Trim$(line), " ")
    If UBound(parts) < 1 Then Exit Function
    span = Val(parts(0)): headroom = Val(parts(1))
    ReadSpan = True
    Exit Function
done:
    On Error Resume Next
    Close #h
End Function

' --- DETECT (called by BuildPlan, after RenderCableStrip). Alerts if over. ---
Public Sub DetectCableSpan()
    Dim span As Double, headroom As Double
    If Not ReadSpan(span, headroom) Then
        LogEvent LOG_CATEGORY, "no span sidecar - run Render Cable Strip first; treating as NOT OK"
        Exit Sub
    End If
    Dim okFlag As Boolean: okFlag = (span <= SPAN_LIMIT)
    LogEvent LOG_CATEGORY, "swept span = " & Format(span, "0") & " deg (limit " & _
             Format(SPAN_LIMIT, "0") & "), headroom " & Format(headroom, "0") & ", OK=" & okFlag
    If Not okFlag Then
        MsgBox "Cable span " & Format(span, "0") & " deg EXCEEDS the " & _
               Format(SPAN_LIMIT, "0") & " deg limit (over by " & _
               Format(-headroom, "0") & " deg)." & vbCrLf & vbCrLf & _
               "The gimbal would over-wind its cables. Fix the plan " & _
               "(sweep direction / GP order) before pushing to the cart." & vbCrLf & _
               "Prep Cart will refuse to push until this is resolved.", _
               vbExclamation, "Cable span over limit"
    End If
End Sub

' --- GATE (called by PushToCart). True = safe to push. ---
Public Function CableSpanOK() As Boolean
    Dim span As Double, headroom As Double
    If Not ReadSpan(span, headroom) Then
        ' no sidecar -> cannot prove safety -> refuse (run Prep Plan first).
        LogEvent LOG_CATEGORY, "PUSH BLOCKED: no span sidecar (run Prep Plan first)"
        MsgBox "Push to cart BLOCKED." & vbCrLf & vbCrLf & _
               "No cable-span result found. Run Prep Plan (Render Cable Strip) " & _
               "first so the span can be checked against the " & _
               Format(SPAN_LIMIT, "0") & " deg limit.", _
               vbCritical, "Prep Cart blocked - no span data"
        CableSpanOK = False
        Exit Function
    End If
    CableSpanOK = (span <= SPAN_LIMIT)
    If Not CableSpanOK Then
        LogEvent LOG_CATEGORY, "PUSH BLOCKED: span " & Format(span, "0") & _
                 " over limit by " & Format(-headroom, "0")
        MsgBox "Push to cart BLOCKED." & vbCrLf & vbCrLf & _
               "Cable span " & Format(span, "0") & " deg exceeds the " & _
               Format(SPAN_LIMIT, "0") & " deg limit (over by " & _
               Format(-headroom, "0") & " deg). The gimbal would over-wind." & vbCrLf & _
               "Fix the plan and re-run Prep Plan first.", _
               vbCritical, "Prep Cart blocked - cable span"
    End If
End Function
