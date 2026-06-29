# RosedaleVan AX6000 — Test & Findings
Date: 2026-06-27
Unit: Wavlink WL-WN536AX6 Rev A "Mighty LX2" (AX6000), firmware M36AX6_V250320

## Verdict
**AX6000 CLEARED.** Not the cause of the WiFi-drop faults.
Root cause was Giga firmware socket handling, not the router.

## Configuration applied (unit 1)
- Mode: Router
- SSID: RosedaleVan
- 2.4G: channel 6, 20MHz, signal High
- 5G: disabled
- LAN: 192.168.20.x (test subnet; final field subnet to be .2.x post-approval)
- WAN: not required (no internet); USB iPhone tether optional (Trust prompt OK)
- Config backed up (More > Backup and Restore)

## What was actually wrong
- Faults = Giga firmware socket handling: mbed TCPSocket pool-4 leak / half-open.
  Symptom = association UP (wifi=3), RSSI strong, :80 dead, no drop logged.
- Fixed in cart firmware across v203–v240 (latest: v234 stop()/socket-free close fix).
- This is the Giga's fault and follows the cart onto ANY AP — not the AX6000's.

## Evidence
- Trial sketch v1 served HTTP in-loop (retired firmware method) -> self-stalled.
  Invalid rig. Rewritten v2 threaded (rtos::Thread + raw TCPSocket, matches
  httpThreadFn). v2 then held drops=0 over 256s at RSSI -60..-73.
- Real-cart run, 1.12h at a marginal placement: 40.3% loss seen by laptop hammer,
  BUT cart [httpxmon] showed wifi=3 throughout, lasterr=0, served climbing 33->783.
  RSSI swinging -66..-87. One genuine drop+self-recover at the -86 trough.
  => failures tracked RSSI floor, not the AP. Two witnesses reconciled: AP fine,
  signal floor at that placement was the only real drop, cart recovered itself.

## RSSI behaviour (measured)
- AP holds association cleanly when RSSI adequate: drops=0 at -60..-73.
- Failures only at the RSSI floor: troughs -85..-87 cause brief real drops.
  This is propagation/placement, not the unit.
- Approval bar going forward: TROUGHS (not average) must stay above ~-78.

## Test method note
- 60m open-ground from van = NOK (signal floor).
- Pushing the cart further to induce drops tests propagation, not the router —
  not a useful AP test.
- Valid test = real field geometry, read the trough floor, pass if above -78.

## Field deployment (TARGET — not yet soak-tested)
- TWO AX6000 in MESH (unit 1 on van, unit 2 as mesh node between van and cart).
- Cart associates to nearest node; node placement keeps cart RSSI above -78 at 60m.
- Open: (1) confirm the two units are paired in mesh, (2) node placement,
  (3) soak at real two-node geometry reading the trough floor.

## IP scheme
- Test now: AX6000 LAN .20.x, cart Giga static 192.168.20.97, gw/dns .20.1.
- Post-approval: AX6000 LAN -> 192.168.2.1, Giga/camera -> permanent .2.x.
- Home router "Rosedale" is a SEPARATE box on 192.168.1.x (do not collide).

## Tooling produced
- soak_wifi_trial.ino (v2, threaded) — link-hold trial target, /ping + /stats + drum-beat.
- wifi_hammer.py — sustained 2s-cadence link hammer, targets cart /heartbeat,
  logs every gap with timestamp; cart soak CSV is the inside witness.
- DJI_Ronin_Giga_v2.ino — cart SSID/IP pointed at RosedaleVan .20.97 for the soak.

---

# Mesh Setup — Unit 2 (Update)
Date: 2026-06-27

## Status: mesh formed and holding
Two AX6000 now meshed. Unit 1 = controller (Router), unit 2 = node (Extender).

## Devices (confirmed by network scan, .20.x)
- 192.168.20.1   wavlogin.link  MAC 80:3F:5D:89:3F:0B  ports 80/443 — unit 1 controller
- 192.168.20.201 MAC 80:3F:5D:89:3D:A9  ports 80/443 — unit 2 node (mesh list shows ...3D:AB; adjacent host/radio MAC, same unit)
- 192.168.20.97  MAC 34:90:EA:71:C5:1B  port 80 — cart Giga, live, 28ms

## ROOT CAUSE of repeated mesh-join failures: controller needs WAN
- Pairing kept failing (node appeared in list then dropped, never on Topology Map).
- Cause: Everything Mesh validates the controller can reach the Internet during/after
  pairing. Unit 1 had NO WAN (0.0.0.0) -> node paired in handshake but was never
  promoted into live topology.
- Fix: gave unit 1 a WAN via iPhone USB tether (Device IP 172.20.10.4, gw 172.20.10.1,
  Apple hotspot subnet). System clock then NTP-synced (confirms real internet).
  Re-paired -> node held, drawn connected on Topology Map.
