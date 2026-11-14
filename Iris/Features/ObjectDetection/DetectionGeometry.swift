import Foundation
import CoreGraphics

enum DetectionGeometry {
    static func clippedUnitRect(_ rect: CGRect) -> CGRect? {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0 else { return nil }
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    /// Vision bottom-left -> UI top-left, then the same centered aspect-fill as ARSCNView.
    /// The preview and overlay must share one viewport, including safe-area extensions.
    static func viewRect(_ box: CGRect, imageSize: CGSize, viewport: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: box.minX * width + (viewport.width - width) / 2,
                      y: (1 - box.maxY) * height + (viewport.height - height) / 2,
                      width: box.width * width, height: box.height * height)
    }

    /// Inverse of the rear sensor's .right rotation, for future depth-map sampling.
    /// Output is normalized native landscape sensor space with a top-left origin.
    static func sensorRect(_ box: CGRect) -> CGRect {
        CGRect(x: 1 - box.maxY, y: 1 - box.maxX, width: box.height, height: box.width)
    }

    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Double {
        let overlap = a.intersection(b)
        guard !overlap.isNull, !overlap.isEmpty else { return 0 }
        let area = overlap.width * overlap.height
        let union = a.width * a.height + b.width * b.height - area
        return union > 0 ? area / union : 0
    }
}
