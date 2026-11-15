import CoreText
import SwiftUI
import UIKit

/// Iris's wordmarks ("IRIS", "LOCATE", "EXPLORE") as `ArtLayer`s, built from glyph outlines so they
/// animate and rasterize exactly like the Illustrator layers they replace (`ArtLayer.pieces` splits
/// them into letters for the home screen's hop-in wave).
enum IrisLettering {
    enum Orientation {
        /// Reads left to right.
        case horizontal
        /// Turned a quarter turn counter-clockwise, reading bottom to top, like the button labels in
        /// the artwork (the Explore face turns its label upright again).
        case upward
    }

    /// `text` set in heavy type, scaled to fit `rect` (artboard points, y down) and centered in it.
    static func layer(name: String, text: String, in rect: CGRect, color: Color,
                      orientation: Orientation = .horizontal) -> ArtLayer {
        var outline = glyphOutline(text)
        if orientation == .upward {
            // (x, y) → (y, -x): the reading direction turns from rightward to upward on a y-down canvas.
            outline = outline.applying(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0))
        }
        let box = outline.boundingRect
        guard box.width > 0, box.height > 0 else {
            return ArtLayer(name: name, fills: [ArtFill(color: color, evenOdd: false, path: Path())])
        }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let fitted = outline.applying(
            CGAffineTransform(translationX: -box.midX, y: -box.midY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        )
        return ArtLayer(name: name, fills: [ArtFill(color: color, evenOdd: false, path: fitted)])
    }

    /// The text's glyph outlines on a y-down canvas, at an arbitrary size (callers scale it).
    /// Set in SF Pro Heavy: the closest system match to the artwork's heavy grotesque wordmarks.
    private static func glyphOutline(_ text: String) -> Path {
        let base = UIFont.systemFont(ofSize: 200, weight: .heavy)
        let font = CTFontCreateWithFontDescriptor(base.fontDescriptor as CTFontDescriptor, 200, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): 0
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let combined = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                // Font space is y-up; flip to the artboard's y-down while placing each glyph.
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                  tx: positions[index].x, ty: -positions[index].y)
                if let placed = glyph.copy(using: &transform) { combined.addPath(placed) }
            }
        }
        return Path(combined)
    }
}
