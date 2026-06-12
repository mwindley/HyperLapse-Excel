Attribute VB_Name = "PlanCols"
' ============================================================
' HyperLapse Cart - Shared MIDDLE-plan column resolver.
'
' Single source of truth for reading the MIDDLE gimbal-plan columns BY
' HEADER NAME instead of by fixed letter, so the operator can reorder the
' MIDDLE columns in Excel without breaking any macro that reads them.
'
' Usage in a reader macro:
'     Dim cols As Object
'     Set cols = PlanCols.ResolveMiddleCols(ws)        ' fail-loud
'     If cols Is Nothing Then Exit Sub                  ' missing header
'     act = UCase(Trim(CStr(ws.Cells(r, cols("action")).value)))
'
' Returns a Scripting.Dictionary keyed by the NORMALISED header name
' (see NKey) -> 1-based column index. Returns Nothing (and logs + MsgBox)
' if the MIDDLE header row or a required header is missing.
'
' WHY MIDDLE-bounded: the cart-plan section (cols B..) and the recon-log
' section (Log row#..) reuse header names (Action, Note, Ry, dyaw, dpitch).
' A whole-row scan would match the wrong section. We scan only from the
' 'Step' column up to the log block / a double blank, where names are unique.
' ============================================================
Option Explicit

Private Const LOG_CATEGORY As String = "PLANCOLS"

' Required MIDDLE headers (normalised keys). A reader may use a subset; this
' set is what ResolveMiddleCols guarantees present before returning.
Public Function PlanColsVersion() As String
    PlanColsVersion = "PlanCols Day32 stay(min) | keys: " & Join(RequiredKeys(), ",")
End Function

Sub ShowPlanColsVersion()
    MsgBox PlanColsVersion()
End Sub

Private Function RequiredKeys() As Variant
    RequiredKeys = Array("step", "anchortype", "anchorref", "offset(min)", _
        "firesat", "stay(min)", "action", "target", "panspeed", "ry", "rp", _
        "dyaw", "dpitch", "dir(cw/ccw)")
End Function

Public Function ResolveMiddleCols(ByVal ws As Worksheet) As Object
    Set ResolveMiddleCols = Nothing
    Dim hdrRow As Long, cStep As Long, r As Long, c As Long
    hdrRow = 0: cStep = 0

    ' locate the MIDDLE header row + Step column (first 12 rows, cols 1..41)
    For r = 1 To 12
        For c = 1 To 41
            If NKey(ws.Cells(r, c).value) = "step" Then
                hdrRow = r: cStep = c: Exit For
            End If
        Next c
        If hdrRow > 0 Then Exit For
    Next r
    If hdrRow = 0 Then
        FailMsg "MIDDLE header row (Step) not found."
        Exit Function
    End If

    ' scan ONLY the contiguous MIDDLE columns to the right of Step
    Dim found As Object
    Set found = CreateObject("Scripting.Dictionary")
    For c = cStep To 41
        Dim k As String: k = NKey(ws.Cells(hdrRow, c).value)
        If k = "logrow#" Then Exit For                ' reached the recon-log block
        If Len(k) = 0 Then
            ' tolerate one blank spacer; stop on a second consecutive blank
            If c > cStep Then
                If Len(NKey(ws.Cells(hdrRow, c - 1).value)) = 0 Then Exit For
            End If
        Else
            If Not found.Exists(k) Then found(k) = c
        End If
    Next c

    ' verify required headers present
    Dim req As Variant: req = RequiredKeys()
    Dim i As Long, miss As String: miss = ""
    For i = LBound(req) To UBound(req)
        If Not found.Exists(req(i)) Then miss = miss & req(i) & " "
    Next i
    If Len(miss) > 0 Then
        FailMsg "MIDDLE header(s) missing/renamed: " & Trim(miss)
        Exit Function
    End If

    Set ResolveMiddleCols = found
End Function

' Normalise a header/cell to a match key: map both delta cases to 'd' BEFORE
' lowercasing (LCase folds U+0394 to U+03B4), then lowercase, drop spaces,
' the degree sign, and the '(deg)'/'()' decorations.
Public Function NKey(ByVal v As Variant) As String
    Dim s As String: s = Trim(CStr(v))
    s = Replace(s, ChrW(916), "d")        ' greek capital delta U+0394
    s = Replace(s, ChrW(948), "d")        ' greek small delta   U+03B4
    s = LCase(s)
    s = Replace(s, " ", "")
    s = Replace(s, Chr(176), "")          ' degree sign
    s = Replace(s, "(deg)", "")
    s = Replace(s, "()", "")
    NKey = s
End Function

Private Sub FailMsg(ByVal why As String)
    On Error Resume Next
    LogEvent LOG_CATEGORY, "FAILED: " & why
    On Error GoTo 0
    MsgBox "Plan MIDDLE columns: " & why & vbCrLf & _
           "Push/read aborted - fix the header(s) and retry.", _
           vbCritical, "PlanCols"
End Sub
