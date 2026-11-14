# Iris UI and motion preview

Editable design: https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg

Animated Figma code layer: https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=11-102&autoplay-code-preview=11-102

Imported and checked in Figma. Select the code layer and press Play to interact.
The Find, guidance, reading countdown, and follow-up flows were also checked in
the local browser with no console warnings or errors.

This standalone preview adapts the UI artwork and motion from an earlier reference study. No repository was cloned or forked.
Only the relevant UI files were inspected; Illustrator-derived paths were translated
from `HomeArt.swift` and `MainArt.swift` into the SVG assets here.

The shared blue palette is in `assets.json` and `assets.js`. The same palette,
artwork, screen proportions, and approved Nunito typography are used in Figma.
Open `index.html` directly, or serve this directory with a static HTTP server.
There is no package installation or build step.

## Preview coverage

- Loading ring, title rise, jelly lettering and breathing rhythm.
- Blue feathered one-eyed mascot, blinking and pointer-following gaze.
- Swipe-up/tap navigation and a rising water transition.
- Staggered headings, falling/floating Find and Analyze cards, 1.7× magnifier.
- Looking, spatial guidance, distance, object reached and ready-to-read states.
- Label scanning, a five-second hold, reset, speaking and listening states.
- Press feedback, back navigation and reduced-motion support.

The camera still is AI-generated demo imagery. Voice, object detection, AR,
distance readings and haptics are simulated; this is a design preview, not a
native iOS feature integration. Use the review controls outside the phone to
trigger the demonstrated voice and camera events.

Native Figma frames include linked navigation, 21 keyframe tracks and two
text-stagger animations. Continuous blinks, pointer gaze, water pour and lens
movement are demonstrated in the runnable code preview. Figma does not permit
writing keyframes to instance sublayers through the current MCP API.

Nunito and Nunito Sans replace Apple SF fonts with user approval because the
connected Figma renderer did not render SF text. Font files and their SIL Open
Font Licenses are included in `fonts/`.

## Reference files

- HomeScreen.swift, LoadingScreen.swift, HomeArt.swift
- MainScreen.swift, MainArt.swift, BubbleTitle.swift
- PageTransition.swift, Floating.swift, EyeMotion.swift, WaterVisualizer.swift
- ContentView.swift, AnalyzeView.swift, StatusBlob.swift, ListeningIndicator.swift

Video reference: https://www.youtube.com/watch?v=IKNUVaGHbME&t=109s
