#!/usr/bin/env python3
"""
HyperLapse — Gimbal Plan View (#2), production renderer.
Spec: GIMBAL_PLANVIEW_BUILD.md.

Step A (resolve) + Step C (render). Reads HyperLapse.xlsm directly.

Per GP:
  - frame: earth if target in {sun,moon,gc} or Action in {Track,Track-yaw};
           else chassis.
  - cart-frame yaw/pitch accumulate (numeric Ry/Rp = absolute anchor).
  - world bearing:
        chassis : expected_cart_heading(anchor WP) + cart_frame_yaw
        earth   : object_az(fire time) + dyaw   [+ heading-correction scalar]
  - cumulative cart-frame yaw carried signed/un-wrapped (cable + midpoint).

Render:
  - cart centre, true-N up, radius = altitude (horizon rim, zenith centre)
  - GP glyph = radial line rim->endpoint, dir = world bearing,
    length proportional to pitch (endpoint sits on the altitude grid)
  - earth vs chassis styled distinctly
  - midpoint on near-180 cart-frame slews, labelled cumulative yaw
  - park-and-wait marker for below-horizon earth objects
  - shared validation flags (pitch > 80)
  - PREV/NEXT: --gp N foregrounds one GP
  - map underlay v1: --map north_up.png (decorative, clipped to dial)

Usage: python3 gimbal_planview_v2.py HyperLapse.xlsm out.png [--gp 3] [--map t.png]
"""
import sys, math, argparse
from openpyxl import load_workbook
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Circle, FancyArrowPatch

BG="#0d1117"; RING="#2b3340"; RINGTXT="#5b6675"; CARD="#c9d4e3"
CHASSIS="#36d399"; EARTH={"sun":"#ffb02e","gc":"#9b8cff","moon":"#7fd4ff"}
EARTH_DEF="#ffb02e"; HDG="#ff5c7a"; FLAG="#ff5470"; MID="#ffd24a"; TXT="#e6edf3"
DIM=0.22
R=1.0
NEAR180=150.0           # cart-frame |dyaw| that triggers a direction midpoint
PITCH_LIMIT=80.0
OBJ_COL={"sun":(3,4),"gc":(1,2)}   # AstroTable (az_col, alt_col) by object

def alt_to_r(alt): return max(0.0,min(1.0,(90.0-max(0,min(90,alt)))/90.0))*R
def az_to_xy(az,r):
    a=math.radians(az); return r*math.sin(a), r*math.cos(a)

