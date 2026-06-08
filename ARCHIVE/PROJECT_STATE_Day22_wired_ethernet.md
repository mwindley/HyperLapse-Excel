## Session G (cont.) / Day 22 — Wired Ethernet (W5500) CCAPI commissioned

**Outcome: PASS.** CCAPI now reachable over a wired W5500 link, independent of
WiFi. Transport proven end to end: init -> link up -> TCP connect -> GET
/ccapi/ -> full 12616-byte endpoint dump returned -> clean close, board stable.

### Goal
Commission wired HTTP (CCAPI over Ethernet) so exposure control survives an
external-WiFi outage. D7 hardware shutter remains the sacred photo path,
untouched. Shutter-over-HTTP remains a separate, deferred decision.

### Hardware / setup
- W5500 Ethernet Shield 2 on Giga R1, CS = D10 (Giga SPI header).
- Point-to-point cable Giga <-> camera. Giga wired static IP 192.168.1.98,
  camera 192.168.1.99:8080 (wired Ethernet enabled in camera menu, .99
  confirmed on the WIRED interface specifically).
- WiFi NOT started in the bench sketches -> single interface, no dual-subnet
  routing ambiguity during bring-up.

### The key finding (architecture, not config)
Two library FAMILIES were tried; only the second works on the Giga:

1. **W5500-EMAC (JAndrassy) — DOES NOT WORK for data transport.**
   Routes the W5500 through the mbed EMAC networking stack. It brings the
   interface up (hardwareStatus detects the chip) but HARD-FAULTS the board
   (red LED / boot loop) on ANY socket open:
     - TCP client.connect() -> fault
     - udp.begin()          -> fault
   Confirmed it's a runtime fault in the EMAC socket layer, not upload/hardware:
   stock Blink uploads and runs fine on the same board. Also: this library's
   linkStatus() is unreliable on the Giga — stayed LinkOFF through a physical
   cable unplug/replug (not reading the PHY). Dead end.

2. **Stock Arduino Ethernet library (utility/w5100.h) — WORKS.**
   Talks DIRECTLY to the W5500 over SPI using the chip's OWN hardware TCP/IP
   stack, bypassing mbed networking entirely. Setup:
     Ethernet.init(10);            // CS = D10
     Ethernet.begin(mac, ip);      // static, no DHCP on point-to-point
   Results (minimal bracketed probe, every call survived):
     hardwareStatus = 3  (W5500 detected)
     linkStatus     = 1  (LinkON — reliable here, unlike EMAC)
     localIP        = 192.168.1.98
   Then client.connect(192.168.1.99, 8080) returned 1, GET /ccapi/ returned
   HTTP/1.1 200 OK + the full endpoint JSON. Board stable throughout.
   This is the most mature code path in the ecosystem (~15-yr W5100 lineage).

   NOTE: stock lib has NO setConnectionTimeout() — use
   setRetransmissionTimeout()/setRetransmissionCount() if bounding is needed.
   (An early crash was caused by calling the non-existent setConnectionTimeout;
   removing it fixed it. begin() itself is safe.)

### Bench sketches (standalone, NOT in production sketch)
- W5500_bringup.ino       — chip detect + link (EMAC era)
- W5500_reach / reach2    — EMAC reachability (crashed on connect)
- W5500_udp.ino           — EMAC udp.begin crash test (crashed)
- W5500_spi_min.ino       — stock-SPI minimal, all 6 init calls PASS
- W5500_spi_connect.ino   — stock-SPI + connect, FULL PASS (CCAPI dump)

### Still to do (next session)
- Integrate direct-SPI EthernetClient into production ccapiRequest() behind a
  now-REAL STUB_WIRED_ETHERNET switch (currently comment-only; no Ethernet
  code in production sketch yet).
- Resolve the deferred DUAL-SUBNET / dual-interface design: production runs
  WiFi (operator UI/Excel) AND wired (CCAPI to camera) together. Bench test
  ran wired-only to avoid the routing ambiguity; that ambiguity must be
  designed for before integration (likely: camera on a separate subnet, e.g.
  192.168.2.x, so wired CCAPI traffic is unambiguous).
- D7 shutter stays sacred. Shutter-over-HTTP still a separate later decision,
  to be MEASURED against the D7 baseline if ever pursued.

### Corrections to apply elsewhere in PROJECT_STATE
- #69 wired-Ethernet build: transport now PROVEN (was "future/reserved").
- Any "W5500 future" notes: chip + direct-SPI transport confirmed working.
