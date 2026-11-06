import SwiftUI

/// The body figure on the Today screen, in 3D: the figure spins on its
/// vertical axis when you arrive — you see the back, then the front — and
/// settles facing whichever side today's muscles are on. Then those muscles
/// take one slow flex and hold.
///
/// The founder asked for 3D, and the spin IS a 3D rotation (a perspective
/// transform, not a crossfade): a pull day genuinely turns the figure around
/// to show you its back. A sculpted mesh like his reference image is a later
/// step gated on a licensed model; this gets the motion and the meaning now.
///
/// Deliberate choices carried over from the flat version:
/// - Black and white only: red here means "the engine changed something" and
///   green means "done" — decoration must not spend either.
/// - The spin runs ONCE, then stillness. A looping home screen nags.
/// - Reduce Motion: no spin, no flex, straight to the final frame. The whole
///   figure reads to VoiceOver as a sentence, not a shape.
struct BodyFigure: View {
    let sessionType: String
    @State private var angle: Double = 0
    @State private var flexed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// UI tests screenshot whatever instant they land on; a half-turned body
    /// would make every Today frame unreviewable.
    private var skipAnimation: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("-uiTestResetState")
    }

    /// Pull days end facing away (that is where the muscles are); everything
    /// else ends facing you. Both do one full revolution first so the reveal
    /// shows the whole body.
    private var restingAngle: Double { sessionType == "pull" ? 540 : 360 }

    var body: some View {
        SpinningBody(angle: angle, sessionType: sessionType, flexed: flexed)
            .aspectRatio(0.5, contentMode: .fit)
            .onAppear {
                if skipAnimation {
                    angle = restingAngle
                    flexed = true
                } else {
                    withAnimation(.easeInOut(duration: 2.4).delay(0.15)) {
                        angle = restingAngle
                    }
                    // The flex begins as the spin lands, not after a dead gap.
                    withAnimation(.easeOut(duration: 1.0).delay(2.3)) {
                        flexed = true
                    }
                }
            }
            .accessibilityLabel("Today trains \(BodyFigure.spoken(for: sessionType))")
    }

    /// Which muscles light up, given the side currently facing the viewer.
    ///
    /// Both sides carry today's truth so the mid-spin frames are honest too: a
    /// push day passing the rear view lights the triceps, a leg day's rear
    /// view lights hamstrings and glutes.
    static func litRegions(for sessionType: String, back: Bool) -> Set<MuscleRegion> {
        switch sessionType {
        case "pull":
            return back ? [.upperBack, .trapezius, .lowerBack, .backDeltoids, .forearm]
                        : [.biceps, .forearm]
        case "legs":
            return back ? [.hamstring, .gluteal, .calves, .adductor, .leftSoleus, .rightSoleus]
                        : [.quadriceps, .calves, .abductors]
        default: // push
            return back ? [.triceps]
                        : [.chest, .frontDeltoids, .triceps]
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

/// The rotating figure itself.
///
/// Conforms to Animatable so SwiftUI hands it every intermediate angle of the
/// spin: at each frame it decides which side of the body faces the viewer and
/// draws THAT side's muscles. A plain rotation3DEffect on a static image
/// would show the front mirrored through the back of its own head — this is
/// the standard card-flip construction, with anatomy instead of playing cards.
private struct SpinningBody: View, Animatable {
    var angle: Double
    let sessionType: String
    var flexed: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let turn = angle.truncatingRemainder(dividingBy: 360)
        let showingBack = turn > 90 && turn < 270
        BodyCanvas(side: showingBack ? BodyMap.posterior : BodyMap.anterior,
                   lit: BodyFigure.litRegions(for: sessionType, back: showingBack),
                   flexed: flexed)
            // The 3D transform mirrors whatever faces away; pre-mirroring the
            // back view cancels that so left stays left.
            .scaleEffect(x: showingBack ? -1 : 1, y: 1)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                              perspective: 0.55)
    }
}

/// Draws one side of the body. A pure function of its inputs; all motion
/// lives in the views above.
private struct BodyCanvas: View {
    let side: [MuscleRegion: [[CGPoint]]]
    let lit: Set<MuscleRegion>
    let flexed: Bool

    var body: some View {
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
            for (region, polys) in side {
                let p = path(polys)
                if lit.contains(region) {
                    context.fill(p, with: .color(.white.opacity(flexed ? 0.30 : 0.12)))
                    context.stroke(p, with: .color(.white.opacity(flexed ? 0.95 : 0.55)),
                                   lineWidth: 1.4)
                } else {
                    context.stroke(p, with: .color(.white.opacity(0.22)), lineWidth: 0.7)
                }
            }
        }
    }
}
