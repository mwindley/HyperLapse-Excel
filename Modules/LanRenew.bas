Attribute VB_Name = "LanRenew"
' =====================================================================
' LanRenew.bas  -  refresh the wired .20.x DHCP lease from RosedaleVan.
'
' Called by Prep Session (GimbalPrep.PrepSession), at the desk, where it
' is safe. After an AX6000 reboot the USB-C wired NIC clings to a stale
' lease and falls back to 169.254 (APIPA); a release+renew forces
' RosedaleVan to re-hand 192.168.20.231. No-op when the lease is good.
'
' Adapter name MUST match Windows exactly. Check with: getmac /v  (or
' ipconfig). If Windows renames the NIC, update ADAPTER_NAME below.
'
' Hidden window, waits for completion (~1-2s). On any error it is a
' silent no-op so it can never block Prep Session.
' =====================================================================

Option Explicit

Private Const ADAPTER_NAME As String = "Ethernet 2"

Public Sub RenewLanLease()
    On Error Resume Next
    CreateObject("WScript.Shell").Run _
        "cmd /c ipconfig /release """ & ADAPTER_NAME & """ & ipconfig /renew """ & ADAPTER_NAME & """", _
        0, True
    On Error GoTo 0
End Sub
