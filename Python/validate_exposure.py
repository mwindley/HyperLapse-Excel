#!/usr/bin/env python3
"""
HyperLapse — Exposure Validation Against Reference Table (workfront #36)
========================================================================

Reads an exif.csv produced by exif_ingest.py and compares each photo's
exposure against the hand-built reference table from
EXPOSURE_FALLBACK.md Appendix A.

Implements the validation method from EXPOSURE_FALLBACK.md §5.5.

Inputs (hardcoded — edit at top of file or pass as args):
  - Path to exif.csv
  - Sunset wall-clock time (local, matching camera-clock timezone)
  - Sunrise wall-clock time (local, matching camera-clock timezone)
  - DST offset to apply (typically 0; +/-3600 if camera clock on wrong DST)

Outputs:
  - Per-block summary printed to stdout
  - validation.csv next to exif.csv with per-photo:
      filename, sun_event, t_rel_sec, actual_EV, table_EV, EV_diff
  - Aggregate stats: mean/median/std EV_diff,
    % within +/- 0.5, +/- 1.0, +/- 2.0 stop

Usage:
    python validate_exposure.py "E:\\Media R3\\exif.csv" \\
        --sunset "2026-01-22 20:32" --sunrise "2026-01-23 06:24"

DST option (apply offset to ALL camera timestamps before processing):
    python validate_exposure.py exif.csv --sunset "..." --sunrise "..." \\
        --clock-offset-min -60       (camera 60 min ahead of true local)

Method gotchas reminder (EXPOSURE_FALLBACK.md §5.6):
  - Excel date-mangling: not applicable here, we read float ExposureTime
  - Camera-clock DST: check Tv inflection points line up with sun events;
    if implied sunset is ~1h off, use --clock-offset-min
  - Manual time-nudge: not applicable to new shoots, only to old Excel
"""

import argparse
import csv
import math
import statistics
import sys
from datetime import datetime, timedelta
from pathlib import Path


# Reference table from EXPOSURE_FALLBACK.md Appendix A.
# Columns: (sun_label, t_rel_sec, Tv_str, Tv_seconds, ISO)
# Tv_seconds pre-computed to skip parsing.

