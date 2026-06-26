"""
HyperLapse Cart - laptop-side alarm watcher (#49)

WHY THIS EXISTS: the Exec-page audio alarm only sounds while that browser tab
is open, foreground, and the device awake - exactly the conditions an
unattended overnight rig does NOT have. This is an INDEPENDENT Windows process
that polls the cart's /exec/feed itself, edge-detects the alarm conditions, and
raises a sound + an always-on-top acknowledge pop-up that does not depend on any
browser tab. Because it polls the cart directly, its OWN poll failing IS the
link-down alarm - it fires precisely when the cart is unreachable, which the
browser beep never can.

Pure standard library: urllib (poll), json (parse), winsound (tone), tkinter
(ack pop-up), threading (sound loop). No installs.

SPEC (locked Day 35):
  - poll http://192.168.20.97/exec/feed every 5s
  - >15s with no good reply (3 missed polls) = LINK-DOWN
  - 8 conditions, edge-triggered (alarm on false->true)
  - sound loops + always-on-top pop-up until operator clicks ACK
  - acked condition stays silent until it CLEARS then re-occurs
  - one log line per event, appended to a file
  - single-instance lock (pidfile) so AUTO + MANUAL starts never double-launch

Run:  pythonw hyperlapse_watcher.py     (no console window)
  or:  python  hyperlapse_watcher.py     (console, for debugging)
Stop: close the small status window, or delete the lock and kill the process.
"""

import json
import os
import sys
import time
import tempfile
import threading
import urllib.request
import urllib.error
from datetime import datetime

import tkinter as tk
import winsound

# ----------------------------------------------------------------------------
# Config (the few values that may change site-to-site)
# ----------------------------------------------------------------------------
# Cart target: take the IP (or full URL) from the command line so Excel can pass
# the CURRENT dataArduinoIP instead of a baked-in address. Accepts either:
#   hyperlapse_watcher.py 192.168.1.97          -> http://192.168.1.97/exec/feed
#   hyperlapse_watcher.py http://192.168.1.97   -> .../exec/feed appended
# Falls back to the default below when launched with no argument.
_DEFAULT_CART_IP  = "192.168.1.97"
def _build_cart_url(argv):
    arg = argv[1].strip() if len(argv) > 1 and argv[1].strip() else _DEFAULT_CART_IP
    if arg.startswith("http://") or arg.startswith("https://"):
        base = arg.rstrip("/")
    else:
        base = "http://" + arg.rstrip("/")
    if not base.endswith("/exec/feed"):
        base = base + "/exec/feed"
    return base
CART_URL          = _build_cart_url(sys.argv)
POLL_EVERY_S      = 5          # poll cadence
LINK_DOWN_AFTER_S = 15         # no good reply for this long = link down
HTTP_TIMEOUT_S    = 4          # per-request timeout (< POLL_EVERY_S)
CART_BATT_LOW_V   = 22.0       # fallback only; the cart now serves "battlow" in /exec/feed (Excel dataCartBattLow) and the watcher uses that when present
LOG_PATH          = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hyperlapse_watcher.log")
LOCK_PATH         = os.path.join(tempfile.gettempdir(), "hyperlapse_watcher.lock")

# ----------------------------------------------------------------------------
# Single-instance lock: AUTO (Excel START) and MANUAL (button) both launch this;
# the second one must no-op. Write our pid; if a live process already holds the
# lock, exit quietly.
# ----------------------------------------------------------------------------
def acquire_lock():
    if os.path.exists(LOCK_PATH):
        try:
            with open(LOCK_PATH) as f:
                old = int(f.read().strip())
            # crude liveness check (Windows): if the pid is gone, the lock is stale
            os.kill(old, 0)
            return False          # a live instance holds the lock
        except (ValueError, OSError):
            pass                  # stale lock - take it over
    with open(LOCK_PATH, "w") as f:
        f.write(str(os.getpid()))
    return True


def release_lock():
    try:
        os.remove(LOCK_PATH)
    except OSError:
        pass


# ----------------------------------------------------------------------------
# Logging - one line per event, appended.
# ----------------------------------------------------------------------------
def log_event(text):
    line = "%s  %s\n" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), text)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line)
    except OSError:
        pass


