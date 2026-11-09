import XCTest
@testable import ZeroLogCore

final class MuscleMapTests: XCTestCase {

    func testEveryCataloguePatternMapsToRealMeshGroups() throws {
        let catalog = try Catalog.bundled()
        let mesh = try BodyMesh.bundled()
        let meshGroups = Set(mesh.groups.map(\.name))
        for exercise in catalog.exercises {
            let groups = MuscleMap.groups(for: exercise.pattern)
            XCTAssertFalse(groups.isEmpty,
                           "\(exercise.id)'s pattern \(exercise.pattern) maps to no muscles — the camera would have nowhere to fly")
            for g in groups {
                XCTAssertTrue(meshGroups.contains(g) || g == "body",
                              "pattern \(exercise.pattern) names '\(g)', which the mesh does not ship")
            }
        }
    }

    func testEveryMuscleHasASpokenName() throws {
        let mesh = try BodyMesh.bundled()
        for g in mesh.groups where g.name != "body" {
            XCTAssertNotEqual(MuscleMap.spoken(g.name), g.name,
                              "'\(g.name)' has no human name for chips and VoiceOver")
        }
    }

    func testGroupBoundsSitInsideTheBody() throws {
        // The 'body' group is the head/neck/hands remainder, NOT the whole
        // figure (its own bounds proved that when this test first ran), so
        // the reference frame is the body's full height.
        let mesh = try BodyMesh.bundled()
        let halfHeight = mesh.height / 2
        XCTAssertGreaterThan(halfHeight, 0.7, "body shrank: height \(mesh.height)")
        for g in mesh.groups where g.name != "body" {
            let b = g.bounds
            XCTAssertGreaterThan(b.radius, 0.05, "\(g.name) has almost no extent")
            XCTAssertLessThan(b.radius, halfHeight * 0.8,
                              "\(g.name) spans most of the figure — bounds are wrong")
            XCTAssertLessThan(abs(b.center.y), halfHeight * 1.05,
                              "\(g.name)'s centre floats outside the body vertically")
            XCTAssertLessThan(abs(b.center.x), 0.3,
                              "\(g.name)'s centre floats outside the body horizontally")
        }
    }

    func testPairedMusclesAreCentredOnTheSpine() throws {
        // Chest, abs, traps: left/right pairs joined in one group, so their
        // combined centre should sit near x = 0. A lopsided centre means one
        // side of the pair is missing from the export.
        let mesh = try BodyMesh.bundled()
        for name in ["chest", "abs", "traps", "delts"] {
            guard let g = mesh.groups.first(where: { $0.name == name }) else {
                return XCTFail("mesh lost its \(name)")
            }
            XCTAssertLessThan(abs(g.bounds.center.x), 0.08,
                              "\(name) is off-centre: one side may be missing")
        }
    }
}
