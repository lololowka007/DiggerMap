import Foundation

struct MapVector: Equatable {
    var x: Double
    var y: Double
    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y }
}

struct WallLine {
    var a: MapVector
    var b: MapVector
}

struct CorridorFootprint {
    var start: MapVector
    var end: MapVector
    var halfWidth: Double
    var length: Double { hypot(end.x - start.x, end.y - start.y) }
    var axis: MapVector { (end - start) * (1 / length) }
    var normal: MapVector { .init(x: -axis.y, y: axis.x) }
    var corners: [MapVector] {
        [start + normal * halfWidth, end + normal * halfWidth,
         end - normal * halfWidth, start - normal * halfWidth]
    }
    func containsInterior(_ point: MapVector) -> Bool {
        let relative = point - start
        return relative.dot(axis) > 0.00001 && relative.dot(axis) < length - 0.00001 &&
            abs(relative.dot(normal)) < halfWidth - 0.00001
    }

    /// Parameter interval of a line inside this oriented corridor rectangle.
    func coverage(of line: WallLine) -> (Double, Double)? {
        let offset = line.a - start
        let direction = line.b - line.a
        var lo = 0.0, hi = 1.0
        for (origin, delta, lower, upper) in [
            (offset.dot(axis), direction.dot(axis), 0.00001, length - 0.00001),
            (offset.dot(normal), direction.dot(normal), -halfWidth + 0.00001, halfWidth - 0.00001)
        ] {
            if abs(delta) < 0.0000001 {
                if origin < lower || origin > upper { return nil }
            } else {
                let a = (lower - origin) / delta, b = (upper - origin) / delta
                lo = max(lo, min(a, b)); hi = min(hi, max(a, b))
                if hi <= lo { return nil }
            }
        }
        return (lo, hi)
    }
}

struct CorridorGeometry {
    var footprints: [CorridorFootprint]
    var walls: [WallLine]

    init(route: RouteState, level: Int) {
        var shapes: [CorridorFootprint] = []
        if route.points.count > 1 {
            for index in 1..<route.points.count {
                let a = route.points[index - 1], b = route.points[index]
                guard a.level == level, b.level == level, hypot(b.x - a.x, b.y - a.y) > 0.001 else { continue }
                let shape = CorridorFootprint(start: .init(x: a.x, y: a.y), end: .init(x: b.x, y: b.y),
                                              halfWidth: route.corridorWidth / 2)
                // Retraced corridors have the same footprint. Keep one copy.
                if !shapes.contains(where: {
                    (hypot($0.start.x - shape.start.x, $0.start.y - shape.start.y) < 0.001 &&
                     hypot($0.end.x - shape.end.x, $0.end.y - shape.end.y) < 0.001) ||
                    (hypot($0.end.x - shape.start.x, $0.end.y - shape.start.y) < 0.001 &&
                     hypot($0.start.x - shape.end.x, $0.start.y - shape.end.y) < 0.001)
                }) { shapes.append(shape) }
            }
        }
        footprints = shapes
        var result: [WallLine] = []
        var seen = Set<String>()
        let entry = route.points.first.map { MapVector(x: $0.x, y: $0.y) }
        let current = route.points.last.map { MapVector(x: $0.x, y: $0.y) }
        for (index, shape) in shapes.enumerated() {
            let corners = shape.corners
            for edge in 0..<4 {
                // Leave the entrance and unexplored end open; a dead-end marker closes its end.
                let endPoint = edge == 1 ? shape.end : edge == 3 ? shape.start : nil
                if let endPoint {
                    let isEntry = entry.map { hypot(endPoint.x - $0.x, endPoint.y - $0.y) < 0.001 } ?? false
                    let isCurrent = current.map { hypot(endPoint.x - $0.x, endPoint.y - $0.y) < 0.001 } ?? false
                    let isDeadEnd = route.markers.contains { $0.level == level && $0.kind == .deadEnd && hypot($0.x - endPoint.x, $0.y - endPoint.y) < 0.1 }
                    if isEntry || (isCurrent && !isDeadEnd) { continue }
                }
                let line = WallLine(a: corners[edge], b: corners[(edge + 1) % 4])
                var intervals: [(Double, Double)] = [(0, 1)]
                for (otherIndex, other) in shapes.enumerated() where otherIndex != index {
                    guard let (cutA, cutB) = other.coverage(of: line) else { continue }
                    intervals = intervals.flatMap { lo, hi -> [(Double, Double)] in
                        if cutB <= lo || cutA >= hi { return [(lo, hi)] }
                        var remaining: [(Double, Double)] = []
                        if cutA > lo { remaining.append((lo, min(cutA, hi))) }
                        if cutB < hi { remaining.append((max(cutB, lo), hi)) }
                        return remaining
                    }
                }
                for (lo, hi) in intervals where hi - lo > 0.0001 {
                    let piece = WallLine(a: line.a + (line.b - line.a) * lo, b: line.a + (line.b - line.a) * hi)
                    let keyA = String(format: "%.3f,%.3f", piece.a.x, piece.a.y)
                    let keyB = String(format: "%.3f,%.3f", piece.b.x, piece.b.y)
                    let key = [keyA, keyB].sorted().joined(separator: ":")
                    if seen.insert(key).inserted { result.append(piece) }
                }
            }
        }
        walls = result
    }
}
