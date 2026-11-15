import CoreGraphics

/// The outline of a segmentation mask as an ordered loop of points, for drawing the object's silhouette.
///
/// `ObjectMask.edge` holds the boundary cells but in raster order, which can't be joined into a line;
/// this walks the boundary in order instead (Moore-neighbour tracing), then thins and rounds it so the
/// stroke reads as a smooth contour rather than a staircase of mask cells.
enum MaskContour {
    /// The 8 neighbours, clockwise on screen (y down), starting west.
    private static let directions = [(-1, 0), (-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1)]

    /// The outer boundary of the mask's first region in raster order, as cell coordinates, clockwise.
    /// Empty when the mask is empty; a single cell for a region of one.
    static func trace(width: Int, height: Int, pixels: [Bool]) -> [(x: Int, y: Int)] {
        guard width > 0, height > 0, pixels.count == width * height,
              let first = pixels.firstIndex(of: true) else { return [] }
        func filled(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && pixels[y * width + x]
        }

        let start = (x: first % width, y: first / width)
        // Raster order means nothing is filled to the west of the first cell.
        let startBack = (x: start.x - 1, y: start.y)
        var current = start
        var back = startBack
        var loop = [start]
        let limit = 4 * width * height + 8

        for _ in 0..<limit {
            guard let from = directions.firstIndex(where: { $0.0 == back.x - current.x && $0.1 == back.y - current.y })
            else { break }
            var moved = false
            for step in 1...8 {
                let k = (from + step) % 8
                let next = (x: current.x + directions[k].0, y: current.y + directions[k].1)
                if filled(next.x, next.y) {
                    let previous = directions[(k + 7) % 8]
                    back = (x: current.x + previous.0, y: current.y + previous.1)
                    current = next
                    moved = true
                    break
                }
            }
            guard moved else { return loop }
            // Jacob's stopping criterion: back at the start, entered the same way.
            if current == start, back == startBack { break }
            loop.append(current)
        }
        return loop
    }

    /// The traced outline in normalized image coordinates (0–1, origin top left, y down — the upright
    /// camera image), thinned to at most `maxPoints` and smoothed. Nil for a mask too small to outline.
    static func outline(width: Int, height: Int, pixels: [Bool], maxPoints: Int = 90) -> [CGPoint]? {
        let cells = trace(width: width, height: height, pixels: pixels)
        guard cells.count >= 3 else { return nil }
        let stride = max(1, Int((Double(cells.count) / Double(maxPoints)).rounded(.up)))
        var points = Swift.stride(from: 0, to: cells.count, by: stride).map { i in
            CGPoint(x: (CGFloat(cells[i].x) + 0.5) / CGFloat(width), y: (CGFloat(cells[i].y) + 0.5) / CGFloat(height))
        }
        guard points.count >= 3 else { return nil }
        for _ in 0..<2 { points = chaikin(points) }
        return points
    }

    static func outline(of mask: ObjectMask, maxPoints: Int = 90) -> [CGPoint]? {
        outline(width: mask.width, height: mask.height, pixels: mask.pixels, maxPoints: maxPoints)
    }

    /// One round of Chaikin corner cutting on a closed loop.
    static func chaikin(_ points: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        out.reserveCapacity(points.count * 2)
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            out.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
            out.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
        }
        return out
    }

    /// Normalized image points on a view that shows the image aspect-filled (cropped to fill, centred),
    /// the way the AR camera preview does.
    static func aspectFill(_ point: CGPoint, image: CGSize, view: CGSize) -> CGPoint {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(view.width / image.width, view.height / image.height)
        let content = CGSize(width: image.width * scale, height: image.height * scale)
        return CGPoint(x: point.x * content.width - (content.width - view.width) / 2,
                       y: point.y * content.height - (content.height - view.height) / 2)
    }

    /// A normalized rect in the same mapping.
    static func aspectFill(_ rect: CGRect, image: CGSize, view: CGSize) -> CGRect {
        let a = aspectFill(CGPoint(x: rect.minX, y: rect.minY), image: image, view: view)
        let b = aspectFill(CGPoint(x: rect.maxX, y: rect.maxY), image: image, view: view)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
}