REFERENCE_TABLE = [
    # Sunset
    ("Sunset", -4800, "1/5000", 1/5000, 100),
    ("Sunset", -4020, "1/4000", 1/4000, 100),
    ("Sunset", -3240, "1/3200", 1/3200, 100),
    ("Sunset", -2520, "1/2500", 1/2500, 100),
    ("Sunset", -1920, "1/2000", 1/2000, 100),
    ("Sunset", -1440, "1/1600", 1/1600, 100),
    ("Sunset", -1020, "1/1250", 1/1250, 100),
    ("Sunset",  -840, "1/1000", 1/1000, 100),
    ("Sunset",  -660, "1/800",  1/800,  100),
    ("Sunset",  -480, "1/640",  1/640,  100),
    ("Sunset",  -300, "1/500",  1/500,  100),
    ("Sunset",  -120, "1/400",  1/400,  100),
    ("Sunset",    60, "1/320",  1/320,  100),
    ("Sunset",   240, "1/250",  1/250,  100),
    ("Sunset",   360, "1/200",  1/200,  100),
    ("Sunset",   540, "1/160",  1/160,  100),
    ("Sunset",   660, "1/125",  1/125,  100),
    ("Sunset",   720, "1/100",  1/100,  100),
    ("Sunset",   780, "1/80",   1/80,   100),
    ("Sunset",   900, "1/60",   1/60,   100),
    ("Sunset",  1020, "1/50",   1/50,   100),
    ("Sunset",  1080, "1/40",   1/40,   100),
    ("Sunset",  1140, "1/30",   1/30,   100),
    ("Sunset",  1260, "1/25",   1/25,   100),
    ("Sunset",  1380, "1/20",   1/20,   100),
    ("Sunset",  1440, "1/15",   1/15,   100),
    ("Sunset",  1500, "1/13",   1/13,   100),
    ("Sunset",  1560, "1/10",   1/10,   100),
    ("Sunset",  1620, "1/8",    1/8,    100),
    ("Sunset",  1680, "1/6",    1/6,    100),
    ("Sunset",  1800, "1/5",    1/5,    100),
    ("Sunset",  1860, "1/4",    1/4,    100),
    ("Sunset",  1920, "0.3",    0.3,    100),
    ("Sunset",  1980, "0.4",    0.4,    100),
    ("Sunset",  2040, "0.5",    0.5,    100),
    ("Sunset",  2100, "0.6",    0.6,    100),
    ("Sunset",  2160, "0.8",    0.8,    100),
    ("Sunset",  2220, "1",      1.0,    100),
    ("Sunset",  2280, "1.3",    1.3,    100),
    ("Sunset",  2340, "1.6",    1.6,    100),
    ("Sunset",  2460, "2",      2.0,    100),
    ("Sunset",  2520, "2.5",    2.5,    100),
    ("Sunset",  2580, "3.2",    3.2,    100),
    ("Sunset",  2640, "4",      4.0,    100),
    ("Sunset",  2760, "5",      5.0,    100),
    ("Sunset",  2820, "6",      6.0,    100),
    ("Sunset",  2940, "8",      8.0,    100),
    ("Sunset",  3000, "10",    10.0,    100),
    ("Sunset",  3120, "13",    13.0,    100),
    ("Sunset",  3180, "15",    15.0,    100),
    ("Sunset",  3300, "20",    20.0,    100),
    ("Sunset",  3360, "20",    20.0,    125),
    ("Sunset",  3420, "20",    20.0,    160),
    ("Sunset",  3480, "20",    20.0,    200),
    ("Sunset",  3540, "20",    20.0,    250),
    ("Sunset",  3600, "20",    20.0,    320),
    ("Sunset",  3660, "20",    20.0,    400),
    ("Sunset",  3720, "20",    20.0,    500),
    ("Sunset",  3840, "20",    20.0,    640),
    ("Sunset",  3960, "20",    20.0,    800),
    ("Sunset",  4080, "20",    20.0,   1000),
    ("Sunset",  4260, "20",    20.0,   1250),
    ("Sunset",  4440, "20",    20.0,   1600),
    # Sunrise (in time order: t_rel becomes more negative -> less)
    ("Sunrise", -5940, "20",   20.0,   1600),
    ("Sunrise", -5760, "20",   20.0,   1250),
    ("Sunrise", -5580, "20",   20.0,   1000),
    ("Sunrise", -5460, "20",   20.0,    800),
    ("Sunrise", -5340, "20",   20.0,    640),
    ("Sunrise", -5220, "20",   20.0,    500),
    ("Sunrise", -5160, "20",   20.0,    400),
    ("Sunrise", -5100, "20",   20.0,    300),
    ("Sunrise", -5040, "20",   20.0,    250),
    ("Sunrise", -4980, "20",   20.0,    200),
    ("Sunrise", -4920, "20",   20.0,    160),
    ("Sunrise", -4860, "20",   20.0,    125),
    ("Sunrise", -4800, "20",   20.0,    100),
    ("Sunrise", -4440, "20",   20.0,    100),
    ("Sunrise", -4380, "15",   15.0,    100),
    ("Sunrise", -4320, "13",   13.0,    100),
    ("Sunrise", -4260, "10",   10.0,    100),
    ("Sunrise", -4140, "8",     8.0,    100),
    ("Sunrise", -4020, "6",     6.0,    100),
    ("Sunrise", -3960, "5",     5.0,    100),
    ("Sunrise", -3840, "4",     4.0,    100),
    ("Sunrise", -3780, "3",     3.0,    100),
    ("Sunrise", -3720, "2.5",   2.5,    100),
    ("Sunrise", -3600, "2",     2.0,    100),
    ("Sunrise", -3540, "1.6",   1.6,    100),
    ("Sunrise", -3480, "1.3",   1.3,    100),
    ("Sunrise", -3420, "1",     1.0,    100),
    ("Sunrise", -3300, "0.8",   0.8,    100),
    ("Sunrise", -3180, "0.6",   0.6,    100),
    ("Sunrise", -3060, "0.5",   0.5,    100),
    ("Sunrise", -3000, "0.3",   0.3,    100),
    ("Sunrise", -2880, "1/4",   1/4,    100),
    ("Sunrise", -2820, "1/5",   1/5,    100),
    ("Sunrise", -2700, "1/6",   1/6,    100),
    ("Sunrise", -2640, "1/8",   1/8,    100),
    ("Sunrise", -2520, "1/10",  1/10,   100),
    ("Sunrise", -2460, "1/13",  1/13,   100),
    ("Sunrise", -2400, "1/15",  1/15,   100),
    ("Sunrise", -2340, "1/20",  1/20,   100),
    ("Sunrise", -2280, "1/25",  1/25,   100),
    ("Sunrise", -2220, "1/30",  1/30,   100),
    ("Sunrise", -2160, "1/40",  1/40,   100),
    ("Sunrise", -2100, "1/50",  1/50,   100),
    ("Sunrise", -2040, "1/60",  1/60,   100),
    ("Sunrise", -1980, "1/80",  1/80,   100),
    ("Sunrise", -1860, "1/100", 1/100,  100),
    ("Sunrise", -1800, "1/125", 1/125,  100),
    ("Sunrise", -1740, "1/160", 1/160,  100),
    ("Sunrise", -1620, "1/200", 1/200,  100),
    ("Sunrise", -1560, "1/250", 1/250,  100),
    ("Sunrise", -1440, "1/320", 1/320,  100),
    ("Sunrise", -1320, "1/400", 1/400,  100),
    ("Sunrise", -1200, "1/500", 1/500,  100),
    ("Sunrise", -1080, "1/640", 1/640,  100),
    ("Sunrise",  -960, "1/800", 1/800,  100),
    ("Sunrise",  -780, "1/1000",1/1000, 100),
    ("Sunrise",  -660, "1/1250",1/1250, 100),
    ("Sunrise",  -540, "1/1600",1/1600, 100),
    ("Sunrise",  -420, "1/2000",1/2000, 100),
    ("Sunrise",  -300, "1/2500",1/2500, 100),
    ("Sunrise",  -180, "1/3200",1/3200, 100),
    ("Sunrise",   -60, "1/4000",1/4000, 100),
    ("Sunrise",    60, "1/5000",1/5000, 100),
]


