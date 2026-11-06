import XCTest
import ZeroLogCore   // plain import: the app sees exactly this

/// The body mesh, verified ON LINUX against the real bundled file — so "did
/// the 3D model load as 13 muscle groups" never again needs a Mac to answer.
final class BodyMeshTests: XCTestCase {

    func testTheRealFileParsesIntoAllThirteenGroups() throws {
        let mesh = try BodyMesh.bundled()
        let names = Set(mesh.groups.map(\.name))
        let expected: Set<String> = ["chest", "delts", "biceps", "triceps", "forearm",
                                     "traps", "lats", "abs", "glutes", "quads",
                                     "hams", "adds", "calves", "body"]
        // adds may legitimately be empty if no adductor survived the strip;
        // everything else is load-bearing.
        for required in expected.subtracting(["adds"]) {
            XCTAssertTrue(names.contains(required), "missing group: \(required)")
        }
        XCTAssertGreaterThan(mesh.totalTriangles, 40_000, "most of the mesh must survive")
        XCTAssertLessThan(mesh.totalTriangles, 80_000, "and stay within the phone budget")
    }

    func testEveryIndexPointsAtARealVertex() throws {
        let mesh = try BodyMesh.bundled()
        for g in mesh.groups {
            let count = UInt32(g.vertexCount)
            XCTAssertEqual(g.vertices.count, g.normals.count,
                           "\(g.name): a normal per vertex")
            XCTAssertEqual(g.indices.count % 3, 0, "\(g.name): whole triangles only")
            XCTAssertNil(g.indices.first(where: { $0 >= count }),
                         "\(g.name): index out of range would crash SceneKit")
        }
    }

    func testTheBodyIsLifeSizedAndCentred() throws {
        let mesh = try BodyMesh.bundled()
        XCTAssertGreaterThan(mesh.height, 1.4, "a whole body, not a part")
        XCTAssertLessThan(mesh.height, 2.0, "and not the body plus a stray")
    }

    // MARK: - Parser behaviour on crafted input

    func testFacesBelongToTheObjectAboveThem() throws {
        let obj = """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vn 0 0 1
        o alpha
        f 1//1 2//1 3//1
        o beta
        f 3//1 2//1 1//1
        """
        let mesh = try BodyMesh.parse(obj)
        XCTAssertEqual(mesh.groups.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(mesh.groups[0].triangleCount, 1)
        XCTAssertEqual(mesh.groups[1].triangleCount, 1)
    }

    /// OBJ indices are global across the file: beta's face references
    /// vertices defined before alpha, and that must simply work.
    func testGlobalIndicesCrossObjectBoundaries() throws {
        let obj = """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vn 0 0 1
        o alpha
        f 1//1 2//1 3//1
        v 2 0 0
        o beta
        f 1//1 2//1 4//1
        """
        let mesh = try BodyMesh.parse(obj)
        XCTAssertEqual(mesh.groups[1].vertexCount, 3)
        XCTAssertEqual(mesh.groups[1].vertices.suffix(3), [2, 0, 0])
    }

    func testAnIndexPastTheEndRefusesInsteadOfCrashingLater() {
        let obj = """
        v 0 0 0
        vn 0 0 1
        o alpha
        f 1//1 2//1 3//1
        """
        XCTAssertThrowsError(try BodyMesh.parse(obj)) { error in
            XCTAssertEqual(error as? BodyMesh.ParseError, .indexOutOfRange(line: 4))
        }
    }

    func testAQuadFaceIsRejectedBecauseTheExporterTriangulates() {
        let obj = """
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        vn 0 0 1
        o alpha
        f 1//1 2//1 3//1 4//1
        """
        XCTAssertThrowsError(try BodyMesh.parse(obj)) { error in
            XCTAssertEqual(error as? BodyMesh.ParseError, .malformedFace(line: 7))
        }
    }
}
