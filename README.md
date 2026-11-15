# Iris

Iris is a native iOS accessibility app designed to help blind and visually impaired people find nearby objects, move a hand toward them, and understand what they are holding through clear spoken guidance.

Iris runs on its own camera, detection, hand-tracking, depth and label-reading features, and it is voice-first:

- **Home → Main.** Iris introduces itself and listens ("continue"), then asks whether to **Locate** something or **Explore** something you're holding. Every screen understands "go back".
- **Locate**. Say what you want to find. Iris outlines it with on-device segmentation (YOLO26n-seg), then guides your hand to it in three steps with a stereo tone, optical edge lights and short spoken cues, measuring fingertip to object with Vision hand pose and LiDAR depth. Once you're holding it, Iris reads the label and hands over to a conversational agent.
- **Explore**. Hold an item up while Iris reads the label live, then the ElevenLabs agent summarizes it and answers questions.
- **Design.** The look follows the Iris design in `Design/Iris`: its palette, Nunito type, characters, diagonal choices and camera edge lights, with the same motion curves and timings. Reduced Motion stops continuous movement and hides confetti.
- **Voice.** Every spoken line uses your ElevenLabs voice (the agent's voice), with the on-device voice as a fallback when there is no key or no network.

See [docs/IRIS.md](docs/IRIS.md) for the flows, the ElevenLabs setup and on-device testing. Developer screens — the original Explore screen (object list, depth readout, **Turn to Read** label sheet) and the hand-tracking debug screen — are available in Debug builds: long-press the home screen for 2 seconds.

## ElevenLabs keys

```sh
cp Iris/Secrets.swift.example Iris/Secrets.swift   # git-ignored
```

Fill in the API key (`sk_…`), the public agent ID and the agent's voice ID. A build creates the file from the template if it's missing, so the app always builds; without a key it speaks with the on-device voice.

## Iris UI package

The `main` branch includes the Iris design and runnable browser preview in
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

The browser preview and native app share revision 18 artwork, diagonal
Locate/Explore panels, map/lens motion, optical camera rails, and green object
highlights. `scripts/sync_iris_artwork.py` generates the native vector bundle
from `Design/Iris/assets.json`; use `--check` to detect drift.

The browser's camera, recognition, hand tracking, distances, and voice are
simulated. The native app uses its existing live camera, Vision/LiDAR, OCR,
and voice pipelines. Native reading advances on recognition evidence without
a visible countdown. See [UI parity notes](docs/UI-PARITY.md) for reviewed flows
and the remaining on-phone verification.

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
open Iris.xcodeproj
```

Select a physical iPhone and run the `Iris` scheme. AR camera tracking is unavailable in the iOS Simulator, where Iris displays its unavailable state instead.

## Project structure

```text
Iris/
├── App/                    App entry point (loading → home → main sequence)
├── Features/
│   ├── Assistant/          ElevenLabs agent session, Locate's label hand-off, object-name matching
│   ├── CameraAR/           AR session, preview, lifecycle, and frame streams
│   ├── DepthEstimation/    Depth sampling, calibration, smoothing, spatial estimates and distance UI
│   ├── HandTracking/       Vision hand pose, smoothing, overlay
│   ├── Explore/            Label text reader and multi-scan consolidation
│   ├── LabelReading/       "Turn to Read" (developer screen): orientation guidance, text merging, interpretation
│   ├── Locate/             Segmentation model, hand pose and fingertip-to-object measurement, tone guidance, overlays
│   ├── ObjectDetection/    Core ML model, Vision inference, tracking, selection, overlay and list
│   ├── OCR/                Reusable Vision text recognition
│   ├── Guidance/           Guidance boundary
│   └── Voice/              Speaker (ElevenLabs voice + on-device fallback), keyword listener, target parsing
├── Models/                 Shared domain and readiness models
├── Resources/              Info.plist, asset catalogs and the Nunito fonts (OFL)
├── Secrets.swift.example   Template for the git-ignored ElevenLabs keys
└── UI/
    ├── Glass/              Iris design: palette, fonts, SVG artwork, keyframe motion, crew, cards, camera waves, outline
    ├── Status/             Glass status panel and listening pill
    ├── Screens/            Loading, Home, Main, Locate, Explore
    ├── Exploration/        Original Explore screen (developer)
    ├── Home/               Original home screen (developer)
    ├── LabelReading/       Read Label sheet (developer Explore screen)
    ├── Components/         Reusable branded controls
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

Microphone and speech-recognition permission are requested when the home screen first listens. Camera permission is requested when Locate or Explore opens.

## Camera behavior

- **Start Camera** requests access and starts rear-camera AR tracking.
- **Pause Camera** stops new frame capture while keeping the Explore screen open.
- **Resume Camera** restarts the same session.
- **Exit** stops the session before returning home.
- Capture pauses while the app is in the background and resumes only if it was previously running.
- Permission denial, device restrictions, missing hardware, ARKit support, interruptions, and session failures each have a visible accessible state.

## Object detection

Start the camera in Explore. Tap a box or a row in **Detected objects** to select a target; **Clear Target** removes the selection. Rows expose the class, confidence, and selected state to VoiceOver. The list scrolls at large Dynamic Type sizes. Target selection, loss, and reacquisition are announced without announcing every inference result.

The bundled **YOLOv3TinyFP16** is a real 17.7 MB Core ML detector from [Apple's model gallery](https://developer.apple.com/machine-learning/models/), trained on 80 COCO classes. It accepts 416×416 color images and includes non-maximum suppression and labels, allowing Vision to return `VNRecognizedObjectObservation` values. No runtime download, API key, or network access is required. See [model provenance and supported classes](Iris/Features/ObjectDetection/Resources/MODEL.md) for the exact download, checksum, authors, and license notice.

- `VisionObjectDetector` serializes model loading and inference on its own actor. Vision rotates the rear sensor buffer with `.right` for Iris's portrait-only UI, converts its pixel format, and resizes the whole upright image with `.scaleFill`. This avoids letterbox offsets, but can reduce accuracy through aspect-ratio distortion.
- `ObjectDetectionService` processes at most eight frames per second, one inference at a time. The broker retains only one pending frame. Frames older than 250 ms are skipped before inference; results older than 800 ms are discarded. The watchdog expires displayed boxes if the frame stream stalls. A generation token rejects results from an earlier camera run.
- `ObjectDetectionState` associates same-class observations one-to-one with intersection-over-union ≥ 0.3. Confidence must be ≥ 0.35; model NMS uses IoU 0.45. At most 20 objects are presented. IDs survive short missing detections for up to 800 ms. The list retains existing track order as confidence changes.
- A missing selected object becomes **lost** immediately on the next processed empty/unmatched result. Its current box becomes `nil`. Brief spatially overlapping reappearances can recover its ID; after expiry or a camera pause, a newly detected object requires explicit selection. The app never silently chooses a replacement target.
- Model loading or inference failures clear usable boxes and show an accessible error with **Retry Object Detection**. Camera pause, interruption, backgrounding, permission changes, and exit stop the consumer and invalidate pending results without changing the camera controller's lifecycle.

### Coordinates and future guidance

`DetectedObject.boundingBox` (also exposed as `region`) is normalized to the **entire upright portrait image**, with **bottom-left origin**, matching Vision. It is not normalized to the visible preview. `DetectionGeometry.viewRect` flips Y, applies centered aspect-fill scaling, and subtracts the cropped margins. The overlay is attached directly to the camera preview before its safe-area extension, so both share the same viewport. Visible boxes are clipped to that viewport.

`ObjectDetectionProviding.selectedTarget` exposes the tracked object, `.tracking`/`.lost`, `lastSeenTimestamp` (the originating `CameraFrame.timestamp`), upright image dimensions, and an optional `currentBoundingBox`. `sensorBoundingBox` converts a current box to normalized native landscape sensor/depth coordinates with top-left origin. Depth estimation uses that coordinate contract and a timestamp-matched frame. Detection itself retains no depth buffers or AR frames. The boxes lag the live feed by inference latency; they are not motion-compensated.

### Limitations

Only the fixed 80 model classes are supported; this is not arbitrary object recognition, OCR, segmentation, or a hand detector. IDs are approximate spatial associations, not persistent physical identities. Two similar objects crossing, fast motion, prolonged occlusion, or camera movement can swap or lose IDs. Small, transparent, poorly lit, or partly hidden objects are difficult for this compact model. Confidence is a model score, not a calibrated probability of correctness. All full-image detections are listed, including objects in preview-cropped margins. Portrait rear-camera use is supported; adding landscape/front-camera support requires updating orientation and geometry together. Recognition and real-time speed still need physical-device validation. No reaching instructions are emitted.

## Depth and spatial positioning

Select an object to see **“Bottle — approximately 0.7 meters away”**, with its horizontal/vertical direction relative to the portrait camera. The exact class name comes from detection. Unsupported devices, unreliable readings, missing frames, lost targets, and limited tracking show **“Distance unavailable”**. No metric distance is inferred from the RGB image. The readout is inside the existing scrollable object list, supports Dynamic Type and VoiceOver, and does not interrupt speech on every update.

### Data flow and shared camera changes

`DepthEstimationService` subscribes independently to the existing `CameraFrameBroker` and receives selected-target updates through `DepthEstimationProviding.setTarget`. A serial worker actor handles depth history, pixel-buffer reads, robust statistics, calibration and smoothing. The newest-frame stream and sequential consumption avoid a work queue. Sampling runs once per new detection, normally up to eight times per second; incoming frames only update the bounded history between detections.

The existing ARKit configuration already gated `.sceneDepth` behind `supportsFrameSemantics`. That behavior is preserved; the controller now exposes `supportsSceneDepth` for the service/UI. `CameraFrame` adds only `sceneDepthConfidenceMap` and `isCameraTrackingNormal`. No new sessions, capture configuration modes, or broker changes were introduced. Raw `sceneDepth` keeps the depth paired with the RGB frame; Iris smooths the resulting measurement itself rather than combining temporal depth smoothing with moving boxes. [Apple's ARDepthData documentation](https://developer.apple.com/documentation/arkit/ardepthdata) describes the depth/confidence maps and their relationship to the camera image.

Vision inference finishes after its frame was captured. The depth worker keeps at most 60 depth-only snapshots, expiring after 800 ms, and requires the detection timestamp to match a cached frame within 1 ms. It never uses an unrelated newer map. If a subscriber drops the matching frame, or an observation is older than 500 ms, distance is unavailable. No RGB images or whole ARFrames are retained in this history. A watchdog expires measurements if frames stop arriving. Target loss, selection changes, limited tracking and camera stop/restart invalidate results; each camera run gets a fresh processor/history.

### Coordinates and measurement

The portrait Vision box is mapped to native landscape sensor space by `(x, y, width, height) = (1 − box.maxY, 1 − box.maxX, box.height, box.width)`. Native depth and RGB images cover the same field of view at different resolutions. Normalized sensor coordinates therefore select depth pixels directly, while the RGB resolution and camera intrinsics unproject the box center. Preview aspect-fill cropping is only a display transform and must not be applied to depth sampling. `DepthGeometry` reuses the existing `DetectionGeometry` contract; rotated image dimensions are checked before sampling.

The sampler uses the central 60% of each box dimension and reads at most 400 pixel centers, respecting each buffer's row stride. It accepts finite depth from 0.15–5 meters with ARKit medium/high confidence. It requires at least nine valid samples and 50% validity among sampled pixels. The median is rejected if median absolute deviation exceeds `max(0.04 m, 8%)` or fewer than 70% of valid samples agree within `max(0.08 m, 15%)`. Missing confidence maps are unavailable. These are conservative application thresholds, not claims of sensor accuracy.

Depth values are axial distance from the camera plane, so the service unprojects them using camera intrinsics and reports the **Euclidean camera-to-surface distance**, rather than calling the raw axial value the distance. Horizontal/vertical bearing comes from that ray; ±7 degrees counts as centered. This follows Apple's [scene-depth unprojection approach](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth).

Valid axial measurements use a time-based exponential smoother with a 250 ms time constant. It resets on invalid data, target changes, gaps over 500 ms, time reversal, or jumps exceeding `max(0.2 m, 25%)`, so it does not blend unrelated surfaces. It adds some lag, and a large valid change is shown immediately rather than averaged with the previous surface.

### Interface for future hand tracking / guidance

`DepthEstimationProviding.estimate` is an optional `SpatialTargetEstimate`, containing:

- `objectID`: the selected detector track identifier.
- `distanceMeters`: optional radial distance to the box's approximate central surface.
- Horizontal/vertical position and optional bearing angles in radians (right/up positive).
- `positionInPortraitCameraMeters`: optional `(right, up, forward)` coordinates. **These are not ARKit world axes or an anchor.**
- `validity`: `.measured` or `.unavailable(reason)`, with explicit failure causes.
- `timestamp`: the original AR frame time for a measurement; invalid results carry the associated observation time.

Future guidance must check identity, `.measured`, freshness and coordinate conventions, and align its hand measurement to the same time. A 2D bearing can remain available without depth; it never implies a 3D point. `DepthEstimationService` does not consume hand observations, issue reach instructions, or modify hand-tracking protocols. A later branch can consume this interface without replacing the camera or detector.

This estimates a visible surface within a detection box, **not the object's center of mass, nearest edge, grasp point, or a persistent world pose**. Backgrounds and occluding objects can still dominate a box even when sample statistics pass. Transparent/reflective objects, thin objects and motion are difficult. `.measured` means the configured checks passed, not that the reading is ground truth. Physical-device accuracy, latency and sustained performance remain to be measured.

## Label reading (Turn to Read)

With the camera running, **Read Label** opens a half-height sheet (the camera stays visible above it). Iris reads the selected object's box, or the center 60% of the view when nothing is selected, so cans and boxes outside the detector's classes still work.

### How it decides the label isn't facing the camera

About five times per second, `LabelFrameProcessor` crops the frame (rotating the landscape sensor buffer with `.right`, like every other Vision consumer) and runs `VNRecognizeTextRequest` (`.fast`). `LabelOrientationAnalyzer` then measures, relative to the **object's** bounds rather than the padded crop:

| Signal | Meaning | Decision |
|---|---|---|
| No usable text | Label is on the back | `searching`: "Turn it slowly to the left…"; `needsLight` if the crop is dark |
| Text touching the object's right edge and leaning right | Label wraps around the right side | `turnLeft` |
| Text touching the left edge and leaning left | Label wraps around the left side | `turnRight` |
| Confidence-weighted text center beyond ±0.25 | Label is off to one side | Turn toward it |
| Centered, ≥ 12 characters, mean confidence ≥ 0.5 | Label faces the camera | `ready`: "Stop. Hold still while I read." |
| Centered but tiny text (or LiDAR distance > 0.7 m) | Too far | `moveCloser` |
| Centered but weak recognition | Blur or glare | `holdSteady` |

Convention: **"turn left" means the front of the item moves toward the user's left.** The first turn instruction in a session says so out loud.

`LabelGuidanceStabilizer` keeps speech calm. A decision must hold for 3 consecutive frames before it's spoken, the same phrase is never repeated within 2.5 seconds, and standing instructions are re-prompted every 5 seconds. While a turn is requested, it tracks the text's movement: net movement toward center gives "Good, keep going", and sustained movement the other way for more than 1 second gives "Other way". With no text for 8 seconds it suggests turning the other way. After two sweeps, or 25 seconds overall, it stops with a clear message. Between phrases, a haptic tick (`LabelGuidanceCueing`, a placeholder for the team's sound effects) speeds up as more of the label becomes visible.

### Reading

Text is merged across frames as the item turns (`LabelTextAccumulator`: near-duplicate and fragment merging). On `ready` (or **Read Now**), four `.accurate` passes are added. `OfflineLabelInterpreter` extracts fields with rules only: no network and no API key.

- Prescription detection (an `Rx` marker or at least two keywords such as refill/qty/tablet/pharmacy).
- Drug name: the line carrying a strength (e.g. `METFORMIN HCL 500 MG`). It never picks the largest text on a prescription, because that is often the patient's name. Non-prescription items use the largest line.
- Strength, directions (joined across two lines), Rx number (must contain a digit), quantity, refills, prescriber, pharmacy, filled and discard/expiration dates (`NSDataDetector`), and warnings.

Speech order: name and strength → directions → discard/expiration date → first warning. Then "Tap More Details for the rest" and, for prescriptions, "If anything sounds wrong, confirm with your pharmacist." Unreadable important fields are named ("I couldn't read the directions…"). A low-confidence name is spoken as "I think this says …, but I'm not sure." Abbreviations are expanded for speech (`MG` → milligrams). Iris never states that anything is safe, never gives dosing advice beyond the printed directions, never identifies loose pills, and doesn't read the patient's name in the summary. Frames, crops and label text are never stored or logged.

The result card offers **Read Aloud, More Details, Read Everything, Repeat, Stop Speaking, Read Again**. VoiceOver Magic Tap (two-finger double-tap) stops speech, or reads now / replays / retries depending on state.

### Speech and audio

`SpeechOutputService` wraps `AVSpeechSynthesizer` with interrupt/enqueue/skip-if-busy priorities and duplicate suppression, and uses the person's VoiceOver voice and rate (`prefersAssistiveTechnologySettings`). `AudioSessionCoordinator` is the single owner of `AVAudioSession` (`.playback`, `.spokenAudio`, ducking others). Sound effects and future voice commands should configure audio through it. Voice commands will need `.playAndRecord` there.

### Integration and shared code

`LabelGuidanceService` subscribes to `camera.makeFrameStream()` only while guiding and releases the stream when it finishes, fails or stops. It reads the detector's selected target and the depth estimate through read-only closures. A selected target lost for under 3 seconds (often hidden by the turning hand) keeps its last box. `ExploreView` changes are limited to the Read Label button, the sheet, and stopping the service when the camera stops or Explore exits. No camera, detection, depth or hand-tracking code was modified. Hand-occlusion hints ("your fingers may be covering the label") are not implemented because hand tracking isn't wired into Explore yet.

### Physical iPhone checklist (not yet performed)

1. Print a mock prescription label (fictional patient and drug) and tape it on an empty pill bottle. Start Camera, select the bottle, tap **Read Label**, with the label facing away.
2. Turn slowly in the instructed direction. Expect "Turn it left. That means the front…", "Good, keep going", then "Stop. Hold still while I read." Turn the wrong way on purpose and expect "Other way."
3. Confirm drug name and strength are read first, then directions and discard date. **More Details** reads Rx number, quantity, refills, prescriber and pharmacy.
4. Repeat with a soup can (no selection, center of view), a cleaning product, and in Airplane Mode (everything works offline).
5. Dim the lights (too dark), hold the item far away (move closer), and cover the label. Each gives its own instruction or a clear failure within 25 seconds.
6. Enable VoiceOver. Speech uses the VoiceOver voice; Magic Tap stops and replays; every result button is reachable. Pause the camera or exit Explore mid-guidance: speech stops and no guidance continues.
7. Profile while guiding: OCR stays off the main thread, and detection/depth remain responsive.

## Validation

Regenerate after adding source/resources, then build without signing:

```sh
xcodegen generate
xcodebuild -project Iris.xcodeproj -scheme Iris -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/iris-derived-data CODE_SIGNING_ALLOWED=NO clean build
```

Run focused tests on an available simulator (adjust the device name if needed):

```sh
xcodebuild -project Iris.xcodeproj -scheme Iris \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/iris-derived-data CODE_SIGNING_ALLOWED=NO test
```

Tests cover identity association, target selection/loss/recovery/expiry, stale results, invalid detections, portrait rotation, coordinate clipping, both aspect-fill crop directions, missing-model errors, cancellation during loading, model classes, and real Vision inference using a synthetic pixel buffer. Simulator tests do not validate AR capture or recognition of physical objects.

Depth tests use synthetic float-depth and byte-confidence buffers with padded rows. They cover orientation/region mapping, calibrated bearings and radial distance, invalid intrinsics, outliers, mixed surfaces, sparse/invalid samples, exact timestamp pairing, bounded history, lost/expired targets, tracking interruptions, missing depth, unsupported devices, smoothing resets and service lifecycle fallbacks. LiDAR hardware is not simulated.

Label-reading tests cover orientation decisions (edge cutoff, centering, padding vs. object edges, darkness, distance), crop planning, speech stabilization (3-frame stability, repeats, encouragement vs. jitter, wrong-way detection, sweeps), phrase building, cross-frame text merging, prescription/grocery interpretation and summaries, crop orientation against `DetectionGeometry.sensorRect` with a synthetic sensor buffer, real Vision OCR on rendered text, and service lifecycle (camera stream ended, timeout, stop, frame-stream release).

Validated November 14, 2026 with Xcode 27.2 (label reading): clean unsigned iOS device build passed; all 91 tests passed on the iPhone 18 Pro simulator.

Earlier: validated November 14, 2026 with Xcode 26.2: clean unsigned iOS device build passed; all 32 tests (18 depth and 14 detection tests) passed on the iPhone 17 Pro simulator (iOS 26.2). The build emitted only the App Intents metadata notice because this app does not use App Intents. Physical-device checks below remain outstanding.

### Physical iPhone checklist (not yet performed)

1. Run on an ARKit-capable iPhone in portrait. Start Camera and grant permission. In good light, frame a **cup** and **bottle** separately, then together; also try a **chair**, **book**, **banana**, and **cell phone**. Confirm correct class labels and confidence percentages; record misses and false positives rather than expecting every frame to succeed.
2. Slowly move each object from the center toward all four preview edges, then vary distance. Confirm boxes follow the image without horizontal stretching, Y inversion, or safe-area offsets. Repeat on another iPhone screen aspect ratio and with larger text sizes.
3. Tap a cup's box and then select the bottle's list row. Confirm the selected outline/checkmark, target name, and changing box. With two bottles, move them separately and inspect ID stability; crossing them may lose identity.
4. Cover/remove the target. Confirm **Target lost** and no current box. Briefly reintroduce it at the same position to check recovery. Remove it for over one second, then reintroduce it: it must remain unselected until tapped. Point at a blank wall to check the empty state.
5. Enable VoiceOver. Navigate the detected-object rows, hear names/confidence, select and clear a target, and verify loss/recovery announcements. Test the largest Dynamic Type setting and scroll to every row and camera control.
6. Pause/resume, lock/unlock, background/foreground, interrupt the camera, and exit/re-enter Explore. Boxes must clear on pause and never reappear from a cancelled inference. Deny camera permission, enable it in Settings, and later revoke it; detection must follow the camera's availability without starting its own session.
7. Temporarily remove the model from target membership in a local debug build, regenerate/build, and confirm an accessible model error while the camera remains usable. Restore it before continuing. Retry must not crash or create another session.
8. Profile for at least two minutes with Instruments (Time Profiler/Allocations) on the intended demo phone. Check responsive controls, no main-thread inference, bounded memory, no accumulating frame queue, inference latency, heat and battery use. Hardware speed and thermal performance are not established by the simulator build.

### Additional depth checks on physical iPhones (not yet performed)

1. On a LiDAR-equipped iPhone, select a large opaque bottle or book against a distant background. Compare readings at approximately 0.4, 0.7, 1.0 and 2.0 meters using a tape measure from the rear camera to the visible surface. Record error and variability; no measured accuracy claim is made yet.
2. Move it to each side and above/below camera center. Check direction signs and edge alignment. At the same forward depth, an off-axis object's radial distance should increase. Repeat with another screen aspect ratio; display cropping must not change the sampled region.
3. Hold still and watch jitter, then move toward/away from the object. Verify smoothing settles promptly. Switch between a near cup and far bottle: no distance should carry across target IDs. Occlude or lose the target and confirm the number disappears.
4. Try a transparent glass, reflective bottle, tiny/distant object, and a box spanning foreground/background. Confirm unreliable cases can show **Distance unavailable** and note false stable readings (box statistics cannot guarantee object membership).
5. Pause/resume, background/foreground, interrupt tracking, and exit/re-enter Explore. No previous distance may reappear from an earlier session. Shake/cover the camera enough to limit AR tracking and verify invalidation and recovery.
6. On a non-LiDAR iPhone, verify object detection still works and the selected target shows **Distance unavailable**, with no meters fabricated. On both devices, test the readout with VoiceOver and the largest Dynamic Type setting; every row/control should remain reachable by scrolling.

