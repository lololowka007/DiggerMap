import SwiftUI

struct MapPanel: View {
    let route: RouteState
    let level: Int
    @ObservedObject var preferences: CustomizationStore
    var onMarker: (UUID) -> Void
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragOrigin: CGSize?
    @State private var zoomOrigin: CGFloat?
    @State private var geometry = CorridorGeometry(route: RouteState(), level: 0)
    private var signature: String {
        "\(level):\(route.corridorWidth):" + route.points.map { "\($0.x),\($0.y),\($0.level)" }.joined(separator: ";") +
            route.markers.filter { $0.kind == .deadEnd }.map { $0.id.uuidString }.joined()
    }

    var body: some View {
        GeometryReader { frame in
            let visible = route.points.filter { $0.level == level }
            let minX = visible.map(\.x).min() ?? 0, maxX = visible.map(\.x).max() ?? 0
            let minY = visible.map(\.y).min() ?? 0, maxY = visible.map(\.y).max() ?? 0
            let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2
            let extent = max(max(maxX - minX, maxY - minY), 10) + route.corridorWidth * 2
            let scale = min(frame.size.width, frame.size.height) * 0.72 / CGFloat(extent) * zoom
            let origin = CGPoint(x: frame.size.width / 2 + pan.width, y: frame.size.height / 2 + pan.height)
            let groups = Dictionary(grouping: route.markers.filter { $0.level == level }) {
                String(format: "%.1f,%.1f", $0.x, $0.y)
            }.values.compactMap { $0.last }
            let position: (Double, Double) -> CGPoint = { x, y in
                CGPoint(x: origin.x + CGFloat(x - centerX) * scale, y: origin.y - CGFloat(y - centerY) * scale)
            }
            Canvas { context, size in
                func polygon(_ points: [MapVector]) -> Path {
                    var path = Path()
                    for (index, point) in points.enumerated() {
                        if index == 0 { path.move(to: position(point.x, point.y)) }
                        else { path.addLine(to: position(point.x, point.y)) }
                    }
                    path.closeSubpath(); return path
                }
                if preferences.config.showGrid {
                    let spacing = max(14, scale)
                    var grid = Path()
                    for x in stride(from: origin.x.truncatingRemainder(dividingBy: spacing), through: size.width, by: spacing) {
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: origin.y.truncatingRemainder(dividingBy: spacing), through: size.height, by: spacing) {
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(preferences.color(\.grid).opacity(preferences.config.gridOpacity)), lineWidth: 1)
                }
                for footprint in geometry.footprints {
                    context.fill(polygon(footprint.corners), with: .color(preferences.color(\.walls).opacity(0.10)))
                }
                var walls = Path()
                for wall in geometry.walls {
                    walls.move(to: position(wall.a.x, wall.a.y)); walls.addLine(to: position(wall.b.x, wall.b.y))
                }
                context.stroke(walls, with: .color(preferences.color(\.walls)),
                               style: StrokeStyle(lineWidth: preferences.config.wallThickness, lineCap: .butt, lineJoin: .miter))
                for footprint in geometry.footprints {
                    let a = position(footprint.start.x, footprint.start.y), b = position(footprint.end.x, footprint.end.y)
                    if preferences.config.showRoute {
                        var center = Path(); center.move(to: a); center.addLine(to: b)
                        context.stroke(center, with: .color(preferences.color(\.route).opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    if preferences.config.showLengths {
                        context.draw(Text(String(format: "%.1f м", footprint.length))
                            .font(.system(size: preferences.config.labelSize, weight: .bold))
                            .foregroundColor(preferences.color(\.text)),
                                     at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 12))
                    }
                }
                for marker in route.markers where marker.level == level && !marker.passages.isEmpty {
                    let p = position(marker.x, marker.y)
                    if preferences.config.showPassages {
                        for passage in marker.passages {
                            let radians = (marker.heading + passage.angle) * .pi / 180
                            let length = min(max(30, scale * 2), 60)
                            let end = CGPoint(x: p.x + CGFloat(sin(radians)) * length, y: p.y - CGFloat(cos(radians)) * length)
                            var line = Path(); line.move(to: p); line.addLine(to: end)
                            for side in [-0.5, 0.5] {
                                line.move(to: end)
                                line.addLine(to: CGPoint(x: end.x - CGFloat(sin(radians + side)) * 9,
                                                        y: end.y + CGFloat(cos(radians + side)) * 9))
                            }
                            context.stroke(line, with: .color(preferences.color(\.position)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            if passage.elevation != 0 {
                                context.draw(Text(passage.elevation > 0 ? "выше" : "ниже").font(.system(size: 10))
                                    .foregroundColor(preferences.color(\.position)), at: CGPoint(x: end.x, y: end.y - 12))
                            }
                            if passage.label.contains("тупик") {
                                context.draw(Text("×").font(.system(size: 20, weight: .bold)).foregroundColor(preferences.color(\.position)), at: end)
                            }
                        }
                    }
                }
                for marker in groups {
                    let p = position(marker.x, marker.y)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                                 with: .color(preferences.color(\.background).opacity(0.95)))
                    context.draw(Text(Image(systemName: marker.photos.isEmpty ? marker.kind.symbol : "camera.fill"))
                        .font(.system(size: 14, weight: .bold)).foregroundColor(preferences.color(\.accent)), at: p)
                    if preferences.config.showLabels {
                        let label = Text(marker.title).font(.system(size: preferences.config.labelSize, weight: .semibold))
                            .foregroundColor(preferences.color(\.text)).lineLimit(2)
                        let maximumWidth = min(CGFloat(160), size.width * 0.48)
                        let measured = context.resolve(label).measure(in: CGSize(width: maximumWidth, height: .infinity))
                        let width = min(maximumWidth, measured.width)
                        let x = min(max(8, p.x + 14), size.width - width - 8)
                        let y = min(max(8, p.y - measured.height - 30), size.height - measured.height - 8)
                        let rect = CGRect(x: x, y: y, width: width, height: measured.height)
                        context.fill(Path(roundedRect: rect.insetBy(dx: -3, dy: -2), cornerRadius: 4),
                                     with: .color(preferences.color(\.background).opacity(0.85)))
                        context.draw(label, in: rect)
                    }
                }
                if let last = route.points.last, last.level == level {
                    let p = position(last.x, last.y), angle = route.heading * .pi / 180
                    var arrow = Path()
                    for (index, (a, radius)) in [(angle, 17.0), (angle - 2.4, 11.0), (angle + 2.4, 11.0)].enumerated() {
                        let point = CGPoint(x: p.x + CGFloat(sin(a) * radius), y: p.y - CGFloat(cos(a) * radius))
                        if index == 0 { arrow.move(to: point) } else { arrow.addLine(to: point) }
                    }
                    arrow.closeSubpath()
                    context.fill(arrow, with: .color(preferences.color(\.position)))
                    context.draw(Text("Вы здесь").font(.system(size: preferences.config.labelSize, weight: .bold))
                        .foregroundColor(preferences.color(\.position)), at: CGPoint(x: p.x, y: p.y + 28))
                }
            }
            .background(preferences.color(\.panel))
            .gesture(DragGesture().onChanged { value in
                if dragOrigin == nil { dragOrigin = pan }
                pan = CGSize(width: (dragOrigin?.width ?? 0) + value.translation.width, height: (dragOrigin?.height ?? 0) + value.translation.height)
            }.onEnded { _ in dragOrigin = nil })
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                if zoomOrigin == nil { zoomOrigin = zoom }
                zoom = min(max((zoomOrigin ?? 1) * value, 0.5), 8)
            }.onEnded { _ in zoomOrigin = nil })
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                let nearest = groups.min {
                    hypot(position($0.x, $0.y).x - tap.location.x, position($0.x, $0.y).y - tap.location.y) <
                    hypot(position($1.x, $1.y).x - tap.location.x, position($1.x, $1.y).y - tap.location.y)
                }
                if let nearest, hypot(position(nearest.x, nearest.y).x - tap.location.x, position(nearest.x, nearest.y).y - tap.location.y) < 30 {
                    onMarker(nearest.id)
                }
            })
            .overlay(alignment: .topLeading) {
                Text("ПЛАН · \(level == 0 ? "УРОВЕНЬ ВХОДА" : "УРОВЕНЬ \(level)")")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(preferences.color(\.accent))
                    .padding(12).background(preferences.color(\.background).opacity(0.9), in: Capsule()).padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 7) {
                    mapButton("minus") { zoom = max(0.5, zoom / 1.4) }
                    mapButton("plus") { zoom = min(8, zoom * 1.4) }
                    mapButton("scope") { zoom = 1; pan = .zero }
                }.padding(12)
            }
        }
        .task(id: signature) {
            let snapshot = route, selected = level
            let updated = await Task.detached(priority: .userInitiated) { CorridorGeometry(route: snapshot, level: selected) }.value
            if !Task.isCancelled { geometry = updated }
        }
    }
    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(preferences.color(\.text))
                .frame(width: 36, height: 36).background(preferences.color(\.background).opacity(0.9), in: RoundedRectangle(cornerRadius: 11))
        }
    }
}
