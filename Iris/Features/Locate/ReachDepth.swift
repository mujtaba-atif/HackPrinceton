import CoreGraphics
import Foundation
import simd

/// Remembers where the target sits in the room, so its distance survives a hand covering it.
///
/// The object's depth is read as the median depth inside its detection box, and once a hand is between
/// the camera and the object, most of that box *is* the hand. Read that way, the object appears to be
/// wherever the hand is, so every hand passing in front of it looks like a touch. Instead, the object's
/// position is stored in world coordinates while it is clearly visible. While the hand covers it, its
/// depth is projected from there into the current camera, which also accounts for the phone moving a
/// little in the user's other hand.
struct ObjectDepthMemory {
    /// The object is assumed to stay put this long while the hand covers it.
    var maximumAge: TimeInterval = 20
    /// Weight of each new clear reading; damps LiDAR jitter without lagging a real change much.
    var smoothing: Float = 0.35
    /// A clear reading this far (meters) from the stored point replaces it outright: a different object
    /// or a moved one, not jitter.
    var jumpDistance: Float = 0.25

    private(set) var worldPoint: SIMD3<Float>?
    private var rememberedAt: TimeInterval = -.infinity

    /// - Parameter portraitPoint: The object in portrait camera space (meters; x right, y up, z forward).
    mutating func remember(portraitPoint: SIMD3<Float>, cameraTransform: simd_float4x4, at time: TimeInterval) {
        let world = Self.world(fromPortrait: portraitPoint, cameraTransform: cameraTransform)
        if let worldPoint, time - rememberedAt <= maximumAge, simd_distance(world, worldPoint) < jumpDistance {
            self.worldPoint = worldPoint + (world - worldPoint) * smoothing
        } else {
            worldPoint = world
        }
        rememberedAt = time
    }

    /// Distance along the current camera's forward axis to the remembered point, if still fresh.
    func axialDepth(cameraTransform: simd_float4x4, at time: TimeInterval) -> Float? {
        guard let worldPoint, time - rememberedAt <= maximumAge else { return nil }
        let depth = Self.portrait(fromWorld: worldPoint, cameraTransform: cameraTransform).z
        return depth > 0.05 ? depth : nil
    }

    mutating func reset() {
        worldPoint = nil
        rememberedAt = -.infinity
    }

    // Portrait camera space is `DepthGeometry.portraitRay`'s: x right, y up, z forward. ARKit's camera space
    // has x along the sensor's long side (portrait down → +x), y toward portrait's right, and z toward
    // the viewer. `ReachDepthTests` checks this against the ray formula.

    static func cameraSpace(fromPortrait p: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(-p.y, p.x, -p.z)
    }

    static func portraitSpace(fromCamera c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(c.y, -c.x, -c.z)
    }

    static func world(fromPortrait p: SIMD3<Float>, cameraTransform: simd_float4x4) -> SIMD3<Float> {
        let c = cameraSpace(fromPortrait: p)
        let w = cameraTransform * SIMD4(c.x, c.y, c.z, 1)
        return SIMD3(w.x, w.y, w.z)
    }

    static func portrait(fromWorld w: SIMD3<Float>, cameraTransform: simd_float4x4) -> SIMD3<Float> {
        let c = cameraTransform.inverse * SIMD4(w.x, w.y, w.z, 1)
        return portraitSpace(fromCamera: SIMD3(c.x, c.y, c.z))
    }
}

/// Reads the object's depth around a hand instead of through it. All rects are Vision coordinates.
enum ReachOcclusion {
    /// Each hand's joints, boxed and padded for the flesh around them (joints are bone centres).
    static func handRegions(_ hands: [[CGPoint]], padding: CGFloat = 0.04) -> [CGRect] {
        hands.compactMap { joints in
            guard let first = joints.first else { return nil }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for joint in joints.dropFirst() {
                minX = min(minX, joint.x); maxX = max(maxX, joint.x)
                minY = min(minY, joint.y); maxY = max(maxY, joint.y)
            }
            return CGRect(x: minX - padding, y: minY - padding,
                          width: maxX - minX + 2 * padding, height: maxY - minY + 2 * padding)
        }
    }

    /// Whether hands cover enough of the area `DepthSampler` reads (the box's central 60%) to skew it.
    static func covers(_ box: CGRect, hands: [CGRect], threshold: CGFloat = 0.05) -> Bool {
        let inner = box.insetBy(dx: box.width * 0.2, dy: box.height * 0.2)
        let area = inner.width * inner.height
        guard area > 0 else { return false }
        let covered = hands.reduce(CGFloat(0)) { total, hand in
            let overlap = inner.intersection(hand)
            return overlap.isNull ? total : total + overlap.width * overlap.height
        }
        return covered / area > threshold
    }

    /// The box split into a grid, keeping only the cells no hand touches. Small boxes get a coarser grid
    /// so each cell still holds enough depth pixels to sample.
    static func clearCells(of box: CGRect, avoiding hands: [CGRect]) -> [CGRect] {
        let grid = min(4, max(2, Int(min(box.width, box.height) / 0.06)))
        let width = box.width / CGFloat(grid), height = box.height / CGFloat(grid)
        var cells: [CGRect] = []
        for row in 0..<grid {
            for column in 0..<grid {
                let cell = CGRect(x: box.minX + CGFloat(column) * width, y: box.minY + CGFloat(row) * height,
                                  width: width, height: height)
                if !hands.contains(where: { $0.intersects(cell) }) { cells.append(cell) }
            }
        }
        return cells
    }

    /// The object's depth from the cells clear of the hand.
    ///
    /// A forearm crossing in front isn't in the hand's joint box, but it is always nearer the camera than
    /// the fingertips, so anything clearly nearer than them is dropped. Of what's left, the object is the
    /// nearest surface two cells agree on: the box's edge cells may be wall or table behind it.
    static func objectDepth(cellDepths: [Float], nearestHandDepth: Float?) -> Float? {
        let floor = nearestHandDepth.map { $0 - 0.04 } ?? 0
        let depths = cellDepths.filter { $0 >= floor }.sorted()
        for (index, depth) in depths.enumerated() {
            let tolerance = max(0.05, depth * 0.08)
            let cluster = depths[index...].prefix { $0 - depth <= tolerance }
            if cluster.count >= 2 {
                return cluster.reduce(0, +) / Float(cluster.count)
            }
        }
        return nil
    }
}
