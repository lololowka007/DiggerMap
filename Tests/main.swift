import Foundation

var route = RouteState()
precondition(route.apply(CommandParser.parse("я прошёл около четырёх метров"),
                         source: "я прошёл около четырёх метров"))
precondition(abs(route.totalMeters - 4) < 0.001)
precondition(route.points.count == 2)

precondition(route.apply(CommandParser.parse("на 12 градусов налево"),
                         source: "на 12 градусов налево"))
precondition(abs(route.heading - 348) < 0.001)

precondition(route.apply(CommandParser.parse("прямо 12 шагов"),
                         source: "прямо 12 шагов"))
precondition(abs(route.totalMeters - 13) < 0.001)

var corridor = RouteState()
precondition(corridor.apply(CommandParser.parse("я прошёл по коридору четыре метра"),
                            source: "я прошёл по коридору четыре метра"))
precondition(abs(corridor.totalMeters - 4) < 0.001)
precondition(abs(corridor.corridorWidth - 2) < 0.001)

print("Voice route parsing: OK")

for phrase in ["я разворачиваюсь назад", "мне нужно развернуться назад", "разворот", "поворачиваюсь обратно"] {
    var turn = RouteState()
    precondition(turn.apply(CommandParser.parse(phrase), source: phrase), phrase)
    precondition(abs(turn.heading - 180) < 0.001, phrase)
    precondition(turn.markers.last?.kind == .uTurn, "U-turn must leave a marker")
}
var backward = RouteState()
_ = backward.apply([.move(5)], source: "test")
_ = backward.apply(CommandParser.parse("я возвращаюсь назад на два шага"), source: "test")
precondition(abs((backward.points.last?.y ?? 0) - 3.5) < 0.001)
precondition(backward.heading == 0, "Stepping back must keep facing direction")
var range = RouteState()
_ = range.apply(CommandParser.parse("назад на один или два шага"), source: "test")
precondition(abs((range.points.last?.y ?? 0) + 1.125) < 0.001, "A step range uses its midpoint")
var observation = RouteState()
let observationText = "передо мной проходы налево выше, прямо и направо ниже"
_ = observation.apply(CommandParser.parse(observationText), source: observationText)
precondition(observation.level == 0 && observation.heading == 0 && observation.totalMeters == 0)
precondition(observation.markers.last?.passages.count == 3)
precondition(observation.markers.last?.passages.first?.elevation == 1)
precondition(observation.markers.last?.passages.last?.elevation == -1)
precondition(observation.markers.last?.detail == observationText)
for (phrase, kind) in [("здесь тупик", MarkerKind.deadEnd), ("стрелка налево", .arrow),
                        ("надпись выход 12", .sign), ("фото ржавая дверь", .photo)] {
    var marker = RouteState()
    _ = marker.apply(CommandParser.parse(phrase), source: phrase)
    precondition(marker.markers.last?.kind == kind, phrase)
    precondition(marker.heading == 0, "Describing a sign must not turn the user")
}
var junction = RouteState()
_ = junction.apply([.move(8), .turn(90), .move(8), .turn(90), .move(8),
                   .turn(90), .move(12), .turn(90), .move(4), .turn(90), .move(16)], source: "crossing")
let union = CorridorGeometry(route: junction, level: 0)
precondition(!union.walls.isEmpty)
for wall in union.walls {
    let midpoint = (wall.a + wall.b) * 0.5
    precondition(!union.footprints.contains { $0.containsInterior(midpoint) }, "An intersection must not contain a wall")
}
let oldData = Data("{\"points\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"x\":0,\"y\":0,\"level\":0,\"label\":\"Вход\"}],\"heading\":0,\"level\":0,\"totalMeters\":0}".utf8)
let migrated = try JSONDecoder().decode(RouteState.self, from: oldData)
precondition(migrated.markers.first?.kind == .entrance)
let restored = try JSONDecoder().decode(RouteState.self, from: JSONEncoder().encode(observation))
precondition(restored.markers.last?.passages.count == 3 && restored.markers.last?.detail == observationText)
print("Turn / backstep / observations / markers / wall union / migration: OK")

let walking = CommandParser.parse("я иду прямо")
precondition(walking.contains { if case .walking(true) = $0 { return true }; return false })
var left100 = RouteState()
precondition(left100.apply(CommandParser.parse("я иду налево, сто метров."), source: "test"))
precondition(abs(left100.totalMeters - 100) < 0.001)
precondition(abs((left100.points.last?.x ?? 0) + 100) < 0.001)
precondition(abs(left100.points.last?.y ?? 0) < 0.001)

var segmenter = UtteranceSegmenter()
for _ in 0..<10 { precondition(segmenter.consume(Array(repeating: 0, count: 1600)).phrase == nil) }
var phrases = 0
for _ in 0..<12 {
    if segmenter.consume(Array(repeating: 0.1, count: 1600)).phrase != nil { phrases += 1 }
}
for _ in 0..<20 {
    if segmenter.consume(Array(repeating: 0, count: 1600)).phrase != nil { phrases += 1 }
}
precondition(phrases == 1, "One spoken phrase must produce exactly one command")

if CommandLine.arguments.count > 1 {
    let heard = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    var actual = RouteState()
    precondition(actual.apply(CommandParser.parse(heard), source: heard), "Real audio was not understood")
    precondition(abs(actual.totalMeters - 100) < 0.001, "Real audio distance must be 100m")
    precondition(abs((actual.points.last?.x ?? 0) + 100) < 0.001, "Real audio must go left")
    print("AUDIO → TEXT → MAP: OK")
}
