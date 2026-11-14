# Iris UI and motion preview — Live reading

Editable design: https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg

Revision 11 removes the scan countdown, hold requirement and skip control.
Reading progresses on recognition events rather than elapsed time. In this
simulated preview, the external Text detected / Result ready controls represent
those events; the camera interface itself has no countdown or capture button.

Revision 10 adds a restrained, entry-only letter reveal inspired by the live
Render.com headline. A blue/soft-violet/ice highlight travels through the glyphs
as they rise and come into focus. It appears only on the Iris landing title,
“See beyond the surface”, and “How can Iris help you?”. Each settles to white;
no repeating text shimmer, and reduced motion shows the final text immediately.
The native Figma layers use editable TextStagger and masked gradient tracks;
the code preview uses staggered glyphs and text-clipped gradients.

Revision 09 updates the landing tagline to “See beyond the surface”.

Revision 08 shifts Locate to the left and Explore to the right, with opposite
2° resting tilts and independent, continuous horizontal/vertical floating loops.
Both cards retain their 305 × 177 size, typography, colors and contents.
Reduced motion keeps the diagonal arrangement and pauses the floating.

Revision 07 replaces rectangular camera targets with an image-aligned bottle
contour in Locate, Explore, confirmation, and follow-up states. The outline
tracks the cap, neck, shoulders, body and base; the scanning light is clipped
inside that silhouette. It uses a traced demo mask, not live segmentation.

Revision 06 enlarges each rounded character by roughly 20–26% over revision 05.
Two peek from behind, while two sit in front at different heights and angles.
The group fills more of the lower screen while preserving side margins and room
for the swipe control. Soft feathered silhouettes,
individual blinks and gentle bounces keep the original playful Iris style.

Local browser preview: http://127.0.0.1:4173/

The latest Figma code layer is [Iris · Live reading · v11](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=119-377&code-node-id=119-377).

Select the latest code layer in Figma and press Play to interact. The native
screens are editable. Local preview changes are uncommitted and must not be
pushed to Git without a new explicit user request.

The original study adapted selected UI artwork from an earlier reference study. No repository was cloned or forked.
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
- Four rounded characters: Skye with ears, Pip with glasses, Nova in a lab coat,
  and Echo with headphones; overlapping silhouettes, varied sizes and blink rhythms.
- Swipe-up/tap navigation, a sideways glass wipe, and a sprinkle pop.
- Locate springs from the left; Explore springs from the right, with different timing.
- Floating glass over the eyes, a sweeping rectangular lens, glints, and soft shadows.
- Locate pupils smoothly look up, left, down and right in a continuous loop.
- Three translucent camera-wave layers enter from the top and both sides, then
  sway gently in a dark-blue-to-ice gradient. Flow continues across camera states.
- Ambient blue sprinkles, quieter edge accents over camera views, and success confetti.
- Looking, spatial guidance, distance, object reached and ready-to-read states.
- Object-shaped boundaries and an interior scanning light; no rectangular target.
- Live scanning and reading, followed by speaking and listening states.
- Press feedback, back navigation and reduced-motion support.

The camera still is AI-generated demo imagery. Voice, object detection, AR,
distance readings and haptics are simulated; this is a design preview, not a
native iOS feature integration. Live object contours require a segmentation
mask from the camera pipeline, transformed with the same image crop.
`objectContour` in `assets.json` stores the demo path and its source dimensions.
Use the review controls outside the phone to
trigger the demonstrated voice and camera events.

Native Figma frames include linked navigation, directional entrances, editable
character components, gaze keyframes, glass waves, ambient particles, and success
confetti. Continuous blinks, gaze loops, and flowing waves are demonstrated in the
runnable code preview.
The shared Figma card components retain their IDs and instances.

Reduced motion disables continuous movement and hides confetti. The revised
welcome, Locate, success, Explore, and reduced-motion states were checked locally.
Revision 03 was checked for all four crew members, changing pupil positions,
top/left/right camera entrances, motion continuity between camera states, and
disabled movement in reduced motion. The browser reported no warnings or errors.
The Figma-hosted v3 preview also started successfully and was checked through
welcome, options, Locate, and bottle guidance.

Nunito and Nunito Sans replace Apple SF fonts with user approval because the
connected Figma renderer did not render SF text. Font files and their SIL Open
Font Licenses are included in `fonts/`.

## Reference files

- HomeScreen.swift, LoadingScreen.swift, HomeArt.swift
- MainScreen.swift, MainArt.swift, BubbleTitle.swift
- PageTransition.swift, Floating.swift, EyeMotion.swift, WaterVisualizer.swift
- ContentView.swift, AnalyzeView.swift, StatusBlob.swift, ListeningIndicator.swift

Video reference: https://www.youtube.com/watch?v=IKNUVaGHbME&t=109s
Material inspiration: https://www.harvey.ai/
Text-motion inspiration: https://render.com/
