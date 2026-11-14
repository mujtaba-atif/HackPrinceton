import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation

/// Text found in one camera frame, plus the measurements guidance needs.
struct LabelFrameAnalysis: Sendable {
    let lines: [RecognizedTextLine]
    /// Average luminance of the crop, 0 (black) ... 1 (white).
    let luminance: Double?
    let timestamp: TimeInterval
    let plan: LabelCropPlan
}

/// Crops a camera frame to the label region and recognizes its text, off the main actor.
/// Reads frames from the existing broker only; it owns no camera.
actor LabelFrameProcessor {
    /// Small crops are upscaled to at least this many pixels on their longest side (max 3x) for OCR.
    static let minimumLongSide: CGFloat = 1024

    private let ocr: OCRService
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(ocr: OCRService = OCRService()) {
        self.ocr = ocr
    }

    func analyze(_ frame: CameraFrame, plan: LabelCropPlan,
                 level: TextRecognitionLevel) throws -> LabelFrameAnalysis {
        try autoreleasepool {
            guard let crop = makeCrop(from: frame.capturedImage, region: plan.cropRect) else {
                throw OCRError.unreadableImage
            }
            let lines = try ocr.recognizeText(in: crop.image, level: level)
            return LabelFrameAnalysis(lines: lines, luminance: crop.luminance,
                                      timestamp: frame.timestamp, plan: plan)
        }
    }

    /// - Parameter region: Vision-normalized rectangle of the **upright portrait** image (bottom-left origin).
    func makeCrop(from pixelBuffer: CVPixelBuffer, region: CGRect) -> (image: CGImage, luminance: Double?)? {
        // Native AR buffers are landscape; Iris's UI and every Vision request treat them as `.right`.
        let upright = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let extent = upright.extent
        let pixelRect = CGRect(x: extent.minX + region.minX * extent.width,
                               y: extent.minY + region.minY * extent.height,
                               width: region.width * extent.width,
                               height: region.height * extent.height).integral.intersection(extent)
        guard !pixelRect.isNull, pixelRect.width >= 16, pixelRect.height >= 16 else { return nil }

        var cropped = upright.cropped(to: pixelRect)
            .transformed(by: CGAffineTransform(translationX: -pixelRect.minX, y: -pixelRect.minY))
        let longest = max(pixelRect.width, pixelRect.height)
        if longest < Self.minimumLongSide {
            let scale = min(Self.minimumLongSide / longest, 3)
            cropped = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let outputRect = cropped.extent.integral
        guard let image = context.createCGImage(cropped, from: outputRect) else { return nil }
        return (image, averageLuminance(of: cropped, in: outputRect))
    }

    private func averageLuminance(of image: CIImage, in rect: CGRect) -> Double? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = rect
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let red = Double(pixel[0]), green = Double(pixel[1]), blue = Double(pixel[2])
        return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
    }
}
