import SwiftUI
import SceneKit
import ZeroLogCore

/// The live 3D body on the Today screen.
///
/// A real mesh (60k triangles, derived from Z-Anatomy — attribution in
/// Settings and docs/design/body3d/), rendered by SceneKit: dark sculpted
/// anatomy on true black, the muscles today trains lit. It makes one slow
/// revolution when the screen appears, settles facing today's side, and from
/// then on A FINGER CAN TURN IT — drag left or right to look around the body.
///
/// Rules carried over from every earlier version of this figure:
/// - Black and white only; red means "engine changed something", green means
///   "done", and decoration may spend neither.
/// - One revolution, then stillness. A looping home screen nags.
/// - Reduce Motion: no spin, straight to the resting pose.
struct BodyMeshFigure: View {
    let sessionType: String
    /// Mesh group id to zoom to and flex, nil = whole body. Owned by the
    /// Today screen: tapping a muscle chip flies the camera here.
    var focus: String? = nil
    @State private var drawReport = "rendering"

    var body: some View {
        BodySceneView(sessionType: sessionType, focus: focus, drawReport: $drawReport)
            .aspectRatio(0.62, contentMode: .fit)
            // The CI video caught the figure painting over the plan list:
            // an SCNView does not respect SwiftUI bounds on its own.
            .clipped()
            // The label carries the loader's verdict AND the renderer's. The
            // view snapshots itself after the first frame and reports "drawn"
            // or "BLANK": SceneKit fails to black, black-on-black photographs
            // as nothing, and the camera pointed at CI has now been wrong
            // twice -- so whether pixels landed is asserted by a test, not
            // judged from film.
            .accessibilityLabel("Today trains \(BodyFigure.spoken(for: sessionType)). \(BodyScene.diagnostic), \(drawReport)")
            // No .allowsDirectInteraction: that trait hands RAW touches to
            // the SceneKit view, bypassing the normal routing the gesture
            // delegate participates in -- with it set, synthesized swipes
            // died in the 3D view and the page would not scroll (two element
            // trees in a row showed the list unmoved after nine swipes).
            // VoiceOver's experience IS the spoken sentence; rotation is
            // decoration, not information.
    }
}

private struct BodySceneView: UIViewRepresentable {
    let sessionType: String
    var focus: String?
    @Binding var drawReport: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var skipAnimation: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("-uiTestResetState")
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        // On-demand rendering, and this is load-bearing in BOTH directions:
        // SceneKit DOES draw static scenes on demand (the early CI frames
        // prove it -- the mis-imported legs were visible), and continuous
        // rendering BREAKS XCUITest, which waits for an idle app before every
        // tap -- a view redrawing 30 times a second is never idle, so every
        // test interaction crawled and launches timed out. It also burns the
        // phone's battery on a screen whose whole job is to sit still.
        view.rendersContinuously = false
        view.scene = BodyScene.build(sessionType: sessionType)

