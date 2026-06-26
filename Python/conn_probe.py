#!/usr/bin/env python3
"""
conn_probe.py  --  WiFi connectivity probe + #937 evaluation, laptop-side.

The known-good CONTROL: the same connect-timing loop the Giga/Uno sketches run,
but in Python on the laptop (#937: "Python on Mac no problem"). If the Giga
freezes on the identical loop while this stays flat -> the fault is the mbed
stack, not the network.

Does three things to ONE timestamped CSV (conn_probe.csv):
  1. CONNECT-TIMING rate sweep  - connect to a target at each gap (500ms..10s),
     20 per gap, time connect/send/ttfb/drain, record bytes declared vs read.
     Mirrors the sketch sweep so laptop and board line up.
  2. DRAIN toggle               - --drain reads the body fully (firmware-like);
     --no-drain closes early to provoke the #937 undrained leak.
  3. PING watchers (background)  - continuous ping to gateway AND camera, 1/s,
     so any board/laptop freeze can be aligned to which leg lost packets.

Stdlib only. Run on the laptop on Rosedale.

USAGE (defaults match the sketches):
  python conn_probe.py --target camera          # camera .1.99:8080, with GET
  python conn_probe.py --target gateway         # gateway .1.1:80, connect-only
  python conn_probe.py --target camera --no-drain   # provoke #937 leak
  python conn_probe.py --target camera --ip 192.168.1.99 --port 8080

Watch conn_max per gap in the printed PERGAP summary at the end (and the CSV).
#937 predicts slow/fail at gap<=4000 and clean at >=5000 - on the BOARD. On
this laptop it should be flat at ALL gaps (that's the point of the control).
"""

import argparse, socket, time, csv, threading, subprocess, sys, platform, re

GAP_SWEEP_MS   = [500, 1000, 2000, 3000, 4000, 5000, 10000]
TRIES_PER_GAP  = 20
CONN_TMO_S     = 2.0
GET_PATH       = "/ccapi/ver100/shooting/settings/tv"
GATEWAY_IP     = "192.168.1.1"
CAMERA_IP      = "192.168.1.99"

# ---------- ping watchers (background) ----------
_ping_lock = threading.Lock()
_ping_state = {}          # ip -> (last_ms, lost_bool, ts)
_stop = threading.Event()

def _ping_once(ip):
    """One ping, return latency ms or None if lost. Cross-platform."""
    is_win = platform.system().lower().startswith("win")
    cmd = (["ping", "-n", "1", "-w", "1000", ip] if is_win
           else ["ping", "-c", "1", "-W", "1", ip])
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return None
    m = re.search(r"time[=<]\s*([\d.]+)\s*ms", out)
    if m:
        return float(m.group(1))
    return None

def _ping_loop(ip):
    while not _stop.is_set():
        ms = _ping_once(ip)
        with _ping_lock:
            _ping_state[ip] = (ms, ms is None, time.time())
        _stop.wait(1.0)

def ping_snapshot(ip):
    with _ping_lock:
        return _ping_state.get(ip, (None, None, 0))

# ---------- one connect (the measured event) ----------
def one_connect(ip, port, issue_get, drain):
    """Returns a dict of measurements for one connect."""
    r = dict(connect_ms=0, send_ms=0, ttfb_ms=0, drain_ms=0, total_ms=0,
             bytes_sent=0, content_length=-1, bytes_read=0, drained=0,
             errno=0, ok=0, local_port=0)
    t0 = time.time()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(CONN_TMO_S)
    try:
        tc = time.time()
        s.connect((ip, port))                       # THE call under test
        r["connect_ms"] = int((time.time() - tc) * 1000)
        r["ok"] = 1
        try:
            r["local_port"] = s.getsockname()[1]
        except Exception:
            pass

        if issue_get:
            req = (f"GET {GET_PATH} HTTP/1.1\r\nHost: {ip}:{port}\r\n"
                   f"Connection: close\r\n\r\n").encode()
            ts = time.time()
            s.sendall(req)
            r["send_ms"] = int((time.time() - ts) * 1000)
            r["bytes_sent"] = len(req)

            if drain:
                tr = time.time()
                first = None
                buf = b""
                cl = -1
                body = 0
                hdr_done = False
                while time.time() - tr < CONN_TMO_S:
                    try:
                        chunk = s.recv(1024)
                    except socket.timeout:
                        break
                    if not chunk:
                        break
                    if first is None:
                        first = time.time()
                        r["ttfb_ms"] = int((first - ts) * 1000)
                    if not hdr_done:
                        buf += chunk
                        i = buf.find(b"\r\n\r\n")
                        if i >= 0:
                            hdr_done = True
                            head = buf[:i].decode(errors="replace").lower()
                            m = re.search(r"content-length:\s*(\d+)", head)
                            if m:
                                cl = int(m.group(1))
                            body += len(buf) - (i + 4)
                    else:
                        body += len(chunk)
                    if cl >= 0 and body >= cl:
                        break
                r["drain_ms"] = int((time.time() - tr) * 1000)
                r["content_length"] = cl
                r["bytes_read"] = body
                r["drained"] = 1 if (cl >= 0 and body >= cl) else 0
            else:
                r["drained"] = 0           # #937 provocation: close without reading
    except socket.timeout:
        r["errno"] = -1                    # timed out (= the freeze, if connect)
    except OSError as e:
        r["errno"] = e.errno or -2
    finally:
        try:
            s.close()
        except Exception:
            pass
    r["total_ms"] = int((time.time() - t0) * 1000)
    return r

