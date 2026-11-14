# Reachly

Reachly is a native iOS accessibility app designed to help blind and visually impaired people find nearby objects, move a hand toward them, and understand what they are holding through clear spoken guidance.

This repository contains the iOS 17+ SwiftUI foundation, Reachly visual identity, an accessible home experience, and a live rear-camera Explore screen backed by one ARKit session. Object detection, hand tracking, guidance logic, and voice processing are intentionally not implemented yet.

## Requirements

- macOS with Xcode installed
- XcodeGen
- iOS 17 or newer

Install XcodeGen with Homebrew if needed:

```sh
brew install xcodegen
```

## Generate and open the project

From the repository root:

```sh
xcodegen generate
open Reachly.xcodeproj
```

Select a physical iPhone and run the `Reachly` scheme. AR camera tracking is unavailable in the iOS Simulator, where Reachly displays its unavailable state instead.

## Project structure

```text
Reachly/
├── App/                    App entry point
├── Features/
│   ├── CameraAR/           AR session, preview, lifecycle, and frame streams
│   ├── ObjectDetection/    Object observation boundary
│   ├── HandTracking/       Hand observation boundary
│   ├── Guidance/           Spoken, visual, and haptic guidance boundary
│   └── Voice/              Speech input and output boundary
├── Models/                 Shared domain and readiness models
├── Resources/              Info.plist and asset catalogs
└── UI/
    ├── Components/         Reusable branded controls
    ├── Exploration/        Accessible live-camera experience
    ├── Home/               Accessible home screen
    └── Theme/              Color and layout tokens
```

The camera layer owns one `ARSession` for preview, tracking, and frame delivery. It publishes independent newest-frame streams so future object detection and hand tracking services can subscribe without starting competing camera sessions. The remaining feature folders expose protocol boundaries for their future implementations.

## Accessibility foundation

- High-contrast charcoal and aqua palette
- Dynamic Type throughout the interface
- Large, clearly labeled touch targets
- VoiceOver labels and hints on primary actions
- Concise copy designed to work when read aloud
- Portrait-first layout that scrolls at large accessibility text sizes

## Permissions

The generated `Info.plist` includes purpose strings for:

- Camera access
- Microphone access
- Speech recognition

Camera permission is requested only after the user enters Explore and chooses **Start Camera**. Microphone and speech-recognition permissions are not requested yet.

## Camera behavior

- **Start Camera** requests access and starts rear-camera AR tracking.
- **Pause Camera** stops new frame capture while keeping the Explore screen open.
- **Resume Camera** restarts the same session.
- **Exit** stops the session before returning home.
- Capture pauses while the app is in the background and resumes only if it was previously running.
- Permission denial, device restrictions, missing hardware, ARKit support, interruptions, and session failures each have a visible accessible state.

