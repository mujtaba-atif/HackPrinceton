import SwiftUI

/// An SVG from the design (`IrisArtwork`), parsed into shapes SwiftUI can draw and animate.
///
/// Every `<g>` with an `id` or `class` stays a named group, so a view can animate it on its own (a blink,
/// a glance) the way the design's CSS does. Text is left out: the cards set theirs in SwiftUI.
struct VectorArt: Sendable {
    let viewBox: CGRect
    let root: VectorGroup

    init(svg: String) {
        let parser = SVGParser(svg)
        viewBox = parser.viewBox
        root = parser.root
    }

    /// The group named `name`, anywhere in the tree.
    func group(_ name: String) -> VectorGroup? { root.find(name) }

    /// Every path in the art, in one, for a silhouette (the crew's shadows).
    var outline: Path { root.outline }
}

struct VectorGroup: Sendable {
    var name: String?
    var children: [VectorNode] = []

    func find(_ name: String) -> VectorGroup? {
        if self.name == name { return self }
        for case .group(let group) in children {
            if let found = group.find(name) { return found }
        }
        return nil
    }

    /// Union of everything in it, in user units: the CSS `transform-box: fill-box` a group's
    /// transforms are anchored to.
    var bounds: CGRect {
        children.reduce(CGRect.null) { box, node in
            switch node {
            case .shape(let shape): box.union(shape.path.boundingRect)
            case .group(let group): box.union(group.bounds)
            }
        }
    }

    var outline: Path {
        var path = Path()
        for node in children {
            switch node {
            case .shape(let shape): path.addPath(shape.path)
            case .group(let group): path.addPath(group.outline)
            }
        }
        return path
    }
}

indirect enum VectorNode: Sendable {
    case shape(VectorShape)
    case group(VectorGroup)
}

struct VectorShape: @unchecked Sendable {
    enum Paint {
        case color(Color)
        case linear(Gradient, start: CGPoint, end: CGPoint)
    }

    var path: Path
    var fill: Paint?
    var stroke: Paint?
    var strokeStyle = StrokeStyle(lineWidth: 1)
    var opacity: Double = 1

    func draw(in context: inout GraphicsContext) {
        context.opacity = opacity
        if let fill { context.fill(path, with: shading(fill)) }
        if let stroke { context.stroke(path, with: shading(stroke), style: strokeStyle) }
    }

    private func shading(_ paint: Paint) -> GraphicsContext.Shading {
        switch paint {
        case .color(let color): .color(color)
        case .linear(let gradient, let start, let end): .linearGradient(gradient, startPoint: start, endPoint: end)
        }
    }
}