# ---------- Step A: read + resolve ----------
def resolve(path):
    wb=load_workbook(path,read_only=True,data_only=True)

    s={}
    for row in wb["Settings"].iter_rows(min_row=1,max_row=60,max_col=4,values_only=True):
        if row[1] is not None: s[str(row[1]).strip()]=row[2]
    lat=float(s.get("Latitude",0)); lon=float(s.get("Longitude",0))

    arows=list(wb["AstroTable"].iter_rows(values_only=True))
    def cell(r,i):
        try: return float(r[i])
        except (TypeError,ValueError,IndexError): return None
    astro=[]
    for r in arows[1:]:
        if r[0] is None: continue
        gca,gcl,sa,sal=cell(r,1),cell(r,2),cell(r,3),cell(r,4)
        if None in (gca,gcl,sa,sal): continue
        rec=dict(t=str(r[0]),gc_az=gca,gc_alt=gcl,sun_az=sa,sun_alt=sal)
        ma,mal=cell(r,6),cell(r,7)            # cols G/H = Moon Az/Alt (present after step 3)
        if ma is not None and mal is not None:
            rec["moon_az"]=ma; rec["moon_alt"]=mal
        astro.append(rec)

    prows=list(wb["Plan"].iter_rows(min_row=1,max_row=80,max_col=30,values_only=True))
    # header row
    hdr=next(i for i,r in enumerate(prows) if any(str(v).strip()=="Step" for v in r if v))
    # cart WP -> heading (col B id, col H heading)
    wp_hdg={}
    for r in prows[hdr+1:]:
        if r[1] and str(r[1]).strip().startswith("WP"):
            try: wp_hdg[str(r[1]).strip()]=float(r[7])
            except (TypeError,ValueError): pass

    def fire_minutes(q):
        if q is None: return None
        try:
            t=str(q); h,m,*_=t.split(":"); return int(h)*60+int(m)
        except Exception: return None
    KEYS={"sun":("sun_az","sun_alt"),"gc":("gc_az","gc_alt"),"moon":("moon_az","moon_alt")}
    def astro_az(obj,fire_q):
        key=fire_minutes(fire_q)
        if key is None or obj not in KEYS: return None,None
        azc,altc=KEYS[obj]
        best=None
        for p in astro:
            if azc not in p: continue          # moon absent until table regenerated
            pm=fire_minutes(p["t"])
            if pm is None: continue
            d=abs(((pm-key+720)%1440)-720)
            if best is None or d<best[0]: best=(d,p[azc],p[altc])
        return (best[1],best[2]) if best else (None,None)

    gps=[]
    for r in prows[hdr+1:]:
        step=r[12]
        if step is None or str(step).strip()=="": continue
        act=str(r[18]).strip() if r[18] else ""
        if act.upper()=="END": break
        anchor=str(r[14]).strip() if r[14] else ""
        target=str(r[19]).strip().lower() if r[19] else ""
        target=target if target in ("sun","gc","moon") else ""
        def num(c):
            try: return float(r[c])
            except (TypeError,ValueError): return None
        ry,rp,dy,dp=num(21),num(22),num(23),num(24)
        dlbl=str(r[28]).strip().upper() if r[28] else None
        dlbl=dlbl if dlbl in ("CW","CCW") else None

        # NON-cumulative, per-GP. Ry/Rp = real-world (earth) anchor; blank Ry = cart-frame.
        if ry is not None:                       # earth-frame: Ry is the world bearing
            world=(ry+(dy or 0))%360
            frame="earth"; below=False; oaz=oalt=None
            pitch=(rp if rp is not None else 0.0)+(dp or 0.0)
        elif target:                              # earth-frame astro: object az at fire time
            oaz,oalt=astro_az(target,r[16])
            world=((oaz or 0)+(dy or 0))%360
            frame="earth"; below=(oalt is not None and oalt<=0)
            pitch=(rp if rp is not None else 0.0)+(dp or 0.0)
        else:                                     # chassis-frame: offset from cart heading
            h=wp_hdg.get(anchor,0.0)
            world=(h+(dy or 0))%360
            frame="chassis"; below=False; oaz=oalt=None
            pitch=(rp if rp is not None else 0.0)+(dp or 0.0)
        gps.append(dict(step=str(step).strip(),act=act,frame=frame,target=target,
                        anchor=anchor,world=world,yaw_off=(dy or 0.0),ry=ry,pitch=pitch,
                        below=below,obj_az=oaz,obj_alt=oalt,dir=dlbl))
    # cable wind-up: gimbal's running cart-frame angle (unwrapped), even though
    # plan yaw values are per-GP references. cart-frame yaw = world - heading.
    cable=0.0; prev_cf=None
    for g in gps:
        h=wp_hdg.get(g["anchor"],0.0)
        cf=((g["world"]-h+540)%360)-180          # cart-frame target, wrapped to +/-180
        if prev_cf is None:
            cable=cf; step=0.0
        else:
            short=((cf-prev_cf+540)%360)-180          # shortest signed step
            if g["dir"]=="CW":   step=short if short>=0 else short+360
            elif g["dir"]=="CCW":step=short if short<=0 else short-360
            else:                step=short            # auto = shortest
            cable+=step
        g["cf_yaw"]=cf; g["cable"]=cable; g["slew"]=step
        prev_cf=cf
    return dict(lat=lat,lon=lon,astro=astro,gps=gps,wp_hdg=wp_hdg)

