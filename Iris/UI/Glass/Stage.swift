import SwiftUI

/// The design's 360 × 800 phone, fitted to the screen.
///
/// The design places everything in points on that phone. A `Stage` scales those points uniformly to fit
/// the real screen (`unit` screen points per design point) and centres the result, so every screen keeps
/// the design's proportions; backgrounds and edge effects still bleed to the screen's edges.
struct Stage: Equatable {
    static let design = CGSize(width: 360, height: 800)

    /// The real screen, in points.
    let size: CGSize
    /// Screen points per design point.
    let unit: CGFloat
    /// Where the design's top-left corner lands on screen.
    let origin: CGPoint

    init(size: CGSize) {
        self.size = size
        let fit = min(size.width / Self.design.width, size.height / Self.design.height)
        unit = fit.isFinite && fit > 0 ? fit : 1
        origin = CGPoint(x: (size.width - Self.design.width * unit) / 2,
                         y: (size.height - Self.design.height * unit) / 2)
    }

    /// A design rect, on screen.
    func rect(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * unit, y: origin.y + rect.minY * unit,
               width: rect.width * unit, height: rect.height * unit)
    }

    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        rect(CGRect(x: x, y: y, width: width, height: height))
    }

    /// Design points to screen points, for sizes, strokes and font sizes.
    func callAsFunction(_ value: CGFloat) -> CGFloat { value * unit }
}

extension View {
    /// Lays the view out in a design rect (`Stage.rect`). Put it directly in a full-screen `ZStack`.
    func placed(_ rect: CGRect, on stage: Stage) -> some View {
        let frame = stage.rect(rect)
        return self.frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    func placed(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, on stage: Stage) -> some View {
        placed(CGRect(x: x, y: y, width: width, height: height), on: stage)
    }
}

/// A full-screen container that hands its children the `Stage` for the screen's size.
struct StageView<Content: View>: View {
    @ViewBuilder var content: (Stage) -> Content

    var body: some View {
        GeometryReader { geo in
            let stage = Stage(size: geo.size)
            ZStack(alignment: .topLeading) {
                content(stage)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.irisUnit, stage.unit)
        }
    }
}
