# HyperLapse Cart — Project State

> **ARCHIVE / HISTORY ONLY.** This file is the session-by-session build record.
> It does NOT describe current state. For "where things are now" read
> **PROJECT_STATE.md** (NOW); for open work read **WORKFRONTS.md** (NEXT).
> Relocated WORKFRONTS dated-history blocks, the two build-complete workfront
> docs (cable-UI, moon-astro), and the Day 25 -> Day 31 session summaries are
> appended at the END of this file (history only — their live content was
> migrated into PROJECT_STATE.md / WORKFRONTS.md).

## Session bootstrap — files to load

At the start of every new Claude session, upload these so the
assistant has full project context. (List refreshed Day 25 after the
big consolidation — the three state docs and the loose reference docs
were merged/sorted; superseded files moved to ARCHIVE\.)

**Load first (core state — always):**
- PROJECT_STATE_CONSOLIDATED.md  — current state + day-by-day narrative (this file)
- WORKFRONTS.md                  — open + closed workfronts; the #40 BNO build now lives in its own section here
- PREFERENCES_CONSOLIDATED.md    — working style, build lessons (1–17), standing rules
- GIGA_PIN_PLAN.md               — Giga pin assignments + I²C/CAN/W5500 wiring + collisions (LIVE hardware reference)

**Production sketch (the cart runs on the Giga now — Uno retired Day 18):**
- DJI_Ronin_Giga_v2.ino          — current production sketch (the live one; "soak-vNN" in its boot banner)

**Reference docs — load on demand for the relevant work:**
- PLAN_AUTHORING.md              — single source of truth for the Excel Plan-authoring surface (P1–P10)
- GIMBAL_EXECUTION_CAPABILITIES.md — what each gimbal GP type does + the push pipeline (live gimbal-exec reference)
- UI_DESIGN_v2.md                — three-screen UI spec (Execution screen still unbuilt; action-type taxonomy section carries a stale-vocabulary note)
- GIMBAL_VIZ.md                  — Day-8 gimbal plan/visualisation design (older; some vocabulary predates PLAN_AUTHORING)
- EXPOSURE_FALLBACK.md           — table-mode + exposure fallback reference
- BNO085_BenchTest_Giga.ino      — the polled BNO bench sketch (heartbeat/stall probe) used for #40