        if let body = view.scene?.rootNode.childNode(withName: "spinPivot", recursively: false) {
            let resting = BodyScene.restingAngle(for: sessionType)
            if skipAnimation {
                body.eulerAngles.y = resting
            } else {
                let spin = SCNAction.rotateBy(x: 0, y: CGFloat(2 * Float.pi) + CGFloat(resting),
                                              z: 0, duration: 2.6)
                spin.timingMode = .easeInEaseOut
                body.runAction(spin)
            }
        }

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.pan(_:)))
        // The body only claims HORIZONTAL drags. Without this the recognizer
        // swallowed vertical swipes too, and with the body covering half the
        // Today screen the page simply could not be scrolled from where a
        // thumb naturally lands -- a committed element tree showed the list
        // unmoved after nine swipes. Turning is left-right; up-down belongs
        // to the page.
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.view = view

        // Self-audit: measure the first frame instead of trusting it.
        let report = $drawReport
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak view] in
            guard let view else { return }
            let image = view.snapshot()
            report.wrappedValue = Self.meanLuminance(of: image) > 0.015 ? "drawn" : "BLANK"
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // Session type changes only when a new plan is generated; rebuilding
        // the materials is cheaper than diffing them.
        if context.coordinator.sessionType != sessionType {
            context.coordinator.sessionType = sessionType
            view.scene = BodyScene.build(sessionType: sessionType)
            view.scene?.rootNode.childNode(withName: "spinPivot", recursively: false)?
                .eulerAngles.y = BodyScene.restingAngle(for: sessionType)
            context.coordinator.focusedGroup = nil
        }
        if context.coordinator.focusedGroup != focus {
            context.coordinator.focusedGroup = focus
            context.coordinator.focus(on: focus, animated: !skipAnimation)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(sessionType: sessionType) }

    /// Average brightness of the rendered frame, 0...1. The body occupies
    /// most of the view; anything above a sliver of grey means real pixels.
    static func meanLuminance(of image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let w = 32, h = 48
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let total = pixels.reduce(0) { $0 + Int($1) }
        return Double(total) / Double(w * h * 255)
    }

    /// Drag turns the body about its vertical axis. Just that one axis:
    /// free-orbiting a camera ends with the figure upside-down and nobody
    /// knowing which way is forward.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var sessionType: String
        var focusedGroup: String?
        weak var view: SCNView?
        init(sessionType: String) { self.sessionType = sessionType }

        /// Horizontal drags turn the body; vertical drags scroll the page.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let view, focusedGroup == nil,   // zoomed in, the camera owns the view
                  let body = view.scene?.rootNode.childNode(withName: "spinPivot",
                                                            recursively: false) else { return }
            let dx = Float(g.translation(in: view).x)
            g.setTranslation(.zero, in: view)
            body.removeAllActions()
            body.eulerAngles.y += dx * 0.012
        }

        /// These live on the body's back, so the figure turns around before
        /// the camera closes in — zooming to lats while facing the chest
        /// would frame the right place on the wrong side.
        private static let backMuscles: Set<String> =
            ["lats", "traps", "hams", "glutes", "calves", "triceps"]

        /// Fly the camera to one muscle and flex it, or home to the whole body.
        ///
        /// Driven by SCNActions, not SCNTransaction, deliberately: the opening
        /// spin is an action and it renders silk-smooth under on-demand
        /// drawing WITHOUT making XCUITest consider the app busy -- the launch
        /// tests tap through it. The camera flight rides the proven mechanism:
        /// position and turn as eased actions, the orthographic zoom as a
        /// custom action interpolating with the same smoothstep curve.
        func focus(on group: String?, animated: Bool) {
            guard let view, let scene = view.scene,
                  let pivot = scene.rootNode.childNode(withName: "spinPivot", recursively: false),
                  let bodyRoot = pivot.childNode(withName: "bodyRoot", recursively: false),
                  let camNode = scene.rootNode.childNodes.first(where: { $0.camera != nil }),
                  let camera = camNode.camera else { return }

            pivot.removeAllActions()
            camNode.removeAllActions()

            let target: SCNVector3
            let endScale: Double
            let endAngle: Float
            var flexNode: SCNNode?

            if let group,
               let node = bodyRoot.childNode(withName: group, recursively: false),
               let bounds = BodyScene.bounds(of: group) {
                // The mesh was normalised at build time (scaled to 1.6 tall,
                // centred); the camera target needs the same transform.
                let s = bodyRoot.scale.x
                let showBack = Self.backMuscles.contains(group)
                let localX = bounds.center.x * s + bodyRoot.position.x
                let worldY = bounds.center.y * s + bodyRoot.position.y
                endAngle = showBack ? .pi : 0
                // A pi turn about y negates x for everything the pivot holds.
                target = SCNVector3(showBack ? -localX : localX, worldY, 6)
                endScale = Double(max(bounds.radius * s * 1.5, 0.22))
                flexNode = node
            } else {
                endAngle = BodyScene.restingAngle(for: sessionType)
                target = SCNVector3(0, 0, 6)
                endScale = 0.9
            }

            guard animated else {
                pivot.eulerAngles.y = endAngle
                camNode.position = target
                camera.orthographicScale = endScale
                return
            }

            // Zooming out is quicker than zooming in: leaving should feel
            // lighter than arriving.
            let duration = flexNode == nil ? 0.65 : 0.95

            let turn = SCNAction.rotateTo(x: 0, y: CGFloat(endAngle), z: 0,
                                          duration: duration, usesShortestUnitArc: true)
            turn.timingMode = .easeInEaseOut
            pivot.runAction(turn)

            let move = SCNAction.move(to: target, duration: duration)
            move.timingMode = .easeInEaseOut
            let startScale = camera.orthographicScale
            let zoom = SCNAction.customAction(duration: duration) { _, elapsed in
                let p = Double(elapsed) / duration
                let eased = p * p * (3 - 2 * p)   // smoothstep, same feel as the move
                camera.orthographicScale = startScale + (endScale - startScale) * eased
            }
            camNode.runAction(.group([move, zoom]))

            if let flexNode { flex(flexNode) }
        }

        /// The flex: the muscle throbs brighter twice under the skin. The
        /// mesh is a statue, not a puppet — no joints to bend — so the flex
        /// is light, not movement, and Reduce Motion skips it entirely.
        private func flex(_ node: SCNNode) {
            guard let material = node.geometry?.firstMaterial else { return }
            let up = SCNAction.customAction(duration: 0.45) { _, t in
                material.emission.intensity = 1 + 2.4 * (t / 0.45)
            }
            let down = SCNAction.customAction(duration: 0.45) { _, t in
                material.emission.intensity = 3.4 - 2.4 * (t / 0.45)
            }
            // Starts as the camera flight ends: arrive, THEN flex.
            node.runAction(.sequence([.wait(duration: 1.0), up, down, up, down]))
        }
    }
}

