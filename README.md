# Reachly

Reachly is a native iOS accessibility app designed to help blind and visually impaired people find nearby objects, move a hand toward them, and understand what they are holding through clear spoken guidance.

This repository contains the iOS 17+ SwiftUI app, an accessible home experience, and a live rear-camera Explore screen backed by one ARKit session. Explore runs on-device Core ML object detection, displays selectable boxes and an accessible object list, and exposes a tracked target for future guidance. Hand tracking, depth estimation, reach guidance, and voice commands are not implemented yet.

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
│   ├── ObjectDetection/    Core ML model, Vision inference, tracking, selection, overlay and list
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

The camera layer owns one `ARSession` for preview, tracking, and frame delivery. Object detection subscribes to its `CameraFrameBroker` through `makeFrameStream()`. Each subscriber buffers only the newest frame. No extra capture session or external dependency is used.

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

## Object detection

Start the camera in Explore. Tap a box or a row in **Detected objects** to select a target; **Clear Target** removes the selection. Rows expose the class, confidence, and selected state to VoiceOver. The list scrolls at large Dynamic Type sizes. Target selection, loss, and reacquisition are announced without announcing every inference result.

The bundled **YOLOv3TinyFP16** is a real 17.7 MB Core ML detector from [Apple's model gallery](https://developer.apple.com/machine-learning/models/), trained on 80 COCO classes. It accepts 416×416 color images and includes non-maximum suppression and labels, allowing Vision to return `VNRecognizedObjectObservation` values. No runtime download, API key, or network access is required. See [model provenance and supported classes](Reachly/Features/ObjectDetection/Resources/MODEL.md) for the exact download, checksum, authors, and license notice.

- `VisionObjectDetector` serializes model loading and inference on its own actor. Vision rotates the rear sensor buffer with `.right` for Reachly's portrait-only UI, converts its pixel format, and resizes the whole upright image with `.scaleFill`. This avoids letterbox offsets, but can reduce accuracy through aspect-ratio distortion.
- `ObjectDetectionService` processes at most eight frames per second, one inference at a time. The broker retains only one pending frame. Frames older than 250 ms are skipped before inference; results older than 800 ms are discarded. The watchdog expires displayed boxes if the frame stream stalls. A generation token rejects results from an earlier camera run.
- `ObjectDetectionState` associates same-class observations one-to-one with intersection-over-union ≥ 0.3. Confidence must be ≥ 0.35; model NMS uses IoU 0.45. At most 20 objects are presented. IDs survive short missing detections for up to 800 ms. The list retains existing track order as confidence changes.
- A missing selected object becomes **lost** immediately on the next processed empty/unmatched result. Its current box becomes `nil`. Brief spatially overlapping reappearances can recover its ID; after expiry or a camera pause, a newly detected object requires explicit selection. The app never silently chooses a replacement target.
- Model loading or inference failures clear usable boxes and show an accessible error with **Retry Object Detection**. Camera pause, interruption, backgrounding, permission changes, and exit stop the consumer and invalidate pending results without changing the camera controller's lifecycle.

### Coordinates and future guidance

`DetectedObject.boundingBox` (also exposed as `region`) is normalized to the **entire upright portrait image**, with **bottom-left origin**, matching Vision. It is not normalized to the visible preview. `DetectionGeometry.viewRect` flips Y, applies centered aspect-fill scaling, and subtracts the cropped margins. The overlay is attached directly to the camera preview before its safe-area extension, so both share the same viewport. Visible boxes are clipped to that viewport.

`ObjectDetectionProviding.selectedTarget` exposes the tracked object, `.tracking`/`.lost`, `lastSeenTimestamp` (the originating `CameraFrame.timestamp`), upright image dimensions, and an optional `currentBoundingBox`. `sensorBoundingBox` converts a current box to normalized native landscape sensor/depth coordinates with top-left origin. Future depth work must use a timestamp-matched frame, validate freshness and depth, and ignore lost targets. Detection retains no depth buffers or AR frames. The boxes lag the live feed by inference latency; they are not motion-compensated.

### Limitations

Only the fixed 80 model classes are supported; this is not arbitrary object recognition, OCR, segmentation, or a hand detector. IDs are approximate spatial associations, not persistent physical identities. Two similar objects crossing, fast motion, prolonged occlusion, or camera movement can swap or lose IDs. Small, transparent, poorly lit, or partly hidden objects are difficult for this compact model. Confidence is a model score, not a calibrated probability of correctness. All full-image detections are listed, including objects in preview-cropped margins. Portrait rear-camera use is supported; adding landscape/front-camera support requires updating orientation and geometry together. Recognition and real-time speed still need physical-device validation. No reach/distance advice is emitted.

### Reference study

The requested `../probe-reference` was absent, so [Probe](https://github.com/amiezeng/Probe) was inspected from a temporary GitHub checkout at `4f393171b9b4a32592413fc6fc8df617606d4306`, with the owner's permission. Relevant files were `CameraController.swift`, `ObjectDetection.swift`, `Segmentation.swift`, `ModelStore.swift`, `CameraView.swift`, `BoundingBox.swift`, and the bundled model packages.

Probe's active segmentation path uses `yolo26n-seg`, 640-pixel input, `.right` orientation, `.scaleFit`, a 100 ms throttle and busy guard. It decodes raw tensors/masks and removes letterbox padding; its default filter permits bottles. Its separate EGOHOS object model targets hand/interaction categories and is disabled by default. Reachly's integration is original: it uses an independently downloaded bounding-box model, the existing frame broker, typed Vision results, explicit tracking/selection state, and aspect-fill-aware overlay geometry. No Probe source, weights, hand logic, or camera lifecycle was copied into Reachly.

## Validation

Regenerate after adding source/resources, then build without signing:

```sh
xcodegen generate
xcodebuild -project Reachly.xcodeproj -scheme Reachly -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/reachly-derived-data CODE_SIGNING_ALLOWED=NO clean build
```

Run focused tests on an available simulator (adjust the device name if needed):

```sh
xcodebuild -project Reachly.xcodeproj -scheme Reachly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/reachly-derived-data CODE_SIGNING_ALLOWED=NO test
```

Tests cover identity association, target selection/loss/recovery/expiry, stale results, invalid detections, portrait rotation, coordinate clipping, both aspect-fill crop directions, missing-model errors, cancellation during loading, model classes, and real Vision inference using a synthetic pixel buffer. Simulator tests do not validate AR capture or recognition of physical objects.

Validated November 14, 2026 with Xcode 26.2: clean unsigned iOS device build passed; all 14 tests passed on the iPhone 17 Pro simulator (iOS 26.2). The build emitted only the App Intents metadata notice because this app does not use App Intents. Physical-device checks below remain outstanding.

### Physical iPhone checklist (not yet performed)

1. Run on an ARKit-capable iPhone in portrait. Start Camera and grant permission. In good light, frame a **cup** and **bottle** separately, then together; also try a **chair**, **book**, **banana**, and **cell phone**. Confirm correct class labels and confidence percentages; record misses and false positives rather than expecting every frame to succeed.
2. Slowly move each object from the center toward all four preview edges, then vary distance. Confirm boxes follow the image without horizontal stretching, Y inversion, or safe-area offsets. Repeat on another iPhone screen aspect ratio and with larger text sizes.
3. Tap a cup's box and then select the bottle's list row. Confirm the selected outline/checkmark, target name, and changing box. With two bottles, move them separately and inspect ID stability; crossing them may lose identity.
4. Cover/remove the target. Confirm **Target lost** and no current box. Briefly reintroduce it at the same position to check recovery. Remove it for over one second, then reintroduce it: it must remain unselected until tapped. Point at a blank wall to check the empty state.
5. Enable VoiceOver. Navigate the detected-object rows, hear names/confidence, select and clear a target, and verify loss/recovery announcements. Test the largest Dynamic Type setting and scroll to every row and camera control.
6. Pause/resume, lock/unlock, background/foreground, interrupt the camera, and exit/re-enter Explore. Boxes must clear on pause and never reappear from a cancelled inference. Deny camera permission, enable it in Settings, and later revoke it; detection must follow the camera's availability without starting its own session.
7. Temporarily remove the model from target membership in a local debug build, regenerate/build, and confirm an accessible model error while the camera remains usable. Restore it before continuing. Retry must not crash or create another session.
8. Profile for at least two minutes with Instruments (Time Profiler/Allocations) on the intended demo phone. Check responsive controls, no main-thread inference, bounded memory, no accumulating frame queue, inference latency, heat and battery use. Hardware speed and thermal performance are not established by the simulator build.

