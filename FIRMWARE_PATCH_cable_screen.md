# Firmware patch — Cable screen (view #3, cart side)

Six edits to `DJI_Ronin_Giga_v2.ino` (read against soak-v101). All additive;
the jog engine (`/preview/step`, `previewGoto` — already eases) is reused
unchanged. Line numbers are landmarks from the file you shared; paste by
context, not blind line number.

Reuses: `preview_plan[]`/`preview_idx` (jog), the `?screen=` UI routing,
the `chart_svg` chunk pattern, `urlDecode`, `/exec/feed` (for run state).

---

## Edit 1 — state (after `chart_yaw_min`, ~line 3931)

```cpp
static String  cable_svg     = "";        // authored inner SVG fragment (cable strip)
static float   cable_yaw_min = 0.0f;      // left edge of the 450deg yaw axis (cable strip)
static float   cable_gp_x[PREVIEW_PLAN_MAX]; // per-GP strip x (0..355), index-aligned to preview poses
static int     cable_gp_n    = 0;         // count of cable_gp_x entries
```

---

## Edit 2 — `/settings/cablesvg` handler (immediately AFTER the
`/settings/chartsvg` else-if block, ~line 7270)

Twin of chartsvg; on idx=0 it also loads the per-GP strip-x list (`gpx`,
comma-separated) for the index-driven marker. `d=` stays last.

```cpp
    // /settings/cablesvg?idx=N&last=0|1&yawmin=F&gpx=csv&d=<urlenc inner SVG chunk>
    // Cable-strip twin of /settings/chartsvg. idx=0 clears, sets yaw_min,
    // and loads gpx (per-GP strip x, index-aligned to preview poses). d=last.
    } else if (path.startsWith("/settings/cablesvg")) {
        auto qStr = [&](const char* key) -> String {
            String k = String(key) + "="; int i = path.indexOf(k);
            if (i < 0) return String();
            int st = i + k.length(); int en = path.indexOf('&', st);
            return (en < 0) ? path.substring(st) : path.substring(st, en);
        };
        int cidx = qStr("idx").toInt();
        if (cidx == 0) {
            cable_svg = "";
            String ym = qStr("yawmin"); if (ym.length()) cable_yaw_min = ym.toFloat();
            cable_gp_n = 0;
            String gx = qStr("gpx");
            while (gx.length() && cable_gp_n < PREVIEW_PLAN_MAX) {
                int c = gx.indexOf(',');
                cable_gp_x[cable_gp_n++] = ((c < 0) ? gx : gx.substring(0, c)).toFloat();
                if (c < 0) break;
                gx = gx.substring(c + 1);
            }
        }
        cable_svg += urlDecode(qStr("d"));
        response = "OK cablesvg idx=" + String(cidx) + " len=" + String(cable_svg.length()) +
                   " gp=" + String(cable_gp_n);
```

---

## Edit 3 — jog interlock (in `/preview/step` ~line 7062 and
`/preview/goto` ~line 7076). Add a PLAN_RUNNING guard as the FIRST check.

`/preview/step` — change the opening test:

```cpp
    } else if (path.startsWith("/preview/step")) {
        if (plan_state == PLAN_RUNNING) {
            response = "ERROR: jog blocked - timelapse running";
        } else if (preview_count == 0) {
            response = "ERROR: no preview plan loaded";
        } else {
            // ...existing step body unchanged...
        }
```

`/preview/goto` — add the same guard before its existing body:

```cpp
    } else if (path.startsWith("/preview/goto")) {
        if (plan_state == PLAN_RUNNING) {
            response = "ERROR: jog blocked - timelapse running";
        } else {
            // ...existing goto body unchanged...
        }
```

(Authoritative gate. The page also disables the buttons, but this is the
real lock.)

---

## Edit 4 — allow the new screen (the `?screen=` validation, ~line 7932)

```cpp
        if (screen != "cart" && screen != "gimbal" && screen != "exec" && screen != "cable") screen = "cart";
```

---

## Edit 5 — nav tab (right after the Exec tab `<a>`, ~line 7979)

```cpp
        client.print  ("<a href='/?screen=cable'"); if (screen=="cable") client.print(" class='act'"); client.print(">Cable</a>");
```

---

## Edit 6 — the Cable screen branch (insert `} else if (screen == "cable") { ... }`
immediately BEFORE the `} else { // exec` branch, ~line 8265)

