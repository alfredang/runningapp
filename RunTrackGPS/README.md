# RunTrack GPS

A simple, lightweight **native iOS running app** built with **Swift + SwiftUI** and an **MVVM**
architecture. It tracks outdoor runs by GPS, draws your route live on a map, supports preset and
custom distance goals, voice commands, voice feedback, and **background tracking**.

> **Mapping note:** This build uses **Apple MapKit** instead of the Google Maps SDK. MapKit is
> native, free, needs **no API key or billing**, and still provides route polylines, start/current
> markers, follow-mode, and zoom/pan — so the project compiles and runs on a real iPhone with **zero
> external setup**. See [Swapping in Google Maps](#optional-swapping-in-google-maps) if you need it.

---

## Features

- Preset goals: **5 / 10 / 20 / 40 km** + custom distance input
- Real-time GPS distance tracking with noise filtering
- Live MapKit route polyline, start + current markers, follow camera
- Elapsed timer with pause / resume / stop (wall-clock based — survives backgrounding)
- Current pace, average pace, remaining distance, progress bar
- **Voice commands**: "start run", "pause run", "resume run", "stop run"
- **Voice feedback**: start/pause/resume/stop, each completed km, 50%, 90%, goal reached (de-duplicated)
- **Background tracking**: GPS, timer, distance, and voice feedback all continue when the screen is locked
- Saved run history + recent-run summary on the home screen
- Native dark-mode support, large typography, large touch targets

---

## Requirements

- macOS with **Xcode 15+**
- An iPhone running **iOS 16+** (GPS and Speech need a **real device** — the Simulator can't
  produce real GPS movement or microphone input)
- [XcodeGen](https://github.com/yonyz/XcodeGen) to generate the Xcode project

---

## Setup & Run

```bash
# 1. Install XcodeGen (once)
brew install xcodegen

# 2. Generate the Xcode project from project.yml
cd RunTrackGPS
xcodegen generate

# 3. Open it
open RunTrackGPS.xcodeproj
```

Then in Xcode:

1. Select the **RunTrackGPS** target → **Signing & Capabilities** → choose your **Team**
   (a free Apple ID works for on-device testing). The bundle id `com.example.runtrackgps` can be
   changed to something unique if signing complains.
2. Plug in your iPhone, select it as the run destination, and press **⌘R**.
3. Grant the permission prompts when they appear:
   - **Location** → choose **Allow While Using**, then **Change to Always** (or accept the later
     "Always" prompt) for full background tracking.
   - **Microphone** + **Speech Recognition** → allow, to enable voice commands.

> The **Location (Always)**, **Background Modes → Location updates**, and **Background Modes → Audio**
> settings are already wired through `RunTrackGPS/Support/Info.plist`, so no manual capability setup
> is needed.

---

## Quick smoke test

1. **Home** → tap **5 KM** (or type a custom distance like `0.2` and tap **Set** for a fast test) →
   the goal updates → tap **Start Run**.
2. Start walking/running outdoors: the map draws your polyline and follows you; distance, time, and
   pace update live.
3. Say **"pause run"**, then **"resume run"**, then **"stop run"** — the state changes and each is
   confirmed by voice.
4. **Lock the phone** mid-run: distance keeps accumulating and kilometre announcements are still
   spoken (background Location + Audio modes).
5. Reach the goal (a `0.2 km` custom goal makes this quick) → you hear *"Your goal is reached"* and
   land on the **Completion** screen.
6. Tap **Save Run** → return via **Start New Run** → the run appears in the home **Recent Run** card.

---

## Architecture (MVVM)

```
RunTrackGPS/
├── App/RunTrackGPSApp.swift          @main, injects RunViewModel, configures audio session
├── Models/
│   ├── RunSession.swift              Codable run model + Coordinate wrapper
│   └── AppScreen.swift               home / running / completion
├── ViewModels/RunViewModel.swift     central coordinator (owns managers, state, actions)
├── Views/
│   ├── RootView.swift                screen router + alerts
│   ├── HomeView.swift                dashboard
│   ├── RunView.swift                 live map + metrics + controls
│   └── CompletionView.swift          summary + save / new run
├── Managers/
│   ├── LocationManager.swift         CoreLocation, GPS filtering, distance, background
│   ├── RunTimerManager.swift         wall-clock elapsed time
│   ├── VoiceCommandManager.swift     Speech framework recognition
│   └── SpeechFeedbackManager.swift   AVSpeechSynthesizer (de-duplicated)
├── Maps/RouteMapView.swift           MKMapView via UIViewRepresentable
├── Utilities/
│   ├── PaceCalculator.swift          pace math + formatting
│   └── RunStore.swift                UserDefaults persistence
└── Support/Info.plist                permissions + background modes
```

`RunViewModel` is the single source of truth. It owns the four managers, subscribes to the
`LocationManager`'s distance/route via Combine, recomputes paces, fires de-duplicated milestone
feedback, detects goal completion, and drives navigation between the three screens.

### GPS filtering (in `LocationManager`)
Each fix must pass: horizontal accuracy ≤ 20 m, age ≤ 5 s, implied speed ≤ 12 m/s (rejects
teleport-like jumps), and ≥ 2 m of movement (rejects jitter while standing). Distance is summed via
`currentLocation.distance(from: previousLocation)`.

### Timer
Elapsed time is derived from wall-clock `Date`s (accumulated segments + live segment), so a
suspended app or dropped timer ticks never lose time. The 1 Hz timer only refreshes the UI.

---

## Voice commands — background limitation

Voice **feedback** (spoken announcements) works in the background via the **Audio** background mode.
Voice **commands** rely on live microphone capture, which iOS suspends when the app is backgrounded —
so command recognition is a **foreground** feature and resumes automatically when the app returns to
the foreground. GPS, timer, distance, and spoken feedback all continue uninterrupted in the
background.

---

## Error handling

- **Location denied / restricted** → alert + Start disabled; home banner prompts to enable it.
- **Only "When in Use" granted** → banner explaining background tracking is limited.
- **Microphone / Speech denied** → the app stays fully usable; the voice indicator shows "Voice off".
- **Poor GPS accuracy** → a "Weak GPS" chip appears on the run screen; bad fixes are dropped.

---

## Optional: Swapping in Google Maps

If you specifically need Google Maps:

1. Add the `GoogleMaps` Swift Package (`https://github.com/googlemaps/ios-maps-sdk`) to the target
   in `project.yml` under `packages:` / `dependencies:`.
2. Obtain an API key from a **billing-enabled** Google Cloud project (Maps SDK for iOS) and store it
   outside source control (e.g. an `.xcconfig` that's gitignored).
3. Call `GMSServices.provideAPIKey("…")` at launch in `RunTrackGPSApp`.
4. Replace `Maps/RouteMapView.swift` with a `GMSMapView`-based `UIViewRepresentable`, mapping the
   same inputs (`route`, `currentLocation`, `followUser`) to a `GMSPolyline`, `GMSMarker`s, and
   `GMSCameraPosition`. The rest of the app is map-agnostic and needs no changes.
