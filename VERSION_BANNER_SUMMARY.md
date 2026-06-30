# DJI_Ronin_Giga_v2 — Version Banner Summary

| Version | Description |
|---|---|
| v261 (30 Jun) | WiFi moved off the field AP back to the bench `Rosedale` .1.x (cart .1.97, has internet); wired camera CCAPI .20.99 unchanged. |
| v260 (29 Jun) | Manual LUM testshot now retries the flipdetail read on any failure, surviving the 503 "Device busy" race after a cold liveview start. |
| v259 | Dark-window exposure LATCH moved to the top of `meterAndAdjustLive` so it holds even when the luminance fetch fails. |
| v258 | LUM walk steps one way per twilight wing (brighten at sunset, darken at sunrise) and LATCHES between astro dusk/dawn so transient light can't move the night exposure. |
| v256 | Added GET `/exposure/phase` exposing `lumPhaseSelect()`'s live target/side decision without running a plan. |
| v255 | Cart picks the LUM target from its own clock vs two pushed astro epochs (`/exposure/epochs`, `/exposure/check`), with `xstart()` gating on readiness. |
| v254 | Hygiene pass: deleted ~110 lines of now-uncalled TABLE-mode machinery after the functional removal was field-proven. |
| v253 | Removed the open-loop clock-driven TABLE fallback from the live path — on a meter/CCAPI fail the walk now HOLDS + ALARMs + RESUMEs. |
| v252 | Black-box pattern: the 1 Hz RAM ring runs from boot and freezes a pre-fault snapshot to the SD soak file on a half-open confirm. |
| v251 | Runtime toggle `/halfopen/kick?on=0\|1` so the half-open recovery is provable on/off against the same forced AP drop. |
| v250 | Silence-gated gateway ping detects the associated-but-dead window and forces a disconnect so the existing reconnect re-associates. |
| v249 | Added a 1 Hz RAM ring plus `/halfopen` routes to fingerprint a half-open (associated-but-dead) UI death after the fact. |
| v248 (28 Jun) | Reverted the v200 Rosedale move back to the field `RosedaleVan` AP on .20.x. |
| v247 (28 Jun) | `soakHeartbeat` now checks the write byte-count so a dead/pulled SD card is detected and surfaced as `soak:DEAD`. |
| v246 (28 Jun) | `/soak/list` keeps fixed-size state so it can no longer exhaust the heap past ~99 files. |
| v245 (28 Jun) | The http-thread monitor line is mirrored to the soak file so a `:80` wedge is captured headless. |
| v244b (27 Jun) | LUM meter-rate trigger changed to a direct flag (not a modulo remainder) so it needs no interval divisibility. |
| v244 | LUM meter rate adapts to cadence (every photo at ≥5 s beats) so the Tv/ISO walk can keep up with sunrise. |
| v243 | Exec ribbon line 2 reworked to CAM/Gimbal ok-nok, LUM measured/target, and soak file number. |
| v242 | Exec ribbon line 3 shows current Tv/ISO/cadence in place of the battery readout. |
| v241 | Added the `/gimbal/check` arm-guard against the power-up homing snap, and fixed the `RawClient::stop()` socket-pool leak (the real WiFi non-recovery bug). |
| v233 (26 Jun) | Backed out the v231/v232 RSSI-floor half-open kick because it fought `wifiReconnectTick`'s design and thrashed at marginal RSSI. |
| v231 (26 Jun) | Re-enabled the half-open detector, triggered by RSSI ≤ -85 dBm held for 20 s, to force a reconnect. |
| v230 (26 Jun) | `/soak/summary` now prints the requested file (not the current one), and the RSSI half-open floor became a live-settable runtime global. |
| v229 (26 Jun) | Exec START checks `/camera/check` first and refuses to arm if the camera isn't on the wired link. |
| v228 (26 Jun) | New `/camera/check` route runs a live CCAPI-root reachability test over the wire. |
| v227 (26 Jun) | Reachability probe switched from `WiFi.ping` (wrong interface for the wired camera) to a CCAPI GET so it agrees with the fire path. |
| v226 (26 Jun) | Main-loop monitor counts served/accept-streak/err to adjudicate pool leak vs thread wedge vs WiFi drop after `:80` dies. |
| v225 (26 Jun) | Reverted the v224 restart — the watchdog now only logs staleness, never restarts, rebinds, or touches the socket. |
| v224 (26 Jun) | Thread-only http restart without rebinding `:80` to recover a wedged server thread. |
| v223 (26 Jun) | Widened `LUM_TARGET_DEADBAND` from 5 to 6 counts for more headroom against a second Tv step. |
| v222 (26 Jun) | `lum_mode` decided per-meter by lum-vs-target instead of by phase, so the walk tracks rather than fights the target. |
| v221 (26 Jun) | Moved CCAPI to the wired W5500, restored CCAPI-first fire, and restored every-3rd pre-fire LUM metering. |
| v220 (26 Jun) | `firePhoto` fires only on the D7 hardware pulse (WiFi-independent) and metering went time-gated at 60 s. |
| v219 (25 Jun) | Re-anchor the shutter beat to actual completion after a CCAPI stall, giving one long gap instead of a catch-up burst. |
| v218 (25 Jun) | Comms leaves NORMAL only after 3 consecutive CCAPI connect fails so a single blip doesn't cry "camera off." |
| v217 (25 Jun) | `can_tx_enabled` boots true again (transmit/pose restored) with the TX-error spam moved behind its own log flag. |
| v216 (25 Jun) | The three `[httpx]` thread prints gated behind `httpx_log_enabled` so serial is quiet in steady state. |
| v215 (25 Jun) | Restored the Exec START JS function that had been silently dropped, plus a sock-open retry for momentary pool-full. |
| v214 (25 Jun) | Manual testshot reads luminance off the live-view histogram (no capture), dropping it from ~1.2 s to ~100 ms. |
| v213 (25 Jun) | Cable-screen pollers chained into one 2 s socket-at-a-time poller to stop the -3005 storm on refresh. |
| v212 (25 Jun) | Testshot worker clears `pending` last so the UI distinguishes in-progress from done and stops showing false LUM err. |
| v211 (25 Jun) | Diagnostic logging of the served testshot result/pending to locate the UI-side false-err. |
| v210 (25 Jun) | Removed the v207 free-slots probe that was itself draining the pool into a -3005 storm. |
| v209 (25 Jun) | Testshot latches and returns instantly, with fire/fetch done in the main loop so the accept loop never blocks. |
| v208 (25 Jun) | Gimbal-screen's three pollers chained into one 3 s poller so page load opens at most one connection. |
| v207 (25 Jun) | Diagnostic that probes free socket slots at each accept error to measure the exhaustion mechanism. |
| v206 (25 Jun) | Bisected the 3-day regression to the v192 watchdog's rebind leak and made the watchdog observe-only. |
| v205 (25 Jun) | `srv.listen(1)` frees one of the 4 mbed pool slots so the testshot's outbound CCAPI socket always fits. |
| v204 (25 Jun) | Reverted the v203 accept-socket delete that double-freed and hung the cart; back to close-only. |
| v203 (25 Jun) | Added a delete on the accepted socket after each request (later proven wrong in v204). |
| v202 (25 Jun) | Boot-time servo sweep to make steering pin D5 observable instead of guessed. |
| v201 (25 Jun) | Compiled out the v198 watchdog that self-inflicted disconnects during ICMP-only `net_probe` runs. |
| v200 (24 Jun) | Moved the rig to the `Rosedale` AP on .1.x to take the AX6000 out of the WiFi-drop investigation. |
| v199 (24 Jun) | `can_tx_enabled` boots false to silence CAN TX spam during drop capture (later found hazardous). |
| v198 (24 Jun) | Diagnostic that forces a reconnect when no HTTP request arrives for 45 s while status reads CONNECTED. |
| v197 (24 Jun) | Restored the boot WiFi-scan line and the httpx accept-err print. |
| v196 (24 Jun) | `wifiReconnectTick` prints scan result, AP visibility, and each reconnect attempt. |
| v195 (24 Jun) | Battery poll skips unless comms is already healthy so it never pays the blocking CCAPI connect freeze. |
| v194 (24 Jun) | Manual testshot clears `camera_reachable` so a stale latch doesn't permanently block it. |
| v193 (24 Jun) | `initExposureFromCamera` retries the tv/iso read up to 5× so transient contention doesn't disable the walk all shoot. |
| v192 (24 Jun) | Main-loop watchdog restarts the http thread when it stops cycling (later found to be the rebind-leak culprit). |
| v191 (24 Jun) | Per-request trace plus a 5 s idle heartbeat to isolate a browser UI hang. |
| v190 (24 Jun) | `/soak/list` and `?file=` named reads so any prior run is retrievable over WiFi. |
| v189 (22 Jun) | Exec UI LUM-target button became the single walk target with a ±5 deadband. |
| v188 (22 Jun) | Soak files cycle `SOAK_001..999` round-robin so the card never fills. |
| v187 | Stripped diagnostic trace (httpx accept-err, boot-scan, reconnect prints). |
| v186 | Cart battlow threshold pushed from Excel and echoed in `/exec/feed`. |
| v184 | The Move endpoint releases the photo cadence (clears first-acquire-hold). |
| v183 | CCAPI reachability gate (flag read at a chokepoint; #36d probe is the sole ping source). |
| v175–v179 | WiFi runtime reconnect on dead-time slots, scan-gated. |
| v174 | Cold-start tuned. |
