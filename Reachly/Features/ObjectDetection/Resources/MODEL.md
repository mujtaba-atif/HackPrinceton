# Bundled object detector

- Artifact: `YOLOv3TinyFP16.mlmodel`, 17,769,580 bytes (verify using `wc -c`).
- Source: [Apple Core ML model gallery](https://developer.apple.com/machine-learning/models/).
- [Direct download](https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyFP16.mlmodel).
- Downloaded November 14, 2026; unchanged upstream weights.
- SHA-256: `73406178d0f5793d0d5d1e38274acd146a744c2245c9b63a11998a5015925dda`.
- Metadata authors: Joseph Redmon and Ali Farhadi. Version: YOLOv3-tiny; Apple model metadata version: 2.0.
- Metadata license points to [pjreddie/darknet](https://github.com/pjreddie/darknet). Its upstream [LICENSE](https://github.com/pjreddie/darknet/blob/master/LICENSE) is bundled verbatim as `YOLO-LICENSE.txt`.
- Input: RGB image, 416×416. Optional double inputs: `confidenceThreshold`, `iouThreshold`.
- Outputs: variable-length `coordinates` (N×4) and `confidence` (N×80), with NMS and class labels. Vision converts these into recognized-object observations.
- Xcode compiles the source model into `YOLOv3TinyFP16.mlmodelc` in the app bundle. The app loads that compiled resource; no runtime model download or Python dependency is needed.

## Supported classes

These are the exact 80 labels read from the bundled model, including its older COCO spellings:

```text
person, bicycle, car, motorbike, aeroplane, bus, train, truck, boat,
traffic light, fire hydrant, stop sign, parking meter, bench,
bird, cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe,
backpack, umbrella, handbag, tie, suitcase, frisbee, skis, snowboard,
sports ball, kite, baseball bat, baseball glove, skateboard, surfboard,
tennis racket, bottle, wine glass, cup, fork, knife, spoon, bowl,
banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza,
donut, cake, chair, sofa, pottedplant, bed, diningtable, toilet,
tvmonitor, laptop, mouse, remote, keyboard, cell phone, microwave,
oven, toaster, sink, refrigerator, book, clock, vase, scissors,
teddy bear, hair drier, toothbrush
```

These are recognition categories, not guaranteed detections. There is no class for keys, medication, a generic can, or arbitrary named personal items. A mug may be recognized as `cup`; the model does not identify a particular person's cup. See the README for thresholds, tracking limits, and physical-device tests.
