import CoreVideo
import CoreGraphics
import Foundation

enum DepthSampleResult {
    case measured(axialDepth: Double)
    case unavailable(DepthUnavailableReason)
}

enum DepthSampler {
    /// Median over the central 60% of the box avoids many boundary/background samples.
    /// This is a box heuristic, not segmentation: background or occluders may still dominate.
    static func sample(frame: DepthFrame, sensorRegion: CGRect) -> DepthSampleResult {
        guard let depth = frame.depthMap else { return .unavailable(.missingDepth) }
        guard let confidence = frame.confidenceMap else { return .unavailable(.lowConfidence) }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              width == CVPixelBufferGetWidth(confidence), height == CVPixelBufferGetHeight(confidence),
              let clipped = DetectionGeometry.clippedUnitRect(sensorRegion) else {
            return .unavailable(.invalidGeometry)
        }
        let inner = clipped.insetBy(dx: clipped.width * 0.2, dy: clipped.height * 0.2)
        // Include only pixel centers inside the region; never expand a tiny box to other surfaces.
        let minX = max(0, Int(ceil(inner.minX * Double(width) - 0.5)))
        let maxX = min(width - 1, Int(floor(inner.maxX * Double(width) - 0.5)))
        let minY = max(0, Int(ceil(inner.minY * Double(height) - 0.5)))
        let maxY = min(height - 1, Int(floor(inner.maxY * Double(height) - 0.5)))
        guard maxX >= minX, maxY >= minY else { return .unavailable(.lowConfidence) }
        guard CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else {
            return .unavailable(.missingDepth)
        }
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else {
            return .unavailable(.lowConfidence)
        }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depth),
              let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else {
            return .unavailable(.missingDepth)
        }
        let depthStride = CVPixelBufferGetBytesPerRow(depth) / MemoryLayout<Float32>.stride
        let confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
        let depths = depthBase.assumingMemoryBound(to: Float32.self)
        let confidences = confidenceBase.assumingMemoryBound(to: UInt8.self)
        var samples: [Double] = []
        var attempted = 0
        // At most 20 × 20 samples; row padding is respected for both buffers.
        let stepX = max(1, Int(ceil(Double(maxX - minX + 1) / 20)))
        let stepY = max(1, Int(ceil(Double(maxY - minY + 1) / 20)))
        for y in stride(from: minY, through: maxY, by: stepY) {
            for x in stride(from: minX, through: maxX, by: stepX) {
                attempted += 1
                let level = confidences[y * confidenceStride + x]
                let meters = Double(depths[y * depthStride + x])
                // ARConfidenceLevel medium=1, high=2. Conservative application range, not a sensor guarantee.
                if (1...2).contains(level), meters.isFinite, (0.15...5).contains(meters) {
                    samples.append(meters)
                }
            }
        }
        guard samples.count >= 9, Double(samples.count) / Double(attempted) >= 0.5 else {
            return .unavailable(.lowConfidence)
        }
        let median = median(samples)
        let deviation = self.median(samples.map { abs($0 - median) })
        let agreement = Double(samples.filter { abs($0 - median) <= max(0.08, median * 0.15) }.count)
            / Double(samples.count)
        guard deviation <= max(0.04, median * 0.08), agreement >= 0.7 else {
            return .unavailable(.inconsistentDepth)
        }
        return .measured(axialDepth: median)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