/// Draws a group of `art` filling its frame, the way an `<svg>` with that viewBox fills its box
/// (`xMidYMid meet`). `animate` returns the motions for a named group: each plays about the group's own
/// bounds, with design units scaled to the frame.
struct VectorArtView: View {
    let art: VectorArt
    var group: VectorGroup?
    var animate: (String) -> [Motion] = { _ in [] }
    /// A shared clock for the motions, so separate pieces of one picture stay in step.
    var since: Date?
    /// How a named group answers the phone (eyes looking and blinking), on top of its motions.
    var respond: (String) -> EyeResponse? = { _ in nil }
    var hiddenGroups: Set<String> = []
    /// Dash travel in SVG units/second, applied only to the named animated strokes.
    var dashSpeeds: [String: CGFloat] = [:]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / art.viewBox.width, geo.size.height / art.viewBox.height)
            GroupView(group: group ?? art.root, viewBox: art.viewBox, scale: scale, animate: animate, since: since,
                      respond: respond, hiddenGroups: hiddenGroups, dashSpeeds: dashSpeeds)
                .frame(width: art.viewBox.width * scale, height: art.viewBox.height * scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct GroupView: View {
    let group: VectorGroup
    let viewBox: CGRect
    let scale: CGFloat
    let animate: (String) -> [Motion]
    let since: Date?
    let respond: (String) -> EyeResponse?
    var hiddenGroups: Set<String> = []
    var dashSpeeds: [String: CGFloat] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Consecutive shapes share one `Canvas`; a named group gets its own view so it can move.
    private enum Run {
        case shapes([VectorShape])
        case group(VectorGroup)
    }

    private var runs: [Run] {
        var runs: [Run] = []
        var shapes: [VectorShape] = []
        for node in group.children {
            switch node {
            case .shape(let shape):
                shapes.append(shape)
            case .group(let child):
                if child.name == nil {
                    // An anonymous group only carried styles, which the parser has already applied.
                    shapes.append(contentsOf: child.flattenedShapes)
                } else {
                    if !shapes.isEmpty { runs.append(.shapes(shapes)) }
                    shapes = []
                    runs.append(.group(child))
                }
            }
        }
        if !shapes.isEmpty { runs.append(.shapes(shapes)) }
        return runs
    }

    var body: some View {
        let content = ZStack {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case .shapes(let shapes):
                    if let name = group.name, let speed = dashSpeeds[name], !reduceMotion {
                        TimelineView(.animation) { timeline in
                            draw(shapes, dashPhase: timeline.date.timeIntervalSince(since ?? timeline.date) * speed)
                        }
                    } else {
                        draw(shapes, dashPhase: 0)
                    }
                case .group(let child):
                    if !hiddenGroups.contains(child.name ?? "") {
                        GroupView(group: child, viewBox: viewBox, scale: scale, animate: animate, since: since,
                                  respond: respond, hiddenGroups: hiddenGroups, dashSpeeds: dashSpeeds)
                    }
                }
            }
        }
        if let name = group.name {
            let box = group.bounds
            let anchor = UnitPoint(x: (box.midX - viewBox.minX) / viewBox.width,
                                   y: (box.midY - viewBox.minY) / viewBox.height)
            let response = respond(name) ?? EyeResponse()
            content
                .motion(animate(name), unit: scale, anchor: anchor, since: since)
                .scaleEffect(response.scale, anchor: anchor)
                .offset(x: response.offset.x * scale, y: response.offset.y * scale)
                .blink(response.blinks, anchor: anchor)
                .animation(.spring(duration: 0.3, bounce: 0.45), value: response.scale)
        } else {
            content
        }
    }
    private func draw(_ shapes: [VectorShape], dashPhase: CGFloat) -> some View {
        Canvas { context, _ in
            context.translateBy(x: -viewBox.minX * scale, y: -viewBox.minY * scale)
            context.scaleBy(x: scale, y: scale)
            for var shape in shapes {
                var layer = context
                shape.strokeStyle.dashPhase = dashPhase
                shape.draw(in: &layer)
            }
        }
    }

}

extension VectorGroup {
    var flattenedShapes: [VectorShape] {
        children.flatMap { node -> [VectorShape] in
            switch node {
            case .shape(let shape): [shape]
            case .group(let group): group.flattenedShapes
            }
        }
    }
}

// MARK: - Parsing

/// Reads the subset of SVG the design exports: `svg` (viewBox, presentation attributes), `g`, `path`,
/// `rect`, `circle`, `ellipse`, and `linearGradient` in user space, with inherited presentation
/// attributes.
private final class SVGParser: NSObject, XMLParserDelegate {
    private(set) var viewBox = CGRect(x: 0, y: 0, width: 100, height: 100)
    private(set) var root = VectorGroup()

    private struct Style {
        var fill: String? = "#000"
        var fillOpacity: Double = 1
        var stroke: String?
        var strokeOpacity: Double = 1
        var strokeWidth: Double = 1
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var dash: [CGFloat] = []
    }

    private struct GradientDef {
        var start = CGPoint.zero
        var end = CGPoint(x: 1, y: 0)
        var stops: [Gradient.Stop] = []
        var userSpace = false
    }

    private var stack: [(group: VectorGroup, style: Style)] = []
    private var gradients: [String: GradientDef] = [:]
    private var gradientID: String?
    /// Shapes inside `<defs>` are definitions, not drawing.
    private var defsDepth = 0
    private var transforms: [CGAffineTransform] = [.identity]

