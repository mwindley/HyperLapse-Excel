#!/usr/bin/env python3
"""
pair_fires_to_photos.py — match cart PIN8 fires to camera photos.

Inputs:
  --serial PATH  — text file with the serial transcript from /start to /stop.
                   Looks for [ANCHOR] line (one) and PIN8 #N lines (many).
  --exif   PATH  — CSV from exif_ingest.py with columns including
                   Filename, DateTimeOriginal (the camera-clock timestamp).

Output:
  prints one row per PIN8 fire: PIN8#, cart_millis, camera_clock, matched_photo
  ends with a summary count: fired / on_card / drops, and lists which PIN8
  numbers had no matching photo.

How matching works:
  ANCHOR line gives cart_millis ↔ camera_clock anchor at /shutter/start.
  Each PIN8 has cart_millis. Compute its predicted camera_clock = anchor_clock
  + (pin8_millis - anchor_millis) / 1000 seconds. Then find the EXIF photo
  with DateTimeOriginal closest to that, within MATCH_TOLERANCE_S.

Usage:
  python3 pair_fires_to_photos.py --serial run1.txt --exif run1_exif.csv

Notes:
  - DateTimeOriginal is 1-second resolution; matching tolerance is 1.5s
    by default. Adjust with --tolerance N if needed.
  - If two PIN8 fires fall in the same camera-clock second, both will match
    the same photo (the camera only timestamps to the second). This is OK
    when fires are 2s apart; flagged if tighter.
"""

import argparse
import csv
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Regex: [T+5486822] PIN8 #1 gap=2618ms ...
PIN8_RE = re.compile(r'\[T\+(\d+)\] PIN8 #(\d+) gap=(\d+)ms')

# Regex: [ANCHOR] millis=5486212 body={"datetime":"Tue, 19 May 2026 20:57:16 +0930","dst":true}
ANCHOR_RE = re.compile(
    r'\[ANCHOR\] millis=(\d+) body=\{"datetime":"([^"]+)"'
)

# Anchor datetime example: "Tue, 19 May 2026 20:57:16 +0930"
ANCHOR_DT_FMT = "%a, %d %b %Y %H:%M:%S %z"

# EXIF DateTimeOriginal example from exif_ingest.py: "2026-05-19T20:57:18"
EXIF_DT_FMT = "%Y-%m-%dT%H:%M:%S"


def parse_serial(path: Path):
    """Return (anchor_millis, anchor_dt, [(pin8_n, pin8_millis), ...])."""
    anchor = None
    fires = []
    with path.open('r', encoding='utf-8', errors='replace') as fh:
        for line in fh:
            m = ANCHOR_RE.search(line)
            if m:
                if anchor is not None:
                    print(f"WARN: multiple ANCHOR lines, using first",
                          file=sys.stderr)
                else:
                    millis = int(m.group(1))
                    dt = datetime.strptime(m.group(2), ANCHOR_DT_FMT)
                    anchor = (millis, dt)
                continue
            m = PIN8_RE.search(line)
            if m:
                fires.append((int(m.group(2)), int(m.group(1))))
    if anchor is None:
        raise SystemExit("ERROR: no [ANCHOR] line found in serial transcript")
    if not fires:
        raise SystemExit("ERROR: no PIN8 lines found in serial transcript")
    return anchor[0], anchor[1], fires


def parse_exif(path: Path):
    """Return list of (filename, dt) tuples sorted by dt.

    Reads CSV produced by exif_ingest.py — columns SourceFile, DateTimeOriginal.
    DateTimeOriginal is naive (no timezone); caller assigns tzinfo after.
    """
    photos = []
    with path.open('r', encoding='utf-8', errors='replace') as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            fn = row.get('SourceFile') or ''
            ts = row.get('DateTimeOriginal') or ''
            if not fn or not ts:
                continue
            try:
                dt = datetime.strptime(ts.strip(), EXIF_DT_FMT)
            except ValueError:
                continue
            photos.append((fn, dt))
    photos.sort(key=lambda t: t[1])
    return photos


