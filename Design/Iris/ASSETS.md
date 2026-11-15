# Iris UI asset guide

This package reproduces the revision 18 browser design, including the four
characters, diagonal Locate/Explore choices, moving treasure map and magnifier,
glass lights, green target highlight, and simulated hand-distance graphics.

## Source and preview

- [Editable Figma file](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg)
- [Discovery screen](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=4-275)
- [Camera guidance](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=4-279)
- [Closer-hand state](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=201-1050)
- [Animated code preview](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=204-858&code-node-id=204-858)

The editable components and native Figma timelines remain in the linked file.
The repository contains the browser implementation and SVG exports, not a `.fig`
document. SVG export preserves still artwork; it does not carry Figma prototype
links, component behavior, or timeline animations.

## Runtime files

| File | Purpose |
| --- | --- |
| `index.html` | Preview entry point, screen navigation, and demo controls. |
| `app.js` | Screen composition, transitions, confetti, and simulated camera/voice events. |
| `style.css` | Layout, blue/glass styling, animated map and lens, light strips, and reduced motion. |
| `assets.json` | Shared palette and SVG strings used to compose the UI. |
| `assets.js` | Browser-loadable copy of that asset data; keep it synchronized with `assets.json`. |
| `motion.js` | Idle/sensor motion controller and gentle/quick shake demonstrations. |
| `tracking.js` | Demo hand geometry, 21 landmarks, fingertip connector, and distance interpolation. |
| `camera-demo.png` | Local bottle photograph used by the simulated camera screens. |
| `fonts.css`, `fonts/` | Bundled Nunito/Nunito Sans fonts and their SIL Open Font Licenses. |

Keep the runtime files together when copying or serving the preview. Artwork is
inlined through `assets.js`; changing an individual SVG file alone does not
update that bundle. Update the corresponding asset data and browser bundle too.

## Artwork

| Asset | Purpose |
| --- | --- |
| `hero-skye.svg`, `hero-pip.svg`, `hero-nova.svg`, `hero-echo.svg` | The four current landing characters. |
| `treasure-map.svg` | Locate parchment, route, compass, islands, and red X. |
| `find.svg`, `analyze.svg` | Card artwork retained from the card design revisions. The current full-screen choices are composed by `app.js` from `art.locateContent`, `art.exploreContent`, `splitPanels`, and the animated map/lens. |
| `camera-edge-lights.svg` | Four slim camera edge strips, animated by CSS. |
| `bottle-contour.svg` | Image-aligned demo bottle contour; runtime geometry is also in `assets.json` under `objectContour`. |
| `figma-exports/locate-art.svg`, `figma-exports/explore-art.svg` | Direct exports of the current Figma action artwork, with text outlined. |
| `figma-exports/locate-explore-screen.svg` | Complete current diagonal choice screen, including its panels and controls. |
| `figma-exports/camera-edge-lights.svg` | Native Figma light-strip component export. |
| `figma-exports/object-highlight.svg` | Translucent green bottle mask and contour on a transparent 360 × 800 canvas. |
| `figma-exports/hand-distance-*.svg` | Hand graphics and labels at 0.8 m, 0.3 m, and contact. |
| `figma-exports/manifest.json` | Original node IDs, dimensions, and Figma links for every direct export. |

The older `monster.svg`, `body.svg`, `eye.svg`, `crew-*.svg`, and
`glass-wave-*.svg` files remain as design source/history. The current home uses
`heroCrew`, Locate uses the treasure map, and camera screens use edge lights.

## Integration boundaries

The camera scene, segmentation mask, hand landmarks, meter values, and spoken
responses are demonstration data. A real implementation must supply camera
frames, object masks, tracked landmarks, and calibrated distances. Transform
object masks and hand coordinates with the same camera crop and orientation.
Do not infer physical meters from this demo's pixel separation.

`IrisTracking.update(element, distance)` animates the predefined demo pose; it
does not accept live hand landmarks. Replace that demo pose with detector output
when connecting a real tracking pipeline. Phone shake input in `motion.js` is a
separate optional device-sensor feature and requires permission and a secure
browser context on supporting phones.

The native SwiftUI app in `Iris/` uses the same revision 18 vector artwork.
Run `python3 scripts/sync_iris_artwork.py` after updating `assets.json`, or use
`--check` to confirm the generated `Iris/UI/Glass/IrisArtwork.swift` is current.
The native renderer preserves SVG group transforms, gradients and dash patterns
so the map, compass, route marker and camera rails can animate independently.
Live Vision joints and segmentation contours replace the browser's demo pose;
LiDAR provides meter values, and unavailable depth remains unavailable.

## Review checklist

1. Open the preview and try Loading & welcome, then Locate or explore.
2. Check map/lens sway; try the gentle and quick shake controls.
3. Choose Locate an object, then Say “locate my bottle”.
4. Try Move hand closer/back and Hide hand/Show hand. Both distance displays
   update together; no numeric distance remains when the hand is hidden.
5. Open Explore & understand and advance the simulated recognition events.
6. Enable Reduce motion to stop continuous movement.

Font license files and original visual-reference attribution are retained in
[`README.md`](README.md) and `fonts/`.