/// Builds the scene: body at origin, camera, three lights, materials by group.
enum BodyScene {
    /// Pull days rest facing away — that is where the muscles are.
    static func restingAngle(for sessionType: String) -> Float {
        sessionType == "pull" ? .pi : 0
    }

    static func litGroups(for sessionType: String) -> Set<String> {
        switch sessionType {
        case "pull": return ["traps", "lats", "biceps", "forearm"]
        case "legs": return ["quads", "hams", "glutes", "calves"]
        default:     return ["chest", "delts", "triceps"]
        }
    }

    /// The mesh, loaded exactly once. `static let` makes the first ACCESS do
    /// the work, so the accessibility label and the scene builder read the
    /// same result in any order -- the previous mutable diagnostic was set
    /// during build and read before it, reporting "not built yet" about a
    /// body that rendered fine.
    static let loaded: Result<BodyMesh, Error> = Result { try BodyMesh.bundled() }

    /// Per-group camera targets, from the Core mesh the tests proved.
    static func bounds(of group: String) -> (center: (x: Float, y: Float, z: Float), radius: Float)? {
        guard case .success(let mesh) = loaded,
              let g = mesh.groups.first(where: { $0.name == group }) else { return nil }
        return g.bounds
    }

    /// What actually loaded, for the accessibility label and the UI tests.
    static var diagnostic: String {
        switch loaded {
        case .success(let mesh):
            return "3D body: \(mesh.groups.count) groups, \(mesh.totalTriangles) triangles"
        case .failure(let error):
            return "3D body failed: \(error)"
        }
    }

    static func build(sessionType: String) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        let bodyRoot = SCNNode()
        bodyRoot.name = "bodyRoot"

        // No ModelIO. Two CI round-trips showed its OBJ import shipping a
        // floating pair of legs with no way to ask why from this side. The
        // parser lives in ZeroLogCore and is tested ON LINUX against this
        // exact file: 13 groups, every index valid, life-sized. What renders
        // here is what those tests proved.
        switch loaded {
        case .failure:
            break   // the label carries the error; the scene stays empty
        case .success(let mesh):
            let lit = litGroups(for: sessionType)
            for group in mesh.groups {
                let vertexData = group.vertices.withUnsafeBufferPointer { Data(buffer: $0) }
                let normalData = group.normals.withUnsafeBufferPointer { Data(buffer: $0) }
                let indexData = group.indices.withUnsafeBufferPointer { Data(buffer: $0) }
                let vertices = SCNGeometrySource(data: vertexData, semantic: .vertex,
                                                 vectorCount: group.vertexCount,
                                                 usesFloatComponents: true,
                                                 componentsPerVector: 3,
                                                 bytesPerComponent: MemoryLayout<Float>.size,
                                                 dataOffset: 0,
                                                 dataStride: MemoryLayout<Float>.size * 3)
                let normals = SCNGeometrySource(data: normalData, semantic: .normal,
                                                vectorCount: group.vertexCount,
                                                usesFloatComponents: true,
                                                componentsPerVector: 3,
                                                bytesPerComponent: MemoryLayout<Float>.size,
                                                dataOffset: 0,
                                                dataStride: MemoryLayout<Float>.size * 3)
                let element = SCNGeometryElement(data: indexData,
                                                 primitiveType: .triangles,
                                                 primitiveCount: group.triangleCount,
                                                 bytesPerIndex: MemoryLayout<UInt32>.size)
                let geometry = SCNGeometry(sources: [vertices, normals], elements: [element])
                geometry.materials = [lit.contains(group.name) ? litMaterial : baseMaterial]
                let node = SCNNode(geometry: geometry)
                node.name = group.name
                bodyRoot.addChildNode(node)
            }
        }
        scene.rootNode.addChildNode(bodyRoot)

