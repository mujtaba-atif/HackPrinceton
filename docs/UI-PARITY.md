# Iris revision 18 parity

The UI reference is the [interactive Figma preview](https://app-pgx4ms76rppvohkneqyeezy5lnq44y6h6qgehvear4xi2jidzs7h.makeproxy-c.figma.site/)
and the browser bundle in `Design/Iris`. Both were inspected on November 15, 2026.

## Shared implementation

- Welcome keeps the four original characters, title reveal, swipe/tap/voice continuation, and glass wipe.
- Discovery uses equal-area diagonal Locate/Explore panels with matching hit regions, the treasure map, traveling route marker, compass, destination animation, and 6.2-second map/lens sway.
- Camera screens use the four original optical rails, green silhouette tint, clipped scanning light, and matching glass status panels/pills.
- Live hand joints, a faint contour, fingertip pulse, connector, and measured meter labels replace the browser's simulated hand pose. Missing joints break individual bone segments. Missing hands hide measurements, and unavailable depth is not replaced by camera-to-hand distance.
- Explore advances from searching to live reading to conversation on OCR evidence. There is no visible countdown. Back navigation, spoken commands, rescanning, and the existing voice fallback remain connected.
- Reduced Motion stops continuous decoration and sensor movement and hides confetti.

`scripts/sync_iris_artwork.py` generates the native vector bundle from
`Design/Iris/assets.json`. The browser implementation was already on `main`;
its runtime assets and simulated flows are retained.

## Review completed

Browser walkthroughs covered discovery, search/no result, hand closer/back,
hidden/recovered hand, object reached, reading distance, text detected/lost,
result ready, summary visibility, follow-up questions, rescanning, back
navigation, shake demonstrations, and reduced motion. Intro replay was also
checked locally.

The hosted reference had a missing camera photograph and fallback serif card
titles during review. The local preview retains its working bundled camera
photograph and Nunito/Nunito Sans fonts.

The native simulator build and 123 unit tests passed before the user requested
that further app testing happen on their phone. Those tests include SVG parsing,
diagonal hit regions, OCR readiness/text loss, camera geometry, and the existing
vision, depth, hand-tracking, label-reading, and voice logic. Final visual
polish was reviewed in source and the final iPhone target compiled successfully;
simulator UI review was stopped at the user's request. No pixel-exact native
visual certification is claimed.

## Phone verification

Run the `Iris` scheme on the intended iPhone and check welcome → discovery →
Locate/Explore, the diagonal tap boundary, live contours and hand landmarks,
missing-hand/depth states, recognition-driven reading, conversation/back,
background/resume, and the system Reduce Motion setting. Camera, LiDAR,
sensor response, speech, and end-to-end hardware latency require this device
check; browser demo distances are not hardware measurements.