def ev_from_tv_iso(tv_seconds, iso):
    """EV (with ISO factored in, normalized to ISO 100).

    EV = -log2(Tv) - log2(ISO/100)

    Higher EV = brighter scene (faster Tv or lower ISO).
    """
    return -math.log2(tv_seconds) - math.log2(iso / 100.0)


def build_table_ev(sun_label):
    """Return list of (t_rel, EV) sorted by t_rel, for given sun_label."""
    rows = [(t, ev_from_tv_iso(tv_s, iso))
            for (lbl, t, _, tv_s, iso) in REFERENCE_TABLE if lbl == sun_label]
    rows.sort(key=lambda r: r[0])
    return rows


def interp_table(t_rel, table):
    """Linear-interpolate table EV at t_rel. Returns None if out of range."""
    if not table:
        return None
    if t_rel < table[0][0] or t_rel > table[-1][0]:
        return None
    # Find bracketing pair
    for i in range(len(table) - 1):
        t0, ev0 = table[i]
        t1, ev1 = table[i + 1]
        if t0 <= t_rel <= t1:
            if t1 == t0:
                return ev0
            frac = (t_rel - t0) / (t1 - t0)
            return ev0 + frac * (ev1 - ev0)
    return None


def parse_iso_dt(s):
    try:
        return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None


def parse_wallclock(s):
    """Accept 'YYYY-MM-DD HH:MM' or 'YYYY-MM-DD HH:MM:SS'."""
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            pass
    raise ValueError(f"Could not parse datetime: {s!r}")


