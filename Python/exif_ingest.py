#!/usr/bin/env python3
"""
HyperLapse — EXIF Ingestion Pipeline (workfront #38a)
=====================================================

Walks a folder of CR3 files, extracts per-image EXIF data via
exiftool, writes exif.csv into the same folder.

Output columns:
    SourceFile, DateTimeOriginal, ExposureTime, ISO,
    BrightnessValue, GPSLat, GPSLon, Status

ExposureTime is a float in seconds (e.g. 0.00025 for 1/4000, 20.0
for 20s). This avoids the Excel date-mangling problem documented
in EXPOSURE_FALLBACK.md §5.6.1 — no fractional strings in the CSV.

BrightnessValue is best-effort. Blank where exiftool doesn't return
a value. EXIF tag 0x9203 — camera's own metered EV, separate from
the exposure decision.

Status values:
    ok                — all required fields parsed
    no_datetime       — DateTimeOriginal missing or unparseable
    no_exposure       — ExposureTime missing
    no_iso            — ISO missing
    exiftool_fail     — exiftool returned no record for this file

Usage (called from VBA shell, like luminance.py):
    python exif_ingest.py "D:\\Shoots\\2026-02-20"

Writes "D:\\Shoots\\2026-02-20\\exif.csv".

Exit code:
    0  — success, CSV written (even if some rows had non-ok status)
    1  — fatal: folder missing, exiftool not found, or CSV write failed

Dependencies:
    exiftool.exe — tries PATH first, falls back to script directory.
    Python stdlib only otherwise (json, csv, subprocess, pathlib).
"""

import csv
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def find_exiftool():
    """Try exiftool on PATH first, then script directory. Return path or None."""
    # Try PATH
    try:
        result = subprocess.run(
            ["exiftool", "-ver"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return "exiftool"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Fall back to script directory
    script_dir = Path(__file__).resolve().parent
    candidate = script_dir / "exiftool.exe"
    if candidate.exists():
        try:
            result = subprocess.run(
                [str(candidate), "-ver"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                return str(candidate)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

    return None


def parse_datetime(s):
    """EXIF DateTimeOriginal format: 'YYYY:MM:DD HH:MM:SS'. Return ISO string or None."""
    if not s:
        return None
    try:
        dt = datetime.strptime(s, "%Y:%m:%d %H:%M:%S")
        return dt.strftime("%Y-%m-%dT%H:%M:%S")
    except (ValueError, TypeError):
        return None


def to_float(v):
    """Coerce a JSON value to float, return None if not possible."""
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def main():
    if len(sys.argv) != 2:
        print("Usage: python exif_ingest.py <folder>", file=sys.stderr)
        return 1

    folder = Path(sys.argv[1]).resolve()
    if not folder.is_dir():
        print(f"ERROR: not a directory: {folder}", file=sys.stderr)
        return 1

    exiftool = find_exiftool()
    if exiftool is None:
        print(
            "ERROR: exiftool not found on PATH or beside script.\n"
            "Install from https://exiftool.org/ or place exiftool.exe "
            "next to this script.",
            file=sys.stderr
        )
        return 1

    # Single batch call — exiftool reads the whole folder, returns JSON.
    # -n forces numeric output (no "1/4000 sec" strings; floats only).
    # -j gives JSON. Tags requested explicitly so we get a consistent shape.
    # -fast2 skips MakerNotes parsing — substantial speedup on CR3, all
    # tags we need are in the main + GPS IFD.
    # -progress streams "N/total" messages to stderr; we pipe stderr
    # through to the operator's console so they can see it's working.
    print(f"Scanning: {folder}", file=sys.stderr)
    print(f"Using: {exiftool}", file=sys.stderr)
    print("This may take several minutes for large folders.", file=sys.stderr)
    print("Progress (file N of total) will print below:", file=sys.stderr)
    sys.stderr.flush()

    cmd = [
        exiftool,
        "-j",                       # JSON output
        "-n",                       # numeric values (ExposureTime as float)
        "-fast2",                   # skip MakerNotes, big speedup on CR3
        "-progress",                # show "filename [N/total]" on stderr
        "-ext", "CR3",              # restrict to CR3 only
        "-DateTimeOriginal",
        "-ExposureTime",
        "-ISO",
        "-BrightnessValue",
        "-GPSLatitude",
        "-GPSLongitude",
        "-SourceFile",
        str(folder),
    ]

    # Stream stderr live (for progress), capture stdout (for JSON).
    # Timeout of 1 hour — one-time-per-shoot operation, better long than short.
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=None,            # inherit parent stderr → live progress
            text=True,
        )
        stdout_data, _ = proc.communicate(timeout=3600)
    except subprocess.TimeoutExpired:
        proc.kill()
        print("ERROR: exiftool timed out after 3600s (1 hour)", file=sys.stderr)
        return 1

    if proc.returncode != 0 and not stdout_data.strip():
        print(f"ERROR: exiftool exit code {proc.returncode} with no output",
              file=sys.stderr)
        return 1

    # Repurpose `result.stdout` references below to `stdout_data`.
    class _R:
        pass
    result = _R()
    result.stdout = stdout_data
    result.stderr = ""
    result.returncode = proc.returncode

    if result.returncode != 0 and not result.stdout.strip():
        print(f"ERROR: exiftool failed: {result.stderr}", file=sys.stderr)
        return 1

    try:
        records = json.loads(result.stdout) if result.stdout.strip() else []
    except json.JSONDecodeError as e:
        print(f"ERROR: could not parse exiftool JSON: {e}", file=sys.stderr)
        return 1

    if not records:
        print(f"WARNING: no CR3 files found in {folder}", file=sys.stderr)
        # Still write an empty CSV with headers so caller knows we ran.

    # Write CSV
    out_path = folder / "exif.csv"
    rows_written = 0
    rows_ok = 0

    try:
        with open(out_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow([
                "SourceFile", "DateTimeOriginal", "ExposureTime",
                "ISO", "BrightnessValue", "GPSLat", "GPSLon", "Status"
            ])

            for rec in records:
                # exiftool returns SourceFile as full path; we want just filename
                src = Path(rec.get("SourceFile", "")).name

                dt_raw = rec.get("DateTimeOriginal")
                dt_iso = parse_datetime(dt_raw)

                exp = to_float(rec.get("ExposureTime"))
                iso = to_float(rec.get("ISO"))
                bv = to_float(rec.get("BrightnessValue"))
                lat = to_float(rec.get("GPSLatitude"))
                lon = to_float(rec.get("GPSLongitude"))

                # Determine status — first failure wins
                if dt_iso is None:
                    status = "no_datetime"
                elif exp is None:
                    status = "no_exposure"
                elif iso is None:
                    status = "no_iso"
                else:
                    status = "ok"
                    rows_ok += 1

                writer.writerow([
                    src,
                    dt_iso if dt_iso else "",
                    exp if exp is not None else "",
                    int(iso) if iso is not None else "",
                    bv if bv is not None else "",
                    lat if lat is not None else "",
                    lon if lon is not None else "",
                    status,
                ])
                rows_written += 1

    except OSError as e:
        print(f"ERROR: could not write {out_path}: {e}", file=sys.stderr)
        return 1

    print(f"Wrote {rows_written} rows ({rows_ok} ok) to {out_path}",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
