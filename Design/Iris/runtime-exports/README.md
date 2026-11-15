# Current runtime SVG states

These exports are generated from the same JavaScript modules used by the live
preview. They complement the older, direct Figma exports in `../figma-exports/`.
They are **not** exports of native Figma nodes and are not `.fig` documents.

Run from the repository root:

```sh
node Design/Iris/runtime-exports/generate.cjs
```

The files contain two four-chevron columns facing forward, left, right, or back;
hand poses and bare distance labels at 0.8 m, 0.3 m, and contact; a retained
measurement during hand loss; and the exact
landing artwork in its still/reduced-motion state. Each SVG has its own styles.
Distance labels embed the bundled Nunito font. The landing SVG embeds the
original PNG, so the characters retain their exact pixels rather than becoming
editable vector paths.

These files are portable static states. Continuous motion, steering, persistence,
screen transitions, and controls live in the HTML/CSS/JS source one directory up.
`manifest.json` records source and output hashes for reproducible regeneration.