# ---------- Step C: render ----------
def render(d,out,hi=None,map_img=None):
    fig,ax=plt.subplots(figsize=(9.5,9.5),dpi=160)
    fig.patch.set_facecolor(BG); ax.set_facecolor(BG)
    ax.set_xlim(-1.38,1.38); ax.set_ylim(-1.42,1.34); ax.set_aspect("equal"); ax.axis("off")

    if map_img:
        try:
            im=plt.imread(map_img); ax.imshow(im,extent=[-R,R,-R,R],zorder=0,alpha=0.5)
            clip=Circle((0,0),R,transform=ax.transData)
            for a in ax.images: a.set_clip_path(clip)
        except Exception as e: print("map underlay skipped:",e)

    for alt,lab in [(0,"horizon"),(30,"30\u00b0"),(60,"60\u00b0")]:
        rr=alt_to_r(alt); ax.add_patch(Circle((0,0),rr,fill=False,ec=RING,lw=1,zorder=1))
        if alt>0: ax.text(0,rr," "+lab,color=RINGTXT,fontsize=7,va="bottom",ha="left",zorder=2)
    ax.plot(0,0,marker="+",color=RINGTXT,ms=8,zorder=2)
    for az in range(0,360,30):
        x,y=az_to_xy(az,R); ax.plot([0,x],[0,y],color=RING,lw=0.6,zorder=1)
    for az,lab in [(0,"N"),(90,"E"),(180,"S"),(270,"W")]:
        x,y=az_to_xy(az,R*1.12); ax.text(x,y,lab,color=CARD,fontsize=14,fontweight="bold",
                                          ha="center",va="center",zorder=3)

    # faint astro context arcs (sun, gc, + moon when the table has it)
    arc_specs=[(("sun_az","sun_alt"),EARTH["sun"]),(("gc_az","gc_alt"),EARTH["gc"])]
    if any("moon_az" in p for p in d["astro"]):
        arc_specs.append((("moon_az","moon_alt"),EARTH["moon"]))
    for key,col in arc_specs:
        seg=[az_to_xy(p[key[0]],alt_to_r(p[key[1]])) for p in d["astro"]
             if key[0] in p and p[key[1]]>0]
        if seg: ax.plot([p[0] for p in seg],[p[1] for p in seg],color=col,lw=1.2,alpha=0.30,zorder=2)

    gps=d["gps"]

    # ---- world-sweep legs: GP1->GP2->... arrowed arcs along the short way ----
    def leg_alpha(i):
        if hi is None: return 0.9
        names={gps[i]["step"],gps[i+1]["step"]}
        focus = hi if isinstance(hi,str) else "GP%02d"%hi
        return 0.9 if focus in names else DIM
    nlegs=len(gps)-1
    for i in range(nlegs):
        legr=R*(0.72+0.055*i)                      # fan consecutive legs onto separate radii
        a0=gps[i]["world"]; a1=gps[i+1]["world"]
        dlbl=gps[i+1]["dir"]
        short=((a1-a0+540)%360)-180
        if dlbl=="CW":    diff=short if short>=0 else short+360
        elif dlbl=="CCW": diff=short if short<=0 else short-360
        else:             diff=short               # auto = shortest
        amb = (dlbl is None) and abs(abs(short)-180)<=30   # only flag if not yet chosen
        n=max(2,int(abs(diff)/4))
        pts=[az_to_xy((a0+diff*k/n)%360,legr) for k in range(n+1)]
        la=leg_alpha(i)
        col_leg = MID if (dlbl and abs(diff)>180.5) else CARD   # highlight a forced long-way leg
        ax.plot([p[0] for p in pts],[p[1] for p in pts],color=col_leg,lw=1.6,alpha=0.6*la,
                ls=("--" if amb else "-"),zorder=4)
        ax.add_patch(FancyArrowPatch(pts[-2],pts[-1],color=col_leg,lw=0,arrowstyle="-|>",
                     mutation_scale=15,alpha=0.85*la,zorder=4))
        # leg label: number + chosen direction (or AUTO)
        sx,sy=az_to_xy((a0+diff*0.12)%360,legr)
        tag=f"{i+1}\u2192{i+2}" + (f" {dlbl}" if dlbl else "")
        ax.text(sx,sy,tag,color=col_leg,fontsize=7,alpha=0.8*la,ha="center",va="center",zorder=5)
        if amb:
            mx,my=az_to_xy((a0+short/2)%360,legr)
            ax.plot(mx,my,"D",color=MID,ms=8,alpha=la,zorder=5,mec=BG,mew=1)
            ax.annotate(f"leg {i+1}\u2192{i+2}: ~180\u00b0 \u2014 set CW/CCW (col AC)",(mx,my),
                        color=MID,fontsize=7,alpha=la,ha="center",va="bottom",
                        xytext=(0,9+10*i),textcoords="offset points",zorder=8)

    prev=None; seen={}; idx=1
    for gp in gps:
        foreground = (hi is None) or (gp["step"]==hi) or (gp["step"]==("GP%02d"%hi) if isinstance(hi,int) else False)
        a = 1.0 if foreground else DIM
        col = CHASSIS if gp["frame"]=="chassis" else EARTH.get(gp["target"],EARTH_DEF)

        # below-horizon earth object -> park-and-wait marker at rise, no glyph line
        if gp["frame"]=="earth" and gp["below"]:
            wx,wy=az_to_xy(gp["world"],R)
            ax.plot(wx,wy,marker="P",color=col,ms=14,alpha=a,zorder=6,mec=BG,mew=1)
            ax.text(wx,wy,str(idx),color=BG,fontsize=8,fontweight="bold",ha="center",va="center",
                    alpha=a,zorder=9)
            ax.annotate(gp["step"]+" goto-rise + wait",(wx,wy),color=col,fontsize=7.5,alpha=a,
                        ha="center",va="top",xytext=(0,-10),textcoords="offset points",zorder=8)
            prev=gp; idx+=1; continue

        # glyph: radial line rim -> endpoint at altitude(pitch); length ∝ pitch
        pitch=gp["pitch"]; flag = pitch>PITCH_LIMIT
        endr=alt_to_r(pitch)                         # near centre = high pitch
        ex,ey=az_to_xy(gp["world"],endr)
        rx,ry=az_to_xy(gp["world"],R)                # rim foot
        ls = "-" if gp["frame"]=="chassis" else (0,(6,2))
        ax.plot([rx,ex],[ry,ey],color=col,lw=2.6,ls=ls,alpha=a,zorder=5,solid_capstyle="round")
        ax.plot(ex,ey,"o",color=col,ms=8,alpha=a,zorder=6,mec=BG,mew=1)
        if flag:
            ax.plot(ex,ey,"o",mfc="none",mec=FLAG,ms=15,mew=2.2,alpha=a,zorder=7)
        lab=f"{gp['step']}  {pitch:.0f}\u00b0p"
        key=(round(gp["world"]),round(min(pitch,90)))
        dy=-12*seen.get(key,0); seen[key]=seen.get(key,0)+1
        ax.annotate(lab,(ex,ey),color=(FLAG if flag else col),fontsize=8,alpha=a,
                    ha="left",va="center",xytext=(8,dy),textcoords="offset points",zorder=8)

        # sequence badge on the glyph endpoint
        bx,by=az_to_xy(gp["world"],endr)
        ax.plot(bx,by,"o",color=col,ms=15,alpha=a,zorder=8,mec=BG,mew=1.5)
        ax.text(bx,by,str(idx),color=BG,fontsize=9,fontweight="bold",ha="center",va="center",
                alpha=a,zorder=9)
        prev=gp; idx+=1

    # legend
    handles=[
        Line2D([0],[0],color=CHASSIS,lw=2.6,label="chassis-frame GP (cart-nose + offset)"),
        Line2D([0],[0],color=EARTH_DEF,lw=2.6,ls=(0,(6,2)),label="earth-frame GP (points at object)"),
        Line2D([0],[0],color=CARD,lw=1.6,marker=">",alpha=0.7,label="GP sweep order (1\u21922\u21923\u21924)"),
        Line2D([0],[0],color=MID,marker="D",lw=1,ls="--",label="~180\u00b0 sweep \u2014 direction ambiguous, set midpoint"),
        Line2D([0],[0],marker="o",mfc="none",mec=FLAG,lw=0,ms=10,label="pitch > 80\u00b0 flag"),
        Line2D([0],[0],color=EARTH["gc"],lw=1.2,alpha=0.4,label="astro context arcs (sun / GC)"),
    ]
    ax.legend(handles=handles,loc="lower center",bbox_to_anchor=(0.5,-0.11),ncol=1,
              frameon=False,fontsize=8.5,labelcolor=TXT,handlelength=2.4)
    sub = "" if hi is None else f"   |   focus: {hi if isinstance(hi,str) else 'GP%02d'%hi}"
    ax.set_title("Gimbal Plan View  —  glyph dir = world bearing, length = pitch"+sub,
                 color=TXT,fontsize=12,pad=14)
    ax.text(0,-1.33,f"lat {d['lat']:.4f}, lon {d['lon']:.4f}   |   cart at centre, N up, radius = altitude",
            color=RINGTXT,fontsize=8,ha="center")

    fig.savefig(out,facecolor=BG,bbox_inches="tight")
    svg=out.rsplit(".",1)[0]+".svg"; fig.savefig(svg,facecolor=BG,bbox_inches="tight")
    print("wrote",out,"and",svg)

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("xlsm"); ap.add_argument("out",nargs="?",default="gimbal_planview_v2.png")
    ap.add_argument("--gp",type=int,default=None); ap.add_argument("--map",default=None)
    a=ap.parse_args()
    d=resolve(a.xlsm)
    for g in d["gps"]:
        print(g["step"],g["frame"],"world=%.0f"%g["world"],"pitch=%.0f"%g["pitch"],
              "cf_yaw=%+.0f"%g["cf_yaw"],"cable=%+.0f"%g["cable"],"slew=%+.0f"%g["slew"])
    render(d,a.out,hi=a.gp,map_img=a.map)
