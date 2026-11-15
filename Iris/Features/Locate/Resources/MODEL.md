# Locate segmentation model

- Artifact: `yolo26n-seg.mlpackage` (Ultralytics YOLO26n-seg, Core ML), weights 2,841,088 bytes.
- Weights SHA-256: `8e480045754d661cc2c0c14f06599d892151d28baa55c60da1b128aa5c66534b`.
- Metadata author: Ultralytics. Metadata license: AGPL-3.0 (https://ultralytics.com/license).
- Trained on COCO's 80 classes; class names are read from the model's `names` metadata at load.
- Input: 640×640 RGB image (Vision `.scaleFit`). Outputs: candidate boxes with class scores and 32 mask
  coefficients, plus 32×160×160 mask prototypes. `SegmentationDetector` decodes them (per-class NMS,
  letterbox removal, sigmoid masks) and keeps the largest mask as the target outline.
- Xcode compiles the package into `yolo26n-seg.mlmodelc` in the app bundle; nothing is downloaded at runtime.
