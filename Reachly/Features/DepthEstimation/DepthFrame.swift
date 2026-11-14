import CoreVideo
import CoreGraphics
import Foundation
import simd

/// Retains only low-resolution depth buffers and calibration, never the RGB image or ARFrame.
/// Pixel buffers supplied by ARKit are read-only for this snapshot's lifetime.
struct DepthFrame: @unchecked Sendable {
    let depthMap: CVPixelBuffer?
    let confidenceMap: CVPixelBuffer?
    let timestamp: TimeInterval
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
    let isTrackingNormal: Bool

    init(cameraFrame: CameraFrame) {
        self.init(depthMap: cameraFrame.sceneDepthMap, confidenceMap: cameraFrame.sceneDepthConfidenceMap,
                  timestamp: cameraFrame.timestamp, intrinsics: cameraFrame.cameraIntrinsics,
                  imageResolution: cameraFrame.imageResolution, isTrackingNormal: cameraFrame.isCameraTrackingNormal)
    }

    init(depthMap: CVPixelBuffer?, confidenceMap: CVPixelBuffer?, timestamp: TimeInterval,
         intrinsics: simd_float3x3, imageResolution: CGSize, isTrackingNormal: Bool) {
        self.depthMap = depthMap
        self.confidenceMap = confidenceMap
        self.timestamp = timestamp
        self.intrinsics = intrinsics
        self.imageResolution = imageResolution
        self.isTrackingNormal = isTrackingNormal
    }
}
