import Foundation

struct Vec3: Equatable {
    var x: Double, y: Double, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, k: Double) -> Vec3 { Vec3(a.x * k, a.y * k, a.z * k) }
    func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: Vec3) -> Vec3 { Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { sqrt(dot(self)) }
    var normalized: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }
}

/// A triangle mesh as read from an STL file.
struct Mesh {
    var triangles: [(Vec3, Vec3, Vec3)] = []

    var bounds: (min: Vec3, max: Vec3)? {
        guard let first = triangles.first else { return nil }
        var lo = first.0, hi = first.0
        for t in triangles {
            for v in [t.0, t.1, t.2] {
                lo = Vec3(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z))
                hi = Vec3(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z))
            }
        }
        return (lo, hi)
    }
}

enum STLError: LocalizedError {
    case empty, malformed
    var errorDescription: String? {
        switch self {
        case .empty: return "The file has no triangles."
        case .malformed: return "This does not look like an STL file."
        }
    }
}

enum STLParser {
    /// Reads binary and ASCII STL.
    static func parse(_ data: Data) throws -> Mesh {
        if let mesh = parseBinary(data) { return try checked(mesh) }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1), text.contains("facet") || text.contains("vertex") {
            return try checked(parseASCII(text))
        }
        throw STLError.malformed
    }

    private static func checked(_ m: Mesh) throws -> Mesh {
        guard !m.triangles.isEmpty else { throw STLError.empty }
        return m
    }

    /// Binary layout: 80-byte header, UInt32 count, then 50 bytes per triangle (normal, three vertices, attribute).
    private static func parseBinary(_ data: Data) -> Mesh? {
        guard data.count >= 84 else { return nil }
        let count = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) }.littleEndian
        guard data.count == 84 + Int(count) * 50 else { return nil }
        var mesh = Mesh()
        mesh.triangles.reserveCapacity(Int(count))
        data.withUnsafeBytes { raw in
            func f(_ o: Int) -> Double { Double(Float(bitPattern: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian)) }
            for i in 0..<Int(count) {
                let o = 84 + i * 50 + 12
                mesh.triangles.append((Vec3(f(o), f(o + 4), f(o + 8)), Vec3(f(o + 12), f(o + 16), f(o + 20)), Vec3(f(o + 24), f(o + 28), f(o + 32))))
            }
        }
        return mesh
    }

    private static func parseASCII(_ text: String) -> Mesh {
        var mesh = Mesh()
        var pending: [Vec3] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.drop { $0 == " " || $0 == "\t" }
            guard t.hasPrefix("vertex") else { continue }
            let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 4, let x = Double(parts[1]), let y = Double(parts[2]), let z = Double(parts[3]) else { continue }
            pending.append(Vec3(x, y, z))
            if pending.count == 3 { mesh.triangles.append((pending[0], pending[1], pending[2])); pending = [] }
        }
        return mesh
    }

    /// Writes a binary STL (used by the tests and the sample part).
    static func binary(_ mesh: Mesh) -> Data {
        var data = Data(count: 80)
        var count = UInt32(mesh.triangles.count).littleEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        func put(_ v: Float) { var b = v.bitPattern.littleEndian; withUnsafeBytes(of: &b) { data.append(contentsOf: $0) } }
        for t in mesh.triangles {
            let n = (t.1 - t.0).cross(t.2 - t.0).normalized
            [n, t.0, t.1, t.2].forEach { put(Float($0.x)); put(Float($0.y)); put(Float($0.z)) }
            data.append(contentsOf: [0, 0])
        }
        return data
    }
}
