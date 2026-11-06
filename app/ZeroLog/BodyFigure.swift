import SwiftUI

/// The body figure on the Today screen: an outlined figure, drawn in white on
/// true black, with the muscles today trains lit up and taking one slow
/// breath when the screen appears.
///
/// The founder's idea, and a good one: it answers "what is today?" with zero
/// reading. Push day lights the chest, delts and triceps from the front; pull
/// day shows the back; leg day lights the legs.
///
/// Two deliberate choices:
/// - Black and white only. Red in this app is reserved for rows the engine
///   changed, and green for done. Spending either on decoration would dilute
///   a meaning we rely on, so the lit muscles are simply brighter white.
/// - One pulse, not a loop. A looping animation on the home screen is a
///   nagging one. The figure flexes once when you arrive, then holds. Under
///   Reduce Motion it does not move at all.
struct BodyFigure: View {
    let sessionType: String
    @State private var flexed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let target = BodyFigure.regions(for: sessionType)
        Canvas { context, size in
            // The data is normalised to a 1 x 2 space; fit by height, centre by width.
            let scale = size.height / 2
            let xOffset = (size.width - scale) / 2
            func path(_ polys: [[CGPoint]]) -> Path {
                var p = Path()
                for poly in polys {
                    guard let first = poly.first else { continue }
                    p.move(to: CGPoint(x: first.x * scale + xOffset, y: first.y * scale))
                    for pt in poly.dropFirst() {
                        p.addLine(to: CGPoint(x: pt.x * scale + xOffset, y: pt.y * scale))
                    }
                    p.closeSubpath()
                }
                return p
            }
            for (region, polys) in target.side {
                let p = path(polys)
                if target.regions.contains(region) {
                    context.fill(p, with: .color(.white.opacity(flexed ? 0.30 : 0.12)))
                    context.stroke(p, with: .color(.white.opacity(flexed ? 0.95 : 0.55)),
                                   lineWidth: 1.4)
                } else {
                    context.stroke(p, with: .color(.white.opacity(0.22)), lineWidth: 0.7)
                }
            }
        }
        .aspectRatio(0.5, contentMode: .fit)
        .onAppear {
            if reduceMotion {
                flexed = true
            } else {
                // One slow breath in. Ease-out so it lands softly and stays.
                withAnimation(.easeOut(duration: 1.2).delay(0.2)) { flexed = true }
            }
        }
        .accessibilityLabel("Today trains \(BodyFigure.spoken(for: sessionType))")
    }

    /// Which muscles light up, and which side of the body shows them.
    ///
    /// The side follows the primary movers: a pull day from the front would
    /// light nothing you can see.
    static func regions(for sessionType: String)
        -> (side: [MuscleRegion: [[CGPoint]]], regions: Set<MuscleRegion>) {
        switch sessionType {
        case "pull":
            return (BodyMap.posterior,
                    [.upperBack, .trapezius, .lowerBack, .backDeltoids, .biceps, .forearm])
        case "legs":
            return (BodyMap.anterior,
                    [.quadriceps, .calves, .abductors])
        default: // push
            return (BodyMap.anterior,
                    [.chest, .frontDeltoids, .triceps])
        }
    }

    static func spoken(for sessionType: String) -> String {
        switch sessionType {
        case "pull": return "your back and biceps"
        case "legs": return "your legs"
        default: return "your chest, shoulders and triceps"
        }
    }
}