- Backhaul is independent of WAN once paired; tether can be pulled after.

## iPhone tether note
- "Personal Hotspot greyed out" is an iPhone-side dependency block (cellular data off,
  carrier/plan provisioning, missing APN, iOS 26 bug, or MDM/VPN profile) — NOT the AX6000.
- Once resolved, tether came up, unit 1 online, mesh paired.

## MESH REQUIRES BOTH BANDS
- Mesh uses 5GHz for inter-node backhaul, 2.4GHz for client coverage.
- The earlier "5G disabled" setting (valid for single-AP standalone test) is NOT
  compatible with mesh — 5G comes back on / must stay on. 5G Channel Auto (56) observed.
- Cart still associates on 2.4G ch6 regardless; single SSID, backhaul on 5G. No conflict.

## Cart roams to the node (working as intended)
- Cart (.20.97) associated to the NODE (unit 2), not the controller — it picked the
  stronger signal. Confirmed on Topology Map: cart hangs off the Extender.
- Controller client summary LAGS node-side clients (display lag), so the cart shows in
  a network scan but not yet in the controller summary. Topology Map is authoritative.
  This is a display lag, NOT a connectivity fault.

## Mesh pairing procedure (working, for re-use)
1. Ensure controller has WAN (Internet) — tether if needed; verify Network shows a real IP.
2. More > Mesh > Mesh Devices; DELETE any stale node entry.
3. Node next to controller; factory reset node (hold Reset >6s); power on, let boot.
4. Press node Pair button ~2s (indicator flashes blue slowly = armed).
5. ADD > Start scanning > select node > add.
6. Refresh, wait ~2 min, open Topology Map.
7. BAR: node must be DRAWN CONNECTED to Router on the Topology Map before trusting it.
   (Appearing in the list alone is not enough — that was the phantom-join failure mode.)

## Still open
- Field soak at real two-node geometry (cart 60m): read node Signal Strength,
  pass if troughs stay above ~-78. Not yet done (operator's own time).

---

# Resolution & Remaining Issue (Update)
Date: 2026-06-27

## Mesh no-WAN drop: SOLVED
- Cause: with WAN Type = DHCP the controller sits "waiting for lease" and the
  mesh-agent tears the node down when no internet is present.
- Fix: WAN Type = Static, dummy values (IP 10.0.0.2 / 255.255.255.0 /
  gw 10.0.0.1 / DNS 10.0.0.1), nothing plugged into the WAN port.
  WAN Status still reads "Disconnected" but the node holds with an IP and on
  the Topology Map, and SURVIVES a power-cycle. No internet, no iPhone, no cable.
- Confirmed by test (power-cycle, node holds; cart keeps .20.97).
- Note: this firmware (M36AX6_V250320) has NO "Auto DHCP Service" toggle, and
  Auto Mesh was already OFF when the drop occurred — so neither of those was the
  fix. WAN Type = Static is the fix.

## ONE REMAINING ISSUE: stale DHCP lease after AX6000 reboot
- Symptom: after the AX6000 reboots, the laptop's wired adapter ("Ethernet 2")
  clings to its old lease and shows 169.254.x.x (Windows APIPA) until renewed.
  The 169.254 is Windows self-assigning because no DHCP reply arrived in time
  (the USB-C link does not drop on router reboot, so Windows never re-asks).
  It is a Windows-side behaviour, NOT an AX6000 fault — the router serves the
  lease fine the instant a renew is issued.
- Fix (chosen): release+renew the wired adapter at the desk during Prep Session.
  Macro RenewLanLease in LanRenew.bas (release+renew "Ethernet 2", hidden,
  ~1-2s, silent no-op on error). Adapter stays on DHCP (not static), so the
  renew is the recovery.
- Why Prep Session and not Prep Cart: the three buttons are time/place
  separated - Prep Session (desk, has internet) -> van recon -> Prep Plan ->
  Prep Cart. The renew must run at the desk where it's safe; in the field there
  is no internet to disturb. Prep Cart was the wrong home.
- Wiring: import LanRenew.bas; add as the FIRST step in GimbalPrep.PrepSession:
      RunStep "RenewLanLease", "Renew LAN Lease", rpt
  PrepSession then calls 6 macros (was 5):
      0 RenewLanLease       (new, first, soft)
      1 GetSunsetTime
      2 Astro.UpdateGCTimes
      3 InitShoot
      4 GenerateGCTable
      5 FetchGimbalMap      (conditional)
- Adapter name "Ethernet 2" is hard-set in LanRenew.bas; if Windows renames the
  NIC, update ADAPTER_NAME (check with getmac /v).

## AX6000 status
- No hardware/firmware fault attributable to the AX6000.
- Mesh no-WAN drop solved (Static WAN).
- One remaining operational item: the Windows stale-lease, handled by the
  Prep Session renew above.
