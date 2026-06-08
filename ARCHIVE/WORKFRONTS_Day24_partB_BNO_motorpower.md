# WORKFRONTS.md — Day 24 (part B) — #40 BNO stalls under motor power (CAUSE LOCALISED)

**Append to the #40 Day-24 findings notes (after IMU_methodproven).
Build progression this session: soak-v13b → v14 (Phase-A ease) →
v15 (3a anchor instrumentation) → v15a (/debug/imu gate probe).
Ry=Cy holds throughout.**

---

## Session wins (gimbal Steps 2 + 3a)

- **Step 2 — Phase-A ease-onto-curve: BUILT + PROVEN (soak-v14).**
  Executor now eases from its actual pose ONTO the live real-time cubic
  over a pushed `acquire_ms` (smoothstep), instead of snapping. Proven
  on hardware: parked at y=-73.5, armed with acquire=8000 → smooth ~8 s
  glide onto the curve, `[track] acquire done -> tracking`, no snap.
  Cart stays dumb (one pushed ms value; no astronomy, no profile math).
  `acquire_ms` rides on the TrackInterval; absent/0 = legacy snap.
  Late-start self-correction unchanged (target read live each tick).
- **Step 3a — anchor heading-sample instrumentation: BUILT + VERIFIED
  (soak-v15/v15a).** `PlanSegment` gains an `anchor` flag (optional `a`
  token in the s-string, tail position, order-independent with the
  transition token, append-per-build-lesson-12). While in an anchor
  segment the cart samples BNO `true_yaw` + cal byte to CartLog `A`
  events every 500 ms (record-only — Ry=Cy holds). `CartLogEntry`
  gained an `aux` tail column (cal; `value` carries true_yaw×10) so old
  index parsers stay intact. Verified end-to-end: live read tracks a
  real ~55° rotation, cal byte logged faithfully. **3a did its job — it
  surfaced the hardware problem below.**

---

## #40 BNO085 — stream STALLS when main/motor power energises (Day 24 pt B)

**Symptom:** the BNO SHTP rotation-vector stream goes silent and does
NOT self-recover (needs a power-cycle) whenever main/motor power is
energised. With main off it streams perfectly.

**Controlled test — single variable = main/motor power (no power-cycle
between the two halves, so no enumeration confound):**
- **Main OFF, USB on (known-good baseline):** `last_poll_ms_ago` small
  (40, 125), `yaw_raw` tracks rotation (118.7→155.3°), `cal` 3. Live.
- **Flip main ON (motors energised-holding):** the SAME just-verified
  stream stalls — `last_poll_ms_ago` 6647 → 13812 (climbing in lockstep
  with real time = no completed read), `yaw_raw` frozen at 113.4°.
- Earlier run with **USB IN + main ON** also stalled (last_poll climbing
  ~8 s/read). So clean USB 5V being present did NOT keep it alive.

**Conclusion (measured, not inferred):** energising the motor power
domain kills a known-good BNO stream. Ruled out: enumeration/boot
intermittency (stream was confirmed live immediately before), and
GIGA-input brownout / USB sag (USB was present and it still died — so a
steadier GIGA supply is NOT the fix).

**The Tic asymmetry (key clue):** the Tics sit on the SAME shared I²C
bus and keep working under full load (cart drives, `/status` reads).
Only the BNO dies. Two reasons this fits:
- **Protocol fragility.** Tic = short, stateless register reads; the
  SparkFun Tic lib shrugs off a corrupted read (bad value / retried
  next loop, unnoticed among thousands). BNO = stateful, sequence-
  numbered SHTP packet stream — one corrupted header/seq wedges the
  WHOLE stream until reset. Same bus noise the Tics ignore is fatal to
  the BNO.
- **NOT proximity.** The BNO is FURTHER from the motors (50 cm) than the
  GIGA/Tic enclosure (25 cm). If raw radiated motor field were the
  agent the closer Tics would suffer first. They don't.

**The standout asymmetry — cable.** Tic I²C branch = 7 cm; BNO branch =
**30 cm**, both Y-cables off the shared bus with pull-ups to 3.3 V, and
**all UNSHIELDED / untwisted**, carrying SDA/SCL + 5V/GND together. A
30 cm unshielded stub has ~4× the pickup loop and capacitance of the
7 cm Tic run: more coupled noise when motor power switches, AND softer
I²C rising edges (pull-ups fighting more cable capacitance over 30 cm).
That is the prime suspect for why the long BNO branch is the fragile one.

**NOT yet determined (reserve for scope):** whether the coupling is onto
the **I²C lines** or onto the **BNO 5V** — the unshielded run degrades
both equally, and the 5V rides the same 30 cm. Discriminator: scope
SDA/SCL and the BNO 5V at the sensor end at the moment main energises.
Kit is currently packed — this is the unpack-the-scope job. (We have a
logic analyser + multimeter on hand when unpacked.)

## Fix tiers (cheapest first — try before the scope)

**Tier 1 — cheap, reversible, no rewire:**
- Stronger (lower-value) pull-up on the BNO branch to stiffen the I²C
  rising edges over 30 cm.
- Local 5V decoupling at the BNO end (bulk + ceramic) against supply
  dip/noise arriving over the long run.
- Then RE-RUN the main-ON transition test. If the stream survives
  motors-energised with just these, it's fixed without a rewire.

**Tier 2 — structural (if Tier 1 doesn't hold):**
- Twist the SDA/SCL pair (and ideally 5V/GND); shorten and/or shield the
  30 cm run.
- Or give the BNO its **own short dedicated I²C bus** — Giga R1 has 3
  I²C buses; use the dedicated **SDA1/SCL1** pair (has its own pull-ups).
  NOT the D8/D9 bus (no internal pull-ups — would need external).
  Reframed motivation: not for *contention* (the bus mostly works) but
  to replace a 30 cm noisy shared stub with a short clean dedicated one.
  **Caveat: a separate bus helps ONLY if the coupling is onto the I²C
  lines. If it's onto the BNO 5V, the bus move does nothing** — hence
  scope first before committing to the rewire.

## Step-3 status

- **3a (anchor heading-sample instrumentation): DONE + verified.**
- **3b (fold `gimbal_yaw_correction = (−true_yaw) − expected_cart_heading`
  into earth-frame gimbal cubics): BLOCKED on the electrical fix above,
  NOT on code.** The correction cannot be trusted until the BNO survives
  motors running — a heading read that stalls under load would feed
  garbage into gimbal yaw. Resolve the motor-power stall, then build 3b.
- `expected_cart_heading` deliberately NOT added to the stream yet (3a is
  pure instrumentation; the moving/turning-read question made a per-
  segment scalar premature — revisit in 3b with real anchor data).

## Cal-byte aside (single data point, not a conclusion)

The byte reached **3** with main OFF (idle, off-plane orientation during
handling). The IMU_methodproven "mounted cart sits at 0–1" concern is
about the LIVE electrical/magnetic environment — consistent, since this
3 was with motor power removed. Shows the byte CAN reach 3 on the
assembled cart. Heading vs iPhone NOT validated this session
(`offset_set` was false throughout — no true-north capture done).

## Open / next

- Electrical: Tier-1 fix attempt, then scope to split lines-vs-5V.
- The recurring favicon/empty-request LOOP-LONG stalls (1.6–2.6 s) still
  present; harmless with camera off, still needs a request-read timeout
  before a live shoot.
- Once BNO survives motors: build 3b, then Step 4 (pan-follow), then the
  leftover previewplan / Move-cubic Stage-4 Excel pushers.
