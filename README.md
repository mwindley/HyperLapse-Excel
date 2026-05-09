# HyperLapse Excel Controller

Excel VBA workbook for controlling the HyperLapse Cart system — a fully automated timelapse rig combining a motorised cart, DJI Ronin RS4 Pro gimbal and Canon EOS R3 camera.

## System Overview

```
Excel Workbook (laptop in van)
  │
  ├── WiFi → Arduino Uno R4 (192.168.20.97)
  │           ├── CAN → DJI Ronin RS4 Pro gimbal
  │           ├── I2C → Tic 36v4 stepper controllers (cart motors)
  │           └── Servo → Cart steering
  │
  └── WiFi → Canon EOS R3 CCAPI (192.168.20.99:8080)
              └── Camera settings, shutter control, thumbnail retrieval
```

## Projects

| # | Project | Status |
|---|---------|--------|
| 1 | DJI Ronin RS4 Pro gimbal control via Arduino CAN | ✅ Done |
| 2 | Motorised SCX6 cart (Tic 36v4 steppers + servo) | ✅ Done |
| 3 | Gimbal pointing direction / sunset-to-Milky Way sequence | 🔧 In progress |
| 4 | Canon CCAPI camera control from Excel | 🔧 In progress |

## Repository Structure

```
HyperLapse-Excel/
  Modules/
    Camera.bas     Canon CCAPI — ISO, Tv, Av, shutter, luminance
    Gimbal.bas     Arduino gimbal control — GimbalPosition, Heartbeat
    Sequence.bas   Phase control loop — sunset timing, transitions
    Cart.bas       Cart log retrieval and replay plan generation
    Astro.bas      Sun position, Milky Way galactic centre angles
    Utils.bas      Shared helpers — CameraGet, logging, sunrise API
  Python/
    luminance.py          Thumbnail luminance calculator (called by VBA)
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
| dataCameraIP | Canon R3 CCAPI URL | http://192.168.20.99:8080 |
| dataArduinoIP | Arduino Uno R4 WiFi URL | http://192.168.20.97 |
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

## Arduino Endpoints

```
GET  /move?yaw=&roll=&pitch=&time=   Gimbal move
GET  /home                           Gimbal to 0,0,0
GET  /shutter                        CAN shutter trigger
GET  /status                         Live status CSV
GET  /heartbeat?msg=HH:MM:SS         Excel alive timestamp
GET  /cameramsg?msg=...              Camera settings for UI display
GET  /btn1 — /btn21                  Web UI button actions
GET  /cartlog                        Cart log CSV, clears buffer
GET  /gimballog                      Gimbal waypoint log CSV, clears buffer
GET  /interval?secs=N                Set backup shutter interval
```

## Python Setup

Install Pillow (once):
```
pip install Pillow
```

Place `luminance.py` in:
```
C:\Users\[username]\Documents\luminance.py
```

## Hardware

| Component | Details |
|-----------|---------|
| Controller | Arduino Uno R4 WiFi |
| Gimbal | DJI Ronin RS4 Pro |
| CAN transceiver | SN65HVD230 (3.3V) |
| Cart | Axial SCX6 |
| Stepper controllers | Pololu Tic 36v4 × 2 (I2C addr 14, 15) |
| Camera | Canon EOS R3 |
| WiFi | TP-Link AX6000 mesh (van + battery portable node) |

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
