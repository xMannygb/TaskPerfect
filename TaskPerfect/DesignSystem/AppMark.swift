import SwiftUI

/// The Task Perfect mark: a white disc outlined in black, with a green check
/// whose long stroke breaks out past the top-right edge.
///
/// The overflow is the point — a check drawn wholly inside the circle reads as a
/// generic "done" badge, while one that escapes reads as motion, as something
/// completed rather than merely marked. It also means the mark can't be clipped
/// to a circle, so the container reserves room for the overshoot.
public struct AppMark: View {

    /// Diameter of the disc. The view is wider than this to hold the overshoot.
    var size: CGFloat = 26

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(.white)
                .overlay(Circle().strokeBorder(.black, lineWidth: max(1, size * 0.07)))
                .frame(width: size, height: size)

            CheckStroke()
                .stroke(
                    AppMark.green,
                    style: StrokeStyle(lineWidth: size * 0.23, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 1.24, height: size * 1.24)
                .offset(x: size * 0.20, y: -size * 0.17)
        }
        // Room for the stroke that leaves the disc, so nothing gets clipped.
        .frame(width: size * 1.40, height: size * 1.18)
        .accessibilityHidden(true)
    }

    /// Deeper than a mint green but fully saturated — darker in value so it holds
    /// its own against the black outline, while the chroma keeps it vivid rather
    /// than muddy.
    static let green = Color(hex: 0x00A63E)
}

/// Check mark in a unit square. The short leg sits inside the disc; the long leg
/// runs out through the top-right corner.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.13, y: rect.minY + h * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: rect.minY + h * 0.80))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.95, y: rect.minY + h * 0.06))
        return path
    }
}

#Preview {
    HStack(spacing: 20) {
        AppMark(size: 22)
        AppMark(size: 44)
        AppMark(size: 88)
    }
    .padding(40)
    .background(Theme.Palette.canvas)
}
