# Iris UI and motion preview — Playful optics

Editable design: https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg

The current animated code layer is named **Iris · Playful optics · v2** in the
same Figma file. The earlier preview remains available as revision 01.

Preview v2: https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=23-203&code-node-id=23-203

Imported and checked in Figma. Select the code layer and press Play to interact.
The Find, guidance, reading countdown, and follow-up flows were also checked in
the local browser with no console warnings or errors.

The original study adapted selected UI artwork from the user-selected
`amiezeng/Probe` branch `riba/more-ui-stuff`. No repository was cloned or forked.
Revision 02 keeps the mascot and eye-card motif, while introducing original card
layouts, Locate / Explore labels, glass materials, and different choreography.
Harvey's current website informed the layered panels, fine borders, and soft
surface treatment; no Harvey code or assets were copied.

The shared blue palette is in `assets.json` and `assets.js`. The same palette,
artwork, screen proportions, and approved Nunito typography are used in Figma.
Open `index.html` directly, or serve this directory with a static HTTP server.
There is no package installation or build step.

## Preview coverage

- Loading ring, side-swept title, jelly lettering and breathing rhythm.
- Blue feathered one-eyed mascot entering diagonally, blinking and following the pointer.
- Swipe-up/tap navigation, a sideways glass wipe, and a sprinkle pop.
- Locate springs from the left; Explore springs from the right, with different timing.
- Floating glass over the eyes, a sweeping rectangular lens, glints, and soft shadows.
- Ambient blue sprinkles, quieter edge accents over camera views, and success confetti.
- Looking, spatial guidance, distance, object reached and ready-to-read states.
- Label scanning, a five-second hold, reset, speaking and listening states.
- Press feedback, back navigation and reduced-motion support.

The camera still is AI-generated demo imagery. Voice, object detection, AR,
distance readings and haptics are simulated; this is a design preview, not a
native iOS feature integration. Use the review controls outside the phone to
trigger the demonstrated voice and camera events.

Native Figma frames include linked navigation, revised directional entrances,
ambient particle keyframes, and success confetti. Continuous blinks, pointer gaze,
glass reflections and lens movement are demonstrated in the runnable code preview.
The shared Figma card components retain their IDs and instances.

Reduced motion disables continuous movement and hides confetti. The revised
welcome, Locate, success, Explore, and reduced-motion states were checked locally.

Nunito and Nunito Sans replace Apple SF fonts with user approval because the
connected Figma renderer did not render SF text. Font files and their SIL Open
Font Licenses are included in `fonts/`.

## Reference files

- HomeScreen.swift, LoadingScreen.swift, HomeArt.swift
- MainScreen.swift, MainArt.swift, BubbleTitle.swift
- PageTransition.swift, Floating.swift, EyeMotion.swift, WaterVisualizer.swift
- ContentView.swift, AnalyzeView.swift, StatusBlob.swift, ListeningIndicator.swift

Source: https://github.com/amiezeng/Probe/tree/riba/more-ui-stuff
Video reference: https://www.youtube.com/watch?v=IKNUVaGHbME&t=109s
Material inspiration: https://www.harvey.ai/
