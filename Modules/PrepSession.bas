Attribute VB_Name = "PrepSession"
' =====================================================================
' PrepSession.bas  -  HyperLapse Cart session prep
' Run at the start of every field/bench session BEFORE any PushToCart.
'
' Purpose: guarantee the laptop's wired adapter holds a fresh .20.x lease
' from RosedaleVan before cart comms, killing the stale-lease 169.254
' (APIPA) surprise after an AX6000 reboot. Then verify the cart is
' actually reachable, so the session fails LOUD instead of pushing to a
' cart it can't see.
'
' Network (bench/field):
'   AX6000 RosedaleVan  192.168.20.1   (DHCP server on .20.x)
'   Cart Giga (static)  192.168.20.97
'   Laptop wired NIC    "Ethernet 2"   (DHCP -> .20.231 typ.)
'
' Adapter name MUST match Windows exactly. If Windows renames the NIC,
' update ADAPTER_NAME below (check with: getmac /v  or  ipconfig).
' =====================================================================

Option Explicit

Private Const ADAPTER_NAME As String = "Ethernet 2"
Private Const CART_IP      As String = "192.168.20.97"
Private Const ROUTER_IP    As String = "192.168.20.1"
Private Const SUBNET_PFX   As String = "192.168.20."     ' expected lease prefix

' ---------------------------------------------------------------------
' Entry point: call this from your session-start macro.
' Returns True only if the laptop is on .20.x AND the cart answers.
' ---------------------------------------------------------------------
Public Function PrepSession() As Boolean
    PrepSession = False

    ' 1) Force a fresh DHCP lease on the wired adapter (release+renew).
    RenewWiredLease

    ' 2) Confirm the adapter actually landed on .20.x (not 169.254 APIPA).
    If Not OnExpectedSubnet() Then
        MsgBox "Prep FAILED: wired adapter is not on " & SUBNET_PFX & "x." & vbCrLf & _
               "Likely 169.254 (APIPA) - no DHCP lease from RosedaleVan." & vbCrLf & vbCrLf & _
               "Checks:" & vbCrLf & _
               " - Cat6 seated, USB-C adapter shows a wired connection" & vbCrLf & _
               " - RosedaleVan powered, DHCP serving .20.x" & vbCrLf & _
               " - Adapter name still '" & ADAPTER_NAME & "' (getmac /v)", _
               vbCritical, "PrepSession"
        Exit Function
    End If

    ' 3) Confirm the router itself answers (link to AP is live).
    If Not PingOK(ROUTER_IP) Then
        MsgBox "Prep FAILED: on .20.x but RosedaleVan (" & ROUTER_IP & ") not answering ping." & vbCrLf & _
               "Router up but not reachable - check WiFi/wired path.", _
               vbCritical, "PrepSession"
        Exit Function
    End If

    ' 4) Confirm the CART answers (the thing PushToCart needs).
    If Not PingOK(CART_IP) Then
        MsgBox "Prep WARNING: laptop on .20.x and router OK, but cart (" & CART_IP & ")" & vbCrLf & _
               "is not answering. Cart powered? Associated to RosedaleVan?" & vbCrLf & _
               "Do NOT PushToCart until the cart responds.", _
               vbExclamation, "PrepSession"
        Exit Function
    End If

    PrepSession = True
    ' Silent on success - no nag. Caller proceeds to the session.
End Function

' ---------------------------------------------------------------------
' release + renew the wired adapter, hidden, wait for completion.
' Only meaningful while the adapter is on DHCP (it is, by design).
' ---------------------------------------------------------------------
Private Sub RenewWiredLease()
    Dim sh As Object
    Set sh = CreateObject("WScript.Shell")
    ' release then renew in one shell; quotes around adapter name for the space.
    sh.Run "cmd /c ipconfig /release """ & ADAPTER_NAME & """ & ipconfig /renew """ & ADAPTER_NAME & """", 0, True
    ' brief settle so the lease is in place before we read it.
    WaitMs 1500
End Sub

' ---------------------------------------------------------------------
' True if ipconfig shows the adapter holding an IPv4 in SUBNET_PFX.
' Reads ipconfig output via a temp file (no extra references needed).
' ---------------------------------------------------------------------
Private Function OnExpectedSubnet() As Boolean
    Dim sh As Object, fso As Object, ts As Object
    Dim tmp As String, out As String
    Set sh = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")
    tmp = fso.GetSpecialFolder(2) & "\hl_ipcfg.txt"   ' %TEMP%

    sh.Run "cmd /c ipconfig > """ & tmp & """", 0, True
    WaitMs 300

    On Error GoTo done
    If fso.FileExists(tmp) Then
        Set ts = fso.OpenTextFile(tmp, 1)
        out = ts.ReadAll
        ts.Close
        fso.DeleteFile tmp
    End If
done:
    On Error GoTo 0
    OnExpectedSubnet = (InStr(out, SUBNET_PFX) > 0)
End Function

' ---------------------------------------------------------------------
' True if host answers ping (1 echo, short timeout).
' Uses ping's errorlevel via a marker file - no WMI, no references.
' ---------------------------------------------------------------------
Private Function PingOK(ByVal host As String) As Boolean
    Dim sh As Object, fso As Object, ts As Object
    Dim tmp As String, out As String
    Set sh = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")
    tmp = fso.GetSpecialFolder(2) & "\hl_ping.txt"

    ' -n 1 one echo, -w 800 ms timeout
    sh.Run "cmd /c ping -n 1 -w 800 " & host & " > """ & tmp & """", 0, True
    WaitMs 200

    On Error GoTo done
    If fso.FileExists(tmp) Then
        Set ts = fso.OpenTextFile(tmp, 1)
        out = ts.ReadAll
        ts.Close
        fso.DeleteFile tmp
    End If
done:
    On Error GoTo 0
    ' "TTL=" appears only on a successful reply; robust across locales.
    PingOK = (InStr(out, "TTL=") > 0)
End Function

' ---------------------------------------------------------------------
' Sleep without pegging the CPU. Uses Application.Wait granularity-safe.
' ---------------------------------------------------------------------
Private Sub WaitMs(ByVal ms As Long)
    Dim t As Single
    t = Timer
    Do While (Timer - t) * 1000 < ms
        DoEvents
    Loop
End Sub
