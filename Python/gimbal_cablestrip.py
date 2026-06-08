#!/usr/bin/env python3
"""
HyperLapse — Gimbal Cable Strip (view #3).

Shows the gimbal's yaw sweep as an UNWRAPPED world bearing (relative to
true North), accumulated leg-by-leg in the direction the operator set in
Plan col AC (CW/CCW; blank = shortest). Plotted on a 1-D strip against the
450 deg span limit: min yaw on the left, min+450 (the hard ceiling where
cables break) on the right.

It reuses resolve() from gimbal_planview_v2 (single source of truth), so
frame/world/dir come out identical to the dial. This view adds only the
unwrap-to-world and the strip drawing.

The tool SHOWS what the plan says; it does not pick direction. Operator
sets col AC (proposed by the sweep-dir macro, accepted/overridden by the
operator using the dial and/or this strip).

Usage:
  python3 gimbal_cablestrip.py HyperLapse.xlsm out.png [--gp N] [--limit 450]
"""
import argparse
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, Rectangle
from gimbal_planview_v2 import (resolve, BG, RING, RINGTXT, CARD, CHASSIS,
                                MID, FLAG, TXT)

USED="#3b82f6"      # used-span fill
FREE="#1f2a37"      # headroom fill
LIMIT="#ff5470"     # span-limit line

def unwrap_world(gps):
    """Accumulate world bearing leg-by-leg honouring col AC; returns list."""
    wu=[]; prev_w=None; prev_u=0.0
    for g in gps:
        w=g["world"]
        if prev_w is None:
            u=w
        else:
            short=((w-prev_w+540)%360)-180          # shortest signed step
            d=g["dir"]
            if d=="CW":    step=short if short>=0 else short+360
            elif d=="CCW": step=short if short<=0 else short-360
            else:          step=short               # auto = shortest
            u=prev_u+step
        wu.append(u); prev_w=w; prev_u=u
    return wu

def render(d, out, hi=None, limit=450.0):
    gps=d["gps"]
    if not gps:
        print("no GPs in plan"); return
    wu=unwrap_world(gps)
    lo=min(wu); hi_used=max(wu); span=hi_used-lo
    ceil=lo+limit; headroom=ceil-hi_used
    imax=wu.index(hi_used)                          # turn-around / max-wind GP

    fig,ax=plt.subplots(figsize=(11,3.4))
    ax.set_xlim(lo-15, ceil+15); ax.set_ylim(-1.0,1.4)
    ax.axis("off")

    y=0.0
    # full track, used span, headroom
    ax.add_patch(Rectangle((lo,y-0.13),ceil-lo,0.26,facecolor=FREE,edgecolor=RING,lw=1,zorder=1))
    ax.add_patch(Rectangle((lo,y-0.13),span,0.26,facecolor=USED,edgecolor="none",alpha=0.45,zorder=2))
    # limit line (right end) + min mark
    ax.plot([ceil,ceil],[y-0.32,y+0.32],color=LIMIT,lw=2.5,zorder=5)
    ax.text(ceil,y+0.42,f"span limit  {limit:.0f}\u00b0\n(cables break beyond)",
            color=LIMIT,fontsize=8,ha="center",va="bottom")
    ax.plot([lo,lo],[y-0.32,y+0.32],color=RINGTXT,lw=1.5,zorder=5)
    ax.text(lo,y-0.42,f"min  {lo:.0f}\u00b0",color=RINGTXT,fontsize=8,ha="center",va="top")

    # sweep order arrows between consecutive GPs (above the strip)
    for i in range(len(wu)-1):
        a,b=wu[i],wu[i+1]
        col=CHASSIS if b>=a else FLAG
        ax.add_patch(FancyArrowPatch((a,y+0.16),(b,y+0.16),
            connectionstyle="arc3,rad=0.45",arrowstyle="-|>",mutation_scale=12,
            color=col,lw=1.4,alpha=0.85,zorder=4))

    # alternate label side by x-order so near-coincident GPs don't overlap
    side={}; order=sorted(range(len(wu)),key=lambda i:wu[i])
    for k,i in enumerate(order): side[i]=(k%2==0)   # True=above

    # GP markers (label uses the UNWRAPPED swept value, e.g. 440 not 80)
    for i,(g,x) in enumerate(zip(gps,wu)):
        focus = (hi is not None and (g["step"]==(hi if isinstance(hi,str) else None)
                                     or i+1==hi))
        ismax=(i==imax)
        c = MID if focus else (LIMIT if ismax else CARD)
        ax.plot([x],[y],marker="o",ms=11 if (focus or ismax) else 8,
                color=c,zorder=6,markeredgecolor=BG,markeredgewidth=1.2)
        lab=f"{g['step']}\n{wu[i]:.0f}\u00b0"
        if ismax: lab+="  (max)"
        up=side[i]
        ax.text(x, y+0.32 if up else y-0.32, lab, color=c,fontsize=8.5,
                ha="center", va="bottom" if up else "top", zorder=6)

    ax.set_title("Gimbal Cable Strip  —  yaw sweep (world bearing, unwrapped via col AC) vs span limit",
                 color=TXT,fontsize=12,pad=12)
    sub=(f"used span {span:.0f}\u00b0   |   headroom to limit {headroom:.0f}\u00b0   |   "
         f"max-wind {gps[imax]['step']} at {hi_used:.0f}\u00b0")
    if headroom<0: sub+="   ***  EXCEEDS LIMIT  ***"
    ax.text((lo+ceil)/2,-0.78,sub,color=(LIMIT if headroom<0 else RINGTXT),
            fontsize=9,ha="center")

    fig.savefig(out,facecolor=BG,bbox_inches="tight")
    svg=out.rsplit(".",1)[0]+".svg"; fig.savefig(svg,facecolor=BG,bbox_inches="tight")
    print("wrote",out,"and",svg)
    print("min %.0f  max %.0f  span %.0f  headroom %.0f"%(lo,hi_used,span,headroom))

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("xlsm"); ap.add_argument("out",nargs="?",default="gimbal_cablestrip.png")
    ap.add_argument("--gp",type=int,default=None)
    ap.add_argument("--limit",type=float,default=450.0)
    a=ap.parse_args()
    d=resolve(a.xlsm)
    render(d,a.out,hi=a.gp,limit=a.limit)
