import ARKit
import CoreGraphics
import CoreVideo
import Foundation
import simd

/// The camera data future vision features need, without exposing or retaining an entire `ARFrame`.
/// Core Video buffers are reference-counted and safe to retain for the short lifetime of an inference.
struct CameraFrame: @unchecked Sendable {
    let capturedImage: CVPixelBuffer
    let sceneDepthMap: CVPixelBuffer?
    let sceneDepthConfidenceMap: CVPixelBuffer?
    let isCameraTrackingNormal: Bool
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4
    let cameraIntrinsics: simd_float3x3
    let imageResolution: CGSize

    init(arFrame: ARFrame) {
        capturedImage = arFrame.capturedImage
        sceneDepthMap = arFrame.sceneDepth?.depthMap
        sceneDepthConfidenceMap = arFrame.sceneDepth?.confidenceMap
        if case .normal = arFrame.camera.trackingState {
            isCameraTrackingNormal = true
        } else {
            isCameraTrackingNormal = false
        }
        timestamp = arFrame.timestamp
        cameraTransform = arFrame.camera.transform
        cameraIntrinsics = arFrame.camera.intrinsics
        imageResolution = arFrame.camera.imageResolution
    }
}

