<div align="center">

<img src="https://img.shields.io/badge/Platform-Android%208.0+-3DDC84?style=flat-square&logo=android&logoColor=white" />
<img src="https://img.shields.io/badge/Flutter-3.x-54C5F8?style=flat-square&logo=flutter&logoColor=white" />
<img src="https://img.shields.io/badge/ESP32-BLE-E7352C?style=flat-square&logo=espressif&logoColor=white" />
<img src="https://img.shields.io/badge/Guidelines-AHA%2FERC%202020-194E9D?style=flat-square" />
<img src="https://img.shields.io/github/v/release/roueva/CPR-Assist-Glove?style=flat-square&color=194E9D&label=Release" />

<br /><br />

# 🫀 CPR Assist

### Smart glove system for CPR training and emergency response

A wearable glove with real-time Bluetooth feedback guides rescuers through every compression while a mobile app maps nearby AEDs and tracks training progress.

<br />

[![Download APK](https://img.shields.io/badge/⬇%20Download%20APK-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/roueva/CPR-Assist-Glove/releases/latest/download/cpr_assist.apk)
&nbsp;&nbsp;
[![App Website](https://img.shields.io/badge/🌐%20Website-Visit-194E9D?style=for-the-badge)](https://roueva.github.io/CPR-Assist-Glove/)
&nbsp;&nbsp;
[![Latest Release](https://img.shields.io/badge/📦%20Release-v1.0.0-335484?style=for-the-badge)](https://github.com/roueva/CPR-Assist-Glove/releases/latest)

</div>

---

## Screenshots

| Live CPR | Session Results | AED Map | Achievements |
|:-:|:-:|:-:|:-:|
| ![](docs/screenshots/live_cpr.png) | ![](docs/screenshots/results.png) | ![](docs/screenshots/aed_map.png) | ![](docs/screenshots/achievements.png) |

---

## What it does

CPR Assist combines a sensor-equipped glove with a Flutter mobile app to provide real-time guidance during CPR, whether in a training session or a real emergency.

```
Smart Glove  ──── BLE ────►  Mobile App  ──── HTTPS ────►  Cloud Backend
ESP32 · IMU · PPG           Flutter · Android            Node.js · PostgreSQL
Measures compressions       Guides & grades              Stores sessions
```

### Two modes

| | 🚨 Emergency | 🎓 Training |
|---|---|---|
| Login required | No | Yes |
| Real-time feedback | ✅ | ✅ |
| AED map + 112 call | ✅ | ✅ |
| Session grading | — | ✅ |
| Progress tracking | — | ✅ |

---

## Features

**Live feedback**
- Compression depth bar with target zone (5–6 cm adult · 4–5 cm pediatric)
- Rate target 100–120 BPM
- Recoil, wrist alignment, and force monitoring
- Rescuer heart rate and SpO₂ at each pause
- Fatigue detection and swap guidance

**Training**
- Graded sessions across 3 scenarios: Adult, Pediatric, No-Feedback
- Post-session analysis with depth and rate graphs
- PDF and CSV export
- 12 achievements · 5 certificate milestones · CPR knowledge quiz
- Global leaderboard

**AED Map**
- 3,400+ AED locations across Greece (iSaveLives registry)
- Real-time availability and turn-by-turn navigation
- Compass-based direction when offline

**Other**
- NFC tag on glove with tap to open app instantly
- Emergency mode requires no account, no login

---

## Install

1. Download [`cpr_assist.apk`](https://github.com/roueva/CPR-Assist-Glove/releases/latest/download/cpr_assist.apk)
2. Enable **Install unknown apps** in Android settings
3. Open the file, tap Install, then Open
4. Allow Bluetooth and Location when prompted

**Requires:** Android 8.0+ · Bluetooth 4.0 BLE

---

## Build from source

```bash
git clone https://github.com/roueva/CPR-Assist-Glove.git
cd CPR-Assist-Glove/CPR-Assist-App/cpr_assist
flutter pub get
flutter run
```

Add a `.env` file with `GOOGLE_MAPS_API_KEY` and `API_BASE_URL`.

---

## Research

Developed as a Master's thesis in Biomedical Engineering at the **Aristotle University of Thessaloniki**.

Compression targets and grading are aligned with the **AHA/ERC 2020 Guidelines for CPR and Emergency Cardiovascular Care**.
---

<div align="center">
<sub>AUTH · Biomedical Engineering · 2024–2026</sub>
</div>
