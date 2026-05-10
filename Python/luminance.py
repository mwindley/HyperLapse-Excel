# luminance.py
# Called by Excel VBA to calculate average luminance of a JPEG thumbnail.
#
# Usage:  python luminance.py "C:\path\to\LastThumb.jpg"
#
# Output (stdout): single integer 0-255 (average luminance of centre crop)
#                  or -1 on error
# Output (stderr): on failure, a short human-readable description of WHY
#                  it failed. Excel's CalcLuminance reads stderr and logs
#                  this when stdout is non-numeric or -1, so the operator
#                  can see Pillow-missing / file-not-found / unreadable-
#                  jpeg etc. without running the script manually.
#
# Place this file in the repo's Python/ folder. Excel's FindLuminanceScript
# searches there first.
#
# Requires: pip install Pillow

import sys
import os
import traceback


def fail(msg):
    """Print an error message to stderr and -1 to stdout, then exit non-zero."""
    print(msg, file=sys.stderr)
    print(-1)
    sys.exit(1)


# ─── Argument check ──────────────────────────────────────────────────
if len(sys.argv) < 2:
    fail("luminance.py: no image path argument")

jpg_path = sys.argv[1]

if not os.path.exists(jpg_path):
    fail(f"luminance.py: file not found: {jpg_path}")

# ─── Pillow import ───────────────────────────────────────────────────
try:
    from PIL import Image, ImageStat
except ImportError as e:
    fail(f"luminance.py: Pillow not installed ({e}). "
         f"Fix: pip install Pillow")

# ─── Image processing ────────────────────────────────────────────────
try:
    img = Image.open(jpg_path)
    img.load()                          # force decode now so errors surface here
    img = img.convert('L')              # convert to greyscale (0-255)
    w, h = img.size

    if w == 0 or h == 0:
        fail(f"luminance.py: image has zero dimensions (w={w}, h={h})")

    # Sample centre 60% to avoid edge vignetting on 160x120 thumbnail
    crop = img.crop((
        int(w * 0.2),
        int(h * 0.2),
        int(w * 0.8),
        int(h * 0.8),
    ))

    # ImageStat.Stat(...).mean returns mean per band; band 0 is the only
    # band on a greyscale ('L') image. This replaces the deprecated
    # crop.getdata() / sum() / len() approach (Pillow 14+ removes getdata).
    avg = int(ImageStat.Stat(crop).mean[0])
    print(avg)

except Exception as e:
    # Verbose diagnostic — full traceback goes to stderr so we can see
    # what went wrong from Excel's log.
    tb = traceback.format_exc()
    fail(f"luminance.py: exception {type(e).__name__}: {e}\n{tb}")
