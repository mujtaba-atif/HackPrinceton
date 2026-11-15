# Iris UI asset guide

This package contains the revision 25 browser design, including the four
characters, diagonal Locate/Explore choices, moving treasure map and magnifier,
two trails of four blue chevrons that steer continuously, a bare connector distance label, green target highlight, and
simulated hand-distance graphics. The bare measurement remains visible after
acquisition, including temporary hand loss, using the last valid sample until
tracking supplies a new one.

## Source and preview

- [Animated landing preview](https://app-vv74nvdykzsio2xxoy5pgrvgmdczd43ramggdbyipubmjv56i7pp.makeproxy-c.figma.site/?screen=home)
- [Editable Figma file](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg)
- [Discovery screen](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=4-275)
- [Camera guidance](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=4-279)
- [Closer-hand state](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=201-1050)
- [Live guidance preview](https://app-vv74nvdykzsio2xxoy5pgrvgmdczd43ramggdbyipubmjv56i7pp.makeproxy-c.figma.site/?screen=guidance)
- [Animated code preview](https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg?node-id=204-858&code-node-id=204-858)

The editable components and native Figma timelines remain in the linked file.
The native snapshot is included as
[`figma-source/iris-design-v25.fig`](figma-source/iris-design-v25.fig), preserving
the editable design and its current and historical Make repositories. The
[parity report](figma-source/parity-report.json) confirms that all 41 current
runtime files match this package byte for byte, including the ten resolved
binary LFS assets. The supplied landing PNG also matches its embedded Figma
copy exactly. Figma hosting configuration and older documentation remain in
the native archive; the local preview is dependency-free.

SVG exports preserve still artwork; they do not carry the complete Figma
prototype links, component behavior, or timeline animations.

`runtime-exports/` contains current SVG states generated from the preview's
production modules. `figma-exports/` preserves direct native Figma exports from
revision 18. The two manifests identify their distinct provenance; historical
exports are not mislabeled as the current runtime.

## Runtime files

| File | Purpose |
| --- | --- |
| `landing-reference.png` | Exact original user artwork from `Downloads/irisnewpic.png`, 852 × 1846, without recompression. |
| `landing-image.js` | Lossless data-URL embedding of that PNG for the hosted code layer. |
| `landing-motion.js` | Source-image masks, full white star trails, violet text shimmer, layered wave ribbons, and floating moon/crew scene. |
| `landing-motion.css` | Visible 7–10-second wave/scene loops, 1.6-second staggered streaks, reduced-motion support, and landing-only styling. |
| `index.html` | Preview entry point, screen navigation, and demo controls. |
| `app.js` | Screen composition, transitions, confetti, and simulated camera/voice events. |
| `style.css` | Layout, blue/glass styling, animated map and lens, guidance arrows, connector distance label, and reduced motion. |
| `assets.json` | Shared palette and SVG strings used to compose the UI. |
| `assets.js` | Browser-loadable copy of that asset data; keep it synchronized with `assets.json`. |
| `motion.js` | Idle/sensor motion controller and gentle/quick shake demonstrations. |
| `tracking.js` | Demo hand geometry, 21 landmarks, fingertip connector, persistent bare inch label, retained valid measurement, and distance interpolation. |
| `guidance.js` | Two four-chevron trails, continuous signed bearings, smooth in-place rotation, and direction/proximity states. |
| `camera-demo.png` | Local bottle photograph used by the simulated camera screens. |
| `fonts.css`, `fonts/` | Bundled Nunito/Nunito Sans fonts and their SIL Open Font Licenses. |

Keep the runtime files together when copying or serving the preview. Artwork is
inlined through `assets.js`; changing an individual SVG file alone does not
update that bundle. Update the corresponding asset data and browser bundle too.

## Artwork

| Asset | Purpose |
| --- | --- |
| `hero-skye.svg`, `hero-pip.svg`, `hero-nova.svg`, `hero-echo.svg` | Earlier vector landing characters retained as editable design history. The current landing uses the supplied raster artwork. |
| `treasure-map.svg` | Locate parchment, route, compass, islands, and red X. |
| `find.svg`, `analyze.svg` | Card artwork retained from the card design revisions. The current full-screen choices are composed by `app.js` from `art.locateContent`, `art.exploreContent`, `splitPanels`, and the animated map/lens. |
| `camera-edge-lights.svg` | Historical revision 18 camera edge strips; replaced in the browser by `guidance.js`. |
| `bottle-contour.svg` | Image-aligned demo bottle contour; runtime geometry is also in `assets.json` under `objectContour`. |
| `figma-exports/locate-art.svg`, `figma-exports/explore-art.svg` | Direct exports of the current Figma action artwork, with text outlined. |
| `figma-exports/locate-explore-screen.svg` | Complete current diagonal choice screen, including its panels and controls. |
| `figma-exports/camera-edge-lights.svg` | Historical native Figma light-strip component export. |
| `figma-exports/object-highlight.svg` | Translucent green bottle mask and contour on a transparent 360 × 800 canvas. |
| `figma-exports/hand-distance-*.svg` | Revision 18 hand graphics and moving labels at 0.8 m, 0.3 m, and contact; the current runtime uses bare text above the connector. |
| `figma-exports/manifest.json` | Original node IDs, dimensions, and Figma links for every direct export. |
| `runtime-exports/guidance-*.svg` | Current two-column, four-chevron overlays facing forward, left, right, and back, with styles embedded. |
| `runtime-exports/hand-distance-*.svg` | Current hand geometry and bare labels at 0.8 m, 0.3 m, and contact; includes the bundled Nunito font. |
| `runtime-exports/landing-static.svg` | Exact supplied artwork embedded in an SVG generated by the landing module, in its still/reduced-motion state. Raster characters remain raster. |
| `runtime-exports/generate.cjs`, `runtime-exports/manifest.json` | Reproducible SVG generation and source/output hashes. These are runtime exports, not native Figma exports. |

The landing now displays the supplied raster artwork; the earlier SVG characters remain as design history.

The older `monster.svg`, `body.svg`, `eye.svg`, `crew-*.svg`, and
`glass-wave-*.svg` files remain as design source/history. The current home uses
`landing-reference.png` through `landing-image.js` and `landing-motion.js`.
Locate uses the treasure map, and camera screens use the two four-chevron
trails generated by `guidance.js`.

## Integration boundaries

The camera scene, segmentation mask, hand landmarks, distance values, and spoken
responses are demonstration data. A real implementation must supply camera
frames, object masks, tracked landmarks, and calibrated distances. Transform
object masks and hand coordinates with the same camera crop and orientation.
Do not infer physical meters from this demo's pixel separation.

`IrisGuidance.render(options)` creates the two chevron trails;
`IrisGuidance.update(container, options)` updates direction and proximity.
Options are `distance` in meters, `handVisible`, `targetVisible`, and
`direction` (`forward`, `back`, `left`, `right`, or `reached`). A finite `bearing`
in degrees overrides directional presets and is clamped to −180…180. Negative
bearings point left, zero points forward, and positive bearings point right.
The bare measurement is rendered by `tracking.js`, follows the connector
midpoint and angle, and uses exactly 0.0254 meters per inch. After acquisition,
invalid or missing measurements retain the last valid number and connector.
The existing tracking badge reads **Last measurement** when that value is held;
the hand skeleton hides while the hand is lost. The first valid measurement is
required before showing a number. A new locate session or leaving the camera
resets the retained sample. The demo distance range is 0–0.8 meters.

`IrisTracking.render(distance, {handVisible, measurementValid})` can render a
retained sample. `IrisTracking.update(element, distance, {handVisible})` preserves
its last valid sample while the hand is absent or the new value is invalid; it
updates on a valid observed sample. Both use the predefined demo pose; the API
does not accept live hand landmarks. Replace that demo pose with detector output
when connecting a real tracking pipeline. Phone shake input in `motion.js` is a
separate optional device-sensor feature and requires permission and a secure
browser context on supporting phones.

The native SwiftUI app is in `Iris/`. It implements earlier Iris design revisions
and includes live camera, detection, hand-tracking, depth, and voice features.
These files provide the revision 25 browser reference and historical assets; they do not
automatically update the artwork embedded in `Iris/UI/Glass/IrisArtwork.swift`
or replace the native feature implementations.

## Review checklist

1. Open the preview and try Loading & welcome, then Locate or explore.
2. Check map/lens sway; try the gentle and quick shake controls.
3. Choose Locate an object, then Say “locate my bottle”.
4. Move the Demo hand distance slider or use closer/away. The bare inch label
   follows the connector while the hand pose and chevron colors update.
5. Try Guide left/right, Reach forward, Overshot — move back, and the target
   direction slider. Every chevron turns to the requested heading. Hide hand
   removes the skeleton while retaining the last number and connector; Show
   hand resumes live demo updates.
6. Open Explore & understand and advance the simulated recognition events.
7. Enable Reduce motion to stop continuous movement while preserving direction.

Font license files and original visual-reference attribution are retained in
[`README.md`](README.md) and `fonts/`.
