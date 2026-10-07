<div align="center">

# 🏃 RunTrack GPS

[![Platform](https://img.shields.io/badge/Platform-iOS%2016%2B-blue?logo=apple)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-MVVM-005FCC?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![MapKit](https://img.shields.io/badge/Maps-MapKit-34C759?logo=apple)](https://developer.apple.com/maps/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](#license)
[![App Store](https://img.shields.io/badge/Download_on_the-App_Store-0D96F6?logo=apple&logoColor=white)](https://apps.apple.com/us/app/runtrack-gps/id6779956150)

**A clean, lightweight native iOS running app — track your run by GPS, watch your route draw live, and reach your distance goal with voice feedback.**

📲 **Now live on the App Store — [Download RunTrack GPS](https://apps.apple.com/us/app/runtrack-gps/id6779956150)**

[![RunTrack GPS on the App Store](RunTrackGPS/screenshots/appstore-listing.png)](https://apps.apple.com/us/app/runtrack-gps/id6779956150)

</div>

## Screenshots

| Home | Live Run | Goal Reached | History |
|------|----------|--------------|---------|
| ![Home](RunTrackGPS/screenshots/appstore/home.png) | ![Run](RunTrackGPS/screenshots/appstore/running.png) | ![Completion](RunTrackGPS/screenshots/appstore/completion.png) | ![History](RunTrackGPS/screenshots/appstore/history.png) |

## About

RunTrack GPS is a focused outdoor running tracker built entirely with **Swift + SwiftUI** and an **MVVM** architecture. Choose a distance goal, start running, and the app tracks your distance, pace, time, and calories in real time while drawing your route on a live map — even with the screen locked.

### Key Features

- 🧭 **Bottom-tab navigation** — Run, History, Settings, Feedback, and About
- 🎯 **Distance goals** — pick from a dropdown (1 / 2 / 3 / 5 / 10 / 15 / 20 / 30 km, Half Marathon, Marathon)
- 🛰️ **Real-time GPS tracking** with noise filtering (rejects poor accuracy, jitter, and unrealistic jumps)
- 🗺️ **Live route map** (MapKit) with start/current markers — follows you, but pan and zoom freely; tap the location button to follow again
- ⏱️ **Distance, pace, time & calories** updating live, with big glanceable readouts
- 🔥 **Calorie tracking** — set your body weight; calories shown live, on the summary, and in history
- 🗣️ **Voice commands** — "start / pause / resume / stop" (Speech framework)
- 🔊 **Voice coaching** — each kilometre reports distance to go, calories burned, and average pace, plus 25 / 50 / 75 % checkpoints
- 🎧 **Speaks over other apps** — announcements briefly duck YouTube / Music and pause podcasts, then let them resume; plays alongside Google Maps navigation instead of being silenced by it
- 🎈 **Goal celebration** — a spoken congratulations and a balloon animation when you reach your goal; the run auto-saves at the goal and keeps tracking until you finish
- 📍 **Favourite destinations** — save places and get the shortest walking route drawn on the map (MapKit directions), with route distance, walking time and straight-line distance shown before you start
- ↩️ **Back to Start** — one tap during a run plans the shortest route back to where you began, with the distance still to go
- 🚩 **Distance from Start** — always visible on the run screen
- 🌙 **Background tracking** — GPS, timer, and spoken feedback keep running when the screen is locked
- 📊 **On-device history** — every run saved locally (distance, time, pace, calories, date), with lifetime totals, run details, and *Run It Again*
- 🏆 **Personal-record trophies** — the fastest-pace and longest-distance runs are marked with a trophy right in the history list
- 🎨 Warm light-grey theme, large typography, large touch targets

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5 |
| UI | SwiftUI (iOS 16+) |
| Architecture | MVVM (single coordinating view model) |
| Location | CoreLocation (background updates, GPS filtering) |
| Maps | MapKit (`MKMapView` via `UIViewRepresentable`) |
| Voice input | Speech framework (`SFSpeechRecognizer`) |
| Voice output | AVFoundation (`AVSpeechSynthesizer`) |
| Persistence | `UserDefaults` (local, on-device) |
| Project gen | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |

## Architecture

```
┌──────────────────────────── SwiftUI Views ────────────────────────────┐
│ MainTabView → Run (Home/Run/Completion) · History · Settings · Feedback · About │
└───────────────────────────────┬────────────────────────────────────────┘
                                 │ observes (@Published)
                       ┌─────────▼──────────┐
                       │    RunViewModel     │   ← MVVM coordinator
                       │  (state + actions)  │
                       └───┬───┬───┬───┬─────┘
        ┌─────────────┘  │    │    └─────────────┬───────────────┐
   ┌────▼───────────┐ ┌──▼────────┐ ┌────────────▼───┐ ┌─────────▼─────┐ ┌───────────────┐
   │ LocationManager│ │RunTimer   │ │VoiceCommand    │ │SpeechFeedback │ │ RoutePlanner  │
   │ CoreLocation   │ │Manager    │ │Manager (Speech)│ │ (AVSpeech)    │ │ MKDirections  │
   │ + GPS filtering│ │wall-clock │ │recognition     │ │ de-duplicated │ │ shortest route│
   └───────┬────────┘ └───────────┘ └────────────────┘ └───────────────┘ └───────────────┘
           │ route + distance
   ┌───────▼────────┐        ┌────────────────┐
   │  RouteMapView  │        │   RunStore      │
   │  (MapKit)      │        │ UserDefaults    │
   └────────────────┘        └────────────────┘
```

`RunViewModel` is the single source of truth: it owns the managers, subscribes to the
location stream via Combine, recomputes pace, fires de-duplicated milestone announcements,
detects goal completion, and drives navigation. Views are thin and observe only the view model.

## Project Structure

```
runningapp/
└── RunTrackGPS/
    ├── project.yml                 # XcodeGen project definition
    ├── RunTrackGPS/
    │   ├── App/                    # @main entry point
    │   ├── Models/                 # RunSession, AppScreen, Destination
    │   ├── ViewModels/             # RunViewModel (coordinator)
    │   ├── Views/                  # MainTabView, Home, Run, Completion, History, RunDetail,
    │   │                           #   Destinations, Settings, Feedback, About, Celebration, Root
    │   ├── Managers/               # Location, Timer, VoiceCommand, SpeechFeedback, RoutePlanner
    │   ├── Maps/                   # RouteMapView (MapKit)
    │   ├── Utilities/              # PaceCalculator, CalorieCalculator, RunStore, AppSettings, Theme
    │   ├── Resources/              # Assets (icon, accent color)
    │   └── Support/                # Info.plist, PrivacyInfo.xcprivacy
    └── scripts/                    # icon + screenshot generators
```

## Getting Started

### Prerequisites

- macOS with **Xcode 15+**
- An iPhone running **iOS 16+** (GPS & Speech need a real device, not the Simulator)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Build & Run

```bash
git clone https://github.com/alfredang/runningapp.git
cd runningapp/RunTrackGPS

# Generate the Xcode project from project.yml
xcodegen generate
open RunTrackGPS.xcodeproj
```

Then in Xcode:
1. Select the **RunTrackGPS** target → **Signing & Capabilities** → choose your **Team**.
2. Plug in your iPhone, select it as the destination, and press **⌘R**.
3. Grant **Location (Always)**, **Microphone**, and **Speech Recognition** when prompted.

> The `.xcodeproj` is generated by XcodeGen and is gitignored — edit `project.yml`, not the project.

## Permissions & Background

The app requests Location (Always, for background tracking), Microphone, and Speech Recognition.
The `location` and `audio` background modes keep GPS, the timer, and spoken coaching running while the
screen is locked — `audio` is required, or iOS silences announcements from a backgrounded app (voice
**commands** are foreground-only, since iOS suspends the microphone in the background).
All run data stays **on the device** — nothing is uploaded.

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes
4. Open a Pull Request

## License

Released under the MIT License.

## Developed By

**Tertiary Infotech Academy Pte. Ltd.**

## Acknowledgements

- Apple — SwiftUI, CoreLocation, MapKit, AVFoundation, Speech
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for reproducible project generation

---

<div align="center">

⭐ If you find this useful, give it a star!

</div>