    init(_ svg: String) {
        super.init()
        stack = [(VectorGroup(), Style())]
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = self
        parser.parse()
        root = stack.first?.group ?? VectorGroup()
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "svg":
            if let box = attributes["viewBox"]?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap({ Double($0) }),
               box.count == 4 {
                viewBox = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
            }
            stack[0].style = resolveStyle(attributes, inheriting: stack[0].style)
        case "defs":
            defsDepth += 1
        case "linearGradient":
            gradientID = attributes["id"]
            var def = GradientDef()
            def.userSpace = attributes["gradientUnits"] == "userSpaceOnUse"
            def.start = CGPoint(x: number(attributes["x1"]) ?? 0, y: number(attributes["y1"]) ?? 0)
            def.end = CGPoint(x: number(attributes["x2"]) ?? 1, y: number(attributes["y2"]) ?? 0)
            if let gradientID { gradients[gradientID] = def }
        case "stop":
            guard let gradientID, var def = gradients[gradientID] else { return }
            let color = parseColor(attributes["stop-color"] ?? "#000", opacity: number(attributes["stop-opacity"]) ?? 1)
                ?? .clear
            def.stops.append(.init(color: color, location: number(attributes["offset"]) ?? 0))
            gradients[gradientID] = def
        case "g":
            let parentStyle = stack.last!.style
            var group = VectorGroup()
            group.name = attributes["id"] ?? attributes["class"]
            stack.append((group, resolveStyle(attributes, inheriting: parentStyle)))
            pendingOpacity.append(number(attributes["opacity"]) ?? 1)
            transforms.append(transform(attributes["transform"]).concatenating(transforms.last!))
        case "path", "rect", "circle", "ellipse":
            guard defsDepth == 0, let path = shapePath(element, attributes) else { return }
            let style = resolveStyle(attributes, inheriting: stack.last!.style)
            let matrix = transform(attributes["transform"]).concatenating(transforms.last!)
            var shape = VectorShape(path: path.applying(matrix))
            shape.fill = style.fill.flatMap { paint($0, opacity: style.fillOpacity, bounds: path.boundingRect, transform: matrix) }
            shape.stroke = style.stroke.flatMap { paint($0, opacity: style.strokeOpacity, bounds: path.boundingRect, transform: matrix) }
            shape.strokeStyle = StrokeStyle(lineWidth: style.strokeWidth, lineCap: style.lineCap,
                                            lineJoin: style.lineJoin, dash: style.dash)
            shape.opacity = (number(attributes["opacity"]) ?? 1) * pendingOpacity.reduce(1, *)
            let named = attributes["id"] ?? attributes["class"]
            if let named {
                // A named shape is a group of one, so it can be animated like the design's CSS does.
                var group = VectorGroup()
                group.name = named
                group.children = [.shape(shape)]
                stack[stack.count - 1].group.children.append(.group(group))
            } else {
                stack[stack.count - 1].group.children.append(.shape(shape))
            }
        default:
            break
        }
    }

    /// `opacity` on each open `<g>`, applied to the shapes inside it.
    private var pendingOpacity: [Double] = []

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "defs":
            defsDepth -= 1
        case "linearGradient":
            gradientID = nil
        case "g":
            guard stack.count > 1 else { return }
            let finished = stack.removeLast().group
            pendingOpacity.removeLast()
            transforms.removeLast()
            stack[stack.count - 1].group.children.append(.group(finished))
        default:
            break
        }
    }

    private func resolveStyle(_ attributes: [String: String], inheriting parent: Style) -> Style {
        var style = parent
        if let fill = attributes["fill"] { style.fill = fill == "none" ? nil : fill }
        if let stroke = attributes["stroke"] { style.stroke = stroke == "none" ? nil : stroke }
        if let value = number(attributes["fill-opacity"]) { style.fillOpacity = value }
        if let value = number(attributes["stroke-opacity"]) { style.strokeOpacity = value }
        if let value = number(attributes["stroke-width"]) { style.strokeWidth = value }
        if let value = attributes["stroke-dasharray"] {
            style.dash = value.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { token -> CGFloat? in
                guard let number = Double(token) else { return nil }; return CGFloat(number)
            }
        }
        switch attributes["stroke-linecap"] {
        case "round": style.lineCap = .round
        case "square": style.lineCap = .square
        case "butt": style.lineCap = .butt
        default: break
        }
        switch attributes["stroke-linejoin"] {
        case "round": style.lineJoin = .round
        case "bevel": style.lineJoin = .bevel
        case "miter": style.lineJoin = .miter
        default: break
        }
        return style
    }

    private func shapePath(_ element: String, _ a: [String: String]) -> Path? {
        switch element {
        case "path":
            return a["d"].map(SVGPath.parse)
        case "rect":
            let rect = CGRect(x: number(a["x"]) ?? 0, y: number(a["y"]) ?? 0,
                              width: number(a["width"]) ?? 0, height: number(a["height"]) ?? 0)
            let radius = number(a["rx"]) ?? number(a["ry"]) ?? 0
            return radius > 0 ? Path(roundedRect: rect, cornerRadius: radius, style: .circular) : Path(rect)
        case "circle":
            let r = number(a["r"]) ?? 0
            return Path(ellipseIn: CGRect(x: (number(a["cx"]) ?? 0) - r, y: (number(a["cy"]) ?? 0) - r,
                                          width: 2 * r, height: 2 * r))
        case "ellipse":
            let rx = number(a["rx"]) ?? 0, ry = number(a["ry"]) ?? 0
            return Path(ellipseIn: CGRect(x: (number(a["cx"]) ?? 0) - rx, y: (number(a["cy"]) ?? 0) - ry,
                                          width: 2 * rx, height: 2 * ry))
        default:
            return nil
        }
    }

    private func paint(_ value: String, opacity: Double, bounds: CGRect, transform: CGAffineTransform) -> VectorShape.Paint? {
        if value.hasPrefix("url(#") {
            let id = String(value.dropFirst(5).dropLast())
            guard let def = gradients[id] else { return nil }
            let stops = def.stops.map { Gradient.Stop(color: $0.color.opacity(opacity), location: $0.location) }
            func point(_ p: CGPoint) -> CGPoint {
                let local = def.userSpace ? p : CGPoint(x: bounds.minX + p.x * bounds.width,
                                                       y: bounds.minY + p.y * bounds.height)
                return local.applying(transform)
            }
            return .linear(Gradient(stops: stops), start: point(def.start), end: point(def.end))
        }
        return parseColor(value, opacity: opacity).map { .color($0) }
    }

    private func number(_ value: String?) -> Double? {
        guard let value else { return nil }
        if value.hasSuffix("%") { return Double(value.dropLast()).map { $0 / 100 } }
        return Double(value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: ""))
    }

    /// The map's compass, destination and sparkles are positioned by SVG transforms.
    private func transform(_ source: String?) -> CGAffineTransform {
        guard let source, let regex = try? NSRegularExpression(pattern: "([A-Za-z]+)\\(([^)]*)\\)") else { return .identity }
        var result = CGAffineTransform.identity
        let ns = source as NSString
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            let values = ns.substring(with: match.range(at: 2))
                .split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            let next: CGAffineTransform
            switch name {
            case "translate" where !values.isEmpty:
                next = CGAffineTransform(translationX: values[0], y: values.count > 1 ? values[1] : 0)
            case "scale" where !values.isEmpty:
                next = CGAffineTransform(scaleX: values[0], y: values.count > 1 ? values[1] : values[0])
            case "rotate" where !values.isEmpty:
                let x = values.count > 2 ? values[1] : 0, y = values.count > 2 ? values[2] : 0
                next = CGAffineTransform(translationX: -x, y: -y)
                    .concatenating(CGAffineTransform(rotationAngle: values[0] * .pi / 180))
                    .concatenating(CGAffineTransform(translationX: x, y: y))
            case "matrix" where values.count == 6:
                next = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            default: continue
            }
            result = next.concatenating(result)
        }
        return result
    }
}

/// `#RGB`, `#RRGGBB`, `#RRGGBBAA` and the few names the artwork uses.
func parseColor(_ value: String, opacity: Double = 1) -> Color? {
    var hex = value.trimmingCharacters(in: .whitespaces)
    switch hex.lowercased() {
    case "white": return Color.white.opacity(opacity)
    case "black": return Color.black.opacity(opacity)
    case "none", "transparent": return nil
    default: break
    }
    guard hex.hasPrefix("#") else { return nil }
    hex.removeFirst()
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard let raw = UInt32(hex, radix: 16) else { return nil }
    switch hex.count {
    case 6: return Color(hex: raw, alpha: opacity)
    case 8: return Color(hex: raw >> 8, alpha: Double(raw & 0xFF) / 255 * opacity)
    default: return nil
    }
}
