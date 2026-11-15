# Iris UI and motion preview — Camera guidance

Editable design: https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg

## Run and reuse

This directory contains the complete browser UI package. From the repository
root, run:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory Design/Iris
```

Open <http://127.0.0.1:4173/>. There are no npm dependencies or build steps.
Keep this whole directory together: the preview loads its scripts, stylesheet,
fonts, and demo camera image using relative paths. It also works by opening
`index.html` directly; phone sensor access requires HTTPS in supporting browsers.
The Enable phone motion button requests sensor access only after a tap.

See [ASSETS.md](ASSETS.md) for the file map, current Figma links, and implementation
boundaries. [`figma-exports/`](figma-exports/manifest.json) contains direct SVG
exports of the current card artwork, diagonal discovery screen, and camera
overlays, with a source-node link for each export. The SVGs are static; use the
HTML/CSS/JS preview for animations and interactions.

## Design revisions

Revision 19 replaces the four camera light strips with two original glowing
blue guidance arrows, one on each side. They point forward or back and tilt
left or right, while their white, pale-blue, deep-blue and bright-blue light
changes with approach progress. A persistent HAND → OBJECT card stays in one
screen position while its inches and centimeter values update. The inches
are converted from the supplied demo meters using exactly 0.0254 meters per
inch. Hiding the hand keeps the card visible with an unavailable state instead
of a stale number. The demo slider and closer/away controls update the hand,
connector, arrows and card together; directional controls demonstrate steering.
Open `?screen=guidance` to start directly in this view. These controls simulate
sensor input; this browser preview does not measure real-world distance.

Revision 18 replaces the large camera waves with four narrow optical light
strips, two per side, with softly traveling highlights. The camera object mask
is translucent green and follows the bottle silhouette. A 21-landmark hand
overlay connects the index fingertip to the object with a distance label.
Move hand closer/back updates the pose, connector, and both distances together;
Hide hand removes the landmarks and suppresses the distance until tracking
returns. These are design simulations, not live segmentation, hand detection,
or calibrated physical distance. The camera image and mock inputs remain local.

Revision 17 gives both the map and magnifier a wider 6.2-second side-to-side
sway. The map travels from -12 to +10 px; the lens from +19 to -31 px.
A separate sensor layer adds up to 14 px of map movement and 22 px of lens
movement, proportional to horizontal phone acceleration, then eases to center.
The preview has Enable phone motion plus gentle/quick shake demonstrations.
Sensor access starts only after a tap, handles denial and missing sensors,
works over HTTPS in supporting browsers, and keeps all samples on the device.
Reduced motion disables both the idle animation and sensor response. Native
Figma demonstrates idle sway; actual phone sensors run in the browser preview.
Physical phone testing is still needed; the response model and desktop shake
previews were tested.

Revision 16 replaces the Locate eyes with an editable cartoon treasure map.
Warm textured parchment, blue islands and a compass fit the Iris palette. A
traveling light follows the winding trail to a coral-red X; the parchment sways,
the compass turns and the destination bounces on arrival. Reduced motion keeps
the completed illustration still. Native Figma animates the route opacity; the
browser preview also moves its dashes. All existing controls remain unchanged.

Revision 14 removes the discovery heading and expands Locate and Explore into
full-width, equal-area sections. Their shared diagonal runs from y=448 at the
left edge to y=352 at the right on the 360 × 800 screen. The back and Listening
controls stay overlaid; the content, glass lenses and wandering eyes keep their
original styling and motion. Both entire sections remain tappable.

Revision 12 reshapes Locate and Explore as opposing rounded parallelograms.
Smaller glass lenses and ambient panels share the slanted treatment, preserving
the blue palette, typography, card size, and continuous motion.

Revision 11 removes the scan countdown, hold requirement and skip control.
Reading progresses on recognition events rather than elapsed time. In this
simulated preview, the external Text detected / Result ready controls represent
those events; the camera interface itself has no countdown or capture button.

Revision 10 adds a restrained, entry-only letter reveal inspired by the live
Render.com headline. A blue/soft-violet/ice highlight travels through the glyphs
as they rise and come into focus. It appears only on the Iris landing title,
“See beyond the surface”, and “How can Iris assist you?”. Each settles to white;
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

[Live revision 19 guidance preview](https://app-vv74nvdykzsio2xxoy5pgrvgmdczd43ramggdbyipubmjv56i7pp.makeproxy-c.figma.site/?screen=guidance). Figma refreshed the runtime
address when the existing code layer was updated. The original preview URL
no longer resolves; the code layer below remains the stable entry point.

[Verified hosted preview screenshot](review/guidance-v19.jpg). Browser checks
covered two arrows/no old rails, fixed card bounds as distance changes,
25.6 in at 65 cm, 11.8 in at 30 cm, hand loss, zero-distance arrival, directional
changes, and reduced motion. No native app or simulator was run for this update.

The Figma source is [Iris · Camera guidance code layer](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=204-858&code-node-id=204-858).

Select the latest code layer in Figma and press Play to interact. The native
screens are editable. This UI package and the current SVG exports are included
on the `UI/UX` branch with the user's authorization.

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
- Four rounded characters: Skye with ears, Pip with glasses, Nova in a lab coat,
  and Echo with headphones; overlapping silhouettes, varied sizes and blink rhythms.
- Swipe-up/tap navigation, a sideways glass wipe, and a sprinkle pop.
- Locate springs from the left; Explore springs from the right, with different timing.
- A textured treasure map with a traveling route marker, turning compass and red X.
- Map and magnifier sway horizontally, with an optional phone-shake response.
- Two glowing blue arrows show direction and approach progress along the camera edges.
- A fixed distance card shows inches and centimeters and remains visible when tracking is lost.
- Green silhouette highlighting, hand landmarks, a fingertip connector, and simulated direction/distance controls.
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

Native Figma frames retain linked navigation, directional entrances, editable
character components, map and magnifier motion, camera edge lights, ambient
particles, and success confetti from the earlier revisions. Revision 19's arrows,
fixed distance card, continuous animations and simulated hand movement are
implemented in the runnable code preview.
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

Source: https://github.com/amiezeng/Probe/tree/riba/more-ui-stuff
Video reference: https://www.youtube.com/watch?v=IKNUVaGHbME&t=109s
Material inspiration: https://www.harvey.ai/
Text-motion inspiration: https://render.com/
