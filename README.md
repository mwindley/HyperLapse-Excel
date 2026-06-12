# HyperLapse Excel Controller

Excel VBA workbook (HyperLapse.xlsm) — the planning brain for the HyperLapse
Cart: a fully automated overnight astrophotography timelapse rig combining a
motorised cart, DJI Ronin RS4 Pro gimbal, and Canon EOS R3 camera. Plans are
authored here and pushed to the cart; the cart runs them self-contained from its
on-board web UI.

## System Overview

```
Excel Workbook (laptop in van)
  │
  ├── WiFi → Arduino Giga R1 (192.168.1.97)
  │           ├── CAN → DJI Ronin RS4 Pro gimbal (Adafruit CAN Pal 5708)
  │           ├── I2C → Tic 36v4 stepper controllers (cart motors, addr 14/15)
  │           ├── I2C → BNO085 IMU (heading reference, addr 0x4A)
  │           └── Servo → Cart steering
  │
  └── WiFi → Canon EOS R3 CCAPI (192.168.1.99:8080)
              └── Camera settings, shutter cadence, luminance/thumbnail retrieval
```

(A wired-Ethernet CCAPI path over a W5500 on the .20.x subnet is reserved as a
future build; current production runs CCAPI over WiFi.)

## Projects

| # | Project | Status |
|---|---------|--------|
| 1 | DJI Ronin RS4 Pro gimbal control via Arduino CAN | ✅ Done |
| 2 | Motorised SCX6 cart (Tic 36v4 steppers + servo) | ✅ Done |
| 3 | Astro tracking (sun / moon / Galactic Centre), cubic-fit gimbal paths | ✅ Working |
| 4 | Canon CCAPI camera control + overnight Tv/ISO luminance ramp | ✅ Working |
| 5 | Plan authoring + push pipeline (Excel → cart) | ✅ Working |
| 6 | On-cart Exec web UI (START / E-STOP, field-self-contained) | ✅ Working |

## Repository Structure

```
HyperLapse-Excel/
  Modules/   (~33 .bas modules; key ones by role)
    Astronomy:   Astro.bas (sun/moon/GC ephemeris + rise/transit/set solvers),
                 AstroPush.bas (cubic-fit track paths + zenith-band ease + push)
    Plan author: PlanAuthoring, PlanBuilder, PlanCols (header-name resolver),
                 PlanDVFix (dropdowns), GimbalSweepDir (CW/CCW), MWToGCRenamer
    Push:        CartPlanPush, TrackPlanPush, PlanPush (preview), ChartPush,
                 CableStripPush, CableSpan (450 deg guard), GimbalPrep (orchestrator)
    Camera/exp:  Camera.bas (CCAPI), Formula.bas (Tv/ISO ramp + /exposure/load),
                 Sequence.bas (phase loop)
    Cart/recon:  Cart.bas, BicycleModel.bas (heading integration), CircleFit,
                 WobblyRecon, GimbalLogPuller (recon -> Plan rows)
    Viz:         GimbalPlanViz_v3 (validation chart), GimbalPlanViewButton,
                 GimbalCableStripButton, GimbalMapFetch
    Shared:      Utils.bas, Buttons.bas, Gimbal.bas, Smooth.bas, BackupRestore.bas
  Python/
    gimbal_planview_v2.py   Polar plan-view + cable-strip renderer
    gimbal_cablestrip.py    Cable-span renderer (writes cablestrip_span.txt sidecar)
    luminance.py            Thumbnail luminance calculator (called by VBA)
  README.md
```

## Workbook Structure

| Sheet | Purpose |
|-------|---------|
| Settings | IP addresses, location (lat/lng/UTC), named ranges |
| Monitor | Live status — phase, ISO, Tv, luminance, gimbal, cart, heartbeat |
| Sequence | Phase table — time offsets, camera settings, gimbal angles |
| CartLog | Scout run event log — speed and steering events |
| GimbalLog | Gimbal waypoint log — manually captured yaw/pitch positions |
| Log | Full timestamped event log for the shoot |

## Named Ranges (Settings Sheet)