# ----------------------------------------------------------------------------
# Condition evaluation. Each returns (active: bool, detail: str).
# Plan-related conditions arm only when state == RUNNING; reachability/power
# whenever the cart should be up; heading when a plan is LOADED/RUNNING.
# `feed` is the parsed dict, or None when the poll failed (link down).
# `prev_photos` tracks the frame count across polls for the stall check.
# ----------------------------------------------------------------------------
def evaluate(feed, link_down, prev_photos):
    conds = {}

    # 2 LINK DOWN - the watcher's own poll failing. Highest value alarm.
    conds["link_down"] = (link_down,
                          "no reply from cart for >%ds" % LINK_DOWN_AFTER_S)

    if feed is None:
        # Link down -> we have no other fields; leave the rest inactive.
        for k in ("heading", "cbatt", "paused", "ended",
                  "cart_batt", "cam_link", "gimbal_can", "photos_stalled"):
            conds[k] = (False, "")
        return conds

    state = feed.get("state", "?")
    running = (state == "RUNNING")

    # 1 HEADING WINDOW open - any earth-frame GP row in its alert window.
    hdg = False
    for r in feed.get("rows", []):
        if r.get("earth") and (r.get("alert") or r.get("st") == "now"):
            hdg = True
            break
    conds["heading"] = (hdg and state in ("LOADED", "RUNNING"),
                        "earth-frame heading window open")

    # 3 CAMERA BATT low (only level; no critical tier).
    conds["cbatt"] = (feed.get("cbatt") == "low", "camera battery LOW")

    # 4 PAUSE reached (plan frozen).
    conds["paused"] = (bool(feed.get("paused")) and running,
                       "plan PAUSED / frozen")

    # 5 PLAN ended.
    conds["ended"] = (state == "DONE", "plan ENDED")

    # 6 CART batt low (Tic Vin volts).
    try:
        v = float(feed.get("batt", 99))
    except (TypeError, ValueError):
        v = 99.0
    # Threshold: prefer the cart-served "battlow" (Excel dataCartBattLow) so the
    # watcher uses the SAME value the operator set; fall back to the constant.
    try:
        low_v = float(feed.get("battlow", CART_BATT_LOW_V))
    except (TypeError, ValueError):
        low_v = CART_BATT_LOW_V
    conds["cart_batt"] = (v < low_v,
                          "cart battery %.1fV < %.1fV" % (v, low_v))

    # 7a CAMERA LINK (CCAPI) lost/degraded.
    conds["cam_link"] = (feed.get("cam") == "nok", "camera link NOK (CCAPI)")

    # 7b GIMBAL CAN error (gimbal comms lost).
    conds["gimbal_can"] = (feed.get("can") == "err", "gimbal CAN error")

    # 8 PHOTOS stalled - frame count not rising while RUNNING.
    try:
        photos = int(feed.get("photos", 0))
    except (TypeError, ValueError):
        photos = prev_photos if prev_photos is not None else 0
    stalled = (running and prev_photos is not None and photos == prev_photos)
    conds["photos_stalled"] = (stalled, "photos not advancing (count=%d)" % photos)
    conds["_photos"] = photos          # carried out for next-poll comparison

    return conds


# Human-readable labels for the pop-up + log.
LABELS = {
    "link_down":      "LINK DOWN - cart unreachable",
    "heading":        "HEADING window open",
    "cbatt":          "CAMERA battery LOW",
    "paused":         "Plan PAUSED",
    "ended":          "Plan ENDED",
    "cart_batt":      "CART battery LOW",
    "cam_link":       "CAMERA link NOK",
    "gimbal_can":     "GIMBAL CAN error",
    "photos_stalled": "PHOTOS stalled",
}


