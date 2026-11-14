import SwiftUI

// The app's own icons. They are drawn as shapes instead of images, so the hover state can
// morph from the passive drawing instead of crossfading. Sources: design/icons/*.svg.
//
// Every icon is drawn in the same 15 × 17 box. Coordinates below are in that box.
// The drawing is scaled by `scale`, while the line stays 1 pt at every size.

enum AppIconMetrics {
    /// The box the icons are drawn in.
    static let designSize = CGSize(width: 15, height: 17)
    /// Change this to make all icons bigger or smaller. 1 = drawn size (pixel exact).
    static let scale: CGFloat = 1.3
    static let size = CGSize(width: designSize.width * scale, height: designSize.height * scale)
    static let lineWidth: CGFloat = 1

    /// How far below the text baseline the box sits, so that the middle of the box lines up
    /// with the middle of Averia's cap height (0.677 em). Rounded to half points.
    static func baselineInset(textSize: CGFloat) -> CGFloat {
        let inset = size.height / 2 - 0.677 * textSize / 2
        return (inset * 2).rounded() / 2
    }
}

enum AppIconKind {
    case folder
    case importArrow
    /// Points right when collapsed and turns down when expanded.
    case chevron
}

struct AppIcon: View {
    let kind: AppIconKind
    var hovered = false
    var expanded = false
    /// Size of the text the icon sits next to. Used for baseline alignment.
    var textSize: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        icon
            .frame(width: AppIconMetrics.size.width, height: AppIconMetrics.size.height)
            .alignmentGuide(.firstTextBaseline) { d in
                d[.bottom] - AppIconMetrics.baselineInset(textSize: textSize)
            }
            .animation(hoverAnimation, value: hovered)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: expanded)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var icon: some View {
        let h: CGFloat = hovered ? 1 : 0
        switch kind {
        case .folder:
            ZStack {
                FolderOutline()
                    .stroke(lineWidth: AppIconMetrics.lineWidth * 2)
                    .clipShape(OutsideOf(FolderOutline()), style: FillStyle(eoFill: true))   // outside line, like the SVG's mask
                FolderBar(progress: h)
                    .stroke(style: StrokeStyle(lineWidth: AppIconMetrics.lineWidth, lineCap: .round))
            }
        case .importArrow:
            ImportArrow(progress: h)
                .stroke(style: StrokeStyle(lineWidth: AppIconMetrics.lineWidth, lineCap: .round, lineJoin: .miter))
        case .chevron:
            Chevron(hover: h, turn: expanded ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: AppIconMetrics.lineWidth, lineCap: .round, lineJoin: .miter))
        }
    }

    /// A small spring on the way in, a calm ease on the way out.
    private var hoverAnimation: Animation? {
        if reduceMotion { return nil }
        return hovered ? .spring(response: 0.25, dampingFraction: 0.6) : .easeOut(duration: 0.2)
    }
}

// MARK: - Shapes

/// Maps the 15 × 17 design box onto the shape's rect.
private func iconTransform(_ rect: CGRect) -> CGAffineTransform {
    CGAffineTransform(translationX: rect.minX, y: rect.minY)
        .scaledBy(x: rect.width / AppIconMetrics.designSize.width, y: rect.height / AppIconMetrics.designSize.height)
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

private struct FolderOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 14, y: 12))
        p.addCurve(to: CGPoint(x: 12, y: 14), control1: CGPoint(x: 14, y: 13.1046), control2: CGPoint(x: 13.1046, y: 14))
        p.addLine(to: CGPoint(x: 3, y: 14))
        p.addCurve(to: CGPoint(x: 1, y: 12), control1: CGPoint(x: 1.89543, y: 14), control2: CGPoint(x: 1, y: 13.1046))
        p.addLine(to: CGPoint(x: 1, y: 5))
        p.addCurve(to: CGPoint(x: 2, y: 4), control1: CGPoint(x: 1, y: 4.44772), control2: CGPoint(x: 1.44772, y: 4))
        p.addLine(to: CGPoint(x: 6.38184, y: 4))
        p.addCurve(to: CGPoint(x: 7.27637, y: 4.55273), control1: CGPoint(x: 6.76059, y: 4), control2: CGPoint(x: 7.10697, y: 4.21398))
        p.addLine(to: CGPoint(x: 7.44727, y: 4.89453))
        p.addCurve(to: CGPoint(x: 9.23633, y: 6), control1: CGPoint(x: 7.78607, y: 5.57204), control2: CGPoint(x: 8.47882, y: 6))
        p.addLine(to: CGPoint(x: 13, y: 6))
        p.addCurve(to: CGPoint(x: 14, y: 7), control1: CGPoint(x: 13.5523, y: 6), control2: CGPoint(x: 14, y: 6.44772))
        p.closeSubpath()
        return p.applying(iconTransform(rect))
    }
}

/// Everything in the rect except the shape. Used to keep only the outer half of a stroke.
private struct OutsideOf<S: Shape>: Shape {
    let shape: S
    init(_ shape: S) { self.shape = shape }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -AppIconMetrics.lineWidth, dy: -AppIconMetrics.lineWidth))
        p.addPath(shape.path(in: rect))
        return p
    }
}

/// The horizontal line in the folder. Grows to the right on hover: 7 → 15.
/// Drawn as a stroked line (not a filled bar) so it stays 1 pt thick when scaled.
private struct FolderBar: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.5, y: 8.5))
        p.addLine(to: CGPoint(x: lerp(6.5, 14.5, progress), y: 8.5))
        return p.applying(iconTransform(rect))
    }
}

/// Shaft, arrowhead and tray. On hover the angled line at the bottom flattens and moves down.
private struct ImportArrow: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 7.5, y: 4.5))
        p.addLine(to: CGPoint(x: 7.5, y: 9.5))

        p.move(to: CGPoint(x: 4, y: 8))
        p.addLine(to: CGPoint(x: 7.5, y: 10))
        p.addLine(to: CGPoint(x: 11, y: 8))

        let side = lerp(11, 14, progress), middle = lerp(13, 14, progress)
        p.move(to: CGPoint(x: 4, y: side))
        p.addLine(to: CGPoint(x: 7.5, y: middle))
        p.addLine(to: CGPoint(x: 11, y: side))
        return p.applying(iconTransform(rect))
    }
}

/// Two chevrons that lie on top of each other when passive and slide apart on hover.
/// Drawn pointing right and turned a quarter for the expanded (down) state, which gives
/// exactly the down drawings; the passive down chevron also moves 0.5 pt to sit on the pixel grid.
private struct Chevron: Shape {
    var hover: CGFloat
    var turn: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(hover, turn) }
        set { hover = newValue.first; turn = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for dx in [lerp(0, -1.5, hover), lerp(0, 2.5, hover)] {
            p.move(to: CGPoint(x: 6.5 + dx, y: 12))
            p.addLine(to: CGPoint(x: 8.5 + dx, y: 8.5))
            p.addLine(to: CGPoint(x: 6.5 + dx, y: 5))
        }
        // One path for both chevrons: where they overlap the line is drawn once, not twice as bright.
        let center = CGPoint(x: 7.5, y: 8.5)
        let turnAround = CGAffineTransform(translationX: center.x, y: center.y + turn * (1 - hover) * 0.5)
            .rotated(by: turn * .pi / 2)
            .translatedBy(x: -center.x, y: -center.y)
        return p.applying(turnAround).applying(iconTransform(rect))
    }
}
