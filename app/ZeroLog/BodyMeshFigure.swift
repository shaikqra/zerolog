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

    var body: some View {
        BodySceneView(sessionType: sessionType)
            .aspectRatio(0.62, contentMode: .fit)
            // The CI video caught the figure painting over the plan list:
            // an SCNView does not respect SwiftUI bounds on its own.
            .clipped()
            // The label carries a diagnostic suffix because SceneKit can fail
            // to BLACK, silently, and a screenshot of black-on-black proves
            // nothing. The UI tests assert on this label, so "the model did
            // not load" is a named failure instead of an invisible one.
            .accessibilityLabel("Today trains \(BodyFigure.spoken(for: sessionType)). \(BodyScene.diagnostic)")
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

private struct BodySceneView: UIViewRepresentable {
    let sessionType: String
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
        view.addGestureRecognizer(pan)
        context.coordinator.view = view
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
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(sessionType: sessionType) }

    /// Drag turns the body about its vertical axis. Just that one axis:
    /// free-orbiting a camera ends with the figure upside-down and nobody
    /// knowing which way is forward.
    final class Coordinator: NSObject {
        var sessionType: String
        weak var view: SCNView?
        init(sessionType: String) { self.sessionType = sessionType }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let view,
                  let body = view.scene?.rootNode.childNode(withName: "spinPivot",
                                                            recursively: false) else { return }
            let dx = Float(g.translation(in: view).x)
            g.setTranslation(.zero, in: view)
            body.removeAllActions()
            body.eulerAngles.y += dx * 0.012
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
        case "legs": return ["quads", "hams", "glutes", "adds", "calves"]
        default:     return ["chest", "delts", "triceps"]
        }
    }

    /// The mesh, loaded exactly once. `static let` makes the first ACCESS do
    /// the work, so the accessibility label and the scene builder read the
    /// same result in any order -- the previous mutable diagnostic was set
    /// during build and read before it, reporting "not built yet" about a
    /// body that rendered fine.
    static let loaded: Result<BodyMesh, Error> = Result { try BodyMesh.bundled() }

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

        // Camera: distance derived from the (now known) height and FOV.
        let camera = SCNCamera()
        camera.projectionDirection = .vertical
        camera.fieldOfView = 18
        camera.zNear = 0.1; camera.zFar = 30
        let fovRadians = 18.0 * .pi / 180.0
        let distance = Double(1.6) * 1.12 / (2 * tan(fovRadians / 2))
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.position = SCNVector3(0, 0, Float(distance))
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
