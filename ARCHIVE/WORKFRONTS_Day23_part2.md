# WORKFRONTS.md — Day 23 (part 2) update

**Paste above the Day-23 (part 1) update block.**

---

## Day 23 (part 2) update (29 May 2026) — Soak instrument built

- **#63 multi-hour soak — INSTRUMENT BUILT + VALIDATED; run pending.**
  On-cart soak harness complete and proven end-to-end (log shows all
  200s; camera Tv alternating 0"5/0"4; card images alternating
  0.5/0.4s). Components: microSD CSV logger on the W5500 shield
  (CS=D4), behind `#define SOAK_LOG`; per-CCAPI-call rows + mode-flip
  + RSSI heartbeat; non-fatal SD; auto-incrementing SOAK_NNN.CSV.
  Soak MODE (`/soak/start?ms=N` / `/soak/stop`): per frame PUT Tv
  (alternating) + GET every 3rd + CCAPI photo; no TABLE-fallback so
  dropouts stay visible. Read-back over WiFi via `/soak/info` and
  `/soak/tail`. REMAINING: run the 4h soak on the van AX6000, then 12h.

- **Servo D4 -> D5 — DONE.** Moved to free D4 for the shield's
  hard-wired SD CS. D5 is PWM-valid (Giga PWM range 2-13). Re-tested
  good. Servo wire physically moved.

- **Tv-value + busy-collision lessons (folded into soak mode):**
  Canon Tv must use seconds notation `0"5`/`0"4` (not `0.5`) — send
  via `ccapiPutTv`. PUT a setting only on an idle camera (not right
  after a shutter press) or it 503s. Both now correct in soak mode.

- **NEW gotcha — silent failed Giga upload.** Compile OK but board
  keeps old binary; new handlers missing while old ones work. Boot
  `[build] vN` marker added to detect it; bump each edit. (Capture in
  PREFERENCES build lessons.)

- Camera moved off home WiFi (Rosedale) onto van AX6000 addressing for
  the soak: cart .20.97, camera .20.99 (wired .20.98 reserved).
  WiFi/wired-CCAPI will not coexist — transport chosen after testing.
