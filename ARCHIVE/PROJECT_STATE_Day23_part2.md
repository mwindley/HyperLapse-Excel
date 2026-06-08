# Session H — Day 23 (part 2, 29 May 2026) — Soak instrument built + validated

**Paste into PROJECT_STATE.md above the Day-23 (part 1) block.**

---

## Soak-test instrumentation (#63) — built and validated end-to-end

Built the on-cart soak harness so a 4-hour WiFi-CCAPI soak produces a
readable failure record without depending on the network being tested.
All validated by measurement (log + camera + images), not assumption.

### Servo D4 -> D5 (clears SD CS conflict)
The Ethernet Shield 2 microSD CS is hard-wired to **D4**, which was the
steering servo. Servo moved to **D5** (PWM-OK on Giga; valid PWM range
is 2-13 — pins outside that crash mbed OS). `CART_SERVO_PIN 5`, header
comment updated, servo wire physically moved D4->D5. Re-tested:
centres on boot, /btn4 + /btn3 ramp smoothly. D4 now free for SD CS.

### microSD logging on the W5500 shield (CS=D4)
- Card debug first (standalone SD_Debug.ino): init/write/read/append all
  PASS — but ONLY after formatting. New cards ship exFAT; stock SD lib
  needs FAT32. 58 GB card couldn't FAT32 via Windows dialog (>32 GB
  hides the option); used a smaller (<=32 GB) card formatted FAT32.
- Built into production behind `#define SOAK_LOG` (compiles out cleanly):
  - All CCAPI calls routed through a logging wrapper (`ccapiRequest`
    now wraps `ccapiRequestRaw`): one CSV row per call — ms, method,
    path, HTTP status, round-trip ms.
  - Mode-flip hooks: LIVE->TABLE and TABLE->LIVE logged (dropout
    signatures).
  - Heartbeat ~10s: ms + WiFi RSSI (slow-droop / disconnect signal).
  - Buffered (flush every 20 lines or 10s), auto-incrementing filename
    SOAK_NNN.CSV, SD failure NON-FATAL (cart runs regardless).
  - Holds W5500 CS high in the wireless build so the card has the SPI
    bus (Ethernet not begun when STUB_WIRED_ETHERNET defined).
- Read-back over WiFi (no card pull): `/soak/info` (file, bytes, lines,
  rssi) and `/soak/tail?n=N` (last N lines, cap 100). Caveat: can't see
  the log DURING a WiFi drop, but drop-time rows are on the card and
  read back after recovery — fine for the soak's purpose.

### Soak MODE (self-contained CCAPI stress cycle)
`/soak/start?ms=2000` / `/soak/stop`. Per frame: PUT Tv (alternating),
optional GET every 3rd frame, then photo over CCAPI last. Deliberately
does NOT trigger TABLE-mode fallback, so dropouts stay VISIBLE in the
log rather than being silently recovered.

### Two real bugs found and fixed during shakedown (by reading the log)
1. **PUT Tv returned 503** (device busy). Cause: PUT issued ~100ms
   after the shutter hit the camera mid-capture. Fix: reorder — PUT
   (and GET) first on an idle camera, photo LAST.
2. **PUT Tv then returned 400** (bad value). Cause: hand-built body
   sent `0.5`/`0.4`, not valid Canon Tv strings. Fix: use the proven
   `ccapiPutTv()` path (jsonEscapeTv + 503 retry) with Canon seconds
   notation `0"5` / `0"4`. 0.5s exposure retained deliberately — it
   keeps capture inside the 2s interval with camera-recovery margin.

### Final validation (measured)
- Log: every call 200 — PUT/GET `/tv` and POST `/shutterbutton`.
  RTTs healthy (PUT 119-415ms, GET ~100ms, POST ~200ms). HB RSSI
  steady -30 to -34 (AR3277 aerial). ~2s frame spacing.
- Camera: Tv physically alternating 0"5 / 0"4.
- Card: images alternating 0.5s / 0.4s exposure — full loop proven
  (PUT applies -> shutter fires at new setting -> image lands).

### Build-flash gotcha (RECURRING — capture in PREFERENCES)
Giga uploads can silently NOT take (compile succeeds, board keeps old
binary). Symptom: newly-added handlers missing while old ones work
(here: /soak/start fell through to UI while /soak/info worked). Bit a
prior session too. Mitigation now in place: a boot `[build] soak-vN`
marker line — bump it each edit; the banner proves which binary is
live. Recovery if a flash won't take: reflash watching the UPLOAD
phase complete (not just compile/verify); double-tap reset -> reselect
COM port -> upload; power-cycle if DFU won't connect.

### Status / next
- Soak instrument COMPLETE and validated. Ready for the real 4-hour
  run on the van AX6000 (cart 192.168.20.97, camera 192.168.20.99).
- Procedure: `/soak/start?ms=2000`, leave 4h, read the log. Verdict =
  did all statuses stay 200 (WiFi held) or do non-200 / MODE-flip rows
  appear (dropouts); does RSSI stay healthy.
- Strategy: prefer wireless (no gimbal cables). 4h soak -> if clean,
  12h -> if clean, commit wireless and keep D7 + wired-HTTP as proven
  reserves for the field. If field WiFi fails, fallbacks are ready.

### Addressing (van network, DHCP pool .100+; statics below)
- Cart (Giga WiFi): 192.168.20.97   (camera WiFi: .20.99)
- Camera wired HTTP (if ever used): 192.168.20.98
- WiFi and wired-CCAPI will NOT coexist — one transport, decided after
  testing. No dual-subnet ambiguity.
