import CoreGraphics
import Foundation

/// Coordinate conversions for hand landmarks.
///
/// Spaces:
/// - **Vision**: normalized, bottom-left origin, in the orientation passed to the request (`.right`, upright portrait).
/// - **Image**: normalized, top-left origin, upright portrait. All `HandObservation` points use this.
/// - **View**: points in a SwiftUI viewport that shows the camera image with centered aspect-fill,
///   the same scaling `ARSCNView` and `DetectionGeometry.viewRect` use.
/// - **Sensor**: normalized, top-left origin, native landscape buffer, for future depth-map sampling.
enum HandGeometry {
    static func visionToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1 - point.y)
    }

    /// Image -> view, with centered aspect-fill. `mirrored` flips horizontally (e.g. a front-camera preview).
    static func imageToView(_ point: CGPoint, imageSize: CGSize, viewport: CGSize, mirrored: Bool = false) -> CGPoint {
        guard let fill = aspectFill(imageSize: imageSize, viewport: viewport) else { return .zero }
        let x = mirrored ? 1 - point.x : point.x
        return CGPoint(x: x * fill.width + fill.offset.x, y: point.y * fill.height + fill.offset.y)
    }

    /// View -> image; the exact inverse of `imageToView`. Results outside 0...1 are off-image (cropped).
    static func viewToImage(_ point: CGPoint, imageSize: CGSize, viewport: CGSize, mirrored: Bool = false) -> CGPoint? {
        guard let fill = aspectFill(imageSize: imageSize, viewport: viewport) else { return nil }
        let x = (point.x - fill.offset.x) / fill.width
        let y = (point.y - fill.offset.y) / fill.height
        return CGPoint(x: mirrored ? 1 - x : x, y: y)
    }

    /// Upright image -> native landscape sensor space; undoes the rear camera's `.right` orientation.
    static func imageToSensor(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.y, y: 1 - point.x)
    }

    /// Size of the upright image for a native landscape pixel buffer of `bufferSize`.
    static func uprightSize(forBufferSize bufferSize: CGSize) -> CGSize {
        CGSize(width: bufferSize.height, height: bufferSize.width)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func isValidNormalized(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    /// Monotone-chain convex hull, counter-clockwise, for drawing a hand outline.
    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard sorted.count > 2 else { return sorted }

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        func halfHull(_ input: [CGPoint]) -> [CGPoint] {
            var hull: [CGPoint] = []
            for point in input {
                while hull.count >= 2, cross(hull[hull.count - 2], hull[hull.count - 1], point) <= 0 {
                    hull.removeLast()
                }
                hull.append(point)
            }
            return hull
        }

        let lower = halfHull(sorted)
        let upper = halfHull(sorted.reversed())
        return Array(lower.dropLast() + upper.dropLast())
    }

    private static func aspectFill(imageSize: CGSize, viewport: CGSize) -> (width: CGFloat, height: CGFloat, offset: CGPoint)? {
        guard imageSize.width > 0, imageSize.height > 0, viewport.width > 0, viewport.height > 0 else { return nil }
        let scale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return (width, height, CGPoint(x: (viewport.width - width) / 2, y: (viewport.height - height) / 2))
    }
}
