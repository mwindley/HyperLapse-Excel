# luminance.py
# Called by Excel VBA to calculate average luminance of a JPEG thumbnail
# Usage:  python luminance.py "C:\path\to\LastThumb.jpg"
# Output: single integer 0-255 (average luminance of centre crop)
#         or -1 on error
#
# Place this file in: C:\Users\[username]\Documents\luminance.py
# Requires: pip install Pillow

import sys
import os

try:
    from PIL import Image

    if len(sys.argv) < 2:
        print(-1)
        sys.exit(1)

    jpg_path = sys.argv[1]

    if not os.path.exists(jpg_path):
        print(-1)
        sys.exit(1)

    # Open image and convert to greyscale
    img = Image.open(jpg_path).convert('L')
    w, h = img.size

    # Sample centre 60% to avoid edge vignetting on 160x120 thumbnail
    crop = img.crop((
        int(w * 0.2),
        int(h * 0.2),
        int(w * 0.8),
        int(h * 0.8)
    ))

    # Calculate average luminance
    pixels = list(crop.getdata())
    avg = sum(pixels) // len(pixels)
    print(avg)

except Exception as e:
    print(-1)
