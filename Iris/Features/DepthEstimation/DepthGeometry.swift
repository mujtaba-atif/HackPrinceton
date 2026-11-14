import CoreGraphics
import Foundation
import simd

enum DepthGeometry {
    /// Use full-image Vision coordinates, never preview coordinates. Preview aspect-fill cropping
    /// is a display-only transform; applying it here would sample a different physical surface.
    static func sensorRegion(for target: SelectedObjectTarget, imageResolution: CGSize) -> CGRect? {
        guard target.uprightImageSize == CGSize(width: imageResolution.height, height: imageResolution.width),
              let box = target.currentBoundingBox,
              let clipped = DetectionGeometry.clippedUnitRect(box) else { return nil }
        return DetectionGeometry.sensorRect(clipped)
    }

    /// Unproject using RGB-image intrinsics and RGB dimensions. Normalized coordinates already
    /// account for the lower depth-map resolution, so intrinsics must NOT be scaled again.
    static func portraitRay(sensorPoint: CGPoint, frame: DepthFrame) -> SIMD3<Double>? {
        let fx = Double(frame.intrinsics[0][0]), fy = Double(frame.intrinsics[1][1])
        let cx = Double(frame.intrinsics[2][0]), cy = Double(frame.intrinsics[2][1])
        let width = frame.imageResolution.width, height = frame.imageResolution.height
        guard [fx, fy, cx, cy, width, height, sensorPoint.x, sensorPoint.y].allSatisfy(\.isFinite),
              fx > 0, fy > 0, width > 0, height > 0 else { return nil }
        let sensorX = (sensorPoint.x * width - cx) / fx
        let sensorY = (sensorPoint.y * height - cy) / fy
        // Native sensor X runs down portrait; native sensor Y runs to portrait's left.
        return SIMD3(-sensorY, -sensorX, 1)
    }

    static func estimate(objectID: UUID, ray: SIMD3<Double>, axialDepth: Double?,
                         validity: SpatialMeasurementValidity, timestamp: TimeInterval) -> SpatialTargetEstimate {
        let horizontal = atan2(ray.x, ray.z)
        let vertical = atan2(ray.y, hypot(ray.x, ray.z))
        let deadBand = 7.0 * .pi / 180
        let position = axialDepth.map { ray * $0 }
        return .init(objectID: objectID, distanceMeters: position.map(simd_length),
                     horizontalPosition: horizontal < -deadBand ? .left : horizontal > deadBand ? .right : .center,
                     verticalPosition: vertical < -deadBand ? .below : vertical > deadBand ? .above : .center,
                     horizontalAngleRadians: horizontal, verticalAngleRadians: vertical,
                     positionInPortraitCameraMeters: position, validity: validity, timestamp: timestamp)
    }
}
