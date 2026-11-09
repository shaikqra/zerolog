import Foundation

/// The 3D body model, parsed from the bundled OBJ file.
///
/// Hand-rolled on purpose. Apple's ModelIO was importing this file as
/// something other than its 13 named objects — two CI round-trips showed a
/// floating pair of legs and no way to see why from a Linux box. An OBJ is a
/// text format simple enough to parse exactly, and a parser that lives in
/// this package is TESTED ON LINUX against the real file, so "did the mesh
/// load correctly" stops being a question only a Mac can answer.
public struct BodyMesh: Sendable {
    /// One muscle group: everything the app needs to build a geometry.
    public struct Group: Sendable {
        public let name: String
        /// x,y,z triples, flat.
        public let vertices: [Float]
        /// Matching normals, same layout.
        public let normals: [Float]
        /// Triangle indices into this group's OWN vertex list.
        public let indices: [UInt32]

        public var vertexCount: Int { vertices.count / 3 }
        public var triangleCount: Int { indices.count / 3 }

        /// Where this muscle sits in space: centre of its bounding box and
        /// the radius that encloses it. This is what the camera flies to
        /// when the user asks to see one muscle, so it is computed in Core
        /// where a Linux test can assert every group lands INSIDE the body
        /// instead of discovering a camera pointed at empty air on a Mac.
        public var bounds: (center: (x: Float, y: Float, z: Float), radius: Float) {
            var lo = (Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
            var hi = (-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
            var i = 0
            while i + 2 < vertices.count {
                lo.0 = min(lo.0, vertices[i]);   hi.0 = max(hi.0, vertices[i])
                lo.1 = min(lo.1, vertices[i+1]); hi.1 = max(hi.1, vertices[i+1])
                lo.2 = min(lo.2, vertices[i+2]); hi.2 = max(hi.2, vertices[i+2])
                i += 3
            }
            guard !vertices.isEmpty else { return ((0, 0, 0), 0) }
            let c = ((lo.0 + hi.0) / 2, (lo.1 + hi.1) / 2, (lo.2 + hi.2) / 2)
            let ext = (hi.0 - lo.0, hi.1 - lo.1, hi.2 - lo.2)
            let radius = max(ext.0, max(ext.1, ext.2)) / 2
            return ((c.0, c.1, c.2), radius)
        }
    }

    public let groups: [Group]

    public var totalTriangles: Int { groups.reduce(0) { $0 + $1.triangleCount } }

    /// Height of the whole body (y extent), for camera fitting.
    public var height: Float {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for g in groups {
            var i = 1
            while i < g.vertices.count {
                lo = min(lo, g.vertices[i]); hi = max(hi, g.vertices[i])
                i += 3
            }
        }
        return groups.isEmpty ? 0 : hi - lo
    }

    public enum ParseError: Error, Equatable {
        case missingResource
        case malformedFace(line: Int)
        case indexOutOfRange(line: Int)
    }

    /// Loads the body shipped in this package's resources.
    public static func bundled() throws -> BodyMesh {
        guard let url = Bundle.module.url(forResource: "body", withExtension: "obj") else {
            throw ParseError.missingResource
        }
        return try parse(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    /// Parses OBJ text: v / vn / f / o records; everything else is ignored.
    ///
    /// OBJ facts the code leans on: indices are GLOBAL and 1-based across the
    /// whole file (an object's faces may reference vertices defined under an
    /// earlier object); faces carry v//vn triplets because the exporter wrote
    /// normals and no UVs; negative (relative) indices are not produced by
    /// Blender's exporter and are rejected rather than mishandled.
    public static func parse(_ text: String) throws -> BodyMesh {
        var positions: [Float] = []   // global, flat xyz
        var normals: [Float] = []     // global, flat xyz

        var groups: [Group] = []
        var currentName = "body"
        // Per-group accumulation: OBJ global index pair -> local index.
        var localVerts: [Float] = []
        var localNorms: [Float] = []
        var localIndices: [UInt32] = []
        var remap: [UInt64: UInt32] = [:]

        func closeGroup() {
            guard !localIndices.isEmpty else { return }
            groups.append(Group(name: currentName, vertices: localVerts,
                                normals: localNorms, indices: localIndices))
            localVerts = []; localNorms = []; localIndices = []; remap = [:]
        }

        var lineNo = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            let line = rawLine.drop(while: { $0 == " " })
            guard let first = line.first else { continue }
            switch first {
            case "v":
                let parts = line.split(separator: " ")
                if parts[0] == "v", parts.count >= 4 {
                    positions.append(Float(parts[1]) ?? 0)
                    positions.append(Float(parts[2]) ?? 0)
                    positions.append(Float(parts[3]) ?? 0)
                } else if parts[0] == "vn", parts.count >= 4 {
                    normals.append(Float(parts[1]) ?? 0)
                    normals.append(Float(parts[2]) ?? 0)
                    normals.append(Float(parts[3]) ?? 0)
                }
            case "o":
                closeGroup()
                currentName = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            case "f":
                let corners = line.dropFirst(2).split(separator: " ")
                guard corners.count == 3 else { throw ParseError.malformedFace(line: lineNo) }
                for corner in corners {
                    let refs = corner.split(separator: "/", omittingEmptySubsequences: false)
                    guard let vi = Int(refs[0]), vi > 0,
                          let ni = refs.count >= 3 ? Int(refs[2]) : nil, ni > 0,
                          vi * 3 <= positions.count, ni * 3 <= normals.count else {
                        throw ParseError.indexOutOfRange(line: lineNo)
                    }
                    let key = UInt64(vi) << 32 | UInt64(ni)
                    if let local = remap[key] {
                        localIndices.append(local)
                    } else {
                        let local = UInt32(localVerts.count / 3)
                        remap[key] = local
                        let v = (vi - 1) * 3, n = (ni - 1) * 3
                        localVerts.append(contentsOf: positions[v..<v+3])
                        localNorms.append(contentsOf: normals[n..<n+3])
                        localIndices.append(local)
                    }
                }
            default:
                continue
            }
        }
        closeGroup()
        return BodyMesh(groups: groups)
    }
}