```cpp
        } else if (screen == "cable") {
            // Cable rigging screen: shows the yaw-sweep strip and jogs the
            // gimbal GP-to-GP via /preview/step so the operator can dress
            // cables. Interactive; jog blocked while a timelapse runs.
            client.println("<style>");
            client.println(".cwrap{padding:8px}");
            client.println(".clbl{font-family:sans-serif;font-size:12px;color:#6f6c64;padding:2px 0}");
            client.println(".cstrip{background:#0d141f;border-radius:8px;padding:6px}");
            client.println(".cstat{font-family:monospace;font-size:13px;color:#c9d4e3;text-align:center;padding:8px 0}");
            client.println(".cbtns{display:grid;grid-template-columns:1fr 1fr;gap:10px;padding-top:6px}");
            client.println(".cbtn{font-family:sans-serif;font-size:16px;font-weight:600;border:0;border-radius:8px;padding:16px 0;background:#7a8aa0;color:#fff}");
            client.println(".cbtn:disabled{background:#3a3f47;color:#777}");
            client.println("</style>");
            client.println("<div class='cwrap'>");
            client.println("<div class='clbl'>cable strip &middot; yaw 450&deg; span &middot; min left, limit right</div>");
            client.println("<div class='cstrip'>");
            client.print  ("<svg viewBox='0 0 355 90' preserveAspectRatio='none' style='width:100%;height:90px'>");
            if (cable_svg.length()) client.print(cable_svg);
            else client.print("<rect x='0' y='32' width='355' height='26' fill='#0d141f' stroke='#2b3340'/>");
            client.println("<rect id='cmark' x='-10' y='30' width='4' height='30' fill='#ffd24a'/></svg>");
            client.println("</div>");
            client.println("<div class='cstat' id='cstat'>--</div>");
            client.println("<div class='cbtns'>");
            client.println("<button class='cbtn' id='cprev' onclick='cstep(\"rev\")'>&larr; PREV</button>");
            client.println("<button class='cbtn' id='cnext' onclick='cstep(\"fwd\")'>NEXT &rarr;</button>");
            client.println("</div></div>");
            // per-GP strip x, index-aligned to preview poses (baked at serve time)
            client.print("<script>var CGPX=[");
            for (int i = 0; i < cable_gp_n; i++) { if (i) client.print(","); client.print(cable_gp_x[i], 1); }
            client.println("];");
            client.println("function cmark(idx){var m=document.getElementById('cmark');if(idx>=0&&idx<CGPX.length){m.setAttribute('x',(CGPX[idx]-2).toFixed(1));}else{m.setAttribute('x','-10');}}");
            client.println("function cpoll(){fetch('/preview/status').then(r=>r.json()).then(s=>{");
            client.println(" var t=(s.idx>=0)?('GP'+s.gp+'/'+s.count+' \\u00b7 '+(s.label||'')+' \\u00b7 '+s.yaw.toFixed(0)+'\\u00b0'):('-- \\u00b7 '+s.count+' GPs loaded');");
            client.println(" document.getElementById('cstat').innerHTML=t; cmark(s.idx);");
            client.println("}).catch(e=>{});}");
            client.println("function crun(cb){fetch('/exec/feed').then(r=>r.json()).then(f=>cb(f.state=='RUNNING')).catch(e=>cb(false));}");
            client.println("function cstep(d){crun(function(run){if(run){document.getElementById('cstat').innerHTML='jog blocked \\u2014 timelapse running';return;}fetch('/preview/step?dir='+d).then(r=>r.text()).then(t=>{setTimeout(cpoll,150);});});}");
            client.println("function cguard(){crun(function(run){document.getElementById('cprev').disabled=run;document.getElementById('cnext').disabled=run;});}");
            client.println("cpoll();cguard();setInterval(function(){cpoll();cguard();},2000);");
            client.println("</script>");
```

---

## Notes / limits

- **Jog ease:** unchanged (`previewGoto` timed slew, distance-proportional)
  per your call. The marker snaps to the target GP x on each step; the
  physical move eases.
- **Index alignment (the one caveat):** `cable_gp_x[]` is index-aligned to
  the preview poses ONLY while the plan is chassis/marker (Move/Lock/Pan
  Follow), because `CableStripPush` charts exactly those, in plan order, as
  the preview pusher emits them. When astro Track GPs are added (preview
  emits start+end; the strip skips them), the indices diverge and the
  marker would mis-place. Fix at that time: make `CableStripPush` enumerate
  identically to `PushPreviewPlanToCart`. Captured in WORKFRONT_cable_ui.md.
- **Run-state source:** the page checks `/exec/feed` (JSON, has `state`),
  not `/plan/status` (that returns CSV).
- **Preview plan must be loaded** for the jog: run `PushPreviewPlanToCart`
  (and `PushCableStripToCart`) before using the Cable screen.
```
