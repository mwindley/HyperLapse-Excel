#!/usr/bin/env python3
"""
wifi_hammer.py - RosedaleVan (AX6000) link approval hammer
Target: bench Giga running soak_wifi_trial.ino at 192.168.20.97

PURPOSE
  Approve or condemn the router by SUSTAINING the real cart load against
  the bench Giga and catching every gap with a timestamp. The cart screens
  poll every 2-3s, serialized one socket at a time (firmware v208/v213), so
  the DEFAULT here is one /ping every 2s - the real demand, not a flood.
  Throughput saturation is not the suspected fault; a drop over hours at
  field RSSI is.

TEST BAR  "if you can't cause it you haven't solved it"
  A clean run does NOT approve the router on its own - it must be run at
  FIELD placement/distance (RSSI -60..-75), not bench -13, and ideally warm.
  The hammer's job is to CATCH a fault if one exists and attribute it:
    - hammer gap + Giga /stats link_drops++   -> link actually dropped
    - hammer gap + /stats drops=0 + RSSI ok    -> router :80 stall (router)
    - RSSI collapse in /stats                  -> Giga radio / range (not router)

USAGE
  python wifi_hammer.py                 # 2s cadence, runs until Ctrl-C
  python wifi_hammer.py --interval 2    # explicit
  python wifi_hammer.py --fast          # 50ms stress pass (optional, not real load)
  python wifi_hammer.py --hours 10      # bounded overnight run
  python wifi_hammer.py --host 192.168.20.97

OUTPUT
  Console: live line per fault only (clean pings are silent past the first).
  Log file: wifi_hammer_YYYYMMDD_HHMMSS.csv - every request, ts/seq/ms/rssi/result.
  Summary at end (and on Ctrl-C): total, ok, fails, timeouts, loss%, latency
  min/avg/max/p95, counter-skips, and the Giga-side /stats verdict.
"""

import argparse, csv, datetime, statistics, sys, time, urllib.request, urllib.error, json

def now():
    return datetime.datetime.now()

def ts():
    return now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

def get_text(url, timeout):
    # Link-hold test: success = HTTP 200 with a non-empty body. The cart
    # /heartbeat route returns "OK" (not JSON), so we do NOT json-parse.
    # An empty body on a live connection is a FAIL (server answered blank).
    t0 = time.perf_counter()
    with urllib.request.urlopen(url, timeout=timeout) as r:
        raw = r.read().decode("utf-8", "replace")
    dt = (time.perf_counter() - t0) * 1000.0
    if not raw.strip():
        raise ValueError("empty body")
    return raw, dt

def fetch_stats(host, timeout):
    # Real cart firmware has no /stats route (that was the trial sketch).
    # The cart's own soak CSV is the inside witness now.
    return {"error": "no /stats on cart firmware - use cart soak CSV"}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.20.97")
    ap.add_argument("--interval", type=float, default=2.0, help="seconds between pings (default 2 = cart cadence)")
    ap.add_argument("--fast", action="store_true", help="50ms stress pass (NOT real cart load)")
    ap.add_argument("--hours", type=float, default=0.0, help="stop after N hours (0 = until Ctrl-C)")
    ap.add_argument("--timeout", type=float, default=5.0, help="per-request timeout seconds")
    ap.add_argument("--stats-every", type=int, default=60, help="pull Giga /stats every N pings")
    args = ap.parse_args()

    interval = 0.05 if args.fast else args.interval
    host = args.host
    ping_url = f"http://{host}/heartbeat"

    fname = "wifi_hammer_" + now().strftime("%Y%m%d_%H%M%S") + ".csv"
    f = open(fname, "w", newline="")
    w = csv.writer(f)
    w.writerow(["timestamp", "seq", "result", "latency_ms", "giga_n", "rssi", "note"])

    print(f"[hammer] target {ping_url}")
    print(f"[hammer] interval {interval}s, timeout {args.timeout}s, log {fname}")
    print(f"[hammer] {'STRESS pass (not real load)' if args.fast else 'cart-cadence pass'} - Ctrl-C to stop\n")

    # No baseline stats route on cart firmware (was trial-sketch /stats).
    # The cart's own soak CSV is the inside witness.

    sent = ok = fails = timeouts = skips = 0
    latencies = []
    last_giga_n = None
    rssis = []
    t_start = time.time()
    stop_at = t_start + args.hours * 3600 if args.hours > 0 else None

    try:
        while True:
            if stop_at and time.time() >= stop_at:
                print(f"\n[hammer] reached {args.hours}h limit")
                break
            sent += 1
            note = ""
            seq = sent
            try:
                body, dt = get_text(ping_url, args.timeout)
                ok += 1
                latencies.append(dt)
                w.writerow([ts(), seq, "ok", f"{dt:.1f}", "", "", note])
                # periodic stats cross-check
                if args.stats_every and sent % args.stats_every == 0:
                    print(f"{ts()}  [progress] ok={ok} loss={(fails+timeouts)/sent*100:.2f}% "
                          f"lat_avg={statistics.mean(latencies):.0f}ms")
            except urllib.error.URLError as e:
                reason = getattr(e, "reason", e)
                if isinstance(reason, TimeoutError) or "timed out" in str(reason).lower():
                    timeouts += 1
                    note = "TIMEOUT"
                else:
                    fails += 1
                    note = f"FAIL {reason}"
                print(f"{ts()}  seq={seq}  {note}")
                w.writerow([ts(), seq, "fail", "", "", "", note])
            except Exception as e:
                fails += 1
                note = f"FAIL {type(e).__name__} {e}"
                print(f"{ts()}  seq={seq}  {note}")
                w.writerow([ts(), seq, "fail", "", "", "", note])
            f.flush()
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[hammer] stopped by operator")

    f.close()
    dur = time.time() - t_start

    print("\n" + "=" * 60)
    print("HAMMER SUMMARY")
    print("=" * 60)
    print(f"duration      {dur/3600:.2f}h ({dur:.0f}s)")
    print(f"sent          {sent}")
    print(f"ok            {ok}")
    print(f"fails         {fails}")
    print(f"timeouts      {timeouts}")
    loss = (fails + timeouts) / sent * 100 if sent else 0
    print(f"loss%         {loss:.3f}%")
    print(f"counter-skips {skips}   (Giga served out of sequence = mid-serve drop)")
    if latencies:
        latencies.sort()
        p95 = latencies[int(len(latencies) * 0.95)] if len(latencies) > 1 else latencies[0]
        print(f"latency ms    min {min(latencies):.1f}  avg {statistics.mean(latencies):.1f}  "
              f"max {max(latencies):.1f}  p95 {p95:.1f}")

    print("-" * 60)
    print("INSIDE WITNESS = the cart's own soak CSV (not /stats - that was the")
    print("trial sketch). Cross-check this run's fail timestamps against the cart")
    print("soak log:")
    print("  hammer gap + cart soak logged CLEAN  = laptop/path side, not the AP")
    print("  hammer gap + cart soak shows a drop   = real link drop (AP/range)")
    print(f"\nlog: {fname}")

if __name__ == "__main__":
    main()
