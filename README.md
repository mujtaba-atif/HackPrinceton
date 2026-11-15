# Reachly

Reachly is a native iOS accessibility app designed to help blind and visually impaired people find nearby objects, move a hand toward them, and understand what they are holding through clear spoken guidance.

This repository currently contains the iOS 17+ product foundation: the SwiftUI app shell, Reachly visual identity, accessible home experience, feature boundaries, permission metadata, and XcodeGen configuration. Camera capture, object detection, hand tracking, guidance logic, and voice processing are intentionally not implemented yet.

## Iris UI package

The `UI/UX` branch includes the Iris design and runnable browser preview in
[`Design/Iris`](Design/Iris/README.md), with SVG artwork, fonts and licenses,
glass cards, characters, animations, phone-motion controls, and camera overlays.
The [asset guide](Design/Iris/ASSETS.md) maps these files to the UI.

Run the preview from the repository root:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory Design/Iris
```

Open <http://127.0.0.1:4173/>. No package installation or build step is needed.

- [Editable Figma design](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg)
- [Animated Figma preview, revision 18](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=204-858&code-node-id=204-858)
- [Figma SVG exports and source-node manifest](Design/Iris/figma-exports/manifest.json)

The browser preview demonstrates the Iris UI. The SwiftUI app below remains a
separate foundation; the Iris screens have not been integrated into it. Camera
recognition, hand tracking, physical distances, and voice responses in the
preview are simulated.

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

Select an iPhone simulator or device and run the `Reachly` scheme. The current foundation does not start a camera or microphone session.

## Project structure

```text
Reachly/
├── App/                    App entry point
├── Features/
│   ├── CameraAR/           Camera and AR session boundary
│   ├── ObjectDetection/    Object observation boundary
│   ├── HandTracking/       Hand observation boundary
│   ├── Guidance/           Spoken, visual, and haptic guidance boundary
│   └── Voice/              Speech input and output boundary
├── Models/                 Shared domain and readiness models
├── Resources/              Info.plist and asset catalogs
└── UI/
    ├── Components/         Reusable branded controls
    ├── Exploration/        Exploration destination shell
    ├── Home/               Accessible home screen
    └── Theme/              Color and layout tokens
```

The feature folders contain protocols only. Concrete system-framework and machine-learning implementations can be added behind those boundaries without coupling them to SwiftUI screens.

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

The app does not request these permissions in the foundation build. Each permission should be requested just in time when its corresponding feature is implemented.