**Archived (in ARCHIVE\ — historical, do NOT treat as current):**
- DJI_Ronin_UnoR4_v1prod.ino     — the old Uno production sketch (retired Day 18; superseded by the Giga sketch above)
- GIGA_MIGRATION_STRATEGY.md     — #47 7-step migration plan (migration COMPLETE Day 23)
- GIGA_DESIGN.md                 — Day-18 Giga design draft (overtaken by what's built)
- HANDOFF_Day24_partA_next.md, P6_ANCHOR_RESOLVER.md, SESSION_D_DAY19/E_DAY20/F_DAY21.md — spent handoff/build/session notes, folded into the state docs
- the WORKFRONTS_Day*/PROJECT_STATE_Day*/PREFERENCES_buildlesson* fragments — merged into the consolidated files above
- WORKFRONTS_old_ver1.md         — archived day 6–11 workfront narrative

Note: Claude has no cross-session memory. These files ARE the memory.

---

**Last updated:** 29 May 2026 — Session H, day 23 (part 2). Newest
session narrative is first; older sessions follow in reverse-
chronological order (Day 23 → 22 → 21 → 20 → 19 → 18 → 17 → 15 → 13 → 12 → archived).
The "State of the system (current)" summary near the bottom carries the
standing status.

---

## Session H — Day 23 (part 2, 29 May 2026) — soak instrument built + validated

Built the on-cart soak harness so a multi-hour WiFi-CCAPI soak produces
a readable failure record without depending on the network under test.
All validated by measurement (log + camera + images), not assumption.

- **Servo D4 → D5 (clears SD CS conflict).** The Ethernet Shield 2
  microSD CS is hard-wired to D4, which was the steering servo. Servo
  moved to D5 (`CART_SERVO_PIN 5`; Giga PWM-valid range 2–13 — pins
  outside crash mbed OS), wire physically moved, re-tested (centres on
  boot, /btn4 + /btn3 ramp smoothly). D4 now free for SD CS.
- **microSD logging on the W5500 shield (CS=D4).** Card debug first
  (SD_Debug.ino) PASS — but only after FAT32 formatting (new cards ship
  exFAT; stock SD lib needs FAT32; >32 GB hides the Windows FAT32
  option, so use a ≤32 GB card). Built into production behind
  `#define SOAK_LOG` (compiles out clean): all CCAPI calls routed
  through a logging wrapper (`ccapiRequest` wraps `ccapiRequestRaw`) —
  one CSV row per call (ms, method, path, status, RTT); LIVE↔TABLE
  mode-flip hooks; ~10 s RSSI heartbeat; buffered (flush every 20 lines
  / 10 s); auto-incrementing SOAK_NNN.CSV; SD failure NON-FATAL. Holds
  W5500 CS high in the wireless build so the card owns the SPI bus.
  Read-back over WiFi (no card pull): `/soak/info`, `/soak/tail?n=N`.
- **Soak MODE.** `/soak/start?ms=2000` / `/soak/stop`. Per frame: PUT Tv
  (alternating) + optional GET every 3rd + photo over CCAPI LAST.
  Deliberately does NOT trigger TABLE fallback, so dropouts stay VISIBLE
  in the log.
- **Two real bugs found by reading the log:** (1) PUT Tv 503 (device
  busy) — PUT issued ~100 ms after a shutter hit the camera mid-capture;
  fix = reorder, PUT/GET first on an idle camera, photo last. (2) PUT Tv
  400 (bad value) — hand-built body sent `0.5`/`0.4`, not valid Canon Tv;
  fix = use `ccapiPutTv()` (jsonEscapeTv + 503 retry) with seconds
  notation `0"5`/`0"4`.
- **Final validation (measured):** log all 200 (PUT/GET `/tv`, POST
  `/shutterbutton`; RTTs PUT 119–415, GET ~100, POST ~200 ms; HB RSSI
  −30 to −34 on the AR3277); camera Tv physically alternating 0"5/0"4;
  card images alternating 0.5/0.4 s — full loop proven.
- **Build-flash gotcha (RECURRING — in PREFERENCES).** Giga uploads can
  silently NOT take (compile OK, board keeps old binary; new handlers
  missing while old ones work). Mitigation: boot `[build] soak-vN`
  marker — bump each edit. Recovery: watch the UPLOAD phase complete;
  double-tap reset → reselect COM → upload; power-cycle if DFU won't
  connect.
- **Status/next:** instrument COMPLETE + validated; ready for the real
  4 h run on the van AX6000 (cart 192.168.20.97, camera 192.168.20.99),
  then 12 h; if clean, commit wireless and keep D7 + wired-HTTP as
  proven reserves. Van addressing: cart .20.97, camera WiFi .20.99,
  camera wired-HTTP .20.98; WiFi and wired-CCAPI will NOT coexist (one
  transport, decided after testing).

---

## Session H — Day 23 (part 1, 29 May 2026) — cart recommissioned on the Giga R1

First integrated power-up of the reassembled cart on the Giga. Day 22
proved CAN and the W5500 each in isolation on a stripped bench
(STUB_CART on, one subsystem at a time); this session brought the whole
existing stack up together for the first time — CAN gimbal + Tic-I²C +
steering servo + WiFi/Excel/UI + D7 shutter — verified low-to-high, no
faults. **All existing capability is back online on the Giga.** Scope
was bounded to recommissioning existing capability; BNO (#40) full
integration and the W5500 wired build (#69) were handled separately as
new capability (below).

**Recommissioning order (each verified before the next):**
1. **CAN quick repeat** (Day-22 sketch, STUB_CART on). Clean boot (CRC
   OK, CAN 1 Mbps, WiFi .1.97). TX `/home` → gimbal slewed home, yaw
   read 0.3. RX hand-move → yaw −37.1 / pitch −18.9 tracked.
   Bidirectional confirmed; Day-22 reproduced.
2. **I²C bus scan** (standalone no-drive scanner on Wire D20/D21 —
   one-variable discipline, sidesteps the Day-22 empty-bus trap). Exactly
   three acks: 14 (Tic front), 15 (Tic rear), 0x4A (BNO085). No phantom
   0x60. External 4.7 kΩ pull-ups good with all three on the bus.
3. **D7 shutter** (production sketch, STUB_CART still on so shutter is
   the only variable). `/shutter/pin8` → red LED, image on card. Sacred
   photo path confirmed on the Giga.
4. **STUB_CART removed** — first un-stubbed boot: `[Cart] Tic
   controllers and servo initialised.`, servo snapped to centre (98),
   no I²C hang on live Tic init.
5. **Servo steering** `/btn4` (+5) ramped at 1°/s and settled; `/btn3`
   back.
6. **Tic drive** (Cart Recon UI): energise → +1 → +10 → STOP decel.
   Full motion path confirmed — bus, both motors, ramps, decel stop.

**New-capability bench work (same session, standalone sketches; NOT
folded into production — STUB_BNO and STUB_WIRED_ETHERNET both stayed
defined until the integration below):**

- **BNO085 first-light on the Giga (polled, shared Wire bus).** Giga-safe
  rewrite of the Day-12 bench sketch — polled `begin()` (no INT), no
  `Wire.setClock()` (hangs the Giga), Wire on D20/D21, no INT/RST.
  Connected, rotation vector @10 Hz, figure-8 → acc 0→2→3, converged and
  held at acc=3 at rest. True-north offset path verified. **Heading +
  sign:** a deliberate 40° CW rotation → iPhone 40°, BNO true_yaw −40 —
  magnitude within ~0.5°, **sign opposite** (BNO CW = negative, world CW
  = positive) → negate BNO yaw when folding into the gimbal correction.
  (See `WORKFRONTS_CONSOLIDATED.md` #40 section for the full build.)
- **W5500 wired Ethernet — dual-interface CCAPI proven end-to-end.**
  `W5500_relay.ino` (WiFi server + wired W5500 simultaneously;
  laptop→Giga over WiFi relays to camera over the wire), reusing the
  Day-22 stock-SPI path (SPI.begin → Ethernet.init(10) → Ethernet.begin,
  NOT mbed EMAC). **Subnet design resolved (Day-22 deferred question):
  camera moved to its own subnet** — camera wired .20.99, Giga wired
  .20.98; WiFi/Excel/UI stay on .1.x → no routing ambiguity. `/ccapi` →
  200 ALIVE; `/get/tv` → 200 + ladder; `/tv?v=1/5000` PUT → 200, camera
  confirmed. Note: read `wired_link` after a grace period (reads 2/
  LinkOFF for the first instant before the PHY negotiates).

**Production sketch — transport switch integrated + hygiene (same
session).** Decision: `#define`, not runtime — production ships ONE
transport; A/B soak each, then pick (WiFi outage is handled by TABLE
mode; wired is the alternative, not a live failover).
- **STUB_WIRED_ETHERNET now a real switch:** DEFINED → CCAPI over WiFi,
  camera .1.99 (v1 path, unchanged); UNDEFINED → CCAPI over wired W5500,
  camera .20.99, Giga wired .20.98, direct-SPI stock Ethernet. WiFi/
  Excel/UI run in BOTH builds — only the camera transport changes.
  `ccapiRequest()` got a one-line client-type switch (WiFiClient vs
  EthernetClient); body otherwise unchanged (already a manual bounded
  wait, so the Day-22 setConnectionTimeout trap doesn't apply).
- **#68 D9 shutter-readback STRIPPED** (define, pinMode, three
  digitalRead in `backupShutter`); D7 200 ms pulse timing preserved
  exactly; D9 unwired/free; zero digitalRead left. Stale header comments
  fixed (BNO is I²C/0x4A not UART-RVC; W5500 built not future).
- **Both builds compile clean** (only the known Arduino_CAN/Servo
  arch-tag warnings): WiFi 379,508 (19%) / 92,392 globals (17%) — ≈
  Day-22, confirming no behavioural change; wired 394,588 (20%) /
  94,648 (18%), +15 KB for the Ethernet lib. **Resolves the open
  question: Ethernet.h + WiFi.h coexist in the full build.**
- **Wired CCAPI proven IN THE PRODUCTION SKETCH** (not just the relay):
  wired build boot `[WIRE] hwStatus=3 ip=192.168.20.98`, WiFi up at .97;
  `/exposure/init` → ok:true, current_tv=1/5000 (the value PUT over the
  relay earlier), ISO 320; two clean REQ-PHASES (connect 0–1 ms, 67/63
  ms totals). (STUB_CART left defined for this flash — Tic power off,
  wired test needs no cart; must come out for any cart-involved soak.)
- **AR3277 WiFi aerial fitted:** RSSI −67/−68 (bare) → **−31 dBm**.

**Notes.** Integration risks (#61 ISR-vs-network, #52 I²C cliff) did NOT
bite in this short bring-up — they are load/duration-dependent; real
confidence is the #63 soak. Dead-stop (btn12) absent from Cart Recon UI
is intentional (Day-16 v2 spec); handler still fires by URL; no workfront.

**Workfront status changes (Day 23):**
- **#47 Giga migration — recommissioning of existing capability
  COMPLETE.** Steps 1–5 + the Step-7 v2 sketch validated running
  together; Step 6 coexistence effectively satisfied. #63 multi-hour
  soak remains the gate before Step 7 is fully done.
- **#40 BNO085 — bench-validated on Giga** (acc=3, true_yaw path, ±0.5°
  vs iPhone, sign characterised). Standalone only; STUB_BNO still
  defined in production at this point. (Now fully built — see #40 in
  WORKFRONTS.)
- **#68 — DONE** (D9 stripped). **#69 W5500 — INTEGRATED + proven** in
  the production sketch (compile-time switch, both compile, wired
  round-trips via /exposure/init); subnet resolved; remaining = #63 soak
  of each build + final WiFi-vs-wired decision. **D7 — first live frame
  on the assembled Giga** (verifies the Day-18 D8→D7 assignment).

---

## Session G — Day 22 (28 May 2026, cont.) — wired Ethernet (W5500) CCAPI commissioned

**Outcome: PASS.** Browser-driven wired CCAPI relay working end-to-end
(laptop URL → Giga over WiFi → camera over wired W5500), WiFi and wired
running simultaneously, camera obeying real exposure commands over the
wire. Goal: commission wired HTTP (CCAPI over Ethernet) so exposure
control survives an external-WiFi outage; D7 hardware shutter stays the
sacred photo path; shutter-over-HTTP remains a separate deferred
decision.

**THE critical architecture finding (not config).** Two library FAMILIES
were tried; only the second works on the Giga:
- **W5500-EMAC (JAndrassy) — DOES NOT WORK for data transport.** Routes
  the W5500 through mbed's networking stack; brings the interface up
  (chip detected) but HARD-FAULTS the board (red LED / boot loop) on ANY
  socket open — both TCP connect() and udp.begin() fault. Confirmed a
  runtime fault in the EMAC socket layer, not upload/hardware (stock
  Blink runs fine). Its linkStatus() is also unreliable (stuck LinkOFF
  through a real cable unplug). Dead end.
- **Stock Arduino Ethernet library (utility/w5100.h) — WORKS.** Talks
  DIRECTLY to the W5500 over SPI using the chip's OWN hardware TCP/IP
  stack, bypassing mbed networking: `Ethernet.init(10)` (CS=D10) →
  `Ethernet.begin(mac, ip)` (static, no DHCP point-to-point) →
  `EthernetClient.connect()` returns 1, GET /ccapi/ → 200 + full
  endpoint JSON. Most mature path in the ecosystem (~15-yr W5100
  lineage). NO `setConnectionTimeout()` — use `setRetransmissionTimeout/
  Count` if bounding is needed (an early crash was a call to the
  non-existent setConnectionTimeout; removing it fixed it). Diagnostic
  that cracked it: a minimal sketch bracketing each init call with
  flushed >>>/<<< prints to pinpoint the faulting call.

**Relay + dual-interface coexistence proven.** Relay web server on the
Giga (/ccapi wake, /get/tv, /get/iso, /tv?v=, /iso?v=, /link), each
relaying to the camera over the wire. Verified live: Tv PUT 1/5000
(camera moved), ISO PUT 200 (camera changed), reads correct, /ccapi 200
ALIVE. WiFi (Rosedale) + wired W5500 up together, stable — **because the
camera is on a SEPARATE subnet:** WiFi Giga .1.x; wired Giga
192.168.20.98, camera 192.168.20.99/24 point-to-point, CS=D10. Separate
subnet so .20.x routes to the W5500 by mask while WiFi keeps the default
route — no routing ambiguity. (This resolved the dual-subnet question
the first wired bring-up had left open.)

**Operational lessons (camera behaviour):**
- **Settle-first rule:** connect only AFTER the wired link is LinkON and
  the camera LAN is enabled/settled — connecting into a half-ready link
  fails (all connects failed when fired at link=2). Wake/confirm (GET
  /ccapi/) first, then commands.
- Camera LAN LED red = no LAN, green = LAN up (NOT a CCAPI-session
  indicator).
- **No auto-reenable:** when the Giga/W5500 reboots or loses power, the
  camera LAN drops to RED and only returns on MANUAL menu enable — a
  real gap for an unattended cart. (Open: R3 Network → Connection option
  settings power-mgmt toggle; Canon R3 has auto-reconnect machinery for
  FTP, but auto-restore for wired CCAPI after a W5500 reboot is
  UNCONFIRMED — decides whether wired CCAPI is viable unattended.)
- **ISO 400 was camera STATE, not a bug** — the identical request later
  returned 200 once the session settled. Tv/ISO bodies need no escaping
  for simple values (jsonEscapeTv only for quote-bearing Tv like 0"3).
- Open: pin the WiFi static IP (was DHCP, floats .116/.97) via
  WiFi.config() before WiFi.begin().

(Bench sketches, standalone: W5500_bringup / reach / reach2 / udp =
EMAC era, failed; W5500_spi_min = init pinpoint PASS; W5500_spi_connect
= CCAPI GET PASS; W5500_ccapi_put = Tv PUT pass / ISO 400-then-OK;
W5500_dual / dual_wait = coexistence; W5500_relay = the working browser
relay.) **#69 wired-Ethernet transport now PROVEN** (was future/
reserved). Production integration done in the Day-23 session above.

---

## Session G — Day 22 (28 May 2026) — Step 3 CAN passed end-to-end

Hardware bring-up. The SN65HVD230 cooked on Day 18 (reversed 3V3/GND)
was replaced with an **Adafruit CAN Pal (5708, TJA1051T/3)** per
GIGA_PIN_PLAN.md. Wired CAN-only on the bench (Tic, servo, BNO, W5500
all unwired) to isolate CAN as the single variable. Bidirectional CAN to
the RS4 Pro confirmed end-to-end — **Step 3 of GIGA_MIGRATION_STRATEGY
is PASSED**, closing the gap left when the old transceiver died.

- **Wiring (confirmed correct by the result):** CAN Pal CTX→Giga CANTX,
  CRX→CANRX, **S→GND** (normal/active mode — the pin the old SN65HVD230
  lacked; floating = silent mode = bus appears dead), VCC→3V3 (onboard
  charge pump makes the 5V the TJA1051 core needs; no external 5V/VIO on
  this header variant), GND→GND, CANH/CANL→gimbal bus. Termination left
  as-is (gimbal end already terminated).
- **Core updated to 4.x (mbed_giga) before the session** — added a
  second variable on top of the new transceiver; mitigated by treating a
  clean compile + boot CRC self-test as the toolchain gate. Compile
  warnings (Arduino_CAN / Servo "may be incompatible with mbed_giga")
  are arch-tag metadata gaps, NOT functional — `CAN.begin()` succeeding
  proved the bundled Arduino_CAN driver brings up the Giga FDCAN
  peripheral. There is only ONE CAN driver (bundled); nothing to
  select/install; no Tools-menu CAN config (bitrate/IDs are code-level).
  Build: 379,900 flash (19%) / 92,392 globals (17%) — tiny vs the Uno's
  ~52%/69%, the headroom the migration predicted.
- **STUB_CART — new bench-isolation stub.** When defined, all I²C/Tic +
  servo access is skipped (zero I²C traffic so CAN is the only variable).
  Guards at THREE sites: setup() (Wire.begin, Tic halt/exitSafeStart,
  servo attach/write), cartLoop() (2 s Tic voltage poll), buildStatusCSV()
  (Tic getCurrentPosition → reports 0). **Must be removed when Tic/servo
  are reassembled** — bench-only.
- **buildStatusCSV I²C crash found + fixed mid-session.** First flash
  guarded only setup + voltage poll, not buildStatusCSV. TX tested fine
  (`/home` → gimbal home) but the first `/status` hit **hard-faulted the
  board** (red LED) — `buildStatusCSV()` called `ticRear.
  getCurrentPosition()`, an I²C read to a Tic that wasn't wired and had
  no pull-ups; on the empty bus it faulted the Giga. Added the third
  guard, re-flashed, `/status` worked — before/after confirms
  I²C-on-empty-bus was the cause. (PREFERENCES build lesson.) Recovery:
  double-tap reset hit a DFU COM port that wouldn't connect; **power-
  cycle** recovered cleanly (add power-cycle as the fallback to the
  Day-18 double-tap note).
- **Test results — Step 3 PASSED.** Boot clean (CRC OK, CAN 1 Mbps,
  push subscribe sent, WiFi .1.97 at RSSI −81). TX `/home` → gimbal
  slewed home. RX hand-move → yaw tracked −63.0 → 0.3.
  Commanded-vs-reported both directions at once: `/move?yaw=45&pitch=10`
  → `/status` read back 45.5, 0.0, 10.0 (the 0.5° is settle tolerance,
  pitch dead on) — strongest end-to-end confirmation. No sign of #54
  large-slew overshoot in settled readings (#54 fix remains deferred).
- **Notes:** WiFi RSSI −81 weak for bench proximity (no CAN effect, flag
  if WiFi flakiness appears). #66 empty-connection cost still present
  (favicon/speculative pre-connects → req_len=0 dropped + LOOP-LONG,
  cosmetic). DFU recovery: power-cycle was reliable, double-tap was not.
- **Workfront status changes:** Step 3 (CAN) PASSED (was "paused on
  cooked transceiver" since Day 18); all foundational Giga subsystems
  (Steps 1–5) now pass, Step 6/7 remain. **#60 transceiver hardware —
  CLOSED.** STUB_CART removal tracked alongside #68/#69. The CAN-Pal-VCC-
  to-3V3 charge-pump assumption + S→GND normal-mode wiring are now
  confirmed in hardware (GIGA_PIN_PLAN wiring guidance was correct).

---

## Session F — Day 21 (27 May 2026) — P7 plan-push built (Stages 1–3, dry-run), MW→GC rename

Hardware (replacement transceiver + W5500) had arrived but wasn't yet
assembled, so the Excel Plan-authoring side was worked while the cart was
offline. Full detail was in SESSION_F_DAY21.md (now archived).

- **P7 `PushGimbalPlan` — Stages 1–3 BUILT + verified end-to-end in
  dry-run** against the live Plan sheet (Stage 4, the real push, deferred
  until hardware reassembled). Built on a working copy `HyperLapse_P7.xlsm`
  (made from `HyperLapse.xlsm` per the work-on-a-copy rule; original
  untouched), carrying the Session-E layout (middle zone M..AB, right zone
  AD..AM) + the GP01..GP04 demo rows with verified P6 anchor-resolver
  formulae.
- **#67 Phase 1 — `mw` → `gc` rename executed.** The Milky-Way galactic-
  centre object token and all object-identity code became `gc`
  (the unrelated firmware "Movewatch / MW" feature was deliberately left
  alone). New Settings named ranges added this session.
- Working preferences held (plain-text, one question at a time, small
  steps, work on a copy).

---

## Session E — Day 20 (26 May 2026) — Plan vocabulary refined, P6 anchor resolver built, P7 designed

Surfaced the Day-19 Plan-authoring artefacts and built P6, then refined
the middle-zone vocabulary and locked the P7 design. Full detail was in
SESSION_E_DAY20.md and P6_ANCHOR_RESOLVER.md (now archived); the living
authoring reference is PLAN_AUTHORING.md.

- **P6 anchor resolver — BUILT + verified.** A live formula in a new
  `Fires at` column (Q) converts each gimbal row's (Anchor type, Anchor
  ref, Offset) into an absolute wall-clock time, recomputed instantly on
  any input change (no macro click). Branches on WP / TIME / ASTRO; nested
  `IF` (not `IFS` — `IFS` returned #NAME? cross-engine); INDEX/MATCH
  (WP # column sits left of Arrives); offset stored in its own
  `Offset (min)` column, not parsed from the ref. Settings astro/anchor
  times converted from text to real Excel time values (type-stable).
  Verified against the worked example + three probe rows.
- **Gimbal action vocabulary refined to the CURRENT set: Pan Follow /
  Lock / Move / Track / Track-yaw / END.** Day-19's "Approach" word was
  dropped — Move handles static targets, Track handles moving (astro)
  targets, Track-yaw is the yaw-only variant (matches firmware
  GTM_YAW='Y'). Dropped derivable columns (Target type, KF); added Ry/Rp,
  Ease (named bands), Total dur (derived); replaced the End-anchor column
  with a sentinel END row. WP #/GP # collapsed to `WP01`/`GP01` text
  labels (the anchor resolver MATCHes against the label column).
- **P7 design locked** (build came Day 21).

---

## Session D — Day 19 (25 May 2026) — Plan Authoring deep design + Excel mockup (P1–P5)

Worked PLAN_AUTHORING.md (the Day-18 design doc) end-to-end, simplified
the vocabulary, and built the first implementation phases as concrete
artefacts. Full detail was in SESSION_D_DAY19.md (now archived); the
living reference is PLAN_AUTHORING.md.

- **P1–P5 built + dry-run verified:** P1 sheet design/layout
  (`Plan_mockup_P3.xlsx`, three colour-coded zones, working derived-column
  formulae, zero formula errors); P2 `PlanBuilder.bas` (CartLog W events →
  Cart Plan left zone); P3 left-zone recompute formulae; P4
  `GimbalLogPuller.bas` (GimbalLog → right zone, detects 4-field today vs
  7-field post-#49 shape); P5 `PlanAuthoring.bas` (five middle-zone
  helpers + the Worksheet_SelectionChange snippet for dynamic dropdowns).
- **Vocabulary (Day-19 interim):** collapsed the old 7-type set to 3
  (Pan Follow / Approach / Lock). NOTE this was superseded at Day 20 by
  the current 6-type set (Pan Follow / Lock / Move / Track / Track-yaw /
  END) — the Day-19 "Approach" term no longer exists; see Day 20 above and
  PLAN_AUTHORING.md.
- **Heading/correction model (carried forward):** cart maintains scalars
  (`gimbal_yaw_correction`, `cart_yaw_accumulator`, `pending_bno_
  correction`); BNO correction is folded in at the NEXT Move, never
  snapped — "smooth, no snaps" is the hard operator constraint. No θ_cart
  cubic from Excel; BicycleModel.bas stays a planning-time validator.
- **Gap note (now closed):** Day 19/20/21 were originally NOT written into
  PROJECT_STATE — these three condensed entries (folded in during the
  Day-25 consolidation) close that gap so the day-by-day narrative is
  continuous Day 18 → 19 → 20 → 21 → 22 → 23.

---

## Day-18 session — Giga Steps 1/2/4/5 passed; Step 7 port + smoke test (24 May 2026)

Session C, day 18, full session.

First half: Giga capability demonstrations (Steps 1, 2, 4, 5
of GIGA_MIGRATION_STRATEGY) all passed end-to-end. Step 3
(CAN) paused on cooked SN65HVD230 transceiver. Step 7 v2
sketch port completed section-by-section across 8 sections,
~5700 lines.
Second half: sketch flashed and smoke-tested. mbed WiFi
accept() semantic bug found and fixed (#65). Excel ↔ Giga
round-trip validated end-to-end. Workfront #55 (moon astro)
closed: full sun-equivalent treatment delivered, validated
against timeanddate.com to within 2 minutes, zero internet
dependency.

**Steps passed today:**
- **Step 1** Blink + Serial. Giga R1 selected on COM12, LED blink
  + Serial.println("alive") at 115200 working.
- **Step 2** WiFi + HTTP server. After running the one-time
  WiFiFirmwareUpdater example (Giga ships without WiFi firmware
  on its onboard storage), SimpleWebServer connected to Rosedale
  at 192.168.1.116, browser hit OK.
- **Step 4** I²C / Pololu Tic. Both Tics responded at addresses
  14 and 15 on the Wire bus (pins 20/21). energize / setVelocity
  2000000 / read velocity / setVelocity 0 / deenergize cycle
  worked cleanly on both motors, all getLastError() reads zero.
  See Build lessons below for the wire-up gotchas.
- **Step 5** CCAPI. Alive check `GET /ccapi/` returned full
  endpoint listing; `POST /ccapi/ver100/shooting/control/shutterbutton`
  with body `{"af":false}` returned 200, photo landed on card.
  Required two fixes from v1prod's HTTP code: see Build lessons.

**Step 3 paused.** SN65HVD230 transceiver killed by reversed
3.3V/GND wiring before CAN test could run. CAN-only test sketch
(DJI_Giga_Step3_CAN.ino) ready to flash once new transceiver
arrives. Sketch verified Arduino_CAN library compiles fine on
Giga BSP; only the bench setup is blocked.

**Other infrastructure this session:**
- GIGA_PIN_PLAN.md created. CAN moves to dedicated CANTX/CANRX
  pins; I²C confirmed on Wire (pins 20/21); shutter moved D8→D7
  to free D8 for future Wire2 if ever needed; BNO085 reserved
  on Serial2 (RX1) UART-RVC; W5500 SPI + D10 + D2 reserved for
  v2 wired-Ethernet build.
- Repos moved off OneDrive path. Now at C:\Github\
  DJI-Ronin-RS4-Arduino and C:\Github\HyperLapse-Excel. Per-repo
  .git folders moved cleanly; remotes unchanged. Done to remove
  any future OneDrive-sync interference even though OneDrive was
  not signed in.
- Arduino IDE compile/index time on Giga settled to ~30s
  steady-state after path move and Editor Quick Suggestions
  remained off. Accepted as Giga's floor (mbed-os is large).

**Build lessons added to PREFERENCES (Day 18):**

1. **Giga mbed WiFi stack needs explicit `\r\n` on HTTP headers.**
   WiFiS3 on Uno R4 was lenient with bare `\n` from `println`;
   Canon CCAPI rejects bare-LF requests with 400 + empty body.
   Use `print("...\r\n")` for every header line. Pattern is RFC
   2616 — the strict one is correct, the lenient one was lucky.
   Diagnosed by curl-vs-Giga comparison (curl fired the shutter
   on first attempt; Giga didn't until headers were fixed).

2. **Giga has three I²C buses; the pins near AREF are Wire1, not
   Wire.** Silkscreen near AREF reads "SDA1/SCL1" — that's the
   Wire1 instance. The default `Wire` bus is on pins 20 (SDA)
   and 21 (SCL) at the other end of the digital header row.
   Wired the wrong pair initially; bus appeared completely dead
   until the sketch was changed to `Wire1.begin()` (which then
   showed BNO085 at 0x4A). Then physically moved wires to pins
   20/21 to use `Wire` per the original pin plan. Pinout reference
   confirmed via Adafruit forum and the GIGA datasheet.

3. **Giga's mbed Wire does NOT apply internal pull-ups when the
   pin switches to peripheral mode.** External 4.7kΩ pull-ups
   to 3.3V on both SDA and SCL are mandatory. Without them, lines
   float at ~1.4V (meter impedance reading) and no device acks.
   `pinMode(20, INPUT_PULLUP)` before `Wire.begin()` is useless —
   Wire reconfigures the pins.

4. **`Wire.setClock(50000)` blocks the Giga mbed Wire.** The
   Pololu-recommended "slow clock for marginal pull-ups" advice
   was for the Uno's I²C stack. On Giga, `setClock(50000)` after
   `Wire.begin()` causes `Wire.begin()` to hang silently — sketch
   prints the banner before it but nothing after. Leave default
   clock; use proper external pull-ups instead.

5. **mbed Wire error codes differ from AVR.** `Wire.endTransmission()`
   returns `1` for NACK (no device at address), not "data too long"
   as the standard Arduino docs say. err=1 from a probe = "nothing
   acked." Don't trust the AVR error-code comments when porting
   I²C code to Giga.

6. **Phantom device at 0x60 in mbed Wire scans.** With nothing
   wired to the bus (just pull-ups installed), `Wire.beginTransmission(0x60)`
   returns success. Harmless — disregard 0x60 in scan results,
   it is not a real device.

7. **Giga ships without WiFi firmware loaded on internal flash.**
   First-time Giga WiFi work requires running the
   STM32H747_System / WiFiFirmwareUpdater example sketch before
   any WiFi sketch will work. Sketch prints "Failed to mount the
   filesystem containing the WiFi firmware" if firmware is missing.

8. **Giga 3.3V/GND reversed kills the SN65HVD230 transceiver.**
   The Uno-tested transceiver breakout was insensitive to which
   way round 3.3V and GND landed (or it survived a brief reverse).
   Giga's 3.3V regulator is upstream so the Giga survived a
   GND/3.3V swap on the transceiver supply pins, but the
   transceiver itself was cooked. Triple-check VCC/GND on any
   3.3V breakout before powering.

9. **Arduino IDE 2 indexing penalty after path moves.** Moving
   the sketch folder (out of OneDrive) caused the language
   server to fully re-index on next open. First three builds
   after move: ~60s, ~60s, ~30s. Steady-state thereafter ~30s.
   Index-time bumps after any sketch-folder relocation are
   expected; let them complete before opening Serial Monitor.

10. **Giga upload requires double-tap reset to enter DFU mode**
    when bricked by a crashed sketch. Hard-faulted sketches show
    a flashing red LED, COM port disappears or changes. Recovery:
    double-tap the small reset button, watch for fading orange
    LED, then upload. The COM port often changes between normal
    mode (e.g. COM12) and DFU mode (e.g. COM11) — re-select
    Tools → Port after the double-tap.

**Workfront status changes:**

- **#47 Giga R1 migration** — substantial progress. Steps 1, 2,
  4, 5 of the 7-step capability-demo plan all passed. Step 3
  paused on transceiver hardware. Step 6 (side-by-side subsystem
  test) and Step 7 (full port) remain. Migration is now strongly
  validated for the foundational subsystems; the decision-point
  Step 6 is the next major checkpoint once Step 3 closes.
- **#52 I²C cliff** — separate confirmation today that external
  pull-ups are required on Giga. Day 17's defensive
  `Wire.setClock(50000)` carryover was wrong for Giga (blocks the
  bus). Pull-up requirement was always universal; v1prod sidesteps
  it because Tic 36v4 internal 40kΩ + short wires were just enough
  on the Uno. On Giga those margins evaporate. Cart-side hardware
  fix (external 4.7kΩ on SDA/SCL) is no longer optional for v2.
- **NEW #60 Step 3 transceiver hardware** — one SN65HVD230
  ordered; spare on hand but reserved for final wire-up after
  the polarity-kill lesson. No urgency; Step 3 sketch already
  written and ready.
- **NEW #61 v2 build discipline — mbed-os failure-mode awareness.**
  v1prod was written for bare-metal AVR. Several patterns that
  worked on Uno are latent hazards on Giga's mbed-os. Capturing
  here so the v2 build (Step 7) avoids the obvious traps.

  *Risk 1 — long blocking calls in `loop()`.* `ccapiRequest` can
  block up to 10s on a connect-fail. On Uno that just stalls; on
  Giga the underlying network stack expects to be serviced and
  may panic or silently drop. v1prod's PROBING state machine
  sidesteps this by replacing long fetches with 1s pings. If
  PROBING is dropped in v2 (the wired-Ethernet path makes
  connect-fail much rarer), the bounded-timeout discipline must
  still hold — every blocking network call ≤ 2s, with retry at a
  higher level if needed.

  *Risk 2 — `String` allocation in hot paths.* /status, /cartlog,
  /gimballog/push all build response strings via repeated
  `String +=`. AVR newlib heap fragments under this pattern;
  mbed-os heap is larger and managed differently, so the bug is
  harder to find but still latent. Multi-hour shoots are where
  it surfaces. v2 should prefer fixed `char` buffers or
  `snprintf` for response building in any path that runs more
  than once per minute.

  *Risk 3 — ISR ↔ blocking network read collision.* v1prod's
  #48 mechanism A (Day 15) was a CAN RX ISR preempting WiFi
  `client.read()`. Giga's interrupt + threading model is
  different but the pattern is unchanged. Arduino_CAN's RX ISR
  vs mbed's network thread is unspecified territory. Defensive
  pattern: drain CAN RX FIFO into a ring buffer in the ISR
  (already what `drainCANRx` does in v1prod) and never call
  network code from within a CAN-touch path.

  *Risk 4 — tight polling without yield.* `planTick`, the main
  loop body, runs every iteration with no `delay()` in the
  common case. On Uno that's fine. On Giga, mbed expects the
  main thread to yield. A no-yield loop can starve the network
  stack and cause silent disconnects. v2 should add a `delay(1)`
  at the bottom of `loop()`, or use mbed's `ThisThread::yield()`.

  *Risk 5 — PROGMEM is a no-op on Giga.* `F("...")` macros around
  served HTML do nothing on Giga's flat memory model. The
  strings live in RAM. With 1 MB available it doesn't matter
  for current usage, but the assumption is silent — a v1prod
  port that lifts the served-HTML verbatim quietly uses ~30 KB
  more RAM than the same code did on Uno.

  *Risk 6 — `millis()` rollover.* Identical behaviour on AVR and
  Giga so long as both sides are `unsigned long`. Day 17 found a
  related bug; same defensive guards apply.

  *Risk 7 — no EEPROM on Giga.* v1prod doesn't use EEPROM today
  (Excel pushes Settings) so non-blocking, but anything assuming
  EEPROM would fail silently on Giga.

  *Defensive disciplines for v2 build:*
  1. Bounded network timeouts everywhere (≤ 2s, not 10).
  2. `delay(1)` minimum at the bottom of `loop()`.
  3. Fixed-buffer `snprintf` for any per-iteration response building.
  4. CAN RX stays in ring buffer, never calls network code.
  5. Document `F()` becomes a no-op on Giga; don't rely on PROGMEM
     for RAM savings.
  6. Multi-hour soak test before declaring Step 7 done.

- **NEW #62 Excel Camera.bas dead-code cleanup.** Audit performed
  Day 18 confirmed Camera.bas is largely vestigial — the cart-side
  exposure walk has been live since #36b (Day 12) and the Excel
  per-photo CCAPI path is no longer the production code path,
  even on Uno v1prod. Excel still compiles and runs the dead code
  if invoked, but `SequenceLoop` and `RunShot` are not the live
  per-photo loop in current operation.

  *What's dead (Excel side; cart now owns):*
  - `AdjustExposureByLuminance` (Camera.bas) — cart firmware
    has its own `adjustExposureByLuminance` (sketch line 3213,
    called inline from luminance fetch path line 3890).
  - `KickOffLuminanceCalc`, `KickOffLuminanceFromLastThumb`,
    `PollLuminanceCalc`, `GetLatestLuminance`, `CalcLuminance`,
    `FetchLastThumbnailToDisk`, `GetLastThumbnailLuminance`,
    `SyncWaitForLuminance` — entire Python-thumbnail luminance
    pipeline. Cart now reads the live histogram via CCAPI
    `/shooting/liveview/flipdetail?kind=info` and computes mean
    luminance from the Y histogram inline.
  - `SetShutterSpeed`, `SetISO`, `SetAperture` — cart issues
    these PUTs directly. Excel versions only used by the dead
    AdjustExposureByLuminance path.
  - `TakePhoto`, `ResetPhotoTimer` — cart fires pin-8
    autonomously on its own cadence, no Excel call needed.
  - `RunShot` (Sequence.bas) and most of `SequenceLoop`'s
    per-photo machinery — pre-#36b architecture.

  *What stays (still live runtime path):*
  - `InitShoot`, `SystemCheck`, `GetSunsetTime`,
    `CalculatePhaseTimes`, `CameraReachable`, `ArduinoReachable`
    — setup and pre-flight.
  - `GetCartLog`, `GetGimbalLogToSheet`, `ProcessCartLog`,
    `GenerateReplayPlan` — recon → plan pipeline.
  - `PushFormulaToCart`, `PushAstroToCart`,
    `PushTrackPathsToCart` — plan push, one-shot before shoot.
  - `StartCartReplay`, `RunCartReplayStep` — OnTime-driven
    Sequence-sheet walker, the live execution path. Issues
    `/btn{N}`, `/move`, `/home` per row.
  - `GimbalPosition`, `GimbalHome`, `GimbalHeartbeat`,
    `GimbalMoveAndWait`, `GetGimbalStatus` — gimbal control.
  - `CartButton`, `CartSetSpeed`, `CartSetSteering`,
    `CartStop`, `CartDecay` (Utils.bas) — wrappers used by
    `RunCartReplayStep`.
  - `LogEvent`, `ARDUINO_IP`, `CAMERA_IP`, `CCAPI_VER`,
    `JsonEscape`, `ParseJsonField` — shared utilities.
  - Astro / BicycleModel / CircleFit / Formula / AstroPush
    maths — plan authoring.

  *Scope of cleanup:*
  - Camera.bas: delete the luminance pipeline and the
    per-photo CCAPI walk. Trim to just `CAMERA_IP`, `CCAPI_VER`,
    `CameraGet/Put/Post` (useful for setup pre-flight),
    `InitCamera` (if actually called). Drop `SendHeartbeat`,
    `UpdateArduinoDisplay`.
  - Sequence.bas: drop `RunShot` and the per-photo loop
    structure. Phase machine for plan-baking stays; the runtime
    photo loop body is dead.
  - Utils.bas: `InitTvLookup`, `BuildTvLookupFallback`,
    `NextTv`, `TvToSeconds`, `SecondsToTv`, `CalcInterval` — were
    used by RunShot, dead if RunShot goes. But Plan authoring
    (manual Tv selection in Sequence sheet) may still use these
    — verify before deleting.

  *Risk assessment:* low. The dead code is not on any current
  production path; removing it changes no runtime behaviour. Main
  risk is accidentally deleting a helper the Plan-baking side
  still calls. Mitigation: grep for callers of each candidate
  before deleting; keep a `Camera_dead.bas` archive in the repo
  for one release cycle in case something resurfaces.

  *Not blocking.* Workfront exists as documentation of the
  current architecture vs the code shape. Do during the Giga
  Excel port (when every HTTP call is being repointed anyway)
  or any quiet session.

**Day 18 second half — Step 7 v2 sketch port (section-by-section).**
The migration plan's Step 7 was the verbatim port of v1prod into
DJI_Ronin_Giga_v2.ino, applying the lessons from Steps 1-5 and the
defensive disciplines from workfront #61. Sketch went from 0 → 5667
lines across 8 sections, all source-of-truth ported from
DJI_Ronin_UnoR4_v1prod.ino with explicit Giga deltas marked inline.

*Open design questions resolved at start of port (per GIGA_DESIGN.md):*

1. **IP addressing during parallel run.** Giga gets 192.168.1.95
   on Rosedale (DHCP-reserved via MAC). Uno stays on .97 until
   retirement. At cutover, Excel's `dataArduinoIP` flips from .97
   to .97 (Giga inherits the address); the .95 is for parallel
   bench testing without breaking production polling.

2. **Cart UI vs camera traffic split.** Operator UI (browser HTML
   + Excel /status polling + /btn /move /home plan push) all on
   WiFi STA port 80. Wired Ethernet via W5500 module (when it
   arrives) reserved exclusively for camera CCAPI traffic — Tv/ISO
   PUTs and the 4.5 KB liveview luminance fetch. Cart never serves
   browser UI over Ethernet.

3. **Shutter pin.** Pin-8 → D7 on Giga (D8 reserved for future
   Wire2 if ever needed; not a current need). 200ms HIGH pulse
   discipline carries over verbatim. Sacred pin — fires
   autonomously on shutter_mode==3 regardless of CCAPI state or
   Excel connectivity. Wired Ethernet is for CCAPI reliability,
   NOT for shutter (the pin is the shutter; Ethernet improves
   the metadata around it).

4. **Buffer sizes.** Operator's 20-50m recon path with handful
   of turns + ~20 waypoints gives ~50 events worst-case. Uno's
   CART_LOG_MAX=64 was tight. Giga bumps both CartLog and
   GimbalLog to 128 — comfortable headroom, trivial SRAM cost
   on 1 MB.

5. **String allocation policy.** Replace `String` concat with
   `snprintf` for paths hit more than once a minute (/status,
   /heartbeat, /cameramsg). Cold paths (/cartlog/clear,
   /gimballog/push, /settings/astropos) keep String — convenience
   matters more than per-call cost there.

*Port structure (8 sections):*

- **Section 1 (~370 lines)** — headers, includes, globals, early
  state. WiFi.h (mbed) not WiFiS3.h. STUB_CAN, STUB_BNO,
  STUB_WIRED_ETHERNET conditionals at top. LUM_HTTP_TIMEOUT_MS
  dropped from 10000 to 2000 per discipline #1. CCAPI response
  buffer raised 4096 → 8192 (validated in Step 5b).

- **Section 2 (~510 lines)** — exposure walk state, TABLE mode,
  comms-recovery NORMAL/PROBING, Appendix A formula storage +
  parsers + evaluators (formulaTv, formulaIso, formulaGetParam,
  parseExposurePayload). No Giga changes.

- **Section 3 (~460 lines)** — global gimbal pose, astro storage
  (7 yaw/pitch pairs + valid mask), TrackPath / TrackInterval
  storage, CAN reassembly buffers, CartLog and GimbalLog (both
  to 128 entries), cart motion helpers (cartUpdateOverdrive,
  cartApplyVelocity, cartSetSpeed, cartAdjustSpeed, cartStop,
  cartDeadStop, cartStartDecay, cartApplySteering,
  cartAdjustSteering, cartEnergise, cartDeenergise).

- **Section 4 (~500 lines)** — CAN frame infrastructure. drainCANRx
  + sendFrame wrapped in `#ifndef STUB_CAN`. buildFrame
  library-agnostic. Pano state machine + movewatch sampler.
  Commands (setPosControl/setSpeedControl/getPosData/enablePush/
  setFocControl/getFocPosData/cameraControl) — all callable with
  STUB_CAN; frames built and silently dropped at sendFrame.
  validateFrame, parsePositionResponse, parseFocusResponse,
  processCompleteFrame, handleRxMsg, runCRCSelfTest.

- **Section 5 (~655 lines)** — ccapiRequest with CRLF on outbound
  headers (Step 5b lesson, in-line in build lesson #1 above).
  PROBING entry on connect-fail preserved (still relevant for
  WiFi-parallel mode). ccapiStartLiveview / ccapiStopLiveview /
  tryStartLiveviewIfNeeded. ccapiFetchLuminance with binary-frame
  parse (FF 00 01 + size:4 BE + JSON + FF FF). nextTv/nextIso
  ladder walkers. tvStringToSeconds, intervalForTv,
  applyTvDrivenInterval. adjustExposureByLuminance walk function.
  parseCcapiMessage, isBusyRetryable, jsonEscapeTv,
  ccapiPutWithRetry, ccapiPutTv, ccapiPutIso.

- **Section 6 (~935 lines)** — plan executor (planTick #5a M/S/E/D
  dispatcher + #52 time-based completion + at-rest gate). Pano
  helpers (panoIssueSlew, panoTick, panoStart). Plan parser
  (planParseSegment, planLoadFromQuery, planStatusCSV).
  backupShutter (fires pin D7 with 200ms pulse and readback
  diagnostic). Exposure init helpers (parseCcapiValue,
  ccapiGetCurrentTv, ccapiGetCurrentIso, pollCameraEventOnce,
  initExposureFromCamera). cartLoop housekeeping pulse.

- **Section 7 (~200 lines)** — setup() and loop(). Wire.setClock
  REMOVED (Day 18 finding: blocks Giga). CAN.begin wrapped in
  `#ifndef STUB_CAN`. WiFi STA static IP + AP fallback. loop()
  with diag timing, cartLoop, drainCANRx+dispatch,
  REQUEST_INTERVAL_MS pose request, 30s keepalive setPosControl
  (skipped during pano), movewatch sampler, handleHttpRequest
  delegate, long-iteration detector, **delay(1) at bottom per
  discipline #2**. Forward declaration of handleHttpRequest.

- **Section 8 (~1860 lines)** — handleHttpRequest body, split
  into sub-sections 8a-8h:

  - **8a** — skeleton, request parse, favicon, /status (with
    buildStatusCSV helper), /heartbeat, /cameramsg, /interval.
  - **8b** — /move, /home, /gimbal/panostatus (before pano),
    /gimbal/pano, /shutter/start (with anchor diagnostic),
    /shutter/stop (minimal no-CCAPI per #48), /shutter/pause+
    /resume, /shutter/status, /shutter/pin8, /shutter, /btn{N}
    1-22 with cases 13/17 reserved.
  - **8c** — /exposure/init/load/target/state/walk, /luminance,
    /settings/astropos (5 yaw/pitch pairs + valid_mask),
    /settings/trackpath (cubic coefficients per object × seg),
    /settings/trackplan (intervals + anchor).
  - **8d** — /cartlog/clear, /gimballog/push, /gimballog,
    /cartlog (path-ordered for startsWith match).
  - **8e** — /plan/load/start/stop/status/nudge.
  - **8f** — /gimbal/showastrooffset, /gimbal/showastro,
    /gimbal/snapvar (path-ordered).
  - **8g** — 17 debug endpoints. 4 early-return (/debug/urlsize,
    formula, ping, trel) placed before /status. 13 response-pattern
    in the main chain (/debug/fetch* with nested branches,
    /debug/can, looplong, pathlog, decaytime, trackeval, liveview,
    reqlog, movewatchdump-before-movewatch, tic, overdrive,
    poll_camera).
  - **8h** — browser UI catch-all. Full 3-screen UI verbatim from
    v1prod (Cart Recon, Gimbal Recon, Execution placeholder),
    RS4+R3 SVG icons, day palette, all polling JS.

*Sketch state at end of Day 18:*

- 5667 lines (vs v1prod 6275). Slightly shorter — denser comments,
  same feature set.
- Compiles + runs with STUB_CAN defined. CAN commands build
  frames and silently drop. Pose globals stay at 0 unless
  Serial-poked.
- All 57 v1prod endpoints ported. Excel-facing surface complete.
- 3-screen browser UI complete.
- Path ordering verified for every startsWith chain.
- Two known limitations until hardware arrives:
  - Step 3 CAN: needs new SN65HVD230 transceiver
  - W5500 wired Ethernet: ordered, not yet received

*Pending next steps:*

1. Flash sketch to Giga and smoke test against Excel
   (status poll, btn1-22, /move, /home, /settings/astropos,
   /exposure/load round-trip).
2. Multi-hour soak test once smoke passes (discipline #6).
3. Step 3 CAN test when transceiver arrives (~5 days).
4. Step 7 full validation against real gimbal — confirms the
   STUB_CAN path swaps in cleanly when STUB_CAN is removed.
5. Workfront #62 Excel Camera.bas cleanup — deferred to Giga
   Excel port pass.

**Day 18 second half (continued) — Giga smoke test + moon astro
landed.** Sketch flashed to Giga; smoke test exposed an mbed
WiFi semantic issue; fixed; then full Excel ↔ Giga validation;
then workfront #55 (moon astro) closed end-to-end.

*Bug #65 — mbed accept() semantics.* First flash showed every
HTTP request returning the browser UI catch-all regardless of
URL — `/status`, `/debug/pathlog?on=0`, even single-purpose
debug endpoints all rendered the UI. Diagnostic logging added
to the parse showed `req_len=0` every time — `wifiServer.available()`
returned a client but `client.available()` returned 0, so the
read loop never executed and `path` stayed empty. Root cause
(via web search of ArduinoCore-mbed issues #76, #281, #766):
mbed's `wifiServer.available()` is semantically `accept()` —
returns the client as soon as the TCP three-way handshake
completes, BEFORE the HTTP request body arrives. v1prod's
single-shot `if (client.available())` was lucky on WiFiS3
(which buffered the request before returning the client) but
fails universally on mbed.

Fix: replaced the single-shot check in Section 8a `handleHttpRequest`
with the canonical mbed idiom — `while (client.connected())`
loop that polls `client.available()` with `delay(1)` between
checks, bounded at 2 seconds. If no request line arrives within
the window, `client.stop()` and return quietly. Confirmed working:
/status returned the 13-field CSV cleanly. Documented as Day-18
build lesson #5.

Side-effect (workfront #66): half-open sockets (browser speculative
pre-connect, port scan, stale Excel WinHttp socket) now cost
~3000ms wall-clock to detect and close (2s wait + 1s teardown).
Cosmetic — real Excel polling unaffected, pin-D7 sacred-pin
guarantee intact. Non-blocking accept + pending-client state
machine is the long-term cleaner pattern; deferred.

*Excel ↔ Giga smoke test (post-fix).* IP flipped from .95
(parallel-run) to .97 (Uno retired) per design Q1. Then:
- `?GetGimbalStatus` → True, 13-field CSV parsed cleanly
  (gimbal pose 0/0/0 from STUB_CAN, cart fields all defaults)
- `GimbalHeartbeat` → cart stored 18:19:44 in /status field 3
- `PushAstroToCart` → 132-char URL parsed, mask=0b1110011
  (sun rise/set + MW rise/mid/end; moon skipped pending #55)
- `PushFormulaToCart` → 1384-byte URL parsed cleanly, all
  126 data points captured (sstv=51, ssiso=12, srtv=49, sriso=14)

Tic + servo physically disconnected (will be reassembled when
W5500 Ethernet shield arrives in 2+ days); commands return OK
and log I²C errors but state machines progress.

*Workfront #55 Moon astro — closed end-to-end.* Three modules
modified to deliver full sun-equivalent treatment for moon:

- `Astro.bas` gained `GetMoonPosition` (Schlyter low-precision
  ephemeris, ~150 lines, periodic perturbations + parallax),
  public wrappers (`GetMoonAzimuth/Altitude/AzAltAtTime/GimbalAngles`),
  `FindSunCrossing` + `BisectSunAltitude` (generic sun-altitude
  root finder for all twilight phases — closes the internet
  dependency on api.sunrise-sunset.org), `FindMoonCrossing` +
  `BisectMoonAltitude` (same for moon).

- `Utils.bas` rewrote `GetSunsetTime` — sun events and all four
  twilight phases now computed LOCALLY via `FindSunCrossing`;
  moon rise/set times via `FindMoonCrossing`. Zero internet
  dependency for any astronomical computation.

- `AstroPush.bas` `PushAstroToCart` adds moon rise/set positions
  to query string (mnry/mnrp/mnsy/mnsp). Window selection
  handles all four cases: rise+set in envelope, rise-only,
  set-only (moon up at sunset), neither. `PushTrackPathsToCart`
  adds moon as third object; `FitAndPushTrackPath` dispatcher
  gained a `"moon"` branch using `GetMoonAzAltAtTime`.
  `N_SEGMENTS` bumped from 2 to 4 (Giga `TRACK_SEGS_MAX = 8`
  closed #58 SRAM workaround).

*Validation (Adelaide, 24-May-2026):*
- Local moonset 01:07 vs timeanddate.com 01:09 — **2 minutes**.
  Within ~0.5° at moon's apparent motion. Inside 14mm FOV
  tolerance.
- Initially planned api.sunrisesunset.io as the moon source —
  cross-check revealed it was **64 minutes off** for the same
  instant (returned 02:11). Rejected in favour of local maths.
- End-to-end: `PushAstroToCart` returned mask=11 (sun_rise +
  sun_set + moon_set; no moonrise since moon was up before
  sunset tonight). Moon set yaw 274.90° / pitch -0.50° — matches
  timeanddate's 275° azimuth within 0.1°.
- `PushTrackPathsToCart` pushed sun (4 segs) + MW (4 segs,
  with mw seg 2 FREEZE handling Adelaide's near-zenith MW pass)
  + moon (4 segs). All segments accepted by cart.

*MW push needed a manual `CalculatePhaseTimes` re-run.*
`dataPhase4aStart` was stale from a previous day's prep —
symptom of workfront #57 (no shoot-date anchor; everything
anchored to `Now()`). Worked around for tonight; #57 itself
remains open.

*Two follow-on workfronts created (Day 18):*
- **#64 Phase-time terminology cleanup** — `dataPhase2aStart`
  / `2bStart` / `3Start` / `4aStart` / `4bStart` / `5Start`
  are jargon from a prior session, not real astronomical
  terms. Replace with real-event names (golden hour, civil
  dusk, etc.) computable directly via FindSunCrossing. Defer
  to Giga Excel port pass alongside #62.
- **#65 mbed accept() semantics** — DONE this session. Logged
  for future cross-referencing.
- **#66 Empty-connection diagnostic cost** — 3-second cost per
  half-open socket. Cosmetic; revisit if rate becomes significant.

*Sketch state at end of Day 18 (final):*
- 5711 lines. Compiles + runs at .97. WiFi STA, Excel surface
  validated, browser UI loads.
- Bumped `TRACK_SEGS_MAX` from 2 to 8 (closes #58).
- Section 8a `handleHttpRequest` now uses mbed-correct
  wait-for-data parse (closes #65).
- IP flipped from .95 to .97 (Uno retired).

---

**Last updated (legacy entry):** 23 May 2026 (Session C day 17, **second half** —
workfront #52 (I²C cliff) properly diagnosed and resolved by removing
the cause, not coping with it. Earlier in the day the cliff was
"avoided" by throttling planTick's Tic position reads from per-loop
to 100ms. Extended-run testing later in the day showed the cliff still
fires at 100ms cadence (just slower to arrive — ~3 min instead of 7s)
and even at 1Hz polling. Throttling alone is not enough.

Pololu's own documentation (0J71/4.6) identifies the failure class:
weak pull-ups (Tic's internal ~40 kΩ) + long wires + standard I²C
clock = bus failures at sustained read load. Recommended fixes: add
external ~10 kΩ pull-ups, or slow the I²C clock. Hardware fix flagged
as a future workfront.

Architectural resolution: **time-based open-loop segment completion**.
Operator observation that re-framed the problem: "Tic is accurate for
ticks; if we tell Tic 'go velocity V', it does; if we tell Tic 'count
of ticks', it does. Why are we measuring?" The position-poll loop was
asking the Tic something it already knew and would do faithfully.

New MOVE-segment behaviour:
- Segment enter: commanded velocity sent (one write, no read)
- During segment: ZERO I²C reads. Completion estimated by
  `elapsed_ms >= dist_mm × 3600 / |speed_mhr|`.
- Segment complete: dispatcher transitions to next segment normally.

The cliff cause is gone for MOVE segments. STOP-segment at-rest gate
still polls Tic velocity at 250ms, but only during the bounded ~5s
decel window (~20 reads per STOP) — well below cliff threshold.

Measured open-loop tolerance:
- Standalone MOVE @ 30 m/hr × 250mm: ~-7 mm (3% short; accel ramp
  underrun dominates)
- tr=M merge @ 20 m/hr × 250mm: ~+14 mm (5% long; velocity calibration
  mismatch dominates — CART_SPEED_SCALE × 1.77 µm/step empirical
  consts are internally inconsistent by ~10%)
- Error does NOT scale with segment length; it's per-event, not
  per-mm
- Camera tolerance with 14mm lens at 5m subject ≈ 2 mm/px → ±15mm
  error is ~7 px shift, invisible in motion. Acceptable.

Defensive additions kept in production:
- `Wire.setClock(50000)` in setup — Pololu-recommended slower I²C
  clock; can't hurt and might help long-term stability
- (Hardware: external 10 kΩ pull-ups on SDA/SCL still TBD)

Test re-validation: A2 (STOP+duration), C1 (`/plan/stop` mid-MOVE),
D1 (`/plan/nudge`), E1 (multi-segment with steering), B-S (decel
stop with intermediate STOP+duration) — all re-tested with the new
architecture, all pass cleanly with no CLIFF events.

Diagnostic instrumentation removed at end of session (PTICK throttle
machinery, `/debug/plantickthrottle` endpoint, CLIFF? print, GATE
diagnostic, SEG_DONE measurement print, `plantick_*` globals).

Sketch 5553 → 5561 lines (+8 net; the cleanup roughly offset by
verbose comments documenting the architecture pivot).

**Earlier Day 17 (first half) below.** Five bugs found and fixed via
instrumentation-first diagnosis:

1. **Bogus rear-Tic delta negation** in `planTick`, `planStatusCSV`, and
   `/plan/nudge`. A `delta = -delta;` line, justified by a "rear Tic
   wired physically reversed" comment, made segment-complete check the
   wrong sign. Forward MOVE segments would never complete. Negations
   were not in the Day-15 v1prod branch point — added in uncommitted
   edits from a prior Claude session that crashed before testing.
   Verified empirically with `/debug/tic` after a manual forward drive:
   both Tics report positive position on cart-forward (~1% apart, the
   overdrive ratio). Removed; rear-Tic counts in the natural direction.

2. **I²C "cliff"** during plan execution. `planTick` was reading
   `ticRear.getCurrentPosition()` every main-loop iteration. After a
   variable run time (observed 7s, 17s, 128s across multiple tests),
   both Tics simultaneously NACK on the bus (Wire error code 2) and
   stop responding for the rest of the run. Cart kept moving on the
   last commanded velocity (Tic motors audibly unchanged). Throttled
   the read to 100ms cadence; cliff did not recur in any test
   thereafter. Mechanism not characterised — workfront #52, parked
   under avoidance.

3. **STOP-segment duration timer counted from segment entry, not
   from at-rest.** A 5-second STOP after a 30 m/hr cruise actually held
   only ~1.5 seconds at rest because the Tic STOP_DECEL ramp ate 3.5s
   of the window. Added an "at-rest gate" in `planTick` END_DURATION
   that polls both Tic velocities every 250ms; counts duration only
   from the moment both reach 0. Verified: 30 m/hr → SEG STOP(5s)
   takes 5.3s decel + 5s hold = 10.3s, cart genuinely still for the
   full 5s.

4. **Stop-style dispatcher (TR_S / TR_E / TR_D) pointless as written.**
   Each "stop" case did `cartStop()` THEN immediately
   `cartSetSpeed(speed_mhr)` — Tic got two velocity targets in
   microseconds and ignored the first. No actual stop happened.
   Rewrote dispatcher with revised semantics:
   - **M** (merge) — MOVE-only. Slam target speed; Tic accel/decel
     handles ramp. Default for MOVE.
   - **S** (decel) — STOP-only. `cartSetSpeed(0)`, Tic STOP_DECEL ramp
     to rest. Then hold via at-rest gate. Default for STOP.
   - **E** (emergency) — STOP-only. `cartDeadStop()` (Tic haltAndHold)
     for instant halt. Then hold.
   - **D** (decay) — STOP-only. `cartStartDecay()` arms linear ramp
     from current speed to 0 over `cart_decay_ms` (6 min production).
     Distance is derived, not specified. Then hold.

5. **Decay-loop wrap-around bug** that hid bug #4's true fix. When
   `cartStartDecay()` is called from inside `planTick` (which runs at
   the top of `cartLoop`), `cart_decay_start = millis()` is set AFTER
   `now = millis()` was captured at the top of cartLoop. The next
   line, `elapsed = now - cart_decay_start`, then underflows
   unsigned: tiny-negative becomes ~4 billion. `elapsed >=
   cart_decay_ms` becomes true on the same loop pass, triggering
   `cartStop()` — instant termination of the decay we just armed.
   Fixed with `if ((long)(now - cart_decay_start) < 0) elapsed = 0;`
   to handle the same-iteration decay-arm case. Verified: 60s decay
   ran linearly to zero, factor untouched until ramp complete.

Test-bank validation (all green):
- Bank A2 — STOP segment with END_DURATION (5s hold, true rest)
- Bank B-S — decelerated stop (~5.3s decel from 30 m/hr)
- Bank B-E — emergency stop (~30ms halt via haltAndHold)
- Bank B-D — decay stop (60s linear ramp from 30 m/hr to 0)
- Bank C1 — `/plan/stop` mid-MOVE (aborts plan, ramps cart down)
- Bank C2 — `/btn11` mid-MOVE (stops cart, plan stays RUNNING)
- Bank C3 — `/btn12` mid-MOVE (instant halt, plan stays RUNNING)
- Bank D1 — `/plan/nudge?d=100` extends current segment by 100mm
- Bank D2 — `/plan/nudge?d=-100` with plenty left, target shrinks
- Bank D3 — `/plan/nudge?d=-100` past zero, segment immediate complete
- Bank D4 — nudge on STOP segment rejected
- Bank E1 — multi-segment plan with steering (+5°, -5°, S-curve)

New sketch infrastructure (kept in production):
- `cart_decay_ms` (global, default 360000 / 6 min) replaces the prior
  `const CART_DECAY_MS`. Adjustable via `/debug/decaytime?ms=N`.
- `plantick_dist_last_ms` (100ms throttle for planTick END_DIST read).
- At-rest gate state in planTick END_DURATION (per-segment statics).
- `getLastError()` check after each Tic read in END_DIST — logs
  only on non-zero so a Tic comms collapse surfaces immediately
  without per-tick noise.

Diagnostic instrumentation removed from sketch at end of session:
- PTICK every-500ms probe block
- Post-stop PROBE every-100ms sampler
- DUR elapsed-since-rest 500ms probe
- TR_DECAY pre/post-startDecay diagnostic prints
- `stop_probe_until_ms`, `stop_probe_last_sample_ms`,
  `plantick_probe_last_ms` globals

Sketch 5140 → 5553 lines (+413 net, all production code, no diagnostics).

**Earlier Day 16 below.** Three-screen UI v2 foundation delivered.
Server-side routing on `?screen=cart|gimbal|exec`, shared header with
logo row + 4-tab bar, day palette baked in. **Cart Recon: full build**
— status line (voltage · motor state),
Last/Now waypoint rows, steering/speed/motor/action button rows,
turning-circle notes panel. New `'W'` CartLog event carries the
recon-session waypoint number; new `cart_motor_state` software flag
(DE-E/STOP/ENRG) wired through cartStop/cartDeadStop/cartSetSpeed/
cartEnergise/cartDeenergise; `/status` extended with v[10] motor
state, v[11] waypoint count, v[12] mm-since-last-waypoint; new btn22
Mark wpt handler with confirm. Operator verified end-to-end
(+5/+5/+5 cumulative steering, Last/Now roll-over, d-distance ticks,
Clear logs zeroes back to "—"). **Gimbal Recon: full build,
client-side state** — live readout `Ry · Cy · p` (Ry=Cy until BNO
integration); 4 prior slots + Current row block; type rows
PF/Lock/Move/Track sun + Sunrise/Sunset/MW; conditional sub-controls
(keyframe for astro, R/C frame for PF+Move, yaw Δ / pitch Δ for
astro, measured-variance line); label field; Show astro / Snap var
(TODO stubs pending Excel astro push) / Next action row. Per-type
pose handling: PF/Lock/Move capture pose AND write to cart gimbalLog
via /btn20; astro and Track sun are intent-only with no pose, no
gimbalLog write. Newest at slot c3 (just above Current), older
pushed up and off the top; Clear button on Current for mini-edit
without baking. iOS auto-zoom fixed (inputs at font-size:16px).
**JS escape-quote bug caught and fixed mid-build** — broken `\\'s`
inside an alert() string threw a syntax error and killed the entire
script (live readout stuck on dashes). New build lesson recorded
in PREFERENCES. **Execution screen: placeholder only** — header +
tabs work, body says "Coming next". Deferred until #5a segment
dispatcher + speed transition types + ±100mm nudge endpoint +
PAUSE/RESUME backend are built. Sketch 4843 → 5140 lines (+297 net);
SRAM globals +9 bytes. **Day 16 hygiene:** UI_DESIGN_SUMMARY.md
moved to ARCHIVE/ (superseded by UI_DESIGN_v2.md + Day 16 build);
GIMBAL_VIZ.md §3 / §9 / §10 annotated with superseded-by pointers.
**Earlier Day 15 below.** Day-15 part 7: #48 bus fault localised
via addr2line. Crash is in `WiFiClient::read` /
`Stream::readStringUntil` inside `ccapiStopLiveview()`'s
HTTP DELETE. Sometimes preempted by CAN RX ISR (3 of 4 dumps),
sometimes not (1 of 4). Stack measurement showed 1024/1024 used
in normal idle operation (stack is only 1 KB). Fix attempt 1
(char-buffer reads in ccapiRequest) ruled out — WiFi library
allocates Strings internally. Fix attempt 2 (`enablePush(false)`
+ delay before DELETE) removed CAN ISR from the crash stack but
crash persisted from a second mechanism. **Resolution: minimal
/stop handler.** The `ccapiStopLiveview()` call was housekeeping
(politely close camera liveview session); not required for
correctness because `ccapiStartLiveview()` already handles
"Already started" 503 from stale sessions. Removed from /stop
handler. /stop now does only local flag writes + serial log.
Verified across two full /start → photos → /stop cycles, both
clean, both started fresh liveview on next /start. #48 closed
for v1. v1 sketch current at /mnt/user-data/outputs/.)

This file is the handoff document between sessions. Upload it with the
latest `.bas` files and Arduino sketches at the start of the next session.

Also upload `PREFERENCES.md`, `GIMBAL_VIZ.md`, `WORKFRONTS.md`,
`EXPOSURE_FALLBACK.md`, and `UI_DESIGN_v2.md` — working agreement,
gimbal visualisation design (with Day-16 superseded-by annotations),
open task list, exposure fallback design (with reference table as
Appendix A), and the current authoritative UI spec. The Day-10
`UI_DESIGN_SUMMARY.md` is in ARCHIVE/ as of Day 16 — superseded by
UI_DESIGN_v2 + the Day-16 build.

Older session detail (days 5–11) lives in `PROJECT_STATE_old_ver1.md`.
This file keeps only what the next session needs to read to start work.

---

## Day-17 session — first successful plan execution (two bugs fixed)

Build + diagnostic session. The first attempt to run a multi-segment
plan end-to-end surfaced two faults. Both diagnosed via instrumentation
(oscilloscope approach — see PREFERENCES), then fixed. End-to-end
verification on the third clean test of the day.

### Bug 1 — bogus rear-Tic position negation

**Symptom.** Plan starts cleanly, SEG 1 dispatched, cart drives at
30 m/hr, but segment never completes. Cart drives past the planned
distance and continues until forcibly stopped.

**Diagnosis path.** Added PTICK probe to `planTick` printing `rear.pos`,
computed `delta`, and `target` every 500ms. Trace showed `rear.pos`
climbing positive (3 → 196 → 638 → ... → 628274) on cart-forward, but
the computed `delta` was negative the same magnitude (−628274), never
reaching the positive `target` (565000 steps = 1000mm). Cause: a
`delta = -delta;` line in `planTick`, mirrored in `planStatusCSV` and
`/plan/nudge`, with a comment claiming the rear Tic was "wired physically
reversed." Git blame against the Day-15 v1prod branch point showed
those negations were not in the original code; they had been added in
**uncommitted** edits before this session — from a prior Claude session
that crashed before testing the change.

**Verification before fix.** Ran a manual forward drive in Cart Recon
(no plan), then `/debug/tic`. Both Tics reported positive position
(rear=877,431; front=886,988; ~1% apart, the overdrive ratio). Confirmed
both motors count positive on cart-forward — no opposite-direction
quirk at the position-readback level. Whatever Tic-config inversion
gives the two motors their opposite physical rotation (to drive the
cart forward) is invisible at the library level; `getCurrentPosition`
returns positive numbers from both.

**Fix.** Removed the three `delta = -delta;` lines (planTick:2084,
planStatusCSV:2458, /plan/nudge:5049). Kept the legitimate
`if (speed_mhr < 0) delta = -delta;` lines below them — those handle
plan-authored reverse-direction MOVE segments and remain correct.
Updated comments to record the correct direction observation.

### Bug 2 — I²C "cliff" (Tic comms collapse) during plan execution

**Symptom.** During plan execution, after a variable run time, both
Tic controllers simultaneously stop ACKing on the I²C bus. From that
moment on every `getCurrentPosition()` / `getCurrentVelocity()` returns
0, every `getLastError()` returns 2 (Wire library: address-NACK), and
all subsequent stop commands (`/plan/stop`, `/btn11`, `/btn12`, etc.)
cannot reach the Tics. The Tics themselves continue executing the last
velocity command they received, so the cart runs at full commanded
speed until power-killed manually. Tic motors keep singing at the same
pitch through the cliff — confirms motor command unchanged, only Uno→Tic
comms dead.

**Diagnosis path.** PTICK probe extended with `getLastError()` after
each Tic read. Trace showed clean `(e0)` reads while cart accelerated
to commanded speed; reads then continued cleanly during cruise with
`rear.vel` and `front.vel` locked at the bit-exact commanded values
(`49913765` / `51724110`); at the cliff instant **all three reads
(rear.pos, rear.vel, front.vel) flipped from e0 to e2 simultaneously**.
Cliff timing across three runs: t+128s, t+7s, t+17s — highly
intermittent, not load-bound, not time-bound.

Read-rate inspection of the sketch showed `planTick()` calls
`ticRear.getCurrentPosition()` every main-loop iteration. With no
blocking work in the loop that's hundreds of I²C transactions per
second, all addressed at the rear Tic. Cart Recon (which works fine
indefinitely) only reads via `/status` every 3 seconds — orders of
magnitude lower.

**Hypothesis (not proven, but consistent).** Sustained high-rate I²C
polling against the Tic at the rates `planTick` was running it
eventually corrupts the bus or wedges the slave-side state machine,
producing the sudden simultaneous NACK on both addresses. No deeper
mechanism investigation done; the avoidance fix below proved sufficient.

**Fix.** Throttled `planTick`'s END_DIST read to 100ms cadence. At
30 m/hr the cart covers 8.3mm in 100ms; at 50 m/hr 13.9mm. Worst-case
segment-complete overshoot is ~14mm against multi-hundred-mm segments
— well within shoot tolerance and below the documented turning-circle
measurement noise. Other Tic reads (Cart Recon `/status`, cart log
captures, voltage poll every 2s, debug endpoints) were already
appropriately throttled.

### Validation run

Third end-to-end test of the day after both fixes applied:

```
/plan/load?n=3&s1=m,1000,0,30,d&s2=m,500,0,50,d&s3=s,0,0,0,o
/plan/start
```

Observed:
- SEG 1 (MOVE 1000mm @ 30 m/hr) dispatched, cart accelerated to commanded
  speed via Tic ramp, delta climbed cleanly toward 565000 steps target
- SEG 1 complete at t+115.3s (theory: 120s, actual is slightly under
  due to the initial accel ramp covering part of the distance)
- SEG 2 (MOVE 500mm @ 50 m/hr) entered, `plan_seg_start_rear=565349`
  (captured correctly from SEG 1 end). Velocity ramped 30 → 50 m/hr
  smoothly via `tr=M`. Delta climbed to target 282500
- SEG 2 complete at t+34.2s after SEG 2 entry (theory 36s)
- SEG 3 (STOP, end=operator) entered. Cart halted as part of plan
  execution

No cliff (e2) anywhere in the run. Plan ran to STOP as authored.

### Files modified this session

- `DJI_Ronin_UnoR4_v1prod.ino`:
  - Removed three `delta = -delta;` lines (Bug 1)
  - Added 100ms throttle to `planTick` END_DIST (Bug 2 avoidance)
  - Replaced `CART_DECAY_MS` constant with mutable `cart_decay_ms`
    (default 360000 / 6 min for production); added
    `/debug/decaytime?ms=N` for testing
  - Rewrote `planSegmentEnter` dispatcher with corrected M/S/E/D
    semantics (Bug 4)
  - Added at-rest gate in `planTick` END_DURATION (Bug 3)
  - Fixed decay-loop unsigned-subtraction underflow (Bug 5)
  - Added `getLastError()` check after rear-pos read in END_DIST —
    logs only on non-zero error code
  - Added probe instrumentation for diagnosis, then removed all of
    it at end of session (PTICK probe, PROBE in cartLoop, DUR probe,
    TR_DECAY probe)

### Test-bank validation results

| Bank | Test | Result |
|---|---|---|
| A2 | STOP segment with END_DURATION (5s) | ✓ at-rest gate working |
| B-S | Decelerated stop (Tic STOP_DECEL ramp) | ✓ ~5.3s decel + hold |
| B-E | Emergency stop (cartDeadStop) | ✓ ~30ms halt + hold |
| B-D | Decay stop (linear ramp over cart_decay_ms) | ✓ 60s linear ramp |
| C1 | `/plan/stop` mid-MOVE | ✓ abort + ramp |
| C2 | `/btn11` mid-MOVE | ✓ stop, plan stays RUNNING |
| C3 | `/btn12` mid-MOVE | ✓ instant halt, plan stays RUNNING |
| D1 | `/plan/nudge?d=100` | ✓ target extends |
| D2 | `/plan/nudge?d=-100` (left in seg) | ✓ target shrinks |
| D3 | `/plan/nudge?d=-100` past zero | ✓ immediate segment complete |
| D4 | nudge on STOP segment | ✓ rejected cleanly |
| E1 | Multi-segment with steering | ✓ steering per-segment works |

### Mental model corrections recorded

- **A prior crashed Claude session can leave uncommitted edits in the
  working tree.** Today's Bug 1 came in via the prior-Claude
  edits. The protective practice is to verify a planTick-style change
  by checking against the latest committed version with `git diff` (or
  recent-commit `git show`) before treating the local file as
  authoritative.
- **A "comment that explains a counterintuitive thing" is high-risk
  signal, not high-trust signal.** The "rear Tic wired physically
  reversed" comment was the rationalisation, not the truth. Verifying
  comment claims empirically (manual drive + `/debug/tic`) was a
  one-minute test that should have happened earlier.
- **I²C cliffs are quiet.** No exception, no Serial diagnostic, no
  watchdog reset — just a flip from e0 to e2 and 28+ seconds of
  successful zero-returns from the library that look like "Tic is
  fine, at rest." Without `getLastError()` instrumentation the
  failure mode is invisible. The new on-error-only print in
  `planTick` END_DIST is the standardised check going forward.
- **`millis()` captured at the top of a loop iteration is stale by
  the time inner code completes.** Bug 5 (decay underflow) is the
  worked example. When passing `now` down to sub-blocks that may
  themselves call `millis()`, guard against the timestamp ordering
  not matching code-execution order.
- **A "stop" command followed by an immediate "set speed" is
  identical to "set speed" alone** — the Tic accepts the latest
  target and discards the earlier one. Apparently "stop then go"
  needs an in-between gate (the at-rest check) for any actual stop
  to happen. Bug 4 is the worked example.

### Path back into this work

Plan execution is now production-quality. Outstanding work in this area:

- **Workfront #52 — I²C cliff root cause.** Avoidance fix (100ms
  throttle) is sufficient for now. If the cliff recurs at lower read
  rates, scope the SDA/SCL lines and check pull-up strength.
- **Workfront #51 — was "remove Day-17 diagnostics."** Done this
  session at end. Close.
- Execution screen UI (the placeholder from Day 16) now has a working
  backend; can be wired up when ready. Subscreen design needs the
  Plan state, segment-progress readout, ±100mm buttons, and PAUSE
  semantics decisions captured in WORKFRONTS Day-15 Part 8.

---





Build session. Server-side three-screen UI delivered, two screens
real (Cart Recon, Gimbal Recon), one placeholder (Execution). The
authoritative spec is `UI_DESIGN_v2.md` (Day 15 part 10).

### What was built

**Routing.** Single `else` block in path dispatcher parses
`?screen=cart|gimbal|exec` (default `cart`). Three HTML bodies
between a shared head + header + tab bar.

**Shared header.** Logo row (RS4 + R3 SVG icons reused from old UI)
+ 4-tab grid (Cart / Gimbal / Exec / Day). Active tab marked with
2px maroon bottom border. Day palette baked in CSS — warm grey on
warm grey, muted slate-blue buttons, maroon action, warm tan warn.
Night palette deferred to Execution screen build.

**Cart Recon screen.**

- Status line (monospace, centred): voltage · motor state
- Last row: most-recent waypoint display, empty "—" until first bake
- Now row: live preview, ticks distance from cart-log-start or last
  waypoint
- Steering row: L5 / L1 / CTR / R1 / R5 (existing btn1–5)
- Speed row: −10 / −1 / DEC / +1 / +10 (existing btn6–10)
- Motor row: STOP / DE-E (confirm) / ENRG. DEAD removed from this
  screen per v2 spec (no longer needed when only Cart-Recon work is
  happening; the Execution screen will get its own quick-stop).
- Action row: ● Cart log / Mark wpt (new, with confirm) / Clear logs
- Notes panel: turning-circle table (#10b) preserved

**Sketch additions for Cart Recon:**

- `cart_motor_state` (1 byte): software flag with values
  MOTOR_DEENERGISED / MOTOR_STOPPED / MOTOR_RUNNING. Hooks into
  cartStop, cartDeadStop, cartSetSpeed, cartEnergise, cartDeenergise.
  Decay completion already calls cartStop() so it's covered.
- `cart_waypoint_count` (4 bytes): increments per Mark wpt bake;
  reset by btn19 log-start / btn21 Clear logs / /cartlog/clear.
- `cart_last_waypoint_steps` (4 bytes): `ticRear.getCurrentPosition()`
  at last bake; reset paths same as above. The Now-row distance
  reads `(cur_steps − cart_last_waypoint_steps) / 565` mm
  (565 steps/mm from planMmToSteps calibration).
- New `'W'` event in CartLog, value = `cart_waypoint_count`. Other
  event types unchanged.
- New btn22 (Mark wpt) handler with confirm dialog in the UI.
- `/status` payload extended:
  - v[10] = motor state (0=DE-E, 1=STOP, 2=ENRG)
  - v[11] = waypoint count (recon-session local)
  - v[12] = mm since last waypoint (or cart-log-start if no W yet)

**Operator verification end-to-end.**

- ENRG → −10 m/hr → drive → STOP → status row showed "21.8v · STOP"
- L5 / L5 / L5 → Now row showed cumulative +15° steering correctly
- Mark wpt → confirm → Last rolled to #1, Now reset
- Three more bakes → Last showed #3 with d 8 (real mm covered
  between bake and stop, not noise)
- Clear logs → Last back to "—"

**Gimbal Recon screen.**

- Live readout line: `live · Ry · Cy · p` (monospace, centred).
  Ry = Cy until BNO085 integration lands (architecture: when BNO
  arrives, Ry will add cart_heading to gimbal yaw).
- Four prior slots (c0…c3) showing the four most recent baked rows.
  Newest sits in slot c3 (just above Current row), older pushed up
  toward c0 and off the top. Empty rows show grey.
- Current row block (highlighted maroon border, 5th row visually)
  with Clear button for mini-edit without baking.
- Type rows:
  - Operator-authored: PF / Lock / Move / Track sun
  - Astro: Sunrise / Sunset / MW
- Conditional sub-controls per type:
  - Keyframe (rise/mid/end): astro types only
  - R/C frame toggle (Ry/Cy): PF + Move only
  - Yaw Δ / pitch Δ offset inputs (numeric): astro types only
  - Measured-variance display line: astro types only
- Label field: free-text single-line input, 24-char limit.
- Action row: Show astro (TODO stub) / Snap var (TODO stub) /
  Next (with confirm).

**Per-type pose handling:**

| Type | Captures pose? | Writes to cart gimbalLog? |
|---|---|---|
| PF | yes | yes (via existing /btn20 path) |
| Lock | yes | yes |
| Move | yes | yes |
| Track sun | no | no (intent-only) |
| Sunrise | no | no |
| Sunset | no | no |
| MW | no | no |

Astro and Track sun rows carry intent (type + keyframe + offsets +
label) but no pose — actual pointing is computed at execution time
from astro maths.

**Client-side state.** Captured row list lives in browser memory only.
Reload kills type/label/keyframe/offset data. The cart gimbalLog
buffer still records yaw+pitch for pose-types via /btn20 so Excel
still receives those raw entries via /gimballog. Logged as #49
follow-up: persist the rich list to cart RAM before relying on this
in production.

**Show astro / Snap var.** Both pop a "not yet implemented" alert.
Mechanism is Path A from Day-16 design discussion: Excel pushes
today's astro yaw/pitch positions (sunrise/sunset/MW × rise/mid/end =
9 yaw/pitch pairs, ~50 bytes) to cart in a new settings field.
Cart commands gimbal to stored position when Show astro tapped.
Logged as #50.

**JS escape-quote bug caught and fixed mid-build.** First Gimbal
Recon flash showed dashes in the live readout and never updated.
Operator pulled the served HTML; inspection found
`'... today\\'s ...'` in an alert() string — the `\\'` produced a
literal backslash followed by a string-closing apostrophe, which
threw a syntax error and killed the entire script (live polling
included). Fix: rewrote without the apostrophe. **Build lesson
recorded in PREFERENCES** about C++ string literals containing JS
strings: each level of escaping multiplies, easy to over-escape into
broken JS. The fact that the bug surfaced in a stub-alert function
(showAstro), not in any real logic, made the symptom (no live
readout) look completely unrelated to the bug location.

**Execution screen.** Header + tabs work, body is "Coming next"
placeholder. Deferred because its prerequisites aren't built:

- Gimbal plan plumbing (segments aren't pushed yet)
- Segment dispatcher + speed transition types (Day-15 Part 9 — design
  only)
- ±100mm nudge endpoint (Day-15 Part 9 — design only)
- PAUSE/RESUME endpoint (Day-15 Part 8 — design only)
- BNO085 (#40 build phase) for anchor cluster
- Excel astro push (#50) for full chart

Building Execution tonight would have been ~70% stubs. Better to
build the firmware backend first, then the screen has real things
to show.

### Day-16 hygiene actions

- `UI_DESIGN_SUMMARY.md` (Day 10) moved to `ARCHIVE/`. It's
  superseded by `UI_DESIGN_v2.md` plus the Day-16 build, and already
  self-flagged its heading-architecture section as superseded by
  Day-13 #40.
- `GIMBAL_VIZ.md` §3 (Gimbal UI on cart), §9 (Cart/Gimbal Plan
  coupling), §10 (Open design questions) annotated with
  superseded-by callouts. §3 → UI_DESIGN_v2 Gimbal Recon. §9 →
  WORKFRONTS Day-15 Part 8 + Part 9. §10 → per-question status
  notes inline (most resolved by Day-13 #40 and Day-15 Part 8/9).
- Sections 1, 2, 4, 5, 6, 7, 8 of GIMBAL_VIZ.md remain authoritative
  reference (workflow, Plan/Execution split, segment types, SDK
  constraints, astro maths, velocity bands, Catmull-Rom).

### Memory snapshot (post-build, awaiting Verify confirmation)

- SRAM globals: +9 bytes from new state vars (1 + 4 + 4)
- Flash: +~3 KB estimated from new HTML strings (verify post-flash)
- Sketch 4843 → 5140 lines (+297 net)

### Files modified this session

- `DJI_Ronin_UnoR4_v1prod.ino` — three-screen UI replacement of
  the `else` block, new state vars, new btn22 handler, /status
  payload extension
- `GIMBAL_VIZ.md` — superseded-by annotations on §3 / §9 / §10
- `UI_DESIGN_SUMMARY.md` — moved to ARCHIVE/ (no content change)

### Mental model corrections recorded

- **Cart-side state is the source of truth for production data.**
  Cart Recon waypoint tracking (counter + steps anchor + W events)
  is cart-side and survives page reloads / tab switches via /status.
  Gimbal Recon rich-row state is client-side only and does NOT
  survive reload. Acceptable for this build (recon is a continuous
  session, operator doesn't reload mid-recon), but a real gap for
  production — #49 closes it.
- **Per-type behaviour matters in UI design.** The first Gimbal
  Recon build wrote /btn20 (gimbalLogCapture) on every Next-bake
  including astro types. Realised mid-session that astro rows have
  no meaningful pose to capture; gated /btn20 on `poseT[cur.type]`.
  Same pattern likely repeats in #50 Excel-side: astro rows
  shouldn't carry pose, just type + keyframe + offset + label.
- **Tab switching = full page reload, by design.** Server-side
  routing means each tab tap is a fresh HTTP fetch. Cart state
  reconstructs from /status; client state does not. This is
  acceptable because nothing important on Cart or Gimbal Recon
  lives only in client state — Cart Recon all server-side, Gimbal
  Recon known-ephemeral with the #49 follow-up.

### Path back into this work

A future session can re-enter the UI build by:
1. Reading UI_DESIGN_v2.md + this Day-16 entry alongside the sketch
2. Picking up at #49 (Gimbal rich-row persistence) — smallest path
   to make Gimbal Recon production-usable
3. OR picking up at #5a (segment dispatcher + transition types) —
   unlocks the Execution screen build

---



### Day-15 part 7: #48 bus fault localised via addr2line

Measured the actual crash, drilled to the cause. Did NOT speculate.

**Method:** captured fresh crash dump from current build, ran
`arm-none-eabi-addr2line` on the PC + LR + stack values against the
sketch's `.elf` file.

Build paths used:
- elf: `C:\Users\mauri\AppData\Local\arduino\sketches\
  F4FFB483BA32955ACC96AEEBF10EBF23\DJI_Ronin_UnoR4_v1prod.ino.elf`
- addr2line: `C:\Users\mauri\AppData\Local\Arduino15\packages\
  arduino\tools\arm-none-eabi-gcc\7-2017q4\bin\
  arm-none-eabi-addr2line.exe`

**Resolved call stack at crash (top-down, partial):**

```
PC = 0x0000f21a → WiFiClient::read(uint8_t*, uint32_t)
                  FifoBuffer.h:82
LR = 0x0000ed7a → FifoBuffer::available()
       0x0000ec7e → WiFiClient::read()
       0x00016742 → Stream::timedRead()
       0x00016770 → Stream::readStringUntil('\n')
       0x00005c10 → ccapiRequest    line 2341 (status-line read)
       0x0001684e → arduino::String constructor
       0x0000623a → ccapiStopLiveview  line 2489
       0x00008abe → loop, /shutter/stop handler  line 4003
       ...
       0x000131c8 → can_rx_isr                  ← CAN interrupt!
       0x00012c14 → r_can_call_callback
       0x0000c88a → R7FA4M1_CAN::onCanCallback
       0x00015efe → CanMsgRingbuffer::enqueue    line 54
```

**Concrete mechanism (measured, not guessed):**

A CAN RX interrupt fires while the WiFi blocking-read path is
constructing a `String` object on the heap (allocating memory for
the status-line buffer). The ISR calls into `CanMsgRingbuffer::enqueue`,
which executes `_buf[_head] = msg;` — a struct copy into an array
slot indexed by `_head`.

**The bus fault address `0x200259d2` is OUTSIDE Uno R4 SRAM.**
Uno R4 SRAM range is `0x20000000` to `0x20007FFF` (32 KB).
`0x200259d2` is ~150 KB above the start of SRAM, in unmapped memory.
The previous crash address `0x20025961` is in the same out-of-range
region.

**SRAM layout from `.map` file (measured, not estimated):**

```
0x20000000  __data_start__       (start of SRAM, initialised globals)
0x200002c8  __bss_start__        (uninitialised globals)
0x20005854  __bss_end__          (end of globals; 0x5854 = 22,612 bytes)
0x20005858  __HeapBase           (heap start, 4-byte aligned)
0x20007b00  __HeapLimit          (heap top / stack low limit)
0x20007b00  __StackLimit         (stack grows down from above)
0x20007f00  __StackTop           (top of usable SRAM)
                                 (vector table above)
```

- Globals: 22.5 KB (matches 68.9% of 32 KB from Verify output)
- Heap region: 0x20005858–0x20007b00 = **8,872 bytes**
- Stack region: 0x20007b00–0x20007f00 = **1,024 bytes** (only 1 KB!)
- Total usable: 31.75 KB

**Bit-flip observation (specific finding):**

Compare the fault addresses to nearby valid heap addresses:
- Fault 1: `0x20025961` vs valid heap `0x20005961` → **differ only in bit 17**
- Fault 2: `0x200259d2` vs valid heap `0x200059d2` → **differ only in bit 17**

Both faults land at structured offsets — a valid heap pointer with one
specific bit flipped (bit 17 = +0x20000). This is NOT random garbage;
it's a specific corruption pattern. The valid-region addresses
(`0x20005961`, `0x200059d2`) sit just inside the **heap region**
(0x20005858+).

So either:
- A heap pointer is having bit 17 corrupted somewhere (cosmic ray
  unlikely; more probably a structured bug — a memcpy with wrong
  offset, an array index overflow, a register clobber in an ISR
  prologue/epilogue, or a hardware bus glitch)
- Two heap accesses are racing and OR-ing together (CAN ISR + main
  thread both touching the same memory)
- Some address-arithmetic path adds 0x20000 spuriously

So either:
- `_buf` (the ringbuffer's internal array pointer) is corrupted
- `_head` (the ringbuffer's index) is corrupted to a huge value
- The ringbuffer instance itself is in a memory region the linker
  didn't allocate

Either way, **the CAN ringbuffer's instance variables have been
overwritten** by the time the ISR fires. The fault is a heap/state
corruption symptom, not a bug in the `/stop` handler itself.

**Plausible mechanism (NOT yet proven, requires further drilling):**
- SRAM globals at 68.9% leaves only ~10 KB for heap + stack
- Only **1 KB of stack** — deep call chains (WiFi → Stream → String
  ctor + ISR preempt onto same stack) are tight
- WiFi `readStringUntil` allocates dynamic Strings continuously
  during reads; heap growth + fragmentation over a long shoot
- Heap grows toward stack; if either overruns the other, or grows
  into the CAN ringbuffer's static allocation region, the
  ringbuffer's `_head` or `_buf` gets trampled
- Day-7's failed `CART_LOG_MAX = 128` bump (.stack_dummy overlapped
  .heap) is documented evidence that the SRAM ceiling is already
  uncomfortably close

**What we KNOW (evidence):**
- Crash is in CAN ISR enqueue, reading via WiFi when it fires
- Crash address is outside valid SRAM
- Two separate crashes hit nearly identical out-of-range addresses
- The /stop handler path is identical to fetch path; difference
  must be cumulative state, not handler logic
- 62-photo run vs 87-photo run vs 104-photo run (which DIDN'T crash)
  suggests probabilistic exposure to the corruption window — but
  this is observation, not proof of a memory-pressure mechanism

**What we DON'T know (requires further work):**
- Whether the heap is actually growing without bound
- Where the CAN ringbuffer lives in SRAM (map file would tell us)
- Whether disabling CAN push-subscribe before /stop would mask
  the bug (it would, but doesn't fix the underlying corruption)

**Fix candidates (none chosen yet):**
1. Stop CAN push-subscribe before /stop; gimbal stops sending; ISR
   stops firing during teardown. Doesn't fix the corruption, just
   avoids the trigger.
2. Disable CAN RX interrupts around blocking WiFi reads. Same.
3. Drive `client.readStringUntil` and friends with explicit char-at-
   a-time reads to avoid heap allocations. Investigate.
4. Migrate to Giga R1 (v2 / #47). 1 MB SRAM removes the memory
   pressure entirely.

Updated #48 in WORKFRONTS with this evidence.

**Update — fix attempt 1 (char-buffer reads) failed.** Replaced
`String statusLine = client.readStringUntil('\n')` and the header
read loop in `ccapiRequest()` with a 48-byte stack-local buffer + char-
at-a-time reads. Goal: remove our code's contribution to heap
allocation in the WiFi read path. **Crashed again. Same crash
signature.** addr2line on the new dump showed the String
constructor is STILL in the stack — but inside the WiFiS3 library's
`ModemClass::buf_read`, not our code. The WiFi driver allocates
Strings internally on every `client.read()`. Removing String use in
ccapiRequest didn't help because the library does the same allocation
one frame deeper. We can't avoid this without rewriting WiFiS3.

**Update — regression test against pre-cleanup version.**
Operator uploaded a much older v3 sketch (~Day-14 era, pre-part-3 —
still had `findTableRowForTv`, `lum_fetch_skip_remaining`, the old
String-based reads, all the things later sessions retired). Flashed
and tested /stop. **Did NOT crash on that run.** 31 photos delivered,
clean `[lum] live view stopped status=503` log. Initially suggested
today's changes destabilised /stop.

**Update — back-out + retest revealed it's NOT a code-state issue.**
Reverted today's part-7 work (stack instrumentation removed,
char-buffer change reverted) — restored end-of-part-6 sketch (4843
lines). Re-ran the /stop test. **Crashed again** with same signature.
So the v3 "clean" run was just lucky timing; the bug is **intermittent
across runs of identical code**.

**Revised understanding (end of part 7):**

- /stop crash is a **race condition** between CAN RX ISR and WiFi
  blocking-read path. Whether it manifests depends on millisecond-
  level timing of when /stop arrives relative to CAN message bursts.
- The String-in-WiFi-library finding from fix-attempt-1 means heap
  pressure isn't the only mechanism — even without our String use,
  the library still allocates inside the read path.
- The stack-overflow hypothesis from the painted-stack measurement
  (1024/1024 used at idle) is real and concerning, but doesn't
  fully explain the crash by itself either — v3 with even more
  String use should crash MORE often if stack overflow were the
  sole cause, but didn't crash on the one test we did.
- Honest position: **mechanism partially understood, root cause
  not isolated. Multiple possible contributors. Intermittent.**

**Restated fix candidate ranking after evidence:**
1. **Stop CAN push-subscribe before /stop** — best masking option.
   Closes the race window completely by silencing the ISR during
   teardown. Doesn't require understanding root cause.
2. **Disable CAN RX interrupts around the DELETE** — same idea, even
   narrower window.
3. **Avoid /stop entirely** — current workaround. Power-cycle to end
   shoots. Production-safe but operator-friction.
4. **Giga R1 (v2 / #47)** — different platform, removes the SRAM
   constraint and likely the race timing too. Long-term.
5. ~~Char-buffer reads in ccapiRequest~~ — **ruled out by experiment**.
   Doesn't fix the underlying race; library still allocates Strings.

WORKFRONTS #48 entry updated with revised understanding.

**Fix attempt 2 — `enablePush(false)` + delay before /stop teardown.**
Added 2 lines before `ccapiStopLiveview()`: disable CAN push subscribe
to silence the gimbal, then 50ms delay to let the bus quiet. Goal: close
the ISR-vs-WiFi-read race window by removing the ISR side.
**Result: still crashed**, but with a different stack signature. addr2line
showed the CAN ISR was NO LONGER in the crash stack — `can_rx_isr`,
`r_can_call_callback`, `CanMsgRingbuffer::enqueue` all gone. Crash was
still in `WiFiClient::read` / `Stream::readStringUntil` during the DELETE,
but without the CAN ISR overlay. Fault address `0x810076c3` — high bit
set, no longer the heap-pointer + bit-flip pattern seen earlier.
**Useful diagnostic finding:** at least two distinct corruption mechanisms
contribute to the /stop crash. Silencing CAN closes one. Something else
remains. Reverted (we can re-add if we have a reason).

**Final resolution: minimal /stop handler.** Operator observation:
"/stop never crashed in 14 days of operation, only today" combined with
"1 crash in 5 stops is 1 too many" reframed the problem. We had been
trying to fix the crashing code. The simpler path: **don't call it.**

Audited what /stop actually does. Five steps:
1. Set `shutter_mode = 0` (stop PIN8 firing) — local, can't fail
2. Set `shutter_paused = false` — local, can't fail
3. `enablePush(false)` — single CAN frame, non-blocking
4. `ccapiStopLiveview()` — HTTP DELETE to camera, **the crashing call**
5. Serial summary print — can't fail

Step 4 is housekeeping. Camera times out liveview sessions on its own;
`ccapiStartLiveview()` already handles "Already started" 503 for stale
sessions. So step 4 was never required for correctness.

Minimal /stop applied — only steps 1, 2, 5 retained. Tested through
two full cycles:
- Cycle 1: /start → 29 photos → /stop → clean exit, no crash
- Cycle 2: /start → camera POST /liveview returned 200 ("[lum] live
  view started" — fresh session, camera had timed out the old one
  during the ~20s gap) → 7 photos → /stop → clean exit

**#48 closed for v1.** Crashing code removed from hot path. The
underlying bug in WiFiS3 / Stream / String / CAN ISR interaction is
still there, but cart no longer touches it. v2 (Giga + Ethernet) will
revisit, since that platform may resolve the root cause incidentally.

Trade-off documented inline in the /stop handler: skipped DELETE
means the camera session lingers a few seconds longer; no operational
impact observed.

---

### Day-15 part 6: more dead-var cleanup + canFlip removal + memory snapshot

Two more sketch trims following the part-5 pattern:

**1. #36d cleanup completed.** Traced the original WORKFRONTS
"dead state vars" list var-by-var:
- `lum_fetch_skip_remaining` — dead (branch unreachable, nothing ever
  set it non-zero). Removed, plus its check block in the fetch-service
  loop and two stale comments.
- `lum_consecutive_conn_fails` + `LUM_FAIL_THRESHOLD` — NOT dead. They
  are the liveview-died detector; 3 connection-level fails invalidates
  `lum_liveview_started` for fresh re-POST. Also exposed in
  `/exposure/state`. KEEP.
- `lum_in_outage` — NOT dead. Log-spam suppression flag. KEEP.
- WORKFRONTS line "all sitting at 0 / dead-branch" was wrong about these;
  cleanup item rewritten with verified status of each candidate.

**2. canFlip preconditions removed.** `tryFlipToTableMode` previously
required `exp_anchor_set && exp_tv_ceiling_sec != 0 && current_tv != ""`.
These existed to feed the retired `findTableRowForTv()` call. Decision
basis: the execute UI (planned, separate workfront) prevents
uninitialised cart starts upstream, so the gates protected against a
case that can't happen at runtime. Also aligns with photos-sacred +
autonomous-cart framing: if CCAPI fails, reaching TABLE is the right
move regardless of init state. Removed. Sketch 4862 → 4843 lines after
both trims.

**Verification:** ran the standard sequence end-to-end. 62 photos
delivered cleanly through the LIVE phase before operator hit
`/shutter/stop` and the known #48 bus fault recurred (same crash
signature, photos #1–#62 all delivered). canFlip change unaffected
during the LIVE phase. FLIP path itself not exercised this run (no
WiFi outage), but the only code change touched the LIVE→TABLE entry
function and the rest of LIVE behaviour was unchanged.

**Memory snapshot (post all Day-15 trims):**
- Flash: 135,316 / 262,144 bytes = **51.6%** (Day-15 baseline 50%,
  ~+1.5% net for the session)
- SRAM globals: 22,588 / 32,768 bytes = **68.9%** (Day-15 baseline 68%,
  essentially unchanged)
- Local-variable headroom: 10,180 bytes

Flash has plenty of room. SRAM globals at 69% is the binding constraint
for new features. Day-7's failed `CART_LOG_MAX = 128` bump (.stack_dummy
overlapped .heap) is the historical evidence that the SRAM ceiling
is real, not theoretical. Future features that touch this budget:
#30 (cart log buffer size), #40 (BNO085 ring buffer), `/plan/load`
JSON parsing at scale. Giga R1 (1 MB SRAM) absorbs this via #47.

**Open observation — /shutter/stop bus fault reproduced.** Same crash
as part 5, same stack-region address. Hardware damage previously
attributed to the bus fault is itself unmeasured (see Day-15 part 5
notes — cause of transceiver death is "unknown" per the PREFERENCES
no-guessing rule). The fault itself however is reproducible, occurs
exclusively in the `/stop` handler, and is the basis for the #48
workaround (avoid the endpoint, power-cycle to end shoots).

---

### Day-15 part 5: dead-var cleanup + /shutter/stop bus fault

Two small dead identifiers removed from v1 sketch: `FETCH_FAIL_BACKOFF_CYCLES`
(constant, no reads) and `MODE_FLIP_THRESHOLD` (define, never referenced
— `PROBE_COUNT` is the live equivalent). Sketch −15 lines. Re-test ran
clean through full cycle: 87 photos delivered across LIVE → PROBING →
TABLE → Step D → LIVE. Same shape as part-3 verification.

**Open observation — bus fault on `/shutter/stop` after #87.** Photo
fetch succeeded normally (#87, fetch ok=Y, lum=0, in_deadzone), then
operator hit `/shutter/stop` → cart entered the stop handler →
firmware bus fault, address `0x20025961` (SRAM region), PC `0x0000f1ca`.
Stack dump in transcript. Crash is in the stop path, photos #1–#87
were all clean.

- Previous test (Day-15 part 3) reached `/stop` fine and reported
  `photos_taken=104`. Same code path, different outcome.
- The dead-var edit removed only a `static const = 0` and a `#define`
  that was never referenced. Neither could plausibly change runtime
  behaviour. Edit is not suspected.
- Most likely: stochastic memory-state issue (heap fragmentation,
  stack growth into something, WiFi-stack interaction). Not
  investigated this session — operator's call to move on; photos
  were delivered.

**Crash has real cost (discovered later this session).** Subsequent
bench work showed the CAN transceiver was fried by this crash. CAN
TX errors climbing in bursts of 6, bus impedance measurements
ruled out wiring (terminators sane, 65Ω in parallel as expected).
Swapping the SN65HVD230 transceiver fixed the gimbal comms. So the
`/shutter/stop` bus fault is not just a cosmetic end-of-shoot annoyance
— it can damage hardware downstream. Promotes this from "note it
and move on" to a real workfront. New entry in WORKFRONTS as
**#48 /shutter/stop bus fault**: reproduce, localise (add Serial
checkpoints inside the stop handler), fix.

If this recurs, the investigation order would be: reproduce → check
whether `/stop`-specific or any-shutdown → look at `0x20025961`
relative to known heap/static layout → add `Serial.print` checkpoints
inside the stop handler to localise.

---

### Day-15 part 4: Turning-circle measurements (#20 / #29)

Real-world measurement of cart turning diameter at six servo
offsets. SCX6 chassis on actual ground, walked through full circles
and tape-measured. Standalone calibration drive (no plan execution
yet).

| Servo offset (°) | Diameter (m) | Radius (m) |
|---|---|---|
| 5  | 18.0 | 9.00 |
| 10 | 10.0 | 5.00 |
| 15 |  7.5 | 3.75 |
| 20 |  5.6 | 2.80 |
| 25 |  4.8 | 2.40 |
| 30 |  4.2 | 2.10 |

**Bicycle-model fit attempted, declined.** Pure bicycle model
`R = L/tan(δ_wheel)` with linear servo→wheel linkage doesn't fit:
the "Ackermann constant" `R × δ_servo_rad` climbs from 0.785 at 5°
to 1.100 at 30° (40% increase). Possible causes: non-linear linkage
at extremes, rear-wheel scrub on tight turns, suspension geometry
shift under load. The model also has structural ambiguity from
radius-only measurements — wheelbase L and servo-ratio k can't be
separated without an independent measurement (e.g. static ruler or
front-wheel goniometer).

**Decision per principle #15 (Visualisation > Manipulation):** the
table above IS the calibration. Use it directly as a lookup for
operator turn advice (#29a) — "want a 5m diameter turn? set servo
to ~25°". No fitted physical model needed for that. BicycleModel.bas
still earns its keep for CartLog→(x,y) trace integration; cm-accuracy
isn't the goal there either, eyeball-correct is enough.

**Measurement tolerances:** SCX6 has long-travel suspension; chassis
pitches and rolls under turn loads, tyres scrub on tight turns,
outdoor measurements honestly ±0.5m. The 40% climb in the Ackermann
constant is partly real non-linearity and partly noise; we cannot
separate them from this data alone, and don't need to.

**Tightest achievable turn: ~4.2m diameter at max servo (30°).**
Useful for shoot-planning sanity (any waypoint pair requiring tighter
than 4m radius needs the operator to drive a multi-leg manoeuvre).

---

### Day-15 part 3: v1 TABLE-mode simplification

Follow-on from the Part 2 v1/v2 split. With Step 4 (per-cycle
PUTs from TABLE) permanently closed for v1, the table-row
lookup that produced `exp_delta_t_rel` at flip had no consumer
— and neither did the `last_table_tv` / `last_table_iso`
snapshots, which only existed to support change-detection for
the never-built per-cycle PUT. Retired the lot, plus the
function and endpoint that fed them.

**Code removed from v1 sketch:**
- State vars: `exp_delta_t_rel`, `last_table_tv[8]`, `last_table_iso`
- Function: `findTableRowForTv()` (~30 lines + comment block)
- Endpoint: `/debug/match` (~60 lines)
- Block inside `tryFlipToTableMode`: matchedTrel/matchedIdx
  locals, the call to `findTableRowForTv`, the Δt_rel
  assignment, the `last_table_*` snapshot writes, and the
  matched/no-match Serial logs
- Δt_rel discard line + reset in the Step D recovery branch
- 3 fields from `/exposure/state` JSON response
- Header + state-block comments rewritten to describe v1's
  actual capability (no table lookups, no Δt_rel) rather
  than the original Day-13 design

**Preserved (still earning their keep):**
- `exposure_mode` flag and EXP_MODE_LIVE / EXP_MODE_TABLE
- `tryFlipToTableMode()` (now simpler — just flips and logs)
- All three TABLE-mode CCAPI gates (fetch arm, fetch service,
  PROBING entry) — Day-15 rule still applies
- Step D scheduler, recovery branch, liveview invalidation
- `last_mode_change_ms` (for `/exposure/state` reporting)

**Held back (separate decision needed):** the `canFlip`
precondition in `tryFlipToTableMode` still requires
`exp_anchor_set && exp_tv_ceiling_sec != 0 && current_tv != ""`.
With table lookups gone, those preconditions are arguably
stale — removing them would let TABLE engage on a cold-start
cart that never completed `/exposure/init`. Behaviour change,
not pure cleanup. Flagged but not actioned.

**End-to-end verification (this session, 22 May):**

| Phase | Photos | Behaviour |
|---|---|---|
| LIVE start | #1–#9 | clean 2s cadence, fetches ok=Y |
| Discovery | #10 | 10s CCAPI connect-fail → PROBING |
| PROBING probes | #11–#17 | 3 ping fails, ~1s each |
| FLIP | between #17/#18 | clean log, no Δt_rel or match output |
| TABLE | #18–#77 | ~60 photos clean 2s cadence, zero CCAPI |
| Step D probe | between #77/#78 | ping ok, recovery → LIVE |
| LIVE post-recovery | #78–#104 | liveview restart, fetches ok=Y, in_deadzone |

**Photos delivered: 104/104.** FLIP log line confirmed clean
at the wire: `[#36d] FLIP LIVE -> TABLE (via probe) event=sunset
trel_now=-11703 current_tv=1/5000 current_iso=100` — no orphan
fields. `/exposure/state` JSON confirmed clean (no `delta_t_rel`,
`last_table_tv`, `last_table_iso`).

**Files modified this session:**
- `DJI_Ronin_UnoR4_v1prod.ino` — −143 lines (4986 → 4843)

**Mental model:** with Step 4 closed, TABLE mode is now
exactly what it operationally needed to be all along: a
"don't talk to the camera, just keep photos firing, ping
every 60s" state. The Day-13 design carried Δt_rel and table
lookups in anticipation of Step 4; closing Step 4 lets us
collapse the state to match the actual behaviour. Less code,
same delivery, same robustness.

---

### Day-15 part 2: v1/v2 architectural decision + sketch branch

After Step D verified, discussion widened to comms-outage
fallback architecture. Operator's risk assessment: external
WiFi failure is the only unacceptable risk; camera-side and
cart-side WiFi failures are accepted (rare, handled by
Fallback 1 + Step D).

Three options explored in research: camera-as-AP WiFi,
wired Ethernet point-to-point, USB+Pi+EDSDK. Wired Ethernet
chosen for v2 — structurally cleanest, removes the entire
camera WiFi path from the design, and (key insight) allows
TABLE-mode camera nudging that was impossible in v1.

v1 vs v2:

| | v1 (current) | v2 (future) |
|---|---|---|
| Board | Uno R4 WiFi | Giga R1 WiFi |
| Camera link | WiFi via external AP | Wired Ethernet direct |
| Camera WiFi | Used | Disabled |
| External WiFi | Cart + camera both use | Cart only (operator UI) |
| TABLE camera nudge | Impossible | Allowed |
| Excel/UI HTTP API | Shared | Shared (identical) |

v2 hardware: Giga R1 (on hand) + Arduino Ethernet Shield 2
($51 AUD). #22 Giga migration absorbed into v2 build.

Sketch branched:
- `DJI_Ronin_UnoR4_v1prod.ino` — v1 production, bug-fix only
- `DJI_Ronin_Giga_v2dev.ino` — v2 development starting point,
  same code, ported to Giga + W5500 Ethernet for camera

Both files include a header block stating which branch they
are, the architecture, and what TABLE mode does/doesn't do
in each version.

#36d Step 4 (TABLE actively pushing Tv/ISO to camera) is
permanently closed for v1 (logically impossible — CCAPI
unreachable when in TABLE). Re-opens as a build task in v2
because the wired link is independent of the WiFi outage
that caused entry to TABLE.

---

## Day-15 session — #36d Step D (TABLE → LIVE recovery)

Build session. Extends the Day-14 comms-recovery state machine
with a recovery path so TABLE is no longer a one-way trip per
shoot. Three rounds of test exposed two real bugs in the
adjacent Day-14 code that didn't surface in the Day-14 outage
test because that test cut WiFi mid-cycle in a different phase.

### What was built

**Step D scheduler + merged probe block.** Constants:
`TABLE_PROBE_INTERVAL_MS = 60000`. State: `last_table_probe_ms`.
Scheduler block inside the photo-fire branch arms `probe_pending`
once the wall-clock interval elapses while in TABLE+NORMAL. The
existing PROBING probe-fire block was merged into a two-source
form with explicit `from_table` classification (set when the
predicate matches, not derived after the fact), so a probe is
unambiguously one or the other.

**Recovery branch.** On TABLE-source ping success:
`exposure_mode → LIVE`, `exp_delta_t_rel = 0`, log discard,
invalidate liveview (see Bug 3 below). Standard
`adjustExposureByLuminance()` then nudges Tv/ISO back into the
dead zone via the one-step-per-fetch walk on the next fetch
cycle. No special recovery PUT needed — the dead zone is the
natural arbiter (if TABLE under-nudged, walk pulls it back; if
TABLE over-nudged, in-deadzone says wait).

**Recovery fail path:** stay in TABLE, scheduler re-arms after
another 60s. No fail counter (TABLE is already the failure
state).

### Bugs found and fixed mid-build

**Bug 1 — stale fetch firing after FLIP.** First Step-D test run
showed only ONE TABLE probe and no recovery despite WiFi
returning. Root cause: at the moment of FLIP, `lum_fetch_pending`
had already been set 3 photos earlier by the every-Nth scheduler.
After FLIP the code reset `comms_mode = NORMAL`, which opened the
fetch-service gate. The stale fetch then fired, hit a 10s
connect-fail, and re-entered PROBING — which suppressed Step-D
probes (their predicates require `comms_mode == NORMAL`). Fix:
gate both `lum_fetch_pending = true` assignment AND fetch
service on `exposure_mode != EXP_MODE_TABLE`. Belt-and-braces
on both arm and service sites.

**Bug 2 — re-entering PROBING from TABLE.** Even with fetches
gated, any other CCAPI call from inside TABLE could trip the
PROBING entry block (`comms_mode = PROBING`, `probe_pending =
true`). That would mask Step-D probes the same way. Fix: gate
PROBING entry on `exposure_mode != EXP_MODE_TABLE`. Once in
TABLE, no CCAPI failure can disturb state; only Step D's 60s
ping can move us out.

**Bug 3 — stale liveview session after recovery.** Second test
run got TABLE → LIVE flip cleanly but fetches afterwards
returned 503 forever (~250-700ms each, not the 10s connect-fail
pattern). Camera CCAPI was responding fine — but the
`/shooting/liveview` session expired during the outage. The
existing dead-liveview detector requires 3 *connection-level*
fails to invalidate `lum_liveview_started`; 503 is
application-level, doesn't increment. Result: cart kept asking
for a luminance histogram from a dead session and accepting the
503. Fix: on TABLE → LIVE recovery, set `lum_liveview_started
= false` and `lum_last_liveview_attempt_ms = 0`.
`tryStartLiveviewIfNeeded` then POSTs a fresh /liveview on the
next loop iteration. Single small addition to the recovery
branch.

### Verified end-to-end

WiFi-off-then-on test, single full cycle:

| Photo | Gap | Cause |
|---|---|---|
| #16 | ~10000ms | initial CCAPI discovery (10s connect-fail) |
| #18 | ~3020ms | PROBING probe attempt 1 |
| #21 | ~3019ms | PROBING probe attempt 2 |
| #24 | ~3035ms | PROBING probe attempt 3 → FLIP to TABLE |
| #25 onwards | 2000-2004ms | clean TABLE cadence, zero CCAPI |
| ~#55 | ~3023ms | Step-D probe → ping success → LIVE recovery |
| #56 onwards | 2000-2004ms | post-recovery, liveview restarted, fetches ok=Y |

**Photos delivered: 64/64. Zero dropped.** WiFi happened to come
back within the first 60s window, so only one TABLE probe fired
this test. Multi-probe TABLE cycle (longer outage) not
specifically exercised but mechanism is symmetric and tested
in pieces.

### Setup gotchas (re-discovered)

- `/exposure/init` must succeed before `/shutter/start` — it
  populates `current_tv`, which is a precondition for
  `tryFlipToTableMode`. Without it, FLIP returns "blocked:
  current_tv=(empty)" and the cart stays in LIVE forever
  through repeated CCAPI failures. Day-14 had this set up via
  the test harness; first Day-15 test ran with camera WiFi
  already off at init time, exposed the brittleness.
- Standard sequence reinforced: CCAPI alive check → init
  (verify Tv/ISO in response) → Push Formula to Cart (Excel) →
  exposure/target → shutter/start. Skipping any one of these
  produces a quiet failure mode later.

### Files modified this session

- `DJI_Ronin_UnoR4_v3.ino` — Step D scheduler + merged probe
  block + recovery branch with liveview invalidation; three
  TABLE-mode gates (fetch arm, fetch service, PROBING entry);
  comment header updated for Step D-built status.

### Mental model corrections recorded

- **Once in TABLE, no CCAPI call should originate from the
  cart.** Step-D's 60s ping is the sole permitted outbound
  CCAPI activity. Any other CCAPI call — stale fetch, anchor
  retry, liveview-restart, ISO PUT — risks the 10s connect-fail
  block and (worse) re-entry to PROBING that suppresses Step D.
  Gates on `exposure_mode != EXP_MODE_TABLE` apply at every
  CCAPI-call origination site, not at the request layer.
- **Liveview session state is camera-side, not cart-side.**
  `lum_liveview_started` is the cart's belief about the camera's
  session; it can go stale during outage even though
  WiFi-reachability looks fine afterwards. Recovery from outage
  must invalidate the cart-side belief. The existing
  connection-fail-counter doesn't catch 503-after-recovery
  because 503 isn't a connection fail.
- **Dead zone is the natural recovery arbiter.** Step D doesn't
  need to compute a "what should Tv/ISO be now" PUT at recovery
  — the next luminance fetch tells us whether TABLE under- or
  over-nudged, and the standard walk pulls back into deadzone
  either way. Symmetric with LIVE→TABLE: handoff is jolt-free
  by construction.

---


Build session. The Day-13 designs for #36d became code; the comms
failure handling around them was rebuilt from scratch when the
existing "be polite to recovering camera" approach proved fatal to
photo cadence during a real outage.

### What was built

**Step 1 — state vars + `/exposure/state` extension.** New: `exposure_mode`
(LIVE/TABLE), `consecutive_fetch_fails/successes`, `exp_delta_t_rel`,
`last_table_tv/iso`, `last_mode_change_ms`. No behaviour change.

**Step 2 — `findTableRowForTv()` + `/debug/match` endpoint.** Match
returns t_rel of the table row whose Tv value matches `current_tv`.
Comparison is by **seconds, not string identity**, with 0.5% relative
epsilon — handles Excel's decimal format ("0.5", "1.3", "20") matching
Canon's format ("0\"5", "1/250"). `tvStringToSeconds()` extended to
parse plain decimals and plain integers (previously only fractions and
quote-notation). Verified across all 5 Tv formats including realistic
miss case.

**Step 3 (built then rebuilt) — comms-recovery state machine.**
Originally wired `consecutive_fetch_fails` counter with 3-fail
threshold. Real-world test exposed the flaw: every failing CCAPI call
blocks the cart loop for 10s (library-level `client.connect()`
timeout, can't be shortened per PREFERENCES known quirk). At
`LUM_LIVEVIEW_RETRY_MS = 30000` the cart blocked 10s out of every 30s
during outage — visibly broken cadence. Dropping retry to 10s made it
worse (continuous blocking). The fundamental issue: we shouldn't be
calling CCAPI at all once we know it's down.

**Step 4 onward — comms-recovery redesign.** New state machine:

- `comms_mode` = NORMAL | PROBING
- On ANY CCAPI connect failure → enter PROBING
- During PROBING, replace the every-3rd-photo fetch with a 1s
  `WiFi.ping()` — runs BEFORE pin-8 fires, so camera is idle during
  the ping (verified per PREFERENCES: photo recovery window is for
  camera, not free cart time)
- On ping success → back to NORMAL
- On 3 consecutive ping fails → flip to TABLE mode

**Step 5 — old logic gated/removed.** `tryStartLiveviewIfNeeded`
now gated on `comms_mode == NORMAL` AND `exposure_mode != TABLE`. The
ANCHOR CCAPI call in `/shutter/start` skipped when comms_mode already
PROBING (saves one 10s block on initial discovery). Step-3 inline
fail counters in `ccapiRequest` and `ccapiStartLiveview` removed —
PROBING is single source of truth. `FETCH_FAIL_BACKOFF_CYCLES` dropped
from 2 to 0 (the "give camera recovery time" rationale was Day-11
era thinking).

### Verified end-to-end

Camera WiFi off mid-test, 14 photos through the full failure cycle:

| Photo | Gap | Cause |
|---|---|---|
| #1 | 12089ms | initial discovery, single 10s CCAPI block |
| #2-#8 | 2000-2004ms | normal cadence |
| #3, #6, #9 | ~3020ms | probe-delayed photos (+1s for ping) |
| #9 | — | TABLE flip captured `delta_t_rel=26865`, `last_table_tv="0\"5"`, `last_table_iso=200` |
| #10-#14 | 2000-2004ms | post-flip steady state, no CCAPI activity |

**Photos delivered: 14/14. Zero dropped.** Cart count and card count
match. The cost model from design (1×12s on discovery + 3×1s on
probes + 0 dropped) verified in real-world test.

### Key measurements taken this session

- `WiFi.ping()` cost: **~1015ms regardless of outcome** (live host
  1005ms with 219ms RTT; dead host 1015ms, never-existed IP 1015ms).
  The 1s flat cost is the design's foundation.
- `client.connect()` to dead CCAPI host: **10001-10009ms** (confirmed
  for fetch path and liveview-start path).

### Files modified this session

- `DJI_Ronin_UnoR4_v3.ino` — substantial: state machine, ping helper,
  match function, gates, debug endpoints. Compiles cleanly. Flash
  usage well within Uno R4 limits.

### Step D (future) — TABLE → LIVE recovery during a shoot

Not built. Currently TABLE is a one-way trip within a shoot: cart
stays in TABLE until `/shutter/stop` (or reset). Acceptable for
production because:
- Post-shoot, LRTimelapse fixes the smoothed exposure walk
- Most outages last longer than the remaining shoot anyway
- Recovery probe in TABLE would re-introduce periodic blocking risk

When/if needed: periodic ping in TABLE at low rate (e.g. every 30s),
on 3 consecutive ping successes re-enable LIVE. Lives in WORKFRONTS
as a follow-up.

### Loose ends to clean up later

- `consecutive_fetch_fails`, `consecutive_fetch_successes`,
  `lum_consecutive_conn_fails`, `lum_in_outage`,
  `lum_fetch_skip_remaining` — dead state vars, sitting at 0 doing
  nothing. Remove when convenient.
- `LUM_FAIL_THRESHOLD` constant — also dead.
- `FETCH_FAIL_BACKOFF_CYCLES` — set to 0, branch still in code, can
  be removed.
- `MODE_FLIP_THRESHOLD` comment still references "fetch fails";
  meaning has shifted to "ping fails" (now equivalent to
  `PROBE_COUNT`). Either consolidate to one constant or document.

### Files added/modified this session

- `DJI_Ronin_UnoR4_v3.ino` (cart sketch)

### Mental model corrections recorded

- **"Camera stress" from CCAPI activity is not real.** Day-11 "78%
  delivery under CCAPI load" was the 100ms pulse-width issue (fixed
  Day 12). CCAPI itself is reliable when WiFi is up. The constants
  built around "be polite to stressed camera" were solving a phantom.
- **WiFi outage is the failure mode that matters.** Camera down, AP
  reboot, signal drop. Camera-busy-vs-idle complications don't enter
  the picture because the failure is binary (packet gets through or
  doesn't).
- **The 1.5s photo recovery window is NOT free cart time.** Pings
  there assume camera doesn't mind concurrent network activity during
  card write. Untested. Probe placement moved to BEFORE pin-8 fire,
  guaranteeing camera idle during the ping. Costs +1s on probe photos,
  buys deterministic camera state.

---

## Day-13 session — two designs resolved (#40 BNO + #36d Table Mode)

Pure design session. No code changes. Two unrelated workfronts
moved from "architectural questions open" to "design complete,
ready for build."

### Part 1: #40 BNO085 integration architecture resolved

All six architectural questions raised in WORKFRONTS #40 are now
resolved.

### Anchor design (resolved Q1, Q4, Q6)

**Purpose.** Keep the gimbal's earth-frame output honest against
cart-heading drift. Nothing else. Cart position and cart path are
NOT corrected. The cart drives its pre-baked path blind, believing
it is heading where Excel assumed at authoring time. The gimbal —
which has real earth-frame work to do during astro-track and
earth-frame pan-to-point segments — gets the correction.

**Mechanism.**
- BNO085 samples continuously into a small ring buffer on cart
  (cheap, runs in background, no impact on photo loop)
- Plan rows can carry an `anchor` flag with a per-row threshold,
  authored in Excel
- When cart reaches an anchor-flagged row, it pulls a clean
  averaged BNO yaw from the buffer
- Compares to Excel's pre-baked `expected_cart_heading` for that
  row
- If `|delta| > threshold`, updates a running scalar
  `gimbal_yaw_correction`
- All subsequent earth-frame-tagged gimbal cubics evaluate as
  `at³+bt²+ct+d + gimbal_yaw_correction`
- Pan-follow segments untouched (chassis-frame, no correction
  applies)
- Correction never snaps — only affects computation of the *next*
  gimbal move, never any move in progress
- WiFi-independent during execution

**Plan stream changes required for #40 to land.**
- Per-row `anchor` flag + threshold value in plan
- Per-segment frame tag (`earth_frame` vs `chassis_frame`) on
  CUBIC and HOLD segment types in the existing Segment struct
- Per anchor-flagged row, Excel bakes `expected_cart_heading` so
  cart can compute delta

**Cart-side footprint.**
- Continuous BNO sampling into ring buffer (~tens of samples)
- One float `gimbal_yaw_correction` (updated only at anchor rows)
- Frame-tag check at cubic eval time, one branch
- No bicycle-model integration, no per-photo BNO reads, no astro
  math on cart — all consistent with day-7 / day-8 architectural
  rules

### Offset persistence (resolved Q2)

The `c`-capture true-north offset folds magnetic declination +
BNO mounting angle into one number. Bench test gave +9.16° for
Adelaide; expected declination is +8.11° (web-verified), implying
~+1° BNO mounting angle on the bench setup.

**Storage: Excel-pushed via Settings**, NOT cart EEPROM.
- Operator captures via cart `c` command after
  calibration-by-driving achieves acc≥2
- Reads value from `/debug/imu` endpoint
- Types into Excel named range (suggested: `bnoOffsetDeg`)
- Excel includes it in next Settings/plan push (alongside
  Appendix A, yaw envelope, etc.)
- Cart receives, stores in SRAM, applies to every BNO read
- Re-capture only when something physical changed (mount tweak,
  new location, BNO replacement)

**Rationale.** Cost analysis: EEPROM (8 bytes used of 8KB, ~10
lines C) and Excel-push (1 float in settings struct, 1 named
range) are about equal in machine cost. Excel-push wins on
**architectural consistency** — fits the existing Settings
envelope pattern (#9 yaw envelope, #36b Appendix A, etc.). The
"more steps per shoot" cost is small because the value rarely
changes — operator types it once, every plan push carries it.

**Sanity check (optional).** Excel can display
`expected = declination(lat,lng) + recorded_mount_angle` next to
the typed value. Operator sees if drift looks wrong before
pushing.

### Acc dropout handling (resolved Q3)

Cart may approach an anchor-flagged row with BNO acc<2 (RF
interference, ferrous transient, calibration degradation).

**Two-attempt retry inside one anchor row.**
- **Attempt 1:** 500mm before waypoint. Pull averaged yaw, check
  acc.
  - acc≥2 → use it. Update `gimbal_yaw_correction`. Log
    `ANCHOR_OK, row=N, attempt=1, acc=X, delta=+Y°`.
  - acc<2 → log `ANCHOR_SKIP, row=N, attempt=1, acc=X`. Wait for
    attempt 2.
- **Attempt 2:** 400mm before waypoint. Same logic.
  - acc≥2 → use it. Log `ANCHOR_OK, row=N, attempt=2, acc=X,
    delta=+Y°`.
  - acc<2 → log `ANCHOR_FAIL, row=N, both_attempts_acc_low,
    kept_correction=+Y°`. Carry on with previous correction.

Photos sacred throughout — neither attempt blocks the shutter
loop, both run from the background BNO sampler.

500mm/400mm are sensible starting values, tunable in firmware
later if real-world data suggests otherwise. The two attempts
give one short window for any transient interference to pass.

**Rationale.** Stale correction beats bad correction. The drift
error missed for one anchor cycle is the same magnitude already
tolerated between anchors.

### Cart→Excel feedback (resolved Q5)

Anchor results logged to CartLog as new event type `A`.
- Subtypes: `A_OK`, `A_SKIP`, `A_FAIL` (or single Type=A with
  status column — detail for build time)
- Fields: row#, attempt#, acc value, delta_deg, applied_correction
- Pulled via existing `/cartlog` endpoint — no new infrastructure
- Excel-side: parser splits Type=A rows into a dedicated
  AnchorLog sheet on import, keeping CartLog itself clean
- Trace chart can optionally mark anchor points (small icon at
  the row's (x, y) — green for OK, amber for SKIP, red for FAIL)

**Rationale.** Anchors are cart events. CartLog is the cart event
log. Existing pull mechanism handles them. Excel-side sheet split
keeps the visual clean for non-anchor analysis.

### What was NOT decided

- Stream format detail for per-row anchor flag + threshold +
  expected_heading — design at build time when /plan/load schema
  is touched anyway
- Frame-tag bit position in Segment struct — design at build time
- BNO ring buffer size and sample averaging window — sensible
  default ~3 sec, tune from real-world data
- Whether `A` events overload existing CartLog columns or add a
  status column — Excel-side detail, decide when building the
  parser

### Part 2: #36d remaining subtasks resolved (Table Mode + Δt_rel offset)

The four remaining #36d subtasks (after subtask 1 Time anchor was
done Day 12) all closed in this session. Two were stale or
eliminated; two were designed.

**Outage detection — resolved.**
- Cart counts consecutive luminance fetch outcomes
- **3 consecutive fetch failures** → LIVE → TABLE mode
- **3 consecutive fetch successes (while in TABLE)** → TABLE → LIVE
- Same fetch cadence both modes (every Nth photo, no separate
  probe schedule)
- Threshold grounded in Appendix A data: peak rate of change is
  1/3 stop per 60s in civil twilight; 3 missed fetches at ~6s
  cadence = ~18s gap = well inside the 60s tolerance window
- "3 fail, 3 success" symmetric thresholds — same number both
  directions, easy to reason about

**Recovery smoothing — eliminated, not just deferred.**
- The exposure curve is monotonic in one direction per phase
  (sunset darkens, sunrise brightens — `mode=darken` /
  `mode=skylight` set once at shoot start)
- LIVE mode walks one step per fetch in the configured direction
  via existing `adjustExposureByLuminance()` + `nextTv()` /
  `nextIso()`
- TABLE mode walks the table's own step-function in t_rel
- When TABLE → LIVE handoff occurs, the existing one-step-per-fetch
  walk IS the smoothing — no extra logic needed
- Smoothing the already-shot image is also pointless: exposure
  error is baked into the SD card the moment the photo fires;
  smoothing only delays return to truth
- Removed from subtask list; will not be built

**Tv-format Canon translation — stale subtask.**
- Cart already has a hard-coded `TV_LADDER[]` (line 414 of
  production sketch) with all 60 Canon-format Tv strings
  (`0"5`, `2"5`, `1/5000` etc.)
- Excel pushes Appendix A in Canon-format strings already
  (Day 12 verified end-to-end: 51/12/49/14 entries landed
  correctly)
- `ccapiPutTv()` handles JSON-escape of embedded `"` at send time
- No new translation work needed; subtask removed from list

**Photo-loop integration — resolved as Table Mode + Δt_rel
offset.** The hardest of the four; multi-step design.

*Mode shape:*
- `exposure_mode` flag: `LIVE` (default) or `TABLE`
- Photo loop untouched, fires shutter every interval_ms (sacred)
- Fetch path branches on mode but produces same output shape
  (a PUT, or no PUT)

*"Formula" is a misnomer.* Inspection of cart sketch lines 714
and 756 confirmed: `formulaTv()` and `formulaIso()` are
**step-function lookup tables**, not formulas. Walk ascending
t_rel array, first row where `arr[i].t_rel >= t` gives the Tv.
No interpolation. Renamed concept to **Table Mode** for clarity;
C identifiers (`formulaTv` etc.) left unchanged (working code,
not worth touching for a cosmetic rename).

*The Δt_rel offset (key insight):*
- CCAPI loop in LIVE mode walks Tv/ISO based on actual scene
  luminance. On a dull/dark afternoon, CCAPI might walk the
  cart to Tv=1/100 by the time t_rel says it "should" be at
  Tv=1/200 (one stop ahead of the clock-driven canonical curve)
- Blindly switching to `formulaTv(t_rel_now)` at handoff would
  undo that accumulated wisdom and jolt the exposure
- **Solution:** at LIVE → TABLE handoff, find the table row
  whose Tv matches `current_tv`. The t_rel of that row is the
  "effective t_rel" the CCAPI loop had walked the cart to.
  Compute `Δt_rel = matched_row_t_rel - t_rel_now`. From here,
  table lookups use `t_rel_now + Δt_rel`
- Properties: no jolt at handoff (first PUT matches `current_tv`
  by construction), preserves CCAPI loop's accumulated
  weather-correction, subsequent nudges follow the table's
  natural step intervals

*Per-cycle behaviour in TABLE mode:*
- Compute `target_tv = formulaTv(t_rel_now + Δt_rel)` and
  same for ISO
- Compare to `last_table_tv` (recorded at the previous TABLE-mode
  PUT, or at handoff)
- PUT only when the table actually crosses to a new value
  at the current offset-adjusted t_rel (i.e. only on row
  boundaries). Otherwise hold.
- This naturally paces nudges by the table's own intervals
  (60s in steep zones, hundreds of seconds in flat zones) —
  not by photo cadence
- Probe attempts (CCAPI fetches) continue at the existing every-3rd
  cadence; on the 3rd consecutive success, flip back to LIVE

*TABLE → LIVE handoff:*
- Δt_rel is discarded
- Next fetch reading drives one nudge in the configured direction
  via existing `adjustExposureByLuminance()`
- Subsequent fetches keep nudging until the reading lands in
  deadzone — may take several fetches if reality drifted
  while cart was in TABLE mode; that catch-up walk IS the
  smoothing

**Edge cases — closed without separate design pass.**
- "Edge cases" was Day-12 era language from the opto / pulse-width
  investigation, where electrical/timing edges under load were the
  thing to find. #36d has no analogous continuous parameter near a
  hardware limit — it's a discrete state machine with mode flips
  and a Δt_rel offset.
- Candidate edge cases (boot timing, t_rel boundaries, current_tv
  not in table, Tv-pinned-at-ceiling zone with ISO ramp, sustained
  outage, wild CCAPI reading, operator manual override) all have
  obvious handling paths and are implementation details for the
  build, not design questions.
- Per PREFERENCES discipline: address them at build time when each
  branch of the state machine is exercised against actual behaviour.
- Removed from subtask list.

### What was NOT decided (#36d)

- Exact `current_tv` → table-row matching logic when no exact
  string match exists (closest-by-EV is the obvious choice but
  not coded yet; decide when building)
- Whether ISO gets its own offset or shares Tv's `Δt_rel` (in
  the active Tv-walk zone, ISO is pinned at 100; only at the
  20s ceiling does ISO ramp; sharing the offset is likely fine
  but verify when building)
- Whether wild-CCAPI-reading rejection (>2 stops from prediction
  per EXPOSURE_FALLBACK §6.6) lives inside the LIVE mode loop or
  as a sanity gate at handoff time — build decision

### Files modified today

None. Design session only. Resolution captured in PROJECT_STATE
and WORKFRONTS.

---

## Day-12 session — Pulse width identified as root cause

The Day 11 hypothesis that "CCAPI activity stresses the camera and
causes drops" is overturned. The Canon R3 needs the shutter line
held LOW for ~200ms to register reliably; production's 100ms pulse
was at the edge, and any CCAPI-induced camera slowdown pushed a
fraction of triggers past the edge into drops.

Built `DropTest.ino` — a minimal fork of the production sketch on a
spare Uno R4 WiFi — to sweep variables independently. Key changes:
analyser marker pins on 2/3/5/6, /echo verification endpoint,
/debug/liveview_at_start?on=N flag for true zero-CCAPI baseline,
and pulse width raised to 200ms.

Results across 7 test runs proved:
- Pulse width is the cause (100ms → 53.8-70.4%, 200ms → 96-100%)
- CCAPI load is not the cause (200ms holds up under full Day-11
  stress condition: 37/37 = 100%)
- The opto path is innocent (200ms with intervalometer = 100%,
  200ms with Uno+opto = 96-98%)
- Production resilience verified: a real fetch timeout mid-run was
  handled cleanly, backoff applied, recovery automatic, and all
  photos still landed

See `DAY12_SUMMARY.md` for full data table, traces, and reasoning.

**Production fix applied and validated end-to-end:**
- `backupShutter()` micros window raised from `100000` to `200000`.
  One-line change to the production sketch (`DJI_Ronin_UnoR4_v3.ino`),
  with an 8-line rationale comment above the loop.
- Flashed to cart, ran the Day-11 stress condition end-to-end:
  Tv=0.5", interval=2000ms, mode=darken, luminance fetch every 3rd
  photo, live view active. 38 fires, 38 photos on card. **100%
  delivery.**
- PULSE log confirms full 200ms hold (`high=56820/56820`,
  `fire_us=203765`) — every readback sample HIGH across the window.
- `fetch attempts/successes/errors=12/12/0` — same CCAPI load as
  Day-11 Run #1 (which delivered 70.4%), now 100%.

The chronic 70-74% delivery issue in the 2-second zone is resolved.

**Workfronts resolved this session (key items):**
- #1 / #3 (opto swap, post-opto re-test) — innocent, not needed
- "Stage 4 milestone" reduces to production-envelope soak only
- "Logic-analyser-first vs opto-first" — analyser-first answered it
- #16 / #36c (time-based luminance fetch) — deleted
- #9 (±180° yaw → cumulative) — done via Settings envelope
  (`gimbalYawEnvelopeMin` / `gimbalYawEnvelopeMax`, default ±225°,
  450° span). GimbalPosition refuses out-of-envelope commands.
- #36b (Formula evaluator on cart) — Excel pushes Appendix A
  parameters via GET query (~1.3 KB URL inside the 1.5 KB envelope
  verified via /debug/urlsize). Cart stores ~1.4 KB RAM, walks
  parser matching Excel's UDF logic. Verified end-to-end with 9
  evaluation points + real Appendix A push (51/12/49/14 entries
  landed correctly). `/debug/formula` diagnostic endpoint retained.
- #36d subtask 1 (Time anchor on cart) — Excel sends both sunset
  and sunrise trel anchors plus astronomical-sunset crossover
  threshold (`t0ss`, `t0sr`, `cross`). Cart advances both in
  lockstep from millis base, picks active event by sunset-trel vs
  cross. One push covers a full sunset-through-sunrise shoot.
  Verified end-to-end. `/debug/trel` reports full state. Sketch
  now at 50% flash, 68% globals.
- #40 BNO085 first-light — Adafruit 4754 on Uno R4 over I2C,
  alive at 0x4A. Standalone `BNO085_BenchTest.ino` calibrates via
  figure-8 motion (acc=3 achievable), captures true-north offset
  against iPhone compass with single `c` command, tracks to
  within ±3° of iPhone across all four quadrants. Negligible
  error for 14mm lens (~3% of frame). NOT yet integrated into
  production sketch.

---

## Older sessions (archived)

Days 5–11 detail moved to `PROJECT_STATE_old_ver1.md`. One-line
stubs for reference:

- **Day 5** — Stage 3 Tv-driven cadence, body-read 30× speedup,
  fetch backoff, REQ-PHASES instrumentation committed.
- **Day 6** — PIN8 + PULSE instrumentation, cart-vs-camera
  cross-reference (uncommitted at end of day).
- **Day 7** — Cart Log/Plan/Execution architecture (pure design,
  no code).
- **Day 8** — Gimbal architecture overhaul; astro pre-baked in
  Excel, Catmull-Rom evaluated in Excel, cart sees cubic
  coefficients only. See GIMBAL_VIZ.md for the canonical version.
- **Day 9** — Servo-to-wheel calibration done; plan endpoints
  `/plan/load`, `/plan/start`, `/plan/stop`, `/plan/status`
  built and tested; UI polling fault resolved via avoidance;
  pano firmware built. Late evening: exposure cluster
  restructured around three-session model, FallbackFormula
  built + verified, exif_ingest.py + validate_exposure.py done.
- **Day 10** — Smooth Selection (#44 cluster) built end-to-end
  then REJECTED on operator-workflow grounds; CartLog became
  the Plan; new principle "Visualisation > Manipulation"
  (now in PREFERENCES). Kept: WobblyRecon.bas, BicycleModel
  Trace col H CartLogRow + chart row-number labels, SecToHms
  promoted Public.
- **Day 11** — Photo-drop investigation (later overturned by
  Day 12). Original CCAPI-stress hypothesis now obsolete.

---

## State of the system — MOVED

> The old "State of the system (current)" section has been REMOVED from this
> archive (it had gone stale — e.g. it still listed gimbal plan execution as
> "design only", contradicted by Day 24/28). **Current state now lives in a
> single source: PROJECT_STATE.md (NOW) and WORKFRONTS.md (open work).** This
> file is history only.


## Git repository structure

Two separate repos on the operator's local machine, each pushed
to its own GitHub remote. Captured Day 15 part 10 for future
session reference — Claude should know which files live where
before suggesting commit commands.

**Repo 1 — sketch (firmware):**
- Local path: `C:\Users\mauri\OneDrive\Documents\Github\DJI-Ronin-RS4-Arduino`
- Remote: `https://github.com/mwindley/DJI-Ronin-RS4-Arduino.git`
- Branch: `session-c-uno-luminance` (long-lived working branch
  carrying Day-12 onward). Master not yet caught up.
- Contains: all Arduino sketches (`DJI_Ronin_UnoR4_v1prod.ino`,
  `DJI_Ronin_UnoR4_v3.ino`, plus bench-test sketches like
  `BNO085_BenchTest`, `DropTest`, `I2C_Scanner`).
- The production v1 sketch path inside the repo:
  `DJI_Ronin_UnoR4_v1prod\DJI_Ronin_UnoR4_v1prod.ino`

**Repo 2 — Excel + docs:**
- Local path: `C:\Users\mauri\OneDrive\Documents\Github\HyperLapse-Excel`
- Remote: `https://github.com/mwindley/HyperLapse-Excel.git`
- Branch: `master`
- Contains: `HyperLapse.xlsm`, VBA modules (`Modules/*.bas`),
  Python scripts (`Python/*.py`), all design/state docs
  (`PROJECT_STATE.md`, `WORKFRONTS.md`, `PREFERENCES.md`,
  `UI_DESIGN_v2.md`, `UI_DESIGN_SUMMARY.md`, `GIMBAL_VIZ.md`,
  `EXPOSURE_FALLBACK.md`, `SHOPPING.md`, `TURN_TEST_RESULTS.md`,
  etc.), CSV reference data, ARCHIVE folder.

**Workflow:** Claude generates outputs to `/mnt/user-data/outputs/`
in the chat session. Operator downloads each file, then cuts from
`Downloads` and pastes into the relevant local repo folder before
running git commands. Sketch files go to repo 1, all .md / docs go
to repo 2.

**Implication for commit suggestions:** a single session often
produces changes to both repos (a sketch change AND a doc update).
That means **two separate commits**, one per repo. Cannot combine
into one. Future sessions: always check which repo a file belongs
to before suggesting `git add` paths.

**Other workfronts in the operator's local sketch repo** (not
ours to commit unless we worked on them): bench-test sketches,
v3 sketch (the pre-branch-point reference), other accumulated
work. When committing, stage only the files actually touched this
session — leave the rest as the operator's WIP.

---

## Working preferences

See PREFERENCES.md for the full agreement. Key reminders:
- Windows cmd syntax
- Small steps, one question at a time, wait for confirmation
- Code boxes for shell commands; bare URLs on own line in chat
- Oscilloscope approach — instrument, don't guess
- Photos sacred; wrong exposure fixable in post
- Pin-8 must work when CCAPI is down
- Tv+1.5s cadence rule
- Visualisation > Manipulation (Day 10)
- Compare against known-good reference first (Day 12)


---

# WORKFRONTS history (relocated from WORKFRONTS.md)

> These dated session-history blocks (Day 13 -> Day 25) were moved out of
> WORKFRONTS.md on 07 Jun 2026 to keep that file open-work-only. Build
> narrative; superseded statuses are tracked in the WORKFRONTS catalog.

## Day 25 (part 2, 31 May 2026) — BNO motor-power stall: CORRECTION + real fix (Wire2 isolation)

**Supersedes the "Motor-power stall — RESOLVED (Day 25)" block further
down (the 2.2k-pull-up finding). That fix was PREMATURE.**

**What happened:** building the recon-heading capture (soak-v19), the
Mark-wpt 'A' rows came back with a frozen heading (-142.1 to the tenth
across three rotated marks). `/debug/imu` showed `last_poll_ms_ago`
climbing in lockstep with real time (169 s → 185 s), `yaw_raw` frozen —
the SAME stall the Day-25 block claimed resolved. Power-cycle test: BNO
streamed clean with main power OFF, stalled with main power ON. So the
2.2k pull-up swap did NOT hold; the stall was reproduced under motors.

**Real root cause (operator hypothesis, confirmed against Pololu docs):**
NOT conducted power noise — **I²C bus contention from Tic clock-stretching.**
Pololu (0J71/4.6, 0J71/10): the Tic holds SCL low while busy processing
("clock stretching"). On the SHARED Wire bus (BNO + two Tics on D20/D21),
an energised/driving Tic stretches SCL and blocks the BNO's multi-byte
SHTP read mid-stream → the single-ended stateful stream wedges → stall.
Motors off = Tics idle = minimal stretching = BNO fine. This also
re-explains the Day-24 air-gap result correctly: the spare rode through
because it was on a CLEAN bus with no Tic contention — the test proved
"not radiated," but the leap to "conducted power noise" skipped the
documented bus-contention cause.

**Fix — categorical, not marginal: BNO moved to its OWN bus, Wire2
(D8/D9), isolated from the Tics on Wire.** Tic clock-stretching physically
cannot reach the BNO on a separate bus. The pin plan had already reserved
Wire2/D8-D9 for exactly this. 2.2k pull-ups to 3V3 on D8/D9 (mbed applies
none; the Giga core already DEFINES `Wire2` — do NOT declare your own, it
linker-errors "multiple definition of Wire2").

**Validated by measurement, end to end (all Day 25 pt 2):**
1. Spare Giga, BNO on Wire2 + 2.2k: bench sketch streams clean; removing
   pull-ups kills it (confirms externals mandatory on Wire2 too).
2. Main Giga rewired BNO→D8/D9: bench sketch clean, main power OFF and ON.
3. Production soak-v20 (BNO on Wire2, Tics still on Wire, driving):
   `/debug/imu` motors-ON, four reads, `last_poll_ms_ago` 30–96 ms (small,
   not climbing), `yaw_raw` tracking rotation (-164.0 / -133.7 / -159.3 /
   -126.4). Stall does NOT reproduce. **Motor-power stall FIXED.**

**Status now:** #40 BNO motor-power stall = RESOLVED via Wire2 isolation
(NOT pull-ups). Recon-heading capture (soak-v19/v20) now runs against a
non-stalling BNO. Production sketch = soak-v20.

**Doc follow-ups done same session:** GIGA_PIN_PLAN.md → BNO canonical on
Wire2 (D8/D9) with 2.2k; new build-lesson added to PREFERENCES (shared-bus
misbehaviour → check the other device's documented bus behaviour before
blaming electrical noise).

---

Older session detail (days 6–11 workfront narratives) lives in
`WORKFRONTS_old_ver1.md`. This file keeps only open items, plus
one-line stubs for resolved/rejected ones to preserve traceability.

---

## Comms-outage fallback architecture (Day 15 — resolved)

Step 4 of #36d originally said "TABLE walks the table actively
pushing Tv/ISO PUTs at row boundaries." Day-15 discussion
identified this as a logical impossibility — if CCAPI is
unreachable (which is why we're in TABLE), the cart cannot push
Tv/ISO changes to the camera.

Reframed as a layered fallback problem, then narrowed by
operator's risk assessment.

**Risks classified:**
- Camera-side WiFi failure: accepted (Step D handles)
- Cart-side WiFi failure: accepted (rare; pin-8 keeps firing)
- External AP failure: accepted (pin-8 + TABLE keep photos
  delivered; only operator UI capability is lost)

**Architecture as it stands:**

**Production v1 (current, sufficient for now).** External WiFi
(Rosedale / field router) is the working comms path. When it
fails — for any of the three reasons above — pin-8 keeps
photos firing (Fallback 1), Step D detects the outage, and
TABLE mode runs cart-side exposure walk. Camera stays frozen
at flip-time Tv/ISO; photos are over/underexposed during
outage; LRTimelapse fixes drift in post. The full shoot is
delivered. Architecture is robust. Some risk is accepted by
design.

**Production v2 (future improvement, not blocking).** Move
the camera link to wired Ethernet point-to-point. Camera WiFi
disabled, external WiFi never reaches the camera. Cart still
uses external WiFi for operator UI / Excel only. Tracked as
#47. Optionally drops pin-8 in favour of CCAPI HTTP shutter
over the wire (architectural principle #12 would retire).
Camera-as-AP and USB+Pi+EDSDK options are no longer in the
running — wired Ethernet is structurally cleaner.

#36d Step 4 is closed by this framing. v1 already handles the
outage cases acceptably; v2 explores improvements.

---

## Day 24 (part B) update (30 May 2026) — gimbal execution Steps 2 / 3a / 4 + Move built; BNO motor-power stall resolved

Build progression: soak-v13b → v14 (Phase-A ease) → v15 / v15a (3a
anchor + `/debug/imu` gate probe) → v16 (Pan Follow exec) → v17
(preview GP-start tag + previewplan pusher) → v18 (Move exec).
Ry=Cy holds throughout — gimbal track path stays separate from the
(now-unblocked) BNO correction.

**Gimbal execution — what got built this session:**

- **Step 2 — Phase-A ease-onto-curve: BUILT + PROVEN (v14).** Executor
  eases from its actual pose ONTO the live real-time cubic over a pushed
  `acquire_ms` (smoothstep) instead of snapping. Proven on hardware
  (parked y=-73.5, acquire=8000 → smooth ~8 s glide, `[track] acquire
  done -> tracking`). Cart stays dumb (one pushed ms value). `acquire_ms`
  rides on the TrackInterval; absent/0 = legacy snap. Late-start
  self-correction unchanged (target read live each tick).
- **Step 3a — anchor heading-sample instrumentation: DONE + verified
  (v15/v15a).** `PlanSegment` gained an `anchor` flag (optional `a`
  token, tail position, order-independent — append-per-build-lesson-12).
  In an anchor segment the cart samples BNO `true_yaw` + cal byte to
  CartLog `A` events every 500 ms (record-only, Ry=Cy holds).
  `CartLogEntry` gained an `aux` tail column (cal; `value` carries
  true_yaw×10) so old index parsers stay intact. **3a surfaced the BNO
  motor-power stall below.**
- **Step 4 — Pan Follow execution: DONE + hardware-proven (v16).** New
  interval mode `GTM_PANFOLLOW = 'P'`: on entry, ease ONCE from actual
  pose to the goto offset over `acquire_ms` (or `PANFOLLOW_EASE_MS_
  DEFAULT = 3000`), then go SILENT for the window — the executor was
  already silent between intervals, so "go silent → Ronin follows"
  needed no new machinery. Operator hand-rotated the cart → gimbal
  stayed in Pan Follow holding the offset. Confirms the one bare-bench
  unknown: the Ronin reverts to native Pan Follow the instant SDK
  position commands stop. BNO-independent. TrackPlanPush.bas emits 'P'
  rows (mode=P, offy=Δyaw).
- **Preview GP-start / continuation tag + previewplan pusher: DONE,
  dry-run verified (v17 + PlanPush.PushPreviewPlanToCart).** Preview
  buttons PREV/NEXT (not FWD/RWD). Pose tag: GP-start (PREV/NEXT lands
  here) / continuation ("<GP>e", stepped, skipped by GP-level PREV/NEXT).
- **Move execution: BUILT both sides (v18) — cart bench test pending.**
  The assumed "Move cubic" turned out unnecessary: a Move is a single
  ease-in/ease-out slew to a FIXED endpoint = one smoothstep, no cruise,
  no cubic (operator: "handles making an S"). Cart mode `GTM_MOVE = 'M'`:
  ease to absolute endpoint (offY/offP) over acquire_ms, then HOLD the
  endpoint (do NOT go silent — silence would let the permanently-Pan-
  Follow Ronin drift off the mark). 'M' holds, 'P' releases — the one
  difference. No FitCubic, no cubic slot, no new push path. Excel: Move
  is an INTERVAL in TrackPlanPush (not a cubic in PlanPush);
  PlanPush.EvalAstro / IsAstroTarget lifted Private→Public so Move-to-
  astro endpoints compute; added COL_RY=22 + dataCartHeading. Re-import
  BOTH .bas (TrackPlanPush won't compile against old Private signatures).

**Design captured this session (not built):**

- **Pan Follow + LOCK taxonomy.** Six actions split by "is the cart
  commanding the gimbal?": Commanding = Track, Track-yaw, Move, LOCK;
  NOT commanding = Pan Follow; END terminates. LOCK and Pan Follow both
  look static but are OPPOSITE behaviour — Pan Follow = cart-frame fixed
  (cart silent, Ronin follows); LOCK = earth-frame fixed (cart commands,
  counter-rotating as the cart turns to hold a world bearing).
- **LOCK — parked, BNO-dependent for the moving case.** Parked-cart LOCK
  is cheap (a static commanded yaw IS world-fixed when heading doesn't
  change). Moving LOCK needs `commanded_yaw = planned_Ry −
  (cart_heading_change since lock)` → a live heading source: BNO
  preferred; bicycle-model dead-reckoning the known-imperfect blind
  fallback (short holds only, real-world drift test first). Revisit now
  the BNO survives motors.
- **Open handoff question:** at a Pan Follow → Track (or LOCK → Track)
  boundary, should Phase-A ease apply, or is the transition allowed to
  snap? Decide when building.
- **PANO — manual interrupt + Excel-configured geometry. DESIGN AGREED,
  not built. No BNO dep.** Operator fires the pano in the moment (sky
  earns it; can't schedule interesting skies) — pre-configured shape,
  manually fired. Mechanism: pano start suspends the active GP (track
  executor yields, remembers the interval); pano runs; resume re-engages
  via Phase-A ease onto the object's CURRENT position (object moved
  during the pano — reuse Phase-A, no new easing). Geometry Excel-
  computed and pushed as `{count, offsets[]}` (even rule step=span/n,
  outer shots inset half a step); cart array ceiling `PANO_MAX = 12`
  (replaces hardcoded 4). Push-the-array (not span+n) so future non-
  uniform edge-oversampling is an Excel-only change. Build splits into
  (1) cart interrupt/suspend/resume plumbing (resolves the panoTick vs
  trackPlanTick fight), (2) configurable geometry. Either can go first;
  neither BNO-blocked.
- **VISUALIZATION architecture — DESIGN AGREED, not built. No BNO dep.**
  Three separate views, all rendered OFF-CART (Python at the desk):
  (1) cart 2D top-down plan (Excel XY, exists, low-priority polish);
  (2) gimbal PLANNING polar sky plot (matplotlib, PhotoPills-style:
  astro arcs, gimbal points as lines = yaw direction / pitch length,
  PREV/NEXT per GP); (3) gimbal EXECUTION linear cable-budget strip
  (phone beside cart, reassurance not analysis, axis = gimbal-min→450°
  cable budget, marker slides through the night). (2) and (3) are
  DIFFERENT renderers. Architecture for (3): Python renders an SVG
  backdrop at push time → cart stores on SD → serves to clients with a
  live symbol position → client overlays the moving marker (cart stays
  dumb). The SD card is the enabler (no room for a backdrop in Giga RAM).

**#40 BNO085 — motor-power stall LOCALISED (Day 24) then RESOLVED
(Day 25). Full detail in the #40 BNO085 section below.**

- Symptom (Day 24): the BNO SHTP rotation-vector stream went silent
  and did not self-recover (needed power-cycle) whenever main/motor
  power energised; perfect with main off. Measured: `last_poll_ms_ago`
  climbing in lockstep with real time (6647→13812), yaw frozen. Ruled
  out enumeration and GIGA brownout/USB sag (USB present, still died).
- Diagnosis + fix (Day 25): an air-gapped spare GIGA+BNO (same
  proximity, same untwisted 30 cm cable, isolated power) rode through
  motors-energised FLAT → radiated field is NOT sufficient; the agent
  is CONDUCTED via the shared bus / 5V. CAN (differential, robust) and
  Tics (stateless) survive the same environment — only the stateful
  single-ended I²C SHTP stream dies. Tier-1 fix, single change: BNO
  SDA/SCL pull-ups 4.7k → 2.2k (stiffen rising edges over 30 cm).
  **Held under full production load** (soak-v18, motors running):
  `/debug/imu` `last_poll_ms_ago` 23–107 ms, yaw tracking motion, no
  stall. Read plumbing proven: capture → offset → `true_yaw` wrap →
  360° cart turn reproducible (returned within ~4° of origin).
  (cal stayed 0 — plumbing proven, absolute accuracy is a saved-DCD +
  real-world check; scope lines-vs-5V no longer needed unless it
  returns.)
- **3b (fold `gimbal_yaw_correction = (−true_yaw) − expected_cart_
  heading` into earth-frame cubics): STILL BLOCKED — but now ONLY on
  the plan-stream change, not electrical, not cal.** Confirmed by grep
  of soak-v18: `PlanSegment` has 8 fields (…, anchor) with NO
  `expected_cart_heading` and NO frame tag. **Next workfront = add
  `expected_cart_heading` + per-segment earth/chassis frame tag to the
  stream (tail tokens, build-lesson 12), then build 3b.**

**Execution status across Steps 2/3/4 at session close:**
Step 2 ease DONE both sides (hardware-proven v14); 3a DONE (v15);
Step 4 Pan Follow DONE + proven (v16); preview tag + previewplan pusher
DONE (v17); Move DONE both sides (v18, cart bench test pending);
3b unblocked electrically, gated on plan-stream; LOCK parked (BNO moving
case). Leftover: Move-cubic Stage-4 is retired (no cubic needed);
distance-aware Move-t (col AA) is the later refinement.

---

## Day 24 (part A) update (30 May 2026) — soak baseline PASS + gimbal execution engine proven

Two strands this session: (A1) the first #63 soak ran and passed, and
#63 was reframed; (A2) the gimbal execution engine (the "not-ready
half") was built and proven on hardware end-to-end. Ry=Cy holds.

### A1 — Soak baseline + edge instrument + new workfronts

**First soak — close-range baseline: PASS (soak-v7).** WiFi/CCAPI,
RAW-only, cart stationary on bench (Rosedale, cart .1.97, camera .1.99),
2 s cadence. Duration 7,485 s (~2 h 05 m), 2,880 frames.
**Triggered = accepted = on-card = 2,880** (shutter POST 2,880/2,880,
zero fail; card delta = 2,880 RAW). **Heap dead-flat:** mallinfo
uordblks first/min/max/last all 25,288, drift = 0. **No stalls:**
max_gap 10,003 ms (one heartbeat), stalls_gt_30s = 0. RSSI −32 to −49.
status_err_total = 713 — ALL PUT-Tv 503s (0"5 shutter inside the 2 s
window collides with the next PUT), none on the shutter path; benign
cadence artifact, reconciles exactly (3,593 put attempts − 2,880 ok).
**Limit: link was never stressed and the production envelope was not
exercised** (no plan loop, no slews, no CAN load, flat cadence) — a
clean proof of the CCAPI transport+shutter+Tv path, NOT a production
sign-off.

**#63 REFRAMED — duration test → field link-margin / edge-finding
test.** The real soak measures link margin under field conditions
(remote, 2.4 GHz for reach, AX6000 near the van, cart far out with
terrain between). Failure is an expected, acceptable outcome; the
instrument's job is decision support — stand at a candidate cart
position, soak, read whether the link is good enough for a sunset→
sunrise run. Deliverable = an empirically measured edge RSSI per
terrain/aerial/AP arrangement.

**Edge instrument built (soak-v8):** per-row RSSI on every PUT/GET/POST
(not just heartbeats); LINKDOWN/LINKUP rows on WiFi transitions (a gap
bracketed by them = real drop; gap without = code hang); `/soak/summary`
edge lines (`first_fail_rssi` = headline edge, `longest_fail_run`,
`link_drops`, `longest_outage_s`); `/soak/dump?off=&len=` (≤4096) +
`/soak/info` for WiFi read-back of the sealed microSD; heap on heartbeat
rows. **Cart Recon UI link+IMU line** under the voltage line:
`WiFi <rssi> <OK|marginal|WEAK> · IMU <cal n/3 | -->`, colour-banded
(green ≥ −60, amber −60..−72, red < −72); bands a first guess, reset to
measured `first_fail_rssi` later. Fed by `/status` idx 13 (RSSI) + idx
14 (BNO cal) — appended at the tail, existing indices untouched.

**New workfronts raised this session:**
- **#70 Soak run protocol for edge-finding.** Characterise across range
  (walk-out / several positions, not one spot); one-AP vs two-AP
  (cabled, nearer cart) before/after; record `first_fail_rssi` per
  combo. Confirm the loop never wedges on a drop (a TCP connect timeout
  at the edge must not block the loop seconds-per-frame). Not blocking.
- **#71 Firing-hold for manual camera LAN reconnect (Execution UI).**
  The Canon R3 does NOT auto-rejoin the AP after a WiFi drop — recovery
  is a manual menu sequence on the body, and Canon docs forbid operating
  the camera during connection setup. Requirement: an operator-asserted,
  transport-agnostic firing hold that idles EVERY active firing path
  (CCAPI PUT/GET/POST, pin-D7, plan frame pushes) for the reconnect,
  then resumes. In deliberate tension with "always fire" (a short
  operator-chosen gap beats losing the camera for the night). Open:
  manual vs auto-detect; resume manual vs auto-probe; plan interaction.
  Definition-of-done waits on the #63 edge verdict — scaffold now,
  finalise after soak.
- **#72 Cart + gimbal execution feature testing on the assembled Giga
  (in motion, under a plan).** Quality-validation pass — watch the
  features actually move and do the smooth/photogenic thing (distinct
  from #63's transport stress). Folds in **#54** (large-angle slew
  overshoot) at step 8 (gimbal astro drive). Suggested low-to-high
  sequence: single MOVE w/ easing → MOVE→MOVE merge (tr=M) → STOP
  variants (S/D) → short multi-segment plan (E1 S-curve) → ±100 mm nudge
  mid-MOVE → PAUSE/RESUME mid-MOVE → gimbal cubic-eval motion → gimbal
  astro drive (#54 surfaces here). Independent of the transport verdict;
  parallel with the #63 ladder.

**Transport ladder — soak-adjudicated, ship ONE (resolved-architecture
record).** Objective: always fire, minimum cables. Rungs are competing
candidates for one production slot, each kept built as a compile/runtime
option; soak decides; losers archived (not deleted):
(1) WiFi CCAPI over AX6000 (no cables) — preferred, in soak (#63);
(2) Wired HTTP CCAPI (#69) — archived, promoted to soak only if WiFi
fails; (3) Pin-D7 hardware shutter — archived, ships only if BOTH CCAPI
transports fail. **R3 reconnect is manual** (EOS R line; WFT-R10 guide
forbids shutter/controls during connection config) → motivates the #71
hold. Because production may ship CCAPI-only, the hold can't assume a
D7 path underneath — it's a true firing gap in a CCAPI-only build, hence
transport-agnostic (idle whatever is live).

### A2 — Gimbal execution engine: built + proven on hardware

Day-24 part A traced the gimbal half and found the **data plumbing
built, the execution engine not** — then built the engine. Order as it
landed:

- **Gimbal-half state map.** Confirmed EXISTS: cubic fit+push
  (AstroPush.PushTrackPathsToCart via FitCubic → `/settings/trackpath`),
  cubic store+eval (`/debug/trackeval`), interval store
  (`/settings/trackplan`, modes F/Y). MISSING (then): runtime executor,
  gimbal slew primitive, pan-follow exec, Excel trackplan pusher,
  Move push.
- **Cart plan push — proven end-to-end.** New Excel `CartPlanPush.bas`
  (LEFT-zone Cart Plan → `/plan/load`; DRIVE→`m,…,d`, STOP→`s,…,t|o`).
  New cart `/plan/advance` (soak-v9e) releases END_OPERATOR segments.
  Test: WP01 STOP(op) → WP02 DRIVE 500 mm @5 m/hr → WP03 STOP(op) ran
  full path (282,500 steps = 500 mm × 565 steps/mm calibration
  confirmed).
- **#5a track executor — built + PROVEN (soak-v10b).** The keystone:
  `trackPlanTick()` at 5 Hz walks `track_plan[]`, finds the active
  interval at shoot-time, evaluates the object's cubic
  (`trackEvalAt()`), drives the gimbal via `setPosControl()`. `/track/
  start` arms (re-stamps anchor = shoot t=0), `/track/stop` disarms
  (holds last pose). Hardware: tracked a 0.1°/s sun cubic, slow smooth
  creep. **Arduino auto-prototype trap** (issue #2696/#1269): functions
  taking/returning the custom `TrackPath*` get a prototype hoisted above
  the struct → "does not name a type"; fix = explicit forward
  declarations after the struct. (Build lesson.)
- **Excel trackplan pusher + load-disarm safety (soak-v13a).** New
  `TrackPlanPush.bas` pushes Track/Track-yaw intervals to
  `/settings/trackplan` (target→obj char S/M/W; F=offy/offp, Y=offy/
  fixed pitch; idx 0 resets; TRACK_PLAN_MAX=10). **Load-disarm fix
  (found on hardware):** loading a plan must NEVER cause motion — a push
  onto a still-armed executor + a stale cubic swung the gimbal
  10°→100°. Now `/settings/trackplan?idx=0` AND `/settings/trackpath?
  seg=0` set `track_exec_on=false`; motion resumes only on explicit
  `/track/start`. (Reinforces no-camera-during-first-motion-tests.)
- **Real-time anchor / Model B — built + proven (soak-v12a → v13).**
  Astro cubics keyed to REAL time; cart maps via a learned offset, so a
  late start self-corrects (joins the arc where the sun ACTUALLY is) —
  chosen over Model A (repinned cubics, stale on late start).
  `/settings/realtime?ms=<epoch_ms>` sets `rt_offset_ms`; cubic eval
  uses real time when anchor set AND cubic has rt0. **BUG fixed (v12a):**
  13-digit epoch-ms overflows 32-bit long — use `strtoll` + `%lld`, not
  `atoll`/`(unsigned long)`. Hardware: rt0 100 s in the past → gimbal
  joined the arc at the correct current point.
- **AstroPush rt0 + EPOCH CONVENTION LOCKED (soak-v13b).** seg=0 push
  appends `&rt0=<epoch_ms>` via `DateToEpochMs(d)` = (serial−25569)×
  86400×1000. **LOCKED RULE (critical, future-Claude):** rt0 AND the
  `/settings/realtime` anchor the Execution UI sends MUST both use
  `DateToEpochMs(Now())` — LOCAL serial × day-ms, i.e. local-time-as-UTC,
  NOT a true UTC epoch. The cart only subtracts (real_now − rt0), so a
  constant offset cancels ONLY if both sides match; mixing true-UTC with
  local-as-UTC would be ~9.5 h off (Adelaide) and point wildly wrong.
  Bench tests that fed true-UTC ms are NOT representative — re-test the
  anchor with local-as-UTC. Verified end-to-end on real shoot data
  (rt0 = full 13-digit epoch stored for sun+mw; `/debug/trackeval`
  sensible WNW sunset bearing).
- **Preview / step mode — built + proven (soak-v11b, 12°/s).** Operator
  steps through GP poses on demand (forward AND back) to verify start
  geometry and MANAGE CABLES (slew to half-tangle, dress routing,
  reverse, unwind). Cart stays dumb: Excel computes each GP's preview
  pose and pushes a flat list (`/settings/previewplan`); cart slews to
  pose[idx] on `/preview/step|goto`. 12°/s is the keeper (small
  motion-profile overshoot at landings — same family as #54, harmless
  for preview).
- **Phase-A acquire — design resolved here, built in part B (v14).** The
  Model-B test snapped onto the curve; every gimbal move must ease.
  Resolution: the cart eases from its current pose ONTO the real-time
  cubic it already holds (no astronomy on the cart; late-start recalc
  automatic because the cubic is real-time-keyed).

**#40 BNO085 (part A findings — superseded by the consolidated doc).**
Part A nailed the correction loop + read model + calibration method;
no correction wired (Ry=Cy). Method PROVEN: off-cart figure-8 → cal 3 →
`/savecal` → DCD persists across reboot; production boots on stored DCD;
the cal BYTE ≠ stored calibration (reads 0–1 on a flat-moving cart even
with valid DCD, so can't gate trust at boot). Read model = anticipatory
STATIONARY "duck off" (park, settle, 1–2 s averaged window), not the old
500/400 mm crawl. Cal rule ≥2 use / ≤1 keep-previous. **All folded into
the #40 BNO085 section below — work from that.**

---

## Day 23 (part 2) update (29 May 2026) — soak instrument built

- **#63 soak instrument — BUILT + VALIDATED; run pending.** On-cart
  harness proven end-to-end (all 200s; Tv alternating 0"5/0"4; card
  images match). microSD CSV logger on the W5500 shield (CS=D4) behind
  `#define SOAK_LOG`; per-CCAPI-call rows + mode-flip + RSSI heartbeat;
  non-fatal SD; auto-incrementing SOAK_NNN.CSV. Soak MODE
  (`/soak/start?ms=N` / `/soak/stop`): per frame PUT Tv (alternating) +
  GET every 3rd + CCAPI photo, no TABLE-fallback so dropouts stay
  visible. Read-back via `/soak/info` + `/soak/tail`.
- **Servo D4 → D5 — DONE.** Frees D4 for the shield's hard-wired SD CS;
  D5 PWM-valid (Giga PWM 2–13). Wire physically moved, re-tested good.
- **Tv-value + busy-collision lessons (folded into soak):** Canon Tv
  must use seconds notation `0"5`/`0"4` (not `0.5`), via `ccapiPutTv`;
  PUT a setting only on an idle camera (not right after a shutter press)
  or it 503s.
- **Gotcha — silent failed Giga upload.** Compile OK but board keeps the
  old binary (new handlers missing, old ones work). Boot `[build] vN`
  marker added to detect it — bump each edit. (In PREFERENCES build
  lessons.)
- Camera moved to van AX6000 addressing for the soak: cart .20.97,
  camera .20.99 (wired .20.98 reserved). WiFi/wired-CCAPI do not
  coexist — transport chosen after testing.

---

## Day 23 (part 1) update (29 May 2026) — Giga recommissioning

Hardware bring-up. **Cart recommissioned on the Giga R1 — all existing
capability back online, verified running together for the first time.**
Day 22 had proven CAN and the W5500 each in isolation (STUB_CART on, one
at a time); Day 23 brought the whole stack up together (CAN gimbal +
Tic-I²C + steering servo + WiFi/Excel/UI + D7 shutter), low-to-high, no
faults. Scope was existing capability only; BNO (#40) and wired Ethernet
(#69) full integration were separate next-work.

**Recommissioning order (each verified before the next):** (1) CAN quick
repeat — bidirectional confirmed; (2) I²C scan — exactly 14, 15, 0x4A,
external 4.7 kΩ pull-ups good; (3) D7 shutter — image on card;
(4) STUB_CART removed, clean un-stubbed boot, no I²C hang; (5) servo
ramp; (6) Tic drive full motion path.

**Workfront status changes:**
- **STUB_CART removal — DONE.** Tic/servo init live.
- **#47 Giga migration — recommissioning of existing capability
  COMPLETE.** Steps 1–5 + the Step-7 v2 sketch validated running
  together on the assembled cart for the first time; Step 6 (subsystem
  coexistence) effectively satisfied. Remaining gate was #63 soak.
  Real-gimbal validation done in substance (CAN drives the RS4 Pro
  bidirectionally).
- **#40 BNO085 — bench-validated on Giga, build still open (then).**
  Giga-safe polled bench sketch (no setClock, no INT/RST, Wire D20/D21):
  connected, rotation vector @10 Hz, figure-8 → acc 0→3, true_yaw offset
  path works. Heading vs iPhone: magnitude ±0.5°; **sign opposite** — a
  40° CW rotation read true_yaw −40 (BNO CW = negative, compass CW =
  positive) → **negate BNO yaw when folding into the gimbal correction.**
  (Superseded by the #40 BNO085 section below.)
- **#68 D9 shutter-readback — DONE.** Stripped; D7 200 ms pulse timing
  preserved exactly; D9 unwired/free.
- **#69 W5500 wired Ethernet — INTEGRATED + proven in production
  sketch.** Compile-time `STUB_WIRED_ETHERNET` switch (DEFINED=WiFi
  CCAPI .1.99 / UNDEFINED=wired CCAPI .20.99; WiFi/UI run in both).
  `ccapiRequest()` switches WiFiClient↔EthernetClient. Both builds
  compile (WiFi 19%, wired 20% +15 KB). Wired CCAPI proven
  (`/exposure/init` ok, connect 0–1 ms). `#define` not runtime
  (production ships one transport; soak each, then pick). Remaining:
  #63 soak of each build + final WiFi-vs-wired decision.
- **AR3277 WiFi aerial fitted** — RSSI −67/−68 (bare) → **−31 dBm**;
  supersedes earlier weak-RSSI flags.
- **D7 shutter — first live frame on the assembled Giga.** Verifies the
  Day-18 D8→D7 assignment, not a new change.

**Note — dead stop (btn12) absent from Cart Recon UI:** intentional
(Day-16 v2 spec); de-energise covers "stop now" for recon; handler still
fires by URL. No workfront raised.

---
## Day 17 update (added 23 May 2026)

Diagnostic + build session. **Plan execution fully validated end-to-end
across all designed segment types and stop styles.** Five bugs found
and fixed via instrumentation; full diagnosis narrative in PROJECT_STATE
Day-17 entry.

**Headline.** All test banks green. The cart now executes any authored
plan correctly:

- MOVE segments at any speed, distance-ended, with steering
- MOVE-to-MOVE transitions (tr=M smooth merge)
- STOP segments (decel, emergency-halt, or 6-min decay) with operator-
  authored hold duration counting from genuine rest
- Operator-ended STOP segments
- `/plan/stop` mid-segment (clean abort)
- `/btn11` and `/btn12` mid-plan (stop cart without aborting plan)
- `/plan/nudge ±100mm` extending / shrinking / past-zero

**Bugs fixed (chronological):**

1. **Bogus rear-Tic delta negation** in `planTick`, `planStatusCSV`,
   `/plan/nudge`. Three `delta = -delta;` lines, justified by a stale
   "rear Tic wired physically reversed" comment, made segment-complete
   fire on the wrong sign. Forward MOVE segments would never complete.
   Inserted by an uncommitted edit from a prior Claude session that
   crashed before testing. Removed; verified empirically with
   `/debug/tic` that both Tics count positive on cart-forward.
2. **I²C "cliff"** — `planTick` was reading `ticRear.getCurrentPosition()`
   every main-loop iteration. Sustained high-rate I²C polling caused
   both Tics to simultaneously NACK on the bus (Wire err=2) after a
   variable run time (7s / 17s / 128s observed). Once cliffed, Tic
   comms dead for the rest of run; cart kept moving on last commanded
   velocity. Throttled `planTick` to 100ms cadence; cliff did not
   recur. Root cause not characterised — workfront #52.
3. **STOP-segment duration timer counted from segment entry.** A 5s
   STOP after 30 m/hr cruise actually held only ~1.5s at rest because
   the Tic STOP_DECEL ramp ate 3.5s of the window. Added an "at-rest
   gate" in `planTick` END_DURATION polling both Tic velocities every
   250ms; counts duration only from the moment both reach 0.
4. **Stop-style dispatcher (TR_S / TR_E / TR_D) pointless.** Each
   stop case did `cartStop()` then immediately
   `cartSetSpeed(speed_mhr)` — Tic accepted the latest target and
   ignored the first. No actual stop happened. Rewrote dispatcher
   with corrected M/S/E/D semantics: M for MOVE-to-MOVE, S/E/D for
   STOP segments. STOP variants only initiate deceleration; the
   at-rest gate handles the duration counting. All three converge
   to "wait at 0 then count" — they differ only in HOW the cart
   reaches 0.
5. **Decay-loop unsigned-subtraction underflow.** When
   `cartStartDecay()` is called from `planTick` (which runs at the
   top of `cartLoop`), `cart_decay_start` is set to a `millis()`
   later than `now` captured at the top of cartLoop. The next
   `elapsed = now - cart_decay_start` underflows, fires the
   decay-complete branch, calls `cartStop()` on the same iteration.
   Result: decay-style stop instantly turned into emergency-style
   stop. Fixed by guarding `elapsed` against negative-then-wrapped
   values.

**Authoring vocabulary, post-Day-17 (canonical):**

| Tag | Used on | What it does |
|---|---|---|
| **M** (merge) | MOVE | Slam target speed; Tic accel/decel handles ramp. Default for MOVE. |
| **S** (decel stop) | STOP | `cartSetSpeed(0)`; Tic STOP_DECEL ramps to rest (~5s from 30 m/hr). Then hold for `duration_ms`. Default for STOP. |
| **E** (emergency) | STOP | `cartDeadStop()`; Tic haltAndHold for instant lock (~30ms). Then hold. |
| **D** (decay) | STOP | `cartStartDecay()`; linear ramp from current speed to 0 over `cart_decay_ms` (6 min production). Then hold. |

Authoring format unchanged: `s,VAL,steer,speed,end[,tr]` where the
optional 6th field is the transition tag.

**New endpoints:**
- `/debug/decaytime` and `/debug/decaytime?ms=N` — get/set the global
  `cart_decay_ms` (default 360000 / 6 min, clamped 1s–10min)

**New globals (kept in production):**
- `cart_decay_ms` (replaces `const CART_DECAY_MS`)
- `plantick_dist_last_ms` (100ms read throttle)
- At-rest gate state in `planTick` END_DURATION (per-segment statics)

**Diagnostic instrumentation removed at end of session:**
- PTICK 500ms probe in `planTick` END_DIST
- PROBE 100ms sampler in `cartLoop` (post-stop)
- DUR elapsed-since-rest probe
- TR_DECAY pre/post-startDecay diagnostic prints
- `stop_probe_*`, `plantick_probe_last_ms` globals

Retained as production-grade defensive checks:
- `getLastError()` after Tic position read in `planTick`, logs only
  on non-zero error code — surfaces a cliff event immediately without
  per-tick noise

**Workfront status changes:**
- **#5a Segment dispatcher** — DONE. M for MOVE, S/E/D for STOP all
  verified end-to-end.
- **#5a-related: ±100mm nudge** — DONE. `/plan/nudge?d=±N` working,
  with past-zero segment-complete fallthrough.
- **#48 (was bus fault on shutter)** — unrelated to Day-17 bugs,
  not revisited.
- **NEW #51 Remove Day-17 diagnostics** — DONE this session.
- **NEW #52 I²C cliff** — partially resolved second-session.
  Original avoidance (100ms throttle on planTick) extended cliff
  onset from ~7s to ~3min but did not eliminate it; 1 Hz polling
  pushed cliff out to ~11min but still hit. Throttling alone never
  enough. Per Pololu docs (0J71/4.6): cause class is weak pull-ups
  + long wires + standard clock. Two interventions applied:
  (1) Architectural — MOVE segment completion is now time-based
  open-loop. Zero Tic reads during a MOVE segment. Cliff cause
  removed for the long-running case. STOP at-rest gate still polls
  velocity at 250ms but only during the bounded ~5s decel window
  (~20 reads per STOP, well below threshold).
  (2) Defensive — `Wire.setClock(50000)` added in setup (Pololu
  recommendation for marginal pull-ups).
  **Still open:** hardware fix (external 10 kΩ pull-ups on SDA/SCL
  per Pololu) — flagged as future work, no urgency now that the
  problem is sidestepped.
- **NEW #53 Calibration mismatch** — `CART_SPEED_SCALE = 58` (m/hr
  → Tic velocity) and `565 steps/mm` distance calibration are
  internally inconsistent by ~10%. Empirically chosen constants.
  Not a practical problem at hyperlapse pixel tolerances. Could be
  reconciled by remeasuring on a known-distance track.
- **NEW #54 Gimbal slew overshoot** (Day 17, second session). Observed
  during showastro tests: large-angle slews (e.g. home → 120° pan)
  with default `time_for_action = 0x14` (2s) physically overshoot
  target then correct. The DJI motor controller over-tunes for the
  load when forced to move fast. Fix options:
  (a) bump time_for_action to a slower fixed value (e.g. 0x40 = 6.4s)
  (b) compute slew time from angular distance like panoIssueSlew
      already does (line 2206 of sketch, `dur_ms = dmax / slew_dps × 1000`)
  Option (b) is consistent with existing code and the more durable
  fix. Apply to showastro / showastrooffset / /move endpoints.
  **Status (Day 24):** folded into #72 step 8 (gimbal astro drive) as
  the place it gets exercised and fixed — no longer "deferred, not
  exercised," now "to be exercised under #72." Stays its own numbered
  item.

**Build lessons added to PREFERENCES (Day 17):**
- A prior crashed Claude session can leave uncommitted edits in the
  working tree. `git diff` against the latest commit before treating
  local sketch as authoritative.
- A code comment that explains a counterintuitive behaviour is
  high-risk signal, not high-trust signal. Verify empirically before
  reasoning from it.
- I²C cliffs are quiet — no exception, no watchdog. Standardise
  `getLastError()` checks for any code touching Tic comms.
- `millis()` captured at the top of a cartLoop iteration is stale by
  the time inner code completes. Sub-blocks may set their own
  timestamps later in the same iteration; guard subtraction.
- A "stop" command followed by an immediate "set speed" is identical
  to "set speed" alone — the Tic accepts the latest target. To
  actually stop and hold, there must be an in-between gate that
  waits for rest.
- **If the slave is reliable in doing what you commanded, don't keep
  asking what it's doing.** The cliff symptom was caused by polling
  the Tic for its position 10× per second — asking something the Tic
  already knows and will execute faithfully. Replacing the poll with
  a time-based estimate (commanded velocity × elapsed time) was
  enough to remove the cliff cause entirely. Bigger lesson: when a
  measurement-based feedback loop hits a hardware-bus problem, first
  ask whether the measurement is necessary at all.
- **Position-poll != real-world feedback.** Asking the Tic where the
  cart is doesn't measure the cart — it measures the Tic's internal
  step counter, which equals reality only when nothing slips. Open-
  loop estimation makes the same assumption. No accuracy is lost by
  removing the poll.

---

## Day 18 update (added 24 May 2026)

Giga capability validation (Steps 1, 2, 4, 5 of GIGA_MIGRATION_STRATEGY)
PLUS Step 7 v2 sketch port complete. Step 3 (CAN) paused on cooked
transceiver. Sketch went from 0 → 5667 lines in DJI_Ronin_Giga_v2.ino,
section-by-section verbatim port from v1prod with Giga deltas applied.

**Capability tests passed (Day 18 first half):**
- **Step 1** Blink + Serial on Giga (COM12, 115200, LED + Serial.println).
- **Step 2** WiFi on Rosedale at 192.168.1.116 after one-time
  WiFiFirmwareUpdater run.
- **Step 4** I²C Tic 14+15 at default speed on Wire (D20/D21) with
  external 4.7 kΩ pull-ups. Pololu Tic library compiles + runs
  unchanged.
- **Step 5** CCAPI alive check + shutter trigger. Required two fixes
  vs v1prod (see workfront #61 below): explicit `\r\n` on outbound
  headers + Wire pin selection.
- **Step 5b** Full CCAPI dynamic-range validation. Tv GET (522 bytes,
  current `0\"3`, 60 abilities), ISO GET (253 bytes), liveview start,
  luminance flipdetail. 5162-byte response parsed via FF 00 01 +
  size:4 BE + JSON + FF FF framing. Mean luminance 144→247 (bright)
  →16 (dark). Full headroom confirmed; 8 KB LUM_RESP_BUF_SIZE on
  Giga handles the live histogram cleanly.

**Step 3 paused.** SN65HVD230 transceiver killed by reversed
3.3V/GND wiring. CAN-only test sketch (DJI_Giga_Step3_CAN.ino)
ready to flash once new transceiver arrives (~5 days).

**Step 7 sketch port (Day 18 second half) — DJI_Ronin_Giga_v2.ino.**

Five open design questions resolved up-front via GIGA_DESIGN.md:

1. **IP addressing during parallel.** Giga 192.168.1.95 on Rosedale
   (DHCP-reserved by MAC). Uno stays on .97 until retirement.
   Excel `dataArduinoIP` flips at cutover.
2. **UI vs camera traffic.** Operator UI + Excel polling on WiFi
   STA port 80. W5500 wired Ethernet (when arrives) for CCAPI only.
3. **Shutter pin.** Pin-8 → D7 on Giga. 200ms HIGH pulse discipline
   verbatim. Sacred; fires on shutter_mode==3 regardless of CCAPI.
4. **Buffer sizes.** CartLog 64→128, GimbalLog 24→128. Operator's
   20-50m recon × ~50 events leaves comfortable headroom.
5. **String allocation.** snprintf for hot paths (/status,
   /heartbeat, /cameramsg); String OK for cold paths.

Port structure: 8 sections, 5667 lines total. Compiles + runs with
STUB_CAN defined. All 57 v1prod endpoints ported. Full 3-screen
browser UI verbatim. Path ordering verified for every startsWith
chain (showastrooffset before showastro, movewatchdump before
movewatch, /shutter/* before /shutter, /cartlog/clear before
/cartlog, etc.).

Section breakdown with Giga deltas:
- §1 (~370): WiFi.h not WiFiS3.h; STUB_CAN/BNO/W5500 stubs;
  LUM_HTTP_TIMEOUT_MS 10000→2000; buffer 4096→8192.
- §2 (~510): Appendix A formula plumbing — no Giga changes.
- §3 (~460): Buffer sizes bumped per resolved Q4 above.
- §4 (~500): drainCANRx + sendFrame wrapped in `#ifndef STUB_CAN`.
  All commands callable; frames built and silently dropped at the
  sendFrame stub. Pano state machine + movewatch sampler.
- §5 (~655): ccapiRequest with `\r\n` on outbound headers (Q1
  resolved via build lesson #1). Binary-frame luminance parse.
- §6 (~935): Plan executor with #52 time-based completion, at-rest
  gate, pano helpers, pin-D7 backupShutter.
- §7 (~200): setup + loop. `Wire.setClock` REMOVED (blocks Giga
  per Day-18 finding). CAN.begin wrapped. **delay(1) at bottom of
  loop()** per discipline #2.
- §8 (~1860): handleHttpRequest body split 8a-8h:
  - 8a skeleton + status/heartbeat/cameramsg/interval
  - 8b move/home/gimbal pano/shutter/btn1-22
  - 8c exposure/* + settings/astropos/trackpath/trackplan
  - 8d cartlog/gimballog (+ /clear, /push variants)
  - 8e plan/load/start/stop/status/nudge
  - 8f gimbal/showastro/snapvar/showastrooffset
  - 8g 17 debug endpoints (4 early-return + 13 chain)
  - 8h browser UI catch-all (3 screens, all SVG icons, polling JS)

**Workfront state changes:**

- **#47 (Giga R1 migration) — Step 7 port complete; recommissioning of
  existing capability COMPLETE (Day 23).** Whole stack (CAN + Tic-I²C +
  servo + WiFi/UI + D7) validated running together on the assembled
  cart; Step 6 coexistence effectively satisfied; real-gimbal CAN
  validation done in substance. Soak baseline passed (Day 24, soak-v7,
  close-range). Remaining gate is the field/longer-envelope soak (#63).
- **NEW #60 Step 3 transceiver hardware** — bench setup blocked by
  cooked SN65HVD230. New transceiver in transit (~5 days). DJI_Giga_
  Step3_CAN.ino sketch ready to flash on arrival. Compiles cleanly;
  only hardware blocks the test.
- **NEW #61 v2 build discipline (mbed-os failure modes)** — design
  doc. Seven risks identified from v1prod patterns that may break
  on Giga: long blocking calls, String allocation in hot paths,
  ISR/network collision, no-yield loops, PROGMEM no-op, millis
  rollover (already handled), no EEPROM. Six defensive disciplines
  applied during Step 7 port: bounded timeouts ≤2s, delay(1)
  bottom-of-loop, snprintf for hot paths, CAN RX in ring buffer
  never network code, document F() no-op, multi-hour soak test
  before declaring done. Most folded into the sketch; multi-hour
  soak test still pending (see #63).
- **NEW #62 Excel Camera.bas dead-code cleanup** — design doc.
  Cart firmware has owned the per-photo exposure walk since #36b
  (Day 12). Excel's Camera.bas luminance pipeline + per-photo CCAPI
  walk is vestigial. Low risk, not blocking. Defer to Giga Excel
  port pass when every HTTP endpoint is being repointed anyway.
- **#63 Multi-hour soak — FIRST RUN COMPLETE, PASS (close-range
  baseline, Day 24); REFRAMED to field link-margin / edge-finding.**
  Baseline (soak-v7) proved the CCAPI transport+shutter+Tv path clean
  (2,880/2,880, heap drift 0, no stalls) but the link was unstressed and
  the production envelope (plan loop, slews, CAN load) was not
  exercised. Now primarily a field instrument: stand at a candidate cart
  position, soak, read whether the link holds a sunset→sunrise run;
  deliverable = measured edge RSSI per terrain/aerial/AP combo (edge
  instrument = soak-v8). Open: longer envelopes (4 h, 12 h — duration-
  dependent fragmentation invisible at 2 h); transport matrix (WiFi done
  at 2 h, wired #69 build un-soaked); production envelope still un-soaked;
  PUT-cadence cleanup of the 713 cosmetic 503s. See #70 for the run
  protocol. (Original framing — "close-out test for #61, blocks on flash
  + smoke test" — is superseded.)
- **NEW #64 Phase-time terminology cleanup.**
  `dataPhase2aStart` / `2bStart` / `3Start` / `4aStart` / `4bStart`
  / `5Start` are jargon from a prior session — not real astronomical
  terms. They approximate real events (golden hour, civil dusk,
  nautical dusk, astronomical dawn, civil dawn, sunrise) but the
  offsets drift seasonally and don't match the standard
  astrophotography vocabulary. Astro.bas can compute the real
  events directly via `FindSunCrossing` at the appropriate
  altitudes (-6° civil, -12° nautical, -18° astronomical). Replace
  named ranges with real-event names, retire `CalculatePhaseTimes`.
  Defer to Giga Excel port pass (same window as #62) — every
  consumer of `dataPhaseXStart` will be reviewed anyway. Not
  blocking.
- **NEW #65 mbed WiFi accept() semantics — sketch fix landed.**
  Day-18 smoke test exposed that Giga's mbed WiFi
  `wifiServer.available()` is semantically `accept()` — returns
  the client object as soon as the TCP three-way handshake
  completes, BEFORE the HTTP request body arrives. v1prod's
  Uno-WiFiS3 pattern (single-shot `if (client.available())`)
  saw `req_len=0` always, fell through every if/else, landed in
  the UI catch-all. Root-caused via ArduinoCore-mbed issue #766
  (JAndrassy: "available() here works like Ethernet library's
  accept()"). Fix: replaced single check with a
  `while (client.connected()) { if (client.available()) ... else
  delay(1); }` bounded at 2 seconds. Confirmed working: /status,
  /heartbeat, /settings/astropos, /exposure/load all round-trip
  cleanly. Documented as Day-18 build lesson #5. CLOSED.
- **NEW #66 Empty-connection diagnostic cost.** Side-effect of
  the #65 fix: any TCP socket that lands but never sends a
  request (browser speculative pre-connect, port scan, stale
  Excel WinHttp socket) costs ~3000ms wall-clock (2s wait + 1s
  client.stop tear-down). Cosmetic only — real Excel polling
  is unaffected and pin-D7 cadence is still guaranteed by the
  sacred-pin discipline. Long-term: investigate non-blocking
  accept + pending-client state machine (per ArduinoCore-mbed
  #76 / #281 idiom — `sock->set_blocking(false)` + persistent
  client state). Not blocking #63 soak test; revisit if
  empty-connection rate becomes significant.

**Build lessons from Day 18 (also in PREFERENCES):**

1. **Giga mbed WiFi needs `\r\n` on outbound HTTP headers.** Canon
   CCAPI rejects bare-LF with 400 + empty body. WiFiS3 was lenient;
   mbed is strict per RFC. Use `print("...\r\n")` not `println`
   for headers.
2. **Giga has three I²C buses.** Pins near AREF are Wire1
   (silkscreen reads SDA1/SCL1); default Wire is on D20/D21 at the
   other end of the digital header. Wire1 instance vs Wire: read
   the pin diagram.
3. **External pull-ups on Wire are MANDATORY.** Giga doesn't apply
   internal pull-ups for Wire. 4.7 kΩ to 3V3 — confirmed working.
4. **`Wire.setClock()` blocks on Giga.** Don't call it. Default
   100 kHz works fine with proper pull-ups.
5. **mbed `wifiServer.available()` is `accept()`, not data-ready.**
   Returns the client object as soon as TCP handshake completes,
   BEFORE the HTTP request body arrives. v1prod's single-shot
   `if (client.available())` check saw `req_len=0` always.
   Canonical mbed pattern is a `while (client.connected())` loop
   that waits for `client.available()` with `delay(1)` between
   checks, bounded at 2 seconds. v1prod's Uno-WiFiS3 pattern is
   NOT portable to mbed. Documented in #65.

Sketch line count after port: 5667 (vs v1prod 6275). Denser, same
features. All v1prod functionality reachable; CAN/BNO/W5500 paths
covered by stubs until hardware arrives.

---



Below is a record of what was tested and verified. Future regression
tests should re-run these.

### Test bank A — segment end conditions

A1 (MOVE with END_DURATION) skipped — parser puts MOVE val into
dist_mm, not duration_ms. Combination not designed for. The valid
end conditions per type are MOVE→END_DIST, STOP→END_DURATION or
END_OPERATOR.

**A2 (STOP with END_DURATION).** ✓ Verified.
- Plan: `n=4&s1=m,200,0,20,d&s2=s,5000,0,0,t&s3=m,200,0,20,d&s4=s,0,0,0,o`
- Result: SEG 2 entered at 20 m/hr cruise, at-rest reached t+3545ms,
  5s hold counted from rest, SEG 3 entered, cart re-accelerated to
  20 m/hr cleanly. Total SEG 2 wall-clock: ~8.5s for "5-second STOP".

**A3 (STOP with END_OPERATOR).** ✓ Verified as part of every other
test (the trailing `s,0,0,0,o` segment).

### Test bank B — STOP segment transition tags

5-segment plan: MOVE 250mm @ 30 m/hr → STOP 5s (variant) → MOVE
250mm @ 30 m/hr → STOP 5s (variant) → STOP operator-end.

**B-S (default decel stop).** ✓ At-rest at t+5408ms / t+5306ms.
Cart re-accelerated from full rest, drove SEG 3 cleanly. Re-stopped
in SEG 4.

**B-E (emergency stop, cartDeadStop).** ✓ At-rest at t+31ms / t+32ms.
Cart re-accelerated from dead halt without issue.

**B-D (decay stop).** ✓ With `cart_decay_ms=60000` (1 min) for
test convenience. Cart maintained 30 m/hr at SEG 2 entry, then
linearly decayed over 60s to 0. At-rest at t+60144ms. 5s hold then
SEG 2 complete. Production default 360000ms (6 min) restored at
end of session.

### Test bank C — stop primitives mid-plan

**C1 (`/plan/stop`).** ✓ Abort fires planAbort → cartStop. Cart
decelerates via Tic STOP_DECEL ramp. Plan state → IDLE.

**C2 (`/btn11` cartStop mid-MOVE).** ✓ Cart decelerates and stops
(~5.4s). Plan state stays RUNNING — segment-complete via END_DIST
will not fire because cart isn't moving. Operator must follow with
`/plan/stop` to clean up. UX implication recorded for Execution
screen design.

**C3 (`/btn12` cartDeadStop mid-MOVE).** ✓ Sharp halt within ~50ms.
Plan stays RUNNING (same as C2). Cart locked at last position
(Tic haltAndHold prevents drift).

### Test bank D — `/plan/nudge`

**D1 (`+100mm`).** ✓ Plan: `m,250,0,30,d`. During cruise, nudged
+100mm at delta=68499. `[Plan] NUDGE seg=1 delta_mm=100
new_dist_mm=350 steps=70299/197750`. Target updated to 197750,
cart continued, SEG 1 completed at delta=197824.

**D2 (`-100mm` with plenty left).** ✓ Plan: `m,250,0,30,d`.
Nudged -100mm at delta=50099. Target shrank to 84750. SEG 1
completed at delta≥84750. Cart drove ~150mm total.

**D3 (`-100mm` past zero).** ✓ Plan: `m,250,0,30,d`. Waited until
delta=106849 (~189mm covered). Nudged -100mm. Handler logged:
`NUDGE past zero — segment complete`. SEG 2 entered immediately.

**D4 (nudge on STOP segment).** ✓ Plan with STOP+duration. Nudge
request returned `ERROR: nudge only valid mid-MOVE`. Rejected
cleanly.

### Test bank E — multi-segment with steering

**E1 (S-curve plan).** ✓ Plan: `m,300,-5,20,d` → `m,300,5,20,d`
→ STOP. SEG 1 with steer=-5, SEG 2 with steer=+5, all completed.
Steering ramps at 1°/sec (existing behaviour) so the -5 → +5
transition takes ~10s.

---

## Day 16 update (added 23 May 2026)

Build session — three-screen UI v2 foundation delivered. Two screens
real (Cart Recon, Gimbal Recon), one placeholder (Execution). See
PROJECT_STATE Day-16 entry for full detail.

**Headline:** UI_DESIGN_v2.md spec moved from design to running
firmware. Cart Recon operator-verified end-to-end. Gimbal Recon UI
fully laid out but captured rows are client-side only — production
gap closed by new follow-up #49.

**Sketch additions (v1prod):**
- Server-side `?screen=cart|gimbal|exec` routing in the catch-all
  HTML `else` block. Shared header (logo row + 4-tab bar) on every
  screen. Day palette baked in CSS.
- New state vars: `cart_motor_state` (1B), `cart_waypoint_count` (4B),
  `cart_last_waypoint_steps` (4B). +9 bytes SRAM globals.
- Hooks added: cartStop/cartDeadStop/cartSetSpeed/cartEnergise/
  cartDeenergise all set `cart_motor_state` correctly. Decay completion
  already calls cartStop() so covered.
- New `'W'` event in CartLog (value = waypoint number).
- New btn22 (Mark wpt) handler with confirm.
- `/status` extended: v[10] motor state (0=DE-E, 1=STOP, 2=ENRG),
  v[11] waypoint count, v[12] mm-since-last-waypoint.
- Reset paths: btn19 log-start, btn21 Clear logs, /cartlog/clear all
  zero the waypoint counter and reseat the rear_steps anchor.

**New follow-ups:**
- **#49** Gimbal Recon rich-row persistence (cart-side struct
  extension + /gimballog/push endpoint). Smallest path to make
  Gimbal Recon production-usable.
- **#50** Excel astro position push to cart. Unlocks Show astro
  and Snap var on Gimbal Recon.

**JS escape-quote build lesson** added to PREFERENCES. Broken
`\\'s` in a stub-alert string killed the entire script (live readout
stuck on dashes). Each level of C++ → HTML → JS escape multiplies;
easy to over-escape into a parser error far from the affected feature.

**Hygiene:**
- `UI_DESIGN_SUMMARY.md` (Day 10) moved to `ARCHIVE/` — superseded
  by UI_DESIGN_v2 + Day-16 build.
- `GIMBAL_VIZ.md` §3 / §9 / §10 annotated with superseded-by
  callouts. Sections 1, 2, 4, 5, 6, 7, 8 remain authoritative
  reference.

**Closed / promoted this session:**
- #10a Gimbal UI page — DELIVERED as Gimbal Recon screen (one URL
  with ?screen= routing, not a separate URL as Day-8 had proposed).
  Production-readiness pending #49.
- #29 Mark Waypoint button — DELIVERED (btn22 + `'W'` CartLog event).
- Old design assumptions in GIMBAL_VIZ.md §3 (Way# dropdown, yaw/pitch
  nudge buttons, Extra 1/2 reserved fields) — formally retired.

**Not changed this session:**
- All execution-related workfronts (#5a dispatcher, ±100mm nudge,
  PAUSE/RESUME, #40 BNO build) remain open. Execution screen
  remains a placeholder pending these.

---



## Day 15 update (added 22 May 2026)

Build session. #36d Step D (TABLE → LIVE recovery) delivered and
end-to-end verified. Three Day-14-era bugs surfaced and fixed
during the build (see PROJECT_STATE day-15 entry for detail).

**Headline:** TABLE is no longer one-way per shoot. WiFi outage
mid-shoot now triggers FLIP to TABLE, photos continue on
step-function exposure, every 60s a 1s ping checks if comms are
back; on success the cart returns to LIVE and the standard
luminance walk nudges Tv/ISO back into the dead zone. 64/64
photos delivered across a full WiFi-off-then-on cycle.

**New principle reinforced:** once in TABLE, no CCAPI call should
originate from the cart except the Step-D ping. Gates applied at
every origination site (fetch arm, fetch service, PROBING entry).
Architectural rule, not a defensive patch.

**Part 3 — v1 simplification (same day).** With Step 4 closed
for v1, the per-flip table-row lookup that produced `exp_delta_t_rel`
+ `last_table_tv` / `last_table_iso` had no consumer. Retired
those state vars, `findTableRowForTv()`, `/debug/match` endpoint,
and associated Serial logs / JSON fields. Sketch −143 lines
(4986 → 4843). End-to-end verified 104/104 photos across full
LIVE → PROBING → TABLE → Step D recovery → LIVE cycle. FLIP log
and `/exposure/state` JSON clean at the wire. TABLE mode in v1
is now operationally exactly what it needed to be: "don't talk
to the camera, keep photos firing, ping every 60s."

**Part 8 — Gimbal execution model + PAUSE semantics (design).**
UI design session (Day-15 part 8) resolved how the gimbal half of
the plan executes alongside the cart, and what the proposed
PAUSE button does to both. This is design only — no firmware
written yet. Builds on Day-8 GIMBAL_VIZ design and Day-9
"operator-in-the-loop" architecture.

*Cart execution semantics (from existing v1 sketch).* MOVE
segments are **distance-driven** — cart drives until rear_steps
delta covers the segment's `dist_mm`, at the segment's
`speed_mhr`. Wall-clock time falls out. STOP segments are
**duration-driven** — cart sits for `duration_ms`. No clock-driven
MOVEs exist.

*Gimbal plan linking.* Gimbal events are anchored to cart
**waypoints** (cart distance), not wall-clock time. Example
authoring: "pan-follow from cart way 2 to cart way 5" or "move
from Ry 250° to Ry 110° between way 2 and way 5 (600mm)". The
gimbal events that DON'T link to cart distance: astro targets
(sunrise / sunset / MW) — those still fire on wall-clock astro
time because the sky doesn't wait for the cart.

*Move-to execution math.* For a "move yaw X° over Y mm" event:
- DJI R SDK protocol resolution: 0.1° yaw, 100ms time
  (`int16_t * 0.1f` per the sketch line 1381 etc.)
- Plan provides: total yaw delta, total distance, start yaw
- Execution computes the next nudge from
  `target_yaw - last_commanded_yaw` against accumulated distance
  from segment start — NOT from accumulated micro-increments.
  Rounding errors don't drift across thousands of nudges.
- Slow pan (5° / 600mm = 0.0083°/mm): one 0.1° nudge per ~12mm.
  Distance accumulates with no nudge fire for many cart loops.
- Fast pan (140° / 600mm = 0.233°/mm): one 0.1° nudge per ~0.43mm.
  Tighter nudge cadence.
- The combined plan tells execution the total distance and total
  yaw; execution decides when each 0.1° fires.

*Accuracy budget is loose.* Timelapse is post-processed for
luminance, flicker, and stabilisation. Wind blows the rig left
and right a bit anyway. The 0.1° yaw quantisation will look like
microscopic stair-steps in raw output; post-stabilisation
smooths them out completely. We don't need sub-0.1° resolution,
ms-accurate timing, or fancy interpolation.

*PAUSE semantics.* DEAD STOP button on Execution UI re-framed
as PAUSE (toggle PAUSE ↔ RESUME). Use case: hazard ahead, 2 min
freeze, then continue. Shoot continues throughout — photos keep
firing on Tv cadence, no abort.

- **PAUSE during a MOVE segment**: Tic ramps cart down via
  STOP_DECEL_SETTING (smooth, photogenic). Cart sits at the
  current rear_steps position with X mm still to go. Distance-
  driven gimbal moves also pause (no distance progress = no
  new yaw nudges fired). RESUME: Tic ramps back up via
  ACCEL_SETTING, rear_steps continues from where it stopped,
  segment end condition (delta ≥ target) is met when cart has
  actually covered the remaining distance. Distance preserved.
  Gimbal yaw resumes from its paused intermediate value.
  Total wall-clock extends by however long the pause was.
- **PAUSE during a STOP segment**: cart already at rest. The
  STOP duration counter is frozen — segment won't auto-advance
  until RESUME. Effective use: extend the hold past its
  scheduled end. Subsequent segments still cover their full
  distances, so cart still arrives at the right places.
- **Astro events during pause**: sunrise / sunset / MW are
  wall-clock-fired, independent of pause state. A pause that
  pushes the cart through an astro window means the gimbal
  goes to the astro position on schedule, regardless of where
  the cart is. Acceptable: astro is what audience expects to
  see on time; cart position is flexible.
- **Pause during a hold-at-waypoint (gimbal hold)**: zero
  effect on gimbal. Gimbal was already not moving. Photos keep
  firing on identical-frame which at 1320× speedup = ~1 second
  of audience-visual extra hold per 2-min pause. Indistinguishable
  from planned hold being slightly longer.
- **Pause during pan-follow**: zero effect. Pan-follow points
  gimbal yaw to track cart heading; cart heading isn't changing
  during pause; gimbal stays still.
- **Pause during track-point** (move-to a fixed earth-frame
  object): zero effect. Gimbal already pointed at object; cart
  paused means parallax doesn't change; object stays in frame.
- **Pause during move-to (distance-driven gimbal segment)**:
  the interesting case. Gimbal yaw pauses at intermediate
  value, audience sees a brief hold mid-move. Resumes when
  cart resumes, completes the remaining yaw delta over the
  remaining distance. Yaw will complete "on cart distance",
  not "on time".

*Real-but-not-often consequence.* Astro events are wall-clock-
fired. A long pause near a scheduled astro event can push the
cart into the astro window with a still-incomplete gimbal
move-to. The gimbal will then need to jump from its
mid-move intermediate yaw to the astro target. Whether this
manifests as a jolt or is smoothed by the planner is a
question for the gimbal-plan dispatcher (#5a) and the linking
logic (Excel-side #46).

*Status of this design.* Not built. Inputs to:
- #5a Segment dispatcher + cubic evaluator (firmware)
- #13 New Plan sheet schema (Excel — combined cart+gimbal plan)
- #46 Gimbal authoring against cart row labels (Excel)
- Execution UI (DEAD STOP renamed to PAUSE, toggles to RESUME)

**Part 9 — Speed transition types + ±100mm nudge semantics (design).**
Continuation of Day-15 Part 8. Adds the Excel-side speed-change
authoring vocabulary and the cart-execution behaviour for the
operator's ±100mm distance nudge during a running plan.

*Four speed transition types per segment-to-segment boundary.*
Excel emits the type per segment; cart dispatches in
`planSegmentEnter()`. All four target functions already exist in
the sketch — only the dispatcher and per-segment field are new.

1. **Dead** — `cartDeadStop()` — Tic `haltAndHold`, motor locks at
   current position, sharp stop. Used only when precision matters
   more than smoothness.
2. **Stop** — `cartStop()` — velocity factor → 0 immediately; Tic
   uses its current deceleration setting (STOP_DECEL_SETTING) to
   ramp down. Real-world acceptable for timelapse.
3. **Decay** — distance-driven linear-decay-to-zero. Plan
   specifies the decay distance; cart computes nudge factor
   `current_speed ÷ remaining_distance` and drops speed at each
   rear_steps increment. Recomputed if remaining distance changes
   (see ±100mm below). NOT the existing 6-minute global
   `cartStartDecay()` — that's manual-DEC-button behaviour.
   The plan-side decay is distance-bounded and adaptive.
4. **Smooth** — set the new target speed and let Tic's
   ACCEL_SETTING / STOP_DECEL_SETTING handle the ramp inside the
   next segment. "Slam it in and Tic will sort it out." This is
   the default — most segment-to-segment transitions will be
   smooth.

*±100mm nudge buttons on Execution UI.* Operator can adjust the
current MOVE segment's target distance by ±100mm. The Execution
UI shows the ToGo readout (current `target - delta` in mm) and
two buttons.

- **Within-segment**: target shifts by ±100mm. Cart continues at
  current segment speed. ToGo updates.
- **−100mm past zero**: segment completes immediately
  (`planSegmentComplete()` fires). Cart advances to next segment.
  Behaviour at the boundary depends on the **next** segment's
  speed transition type (above). Overshoot is small at slow
  segment speeds (the use case for −100mm); at higher speeds it
  could be larger but tap is less likely.
- **+100mm with distance left**: target extends 100mm. Cart
  continues; ToGo grows. No special handling.

*Decay segments interact with ±100mm via recompute.* If the
operator nudges a decay segment, the nudge factor is recomputed
each time the remaining distance changes:
- `−100mm during decay (plenty left)`: nudge factor recomputed,
  decay drops to zero faster (steeper). Audience-perceived: cart
  arrives at rest earlier than originally planned.
- `+100mm during decay`: nudge factor recomputed, decay drops
  more gently. Cart arrives at rest later.
- `−100mm during decay past zero`: emergency `cartStop()`
  fallback. Cart was already slow due to decay; overshoot
  negligible (sub-mm).

*Gimbal coupling on ±100mm.* Distance-driven gimbal segments
(move-to with yaw delta) recompute their yaw-per-mm nudge factor
the same way decay does:
- New nudge factor = `(target_yaw − current_yaw) ÷ new_remaining_distance`
- −100mm: yaw nudges accelerate to cover remaining delta in less
  distance. +100mm: yaw nudges slow.
- All other gimbal event types (PF, Lock, sun-track, astro
  targets) are independent of cart distance and need no
  recompute.

*Excel prevents gimbal moves spanning cart STOP segments.*
Distance-driven gimbal nudges only progress while cart distance
progresses — so a gimbal Move-to cannot span a cart STOP (the
gimbal would freeze mid-move during the stop, then resume,
producing an unintended audience-visible hold). Authoring rule:
each gimbal Move-to row may only cover consecutive cart MOVE
segments. Excel detects a Move-to that crosses any STOP and
errors at plan-bake time; operator splits the gimbal row into
before/after pieces. This keeps cart-side execution simple — no
"freeze during STOP / resume after STOP" logic needed.

*Stranded gimbal on −100mm past zero.* Different problem.
Operator-initiated cart shorten can end a MOVE segment while a
distance-driven gimbal move-to is still in progress. Excel
didn't anticipate this; the cart handles it locally with one
simple rule: **gimbal carries on at its current yaw/sec rate.**

- At the moment of strand, gimbal converts its last
  `yaw/mm × cart_speed_at_strand` into a constant `yaw/sec` rate.
- Gimbal continues nudging at that rate until it reaches the
  intended end yaw of the abandoned move-to.
- Then sits at end yaw (gimbal effectively becomes a hold).
- Cart is doing whatever its next segment says, independently.
- No snap. No reach into the next gimbal segment. No coupling
  back to cart distance.

Rare event. Not anticipated in Excel plan. Cart-side rule is
self-contained.

*Status.* Design only, not built. Same downstream consumers as
Part 8: firmware #5a, Excel #13 and #46, UI execution screen.
Additional cart-side need: Excel emits speed transition type in
the segment string, sketch parses it, dispatcher in
`planSegmentEnter()` selects between Dead / Stop / Decay /
Smooth handlers.

---

## Day 14 update (added 21 May 2026)

Build session. #36d Table Mode + comms-recovery state machine
delivered and end-to-end verified. See PROJECT_STATE day-14 entry
for full detail.

**Headline:** photos sacred verified through CCAPI outage. 14/14
delivered. 1 photo delayed 12s on discovery, 3 photos delayed 1s
during probe phase, post-TABLE-flip cadence clean.

**Day-15 part 2 (architectural):** v1 (current Uno R4 + all-WiFi)
declared production; sketch branched to `DJI_Ronin_UnoR4_v1prod.ino`
(bug-fix only) and `DJI_Ronin_Giga_v2dev.ino` (v2 dev starting
point). v2 = Giga R1 + Arduino Ethernet Shield 2, wired Ethernet
point-to-point to camera, camera WiFi disabled. v2 build absorbs
#22 Giga migration. Excel/UI shared across v1 and v2.

**New follow-ups added** (see #36d entries below):
- TABLE → LIVE recovery within a shoot (Step D, not yet built)
- TABLE per-cycle PUT logic (Step 4 of original Day-13 plan,
  design question added)
- Dead-state cleanup from removed Day-12 logic (low priority)

**Mental model retired:** "CCAPI activity stresses the camera" was
Day-11 thinking, traced to 100ms pulse width (fixed Day 12). The
constants built around being polite (`LUM_LIVEVIEW_RETRY_MS`,
`FETCH_FAIL_BACKOFF_CYCLES`, `LUM_FAIL_THRESHOLD`) were solving a
phantom; now gated or zeroed.

---

## Day 13 update (added 21 May 2026)

Two design resolutions in one session, both pure design (no code).

### #40 BNO085 integration architecture resolved (all six questions)

- **Anchor mechanism:** running scalar `gimbal_yaw_correction`
  applied additively to earth-frame-tagged gimbal cubics only.
  Pan-follow untouched. Cart drives its planned path blind — no
  cart position/heading correction. Plan stream gains per-row
  anchor flag + threshold + expected_cart_heading, and per-segment
  earth-frame vs chassis-frame tag.
- **Offset persistence (Q2):** Excel-pushed via Settings, NOT
  EEPROM. Fits the existing Appendix A / yaw envelope push
  pattern. Adelaide declination web-verified at +8.11°; bench
  offset +9.16° implies ~+1° BNO mount angle on bench, within
  ±3° BNO noise.
- **Acc dropout (Q3):** two-attempt retry per anchor row (500mm
  then 400mm before waypoint). If both fail, keep previous
  correction. Photos sacred throughout.
- **Cart→Excel feedback (Q5):** new CartLog event type `A` with
  subtypes A_OK / A_SKIP / A_FAIL. Pulled via existing /cartlog.
  Excel parser splits Type=A rows into a dedicated AnchorLog sheet
  on import.
- **Held over for build session:** stream format detail for the
  anchor flag/threshold/expected_heading fields; frame-tag bit
  position in Segment struct; ring buffer size + averaging window;
  whether A events overload columns or add a status column.

### #36d remaining subtasks resolved (Table Mode + Δt_rel offset)

- **Outage detection:** 3 consecutive fetch fails → TABLE mode;
  3 consecutive fetch successes → back to LIVE. Symmetric
  threshold. Grounded in Appendix A data (peak rate 1/3 stop
  per 60s, 3-miss-window ~18s well inside tolerance).
- **Recovery smoothing — eliminated.** Monotonic per-phase walk
  + post-fix in LRTimelapse makes smoothing both unnecessary and
  counter-productive (delays return to truth). Not deferred —
  removed entirely.
- **Tv-format Canon translation — stale.** Cart already has
  `TV_LADDER[]` (line 414, 60 Canon-format strings); Excel
  pushes Appendix A in Canon format; verified Day 12. No work.
- **Photo-loop integration:** new `exposure_mode` flag
  (LIVE / TABLE). Photo loop untouched. "Formula" in the cart
  is actually a step-function lookup table → renamed concept
  to **Table Mode**.
- **Δt_rel offset** (the key insight): at LIVE → TABLE handoff,
  find table row matching `current_tv`; from then on, lookups
  use `t_rel_now + Δt_rel`. Preserves the CCAPI loop's
  accumulated wisdom about today's specific sky (e.g. an extra
  stop slow because afternoon was overcast). Zero jolt at
  handoff by construction.
- **TABLE → LIVE return:** discard Δt_rel, existing
  `adjustExposureByLuminance()` does one-step-per-fetch
  catch-up walk. That walk IS the smoothing.
- **Edge cases — closed without separate design pass.**
  Candidates are implementation details, not design questions;
  handle at build time per PREFERENCES discipline.
- **Held over for build session:** exact `current_tv` →
  table-row matching when no exact string match; whether ISO
  shares Tv's Δt_rel; where wild-CCAPI rejection
  (EXPOSURE_FALLBACK §6.6) sits.

See PROJECT_STATE day-13 entry for full detail on both designs.

---


---

# Archived workfront doc: Cable UI (build-complete Day 31)

> Built + flashed as soak-v102 (cart Cable screen, view #3). Live status
> is in WORKFRONTS.md "Cart UI tidy-up" + items E/F. Original capture:

# Workfront — Cable UI (interactive cable-rigging screen)

**As of:** 07 Jun 2026. Context captured this session; build starting.
Companion to ChartPush.bas (exec chart author), PushPreviewPlanToCart
(preview/jog author), gimbal_cablestrip.py (the planning-side strip).

---

## The idea (two screens, two modes)

Two cart screens, BOTH authored in Excel, pushed to the cart, cart shows +
animates an icon (Excel = brains, cart = dumb renderer):

- **Execution UI** (exists) — PASSIVE. Gimbal steps in yaw+pitch (2-D
  trajectory) + live camera icon showing timelapse progress. No motion
  buttons. Safe to leave running.
- **Cable UI** (new) — INTERACTIVE. Yaw-only strip (unwrapped sweep vs the
  450 span) + PREV/NEXT buttons that DRIVE the gimbal point-to-point so
  the operator can walk the sweep: jog to a GP, dress cables, jog
  fwd/back to check clearance, repeat. Used BEFORE the shoot.

Safety: jog controls live ONLY on the Cable UI, never the Execution UI,
so no accidental button press moves the gimbal mid-timelapse. Plus a mode
interlock (below).

---

## Reuse map (what exists vs new)

EXISTS / reusable:
- SVG author + chunked push + cart-shows-and-animates-icon pattern:
  ChartPush.bas -> /settings/chartsvg, viewBox 0 0 355 90,
  x = (yaw - yaw_min)/450 * 355. The template.
- PREV/NEXT jog that drives the gimbal per GP -- ALREADY BUILT and its
  stated purpose includes "to route cables against the actual rotations":
  PushPreviewPlanToCart -> /settings/previewplan (idx,yaw,pitch,label,
  start; cap 20; Track GPs emit start+end), stepped via PREV/NEXT or
  /preview/step. This is the jog engine.

NEW:
- **Excel: cable-strip SVG author** (small; parallels ChartPush). Emits
  the 1-D yaw strip. MUST compute world bearing + unwrap via col AC the
  SAME way the dial/Python strip do (heading+offset, col-AC CW/CCW), NOT
  ChartPush's raw Ry+dyaw read -- so the cart strip agrees with the van.
- **Cart: Cable screen** (firmware; clone of the Execution screen made
  interactive). Same strip display + live marker, but PREV/NEXT call the
  existing /preview/step instead of being passive.

---

## Behaviours / decisions

- **2-sec ease between jog positions.** Operator wants a 2s ease GP->GP on
  PREV/NEXT (not a hard goto). Confirm whether /preview/step already eases
  or needs it added (firmware).
- **Mode interlock.** Jog must be blocked when a timelapse is armed/
  running -- a state gate, not just screen separation. (firmware)
- **No "max" shortcut.** Operator reaches the max-wind GP by repeated
  NEXT; no dedicated jump-to-max button needed.
- **Marker drive.** The cable strip's live marker = active preview-pose
  yaw mapped to strip x (same x = (yaw-yaw_min)/450*355 mapping the exec
  icon uses). Cart already tracks the PREV/NEXT index, so it knows the
  active GP.

---

## Open questions to confirm against the firmware (can't see C++ here)

1. Does /preview/step ease (2s) or hard-goto?
2. Can the cart hold a SECOND SVG slot (e.g. /settings/cablesvg) + a
   second screen alongside the Execution one, or does the preview jog
   currently reuse the execution screen? Determines whether the strip
   gets its own slot or shares.
3. Does the cart enforce any arm/run state we can hook the interlock to?

---

## Consistency rule (holds across ALL yaw views)

Dial PNG, planning strip PNG, exec SVG, cable SVG must all compute world
bearing + unwrap identically (heading+offset, col-AC CW/CCW). The Python
side already shares resolve(); the VBA authors must mirror that rule so
the van and the cart never disagree.

---

## Build order (this session)

1. Excel cable-strip SVG author (PushCableStripToCart), modelled on
   ChartPush, using the world-unwrap math. Pushable to a slot
   (cablesvg if available, else chartsvg to view immediately).
2. Wire into Prep / a button as desired.
3. Cart Cable screen + interlock + ease: firmware workfront (separate,
   not buildable here) once slot question (#2) is answered.


---

# Archived workfront doc: Moon astro (build-complete Day 31; firmware step 5 remains)

> Steps 3/4a/4b/6 DONE + hardware-confirmed (cart mask 127). Remaining
> firmware goto-rise-and-wait + gimbal-swing verification tracked in
> WORKFRONTS.md item B and PROJECT_STATE.md #9. Original capture:

# Workfront — Moon astro (init → UI execution)

**As of:** 07 Jun 2026. **Status: SCOPE + HORIZON decided; build pending.**
No code this session — read/check/ask only. Companion to
GIMBAL_EXECUTION_CAPABILITIES.md (#55 moon maths), WORKFRONTS.md (#50/#55),
PROJECT_STATE.md (#9 "moon not pushed").

---

## Decisions made this session (the two free gates)

1. **Moon is IN scope** for the gimbal Plan. (Resolves PROJECT_STATE #9
   "decide whether to push moon" and the WORKFRONTS open question
   "moon tracking in/out of scope".)
2. **Moon obeys no-shoot-under-horizon → goto-rise-and-wait.** When the
   moon is below the horizon the gimbal parks at its rise bearing and
   holds; it does NOT track the moon underground. This **SUPERSEDES** the
   old GIMBAL_EXECUTION_CAPABILITIES line that moon has "no horizon
   gating / clamp the steep-down pitch." Same rule as sun/GC now.

---

## What already exists (do NOT rebuild)

- **Astro maths — DONE (#55, Day 18).** Astro.bas: GetMoonPosition +
  public wrappers (Schlyter ephemeris), FindMoonCrossing /
  BisectMoonAltitude root finder, window selection for all four cases
  (rise+set, rise-only, set-only, neither). Validated vs timeanddate.com
  (moonset 01:07 vs 01:09). Fully local — no API.
- **Cart side — DONE (#50, Day 17).** Moon globals + mask bits,
  /settings/astropos carries mnry/mnrp/mnsy/mnsp,
  /gimbal/showastro?type=moon&kf=rise|set works.
- **Recon UI — DONE (#50, Day 17).** Moonrise/Moonset type buttons,
  Show astro / Snap var wired.
- **AstroPush + trackpath — built, test-proven (#55).** AstroPush.bas can
  populate moon on /settings/astropos; PushTrackPathsToCart adds moon as
  a third object (Day-18 test pushed sun+moon+MW). NOT in the production
  push path yet — see remaining (b/d).

So the gap is wiring + planning data, not new astronomy.

---

## Build plan (dependency order)

**3. Moon column in the generated AstroTable — FIRST BUILD (keystone).**
   The workbook's 15-min astro table is Sun + GC only today; no moon.
   Wire GetMoonPosition into the table generator ("Generate GC Table" /
   the astro-table builder) to add Moon Az/Alt columns. Everything below
   (cubic, plan, viz) depends on this. Maths exists; this is wiring.

**4a. Enable moon in the production astropos push (Excel).**
   btnInitShoot / AstroPush production call sends sun rise/set + MW
   rise/mid/end (mask=115) but NOT moon (bits 2/3 = 0), so the UI's
   Moonrise/Moonset return "slot not pushed" (hardware-confirmed 07 Jun).
   Add mnry/mnrp/mnsy/mnsp + set the mask bits in the production call.

**4b. Confirm moon track-path is in the production push.**
   PushTrackPathsToCart was test-pushed with moon Day 18 — verify it's in
   the production "Push Track Paths to Cart" sequence, dark-window cubic
   (astroDusk → darkEnd), not just the standalone test.

**5. Apply goto-rise-and-wait to moon (per decision 2).**
   Below-horizon window → park at moon-rise bearing + hold; no underground
   tracking / pitch clamp. Reuse the sun/GC park-and-wait path. Remove or
   annotate the stale "no horizon gating" note in CAPABILITIES.

**6. Downstream viz (falls out).** The plan-view renderer already supports
   moon as an earth-frame object colour; once step 3 gives it table data
   it draws with no renderer change. Verify on a real moon Track GP.

Tangential (not moon-specific, capture only): PROJECT_STATE #9 VBA
degree-symbol mojibake in the "Astro pushed" MsgBox — cosmetic, fix with
ChrW(176).

---

## Build log

**07 Jun 2026 — steps 3, 4a, 4b, 6 DONE; 3 + 4a hardware-confirmed.**
- Step 3 (AstroTable moon column): `GenerateGCTable` updated in Astro.bas;
  whole-module swap imported + compiled clean. Table now writes Moon Az/
  Alt/above-horizon (cols G/H/I).
- Step 4a (astro push): `PushAstroToCart` updated in AstroPush.bas (calls
  FetchMoonTimesForNight, pushes mnry/mnrp/mnsy/mnsp for crossings that
  exist). Whole-module swap imported + compiled clean.
- Step 4b (track-path cubic): already in production
  (PushTrackPathsToCart -> FitAndPushTrackPath "moon"); not a gap.
- Step 6 (plan-view renderer): reads moon cols G/H defensively; runs
  unchanged on a no-moon table, draws moon arc once present.
- Modules were ASCII-normalised on swap (cleared #9 mojibake in these two
  modules; degree glyphs in untouched dialogs became spaces).

**Hardware-confirmed push (spare GIGA, no gimbal/camera):**
Sun rise 62.6/-0.9, set 297.5/-0.8; MW rise 116.5/13.0, mid 2.1/84.1,
end 253.5/29.6; Moon rise 23:23 -> 100.3/-0.5, set 12:21 -> 263.6/-0.5.
Cart returned **`"mask":127`** (all 7 slots set; was 115 before = moon
bits 2/3 now on) and echoed moon_rise/moon_set. So table->push->cart
moon flow is proven on the spare GIGA. CCAPI timeouts in the same
InitShoot run are the absent camera (Tv fallback used, expected).

## Still NOT verified (rig apart: main GIGA repackaging, spare in use)
- Show astro -> Moonrise/Moonset actually SWINGING the gimbal (no gimbal
  connected). Stored OK (mask 127); motion untested until reassembly.

## Semantics check raised this session (not a bug)
- Tonight moonset resolved to 12:21 / az 264 deg — a MIDDAY set, outside
  the 4pm-8am dark window. FetchMoonTimesForNight clamps to shootSunrise
  + 0.5 and accepted it as the bookend. Confirm that's desired vs
  treating "no set within the dark window" as none. (Moonrise 23:23 is
  inside the window and clean.)

## One thing to measure, not assume
The moon cubic window is the dark window (astroDusk → darkEnd), same as
GC. With goto-rise-and-wait now in force, confirm the window logic and the
park behaviour agree at the edges (moon rising mid-window, moon already up
at dusk, moon never rising in the dark window) — the four #55 cases now
each need a defined park/track handoff.


---

# Session summaries (relocated, Day 25 -> Day 31)

> Per-session build narratives, archived 07 Jun 2026 after their live
> forward-content was migrated into PROJECT_STATE.md (NOW) and
> WORKFRONTS.md (NEXT). History/reference only. Day-30 (short) is
> superseded by Day-30 FULL; both kept for the record.


---

## (archived) SESSION_SUMMARY_Day25.md

# HyperLapse Cart — Session Summary, Day 25 (31 May 2026)

For future Claude. Read this first, then the consolidated docs. The
operator's working style is strict — see PREFERENCES_CONSOLIDATED.md.
Key points that bit this session: simple SEQUENTIAL one-step-at-a-time
instructions; NO menus of options/"maybe"s; NEVER suggest pausing or
ending the session; MEASURE/READ before theorising, do NOT stack
hypotheses or guess; raw URLs on their own line (not in code boxes).

---

## WHAT LANDED THIS SESSION (all validated end-to-end)

### 1. Recon IMU heading -> Excel (the core objective — DONE)
BNO heading now flows recon -> cart log -> Excel -> bicycle model.
- Cart: Mark-wpt (btn22) logs a 'W' then an 'A' row; 'A' value =
  true_yaw x10, plus cal. (Already in sketch from prior session.)
- Excel Cart.bas GetCartLog: 'A' rows land heading in col 12 (L,
  value/10) and cal in col 13 (M). These tail cols survive
  ProcessCartLog (which only clears E:K).
- BicycleModel.bas seeds theta0 from the first 'A' heading (negated:
  BNO is CW-negative). Measured -154.5 -> integrated +154.5. Validated.
- SIGN STILL TO CONFIRM against iPhone on a clean driven trace (the
  negate may need flipping if mirrored). Not yet done.

### 2. BNO motor-power stall — FIXED (categorical)
Stream froze under motor power. Root cause = I2C bus CONTENTION from
Tic clock-stretching (Pololu docs: Tic holds SCL low while busy),
NOT conducted noise. Prior "2.2k pull-up" fix was premature.
FIX: BNO moved to its OWN bus Wire2 (D8 SDA / D9 SCL), isolated from
Tics on Wire (D20/D21). 2.2k pull-ups on D8/D9 mandatory (mbed adds
none). Use the core's built-in Wire2 — do NOT declare your own
TwoWire (causes "multiple definition" linker error). Validated:
soak motors driving, /debug/imu last_poll_ms_ago 30-96ms, no stall.

### 3. /cartlog NON-CLEARING — FIXED
Was retrieve-and-clear; a stray browser read emptied the buffer
before GetCartLog, losing recon data.
- Sketch: /cartlog no longer clears. Added /cartlog/clearcart
  (clears ONLY the cart buffer; leaves gimbal log, recording,
  waypoint counter). Contrast /cartlog/clear = abandon EVERYTHING.
- Excel GetCartLog: calls /cartlog/clearcart only after a confirmed
  import (newRows>0). EMPTY check fixed to strip CR/LF on a COPY
  (Trim doesn't strip CRLF; don't strip the real response — Split
  needs the Chr(10) separators). Validated: browser re-read returns
  same rows.

### 4. Three pre-existing Excel bugs — FIXED
- TimestampDiff used CDate("00:00:00 " & t) -> type mismatch ->
  caught -> returned 0 -> ALL durations/distances were 0. Now
  TimeValue(t). (Verified in Immediate window: 105s correct.)
- ProcessCartLog distance was speed x time — operator says NEVER
  intended. Now (rearArr(i)-rearArr(i-1)) x M_PER_STEP (actual rear
  steps, same source as bicycle model). Snapshots RearSteps BEFORE
  the E:K clear wipes col 5. Added M_PER_STEP=0.00000178 + SafeDouble.
  GenerateReplayPlan unaffected (reads distance magnitude only).
- BicycleModel ApplyEvent 'T' used raw servo code as wheel angle;
  now evtValue - 98 (98 = straight, operator-confirmed).

### 5. btn3 (CTR) recenter logging — FIXED (sketch v22, NOT yet flashed)
btn3 set steering target to 98 but logged nothing; only the
ramp-arrival 't,98' appeared. BuildPlanFromCartLog ignores lowercase
't' (treats as informational), so the cart plan never saw the return
to centre and left Turn stuck at +32. The bicycle model DID catch it
(it UCases event type, so 't' hits Case "T"). FIX: btn3 now logs an
authoritative 'T,98' like cartAdjustSteering does. Banner soak-v22.
FORWARD-ONLY: existing recon logs predate this and still show held
+32 on post-recenter legs.

### 6. Cart-plan waypoint granularity — FIXED (PlanBuilder.bas)
Plan numbered every stop as a waypoint -> 5 marks became 13 rows.
This recon had ACCIDENTAL starts/stops (operator). FIX: only 'W'
marks number a leg; 'X' stops emit an un-numbered "—" STOP row and
legDistance CARRIES FORWARD to the next 'W' (not reset). Also fixed
WritePlanRow label: was derived from ROW INDEX (so STOPs stole
numbers regardless) — now from the passed wpNum. Bug found en route:
Chr(8212) throws "Invalid procedure call" (Chr is 0-255); use
ChrW(8212) for the em-dash. Validated: 5 marks -> WP01-WP05 + "—"
stops, distances carried (WP02=0.454m survived 3 stops before it).

---

## OPEN / NOT DECIDED

### Bicycle-model steering calibration (operator THINKING, not deciding)
Cart physically turned ~90° (operator ground truth) and BNO measured
~85° (WP1 +6.1 -> WP5 -79.0). Bicycle model integrated ~130-147°
(overshoot). Investigated by measurement, NOT guess:
- Ramp is NOT the cause: instant-on/off simplification gave the same
  overshoot (130-137°). Ruled out.
- Overdrive is NOT the cause: range only 0.95-1.00. Ruled out.
- Distance is NOT the over-rotation cause: log reads 6.15m total vs
  operator-measured 7-8m, i.e. log UNDER-reads — would make overshoot
  worse, not better. So the error is on the STEERING side.
- Circle test (17 May, 8-pt Kasa fit, +30 PWM, grass) gave
  SERVO_TO_DEG=0.504, R=1693mm — internally consistent.
- This recon's main leg implies SERVO_TO_DEG ~0.33-0.35 (matches the
  old day-9 quarter-turn estimate). Two clean measurements disagree;
  no known material difference.
- KEY INSIGHT (operator): protractor shows 30 servo units = 28° wheel,
  linkage near 1:1 at low angles -> geometric SERVO_TO_DEG ~0.93. BUT
  pure geometry (490mm wheelbase, 28° wheel) -> R=921mm, yet cart
  orbited 1693mm. Cart turns WIDER than the wheel angle implies = SLIP.
  So the driven SERVO_TO_DEG values (0.504, 0.33) are slip-corrected
  EFFECTIVE-steering factors, not linkage ratios.
- EMERGING STRUCTURE (agreed, not finalised): bicycle model is a
  planning VISUALISATION the operator edits the plan against — it is
  NOT fed to cart execution (BNO gives real heading at anchors). So
  the right structure is PURE GEOMETRY (honest 28°/wheelbase) x a SLIP
  FACTOR for on-ground path. To make THIS recon read 90°: slip = 0.376
  (eff wheel 11.3°). Circle test implies slip ~0.54. They BRACKET the
  real value. NOT decided which.
- CURRENT CODE STATE: BicycleModel.bas has SERVO_TO_DEG=0.504 and the
  -98 fix. The slip-factor restructure is NOT yet implemented — would
  be pure-geometry-wheel-angle x slip, replacing the single conflated
  constant.
- PROPER RESOLUTION needs a CONTROLLED re-test (linearity +5/+15,
  symmetry -30), not this single wobbly hand-driven recon. Operator
  flagged bicycle model is "at risk to provide [unreliable] repeated
  visualisation" until then — caveat any planning done off the trace.

### Other open threads
- Cart-plan Arrives column: still raw recon elapsed HH:MM:SS; the P3
  clock-time derivation is still a placeholder ("seed with raw
  timestamp for now" in WritePlanRow).
- M_PER_STEP / total-distance gap: log 6.15m vs measured 7-8m
  (~15-25% under). Entangled with slip; day-8 noted a similar ~10%
  theoretical-vs-measured gap (tyre deflection/slip). Needs the same
  controlled test.
- theta0 negate SIGN: verify against iPhone on a clean driven trace;
  flip if mirrored.

---

## NEXT STEPS (when operator returns to testing)
1. Flash sketch v22 to the cart (btn3 -> T,98). Watch the banner;
   if it shows old, clear Arduino IDE build cache
   (AppData\Local\arduino\sketches\) — a v19 flash this project
   previously refused to take due to a STALE BUILD CACHE despite
   dfu-util reporting success.
2. Controlled steering re-test to settle slip factor: repeat circle
   protocol at +5, +15 (linearity) and -30 (symmetry). Then decide
   pure-geometry x slip structure + the value (0.376 vs 0.54 bracket).
3. Confirm theta0 sign vs iPhone on a clean driven trace.
4. (Deferred, separate) plan-stream change: expected_cart_heading +
   earth/chassis frame tag into PlanSegment, then build 3b gimbal-yaw
   correction (-true_yaw) - expected_cart_heading; operator/iPhone
   override is a REQUIRED part of 3b.

## PENDING DOC WORK (not yet written into the masters)
Capture in the consolidated docs next session:
- The slip-factor analysis + the "geometry x slip" structure decision
  when finalised.
- The three Excel fixes (TimestampDiff, step-based distance, -98) and
  the btn3 logging fix, as build lessons.
- Build-lesson candidate: Chr() is 0-255, use ChrW() for Unicode in
  VBA cell writes.
- Build-lesson candidate: stale Arduino IDE build cache can make a
  dfu-util "success" boot the OLD banner — clear the cache.
  (Shared-bus / Wire2 lesson already captured in PREFERENCES build
  lesson 18 + GIGA_PIN_PLAN.)

## DELIVERABLES IN /mnt/user-data/outputs/
- DJI_Ronin_Giga_v2.ino    — soak-v22 (all cart edits; NOT yet flashed)
- Cart.bas                 — GetCartLog A-rows + clearcart + EMPTY fix
                             + TimestampDiff fix + step-based distance
- BicycleModel.bas         — -98 offset + SERVO_TO_DEG 0.504 + theta0 anchor
- PlanBuilder.bas          — stops un-numbered + label-from-wpNum + ChrW
- BNO085_BenchTest_Giga_Wire2.ino — Wire2 bench test
- CartLog_driven_recon.xlsx        — the real driven recon (RearSteps in E)
- CartLog_simplified_instant_turn.xlsx — instant-on/off test variant
- Cart_DIAG.bas            — diagnostic build (SUPERSEDED, can archive)
- CART_HEADING_DESIGN.md, BUILD_SPEC_recon_heading.md,
  IMPL_recon_heading.md  — heading design/spec/impl
- WORKFRONTS.md / WORKFRONTS_CONSOLIDATED.md, GIGA_PIN_PLAN.md,
  PREFERENCES_CONSOLIDATED.md, PROJECT_STATE_CONSOLIDATED.md,
  UI_DESIGN_v2.md        — master docs

## VERIFIED FACTS WORTH KEEPING
- Cart IP 192.168.1.97, WiFi "Rosedale". Operator on Windows/cmd.
- 98 = steering straight; servo range 60-130 on D5.
- Steering ramps 1°/sec (CART_STEERING_STEP_MS=1000). 't' logged only
  on ARRIVAL at target, not during the ramp. btn3 ramp-down from +32
  takes 32s; this recon's recenter t,98 at 00:04:05 means CTR pressed
  ~00:03:33 (cart still turning through the ramp, unlogged).
- M_PER_STEP=0.00000178 (1.77um/step, day-8). WHEELBASE_M=0.49.
- Bicycle model writes Trace sheet; reads RearSteps from CartLog col 5,
  steering as raw servo code (now -98 in ApplyEvent). UCases event type
  (so it catches lowercase 't'). Cart plan does NOT UCase (so it needed
  the btn3 T,98 fix).


---

## (archived) SESSION_SUMMARY_Day26.md

# HyperLapse Cart — Session Summary, Day 26 (01 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first — the operator's
style is strict: SEQUENTIAL one-step-at-a-time; NO option menus / "maybe"s;
MEASURE/READ before theorising, never guess (the word "guess" itself is
disliked — if you don't know, say so and ask); never suggest pausing/ending;
bare URLs on their own line in chat; deliver code as DOWNLOADABLE files, not
paste-in snippets (operator stated this preference explicitly).

Goal of the session was to repeat cart-recon trials and calibrate the
bicycle-model visualisation. We got partway, then uncovered a hardware
blocker (steering servo power) that gates clean calibration data.

---

## WHAT LANDED THIS SESSION (firmware now at soak-v27)

Each change shipped as a downloadable file. Cart sketch went v23→v27.

1. **Cart-log UI button colour (v23).** The b19 "Cart log" button now goes
   GREEN while recording, red when stopped (inline style in the /status
   poll — beats the `.rec` class specificity, the reason it was hard before).

2. **BNO true-north anchor PERSISTS to SD (v24).** `/debug/imu/capture` now
   writes the offset to `BNOANCHR.TXT`; boot restores it and prints a LOUD
   banner line (`ANCHOR RESTORED from SD offset=…` / `NO stored anchor…`).
   Excel just calls the capture link as a trigger. VALIDATED end-to-end:
   survives reflash AND power-cycle AND orientation (raw yaw is magnetometer-
   referenced via enableRotationVector, so it is repeatable across boots).
   Caveat baked in: a stored anchor is only valid while the BNO mounting is
   undisturbed — re-capture after any physical remount (banner reminds).

3. **Recon UI turn display = ACTUAL/TARGET (v25).** Turn now shows e.g.
   `+12/+30°` (+ = right), so the 1°/sec ramp lag is visible against the
   instant command. Speed already showed the commanded target (v[6]).
   /status gained steering TARGET at idx 15 (APPENDED, never inserted —
   lesson 16). Turn buttons (1–5) now re-poll ~200ms so target shows on press.

4. **Steering buttons step the TARGET, not the actual (v26).** `cartAdjustSteering`
   was `cart_steering + delta` (lagging actual) → repeated +5 presses gave
   5,7,9,11… Now `cart_steering_target + delta` → clean 5,10,15,20,25,30.

5. **Steering range made symmetric (v27).** Was MIN60/MAX130 about centre98
   (offset +32 / −38, imbalanced — an old issue). Now MIN63/MAX133 = even
   ±35 servo units. NOTE: 133 is 3 past the old 130 ceiling — operator to
   watch for mechanical bind at the right extreme on first test.

### Excel VBA fixes (delivered as files)
6. **ProcessCartLog no longer clobbers raw steps (Cart.bas).** ROOT CAUSE of
   a recurring data-loss: ProcessCartLog cleared `E:K` and reused cols 5/6
   for Duration/Scout-speed — destroying RearSteps(5)/FrontSteps(6), which
   are a SYSTEM-WIDE convention (written by GetCartLog + the simulators
   Module1/Module2/WobblyRecon; read by BicycleModel + Smooth). Fix: clear
   only G:K (+N:O), keep RearSteps/FrontSteps in 5/6, keep Distance at col 7
   and replay at 8–11 (consumers untouched), move Duration/Scout-speed to
   cols 14/15. Raw steps now survive ProcessCartLog regardless of run order.
   Delivered as the FULL Cart.bas (mojibake from extraction cleaned, written
   cp1252 so it re-imports as the "Cart" module). The earlier one-sub file
   `Cart_ProcessCartLog_FIX.bas` is SUPERSEDED — do NOT import it; it caused
   an "Ambiguous name detected: ProcessCartLog" because it imported as its
   own module, duplicating the sub. Operator removed it.

7. **BicycleModel steering SIGN fix (BicycleModel.bas).** Trace drew a RIGHT
   drive as a LEFT (CCW) arc. Cause: cart steer offset is +ve = RIGHT, but
   the model's wheel-angle convention is +ve = LEFT, so `SteerToRadians` now
   NEGATES. Arc now bends correctly. (The theta0 BNO-seed negate is correct
   and stays — confirmed by the east sign-check this session.)

### Calibration / frame work validated
- theta0 sign CONFIRMED (open from Day 25): cart north→east, true_yaw went
  negative while iPhone went +90 → negate is correct, NOT mirrored.
- Correct macro order for calibration: GetCartLog → BicycleModel (btnIntegrateBicycle)
  → ProcessCartLog → BuildPlanFromCartLog. BicycleModel must precede
  ProcessCartLog ONLY mattered before fix #6; now col 5 survives either order.
- The CircleFit/Calibration sheet machinery (InitCalibrationSheet →
  MatchWaypointsToLog → FitCircle) is for the 8-point CIRCLE runs (FitCircle
  needs ≥3 x/y points; the sheet's input block is for hand-measured ground-
  truth points). Operator is NOT using it for the turn runs.

---

## HARDWARE BLOCKERS — REPEAT THESE ON REFIT (operator's closing note)

### Servo power supply — NOK
- Steering servo is fed from a **Jaycar AA0236** DC-DC step-down: 6–28V in,
  3–15V out, **max 1.5A**, with overload/overheat auto-shutoff.
- 1.5A is the bottleneck. The servo (stock **Spektrum S905**, rated ~555 oz-in
  @7.2V — NOT a weak servo) STALLS partway (~15° instead of commanded 30°)
  on a DRY turn (turning while stopped = max tyre scrub = peak current).
  Delivered torque tracks current; capped at 1.5A the servo can't develop
  its rating → looks like a weak servo but is SUPPLY STARVATION.
- Cheap modules can't be paralleled to cheat more current (they hog/fold-back/
  back-feed; not current-sharing). Don't.
- PLAN (operator going to order): **HobbyKing YEP 20A HV SBEC** (~US$21–25):
  2–12S input (feeds from the onboard 6S aux), jumper output set to **7V**,
  20A continuous. Do NOT select 9V on the S905 (over its 7.2V rating).
  Wiring: BEC output → servo +/−, signal → Arduino D5, BEC ground tied to
  Arduino ground (common ground).
- TEST ON REFIT: put the EXISTING S905 on the YEP BEC and re-run the dry turn.
  If it now reaches 30°, the servo was never the problem — saved a A$260
  S6510 (which is also discontinued / down to single AU stock). If it still
  stalls when properly fed, THEN the S6510 (820 oz-in, 6–8.4V, 15T, giant-
  scale so a mount change) is justified. Both are 15T spline → aluminium
  clamping horn either way.
- ALSO: turning while ROLLING (not dry from a stop) avoids the stall — the
  good-practice ramp-while-moving sidesteps the worst case.

### Turn info in plan — NOK (resolved in firmware, re-verify on refit)
- The plan records ONE steer per leg = the value at the waypoint that OPENS
  the leg, and it's the TARGET (from 'T' events), not the trailing actual.
  WP03 showed +30 after a recenter because the recenter (T,98) landed INSIDE
  the WP2→WP3 leg, and the builder doesn't split a leg at a mid-leg steering
  change. WP02 showed speed 0 for the same reason (Start pressed at rest,
  speed raised during the leg).
- OPERATOR WORKFLOW RULE established: press WP *after* setting the speed and
  steering for the upcoming segment, and mark a waypoint at EVERY speed/steer
  change, so every leg is constant-state and the plan captures it. (Trade-off:
  more waypoints. For calibration runs, mark at each change.)
- The calibration is only trustworthy from turns where the servo ACTUALLY
  reached the commanded angle — i.e. once the power fix lands. A stalled
  servo logs target +30 while the wheel only made ~15°, which would corrupt
  any SERVO_TO_DEG / slip number. So: fix power, then repeat the recon trials.

---

## OPEN / CARRIED FORWARD
- Slip factor / SERVO_TO_DEG still NOT settled. Two clean +30 driven turns
  this session (carpet, R≈2.08 / 2.30 m) vs Day-25 grass circle (R≈1.69 m).
  Surface (carpet vs grass) is ONE known difference but NOT proven causal —
  speed, drive style, step-distance accuracy all also differ. Needs a
  controlled test holding all-but-surface constant, AND a properly-fed servo.
- Dot pitch on the Trace chart: the fine arc dots are 0.1m interpolation
  fill (ARC_VIZ_STEP_M), NOT per-step measurements; straights aren't
  subdivided. Read calibration spacing from the LOGGED event points (W/S/T),
  not the fill. (Optional future: make fill vs logged points visually distinct.)
- GetCartLog APPENDS to the CartLog sheet and does not clear first; it also
  calls /cartlog/clearcart after a confirmed import (so the cart buffer is
  emptied — a sheet mishap then can't be re-pulled). Operator flagged folding
  a sheet-clear into the macro as a future change. Consider also dropping the
  post-import clearcart so the buffer stays recoverable.

## DELIVERABLES IN /mnt/user-data/outputs/
- DJI_Ronin_Giga_v2.ino  — soak-v27 (all firmware edits above; NOT yet
                            flashed by end of session? operator was flashing
                            through v23–v27 live — v27 was the last delivered)
- Cart.bas               — full module, ProcessCartLog non-destructive fix
- BicycleModel.bas       — steering sign fix (SteerToRadians negate)
- Cart_ProcessCartLog_FIX.bas — SUPERSEDED, do not import (caused the
                            ambiguous-name duplicate); archive/delete.

## NEXT STEPS (when operator returns, post servo-power refit)
1. Fit the YEP 20A BEC at 7V to the existing S905; re-run the dry turn to
   confirm it reaches the commanded angle. Decide S905-stays vs S6510 then.
2. Re-verify v27 steering: symmetric ±35, clean +5 target steps, no bind at 133.
3. Repeat the controlled recon/circle trials with the servo properly fed,
   marking a WP at every speed/steer change, to finally pin slip / SERVO_TO_DEG.
4. Confirm the steering-sign-fixed Trace bends right on a fresh run.


---

## (archived) SESSION_SUMMARY_Day27.md

# HyperLapse Cart — Session Summary, Day 27 (02 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first — strict style:
SEQUENTIAL one-step-at-a-time; NO option menus / "maybe"s; MEASURE/READ
before theorising, NEVER guess (operator pulled Claude up repeatedly this
session for guessing — see process note at the end); never suggest
pausing/ending; bare URLs on their own line in chat; deliver code as
DOWNLOADABLE files. On "let's discuss": one-line restatement, then stop.

Session was steering ramp + heading work. The headline outcome: the BNO085
cold-boot heading is NOT trustworthy, and the design pivoted toward an
operator iPhone-compass anchor entered on the cart. Firmware went v27→v33.

---

## WHAT LANDED THIS SESSION (firmware now at soak-v33)

Cart sketch DJI_Ronin_Giga_v2.ino, cumulative v28→v33. Each shipped as a
downloadable file.

1. **Steering ramp rate 1°/sec → 1° per 250ms (v28).** `CART_STEERING_STEP_MS`
   1000→250 (= 4°/sec) after the BEC power refit. Three stale "1°/sec"
   comments updated. NOTE (carried from Day 26): watch for mechanical bind at
   the 133 right extreme on the first faster ramp.

2. **Recon UI heading readout — several iterations, ended at v32/v33 form.**
   - v29: live BNO heading put on the Cart Recon status line in place of the
     IMU cal field; `true_yaw` APPENDED to `/status` at idx 16 (tail, never-
     insert per lesson 16).
   - v30: cold-boot settle gate — UI + /debug/imu showed "settling" for the
     first 15s (BNO_SETTLE_MS), because the BNO emits dumb headings for
     ~10s after a cold boot (operator observation).
   - v31: switched to RAW yaw display (no offset, no settle) for direct
     sensor observation during diagnosis.
   - **v32 (current display): ADJUSTED heading + cal shown as e.g. `175°2`**
     (raw − SD offset, applied immediately at cold boot, NO settle gate).
     idx 16 = adjusted true_yaw; cal is idx 14; UI renders both as
     `<deg>°<cal>`. The 15s settle was REMOVED entirely (also from
     /debug/imu, which now returns true_yaw immediately).

3. **Operator iPhone-compass entry → 'C' row (v33).** Recon UI now has a
   **"Compass → last WP"** button: prompt modal asks for the iPhone compass
   degrees, POSTs to new `/compass?deg=N`, which logs a **`C` event**:
   `value` = degrees as typed (verbatim, no conversion), `aux` = the current
   waypoint number (binds to the most recent `W`, explicitly, not by log
   position — operator may enter it a few seconds after the WP press while
   steering). WP press is untouched/instant. CSV row exports as
   `HH:MM:SS,C,<deg>,<rear>,<front>,<wp#>`. Alert confirms which WP it hit
   (and warns if not recording).

### BicycleModel.bas — reframed to cart coordinates (delivered as file)
4. **Trace now in the cart's compass frame: +Y = NORTH (0°), +X = EAST
   (−90°), clockwise-NEGATIVE.** Matches the 4-quad measurement (below).
   - Seed: heading used DIRECTLY from the first `A` value (negate REMOVED,
     line was `(-CDbl(hdr0))`, now `CDbl(hdr0)`).
   - `SteerToRadians`: negate REMOVED (phi positive for right; the right-
     turn-clockwise sign now lives in the arc as `dtheta = -d/R`).
   - Straight: `x -= d·sin(theta)`, `y += d·cos(theta)`.
   - Arc: `R=WHEELBASE_M/tan(phi)`, `dtheta=-d/R`, `theta_new=theta+dtheta`,
     `x += R·(cos(theta)−cos(theta_new))`, `y += R·(sin(theta)−sin(theta_new))`.
   - Signs verified by a synthetic N/E/S/W Python unit test BEFORE writing
     (N→(0,+1); right turn curves clockwise to East; E→(+1,0); W→(−1,0)).
   - Validated on the real recon run: chart redrew correctly (start leg, the
     35° right arc clockwise, recentre tail). The start leg points ~ESE not
     south — that's THIS run's suspect −101° seed (a BNO capture problem,
     below), NOT a model error. The reframe is sound.

---

## THE BIG FINDING — BNO085 COLD-BOOT HEADING IS NOT TRUSTWORTHY

Measured, not theorised. This supersedes the Day-24/26 "raw yaw is compass-
locked, SD anchor bulletproof" conclusion for the COLD-BOOT case.

- **4-quad measurement (cart heading convention):** N≈0, E≈−84, S≈−179,
  W≈+97. Going N→E→S→W (clockwise) the number DECREASES → the BNO is
  **clockwise-NEGATIVE, North=0**. This confirms the Day-25 finding and
  contradicts a one-off live read earlier in the session (NE→+48.5) that had
  suggested CW-positive. The measured convention is the one used.

- **The SD true-north offset (BNOANCHR.TXT) is sound** — saved/restored
  correctly, survives reboot as a number. That part is NOT the problem.

- **Raw yaw is NOT compass-locked across a true COLD boot.** Repeated cold
  boots (main power only, no laptop) gave raw ≈ the SAME value regardless of
  which way the cart physically pointed (−56 region, later −26 after a
  recapture), with `cal` stuck at 0. WITHIN a boot, rotation tracks correctly
  (NE→N moved ~40°). So: relative datum that comes up the same each cold
  boot, not an absolute compass heading. The laptop-fed "reboots" earlier
  held a stable correct value ONLY because the board never lost power (chip
  RAM DCD survived); true cold boots lose it.

- **Root cause (code-confirmed, not guessed):** production build runs only
  `enableRotationVector(100)` and relies on the chip auto-loading a stored
  DCD (mag calibration) from its OWN flash. It never creates/verifies one.
  `cal 0` on every cold-boot read = no valid mag calibration loading → the
  rotation vector yaw isn't magnetometer-referenced → relative. A flash DCD
  is only written by `/debug/imu/savecal` (cal-capture build).

- **Web-confirmed:** `saveCalibration()` → DCD-to-flash is a real command,
  BUT BNO085 DCD persist/reload is widely reported as unreliable/finicky
  (unlike the older BNO055's clean save/reload), and CEVA says to re-do mag
  calibration per environment / room change.

- **Operator's current BNO state:** was reaching cal 3 at 400mm from metal in
  prior sessions; now sticks at cal 1, captures at cal 2 don't repeat.
  Operator's read: BNO may be dead / unrecoverable. Operator DECLINED the
  "take it well away from the cart to isolate environment vs sensor" test.
  The IMU is DETACHABLE — operator's plan is to dismount, rotate to bring cal
  to 2–3, and hope.

---

## DESIGN DECIDED THIS SESSION (iPhone-compass heading path)

Because the BNO cold-boot heading can't be trusted, the iPhone compass moves
from cross-check to PRIMARY heading source/anchor.

- **Browser-reads-phone-compass is NOT viable on the cart as-is.** Safari's
  `webkitCompassHeading` needs an HTTPS secure context + a per-visit
  permission tap (iOS 13+). The cart serves plain HTTP. Putting HTTPS on the
  Giga means a scary self-signed cert warning each time + heavy TLS — not
  worth it. So: **manual entry chosen** (operator reads the phone's Compass
  app, types the number).

- **Entry mechanism (BUILT, v33):** cart-recon-UI prompt modal → `C` row
  bound to the last WP (above). Separate action from the WP press; enterable
  while steering. Stored verbatim.

- **Execution-side concept (NOT built — deferred):** as the cart approaches a
  tracking gimbal GP (x mm out), the EXECUTION UI will INVITE an optional yaw
  correction (non-blocking). Cart never stops. Operator ignores (keeps
  current offset) or submits a fresh compass number → cart updates its
  heading offset on the spot and stays "dumb" (applies whatever offset it
  holds to aim the gimbal). This lives in the gimbal plan / execution / exec
  UI, which are still incomplete — explicitly deferred.

---

## CART-LOG / CHART WORKFLOW THIS SESSION
- First import attempt looked wrong (a different/older run was on the sheet;
  a lone heading value sat detached in cols L/M). Redone carefully: cleared
  the CartLog sheet → `GetCartLog` (38 events, buffer cleared on confirmed
  import) → rows matched the paste.
- Reminder captured: the bicycle chart macro is **`btnIntegrateBicycle`**
  (reads raw steps directly), NOT `ProcessCartLog`. ProcessCartLog is the
  plan path and is the destructive step on the raw step columns.

---

## NEXT STEPS (tomorrow — test, then continue)
1. **Flash soak-v33**, confirm banner `soak-v33`. Verify steering: faster
   ramp (4°/sec), no bind at 133.
2. **Test the `C` entry:** start cart log → Mark wpt → Compass button → enter
   degrees → confirm a `C` row reaches the buffer with the right WP number in
   the last (aux) column.
3. **Then Cart.bas:** teach `GetCartLog` to import the `C` row (give it a
   Description; land value=deg and the WP number sensibly). NOT yet done.
4. **Then the cart plan (PlanBuilder):** carry the `C` heading through into
   the Cart Plan. NOT yet done.
5. **BNO:** dismount + rotate to try for cal 2–3; decide recoverable vs
   iPhone-compass-as-primary. If the BNO stays dead, the recon `A` rows have
   no sensor behind them and the iPhone `C` value becomes the heading the
   bicycle model/plan rely on.

## DELIVERABLES IN /mnt/user-data/outputs/
- DJI_Ronin_Giga_v2.ino  — soak-v33 (cumulative: ramp 250ms; heading-on-UI as
                           `175°2`; settle removed; operator compass `C`-row
                           entry via /compass + recon UI button)
- BicycleModel.bas       — cart-frame reframe (N=+Y/0°, E=+X/−90°, CW-neg;
                           seed + steer un-negated; straight & arc rewritten)

## PROCESS NOTE (carry into next session)
Operator is precise and repeatedly (and rightly) stopped Claude for guessing
this session: inferring "L/M leftovers", asserting a settle/cal story, and
misreading the operator's cold-boot test method. The discipline that worked:
make ONE measurement at a time, report only what the data shows, say "I don't
know" + name the distinguishing measurement. Also: two `web_search` calls
fired in error mid-session (unrelated results) — disregarded; avoid spurious
searches. The BicycleModel sign work was the model case: verified in a Python
unit test before writing the VBA.


---

## (archived) SESSION_SUMMARY_Day28.md

# HyperLapse Cart - Session Summary, Day 28 (03 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. Operator style is
strict and was reinforced hard this session: SHORT replies, ONE thing at a
time, NO stories / no narrating a finding before you have it, MEASURE/READ
before theorising, NEVER guess, never suggest pausing/ending, bare URLs on
their own line, deliver code as DOWNLOADABLE files. NEW standing preference
this session: "I like simple - remove fancy stuff (decorative Unicode, etc.)
as we go." Files were made pure ASCII accordingly. Operator pulled Claude up
repeatedly for over-talking and for "making a story without the answer" -
answer the question asked, lead with the answer, stop.

The headline: first full edit -> push -> replay round trip worked. Cart drove
the edited plan. BNO now isolated (STUB_BNO); the iPhone compass is the
heading source.

---

## WHAT LANDED THIS SESSION (all delivered as downloadable files, pure ASCII)

### Cart.bas (3 changes, cumulative)
1. **GetCartLog imports the 'C' (iPhone-compass) row.** New tail cols:
   col 14 = "iPhone compass (deg)" (deg verbatim), col 15 = "Compass WP"
   (the bound WP#, from the C-row aux/field 5). Readable description
   "iPhone compass -180 -> WP1". Cols 14/15 survive ProcessCartLog and
   collide with nothing (BicycleModel only reads col 12; CartPlanPush reads
   B-G). Was Day-27 next-step #3.
2. **GetCartLog now WIPES the CartLog sheet before writing** (ws.Cells.Clear
   after the non-empty check, before headers). Fixes runs stacking + stray
   col 12-15 leftovers. Empty buffer still exits early -> sheet untouched, so
   a stray re-pull can't wipe a good sheet. Header-empty guard dropped
   (always fresh now).
3. **ProcessCartLog made NON-DESTRUCTIVE on col 5/6** (the Day-26 fix was
   NEVER actually in this workbook - measured, not assumed). Now: reads
   RearSteps live from col 5, clears ONLY G:K (+P:Q), Distance stays col 7,
   Duration/Scout RELOCATED to cols 16/17 (P/Q). NB: could NOT use the
   Day-26 target cols 14/15 - those are now the compass cols. Result:
   btnIntegrateBicycle and ProcessCartLog can run in EITHER order now.

### PlanBuilder.bas
4. **Compass heading carried into the Cart Plan.** Pre-scans C rows -> map
   WP# (col15) -> deg (col14); writes each WP's deg into Plan **col H**
   ("Heading (deg)", H5 labelled). Uses the explicit col-15 binding, not log
   position. Col H confirmed free (CartPlanPush reads only B-G; inside the
   B:K cleared zone). Was Day-27 next-step #4.

### BicycleModel.bas
5. **theta0 now seeds from the first 'C' row (col 14 iPhone compass), NOT the
   'A' BNO row (col 12).** BNO is stub/untrusted. C value used DIRECTLY
   (same cart frame: N=0, CW-negative; -180 = due south). Verified -180->-275
   in the log = ~90 deg clockwise = the physical right turn, so the frame is
   sound. Start leg now points due south instead of the BNO's ~SSW (162.7).

### DJI_Ronin_Giga_v2.ino  (soak-v34)
6. **STUB_BNO RE-ENABLED** (uncommented line ~82). The stub mechanism already
   existed and is wired through all the right #ifndef guards (driver, Wire2,
   A-row logging, /debug/imu, SD anchor; /status keeps idx 14/16 present
   emitting --/-1 so NO parser index churn). Verified compiles clean
   (bno_cal_status declared at 1027, OUTSIDE the guard, stays defined).
   RE-ENABLE BNO = comment that one line back out. Banner bumped to soak-v34
   "BNO STUBBED". Excel/log need NO change - A rows just stop arriving; the
   GetCartLog A-import path stays dormant.

---

## KEY UNDERSTANDINGS REACHED (operator-driven, measured)

### The recon -> plan column semantics (big one)
- CartPlanPush sends each Plan row as ONE segment `m,<dist_mm>,<steer>,<speed>,d`
  (STOP -> `s,<hold_ms>,0,0,t/o`). The sketch's planSegmentEnter EXECUTES it
  by setting that steer+speed then driving that distance. So a plan row = "drive
  this far at this state going forward." Confirmed end-to-end (Excel + sketch).
- Operator's WORKFLOW RULE (firm): set the state (speed/steer), THEN press W.
  Each W marks the START of a new constant-state segment = "state going forward
  from this WP." This MATCHES how the cart logs steering: the 'T' row records the
  TARGET (set at press, instant), not the actual (which ramps 1 unit/250ms and
  is logged as lowercase 't' only on arrival). So "state going forward" is
  consistent with the firmware.
- The plan's Turn/Speed currently land one WP late vs that rule (builder reads
  the leg-OPENING state). NOT yet fixed in code - operator hand-edited the plan
  instead this session. A forward-attribution fix to BuildPlanFromCartLog was
  DISCUSSED and is the clean fix, but DEFERRED (operator edits by hand for now).
- "Commences" vs "Arrives": operator renamed the Plan time column to
  **Commences** = when the cart STARTS that leg (= prev Commences + prev leg
  time). An END/STOP row gives the final ARRIVAL time (prev + its leg) which the
  gimbal anchors actions to. Plan completes with a STOP row (not "HOLD" - the
  push only knows DRIVE/STOP; HOLD would error).

### Arrives/Commences timing recompute
- There is NO macro that recomputes the Plan's Arrives/Commences from edited
  Speed. Builder only seeds col J with the raw recon timestamp (placeholder).
  GenerateReplayPlan (Cart.bas) DOES do dist/speed*3600 timing maths but writes
  the separate replay/Sequence sheet, off col-8 "Replay speed" - not the Plan.
- The Plan's gimbal side (cols P/Q/R) ALREADY has live formulas: P = anchor
  resolver (INDEX/MATCH a WP's col-J time, or TIME/ASTRO) + offset; R = gap to
  next. They DEPEND on col J. So a col-J formula makes BOTH sides live.
- DELIVERED (as text, for operator to paste) a col-J formula for consistency:
  J6 = `=dataShootStart`; J7 down =
  `=IF(C6="","",J6+IF(C6="STOP",G6/86400,IF(AND(ISNUMBER(D6),ISNUMBER(E6),E6>0),D6/E6/24,0)))`
  (DRIVE adds Dist/Speed/24 hours; STOP adds Hold/86400). dataShootStart =
  Settings!$C$49. Operator had not confirmed pasting it by end of session.

### Diagnostics confirmed by reading the log/sketch (NOT guessed)
- Start-of-run "speed commanded but no TIC distance" (9->79 ramp, count flat):
  cause = motors were DE-ENERGISED during that ramp; the speed buttons set the
  factor regardless. The 79->10 "jump" = cartEnergise() does
  `cart_velocity_factor = 0.0` SILENTLY (no S log), then the next +10 -> S10.
  Buttons are +/-1 and +/-10 (cases 7/9 and 6/10), not "+/-10 only". GAP worth
  noting: cartEnergise emits no 'S', so the log can't show the zeroing - infer
  it from the 79->10 step. (Possible future: log S0 on energise.)
- Dead stop at end: speed 100->0 in ~0.5s real, but only 2 log points 15s
  apart (W5 then final C while typing compass), so the chart line between them
  is a sampling artefact, not a slow coast. 1 Hz logging can't resolve it.
- Bicycle "steering factor" = SERVO_TO_DEG = 0.504 (PLACEHOLDER, Day-9 grass
  circle). wheel_deg = offset*0.504; R = WHEELBASE_M(0.49)/tan(phi). +35 ->
  17.6deg -> R~1.54m. M_PER_STEP = 0.00000178.
- OVER-ROTATION re-confirmed: the +35 leg drove ~3.1m of arc; a true 90deg at
  R=1.54 would be only 2.42m, so 3.1m reads ~128deg. For 3.1m to BE 90deg, R
  must be ~1.98m. So 0.504 turns too sharp = slip/understeer. Compass
  (-180->-270/-275 = 90deg) is ground truth. SERVO_TO_DEG still NOT settled;
  needs the controlled test (linearity +5/+15, symmetry -30). NB operator
  thinks the YEP BEC servo-power upgrade helped the turn quality (plausible -
  servo no longer stalling - but NOT a substitute for the controlled test).

---

## THE REPLAYED PLAN (worked end-to-end this session)
Hand-edited, forward-state, speeds dropped 100->30, turn begins ~0.8m in:
```
WP01 DRIVE 1     30  0   -180
WP02 DRIVE 3.3   30  35  -180
WP03 DRIVE 1     30  0   -270
WP04 STOP  -     -   -   -270   (operator-hold end)
```
Dry-run URL verified, real push OK ("OK loaded n=4"), /plan/start -> "OK plan
started" -> operator reported "worked well". (Outstanding: get the on-ground
turn-vs-90deg number for the slip factor - operator hadn't reported it.)

---

## HARDWARE: charger selected (operator shopping)
SkyRC **B6neo** (SKU SK-100198-01, DC 200W, 1-6S, XT60 in) at Model Flight
Adelaide for **$65**. For the van's 12V/100Ah lithium bank. Covers 6-8A 6S
(<=200W); quiet (~48dB) at 6A, fan busiest at the 8A ceiling. Run via a fused
(~25-30A) XT60 lead - charger pulls ~18-20A from 12V at full 8A. Step-up
quiet-at-8A options noted (B6neo+ 240W / B6neo 2 300W, both spec'd 48dB at
full load) but plain neo chosen as 6A is the norm. Get the DC B6neo, NOT the
AC B6ACneo.

---

## NEXT STEPS (when operator returns)
1. (Optional) Paste the col-J Commences formula + set dataShootStart, so plan
   timing recomputes live on speed edits and the gimbal P/Q/R follow.
2. The controlled slip test (linearity +5/+15, symmetry -30, servo now
   properly fed) to finally pin SERVO_TO_DEG / decide pure-geometry x slip.
   Get the on-ground turn-vs-90 number from the replay too.
3. (Deferred, agreed clean fix, NOT done) forward-attribution in
   BuildPlanFromCartLog so Turn/Speed land on the WP where the state was set
   (not one WP late). Operator hand-edits for now.
4. Gimbal/execution side still incomplete (Day-27 carry): exec-UI optional
   yaw correction on GP approach, etc.

## DELIVERABLES IN /mnt/user-data/outputs/
- Cart.bas              - C-row import + sheet-wipe + non-destructive ProcessCartLog
- PlanBuilder.bas       - compass heading -> Plan col H (col-15 binding)
- BicycleModel.bas      - theta0 seeds from first C row (col 14), BNO dropped
- DJI_Ronin_Giga_v2.ino - soak-v34, STUB_BNO re-enabled (BNO isolated)

## PROCESS NOTE (carry forward, reinforced hard)
Operator wants ANSWERS, not narration. Several rebukes this session: "make a
story without the answer", "less talk i get confused", "too much", "why start
prior text with word No", "stop telling stories", "not too much talk". The
discipline that worked: read/measure the code, then state the finding in one
or two lines, lead with the direct answer to the exact question, stop. When
asked yes/no, start with yes/no. For tables, output the plain table and stop -
don't wrap it in paragraphs. Keep the "remove fancy stuff / ASCII" preference.


---

## (archived) SESSION_SUMMARY_Day29.md

# HyperLapse Cart - Session Summary, Day 29 (04 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. Operator style
held hard this session: SHORT replies, ONE thing at a time, lead with the
answer, yes/no when asked, MEASURE/READ before theorising, NEVER guess,
NEVER jump to root cause, keep separate hardware separate, pure ASCII, no
fancy stuff. Repeated rebukes this session: "what a story", "too big a
story", "again a long story", "stop and think", "no discussion" - and
twice for jumping ahead of the evidence. When the operator says "wait, I
have more to share", STOP and let them finish before analysing.

The headline: the gimbal plan was authored, pushed, and executed
end-to-end; the Phase-A ease bug was fixed and proved; the CAN bus was
traced and restored; and the real design gap was named - gimbal execution
must be WP-event-anchored, not clock-anchored. A stepwise build plan for
that capability was written (WORKFRONT_gimbal_WP_coordination_Day29.md).

---

## WHAT LANDED THIS SESSION

### Gimbal plan authored + pushed + executed
- Built the gimbal block in the Plan sheet to a simple test: GP01 WP01
  straight (dyaw 0), GP02 WP02 right (dyaw -30), GP03 WP03 left (dyaw
  +30), GP04 WP04 straight (0), GP05 WP04 END. Action = Move; END bounds
  the last move's window (the push errors if a Move is the last row).
  Sign convention applied: right = negative yaw (cart CW-negative frame);
  flagged for operator confirmation, not measured on the Ronin.
- Push macro = `PushTrackPlanToCart` (gimbal). Dry run via
  `dataPlanPushDryRun = TRUE`, real push FALSE. (`PushGimbalPlan` is
  validate-only, NOT the push.) No AstroPush/cubics needed - all GPs are
  Move, obj=N.
- Documented "what can be typed" per gimbal column from the sheet's
  data-validation lists + PlanAuthoring.bas. Two stale-DV findings: col P
  (Offset) carries an old "Pan Follow,Approach,Lock" dropdown from a prior
  layout; "Approach" survives only there (live Action list dropped it).
- Col AA "Move t" = a vestigial DERIVED placeholder. PlanAuthoring writes
  the literal "(computed)" and paints it grey; PlanPush declares
  COL_MOVE_T=27 but never uses it; the real move time is computed at push
  from Ease x cadence. Nothing reads AA. Safe to ignore/clear.

### TrackPlanPush.bas - Phase-A ease / sunset fix (DELIVERED)
- Symptom: dry run logged "sunset/sunrise not set", cadence 0, ease
  forced to snap, even on a WP-only plan.
- Cause (measured): TrackPlanPush read the sun-time cells through
  SafeNum, whose IsNumeric() gate returns 0 for a DATE-typed cell. The
  sun cells (Settings F8/F18/F22) store full datetimes, so they read as 0
  -> cadence 0. Fires-at survived because it is time-of-day only.
- Second fault: sun times carry a date, plan Fires-at are time-of-day
  only - different bases for the cadence subtraction.
- Fix (read-time only, GetSunsetTime untouched): added `CellSerial`
  (IsDate-aware read) and `StampClock` (place fire + sun-event times on
  ONE dated timeline anchored at the shoot evening; sunrise rolled to the
  end-of-shoot morning so fireTime-sunriseT has the sign FormulaTv's
  sunrise branch wants). Confirmed FormulaTv expects negative t_rel
  before sunrise before writing.
- Proved: dry run then REAL push - cadence 22.0s, acquire_ms non-zero,
  4 intervals accepted. Build marker added: "(build: Day28
  dated-timeline ease fix)" prints on the start line.
- Ease band note: at 22s cadence, Comfortable (10 frames) = 220s ease,
  which overran the 2-min GP01/GP04 windows; switched those to
  Just-perceptible (3 frames) = ~66s, which fits.

### Giga_CAN_bus_test.ino - standalone CAN isolation sketch (DELIVERED)
- No WiFi/SDK/gimbal logic. 1 Mbit, TX id 0x223, sends a dummy frame
  every 50ms, reports TX OK/FAILING + any RX. Same write() pass/fail
  signal the main sketch logs as "TX errors". Used to clear gimbal,
  spare rig, and finally the cart Giga + Pal one variable at a time.

### WORKFRONT_gimbal_WP_coordination_Day29.md - build plan (DELIVERED)
- The stepwise plan for WP-event-anchored gimbal execution (see below).

---

## KEY UNDERSTANDINGS REACHED (operator-driven, measured)

### Gimbal execution must be WP-event-anchored (the big one)
- The plan binds GP to WP: Plan col Q (Fires-at) = the WP's Commence time
  (col J) + Offset (col P). There is NO independent gimbal timebase in the
  plan.
- The firmware does NOT honour that: TrackPlanPush flattens each GP to
  absolute ts/te ms, and trackPlanTick walks them against its own clock
  (`millis() - track_plan_anchor_ms`), anchored at `/track/start`. The
  executor never reads cart WP progress.
- So cart and gimbal run on TWO independent clocks. `/track/start` zeros
  the gimbal; `/plan/start` zeros the cart; `/plan/start` does NOT re-sync
  the gimbal (confirmed in sketch). Whatever gap is between the two
  start calls becomes permanent drift; cart slip or a `/plan/nudge`
  widens it. This is why the Day-28/29 runs were not coordinated.
- Design intent (operator, firm): GP is tied to WP - whenever the WP
  happens, the GP executes (arrival + offset), surviving slip/nudge.
- The clean hook: the cart already stamps the WP arrival in
  `planSegmentEnter` (`plan_seg_start_ms = millis()`), which IS that WP's
  Commence - the same instant col J represents. WP-event anchoring =
  hooking the gimbal onto an event the cart already produces.
- `/plan/nudge?d=+-N` exists (Day-15/16): live +-mm trim of the running
  MOVE segment. Cart-only - it does NOT touch the gimbal plan, so under
  the current firmware a nudge desyncs cart vs gimbal further.

### Cubic astro tracking is already in the sketch
- `TrackPath` holds per-object cubic coeffs (sun/moon/mw), pushed via
  `/settings/trackpath`; `trackEvalAt` evaluates a0+a1t+a2t^2+a3t^3 each
  tick; the executor drives FULL (yaw+pitch) and YAW (yaw + fixed pitch)
  modes from it. Sun Track hardware-proven. Model B already anchors the
  cubic to REAL time (`real_t0_ms`/`cartRealTimeMs`), so once a WP event
  sets WHEN the interval opens, the cubic gives WHERE the object is at
  that real moment. The tracking math is done; only the WHEN needs to be
  WP-anchored.

### Heading model with BNO stubbed (future work)
- BNO is now stubbed (Day-28). Heading source moves to the iPhone -
  rung 1 of the CART_HEADING_DESIGN trust ladder - with planned
  `expected_cart_heading` as the floor.
- New Day-29 refinement: Cart Recon now captures a compass reading per
  WP. That recon compass becomes `expected_cart_heading` (pushed per WP),
  so the planned heading is measured, not pure bicycle integration. At
  execution, an iPhone request on approach to an astro GP = compare /
  override / offset against it, propagated forward to stop cumulative
  drift. Feeds the existing 3b correction on earth-frame GPs only.
  All future work.

---

## CAN BUS (traced + restored; factual, root cause of trans 2 unconfirmed)
- Gimbal CAN was dead at session start - TX errors climbing, no ACK.
  Established: 1 Mbit both ends; the gimbal accessory link is point-to-
  point and the external node IS an end, so it must terminate. Gimbal
  presented 120 (one terminator); switching the Pal's 120 on gave ~66
  ohm (both ends). Wiring continuity + H/L verified.
- Still TX errors after termination. Isolation via the test sketch:
  spare Giga + spare Pal -> gimbal STREAMS 0x530, two-way good (gimbal +
  spare rig + Ronin all cleared). Cart Giga + production Pal -> TX
  FAILING, rx=0 (the controller accepts ~3 frames into the mailbox then
  collapses when nothing ACKs).
- Parts now: trans 1 dead (reverse polarity, known, operator error);
  trans 2 = production/suspect, REMOVED, cause UNCONFIRMED; trans 3 +
  spare Giga now in the rig and WORKING (0x530 streaming, `/home` good,
  TIC on).
- CORRECTION for the record: I called the S (silent-mode) pin as the
  production fault. That was PREMATURE and wrong - the production Pal had
  S tied to GND (normal mode), the spare had S unconnected (also normal);
  both are normal-mode wiring. Do NOT attribute trans 2's failure to the
  S pin. Cause unconfirmed.

---

## NEXT STEPS (when operator returns)
1. Build WP-event-anchored gimbal execution per
   WORKFRONT_gimbal_WP_coordination_Day29.md: Phase 1 (carry anchor WP +
   offset through the push; record `wp_arrival_ms[]` in planSegmentEnter)
   -> Phase 2 (fire intervals off arrival + offset; retire the gimbal
   clock; this SUPERSEDES the parked /plan/start re-stamp idea) -> Phase 3
   (validate, incl. a nudge test) -> Phase 4 (astro + heading, future).
2. Two decisions deferred to build time: fire-late-vs-skip when an
   offset window is still open at the next WP; Pan-Follow -> Track
   handoff ease.
3. Interim, to SEE coordinated motion before the build: fire
   `/track/start` and `/plan/start` back-to-back (within ~1s). Note GP01
   is a real move now (Move eases from the gimbal's actual non-zero yaw
   to 0), not a no-op.
4. Housekeeping so the standing docs are not misleading: fold the Day-29
   workfront into WORKFRONTS.md (or note it at the top); fix
   PROJECT_STATE "State of the system" which still says gimbal execution
   is "design only" (superseded by Day-24 proofs + the Day-28/29 runs).
5. Future: iPhone heading 3b + recon-compass `expected_cart_heading`
   propagation.

## DELIVERABLES IN /mnt/user-data/outputs/
- TrackPlanPush.bas                         - Phase-A ease/sunset dated-
                                              timeline fix (re-import)
- Giga_CAN_bus_test.ino                     - standalone CAN isolation
- WORKFRONT_gimbal_WP_coordination_Day29.md - stepwise build plan
- SESSION_SUMMARY_Day29.md                  - this file

## MISTAKES OWNED THIS SESSION (carry the discipline forward)
- "GP01 will not move" - WRONG. Move eases from the ACTUAL current pose
  to the absolute endpoint; current yaw was non-zero, so GP01 (yaw 0)
  moves. Read the executor, do not assume a zero-target is a no-op.
- "Cart and gimbal hang off the same start clock" - WRONG. Independent
  clocks; only the plan numbers are shared.
- S-pin called as the CAN fault - PREMATURE, wrong (see CAN section).
- Conflated the spare bench rig with the cart hardware - the operator
  corrected it. Keep separate hardware separate when reasoning.

## PROCESS NOTE (reinforced hard)
Answer the exact question, lead with the answer, stop. Yes/no first when
asked yes/no. Measure/read before theorising; do NOT jump to root cause -
state findings, not stories. When the operator says to wait, wait. Keep
pure ASCII / simple. Several rebukes for length and for getting ahead of
the evidence; the discipline that worked was: one finding, one or two
lines, stop.


---

## (archived) SESSION_SUMMARY_Day30.md

# HyperLapse Cart - Session Summary, Day 30 (05 Jun 2026)

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. Operator style held:
SHORT replies, ONE thing at a time, lead with the answer, MEASURE/READ before
theorising, NEVER guess, keep separate hardware/frames separate, pure ASCII.
Formatting rules reinforced this session: macros in CODE BOXES (copy button),
test URLs as BARE URLs on their own line in chat (never code-boxed - backticks
break click-through). When the operator says "stop", stop.

The headline: WP-event gimbal coordination (Phase 1-3) was built and PROVEN
end-to-end, including a nudge-divergence test. Mid-session a two-convention
heading bug was found and fixed - the whole system is now unified on the
Ronin/standard clockwise-POSITIVE frame. Phase 4 (astro) was scoped; the live
sun run was deferred (sun down, ~6pm Adelaide June).

---

## WHAT LANDED THIS SESSION

### WP-event gimbal coordination - Phases 1-3 (DELIVERED, PROVEN)
The design gap from Day 29: cart and gimbal ran on two independent clocks, so a
gimbal point (GP) fired off /track/start time, not off the cart actually
reaching its waypoint (WP). Now each GP fires on the cart's ACTUAL WP arrival.

- Phase 1 (carry the binding + record arrivals):
  - TrackPlanPush.bas: appends two tail tokens to /settings/trackplan -
    `awp` (anchor WP number, parsed from "WPnn"; 0 = not WP-anchored) and
    `offms` (col P "Offset (min)" x 60000 -> ms). ts/te kept for preview +
    fallback. Append-only (build-lesson 12). Dry-run logs a `bind:` line.
    MEASURED: col P is MINUTES (col Q formula uses P/1440), not ms.
  - Sketch (soak-v35): TrackInterval gains anchor_wp + offset_ms; the
    trackplan parser reads awp/offms; absent => 0 => fall back to ts/te.
  - Sketch (soak-v36): planSegmentEnter stamps wp_arrival_ms[idx+1] (the
    actual arrival = the WP's Commence). WP number = segment idx + 1 (the
    cart logs SEG idx+1). planReset zeroes the array. Record-only.
  - Proven: real push, four `[track] ... awp=N offms=N` lines on the cart;
    cart-plan run printed `[wp] arrival WP1..4` at the right deltas.

- Phase 2 (fire off WP events) - sketch soak-v37:
  - trackPlanTick now selects the active interval from LIVE windows in
    absolute millis(). New helper trackIntervalOpenAbs(i): WP-anchored ->
    wp_arrival_ms[awp] + offset_ms; returns 0 (pending) if that WP not
    reached yet; non-WP (astro/time) -> legacy track-start-relative window
    (made absolute via the anchor), so pure astro/time plans are byte-for-
    byte unchanged. Intervals are contiguous by construction (TrackPlanPush
    sets each te = next GP Fires-at), so the active interval is the LATEST
    one whose window has opened; the LAST interval closes at its planned
    duration past its own open (= the pushed END time = GP05 END).
  - /track/start vs /plan/start order no longer matters. /track/start stays
    arm+anchor (anchor still needed for the astro now_s fallback); WP-
    anchored intervals ignore it. This SUPERSEDES the parked "re-stamp at
    /plan/start" idea.

- Phase 3 (validate) - PASSED:
  - Coordinated run: armed /track/start, gimbal sat still (all WPs pending),
    then GP01 fired on `[wp] arrival WP1`, GP02 on WP2, etc. It did NOT fire
    on the track clock.
  - Nudge divergence: mid-WP1 `/plan/nudge?d=2000` (1000->3000mm). WP3/WP4
    arrived hundreds of seconds late; `[track] interval -> N` landed on each
    late `[wp] arrival`, not on the stale planned time. This is the
    acceptance proof: GPs track the actual WP through slip/nudge.

### Heading convention UNIFIED (cart was running two frames) (DELIVERED)
- Discovery: the Ronin gimbal yaw is clockwise-POSITIVE (right = +), confirmed
  on the bench (GP02 Delta yaw -30 panned LEFT) AND by DJI docs (negative yaw =
  port/left). The cart bicycle/recon frame was clockwise-NEGATIVE (east = -90,
  MEASURED Day-27). Two conventions. Operator chose to unify on the Ronin /
  standard / phone frame: N 0 / E +90 / S 180 / W -90.
- BicycleModel.bas - BOUNDARY FLIP (lowest risk): the proven Day-8 integration
  core runs untouched (internally still CW-negative, so path geometry stays
  validated); only two boundaries negated - the seed read
  (theta_rad = -(C value)*PI/180) and the heading OUTPUT (Trace col 4 + BIKE
  log). Steering (+ = right) is a separate convention, untouched.
- PlanBuilder.bas writes the C value to Plan col H VERBATIM -> the raw +90 you
  now type flows straight through. NO change needed.
- Gimbal Delta yaw (Plan col X) is already authored in the Ronin frame -> NO
  change. Future earth-frame correction now needs NO sign flip (cart + gimbal
  agree).
- Validation drive: started south (theta_deg = +180), right turn climbed
  through the +/-180 seam toward west (-90); path shape matched the ground.
  Frame PROVEN. (Cart ended ~-49 WNW because steering straightened mid-turn -
  faithful, not an error.)
- HEADING_CONVENTION.md written as the single source of truth.

### Phase 4 SCOPED (not built)
- Piece A - astro GPs fire WP-anchored: needs NO new code (the Phase-2 window
  selection is mode-agnostic, so a Track GP anchored to a WP already opens on
  WP arrival; cubic eval / Model B real-time is hardware-proven Day-24). A
  live Sun Track run is the only confirmation left - DEFERRED (sun down).
- Piece B - earth-frame heading correction (3b): the genuinely new build.
  expected_cart_heading pushed per WP (recon compass), iPhone live heading
  compare/override/offset on approach, applied to earth-frame GPs only. Now
  needs NO sign flip thanks to the unification. Future.

---

## KEY UNDERSTANDINGS (measured / read, not guessed)
- WP number = cart segment idx + 1 (the cart logs SEG idx+1). awp is 1-based.
- Phase-2 interval selection is MODE-AGNOSTIC; Move and Track open identically.
- Astro epoch footgun: the cubic's rt0 (AstroPush, treated as UTC) and the
  /settings/realtime anchor MUST both be UTC epoch-ms; local time = sun aimed
  off by the Adelaide offset (~9.5-10.5 h). There is NO realtime-push macro -
  the (unbuilt) Execution UI was meant to hand it; bench test = hit
  /settings/realtime?ms=<UTC epoch> by hand.
- Migration gotcha: any CartLog recorded with the OLD -90-for-east entry now
  integrates WRONG (seed negate flips it). Only re-integrate logs entered with
  the new +90-for-east convention.

---

## NEXT STEPS (when operator returns)
1. Phase 4 piece A: live Sun Track WP-anchored run in DAYLIGHT - author a Sun
   Track GP anchored to a WP, PushTrackPathsToCart, set UTC realtime anchor,
   PushTrackPlanToCart, arm, run. Confirm the Track interval opens on WP
   arrival and the gimbal follows the sun. Mind the UTC epoch consistency.
2. Phase 4 piece B: build the earth-frame heading correction (3b) -
   expected_cart_heading per WP + iPhone live heading. No sign flip needed.
3. SERVO_TO_DEG calibration (controlled slip test: linearity +5/+15, symmetry
   -30). Model still OVER-rotates (+35 leg reads ~128 deg vs true ~90). The
   frame flip did not touch this - geometry preserved, just reported in the
   right frame.
4. Reconcile the remaining docs to HEADING_CONVENTION.md: CART_HEADING_DESIGN,
   GIMBAL_EXECUTION_CAPABILITIES (Delta yaw wording), WORKFRONTS (#40/#41),
   WORKFRONT_gimbal_WP_coordination_Day29 (sec 4), PROJECT_STATE.
5. LOOP-LONG ~1.7-2.0s stalls at /track/start and first interval entry - noted,
   NOT investigated. Instrument before theorising (CAN setPosControl burst? or
   WiFi handling?).

Two build-time decisions still parked (workfront): fire-late-vs-skip when an
offset window is still open at the next WP (our offsets were all 0, not
exercised); Pan-Follow -> Track handoff ease.

---

## DELIVERABLES IN /mnt/user-data/outputs/
- TrackPlanPush.bas        - Phase-1 awp/offms tail tokens (Excel repo)
- DJI_Ronin_Giga_v2.ino    - soak-v37: Phase-1 store + arrival stamp + Phase-2
                             WP-event firing (sketch repo)
- BicycleModel.bas         - heading boundary flip to CW-positive (Excel repo)
- HEADING_CONVENTION.md    - single source of truth for the unified frame
- SESSION_SUMMARY_Day30.md - this file

## MISTAKES OWNED THIS SESSION
- "No code to change" when the operator asked to unify the conventions - that
  was true only for the gimbal relative-pan path. Unifying the WHOLE system
  required the cart-side BicycleModel change. Corrected and called out.
- Formatting: handed a macro as bare text, and repeated it, against the
  standing rule (macros in code boxes, test URLs bare). Corrected mid-session;
  hold it going forward.

## PROCESS NOTE
The discipline that worked: read/measure the actual code (sheet cols, executor,
/compass handler, BicycleModel math, DJI docs) before stating anything; lead
with the answer; stop when the operator said stop. Sign conventions were
settled by MEASUREMENT (bench + datasheet), not assertion.


---

## (archived) SESSION_SUMMARY_Day30_FULL.md

# HyperLapse Cart - Session Summary, Day 30 (05 Jun 2026) [FULL]

For future Claude. Read PREFERENCES_CONSOLIDATED.md first. This supersedes the
earlier Day-30 summary (which stopped after the heading unification) - the
session continued into the Execution UI, chart, and pano.

Operator style held all session: SHORT replies, lead with the answer, ONE
thing at a time, MEASURE/READ before theorising, NEVER guess, NEVER change
design limits/parameters/methods on a whim (got pulled up for proposing a
180deg/20-60 axis change - reverted; the operator does not change on a whim).
Pure ASCII (got pulled up for an em-dash literal in ChartPush - fixed).
FORMATTING (reinforced, hold it): macros in CODE BOXES, test URLs as BARE URLs
on their own line. Do NOT suggest ending/pausing the session (got pulled up).
When the operator says "stop", stop. When testing, hold issues/questions until
the operator calls the test done ("talk issues at end of test not during").

---

## HEADLINE
Three big things landed and are HARDWARE-PROVEN:
1. WP-event gimbal coordination (Phases 1-3) - GPs fire on the cart's ACTUAL
   WP arrival, survive nudge/slip. (covered in the earlier Day-30 summary.)
2. Heading convention UNIFIED on the Ronin/standard CW-positive frame
   (E=+90). BicycleModel boundary flip; HEADING_CONVENTION.md is the source of
   truth. (earlier summary.)
3. The Execution screen is BUILT and live on the cart: reassurance ribbon,
   Excel-authored chart with live camera icon, time-ordered WP/GP row list,
   and controls (Start, E-stop, nudge, heading-update stub, Pano).

---

## EXECUTION UI - DESIGN (captured in UI_DESIGN_Execution_v3.md)
Premise: operator is a SPECTATOR. Path/angles/timing are set-and-forget. The
UI is REASSURANCE + two narrow interventions (heading refine; cart-safety
nudge). FOV reality (14mm on full-frame R3 = ~104H x 81V) means a 5-15deg
heading error is post-fixable; a LATE/mis-aimed move is not - so the UI
optimises for catching imminent moves, not heading precision. Time context:
recon -> van (build+push plan) -> long WAIT -> "lights action" Start much
later. So Start lives on the Exec screen, NOT bundled with the push. The cart
stays powered through the wait (plan kept in RAM); Tics de-energise to save
power. One agnostic alert (red row + optional beep) fires for either an astro
GP approaching OR a fast pan approaching (~2min ETA, time-based). Heading
update = button prepopulated with expected (recon floor), operator overrides,
cart computes delta, REPLACES the running offset (not additive - prevents
cumulative drift), forward-only, non-blocking. iOS audio: tap-to-Start unlocks
it; ringer must be ON (checklist); red row is the real signal, beep best-effort.

## EXECUTION UI - BUILD (all on the cart, soak-v44)
- /exec/feed (v38-v44): JSON the screen polls @3s - plan state, live gimbal
  yaw/pitch, time-ordered WP/GP rows with SIMPLE planned-time ETA (reached
  events use the real wp_arrival stamp), ribbon fields (batt/photos/rssi/can,
  cam='?' placeholder), ymin (chart axis), pano phase+pidx. GP state is HONEST
  ('idle' when track unarmed, never a guessed 'done').
- Screen served at /?screen=exec (the exec branch of the shared 3-screen page;
  day palette - NIGHT PALETTE DEFERRED). Ribbon (2 lines: batt/photos/age/rssi
  + cam/CAN), plan-state line, chart, WP/GP row list (earth badge, fast NNdeg
  badge, hdg button on earth GPs), controls.
- Controls wired to real endpoints: START = /btn15 (energise) -> /track/start
  -> /plan/start (confirm; the tap also unlocks iOS audio). E-STOP = /plan/stop
  -> /btn14 (de-energise), instant no-confirm. nudge = /plan/nudge?d=+-100.
  hdg = prompt STUB (real endpoint is the next build). PANO = /gimbal/pano.
- Build-lesson 16 (JS-in-client.println escaping) handled: validated the
  emitted JS bracket/quote balance statically before flashing; survived.

## CHART (Excel authors, Giga moves the icon) - PROVEN
- Architecture (operator's): Excel computes the faithful path at bake and
  authors an inner SVG; the cart stores+serves it and only moves the live
  camera icon. CONTRACT (locked, do not change on a whim): viewBox 0 0 355 90;
  x=(yaw-yaw_min)/450*355; y=90-(pitch-20)/60*90 (pitch 20 bottom..80 top);
  dashed 80deg limit line. 450deg yaw span, 20-80 pitch are the DESIGN.
- Cart (v43): /settings/chartsvg?idx&last&yawmin&d= reassembles + URL-decodes
  (getStr does NOT decode - urlDecode added) chunked SVG into chart_svg; serves
  it; ymin in feed; JS positions #xcam from yaw/pitch/ymin. PROVEN with a
  hand-made SVG.
- Excel (ChartPush.bas, NEW module): PushChartToCart reads Move/Pan-Follow GP
  rows (point = Ry+dyaw, Rp+dpitch), authors blue polyline + dots + gridlines +
  dashed 80, computes yaw_min, chunk-pushes (150 raw chars/chunk, percent-
  encoded; chunk RAW then encode so no %XX split). PROVEN: test plan points
  (0,20)(-100,30)(-180,60)(0,0), yaw_min=-180, 503-char SVG, 4 chunks, rendered
  correctly on the phone. Track/Track-yaw rows skipped (astro charting deferred
  - the extension uses col-H planned heading + AstroPush az/alt samplers).

## PANO - it was JUST a button
Previous Claude had already built the whole pano firmware (state machine
PANO_IDLE..DONE, panoStart/panoTick/panoIssueSlew, /gimbal/pano +
/gimbal/panostatus, plan skipped during pano, offsets {-78,-26,26,78} = 4 shots
centred on current gimbal yaw). Tonight = add a PANO button on the Exec screen
-> /gimbal/pano, + pano phase/pidx in the feed -> now-line 'PANO shot N/4 (plan
paused)'. PROVEN: tapped, swept -77.8/-25.9/+26.2/+78.2, shutter fired each,
logged 4, resumed to trigger pose. NB the gimbal SLEEPS - if /home or pano does
nothing, wake the gimbal first.

---

## DELIVERABLES IN /mnt/user-data/outputs/ (this session, full)
- DJI_Ronin_Giga_v2.ino   - soak-v44 (Phase1-2 WP-event firing, wp_arrival
                            stamp, /exec/feed, Exec screen, chart receiver,
                            idle auto-de-energise, PANO button)
- TrackPlanPush.bas       - Phase-1 awp/offms tail tokens
- BicycleModel.bas        - heading boundary flip to CW-positive
- ChartPush.bas           - NEW: Execution chart author (Move/relative scope)
- HEADING_CONVENTION.md   - single source of truth (unified CW-positive frame)
- UI_DESIGN_Execution_v3.md - Execution screen design (spectator model)
- SESSION_SUMMARY_Day30.md  - the earlier (pre-UI) summary
- SESSION_SUMMARY_Day30_FULL.md - this file

## FIRMWARE STATE
soak-v44 on the cart. New since v34: v35 awp/offms stored on TrackInterval;
v36 wp_arrival_ms stamp in planSegmentEnter; v37 Phase-2 live WP-event interval
selection (trackIntervalOpenAbs); v38 /exec/feed; v39 honest GP feed state;
v40 idle auto-de-energise (energised+vel0+outside-plan, 2min, reset on ENRG/
Start); v41 feed ribbon fields; v42 Exec screen served; v43 chart receiver;
v44 PANO button + feed pano fields.

## NEXT STEPS (operator's order: heading, then the list)
1. HEADING - operator confirmed: build BOTH halves, ENDPOINT FIRST (it is the
   logical foundation; the executor correction has nothing to apply/test until
   the endpoint feeds it a value). Two halves:
   1a. ENDPOINT half (make the hdg button real, self-contained, testable
       alone): push per-WP expected_cart_heading (PlanBuilder ALREADY writes it
       to Plan col H - just send it to the cart); store it cart-side; the Exec
       hdg button posts the operator's REAL heading; cart computes delta and
       stores it as the running offset - REPLACE (not additive), FORWARD-only,
       non-blocking (no input -> planned floor). Test: post a heading, read the
       stored offset/delta back in /exec/feed. NO sign flip (cart+gimbal both
       CW-positive now). NEXT ACTION when resuming: read how col H /
       expected_cart_heading currently flows (PlanBuilder + any push) before
       wiring - do not guess.
   1b. EXECUTOR half (Phase 4 / 3b): trackPlanTick astro path applies
       gimbal_yaw_correction = real_heading - expected_cart_heading to the
       commanded gimbal yaw, EARTH-FRAME GPs ONLY (relative pans + cart path
       stay heading-independent). Testable once 1a exists, ideally in the
       daylight Sun Track run.
2. Then the parked list:
   - Astro chart curves (extend ChartPush: col-H heading + AstroPush az/alt
     samplers; daylight verify).
   - Gimbal UNWIND / cumulative-yaw: a Move takes the SHORTEST path now (can
     wind toward cable tangle). Decide operator-in-plan control (a per-Move
     unwind/direction hint - simple, not auto cable-modelling). MEASURE the
     executor first: does it command cumulative +-450 or wrapped +-180?
   - Live daylight Sun Track WP-anchored run (Phase 4 piece A) - mind the UTC
     epoch consistency (rt0 and /settings/realtime both UTC epoch-ms).
   - SERVO_TO_DEG slip calibration (model over-rotates; controlled test).
   - Pano "same Tv" (uses default 800ms now; wire the live plan Tv).
   - cam CCAPI-alive flag (feed shows '?'; photos-climbing is the alive proxy).
   - Reconcile remaining docs to HEADING_CONVENTION.md (CART_HEADING_DESIGN,
     GIMBAL_EXECUTION_CAPABILITIES, WORKFRONTS, GIMBAL_VIZ, the Day-29
     workfront sec 4, PROJECT_STATE 'design only' line).
   - Night palette for the Exec screen (deferred; standalone shell proves it).
   - LOOP-LONG stalls (1.4-3.0s) around gimbal commands - partly the gimbal
     SLEEPING (wake it). Worth instrumenting if it persists when awake.

## MISTAKES OWNED
- Proposed changing the chart axes (450->180, 20-80->20-60) - the operator does
  NOT change design limits on a whim; reverted to 450/20-80.
- "No code to change" for the convention unification - was true only for the
  gimbal path; the cart BicycleModel needed the flip. (earlier summary.)
- Em-dash literal in ChartPush broke VBA (non-ASCII) - fixed to ASCII content
  test.
- Suggested ending the session / handed macros as bare text - both against
  standing preferences; corrected.

## PROCESS NOTE
Measure the actual code/sheet/datasheet before stating anything; lead with the
answer; one finding at a time; stop when told. Sign conventions and the chart
size were settled by MEASUREMENT, not assertion. The pano was a reminder to
CHECK what previous Claude already built before designing - the whole state
machine existed; the task was one button.


---

## (archived) SESSION_SUMMARY_AND_PREP.md

# HyperLapse — Session Summary + Prep Order

**As of:** 07 Jun 2026 (Day 31). What got built, the order it runs in, and
the "Prep" button idea that chains it. Companion to WORKFRONTS.md and the
per-topic workfront docs.

---

## The goodness (what now exists)

Gimbal Plan View (#2) — the dial:
- `Python/gimbal_planview_v2.py` — renderer. Cart at centre, true-N up,
  radius = altitude. Non-cumulative reference model. Reads moon cols
  defensively. WORKS.
- `Modules/GimbalSweepDir.bas` — proposes col AC sweep direction
  (shortest-path rule); operator accepts/overrides. WORKS.
- `Modules/GimbalPlanViewButton.bas` — the Render Plan View button.
  Fills AC, saves, runs Python, opens PNG. Auto-uses Python\map.png.
  WORKS.
- `Modules/GimbalMapFetch.bas` — fetches a 60km north-up Esri satellite
  tile (keyless, personal use) to Python\map.png. WORKS.

Moon astro:
- `Astro.bas` (GenerateGCTable) — AstroTable now has Moon Az/Alt/above-
  horizon (cols G/H/I). Swapped + compiled.
- `AstroPush.bas` (PushAstroToCart) — pushes moon rise/set
  (mnry/mnrp/mnsy/mnsp). Swapped + compiled. Cart confirmed mask=127.
- Track-path cubic push for moon was already in production.

Docs:
- WORKFRONTS.md updated (Day 31 block at top).
- WORKFRONT_moon_astro.md, WORKFRONT_canon_battery_pause.md,
  GIMBAL_PLANVIEW_REMAINING.md.

---

## Run order (how a shoot gets prepped today)

Sequenced by dependency — each step needs the ones above it:

1. **Get Sunset Time** — sets dataSunriseTime / dataSunsetTime.
2. **Init Shoot** — sets astroDusk / phase times (CCAPI camera optional;
   Tv fallback covers an absent camera).
3. **Generate GC Table** — builds the 15-min astro table incl. moon
   cols G/H/I. (Needs 1+2 for the window.)
4. **Push Astro to Cart** — sun + moon + MW keypoints to the cart
   (needs 3's times; returns mask, expect 127 when moon in window).
5. **Push Track Paths to Cart** — the cubics (sun/moon/MW), production.
6. **Fetch Gimbal Map** — Esri tile to Python\map.png (only when the
   site/location changes; otherwise skip — the file persists).
7. **Render Plan View** — fills col AC, saves, draws the dial (auto-uses
   the map). Operator reviews framing + sweep here.

Note: 6 is location-bound, not nightly. 1-5 are nightly (date-bound).
7 is whenever you want to eyeball the plan.

---

## The "Prep" button idea

One button that calls the above in order, so prep is one press instead of
seven. High-level behaviour:

- Runs steps 1 -> 5 unconditionally (the nightly astro chain).
- Step 6 (map): skip if Python\map.png already exists, OR expose a
  "refresh map" checkbox / separate button for when the site changes.
- Ends on step 7 (Render Plan View) so the operator lands on the dial.
- Each step logs; on any failure, stop and report which step (don't
  push half a chain to the cart).
- Camera/CCAPI absence is NOT a failure (Tv fallback) — Prep should
  tolerate it, since the rig is often apart during planning.

Open design questions (decide at build time):
- Does Prep require the cart online (steps 4/5 push)? If the cart's not
  up, should Prep do 1-3 + 7 (Excel-only) and skip/flag 4-5? A
  "cart online?" check up front would make Prep safe whether or not the
  GIGA is connected.
- Re-run safety: all steps are idempotent (recompute + overwrite), so
  pressing Prep twice is harmless — confirm that holds for the cart
  pushes.

---

## Remaining (not in Prep yet — separate workfronts)

- **Cable strip (view #3)** — own page. Unwraps yaw from col AC
  (CW/CCW), plots min -> min+450 axis, shows used span + headroom, max-
  wind GP. Shared unwrap step feeds both the strip and the dial's sweep
  arrows. Prev/next buttons step GP-by-GP for the reach check. Operator
  uses dial and/or strip to accept/reject the macro's AC proposal.
- **Fix #11 validation chart** — still uses the old cumulative model;
  cable numbers wrong. Re-base on the non-cumulative + col-AC unwrap.
- **Moon step 5 (firmware)** — below-horizon goto-rise-and-wait in the
  cart executor.
- **Canon overnight power** — battery-swap pause fallback.
- Update GIMBAL_PLANVIEW_BUILD.md to the non-cumulative + col-AC model.

When the cable strip exists, it slots into the Prep order after Render
(or as a second output of the same render press).