def stats_block(name, diffs):
    """Print summary stats for a list of EV_diff values."""
    if not diffs:
        print(f"  {name}: no data")
        return
    n = len(diffs)
    mean = statistics.mean(diffs)
    median = statistics.median(diffs)
    std = statistics.stdev(diffs) if n > 1 else 0.0
    within_05 = 100.0 * sum(1 for d in diffs if abs(d) <= 0.5) / n
    within_10 = 100.0 * sum(1 for d in diffs if abs(d) <= 1.0) / n
    within_20 = 100.0 * sum(1 for d in diffs if abs(d) <= 2.0) / n
    print(f"  {name}: n={n}")
    print(f"    mean EV_diff = {mean:+.2f}  median = {median:+.2f}  std = {std:.2f}")
    print(f"    within ±0.5 stop: {within_05:5.1f}%")
    print(f"    within ±1.0 stop: {within_10:5.1f}%")
    print(f"    within ±2.0 stop: {within_20:5.1f}%")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", help="Path to exif.csv from exif_ingest.py")
    ap.add_argument("--sunset", required=True,
                    help="Local sunset wall-clock (matches camera timestamps), "
                         "e.g. '2026-01-22 20:32'")
    ap.add_argument("--sunrise", required=True,
                    help="Local sunrise wall-clock, e.g. '2026-01-23 06:24'")
    ap.add_argument("--clock-offset-min", type=int, default=0,
                    help="Minutes to ADD to camera timestamps to correct "
                         "wrong-DST etc (default 0)")
    args = ap.parse_args()

    csv_path = Path(args.csv).resolve()
    if not csv_path.is_file():
        print(f"ERROR: not a file: {csv_path}", file=sys.stderr)
        return 1

    sunset_dt = parse_wallclock(args.sunset)
    sunrise_dt = parse_wallclock(args.sunrise)
    offset = timedelta(minutes=args.clock_offset_min)

    # Reference tables, pre-built
    sunset_table = build_table_ev("Sunset")
    sunrise_table = build_table_ev("Sunrise")

    # Block split rule: midpoint between sunset and sunrise.
    # Photos before midpoint -> sunset block; after -> sunrise block.
    midpoint = sunset_dt + (sunrise_dt - sunset_dt) / 2

    # Read CSV
    rows_total = 0
    rows_skipped = 0
    sunset_diffs = []
    sunrise_diffs = []
    out_rows = []

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows_total += 1
            if r.get("Status") != "ok":
                rows_skipped += 1
                continue

            dt = parse_iso_dt(r["DateTimeOriginal"])
            if dt is None:
                rows_skipped += 1
                continue
            dt = dt + offset

            try:
                tv = float(r["ExposureTime"])
                iso = float(r["ISO"])
            except (ValueError, KeyError):
                rows_skipped += 1
                continue

            if tv <= 0 or iso <= 0:
                rows_skipped += 1
                continue

            actual_ev = ev_from_tv_iso(tv, iso)

            # Pick sun event
            if dt <= midpoint:
                sun = "Sunset"
                t_rel = (dt - sunset_dt).total_seconds()
                table_ev = interp_table(t_rel, sunset_table)
            else:
                sun = "Sunrise"
                t_rel = (dt - sunrise_dt).total_seconds()
                table_ev = interp_table(t_rel, sunrise_table)

            if table_ev is None:
                # Out of table range — record but don't include in stats
                out_rows.append((r["SourceFile"], sun, int(t_rel),
                                 f"{actual_ev:.3f}", "", ""))
                continue

            diff = actual_ev - table_ev
            out_rows.append((r["SourceFile"], sun, int(t_rel),
                             f"{actual_ev:.3f}", f"{table_ev:.3f}",
                             f"{diff:+.3f}"))

            if sun == "Sunset":
                sunset_diffs.append(diff)
            else:
                sunrise_diffs.append(diff)

    # Write per-photo CSV
    out_path = csv_path.parent / "validation.csv"
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["SourceFile", "SunEvent", "t_rel_sec",
                    "actual_EV", "table_EV", "EV_diff"])
        w.writerows(out_rows)

    # Print summary
    print(f"Input:    {csv_path}")
    print(f"Sunset:   {sunset_dt}")
    print(f"Sunrise:  {sunrise_dt}")
    print(f"Midpoint: {midpoint}")
    if args.clock_offset_min:
        print(f"Camera-clock offset applied: {args.clock_offset_min:+d} min")
    print(f"Total rows: {rows_total}, skipped: {rows_skipped}, "
          f"validated: {len(sunset_diffs) + len(sunrise_diffs)}")
    print(f"  (out-of-table-range rows recorded in CSV without diff)")
    print()
    print("Per-block stats (EV_diff = actual - table; "
          "positive = brighter than recipe):")
    stats_block("Sunset block", sunset_diffs)
    stats_block("Sunrise block", sunrise_diffs)
    print()
    print(f"Per-photo detail written to: {out_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
