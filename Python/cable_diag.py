# Diagnostic: run the real cable-strip unwrap on the actual workbook and print
# each GP's cart-frame + cumulative wind, to locate where the span inflates.
#   python cable_diag.py "C:\Github\HyperLapse-Excel\HyperLapse.xlsm"
import sys
from gimbal_planview_v2 import resolve
p = sys.argv[1] if len(sys.argv)>1 else r"C:\Github\HyperLapse-Excel\HyperLapse.xlsm"
d = resolve(p)
gps = d["gps"]; h0 = d["wp_hdg"]
print(f"cart anchor heading wp_hdg = {h0}")
def step_dir(short,dd):
    if dd=="CW":  return short if short>=0 else short+360
    if dd=="CCW": return short if short<=0 else short-360
    return short
prev_w=None; prev_u=0.0
for g in gps:
    h=g["cart_hdg"]; tr=g.get("track"); dd=g["dir"]
    if tr:
        azs=[((s[0]-h+540)%360)-180 for s in tr]
        if prev_w is None: u0=azs[0]
        else:
            short=((azs[0]-prev_w+540)%360)-180; u0=prev_u+step_dir(short,dd)
        u=u0; pw=azs[0]
        for w in azs[1:]:
            short=((w-pw+540)%360)-180; u+=short; pw=w
        print(f"{g['step']:5} TRACK dir={dd}  cart-hdg={h:.0f}  cf {azs[0]:.0f}->{azs[-1]:.0f}  cumU {u0:.0f}->{u:.0f}")
        prev_w=azs[-1]; prev_u=u
    else:
        w=((g['world']-h+540)%360)-180
        if prev_w is None: u=w
        else:
            short=((w-prev_w+540)%360)-180; u=prev_u+step_dir(short,dd)
        print(f"{g['step']:5} POINT dir={dd}  cart-hdg={h:.0f}  world={g['world']:.0f} cf={w:.0f}  cumU {u:.0f}  (short_from_prev={None if prev_w is None else ((w-prev_w+540)%360)-180:.0f})")
        prev_w=w; prev_u=u