def pair_fires_to_photos(anchor_millis, anchor_dt, fires, photos, tolerance_s):
    """For each fire, find best matching photo within tolerance. Returns
    list of dicts with fire info and the matched photo (or None)."""
    # Make photos tz-aware using the anchor's tzinfo so subtraction works
    tz = anchor_dt.tzinfo
    photos_aware = [(fn, dt.replace(tzinfo=tz)) for fn, dt in photos]
    used = set()
    results = []
    for pin8_n, pin8_millis in fires:
        delta_ms = pin8_millis - anchor_millis
        predicted = anchor_dt + timedelta(milliseconds=delta_ms)
        # Find closest unused photo within tolerance
        best_idx = None
        best_dt_diff = None
        for i, (fn, dt) in enumerate(photos_aware):
            if i in used:
                continue
            diff = abs((dt - predicted).total_seconds())
            if diff <= tolerance_s and (best_dt_diff is None or diff < best_dt_diff):
                best_dt_diff = diff
                best_idx = i
        match_fn = None
        match_dt = None
        if best_idx is not None:
            used.add(best_idx)
            match_fn = photos_aware[best_idx][0]
            match_dt = photos_aware[best_idx][1]
        results.append({
            'pin8_n': pin8_n,
            'pin8_millis': pin8_millis,
            'predicted_dt': predicted,
            'match_filename': match_fn,
            'match_dt': match_dt,
            'match_diff_s': best_dt_diff,
        })
    return results, used


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--serial', required=True, type=Path,
                    help='serial transcript text file')
    ap.add_argument('--exif', required=True, type=Path,
                    help='exif CSV from exif_ingest.py')
    ap.add_argument('--tolerance', type=float, default=1.5,
                    help='match tolerance in seconds (default 1.5)')
    args = ap.parse_args()

    anchor_millis, anchor_dt, fires = parse_serial(args.serial)
    photos = parse_exif(args.exif)
    results, used = pair_fires_to_photos(
        anchor_millis, anchor_dt, fires, photos, args.tolerance)

    # Print table
    print(f"{'PIN8#':>5}  {'cart_ms':>10}  {'predicted_camera_clock':>23}  "
          f"{'matched_photo':>20}  {'diff_s':>7}")
    drops = []
    for r in results:
        pred = r['predicted_dt'].strftime("%H:%M:%S")
        match_fn = r['match_filename'] or '— DROP —'
        diff_s = f"{r['match_diff_s']:.2f}" if r['match_diff_s'] is not None else ''
        print(f"{r['pin8_n']:>5}  {r['pin8_millis']:>10}  {pred:>23}  "
              f"{match_fn:>20}  {diff_s:>7}")
        if r['match_filename'] is None:
            drops.append(r['pin8_n'])

    # Summary
    fired = len(fires)
    matched = fired - len(drops)
    print()
    print(f"Summary: fired={fired}  on_card_matched={matched}  drops={len(drops)}")
    if drops:
        # Compact run-of-numbers display: 5,7-9,11
        print(f"Dropped PIN8 numbers: {compact_runs(drops)}")
    unused_photos = len(photos) - len(used)
    if unused_photos:
        print(f"WARN: {unused_photos} photos on card had no matching fire "
              f"(camera clock skew? card not cleared before run?)")


def compact_runs(nums):
    """Compact a sorted list of ints into '1,3-5,7' style."""
    nums = sorted(set(nums))
    if not nums:
        return ''
    out = []
    start = prev = nums[0]
    for n in nums[1:]:
        if n == prev + 1:
            prev = n
            continue
        out.append(f"{start}" if start == prev else f"{start}-{prev}")
        start = prev = n
    out.append(f"{start}" if start == prev else f"{start}-{prev}")
    return ','.join(out)


if __name__ == '__main__':
    main()
