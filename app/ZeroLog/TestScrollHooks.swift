import SwiftUI

/// Invisible scroll controls for UI tests, present ONLY in test launches.
///
/// Why they exist: on the iOS 27 simulator, XCUITest's synthesized swipes and
/// drags do not scroll SwiftUI lists AT ALL -- a filmed test run shows the
/// list unmoved through 22 seconds of sweeping while every tap lands
/// perfectly. Real fingers scroll fine; the test robot's cannot. Rather than
/// leave everything below the fold untestable, the tests tap these one-point
/// buttons, which drive the SAME scrolling machinery a user's drag does.
/// They are flag-gated and invisible; no user will ever see or hit them.
struct TestScrollHooks: View {
    let proxy: ScrollViewProxy

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetState") {
            VStack(spacing: 0) {
                Button("test-scroll-top") {
                    proxy.scrollTo("list-top", anchor: .top)
                }
                Button("test-scroll-bottom") {
                    proxy.scrollTo("list-bottom", anchor: .bottom)
                }
            }
            .font(.system(size: 1))
            .tint(.clear)
            // Big enough that a synthesized touch cannot miss; still pure
            // black on the black page, and flag-gated out of real builds'
            // launches anyway.
            .frame(width: 20, height: 20)
            .background(Color.black)
            .opacity(0.9)
        }
    }
}

extension View {
    /// Marks the ends of a List so TestScrollHooks has anchors to fly to.
    @ViewBuilder
    func testScrollAnchor(_ id: String) -> some View {
        self.id(id)
    }
}
