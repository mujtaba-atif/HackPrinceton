# Iris UI preview — Welcome and discovery

This batch brings the updated welcome and Locate/Explore screens from the Iris
Figma study into the browser preview.

- Four large, rounded characters overlap in a blue-toned group, with distinct
  ears, glasses, a lab coat, and headphones. Their entrances, idle movement,
  blinks, and glances have different rhythms.
- The welcome tagline is **See beyond the surface**. A restrained blue-violet
  light reveal introduces the Iris title, tagline, and discovery heading.
- Locate and Explore keep their existing size, fonts, and colors, with diagonal
  placement, independent floating movement, and continuously wandering eyes.
- Existing glass panels, sprinkle accents, press feedback, navigation, and
  reduced-motion support remain available.

The shared palette and inline artwork live in `assets.json` and `assets.js`;
standalone character artwork is also included as `hero-*.svg`.

## Run the preview

From the repository root:

```sh
python3 -m http.server 4173 --directory Design/Iris
```

Open http://localhost:4173. No package installation or build step is needed.
The review controls outside the phone trigger simulated voice and camera events.

## Design and scope

Full editable Figma study: https://www.figma.com/design/zLF4VopCM0YI8eZAH2Aexg

The Figma study includes further camera explorations. This source batch covers
welcome and discovery; camera waves, object-shaped outlines, and live-reading
changes are reserved for a later batch. The camera demo retains the preceding
revision's behavior.

Camera imagery is AI-generated. Voice, object detection, AR, distance readings,
and haptics are simulated; this is a design preview, not native iOS integration.

The original study adapted selected UI artwork from the user-selected
`amiezeng/Probe` branch `riba/more-ui-stuff`. No repository was cloned or forked.
The current layouts, four-character group, and motion develop that visual motif.
Harvey informed the glass treatment; Render informed the entry-only text reveal.
No Harvey or Render code or assets were copied.

Nunito and Nunito Sans were approved for matching rounded typography in the
browser and Figma. Their font files and SIL Open Font Licenses are in `fonts/`.

References:

- https://github.com/amiezeng/Probe/tree/riba/more-ui-stuff
- https://www.youtube.com/watch?v=IKNUVaGHbME&t=109s
- https://www.harvey.ai/
- https://render.com/