        // Normalise: whatever scale and offset the file arrived with, the body
        // on screen is HEIGHT units tall and centred on the origin. This makes
        // the camera maths true by construction instead of true by luck --
        // the first CI screenshot showed a centimetre-tall figure, and every
        // guess at why costs a twenty-minute Mac round trip.
        let (bbMin, bbMax) = bodyRoot.boundingBox
        let rawHeight = bbMax.y - bbMin.y
        if rawHeight > 0 {
            let targetHeight: Float = 1.6
            let s = targetHeight / rawHeight
            bodyRoot.scale = SCNVector3(s, s, s)
            bodyRoot.position = SCNVector3(-(bbMin.x + bbMax.x) / 2 * s,
                                           -(bbMin.y + bbMax.y) / 2 * s,
                                           -(bbMin.z + bbMax.z) / 2 * s)
        }
        // The spin must happen about the body's own axis, so the pivot moves
        // to the body rather than the body moving to the pivot.
        let spinPivot = SCNNode()
        spinPivot.name = "spinPivot"
        scene.rootNode.addChildNode(spinPivot)
        bodyRoot.removeFromParentNode()
        spinPivot.addChildNode(bodyRoot)

        // ORTHOGRAPHIC camera, and that is the fix for a hero that rendered
        // on one commit and came up black on the next: with perspective, what
        // fits depends on distance, field of view, projection direction and
        // the exact pixel size SwiftUI hands the view -- four quantities that
        // must all agree, and whose disagreement looks like an empty box.
        // Orthographic has ONE number: visible height = 2 x orthographicScale,
        // true at any view size. Body is 1.6 tall; 0.9 shows it with margin.
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 0.9
        camera.zNear = 0.1; camera.zFar = 30
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(camNode)

        // The preview renders' three-light rig: two rims for silhouette, one
        // soft key so the dark muscle still reads as form.
        func light(_ type: SCNLight.LightType, _ intensity: CGFloat,
                   _ position: SCNVector3) {
            let l = SCNLight(); l.type = type; l.intensity = intensity
            let n = SCNNode(); n.light = l; n.position = position
            n.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(n)
        }
        light(.omni, 350, SCNVector3(-2.2, 0.5, -0.4))
        light(.omni, 350, SCNVector3(2.2, 0.5, -0.4))
        light(.omni, 500, SCNVector3(0, 0.9, 4.5))
        let ambient = SCNLight(); ambient.type = .ambient; ambient.intensity = 60
        let ambientNode = SCNNode(); ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        return scene
    }

    /// Near-black metal: the unlit body. Matches the committed previews.
    private static var baseMaterial: SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 0.07, alpha: 1)
        m.metalness.contents = 0.65
        m.roughness.contents = 0.42
        return m
    }

    /// Today's muscles: pale and faintly emissive, bright against the black
    /// but still showing their shape. White, never red or green — those
    /// colours carry meanings this figure must not spend.
    private static var litMaterial: SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1)
        m.metalness.contents = 0.1
        m.roughness.contents = 0.5
        m.emission.contents = UIColor(red: 0.20, green: 0.21, blue: 0.23, alpha: 1)
        return m
    }
}