| Range | Description | Default |
|-------|-------------|---------|
| dataCameraIP | Canon R3 CCAPI URL | http://192.168.1.99:8080 |
| dataArduinoIP | Arduino Giga R1 WiFi URL | http://192.168.1.97 |
| dataLatitude | Shoot location latitude | -34.9285 |
| dataLongitude | Shoot location longitude | 138.6007 |
| dataUTCOffset | UTC offset in hours | 9.5 (ACST) / 10.5 (ACDT) |
| dataCurrentMode | Current shooting mode | m |
| dataCurrentAv | Current aperture | f1.8 |
| dataCurrentTv | Current shutter speed | 1/5000 |
| dataCurrentISO | Current ISO | 100 |
| dataLuminance | Last luminance reading | 0 |
| dataShotCount | Running shot counter | 0 |
| dataCommCameraCheck | Camera status message | -- |

## Shoot Sequence

| Phase | Shutter | ISO | Interval | Notes |
|-------|---------|-----|----------|-------|
| 1 — Daytime | 1/5000s | 100 | 2s | Cart moving |
| 2a — Sunset transition | 1/5000→20s | 100 | 2→22s | Shutter slows, interval tracks |
| 2b — ISO ramp | 20s | 100→1600 | 22s | Luminance-controlled |
| 3 — Full night | 20s | 1600 | 22s | Gimbal tracks Milky Way |
| 4a — ISO reverse | 20s | 1600→100 | 22s | Pre-sunrise |
| 4b — Shutter reverse | 20→1/5000s | 100 | 22→2s | |
| 5 — Daytime | 1/5000s | 100 | 2s | |

Interval rule: `interval = max(2.0, shutter_seconds + 2.0)`

## Camera Endpoints (CCAPI ver100)

```
GET/PUT  /ccapi/ver100/shooting/settings/shootingmode  — "m","av","tv","p","bulb"
GET/PUT  /ccapi/ver100/shooting/settings/av            — "f1.8","f2.0" etc
GET/PUT  /ccapi/ver100/shooting/settings/tv            — "1/5000","1/100","1","20" etc
GET/PUT  /ccapi/ver100/shooting/settings/iso           — "100","400","1600" etc
POST     /ccapi/ver100/shooting/control/shutterbutton  — {"af":false}
GET      /ccapi/ver110/devicestatus/currentdirectory   — current SD card folder
GET      {path}?type=jpeg&kind=number                  — page count
GET      {path}?type=jpeg&kind=list&page={n}           — file list
GET      {path}/{file}?kind=thumbnail                  — 160x120 JPEG
```

## Arduino (Cart) Endpoints

The cart exposes a large HTTP surface; the main groups (see the firmware repo
README for the full list):

```
Plan:    /plan/load /plan/start /plan/stop /plan/clear /plan/advance /plan/nudge
Gimbal:  /move /home /heartbeat /gimbal/carthead /gimbal/pano /gimbal/showastro
Track:   /settings/trackplan /settings/trackpath  (Excel-pushed cubics + intervals)
Camera:  /exposure/init /exposure/load /exposure/walk /shutter/start /shutter/stop
         /interval /luminance
Preview: /preview/goto /preview/step /preview/status   (cable-rig jog)
Status:  /exec/feed (Exec UI JSON) /status /cartlog /gimballog /btn<N>
```

## Python Setup

The renderers (plan view, cable strip) and luminance helper need:
```
pip install Pillow matplotlib openpyxl
```
Python files live in the workbook's `Python/` subdirectory (the VBA buttons
shell them from there and read back the PNG + sidecar files). Confirmed on the
operator machine with Python 3.14, openpyxl 3.1.5, matplotlib 3.10.9.

## Hardware

| Component | Details |
|-----------|---------|
| Controller | Arduino Giga R1 WiFi |
| Gimbal | DJI Ronin RS4 Pro |
| CAN transceiver | Adafruit CAN Pal 5708 (TJA1051T/3) |
| Cart | Axial SCX6 |
| Stepper controllers | Pololu Tic 36v4 × 2 (I2C addr 14, 15) |
| IMU | Adafruit BNO085 (I2C addr 0x4A, heading reference) |
| Camera | Canon EOS R3 |
| WiFi | Wavlink AX6000 mesh (van + field node) |

## Arduino Repository

Arduino sketches are in a separate repository:
[DJI-Ronin-RS4-Arduino](https://github.com/mwindley/DJI-Ronin-RS4-Arduino)

## VBA Module Import

To import modules into Excel:
1. Open Excel → Alt+F11 → VBA Editor
2. File → Import File → select each `.bas` file from the `Modules/` folder

To export (after editing in Excel):
1. In VBA Editor, right-click each module → Export File
2. Save to `Modules/` folder
3. Run `push_HyperLapse_Excel.bat`
