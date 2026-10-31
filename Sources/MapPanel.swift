import SwiftUI

struct MapPanel: View {
    let route: RouteState
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragOrigin: CGSize?
    @State private var zoomOrigin: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let visible = route.points.filter { $0.level == route.level }
            let minX = visible.map(\.x).min() ?? 0
            let maxX = visible.map(\.x).max() ?? 0
            let minY = visible.map(\.y).min() ?? 0
            let maxY = visible.map(\.y).max() ?? 0
            let centerX = (minX + maxX) / 2
            let centerY = (minY + maxY) / 2
            let extent = max(max(maxX - minX, maxY - minY), 10) + route.corridorWidth * 2
            let scale = min(geometry.size.width, geometry.size.height) * 0.72 / CGFloat(extent) * zoom
            let origin = CGPoint(x: geometry.size.width / 2 + pan.width, y: geometry.size.height / 2 + pan.height)
            Canvas { context, size in
                func position(_ point: RoutePoint) -> CGPoint {
                    CGPoint(x: origin.x + CGFloat(point.x - centerX) * scale,
                            y: origin.y - CGFloat(point.y - centerY) * scale)
                }
                let gridSpacing = max(14, scale)
                var grid = Path()
                for x in stride(from: origin.x.truncatingRemainder(dividingBy: gridSpacing), through: size.width, by: gridSpacing) {
                    grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: origin.y.truncatingRemainder(dividingBy: gridSpacing), through: size.height, by: gridSpacing) {
                    grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 1)
                if route.points.count > 1 {
                    for index in 1..<route.points.count {
                        let previous = route.points[index - 1]
                        let point = route.points[index]
                        guard previous.level == route.level, point.level == route.level else { continue }
                        let a = position(previous), b = position(point)
                        let dx = b.x - a.x, dy = b.y - a.y
                        let length = hypot(dx, dy)
                        guard length > 0.1 else { continue }
                        let offset = CGFloat(route.corridorWidth / 2) * scale
                        let nx = -dy / length * offset, ny = dx / length * offset
                        var fill = Path()
                        fill.move(to: CGPoint(x: a.x + nx, y: a.y + ny))
                        fill.addLine(to: CGPoint(x: b.x + nx, y: b.y + ny))
                        fill.addLine(to: CGPoint(x: b.x - nx, y: b.y - ny))
                        fill.addLine(to: CGPoint(x: a.x - nx, y: a.y - ny))
                        fill.closeSubpath()
                        context.fill(fill, with: .color(MapStyle.mint.opacity(0.12)))
                        for side: CGFloat in [-1, 1] {
                            var wall = Path()
                            wall.move(to: CGPoint(x: a.x + nx * side, y: a.y + ny * side))
                            wall.addLine(to: CGPoint(x: b.x + nx * side, y: b.y + ny * side))
                            context.stroke(wall, with: .color(MapStyle.mint.opacity(0.8)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                        var center = Path()
                        center.move(to: a); center.addLine(to: b)
                        context.stroke(center, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        context.draw(Text(String(format: "%.1f м", hypot(point.x - previous.x, point.y - previous.y)))
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.white),
                                     at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 12))
                    }
                }
                for point in visible {
                    guard let label = point.label else { continue }
                    let p = position(point)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(MapStyle.mint))
                    context.draw(Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(.white),
                                 at: CGPoint(x: p.x + 10, y: p.y - 14), anchor: .leading)
                }
                if let last = visible.last {
                    let p = position(last)
                    let radians = route.heading * .pi / 180
                    let tip = CGPoint(x: p.x + CGFloat(sin(radians)) * 17, y: p.y - CGFloat(cos(radians)) * 17)
                    let left = CGPoint(x: p.x + CGFloat(sin(radians - 2.4)) * 11, y: p.y - CGFloat(cos(radians - 2.4)) * 11)
                    let right = CGPoint(x: p.x + CGFloat(sin(radians + 2.4)) * 11, y: p.y - CGFloat(cos(radians + 2.4)) * 11)
                    var arrow = Path()
                    arrow.move(to: tip); arrow.addLine(to: left); arrow.addLine(to: right); arrow.closeSubpath()
                    context.fill(arrow, with: .color(.orange))
                    context.draw(Text("Вы здесь").font(.system(size: 11, weight: .bold)).foregroundColor(.orange),
                                 at: CGPoint(x: p.x, y: p.y + 25))
                }
            }
            .background(MapStyle.panel)
            .gesture(DragGesture().onChanged { value in
                if dragOrigin == nil { dragOrigin = pan }
                pan = CGSize(width: (dragOrigin?.width ?? 0) + value.translation.width, height: (dragOrigin?.height ?? 0) + value.translation.height)
            }.onEnded { _ in dragOrigin = nil })
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                if zoomOrigin == nil { zoomOrigin = zoom }
                zoom = min(max((zoomOrigin ?? 1) * value, 0.5), 8)
            }.onEnded { _ in zoomOrigin = nil })
            .overlay(alignment: .topLeading) {
                Text("ПЛАН · УРОВЕНЬ \(route.level)")
                    .font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(MapStyle.mint)
                    .padding(12).background(MapStyle.background.opacity(0.85), in: Capsule()).padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 7) {
                    mapButton("minus") { zoom = max(0.5, zoom / 1.4) }
                    mapButton("plus") { zoom = min(8, zoom * 1.4) }
                    mapButton("scope") { zoom = 1; pan = .zero }
                }.padding(12)
            }
        }
    }

    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(MapStyle.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 11))
        }
    }
}
