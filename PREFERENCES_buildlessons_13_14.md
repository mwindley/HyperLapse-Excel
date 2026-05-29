## Build lessons — add to the numbered list (next are #13, #14)

13. **W5500 Ethernet on Giga R1: use the STOCK Arduino Ethernet library
    (direct-SPI), NOT the mbed-EMAC route.** The Giga has no official Ethernet
    support, so community paths abound — but they split into two families with
    opposite outcomes. The W5500-EMAC library (routes through mbed's networking
    stack) brings the interface up but HARD-FAULTS the board on any socket open
    — both TCP connect() and udp.begin() crash it (red LED / boot loop), while
    stock Blink runs fine (proving runtime fault, not upload). Its linkStatus()
    is also unreliable (stuck LinkOFF through a real cable unplug). The WORKING
    path is the stock Arduino Ethernet library (the one with utility/w5100.h),
    which drives the W5500's OWN hardware TCP/IP stack directly over SPI,
    bypassing mbed networking: Ethernet.init(10); Ethernet.begin(mac, ip);
    then EthernetClient.connect() — proven to return 1 and pull a full CCAPI
    response over the wire. Lesson: on the Giga, prefer the chip's own stack
    over the mbed EMAC abstraction. Also: stock lib has no setConnectionTimeout()
    (use setRetransmissionTimeout/Count); calling the missing method crashed
    begin-time until removed. Diagnostic that cracked it: a minimal sketch that
    brackets each init call with flushed >>>/<<< prints to pinpoint the exact
    faulting call. (Day 22.)

14. **Arduino IDE Library Manager auto-update silently breaks known-good
    library setups — DISABLE it.** On the Giga, the W5500 Ethernet library must
    be MANUALLY copied from the mbed_portenta package's bundled libraries into a
    sketchbook libraries path (the Giga build does NOT search the Portenta
    package's own libraries folder). Library Manager auto-update will, without
    asking, install the GENERIC Arduino Ethernet (e.g. 2.0.2) which SHADOWS the
    manually-placed one and breaks the include (PortentaEthernet.h not found),
    or swaps the wrong library entirely. This cost significant time mid-session.
    Two libraries both claim the <Ethernet.h> name: the Portenta/EMAC one
    (has PortentaEthernet.h) and the stock SPI one (has utility/w5100.h) — only
    ONE can be the active "Ethernet" folder at a time; rename the others aside
    (e.g. Ethernet_PORTENTA_EMAC). Disable auto-update via the advanced setting:
    settings.json -> "arduino.checkForUpdates": false  (file lives at
    C:\Users\<user>\.arduinoIDE\settings.json). It is NOT in the normal
    Preferences panel. Manual installs via Library Manager still work after
    disabling; only the silent background swaps stop. (Day 22.)