# ----------------------------------------------------------------------------
# Alarm state machine + UI. One Tk root; a worker thread polls and posts alarm
# events into Tk via .after(). Sound loops on a thread while any alarm is
# unacked. Ack silences a condition until it clears and re-fires.
# ----------------------------------------------------------------------------
class Watcher:
    def __init__(self, root):
        self.root = root
        self.prev_active = {}     # cond -> bool, last poll's active state
        self.acked = set()        # conds the operator has acknowledged (still true)
        self.unacked = []         # ordered list of cond keys currently alarming
        self.prev_photos = None
        self.last_good = time.time()
        self.sound_stop = threading.Event()
        self.sound_thread = None

        # Small always-visible status line; the ack pop-up is separate/topmost.
        root.title("HyperLapse watcher")
        root.geometry("360x90")
        self.status = tk.Label(root, text="starting...", font=("Segoe UI", 11),
                               justify="left", anchor="w")
        self.status.pack(fill="both", expand=True, padx=12, pady=12)
        self.popup = None

        log_event("WATCHER START (poll %s every %ds)" % (CART_URL, POLL_EVERY_S))
        threading.Thread(target=self.poll_loop, daemon=True).start()

    # --- sound: loop a tone while unacked alarms exist ----------------------
    def start_sound(self):
        if self.sound_thread and self.sound_thread.is_alive():
            return
        self.sound_stop.clear()

        def loop():
            while not self.sound_stop.is_set():
                try:
                    winsound.Beep(1000, 400)   # 1kHz, 400ms
                except RuntimeError:
                    pass
                self.sound_stop.wait(0.3)

        self.sound_thread = threading.Thread(target=loop, daemon=True)
        self.sound_thread.start()

    def stop_sound(self):
        self.sound_stop.set()

    # --- poll loop (worker thread) ------------------------------------------
    def poll_loop(self):
        while True:
            feed = None
            try:
                req = urllib.request.Request(CART_URL,
                                             headers={"Cache-Control": "no-store"})
                with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
                    feed = json.loads(resp.read().decode("utf-8", "replace"))
                self.last_good = time.time()
            except (urllib.error.URLError, OSError, ValueError):
                feed = None

            link_down = (time.time() - self.last_good) >= LINK_DOWN_AFTER_S
            conds = evaluate(feed, link_down, self.prev_photos)
            if "_photos" in conds:
                self.prev_photos = conds.pop("_photos")

            # marshal back onto the Tk thread
            self.root.after(0, self.apply, conds, feed)
            time.sleep(POLL_EVERY_S)

    # --- apply condition results (Tk thread) --------------------------------
    def apply(self, conds, feed):
        for key, (active, detail) in conds.items():
            was = self.prev_active.get(key, False)
            # rising edge -> new alarm (unless already acked and still true)
            if active and not was and key not in self.acked:
                self.raise_alarm(key, detail)
            # cleared -> drop ack so it can re-fire next time
            if not active and was:
                self.acked.discard(key)
                if key in self.unacked:
                    self.unacked.remove(key)
            self.prev_active[key] = active

        if not self.unacked:
            self.stop_sound()
            if self.popup is not None:
                self.popup.destroy()
                self.popup = None

        self.refresh_status(feed)

    def raise_alarm(self, key, detail):
        if key not in self.unacked:
            self.unacked.append(key)
        log_event("ALARM  %s  (%s)" % (LABELS.get(key, key), detail))
        self.start_sound()
        self.show_popup()

    # --- ack pop-up (always on top) -----------------------------------------
    def show_popup(self):
        if self.popup is not None:
            self.popup.lift()
            self.render_popup()
            return
        p = tk.Toplevel(self.root)
        p.title("HyperLapse ALARM")
        p.attributes("-topmost", True)
        p.geometry("420x220")
        p.configure(bg="#a32d2d")
        self.popup = p
        self.popup_list = tk.Label(p, text="", font=("Segoe UI", 12, "bold"),
                                   bg="#a32d2d", fg="white", justify="left",
                                   anchor="nw", wraplength=380)
        self.popup_list.pack(fill="both", expand=True, padx=16, pady=(16, 8))
        tk.Button(p, text="ACKNOWLEDGE (silence)", font=("Segoe UI", 11, "bold"),
                  command=self.acknowledge).pack(fill="x", padx=16, pady=(0, 16))
        p.protocol("WM_DELETE_WINDOW", self.acknowledge)
        self.render_popup()

    def render_popup(self):
        if self.popup is None:
            return
        lines = "\n".join("- " + LABELS.get(k, k) for k in self.unacked)
        self.popup_list.config(text="ACTIVE ALARMS:\n\n" + lines)

    def acknowledge(self):
        # operator silences all current alarms; they stay acked (silent) until
        # each condition clears and re-occurs.
        for k in self.unacked:
            self.acked.add(k)
            log_event("ACK    %s" % LABELS.get(k, k))
        self.unacked = []
        self.stop_sound()
        if self.popup is not None:
            self.popup.destroy()
            self.popup = None

    # --- status line --------------------------------------------------------
    def refresh_status(self, feed):
        age = int(time.time() - self.last_good)
        if feed is None:
            self.status.config(
                text="cart: NO REPLY (%ds)\nalarms acked: %d  active: %d"
                     % (age, len(self.acked), len(self.unacked)))
        else:
            self.status.config(
                text="cart: %s  cam=%s can=%s cbatt=%s batt=%s\n"
                     "photos=%s   acked:%d active:%d  (last reply %ds ago)"
                     % (feed.get("state", "?"), feed.get("cam", "?"),
                        feed.get("can", "?"), feed.get("cbatt", "?"),
                        feed.get("batt", "?"), feed.get("photos", "?"),
                        len(self.acked), len(self.unacked), age))


def main():
    if not acquire_lock():
        # another instance already running - this is the AUTO/MANUAL double; no-op.
        sys.exit(0)
    try:
        root = tk.Tk()
        Watcher(root)
        root.mainloop()
    finally:
        release_lock()
        log_event("WATCHER STOP")


if __name__ == "__main__":
    main()
