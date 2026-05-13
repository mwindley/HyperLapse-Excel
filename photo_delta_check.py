#!/usr/bin/env python3
"""
HyperLapse Cart — Photo Delta Check (v2 with pagination)
=========================================================

Queries the Canon R3 via CCAPI for the timestamps of every photo in the
current folder, computes deltas between consecutive photos, and flags any
gap that suggests a missed pin-8 fire.

v2: Handles CCAPI's 100-file-per-page limit by paging through ?page=N.

Usage (Windows cmd):
    python photo_delta_check.py
"""

import urllib.request
import urllib.error
import json
import sys
from email.utils import parsedate_to_datetime

CAMERA_IP   = "192.168.1.99"
CAMERA_PORT = 8080
CARD        = "cfex"
FOLDER      = "102EOSR3"

EXPECTED_INTERVAL_S = 4
TOLERANCE_S = 1

MAX_PAGES = 50


def fetch_json(url, timeout=10):
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_all_files():
    """Fetch all file paths, paginating if needed."""
    base = f"http://{CAMERA_IP}:{CAMERA_PORT}/ccapi/ver110/contents/{CARD}/{FOLDER}"
    all_paths = []
    seen = set()

    try:
        listing = fetch_json(base)
        paths = listing.get("path", [])
        for p in paths:
            if p not in seen:
                seen.add(p)
                all_paths.append(p)
        print(f"  page (no param): got {len(paths)} files")
    except urllib.error.URLError as e:
        print(f"ERROR fetching base listing: {e}")
        return []

    if len(all_paths) >= 100:
        for page in range(2, MAX_PAGES + 2):
            url = f"{base}?page={page}"
            try:
                listing = fetch_json(url)
                paths = listing.get("path", [])
                new_count = 0
                for p in paths:
                    if p not in seen:
                        seen.add(p)
                        all_paths.append(p)
                        new_count += 1
                print(f"  page {page}: got {len(paths)} files, {new_count} new")
                if new_count == 0:
                    break
            except (urllib.error.URLError, urllib.error.HTTPError) as e:
                print(f"  page {page}: error ({e}) - stopping")
                break

    return all_paths


def main():
    print("Fetching file list from camera ...")
    paths = fetch_all_files()
    n = len(paths)
    print(f"Total: {n} unique files in {FOLDER}\n")

    if n == 0:
        print("No files. Nothing to analyse.")
        return

    print("Fetching per-file metadata ...")
    records = []
    fails = 0
    for i, p in enumerate(paths, 1):
        url = f"http://{CAMERA_IP}:{CAMERA_PORT}{p}?kind=info"
        try:
            info = fetch_json(url, timeout=15)
        except (urllib.error.URLError, urllib.error.HTTPError) as e:
            fails += 1
            if fails < 5:
                print(f"  [{i}/{n}] {p.split('/')[-1]}: FAIL ({e})")
            continue

        lmd = info.get("lastmodifieddate")
        if not lmd:
            continue
        try:
            dt = parsedate_to_datetime(lmd)
        except Exception:
            continue

        records.append((p.split("/")[-1], dt))
        if i % 50 == 0 or i == n:
            print(f"  ... {i}/{n} fetched")

    if fails > 0:
        print(f"  ({fails} metadata fetches failed)")
    print()

    if len(records) < 2:
        print("Need at least 2 records to compute deltas.")
        return

    records.sort(key=lambda r: r[1])

    print(f"{'File':<14} {'Timestamp (camera clock)':<32} {'delta (s)':>10}  Flag")
    print("-" * 78)

    drops_inferred = 0
    captured = len(records)
    prev = None
    for name, dt in records:
        if prev is None:
            print(f"{name:<14} {dt.strftime('%Y-%m-%d %H:%M:%S %Z'):<32} {'-':>10}")
        else:
            delta = (dt - prev[1]).total_seconds()
            flag = ""

            if abs(delta - EXPECTED_INTERVAL_S) <= TOLERANCE_S:
                flag = "ok"
            elif delta < EXPECTED_INTERVAL_S - TOLERANCE_S:
                flag = "FAST (?)"
            else:
                missed = round((delta - EXPECTED_INTERVAL_S) / EXPECTED_INTERVAL_S)
                if missed > 0:
                    drops_inferred += missed
                    flag = f"SLOW - {missed} fire(s) missed"
                else:
                    flag = "SLOW"

            print(f"{name:<14} {dt.strftime('%Y-%m-%d %H:%M:%S %Z'):<32} {delta:>10.1f}  {flag}")
        prev = (name, dt)

    print("-" * 78)
    print(f"Captured: {captured} photos")
    print(f"Drops inferred between captured photos: {drops_inferred}")
    print(f"Implied total pin-8 fires (captured + inferred): {captured + drops_inferred}")
    if records:
        span = (records[-1][1] - records[0][1]).total_seconds()
        print(f"Time span first to last capture: {span:.0f} s ({span/60:.1f} min)")


if __name__ == "__main__":
    main()
