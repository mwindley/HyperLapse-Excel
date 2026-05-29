## Session G (cont.) / Day 22 — Wired Ethernet (W5500) CCAPI relay COMMISSIONED

**Outcome: PASS.** Browser-driven wired CCAPI relay working end to end:
laptop URL -> Giga (WiFi) -> camera (wired W5500 CCAPI). WiFi and wired
run simultaneously. Camera obeys real exposure commands over the wire.

### What works (proven this session)
- Direct-SPI W5500 transport: connect + GET + PUT all succeed.
- Relay web server on the Giga: /ccapi (wake), /get/tv, /get/iso,
  /tv?v=, /iso?v=, /link — each relays to the camera over the wire.
- Verified live: Tv PUT 1/5000 (camera physically moved), ISO PUT 200
  (camera changed), reads return correct values, /ccapi returns 200 ALIVE.
- Dual-interface coexistence: WiFi (Rosedale) + wired W5500 up together,
  stable, no conflict — because camera is on a SEPARATE subnet.

### THE critical architecture finding
The mbed-EMAC library route FAILED (crashes on any socket open — both
TCP connect() and udp.begin() hard-fault the board; linkStatus unreliable).
The WORKING path is the STOCK Arduino Ethernet library (utility/w5100.h),
which drives the W5500's OWN hardware TCP/IP stack directly over SPI,
bypassing mbed networking:
    #include <SPI.h>  #include <Ethernet.h>
    Ethernet.init(10);            // CS = D10
    Ethernet.begin(mac, ip);      // static
    EthernetClient.connect(...)   // works
Diagnostic that cracked it: minimal sketch bracketing each init call with
flushed >>>/<<< prints to pinpoint the faulting call. (begin/init/status
all OK; only the EMAC socket layer faulted — stock Blink ran fine, proving
runtime fault not upload.)

### Network topology (separate subnets — key to coexistence)
- WiFi (laptop UI):  Giga 192.168.1.x on Rosedale (DHCP gave .116; SHOULD
  be pinned static — see open items).
- Wired (camera):    Giga 192.168.20.98, camera 192.168.20.99/255.255.255.0,
  point-to-point. CS=D10. Separate subnet so 192.168.20.x routes to W5500
  by mask while WiFi keeps the default route. No routing ambiguity.

### Operational lessons (camera behaviour)
- **Settle-first rule:** connect only AFTER the wired link is LinkON and the
  camera LAN is enabled/settled. Connecting into a half-ready link fails
  (all connects FAILED when fired at link=2). Wake/confirm (GET /ccapi/)
  first, then commands.
- **Camera LAN LED red = no LAN; green = LAN up.** NOT a CCAPI-session
  indicator (earlier guesses wrong). Confirmed by behaviour.
- **No auto-reenable:** when the Giga/W5500 reboots or loses power, the
  camera LAN drops to RED and only comes back on MANUAL enable in the camera
  menu. This is a real design gap for an unattended cart (a Giga reset kills
  the wired path until someone touches the camera). See open items.
- **ISO 400 was camera STATE, not a bug.** First ISO PUT returned 400; the
  IDENTICAL request (same body {"value":"200"}, same path) later returned
  200 and changed the camera, once the session was cleanly settled. The 400
  meant "not right now," not "bad request." Tv/ISO bodies need no escaping
  for simple values (jsonEscapeTv only for quote-bearing Tv like 0"3).

### Bench sketches (standalone, NOT in production)
W5500_bringup / reach / reach2 / udp (EMAC era — failed),
W5500_spi_min (init pinpoint, PASS), W5500_spi_connect (CCAPI GET PASS),
W5500_ccapi_put (Tv PUT pass, ISO 400-then-OK), W5500_delayed (settle test),
W5500_dual / dual_wait (coexistence), W5500_relay (browser relay — the
working demonstrator).

### Open items (next session)
1. **Camera LAN auto-reenable** — investigate R3 menu (Network settings ->
   Connection option settings: the "don't disconnect from LAN" / power-mgmt
   toggle). Canon R3 HAS auto-reconnect machinery (FTP power-save proves it)
   and fixed-IP makes re-enable fast, but auto-restore for wired CCAPI after
   a W5500 reboot is UNCONFIRMED. This decides whether wired CCAPI is viable
   unattended. (Operator to check on the body.)
2. **Pin WiFi static IP** — currently DHCP (floats .116/.97). Add
   WiFi.config(ip, gateway, subnet) BEFORE WiFi.begin() so the relay URL is
   stable. Need: target IP (.97?), gateway (192.168.1.1?), mask 255.255.255.0.
3. **Production integration** — fold the direct-SPI EthernetClient into
   ccapiRequest() behind a now-REAL STUB_WIRED_ETHERNET (currently
   comment-only). Keep WiFi for UI; route CCAPI over wire.
4. **D7 shutter stays sacred.** Shutter-over-HTTP still a separate, later,
   MEASURED decision against the D7 baseline — not done, not assumed.