# ---------- main sweep ----------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=["camera", "gateway"], default="camera")
    ap.add_argument("--ip", default=None)
    ap.add_argument("--port", type=int, default=None)
    ap.add_argument("--drain", dest="drain", action="store_true", default=True)
    ap.add_argument("--no-drain", dest="drain", action="store_false")
    ap.add_argument("--out", default="conn_probe.csv")
    ap.add_argument("--watch", type=int, default=0,
                    help="ping-only watcher mode: ping camera+gateway every 500ms "
                         "for N seconds, log to watch CSV. Run this on the laptop "
                         "WHILE the Giga/Uno sweep, so camera-ping covers their "
                         "freeze moments. No connects - just the ping timeline.")
    args = ap.parse_args()

    if args.target == "camera":
        ip = args.ip or CAMERA_IP
        port = args.port or 8080
        issue_get = True
    else:
        ip = args.ip or GATEWAY_IP
        port = args.port or 80
        issue_get = False
    if args.ip:
        ip = args.ip
    if args.port:
        port = args.port

    # ---- WATCH MODE: ping-only timeline, no connects ----
    # Run this on the laptop WHILE the boards sweep. Pings camera+gateway every
    # 500ms for --watch seconds to watch_camera.csv. Then align the camera-ping
    # losses against the Giga/Uno dump freeze rows (by wall-clock).
    if args.watch > 0:
        out = "watch_camera.csv"
        print(f"WATCH mode: pinging camera({CAMERA_IP}) + gateway({GATEWAY_IP}) "
              f"every 500ms for {args.watch}s -> {out}")
        print("start the Giga/Uno sweeps NOW so their freezes fall in this window.")
        wrows = []
        t_end = time.time() + args.watch
        while time.time() < t_end:
            cam = _ping_once(CAMERA_IP)
            gw  = _ping_once(GATEWAY_IP)
            now = time.time()
            wrows.append({"ts": f"{now:.3f}", "wall": time.strftime("%H:%M:%S"),
                          "cam_ping_ms": cam, "cam_lost": 1 if cam is None else 0,
                          "gw_ping_ms": gw, "gw_lost": 1 if gw is None else 0})
            tag = ""
            if cam is None: tag = "  <<< CAMERA LOST"
            elif cam > 500: tag = "  <<< camera slow"
            print(f"{time.strftime('%H:%M:%S')} cam={cam} gw={gw}{tag}")
            time.sleep(0.5)
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["ts","wall","cam_ping_ms","cam_lost","gw_ping_ms","gw_lost"])
            w.writeheader(); w.writerows(wrows)
        lost = sum(1 for r in wrows if r["cam_lost"])
        print(f"\nwrote {len(wrows)} pings to {out}. camera lost on {lost} pings.")
        return

    print(f"target={ip}:{port} issue_get={issue_get} drain={args.drain} out={args.out}")
    print("starting ping watchers (gateway + camera)...")
    for w in (GATEWAY_IP, CAMERA_IP):
        threading.Thread(target=_ping_loop, args=(w,), daemon=True).start()
    time.sleep(1.2)   # let first pings land

    rows = []
    fields = ["ts", "gap_ms", "i", "connect_ms", "send_ms", "ttfb_ms", "drain_ms",
              "total_ms", "bytes_sent", "content_length", "bytes_read", "drained",
              "errno", "ok", "local_port",
              "gw_ping_ms", "gw_lost", "cam_ping_ms", "cam_lost"]

    for gap in GAP_SWEEP_MS:
        for i in range(TRIES_PER_GAP):
            r = one_connect(ip, port, issue_get, args.drain)
            gw = ping_snapshot(GATEWAY_IP)
            cam = ping_snapshot(CAMERA_IP)
            row = {
                "ts": f"{time.time():.3f}", "gap_ms": gap, "i": i,
                **{k: r[k] for k in ["connect_ms","send_ms","ttfb_ms","drain_ms",
                   "total_ms","bytes_sent","content_length","bytes_read","drained",
                   "errno","ok","local_port"]},
                "gw_ping_ms": gw[0], "gw_lost": 1 if gw[1] else 0,
                "cam_ping_ms": cam[0], "cam_lost": 1 if cam[1] else 0,
            }
            rows.append(row)
            flag = ""
            if r["connect_ms"] > 500 or r["errno"]: flag = "  <<< SLOW/FAIL"
            print(f"gap={gap:>5} i={i:>2} conn={r['connect_ms']:>5}ms "
                  f"ttfb={r['ttfb_ms']:>4} body={r['bytes_read']:>5}/{r['content_length']:<5} "
                  f"drained={r['drained']} errno={r['errno']} "
                  f"gw={gw[0]} cam={cam[0]}{flag}")
            time.sleep(gap / 1000.0)

    _stop.set()

    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    # PERGAP summary (the #937 readout)
    print("\nPERGAP: gap_ms n ok fail slow conn_max undrained")
    for gap in GAP_SWEEP_MS:
        g = [r for r in rows if r["gap_ms"] == gap]
        n = len(g)
        ok = sum(1 for r in g if r["ok"])
        fail = sum(1 for r in g if not r["ok"])
        slow = sum(1 for r in g if r["connect_ms"] > 500)
        cmax = max((r["connect_ms"] for r in g), default=0)
        und = sum(1 for r in g if r["drained"] == 0 and issue_get)
        print(f"  {gap:>5} {n:>2} {ok:>2} {fail:>2} {slow:>2} {cmax:>6} {und:>3}")
    print(f"\nwrote {len(rows)} rows to {args.out}")

if __name__ == "__main__":
    main()
