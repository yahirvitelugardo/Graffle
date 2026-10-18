import Foundation
import CoreGraphics

/// Layered ("Sugiyama-lite") layout for dependency graphs: dependents on top, what they depend on below.
enum GraphLayout {
    struct Edge: Hashable { var from: String; var to: String }

    struct Result {
        var origins: [String: CGPoint] = [:]
        var layerOf: [String: Int] = [:]
        /// Edges that close a cycle (they point "up"); drawn specially.
        var cycleEdges: Set<Edge> = []
        var size: CGSize = .zero
    }

    /// `edges` go from a dependent to its dependency. Each set in `bottom` gets a row of its own below everything else, in order.
    static func layered(nodes: [String], sizes: [String: CGSize], edges: [Edge], bottom: [Set<String>] = [],
                        maxWidth: CGFloat = 3200, hGap: CGFloat = 36, vGap: CGFloat = 90, margin: CGFloat = 60) -> Result {
        var result = Result()
        guard !nodes.isEmpty else { return result }
        let known = Set(nodes)
        var unique = Set<Edge>()
        for e in edges where e.from != e.to && known.contains(e.from) && known.contains(e.to) { unique.insert(e) }
        let edges = unique.sorted { $0.from != $1.from ? $0.from < $1.from : $0.to < $1.to }

        // 1. Break cycles: DFS, edges to a node on the current path are back edges.
        var out: [String: [String]] = [:]
        for e in edges { out[e.from, default: []].append(e.to) }
        var state: [String: Int] = [:]          // 1 = on path, 2 = done
        var back = Set<Edge>()
        func visit(_ n: String) {
            state[n] = 1
            for m in out[n] ?? [] {
                if state[m] == 1 { back.insert(Edge(from: n, to: m)) }
                else if state[m] == nil { visit(m) }
            }
            state[n] = 2
        }
        for n in nodes where state[n] == nil { visit(n) }
        result.cycleEdges = back
        let dag = edges.filter { !back.contains($0) }

        // 2. Longest-path layering: a node sits below everything that depends on it.
        var incoming: [String: [String]] = [:], outgoing: [String: [String]] = [:]
        for e in dag { incoming[e.to, default: []].append(e.from); outgoing[e.from, default: []].append(e.to) }
        var layer: [String: Int] = [:]
        func depth(_ n: String) -> Int {
            if let l = layer[n] { return l }
            let l = (incoming[n] ?? []).map { depth($0) + 1 }.max() ?? 0
            layer[n] = l
            return l
        }
        for n in nodes { _ = depth(n) }
        // Pull a node that nothing depends on down next to its lowest user, so roots don't float at the top.
        for n in nodes.reversed() where (incoming[n] ?? []).isEmpty {
            if let lowest = (outgoing[n] ?? []).compactMap({ layer[$0] }).min(), lowest > 1 { layer[n] = lowest - 1 }
        }
        var maxLayer = layer.values.max() ?? 0
        if !bottom.isEmpty {
            let fixed = bottom.reduce(into: Set<String>()) { $0.formUnion($1) }
            var base = (nodes.filter { !fixed.contains($0) }.compactMap { layer[$0] }.max() ?? -1) + 1
            for tier in bottom where nodes.contains(where: tier.contains) {
                for n in nodes where tier.contains(n) { layer[n] = base }
                base += 1
            }
            maxLayer = layer.values.max() ?? 0
        }
        result.layerOf = layer

        // 3. Order within layers: barycenter sweeps down and up, starting from input order.
        var rows: [[String]] = Array(repeating: [], count: maxLayer + 1)
        for n in nodes { rows[layer[n] ?? 0].append(n) }
        var neighbours: [String: [String]] = [:]
        for e in dag { neighbours[e.from, default: []].append(e.to); neighbours[e.to, default: []].append(e.from) }
        func position(_ row: [String]) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: row.enumerated().map { ($1, Double($0)) })
        }
        func reorder(_ i: Int, against j: Int) {
            guard rows.indices.contains(i), rows.indices.contains(j) else { return }
            let pos = position(rows[j])
            let current = position(rows[i])
            let keyed: [(String, Double)] = rows[i].map { n in
                let ps = (neighbours[n] ?? []).compactMap { pos[$0] }
                return (n, ps.isEmpty ? current[n]! : ps.reduce(0, +) / Double(ps.count))
            }
            rows[i] = keyed.enumerated().sorted { a, b in
                a.element.1 != b.element.1 ? a.element.1 < b.element.1 : a.offset < b.offset
            }.map { $0.element.0 }
        }
        for _ in 0..<4 {
            if maxLayer > 0 { for i in 1...maxLayer { reorder(i, against: i - 1) } }
            if maxLayer > 0 { for i in stride(from: maxLayer - 1, through: 0, by: -1) { reorder(i, against: i + 1) } }
        }

        // 4. Coordinates. A row wider than `maxWidth` wraps into several lines; each line is centered.
        func size(_ n: String) -> CGSize { sizes[n] ?? CGSize(width: 190, height: 62) }
        var lines: [[String]] = []
        for row in rows where !row.isEmpty {
            var line: [String] = [], width: CGFloat = 0
            for n in row {
                let w = size(n).width
                if !line.isEmpty && width + hGap + w > maxWidth { lines.append(line); line = []; width = 0 }
                width += (line.isEmpty ? 0 : hGap) + w
                line.append(n)
            }
            if !line.isEmpty { lines.append(line) }
        }
        func lineWidth(_ l: [String]) -> CGFloat { l.map { size($0).width }.reduce(0, +) + hGap * CGFloat(max(0, l.count - 1)) }
        let widest = lines.map(lineWidth).max() ?? 0
        var y = margin
        for line in lines {
            let h = line.map { size($0).height }.max() ?? 0
            var x = margin + (widest - lineWidth(line)) / 2
            for n in line {
                let s = size(n)
                result.origins[n] = CGPoint(x: x, y: y + (h - s.height) / 2)
                x += s.width + hGap
            }
            y += h + vGap
        }
        result.size = CGSize(width: widest + margin * 2, height: y - vGap + margin)
        return result
    }
}
