import SwiftUI

/// A celebratory overlay of balloons that float up the screen, shown once when a
/// runner meets their goal. Purely decorative — never blocks touches.
struct CelebrationView: View {
    /// Number of balloons to launch.
    private let balloons: [Balloon]

    init(count: Int = 16) {
        // Precompute each balloon's properties once so they stay stable across
        // re-renders (avoids re-randomising every layout pass).
        let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
        balloons = (0..<count).map { i in
            Balloon(
                color: palette[i % palette.count],
                startXFraction: Double(i) / Double(max(1, count - 1)),
                drift: Double.random(in: -40...40),
                size: CGFloat.random(in: 36...60),
                delay: Double.random(in: 0...0.8),
                duration: Double.random(in: 2.6...4.2),
                sway: Double.random(in: -10...10)
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(balloons) { balloon in
                    BalloonView(balloon: balloon, screen: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Immutable description of a single balloon's flight.
private struct Balloon: Identifiable {
    let id = UUID()
    let color: Color
    let startXFraction: Double   // 0...1 across the screen width
    let drift: Double            // horizontal drift in points
    let size: CGFloat
    let delay: Double
    let duration: Double
    let sway: Double             // rotation in degrees at the end
}

private struct BalloonView: View {
    let balloon: Balloon
    let screen: CGSize
    @State private var rise = false

    var body: some View {
        let startX = balloon.startXFraction * screen.width
        VStack(spacing: 0) {
            Ellipse()
                .fill(balloon.color.gradient)
                .frame(width: balloon.size, height: balloon.size * 1.22)
                .overlay(
                    Ellipse()
                        .fill(.white.opacity(0.3))
                        .frame(width: balloon.size * 0.22, height: balloon.size * 0.38)
                        .offset(x: -balloon.size * 0.18, y: -balloon.size * 0.22)
                )
                .shadow(color: balloon.color.opacity(0.4), radius: 4, y: 2)
            // Knot + string
            Triangle()
                .fill(balloon.color)
                .frame(width: 8, height: 6)
            Rectangle()
                .fill(balloon.color.opacity(0.45))
                .frame(width: 1.5, height: balloon.size * 0.9)
        }
        .rotationEffect(.degrees(rise ? balloon.sway : 0))
        .position(
            x: startX + (rise ? balloon.drift : 0),
            y: rise ? -balloon.size * 2 : screen.height + balloon.size * 2
        )
        .opacity(rise ? 0 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: balloon.duration).delay(balloon.delay)) {
                rise = true
            }
        }
    }
}

/// A small downward-pointing triangle used for the balloon knot.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    ZStack {
        Color.black
        CelebrationView()
    }
}
